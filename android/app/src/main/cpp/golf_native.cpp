/**
 * golf_native.cpp
 *
 * C 加速層：替換所有 JVM 像素迴圈，避免 JIT 開銷與 array bounds-check 冗餘。
 * -O3 + -ffast-math 讓 clang 在 arm64-v8a 自動向量化（NEON SIMD），預期 5–15×。
 *
 * 函數列表：
 *   ── 渲染加速（SkeletonOverlay / TrajectoryOverlay）────────────────
 *   yuvToNv12        — YUV420→NV12，含旋轉+降解析度（SkeletonOverlay）
 *   yuvFillNv12      — YUV420→NV12，clamp-to-edge（TrajectoryOverlay）
 *   compositeOverlay — ARGB Bitmap alpha-blend 進 NV12（兩個 Renderer 共用）
 *
 *   ── 球偵測加速（BallYoloDetector / BallBlobExtractor）────────────
 *   fillYoloInput      — YUV420→RGB float/byte，填 YOLO 640×640 input tensor
 *   blobDiffAndMorphOpen — 幀差+二值化+形態開運算（erode→dilate），替代 BlobExtractor JVM 迴圈
 */

#include <jni.h>
#include <android/bitmap.h>
#include <android/log.h>
#include <cstdint>
#include <cstdlib>   // malloc / free
#include <cstring>   // memset
#include <algorithm>

#define TAG  "GolfNative"
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__)

// ─────────────────────────────────────────────────────────────────────────────
// 輔助：夾值（避免引入 <algorithm> 依賴，也讓編譯器更容易向量化）
// ─────────────────────────────────────────────────────────────────────────────

static inline int clamp(int v, int lo, int hi) {
    return v < lo ? lo : (v > hi ? hi : v);
}

