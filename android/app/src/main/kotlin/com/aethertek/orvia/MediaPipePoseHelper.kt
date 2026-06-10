package com.aethertek.orvia

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.Matrix
import android.util.Log
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.core.Delegate
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarker
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarker.PoseLandmarkerOptions
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarkerResult

/**
 * Camera2 分析幀 → Letterboxing → MediaPipe PoseLandmarker (LIVE_STREAM) → 逆座標還原
 *
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │  Letterboxing 流程                                                       │
 * │                                                                          │
 * │  輸入：已旋轉至直式的 Bitmap（呼叫端負責旋轉）                             │
 * │  例：270×480（16:9 直式，從 480×270 橫式旋轉而來）                        │
 * │                                                                          │
 * │  Letterbox → 256×256 正方形                                              │
 * │    scale = min(256/270, 256/480) = 0.533                                 │
 * │    content = 144×256，padX=56px 兩側，padY=0                              │
 * │    ┌──────────────────────────────┐  256                                 │
 * │    │  black  │  person  │  black  │                                      │
 * │    │  56px   │  144px   │  56px   │                                      │
 * │    └──────────────────────────────┘                                      │
 * │                                                                          │
 * │  MediaPipe 回傳 (x,y) ∈ [0,1]²（相對 256×256 正方形）                    │
 * │                                                                          │
 * │  逆還原 → 原始直式歸一化座標：                                             │
 * │    origX = (x - padXNorm) / contentXNorm                                 │
 * │    origY = (y - padYNorm) / contentYNorm                                 │
 * │  ∈ [0,1]²（相對直式影像，可直接用於直式預覽 Canvas）                      │
 * └─────────────────────────────────────────────────────────────────────────┘
 */
