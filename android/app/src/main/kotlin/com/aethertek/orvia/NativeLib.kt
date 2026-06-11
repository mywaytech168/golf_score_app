package com.aethertek.orvia

import android.graphics.Bitmap

/**
 * JNI 橋接：golf_native.so 中的 C 加速函數。
 *
 * 所有方法均為 stateless，可在任意執行緒安全呼叫。
 * 初始化由 companion object 的 System.loadLibrary() 完成（類別第一次使用時執行）。
 */
object NativeLib {

    init {
        System.loadLibrary("golf_native")
    }

    /**
     * YUV420 → NV12，含旋轉 + nearest-neighbor 降解析度。
     *
     * 等價於 SkeletonOverlayRenderer.yuvToNv12WithRotation()。
     * 輸入 [yBytes]/[uBytes]/[vBytes] 為已從 Image.planes 複製出來的 ByteArray。
     * 結果寫入 [nv12]（in-place）。
     *
     * @param yStride       Y 平面的 rowStride（bytes）
     * @param uvStride      UV 平面的 rowStride
     * @param uvPixelStride UV 平面的 pixelStride（packed=1 / semi-planar=2）
     * @param codedW/H      MediaCodec 解碼的原始尺寸（coded space）
     * @param rotation      影片旋轉角度（0/90/180/270）
     * @param srcW/H        display 解析度（旋轉後的正確方向）
     * @param encW/H        輸出編碼尺寸（16 的倍數）
     * @param nv12          輸出緩衝區，長度 = encW × encH × 3/2
     */
    external fun yuvToNv12(
        yBytes: ByteArray, uBytes: ByteArray, vBytes: ByteArray,
        yStride: Int, uvStride: Int, uvPixelStride: Int,
        codedW: Int, codedH: Int,
        rotation: Int,
        srcW: Int, srcH: Int,
        encW: Int, encH: Int,
        nv12: ByteArray,
    )

    /**
     * YUV420 → NV21，含旋轉 + nearest-neighbor 降解析度。
     *
     * 和 [yuvToNv12] 完全相同，唯 UV 交錯順序相反：
     *   NV12: U0,V0,U1,V1,...  ← 用於 MediaCodec 編碼器輸入
     *   NV21: V0,U0,V1,U1,...  ← 用於 ML Kit InputImage.fromByteArray
     *
     * 使用場景：1080p 影片時先在 C 縮圖到 maxWidth（如 720p），
     * 再用 InputImage.fromByteArray(nv21, scaledW, scaledH, 0, IMAGE_FORMAT_NV21)
     * 傳給 ML Kit，使 GPU 搬運量從 6MB → 0.7MB。
     *
     * @param nv21  輸出緩衝區，長度 = encW × encH × 3/2
     */
    external fun yuvToNv21(
        yBytes: ByteArray, uBytes: ByteArray, vBytes: ByteArray,
        yStride: Int, uvStride: Int, uvPixelStride: Int,
        codedW: Int, codedH: Int,
        rotation: Int,
        srcW: Int, srcH: Int,
        encW: Int, encH: Int,
        nv21: ByteArray,
    )

    /**
     * YUV420 → NV12，clamp-to-edge，無旋轉。
     *
     * 等價於 TrajectoryOverlayRenderer.yuvFillNv12()。
     * 用於軌跡疊加 pass（輸入已是骨架影片，無需再旋轉）。
     */
    external fun yuvFillNv12(
        yBytes: ByteArray, uBytes: ByteArray, vBytes: ByteArray,
        yStride: Int, uvStride: Int, uvPixelStride: Int,
        videoW: Int, videoH: Int,
        encW: Int, encH: Int,
        nv12: ByteArray,
    )