extern "C" {

// ─────────────────────────────────────────────────────────────────────────────
// yuvToNv12
//
// 等價於 SkeletonOverlayRenderer.yuvToNv12WithRotation()。
// 相比 JVM 版本的改進：
//   1. C 整數運算，無 bounds-check overhead
//   2. clang -O3 對內層 Y 平面迴圈自動 NEON 向量化（當 rotation==0 時）
//   3. GetPrimitiveArrayCritical：in-place 鎖定，不複製
// ─────────────────────────────────────────────────────────────────────────────
JNIEXPORT void JNICALL
Java_com_aethertek_orvia_NativeLib_yuvToNv12(
        JNIEnv* env, jclass /*clazz*/,
        jbyteArray yArray, jbyteArray uArray, jbyteArray vArray,
        jint yStride, jint uvStride, jint uvPixelStride,
        jint codedW,  jint codedH,
        jint rotation,
        jint srcW,    jint srcH,
        jint encW,    jint encH,
        jbyteArray nv12Array)
{
    // 取長度（必須在 GetPrimitiveArrayCritical 之前，否則不能呼叫 JNI）
    const jsize ySize   = env->GetArrayLength(yArray);
    const jsize uSize   = env->GetArrayLength(uArray);
    const jsize vSize   = env->GetArrayLength(vArray);

    // 鎖定陣列（不複製；GC 被暫停直到 Release）
    auto* yB  = (uint8_t*)env->GetPrimitiveArrayCritical(yArray,   nullptr);
    auto* uB  = (uint8_t*)env->GetPrimitiveArrayCritical(uArray,   nullptr);
    auto* vB  = (uint8_t*)env->GetPrimitiveArrayCritical(vArray,   nullptr);
    auto* out = (uint8_t*)env->GetPrimitiveArrayCritical(nv12Array, nullptr);

    if (!yB || !uB || !vB || !out) {
        LOGE("yuvToNv12: GetPrimitiveArrayCritical failed");
        if (out) env->ReleasePrimitiveArrayCritical(nv12Array, out, JNI_ABORT);
        if (vB)  env->ReleasePrimitiveArrayCritical(vArray,    vB,  JNI_ABORT);
        if (uB)  env->ReleasePrimitiveArrayCritical(uArray,    uB,  JNI_ABORT);
        if (yB)  env->ReleasePrimitiveArrayCritical(yArray,    yB,  JNI_ABORT);
        return;
    }

    const int uvBase = encW * encH;

    for (int dy = 0; dy < encH; dy++) {
        // 輸出 dy → 來源 sy（nearest-neighbor，整數除法）
        const int sy = (int)((long long)dy * srcH / encH);

        for (int dx = 0; dx < encW; dx++) {
            const int sx = (int)((long long)dx * srcW / encW);

            // 旋轉映射：display (sx,sy) → coded (ci,cj)
            int ci, cj;
            switch (rotation) {
                case  90: ci = sy;          cj = codedH - 1 - sx; break;
                case 270: ci = codedW-1-sy; cj = sx;              break;
                case 180: ci = codedW-1-sx; cj = codedH-1-sy;    break;
                default:  ci = sx;          cj = sy;              break;
            }

            // ── Y 平面 ────────────────────────────────────────────
            const int yIdx = cj * yStride + ci;
            out[dy * encW + dx] = (yIdx >= 0 && yIdx < ySize) ? yB[yIdx] : 16;

            // ── UV 平面（每 2×2 block 處理一次）──────────────────
            if (((dy | dx) & 1) == 0) {
                const int uvOff = (cj >> 1) * uvStride + (ci >> 1) * uvPixelStride;
                const int base  = uvBase + (dy >> 1) * encW + dx;
                out[base]     = (uvOff >= 0 && uvOff < uSize) ? uB[uvOff] : 128;
                out[base + 1] = (uvOff >= 0 && uvOff < vSize) ? vB[uvOff] : 128;
            }
        }
    }

    // 釋放（逆序）：nv12 需 commit（0），其餘只讀（JNI_ABORT）
    env->ReleasePrimitiveArrayCritical(nv12Array, out, 0);
    env->ReleasePrimitiveArrayCritical(vArray,    vB,  JNI_ABORT);
    env->ReleasePrimitiveArrayCritical(uArray,    uB,  JNI_ABORT);
    env->ReleasePrimitiveArrayCritical(yArray,    yB,  JNI_ABORT);
}

// ─────────────────────────────────────────────────────────────────────────────
// yuvFillNv12
//
// 等價於 TrajectoryOverlayRenderer.yuvFillNv12()。
// 無旋轉、clamp-to-edge（encW ≈ videoW，不需降解析度），更簡單，
// 內層迴圈更容易被 clang 向量化。
// ─────────────────────────────────────────────────────────────────────────────
JNIEXPORT void JNICALL
Java_com_aethertek_orvia_NativeLib_yuvFillNv12(
        JNIEnv* env, jclass /*clazz*/,
        jbyteArray yArray, jbyteArray uArray, jbyteArray vArray,
        jint yStride, jint uvStride, jint uvPixelStride,
        jint videoW, jint videoH,
        jint encW,   jint encH,
        jbyteArray nv12Array)
{
    const jsize ySize   = env->GetArrayLength(yArray);
    const jsize uSize   = env->GetArrayLength(uArray);
    const jsize vSize   = env->GetArrayLength(vArray);
    const jsize nv12Sz  = env->GetArrayLength(nv12Array);

    auto* yB  = (uint8_t*)env->GetPrimitiveArrayCritical(yArray,   nullptr);
    auto* uB  = (uint8_t*)env->GetPrimitiveArrayCritical(uArray,   nullptr);
    auto* vB  = (uint8_t*)env->GetPrimitiveArrayCritical(vArray,   nullptr);
    auto* out = (uint8_t*)env->GetPrimitiveArrayCritical(nv12Array, nullptr);

    if (!yB || !uB || !vB || !out) {
        LOGE("yuvFillNv12: GetPrimitiveArrayCritical failed");
        if (out) env->ReleasePrimitiveArrayCritical(nv12Array, out, JNI_ABORT);
        if (vB)  env->ReleasePrimitiveArrayCritical(vArray,    vB,  JNI_ABORT);
        if (uB)  env->ReleasePrimitiveArrayCritical(uArray,    uB,  JNI_ABORT);
        if (yB)  env->ReleasePrimitiveArrayCritical(yArray,    yB,  JNI_ABORT);
        return;
    }

    const int uvBase = encW * encH;

    for (int dy = 0; dy < encH; dy++) {
        const int sy = (dy < videoH) ? dy : (videoH - 1);

        for (int dx = 0; dx < encW; dx++) {
            const int sx = (dx < videoW) ? dx : (videoW - 1);

            // ── Y ────────────────────────────────────────────────
            const int yIdx = sy * yStride + sx;
            out[dy * encW + dx] = (yIdx < ySize) ? yB[yIdx] : 16;

            // ── UV ───────────────────────────────────────────────
            if (((dy | dx) & 1) == 0) {
                const int uvOff = (sy >> 1) * uvStride + (sx >> 1) * uvPixelStride;
                const int base  = uvBase + (dy >> 1) * encW + dx;
                if (base + 1 < (int)nv12Sz) {
                    out[base]     = (uvOff < uSize) ? uB[uvOff] : 128;
                    out[base + 1] = (uvOff < vSize) ? vB[uvOff] : 128;
                }
            }
        }
    }

    env->ReleasePrimitiveArrayCritical(nv12Array, out, 0);
    env->ReleasePrimitiveArrayCritical(vArray,    vB,  JNI_ABORT);
    env->ReleasePrimitiveArrayCritical(uArray,    uB,  JNI_ABORT);
    env->ReleasePrimitiveArrayCritical(yArray,    yB,  JNI_ABORT);
}

// ─────────────────────────────────────────────────────────────────────────────
// compositeOverlay
//
// 等價於 SkeletonOverlayRenderer.compositeSkeleton()
//        / TrajectoryOverlayRenderer.compositeOverlay()（邏輯完全相同）。
//
// 改進：
//   - AndroidBitmap_lockPixels → 直接指標，省去 Bitmap.getPixels() JNI 開銷
//   - alpha < 16 early-exit 在 C 分支預測下更快
//   - alpha >= 240 fast-path：直接覆寫，不做混合乘法
// ─────────────────────────────────────────────────────────────────────────────
JNIEXPORT void JNICALL
Java_com_aethertek_orvia_NativeLib_compositeOverlay(
        JNIEnv* env, jclass /*clazz*/,
        jobject bitmap,
        jint w, jint h,
        jbyteArray nv12Array)
{
    // 取得 Bitmap 原始像素指標（ARGB_8888，不複製）
    AndroidBitmapInfo info{};
    if (AndroidBitmap_getInfo(env, bitmap, &info) != ANDROID_BITMAP_RESULT_SUCCESS) {
        LOGE("compositeOverlay: getInfo failed"); return;
    }
    void* rawPixels = nullptr;
    if (AndroidBitmap_lockPixels(env, bitmap, &rawPixels) != ANDROID_BITMAP_RESULT_SUCCESS) {
        LOGE("compositeOverlay: lockPixels failed"); return;
    }

    const jsize nv12Sz = env->GetArrayLength(nv12Array);
    auto* nv12 = (uint8_t*)env->GetPrimitiveArrayCritical(nv12Array, nullptr);
    if (!nv12) {
        AndroidBitmap_unlockPixels(env, bitmap);
        LOGE("compositeOverlay: GetPrimitiveArrayCritical failed"); return;
    }

    const int uvBase   = w * h;
    const int nv12Size = (int)nv12Sz;

    for (int j = 0; j < h; j++) {
        // info.stride 是 byte 寬度（含行末 padding），正確處理非 4×w 情況
        const auto* row = (const uint32_t*)((const uint8_t*)rawPixels + j * info.stride);

        for (int i = 0; i < w; i++) {
            const uint32_t argb = row[i];
            const int alpha = (int)(argb >> 24) & 0xFF;
            if (alpha < 16) continue;  // 透明像素，跳過（骨架/軌跡稀疏，<1% 像素）

            const int r = (int)(argb >> 16) & 0xFF;
            const int g = (int)(argb >>  8) & 0xFF;
            const int b = (int) argb        & 0xFF;

            // ── Y 平面（BT.601）─────────────────────────────────
            int yv = ((66 * r + 129 * g + 25 * b + 128) >> 8) + 16;
            yv = clamp(yv, 16, 235);

            const int yIdx = j * w + i;
            if (alpha >= 240) {
                nv12[yIdx] = (uint8_t)yv;
            } else {
                const int ex = nv12[yIdx];
                nv12[yIdx]  = (uint8_t)((ex * (255 - alpha) + yv * alpha + 127) / 255);
            }

            // ── UV 平面（每 2×2 block）──────────────────────────
            if (((j | i) & 1) == 0) {
                int u = ((-38 * r - 74  * g + 112 * b + 128) >> 8) + 128;
                int v = ((112 * r - 94  * g -  18 * b + 128) >> 8) + 128;
                u = clamp(u, 16, 240);
                v = clamp(v, 16, 240);

                const int base = uvBase + (j >> 1) * w + i;
                if (base + 1 < nv12Size) {
                    if (alpha >= 240) {
                        nv12[base]     = (uint8_t)u;
                        nv12[base + 1] = (uint8_t)v;
                    } else {
                        nv12[base]     = (uint8_t)((nv12[base]     * (255 - alpha) + u * alpha + 127) / 255);
                        nv12[base + 1] = (uint8_t)((nv12[base + 1] * (255 - alpha) + v * alpha + 127) / 255);
                    }
                }
            }
        }
    }

    env->ReleasePrimitiveArrayCritical(nv12Array, nv12, 0);
    AndroidBitmap_unlockPixels(env, bitmap);
}

// ─────────────────────────────────────────────────────────────────────────────
// yuvToNv21
//
// 等價於 yuvToNv12，但輸出 NV21（Android camera 標準格式）供 ML Kit 使用。
// NV12 vs NV21 的唯一差異：UV 交錯順序
//   NV12: [U0, V0, U1, V1, ...]   (ML Kit 渲染路徑)
//   NV21: [V0, U0, V1, U1, ...]   (ML Kit InputImage.fromByteArray NV21)
//
// 用途：在縮圖到 maxWidth 後（如 1080p→720p）傳給 ML Kit，減少 ML Kit
//       GPU 前處理的 memory bandwidth 消耗（6MB → 0.7MB 搬運量）。
// ─────────────────────────────────────────────────────────────────────────────
JNIEXPORT void JNICALL
Java_com_aethertek_orvia_NativeLib_yuvToNv21(
        JNIEnv* env, jclass /*clazz*/,
        jbyteArray yArray, jbyteArray uArray, jbyteArray vArray,
        jint yStride, jint uvStride, jint uvPixelStride,
        jint codedW,  jint codedH,
        jint rotation,
        jint srcW,    jint srcH,
        jint encW,    jint encH,
        jbyteArray nv21Array)
{
    const jsize ySize = env->GetArrayLength(yArray);
    const jsize uSize = env->GetArrayLength(uArray);
    const jsize vSize = env->GetArrayLength(vArray);

    auto* yB   = (uint8_t*)env->GetPrimitiveArrayCritical(yArray,   nullptr);
    auto* uB   = (uint8_t*)env->GetPrimitiveArrayCritical(uArray,   nullptr);
    auto* vB   = (uint8_t*)env->GetPrimitiveArrayCritical(vArray,   nullptr);
    auto* out  = (uint8_t*)env->GetPrimitiveArrayCritical(nv21Array, nullptr);

    if (!yB || !uB || !vB || !out) {
        LOGE("yuvToNv21: GetPrimitiveArrayCritical failed");
        if (out) env->ReleasePrimitiveArrayCritical(nv21Array, out, JNI_ABORT);
        if (vB)  env->ReleasePrimitiveArrayCritical(vArray,    vB,  JNI_ABORT);
        if (uB)  env->ReleasePrimitiveArrayCritical(uArray,    uB,  JNI_ABORT);
        if (yB)  env->ReleasePrimitiveArrayCritical(yArray,    yB,  JNI_ABORT);
        return;
    }

    const int uvBase = encW * encH;

    for (int dy = 0; dy < encH; dy++) {
        const int sy = (int)((long long)dy * srcH / encH);

        for (int dx = 0; dx < encW; dx++) {
            const int sx = (int)((long long)dx * srcW / encW);

            int ci, cj;
            switch (rotation) {
                case  90: ci = sy;          cj = codedH - 1 - sx; break;
                case 270: ci = codedW-1-sy; cj = sx;              break;
                case 180: ci = codedW-1-sx; cj = codedH-1-sy;    break;
                default:  ci = sx;          cj = sy;              break;
            }

            const int yIdx = cj * yStride + ci;
            out[dy * encW + dx] = (yIdx >= 0 && yIdx < ySize) ? yB[yIdx] : 16;

            if (((dy | dx) & 1) == 0) {
                const int uvOff = (cj >> 1) * uvStride + (ci >> 1) * uvPixelStride;
                const int base  = uvBase + (dy >> 1) * encW + dx;
                // NV21：V 在前，U 在後（和 NV12 相反）
                out[base]     = (uvOff >= 0 && uvOff < vSize) ? vB[uvOff] : 128;
                out[base + 1] = (uvOff >= 0 && uvOff < uSize) ? uB[uvOff] : 128;
            }
        }
    }

    env->ReleasePrimitiveArrayCritical(nv21Array, out, 0);
    env->ReleasePrimitiveArrayCritical(vArray,    vB,  JNI_ABORT);
    env->ReleasePrimitiveArrayCritical(uArray,    uB,  JNI_ABORT);
    env->ReleasePrimitiveArrayCritical(yArray,    yB,  JNI_ABORT);
}

// ─────────────────────────────────────────────────────────────────────────────
// fillYoloInput
//
// 等價於 BallYoloDetector.detect() 內的 input 填充迴圈（L172-197）。
// 將 YUV420 的 tile 區域轉換為 RGB float（或 INT8）並直接寫入
// ByteBuffer.allocateDirect()（透過 GetDirectBufferAddress，零複製）。
//
// 改進：
//   - 整數近似 BT.601（scaled by 1024）取代浮點乘法，clang 自動向量化
//   - GetDirectBufferAddress 避免 ByteBuffer.putFloat() 的 JNI 呼叫
//   - GetPrimitiveArrayCritical 避免 ByteArray 複製
// ─────────────────────────────────────────────────────────────────────────────
JNIEXPORT void JNICALL
Java_com_aethertek_orvia_NativeLib_fillYoloInput(
        JNIEnv* env, jclass /*clazz*/,
        jbyteArray yArray, jint yStride,
        jbyteArray uArray, jint uStride, jint uPixelStride,
        jbyteArray vArray, jint vStride, jint vPixelStride,
        jint frameW, jint frameH,
        jint tileLeft, jint tileTop, jint tileW, jint tileH,
        jint inputSize,
        jobject outputBuf,   // ByteBuffer.allocateDirect()
        jboolean isFloat,
        jint inZeroPoint)
{
    void* outPtr = env->GetDirectBufferAddress(outputBuf);
    if (!outPtr) { LOGE("fillYoloInput: non-direct ByteBuffer"); return; }

    const jsize ySize = env->GetArrayLength(yArray);
    const jsize uSize = env->GetArrayLength(uArray);
    const jsize vSize = env->GetArrayLength(vArray);

    auto* yB = (uint8_t*)env->GetPrimitiveArrayCritical(yArray, nullptr);
    auto* uB = (uint8_t*)env->GetPrimitiveArrayCritical(uArray, nullptr);
    auto* vB = (uint8_t*)env->GetPrimitiveArrayCritical(vArray, nullptr);

    if (!yB || !uB || !vB) {
        LOGE("fillYoloInput: GetPrimitiveArrayCritical failed");
        if (vB) env->ReleasePrimitiveArrayCritical(vArray, vB, JNI_ABORT);
        if (uB) env->ReleasePrimitiveArrayCritical(uArray, uB, JNI_ABORT);
        if (yB) env->ReleasePrimitiveArrayCritical(yArray, yB, JNI_ABORT);
        return;
    }

    // scaleX/Y：tile 座標 → frame 座標（inputSize=640 → tileW×tileH）
    const float scaleX = (float)tileW / (float)inputSize;
    const float scaleY = (float)tileH / (float)inputSize;

    if (isFloat) {
        auto* out = (float*)outPtr;
        for (int yi = 0; yi < inputSize; yi++) {
            const int srcY  = clamp(tileTop  + (int)(yi * scaleY), 0, frameH - 1);
            const int uvRow = srcY >> 1;
            for (int xi = 0; xi < inputSize; xi++) {
                const int srcX  = clamp(tileLeft + (int)(xi * scaleX), 0, frameW - 1);
                const int uvCol = srcX >> 1;

                const int yIdx = srcY * yStride + srcX;
                const int ui   = uvRow * uStride + uvCol * uPixelStride;
                const int vi   = uvRow * vStride + uvCol * vPixelStride;

                const int yv = (yIdx < ySize) ? (int)yB[yIdx] : 0;
                const int uv = (ui < uSize)   ? ((int)uB[ui] - 128) : 0;
                const int vv = (vi < vSize)   ? ((int)vB[vi] - 128) : 0;

                // BT.601 YUV→RGB（整數近似，scaled by 1024）
                // R = Y + 1.402*V  →  Y + (1435*V >> 10)
                // G = Y - 0.344*U - 0.714*V → Y - ((352*U + 731*V) >> 10)
                // B = Y + 1.772*U  →  Y + (1815*U >> 10)
                const int r = clamp(yv + ((1435 * vv) >> 10), 0, 255);
                const int g = clamp(yv - ((352  * uv + 731 * vv) >> 10), 0, 255);
                const int b = clamp(yv + ((1815 * uv) >> 10), 0, 255);

                const int outIdx = (yi * inputSize + xi) * 3;
                out[outIdx]     = r * (1.0f / 255.0f);
                out[outIdx + 1] = g * (1.0f / 255.0f);
                out[outIdx + 2] = b * (1.0f / 255.0f);
            }
        }
    } else {
        // INT8 量化（inZeroPoint 通常為 -128）
        auto* out = (int8_t*)outPtr;
        for (int yi = 0; yi < inputSize; yi++) {
            const int srcY  = clamp(tileTop  + (int)(yi * scaleY), 0, frameH - 1);
            const int uvRow = srcY >> 1;
            for (int xi = 0; xi < inputSize; xi++) {
                const int srcX  = clamp(tileLeft + (int)(xi * scaleX), 0, frameW - 1);
                const int uvCol = srcX >> 1;

                const int yIdx = srcY * yStride + srcX;
                const int ui   = uvRow * uStride + uvCol * uPixelStride;
                const int vi   = uvRow * vStride + uvCol * vPixelStride;

                const int yv = (yIdx < ySize) ? (int)yB[yIdx] : 0;
                const int uv = (ui < uSize)   ? ((int)uB[ui] - 128) : 0;
                const int vv = (vi < vSize)   ? ((int)vB[vi] - 128) : 0;

                const int r = clamp(yv + ((1435 * vv) >> 10), 0, 255);
                const int g = clamp(yv - ((352  * uv + 731 * vv) >> 10), 0, 255);
                const int b = clamp(yv + ((1815 * uv) >> 10), 0, 255);

                const int outIdx = (yi * inputSize + xi) * 3;
                out[outIdx]     = (int8_t)clamp(r + inZeroPoint, -128, 127);
                out[outIdx + 1] = (int8_t)clamp(g + inZeroPoint, -128, 127);
                out[outIdx + 2] = (int8_t)clamp(b + inZeroPoint, -128, 127);
            }
        }
    }

    env->ReleasePrimitiveArrayCritical(vArray, vB, JNI_ABORT);
    env->ReleasePrimitiveArrayCritical(uArray, uB, JNI_ABORT);
    env->ReleasePrimitiveArrayCritical(yArray, yB, JNI_ABORT);
}

// ─────────────────────────────────────────────────────────────────────────────
// blobDiffAndMorphOpen
//
// 等價於 BallBlobExtractor.detectBlobs() 的前兩步：
//   step1: 幀差 + 二值化（diff + binary）
//   step2: 形態學開運算 3×3（erode → dilate）
//
// 改進：
//   - 消除每幀 4 × w×h 的 ByteArray/BooleanArray 分配（消除 GC 壓力）
//   - C 整數迴圈比 JVM 快 5–10×
//   - morphOpen 侵蝕+膨脹共 2 × w×h×9 次比較 = 1660 萬次（720p），是最重的迴圈
//
// 輸出：
//   diffOut[j*w+i]   = |cur - prev|（unsigned byte，供 BFS diffMean 計算）
//   openedOut[j*w+i] = 0 或 1（形態開運算後，1=前景，供 BFS 連通域）
// ─────────────────────────────────────────────────────────────────────────────
JNIEXPORT void JNICALL
Java_com_aethertek_orvia_NativeLib_blobDiffAndMorphOpen(
        JNIEnv* env, jclass /*clazz*/,
        jbyteArray curArray, jbyteArray prevArray,
        jint w, jint h, jint stride,
        jint diffThresh,
        jbyteArray diffOut,    // output: |cur-prev| per pixel（w×h）
        jbyteArray openedOut)  // output: 0/1 after morphOpen（w×h）
{
    const int N = w * h;

    // ── 臨時緩衝區：在 critical section 外分配，避免 GC 互動問題 ──
    auto* binary = (uint8_t*)malloc(N);
    auto* eroded = (uint8_t*)malloc(N);
    if (!binary || !eroded) {
        LOGE("blobDiffAndMorphOpen: malloc failed");
        free(binary); free(eroded); return;
    }
    memset(eroded, 0, N);

    const jsize curSz  = env->GetArrayLength(curArray);
    const jsize prevSz = env->GetArrayLength(prevArray);

    auto* cur    = (uint8_t*)env->GetPrimitiveArrayCritical(curArray,  nullptr);
    auto* prev   = (uint8_t*)env->GetPrimitiveArrayCritical(prevArray, nullptr);
    auto* diffB  = (uint8_t*)env->GetPrimitiveArrayCritical(diffOut,   nullptr);
    auto* opened = (uint8_t*)env->GetPrimitiveArrayCritical(openedOut, nullptr);

    if (!cur || !prev || !diffB || !opened) {
        LOGE("blobDiffAndMorphOpen: GetPrimitiveArrayCritical failed");
        if (opened) env->ReleasePrimitiveArrayCritical(openedOut, opened, JNI_ABORT);
        if (diffB)  env->ReleasePrimitiveArrayCritical(diffOut,   diffB,  JNI_ABORT);
        if (prev)   env->ReleasePrimitiveArrayCritical(prevArray, prev,   JNI_ABORT);
        if (cur)    env->ReleasePrimitiveArrayCritical(curArray,  cur,    JNI_ABORT);
        free(binary); free(eroded); return;
    }

    // ── Step 1：幀差 + 二值化 ─────────────────────────────────────
    for (int j = 0; j < h; j++) {
        for (int i = 0; i < w; i++) {
            const int cIdx = j * stride + i;
            const int oIdx = j * w + i;
            const int d = (cIdx < (int)curSz && cIdx < (int)prevSz)
                ? (int)cur[cIdx] - (int)prev[cIdx]
                : 0;
            const int da = d < 0 ? -d : d;
            diffB[oIdx]  = (uint8_t)(da > 255 ? 255 : da);
            binary[oIdx] = (da >= diffThresh) ? 1 : 0;
        }
    }

    // ── Step 2a：3×3 侵蝕（erode）────────────────────────────────
    // 邊界（r=1 像素）保持 0（已 memset），只處理內部
    for (int j = 1; j < h - 1; j++) {
        for (int i = 1; i < w - 1; i++) {
            // 若 3×3 鄰域全為 1 → 侵蝕後也為 1
            if (binary[(j-1)*w+(i-1)] && binary[(j-1)*w+i] && binary[(j-1)*w+(i+1)] &&
                binary[ j   *w+(i-1)] && binary[ j   *w+i] && binary[ j   *w+(i+1)] &&
                binary[(j+1)*w+(i-1)] && binary[(j+1)*w+i] && binary[(j+1)*w+(i+1)]) {
                eroded[j * w + i] = 1;
            }
        }
    }

    // ── Step 2b：3×3 膨脹（dilate）= opened ────────────────────
    memset(opened, 0, N);
    for (int j = 1; j < h - 1; j++) {
        for (int i = 1; i < w - 1; i++) {
            // 若 3×3 鄰域任意一個侵蝕後為 1 → 膨脹後為 1
            if (eroded[(j-1)*w+(i-1)] || eroded[(j-1)*w+i] || eroded[(j-1)*w+(i+1)] ||
                eroded[ j   *w+(i-1)] || eroded[ j   *w+i] || eroded[ j   *w+(i+1)] ||
                eroded[(j+1)*w+(i-1)] || eroded[(j+1)*w+i] || eroded[(j+1)*w+(i+1)]) {
                opened[j * w + i] = 1;
            }
        }
    }

    env->ReleasePrimitiveArrayCritical(openedOut, opened, 0);
    env->ReleasePrimitiveArrayCritical(diffOut,   diffB,  0);
    env->ReleasePrimitiveArrayCritical(prevArray, prev,   JNI_ABORT);
    env->ReleasePrimitiveArrayCritical(curArray,  cur,    JNI_ABORT);

    free(eroded);
    free(binary);
}

// ─────────────────────────────────────────────────────────────────────────────
// nv21ToRgbaLetterbox
//
// 即時骨架推論的轉換直通：NV21 → 旋轉 → nearest 縮放 → letterbox → RGBA，
// 單趟完成，輸出寫入 direct ByteBuffer（餵 MediaPipe ByteBufferImageBuilder）。
// 取代舊路徑「NV21 → JPEG 編碼 → JPEG 解碼 → Bitmap 旋轉 → 縮放 → letterbox
// canvas」（~25ms + 每幀 5 個 Bitmap 配置）。
//
// 座標流程（與 MediaPipePoseHelper 的逆還原參數一致）：
//   output(ox,oy) ∈ [lboxSize]² → 扣 pad → 等比映射至 portrait(px,py)
//   → 依 rotation 映射回 NV21 來源 (sx,sy) → YUV→RGB
//
// rotation：相機 sensorOrientation（0/90/180/270），90 = 順時針轉 90° 得直式。
// pad 區域填黑（alpha 255）。
// ─────────────────────────────────────────────────────────────────────────────
JNIEXPORT void JNICALL
Java_com_aethertek_orvia_NativeLib_nv21ToRgbaLetterbox(
        JNIEnv* env, jclass /*clazz*/,
        jbyteArray nv21Array,
        jint srcW, jint srcH,
        jint rotation,
        jint lboxSize,
        jint contentW, jint contentH,
        jint padX, jint padY,
        jobject outBuf)
{
    uint8_t* out = (uint8_t*) env->GetDirectBufferAddress(outBuf);
    if (out == nullptr) return;
    const jlong cap = env->GetDirectBufferCapacity(outBuf);
    if (cap < (jlong) lboxSize * lboxSize * 4) return;

    // 預計算 content → portrait 的 nearest 映射表（必須在 Critical 區前 malloc）
    const int pw = (rotation == 90 || rotation == 270) ? srcH : srcW;
    const int ph = (rotation == 90 || rotation == 270) ? srcW : srcH;
    int* pxMap = (int*) malloc(sizeof(int) * (size_t) contentW);
    int* pyMap = (int*) malloc(sizeof(int) * (size_t) contentH);
    if (pxMap == nullptr || pyMap == nullptr) { free(pxMap); free(pyMap); return; }
    for (int i = 0; i < contentW; i++) {
        int v = (int)(((int64_t) i * pw) / contentW);
        pxMap[i] = v < pw ? v : pw - 1;
    }
    for (int i = 0; i < contentH; i++) {
        int v = (int)(((int64_t) i * ph) / contentH);
        pyMap[i] = v < ph ? v : ph - 1;
    }

    const uint8_t* nv21 =
        (const uint8_t*) env->GetPrimitiveArrayCritical(nv21Array, nullptr);
    if (nv21 == nullptr) { free(pxMap); free(pyMap); return; }

    const uint8_t* yPlane  = nv21;
    const uint8_t* uvPlane = nv21 + (size_t) srcW * srcH;

    // 整片填黑（R=G=B=0, A=255）；little-endian RGBA = 0xFF000000
    uint32_t* out32 = (uint32_t*) out;
    const int total = lboxSize * lboxSize;
    for (int i = 0; i < total; i++) out32[i] = 0xFF000000u;

    for (int cy = 0; cy < contentH; cy++) {
        const int py = pyMap[cy];
        uint8_t* row = out + ((size_t)(padY + cy) * lboxSize + padX) * 4;
        for (int cx = 0; cx < contentW; cx++) {
            const int px = pxMap[cx];
            int sx, sy;
            switch (rotation) {
                case 90:   // 順時針 90°：dst(x,y) = src(y, srcH-1-x)
                    sx = py;            sy = srcH - 1 - px; break;
                case 180:
                    sx = srcW - 1 - px; sy = srcH - 1 - py; break;
                case 270:  // 逆時針 90°：dst(x,y) = src(srcW-1-y, x)
                    sx = srcW - 1 - py; sy = px;            break;
                default:
                    sx = px;            sy = py;            break;
            }
            const int Y = yPlane[(size_t) sy * srcW + sx];
            const size_t uvOff = ((size_t)(sy >> 1) * srcW) + (size_t)(sx & ~1);
            const int V = uvPlane[uvOff]     - 128;   // NV21：V 在前
            const int U = uvPlane[uvOff + 1] - 128;

            // BT.601 full-range（與 YuvImage JPEG 路徑一致），定點 <<10
            int r = Y + ((1436 * V) >> 10);                    // 1.402
            int g = Y - ((352 * U + 731 * V) >> 10);           // 0.344, 0.714
            int b = Y + ((1815 * U) >> 10);                    // 1.772
            if (r < 0) r = 0; else if (r > 255) r = 255;
            if (g < 0) g = 0; else if (g > 255) g = 255;
            if (b < 0) b = 0; else if (b > 255) b = 255;

            row[0] = (uint8_t) r;
            row[1] = (uint8_t) g;
            row[2] = (uint8_t) b;
            row[3] = 255;
            row += 4;
        }
    }

    free(pxMap);
    free(pyMap);
    env->ReleasePrimitiveArrayCritical(nv21Array, (void*) nv21, JNI_ABORT);
}

} // extern "C"