class MediaPipePoseHelper(
    private val context: Context,
    private val onResult: (List<Map<String, Any>>, Long) -> Unit,
    private val onFrameDone: () -> Unit = {},
) {
    companion object {
        private const val TAG         = "MediaPipePoseHelper"
        private const val MODEL_LITE  = "flutter_assets/assets/models/pose_landmarker_lite.task"
        // Letterbox 目標正方形邊長，與 pose_landmarker_lite 模型輸入一致（256×256）
        private const val LBOX_SIZE   = 256
    }

    // ── Letterbox 參數（LIVE_STREAM 為單執行緒順序處理，@Volatile 足夠保護）
    private data class LboxParams(
        val contentXNorm: Float,   // scaledW / LBOX_SIZE
        val contentYNorm: Float,   // scaledH / LBOX_SIZE
        val padXNorm:     Float,   // padX    / LBOX_SIZE
        val padYNorm:     Float,   // padY    / LBOX_SIZE
    )

    // ★ 保存兩種 Bitmap：letterboxed（MediaPipe 輸入）+ original（生命週期管理）
    // 都要等 MediaPipe callback 返回後才能 recycle
    private data class PendingFrames(
        val lboxBitmap:    Bitmap,     // letterbox 後的 256×256 bitmap
        val portraitBitmap: Bitmap,    // 呼叫端傳入的原始 bitmap（來自 CameraRecorderChannel）
        val lboxParams:    LboxParams,
    )

    @Volatile private var poseLandmarker: PoseLandmarker? = null
    @Volatile private var isSetup = false
    private val pendingFrames = mutableMapOf<Long, PendingFrames>()  // timestamp -> both bitmaps

    // ── 初始化 ────────────────────────────────────────────────────────────────

    fun setup() {
        try {
            build(Delegate.GPU)
            Log.d(TAG, "PoseLandmarker ready (GPU)")
        } catch (e: Throwable) {
            Log.w(TAG, "GPU → CPU fallback: $e")
            try {
                build(Delegate.CPU)
                Log.d(TAG, "PoseLandmarker ready (CPU)")
            } catch (e2: Throwable) {
                Log.e(TAG, "PoseLandmarker init failed: $e2"); return
            }
        }
        isSetup = true
    }

    private fun build(delegate: Delegate) {
        val base = BaseOptions.builder()
            .setModelAssetPath(MODEL_LITE)
            .setDelegate(delegate)
            .build()
        val opts = PoseLandmarkerOptions.builder()
            .setBaseOptions(base)
            .setRunningMode(RunningMode.LIVE_STREAM)
            .setNumPoses(1)
            .setMinPoseDetectionConfidence(0.5f)
            .setMinPosePresenceConfidence(0.5f)
            .setMinTrackingConfidence(0.5f)
            .setResultListener { result, _ -> dispatch(result) }
            .setErrorListener { err -> Log.w(TAG, "pose error: $err") }
            .build()
        poseLandmarker = PoseLandmarker.createFromOptions(context, opts)
    }

    // ── 送幀 ──────────────────────────────────────────────────────────────────

    /**
     * 送入**已旋轉至直式**的 Bitmap 給 MediaPipe。
     *
     * ★ 呼叫端（CameraRecorderChannel）負責：
     *   1. 縮放至分析解析度（保持 16:9 橫式比例）
     *   2. 用 Matrix.postRotate 旋轉至直式（+前置鏡頭水平翻轉）
     *   3. 傳入此函式
     *
     * 函式內部：
     *   - 加黑邊 Letterbox 至 LBOX_SIZE×LBOX_SIZE
     *   - 不使用 ImageProcessingOptions（避免 SDK 版本差異導致座標歧義）
     *   - 紀錄 padding 比例，回呼時逆還原至直式歸一化座標
     */
    fun detectAsync(portraitBitmap: Bitmap, timestampMs: Long) {
        if (portraitBitmap.isRecycled) {
            Log.w(TAG, "skip detectAsync: portraitBitmap already recycled")
            return
        }

        if (!isSetup) {
            portraitBitmap.recycle()
            return
        }

        val lm = poseLandmarker
        if (lm == null) {
            portraitBitmap.recycle()
            return
        }

        try {
            // ★ 清理太舊的 bitmap（GPU 偶爾卡頓，保留 3000ms 避免 callback 回來時 frames 已被清掉）
            synchronized(pendingFrames) {
                val cutoffTime = timestampMs - 3000L
                pendingFrames.entries.removeIf { (ts, frames) ->
                    if (ts < cutoffTime) {
                        frames.lboxBitmap.recycle()
                        frames.portraitBitmap.recycle()
                        true
                    } else {
                        false
                    }
                }
            }

            val (lboxBmp, params) = letterbox(portraitBitmap)

            synchronized(pendingFrames) {
                pendingFrames.remove(timestampMs)?.let { old ->
                    old.lboxBitmap.recycle()
                    old.portraitBitmap.recycle()
                }
                pendingFrames[timestampMs] = PendingFrames(
                    lboxBitmap     = lboxBmp,
                    portraitBitmap = portraitBitmap,
                    lboxParams     = params,
                )
            }

            val mpImage = BitmapImageBuilder(lboxBmp).build()
            lm.detectAsync(mpImage, timestampMs)

        } catch (e: Exception) {
            portraitBitmap.recycle()
            synchronized(pendingFrames) {
                pendingFrames.remove(timestampMs)?.let { frames ->
                    frames.lboxBitmap.recycle()
                }
            }
            Log.w(TAG, "detectAsync: $e")
        }
    }

    // ── Letterbox ─────────────────────────────────────────────────────────────

    private fun letterbox(src: Bitmap): Pair<Bitmap, LboxParams> {
        val t      = LBOX_SIZE.toFloat()
        val scale  = minOf(t / src.width, t / src.height)
        val scaledW = (src.width  * scale).toInt().coerceAtLeast(1)
        val scaledH = (src.height * scale).toInt().coerceAtLeast(1)
        val padX   = ((LBOX_SIZE - scaledW) / 2)
        val padY   = ((LBOX_SIZE - scaledH) / 2)

        val output = Bitmap.createBitmap(LBOX_SIZE, LBOX_SIZE, Bitmap.Config.ARGB_8888)
        val canvas = android.graphics.Canvas(output)
        canvas.drawColor(Color.BLACK)
        val scaled = Bitmap.createScaledBitmap(src, scaledW, scaledH, true)
        canvas.drawBitmap(scaled, padX.toFloat(), padY.toFloat(), null)
        scaled.recycle()

        val params = LboxParams(
            contentXNorm = scaledW / t,
            contentYNorm = scaledH / t,
            padXNorm     = padX    / t,
            padYNorm     = padY    / t,
        )
        return Pair(output, params)
    }

    // ── 結果回呼 ──────────────────────────────────────────────────────────────

    private fun dispatch(result: PoseLandmarkerResult) {
        val ts = result.timestampMs()
        try {
            val frames = synchronized(pendingFrames) { pendingFrames[ts] }

            if (frames == null) {
                Log.w(TAG, "dispatch: missing pending frame for ts=$ts, skip result")
                return
            }

            val poses = result.landmarks()

            if (poses.isEmpty()) {
                // 單幀沒偵測到不清空，保留上一幀骨架避免閃爍
                Log.v(TAG, "pose empty ts=$ts")
                return
            }

            val landmarks = poses[0].map { lm ->
                val x = ((lm.x() - frames.lboxParams.padXNorm) / frames.lboxParams.contentXNorm)
                    .coerceIn(0f, 1f)
                val y = ((lm.y() - frames.lboxParams.padYNorm) / frames.lboxParams.contentYNorm)
                    .coerceIn(0f, 1f)
                mapOf<String, Any>(
                    "x"   to x.toDouble(),
                    "y"   to y.toDouble(),
                    "z"   to lm.z().toDouble(),
                    "vis" to (lm.visibility().orElse(0f).toDouble()),
                )
            }
            onResult(landmarks, ts)
        } finally {
            // ★ 清理本幀對應的兩個 bitmap（lboxBitmap + portraitBitmap）
            synchronized(pendingFrames) {
                val frames = pendingFrames.remove(ts)
                if (frames != null) {
                    frames.lboxBitmap.recycle()
                    frames.portraitBitmap.recycle()
                }
            }
            // ★ 通知呼叫端推論完成（含 pose 為空的情況），讓 isAnalyzing gate 放行下一幀
            onFrameDone()
        }
    }

    fun close() {
        isSetup = false
        synchronized(pendingFrames) {
            pendingFrames.values.forEach { frames ->
                frames.lboxBitmap.recycle()
                frames.portraitBitmap.recycle()
            }
            pendingFrames.clear()
        }
        runCatching { poseLandmarker?.close() }
        poseLandmarker = null
    }
}