    /**
     * 填入 YOLO 640×640 input tensor（YUV420 tile → RGB float 或 INT8）。
     *
     * 等價於 BallYoloDetector.detect() 內的 input 填充迴圈（640×640 = 40萬次/幀）。
     * 使用 GetDirectBufferAddress 直接寫入 ByteBuffer.allocateDirect()（零複製）。
     *
     * @param outputBuf  ByteBuffer.allocateDirect()（由 TFLite Interpreter 建立）
     * @param isFloat    true=FLOAT32 input，false=INT8 量化
     * @param inZeroPoint INT8 零點（float 模式下忽略）
     */
    external fun fillYoloInput(
        yData: ByteArray, yStride: Int,
        uData: ByteArray, uStride: Int, uPixelStride: Int,
        vData: ByteArray, vStride: Int, vPixelStride: Int,
        frameW: Int, frameH: Int,
        tileLeft: Int, tileTop: Int, tileW: Int, tileH: Int,
        inputSize: Int,
        outputBuf: java.nio.ByteBuffer,
        isFloat: Boolean,
        inZeroPoint: Int,
    )

    /**
     * 幀差 + 二值化 + 形態學開運算（3×3 erode → dilate）。
     *
     * 等價於 BallBlobExtractor.detectBlobs() step1+step2。
     * 同時消除每幀 4 × w×h 的 JVM ByteArray/BooleanArray 分配（~3.7MB GC/幀）。
     *
     * @param cur/prev   當前幀與前一幀的 Y 平面（stride-padded，w*h 可 < cur.size）
     * @param stride     Y 平面 rowStride（可 > w）
     * @param diffThresh |diff| >= diffThresh 才標記前景
     * @param diffOut    [w×h] 輸出：|cur-prev| 差值（供 BFS diffMean 計算）
     * @param openedOut  [w×h] 輸出：0/1（形態開運算結果，供 BFS 連通域）
     */
    external fun blobDiffAndMorphOpen(
        cur: ByteArray, prev: ByteArray,
        w: Int, h: Int, stride: Int,
        diffThresh: Int,
        diffOut: ByteArray,
        openedOut: ByteArray,
    )

    /**
     * NV21 → 旋轉 → nearest 縮放 → letterbox → RGBA（direct ByteBuffer），單趟完成。
     *
     * 即時骨架推論的轉換直通，取代「NV21→JPEG→Bitmap→旋轉→縮放→letterbox」
     * （~25ms + 每幀 5 個 Bitmap）→ ~2-3ms、零 JVM 配置。
     * 輸出餵 MediaPipe ByteBufferImageBuilder(IMAGE_FORMAT_RGBA)。
     *
     * @param nv21      來源（srcW×srcH×3/2）
     * @param rotation  0/90/180/270（90 = 順時針轉 90° 得直式）
     * @param lboxSize  輸出正方形邊長（256）
     * @param contentW/H, padX/Y  letterbox 內容區與黑邊（Kotlin 端先算好，
     *        與 MediaPipePoseHelper 座標逆還原參數一致）
     * @param out       direct ByteBuffer，容量 ≥ lboxSize² × 4
     */
    external fun nv21ToRgbaLetterbox(
        nv21: ByteArray,
        srcW: Int, srcH: Int,
        rotation: Int,
        lboxSize: Int,
        contentW: Int, contentH: Int,
        padX: Int, padY: Int,
        out: java.nio.ByteBuffer,
    )

    /**
     * 將 ARGB_8888 Bitmap overlay alpha-blend 合成進 NV12 緩衝區。
     *
     * 等價於 SkeletonOverlayRenderer.compositeSkeleton()
     *        / TrajectoryOverlayRenderer.compositeOverlay()。
     *
     * 使用 AndroidBitmap_lockPixels（直接指標存取），
     * 省去 Bitmap.getPixels() 的 JNI 呼叫開銷。
     * 骨架/軌跡為稀疏覆蓋（<1% 非透明像素），alpha < 16 快速跳過。
     *
     * @param bitmap ARGB_8888 格式的 overlay Bitmap
     * @param w/h    與 nv12 緩衝區相同的寬高（== encW/encH）
     * @param nv12   NV12 緩衝區（in-place 修改）
     */
    external fun compositeOverlay(
        bitmap: Bitmap,
        w: Int, h: Int,
        nv12: ByteArray,
    )
}
