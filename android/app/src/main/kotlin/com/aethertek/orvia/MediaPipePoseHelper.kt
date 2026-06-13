package com.aethertek.orvia

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.Matrix
import android.util.Log
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.framework.image.ByteBufferImageBuilder
import com.google.mediapipe.framework.image.MPImage
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
        // 對外可見：CameraRecorderChannel 計算 letterbox 參數 / 配置 RGBA buffer 用
        const val LBOX_SIZE   = 256
        // 分段 timing 每 N 幀彙整輸出一次
        private const val TIMING_EVERY = 30
    }

    // ── Letterbox 參數（LIVE_STREAM 為單執行緒順序處理，@Volatile 足夠保護）
    private data class LboxParams(
        val contentXNorm: Float,   // scaledW / LBOX_SIZE
        val contentYNorm: Float,   // scaledH / LBOX_SIZE
        val padXNorm:     Float,   // padX    / LBOX_SIZE
        val padYNorm:     Float,   // padY    / LBOX_SIZE
    )

    // ★ 保存推論輸入的生命週期：Bitmap 路徑（舊）或 RGBA direct buffer 路徑（新），
    // 都要等 MediaPipe callback 返回後才能 recycle / 歸還 pool
    private data class PendingFrames(
        val lboxBitmap:    Bitmap? = null,   // Bitmap 路徑：letterbox 後的 256×256
        val portraitBitmap: Bitmap? = null,  // Bitmap 路徑：呼叫端傳入的原始 bitmap
        val rgbaBuf:       java.nio.ByteBuffer? = null,  // RGBA 路徑：direct buffer（歸還 pool）
        val lboxParams:    LboxParams,
        val submitAtMs:    Long,       // detectAsync 送出時刻（量測推論耗時）
    )

    @Volatile private var poseLandmarker: PoseLandmarker? = null
    @Volatile private var isSetup = false
    private val pendingFrames = mutableMapOf<Long, PendingFrames>()  // timestamp -> both bitmaps

    // ── 分段 timing 統計（每 TIMING_EVERY 幀彙整輸出一次）──────────────────────
    @Volatile private var delegateName = "?"
    private var statConvertMs  = 0L   // 呼叫端 NV21→Bitmap 轉換段（noteConvertMs 餵入）
    private var statLboxMs     = 0L   // letterbox 段
    private var statInferMs    = 0L   // detectAsync 送出 → callback 返回
    private var statCount      = 0
    private var statWindowStart = 0L
    private var pendingConvertMs = 0L

    /** 呼叫端回報本幀「YUV→Bitmap 轉換段」耗時（ms），與推論統計一起輸出。 */
    fun noteConvertMs(ms: Long) { pendingConvertMs = ms }

    // ── RGBA direct buffer pool（2 幀 in-flight + 1 備用）────────────────────
    private val rgbaPool = ArrayDeque<java.nio.ByteBuffer>()

    /** 取得 256×256×4 RGBA direct buffer（呼叫端以 JNI 填入後交 detectAsyncRgba）。 */
    fun acquireRgbaBuffer(): java.nio.ByteBuffer {
        synchronized(rgbaPool) {
            if (rgbaPool.isNotEmpty()) return rgbaPool.removeFirst().also { it.clear() }
        }
        return java.nio.ByteBuffer.allocateDirect(LBOX_SIZE * LBOX_SIZE * 4)
            .order(java.nio.ByteOrder.nativeOrder())
    }

    /** 歸還 buffer（呼叫端在「未送進 detectAsyncRgba」的失敗路徑使用）。 */
    fun releaseRgbaBuffer(buf: java.nio.ByteBuffer) {
        synchronized(rgbaPool) { if (rgbaPool.size < 3) rgbaPool.addLast(buf) }
    }

    /**
     * RGBA direct buffer 推論路徑（取代 Bitmap 路徑，零 JVM 配置）。
     *
     * [buf] 已由 NativeLib.nv21ToRgbaLetterbox 填好（含旋轉/縮放/黑邊）；
     * [contentW]/[contentH]/[padX]/[padY] 與 JNI 填入時使用的參數一致，
     * 用於座標逆還原。gate 釋放契約與 detectAsync 相同：任何路徑恰好
     * 觸發一次 onFrameDone，buffer 在 dispatch finally / 失敗路徑歸還 pool。
     */
    fun detectAsyncRgba(
        buf: java.nio.ByteBuffer,
        contentW: Int, contentH: Int, padX: Int, padY: Int,
        timestampMs: Long,
    ) {
        if (!isSetup || poseLandmarker == null) {
            releaseRgbaBuffer(buf)
            onFrameDone()
            return
        }
        try {
            val t = LBOX_SIZE.toFloat()
            val params = LboxParams(
                contentXNorm = contentW / t,
                contentYNorm = contentH / t,
                padXNorm     = padX / t,
                padYNorm     = padY / t,
            )
            synchronized(pendingFrames) {
                pendingFrames.remove(timestampMs)?.let { old ->
                    old.lboxBitmap?.recycle()
                    old.portraitBitmap?.recycle()
                    old.rgbaBuf?.let(::releaseRgbaBuffer)
                }
                pendingFrames[timestampMs] = PendingFrames(
                    rgbaBuf    = buf,
                    lboxParams = params,
                    submitAtMs = android.os.SystemClock.uptimeMillis(),
                )
            }
            statConvertMs += pendingConvertMs

            buf.rewind()
            val mpImage = ByteBufferImageBuilder(
                buf, LBOX_SIZE, LBOX_SIZE, MPImage.IMAGE_FORMAT_RGBA,
            ).build()
            poseLandmarker?.detectAsync(mpImage, timestampMs)
        } catch (e: Exception) {
            synchronized(pendingFrames) {
                val removed = pendingFrames.remove(timestampMs)
                if (removed?.rgbaBuf != null) {
                    releaseRgbaBuffer(removed.rgbaBuf)
                } else {
                    releaseRgbaBuffer(buf)
                }
            }
            Log.w(TAG, "detectAsyncRgba: " + e)
            onFrameDone()
        }
    }

    // ── 初始化 ────────────────────────────────────────────────────────────────

    fun setup() {
        try {
            build(Delegate.GPU)
            delegateName = "GPU"
            Log.i(TAG, "PoseLandmarker ready (GPU)")
        } catch (e: Throwable) {
            Log.w(TAG, "GPU → CPU fallback: $e")
            try {
                build(Delegate.CPU)
                delegateName = "CPU"
                Log.w(TAG, "PoseLandmarker ready (CPU) ← GPU init 失敗，推論速度受限")
            } catch (e2: Throwable) {
                Log.e(TAG, "PoseLandmarker init failed: $e2"); return
            }
        }
        isSetup = true
    }

    private fun build(delegate: Delegate) {
        // ★ 用 setModelAssetBuffer 讀 bytes，而非 setModelAssetPath（後者走 openFd 要求 asset
        //   未壓縮；AAB 打包時 noCompress glob 不一定傳遞到 bundle → Play 安裝版 .task 被壓縮 →
        //   openFd 失敗 → 骨架全無，但 debug 正常）。讀 bytes 不管壓縮，與球 YOLO 載入方式一致。
        val base = BaseOptions.builder()
            .setModelAssetBuffer(loadModelBuffer(MODEL_LITE))
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
            // ★ 推論錯誤時 result listener 不會被呼叫 → 必須在此釋放 gate，
            //   否則 isAnalyzing 永久卡 true（骨架停止更新）。重複釋放無害（boolean gate）。
            .setErrorListener { err ->
                Log.w(TAG, "pose error: $err")
                onFrameDone()
            }
            .build()
        poseLandmarker = PoseLandmarker.createFromOptions(context, opts)
    }

    /** 從 assets 讀模型成 direct ByteBuffer（繞開 openFd 對未壓縮 asset 的依賴）。 */
    private fun loadModelBuffer(assetPath: String): java.nio.ByteBuffer {
        val bytes = context.assets.open(assetPath).use { it.readBytes() }
        return java.nio.ByteBuffer.allocateDirect(bytes.size).apply {
            put(bytes)
            rewind()
        }
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
        // ★ gate 釋放契約：本函式被呼叫後，無論成功與否都必須恰好觸發一次 onFrameDone
        //  （成功 → dispatch 的 finally；失敗 → 各 early-return / catch 自行呼叫），
        //   否則呼叫端 isAnalyzing 永久卡 true → 骨架永遠不更新（死鎖）。
        if (portraitBitmap.isRecycled) {
            Log.w(TAG, "skip detectAsync: portraitBitmap already recycled")
            onFrameDone()
            return
        }

        if (!isSetup) {
            portraitBitmap.recycle()
            onFrameDone()
            return
        }

        val lm = poseLandmarker
        if (lm == null) {
            portraitBitmap.recycle()
            onFrameDone()
            return
        }

        try {
            // ★ 清理太舊的 bitmap（GPU 偶爾卡頓，保留 3000ms 避免 callback 回來時 frames 已被清掉）
            synchronized(pendingFrames) {
                val cutoffTime = timestampMs - 3000L
                pendingFrames.entries.removeIf { (ts, frames) ->
                    if (ts < cutoffTime) {
                        frames.lboxBitmap?.recycle()
                        frames.portraitBitmap?.recycle()
                        frames.rgbaBuf?.let(::releaseRgbaBuffer)
                        true
                    } else {
                        false
                    }
                }
            }

            val lboxStart = android.os.SystemClock.uptimeMillis()
            val (lboxBmp, params) = letterbox(portraitBitmap)
            val lboxMs = android.os.SystemClock.uptimeMillis() - lboxStart

            synchronized(pendingFrames) {
                pendingFrames.remove(timestampMs)?.let { old ->
                    old.lboxBitmap?.recycle()
                    old.portraitBitmap?.recycle()
                    old.rgbaBuf?.let(::releaseRgbaBuffer)
                }
                pendingFrames[timestampMs] = PendingFrames(
                    lboxBitmap     = lboxBmp,
                    portraitBitmap = portraitBitmap,
                    lboxParams     = params,
                    submitAtMs     = android.os.SystemClock.uptimeMillis(),
                )
            }
            statLboxMs    += lboxMs            // 與 dispatch 同為序列處理，無競爭
            statConvertMs += pendingConvertMs  // 呼叫端轉換段（同 renderThread 寫入）

            val mpImage = BitmapImageBuilder(lboxBmp).build()
            lm.detectAsync(mpImage, timestampMs)

        } catch (e: Exception) {
            portraitBitmap.recycle()
            synchronized(pendingFrames) {
                pendingFrames.remove(timestampMs)?.let { frames ->
                    frames.lboxBitmap?.recycle()
                }
            }
            Log.w(TAG, "detectAsync: $e")
            // ★ 幀未送進 MediaPipe（或送出失敗）→ result/error listener 都不會回呼，
            //   必須在此釋放 gate（detectAsync 對外吞例外，呼叫端不會走到自己的 catch）。
            onFrameDone()
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
            val removed: PendingFrames?
            synchronized(pendingFrames) {
                removed = pendingFrames.remove(ts)
                removed?.let {
                    it.lboxBitmap?.recycle()
                    it.portraitBitmap?.recycle()
                    it.rgbaBuf?.let(::releaseRgbaBuffer)
                }
            }
            // ── 分段 timing 彙整：每 TIMING_EVERY 幀輸出一次 ────────────────
            removed?.let {
                val now = android.os.SystemClock.uptimeMillis()
                statInferMs += now - it.submitAtMs
                statCount++
                if (statWindowStart == 0L) statWindowStart = now
                if (statCount >= TIMING_EVERY) {
                    val winSec = (now - statWindowStart) / 1000.0
                    val fps = if (winSec > 0) statCount / winSec else 0.0
                    Log.i(TAG, "TIMING delegate=$delegateName n=$statCount " +
                        "convert=${statConvertMs / statCount}ms " +
                        "lbox=${statLboxMs / statCount}ms " +
                        "infer=${statInferMs / statCount}ms " +
                        "effFps=${"%.1f".format(fps)}")
                    statConvertMs = 0; statLboxMs = 0; statInferMs = 0
                    statCount = 0; statWindowStart = now
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
                frames.lboxBitmap?.recycle()
                frames.portraitBitmap?.recycle()
                frames.rgbaBuf?.let(::releaseRgbaBuffer)
            }
            pendingFrames.clear()
        }
        runCatching { poseLandmarker?.close() }
        poseLandmarker = null
    }
}
