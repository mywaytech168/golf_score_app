package com.aethertek.orvia

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import android.util.Log
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.core.Delegate
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarker
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarker.PoseLandmarkerOptions

/**
 * MediaPipe PoseLandmarker 離線影片分析（IMAGE 模式，同步推理）。
 *
 * 取代 `analyzeVideoNatively` 中的 ML Kit PoseDetector。
 *
 * 座標系：回傳值已逆 Letterbox，為原始直式影像的歸一化座標 [0,1]²。
 * CSV 格式：xNorm, yNorm, z, vis, xPx(=xNorm*dispW), yPx(=yNorm*dispH) — 與 PoseFrameModel 完全一致。
 */
class MediaPipeVideoAnalyzer(private val context: Context) {

    companion object {
        private const val TAG       = "MediaPipeVideoAnalyzer"
        private const val MODEL     = "flutter_assets/assets/models/pose_landmarker_lite.task"
        private const val LBOX_SIZE = 256
    }

    private var landmarker: PoseLandmarker? = null

    private data class LboxParams(
        val contentXNorm: Float,
        val contentYNorm: Float,
        val padXNorm:     Float,
        val padYNorm:     Float,
    )

    /**
     * 初始化 PoseLandmarker（IMAGE 模式）。
     * GPU → CPU fallback，失敗回傳 false。
     */
    fun setup(): Boolean {
        for (delegate in listOf(Delegate.GPU, Delegate.CPU)) {
            try {
                val base = BaseOptions.builder()
                    .setModelAssetPath(MODEL)
                    .setDelegate(delegate)
                    .build()
                val opts = PoseLandmarkerOptions.builder()
                    .setBaseOptions(base)
                    .setRunningMode(RunningMode.IMAGE)
                    .setNumPoses(1)
                    .setMinPoseDetectionConfidence(0.5f)
                    .setMinPosePresenceConfidence(0.5f)
                    .setMinTrackingConfidence(0.5f)
                    .build()
                landmarker = PoseLandmarker.createFromOptions(context, opts)
                Log.d(TAG, "ready ($delegate)")
                return true
            } catch (e: Throwable) {
                Log.w(TAG, "init failed ($delegate): $e")
            }
        }
        Log.e(TAG, "setup failed — GPU and CPU both unavailable")
        return false
    }

    /**
     * 偵測單幀骨架（同步）。
     *
     * @param portraitBitmap 已旋轉至直式的 Bitmap（呼叫端負責旋轉）。
     * @return 33 個地標的 Map 列表 {x, y, z, vis}（歸一化 [0,1]²），
     *         未偵測到人體時回傳空列表。
     */
    fun detect(portraitBitmap: Bitmap): List<Map<String, Any>> {
        val lm = landmarker ?: return emptyList()
        val (lboxBmp, params) = letterbox(portraitBitmap)
        return try {
            val mpImage = BitmapImageBuilder(lboxBmp).build()
            val result  = lm.detect(mpImage)
            val poses   = result?.landmarks() ?: return emptyList()
            if (poses.isEmpty()) return emptyList()
            poses[0].map { landmark ->
                val origX = if (params.contentXNorm > 0f)
                    ((landmark.x() - params.padXNorm) / params.contentXNorm).coerceIn(0f, 1f)
                else landmark.x()
                val origY = if (params.contentYNorm > 0f)
                    ((landmark.y() - params.padYNorm) / params.contentYNorm).coerceIn(0f, 1f)
                else landmark.y()
                mapOf<String, Any>(
                    "x"   to origX.toDouble(),
                    "y"   to origY.toDouble(),
                    "z"   to landmark.z().toDouble(),
                    "vis" to (landmark.visibility().orElse(0f).toDouble()),
                )
            }
        } catch (e: Exception) {
            Log.w(TAG, "detect failed: $e")
            emptyList()
        } finally {
            lboxBmp.recycle()
        }
    }

    fun close() {
        runCatching { landmarker?.close() }
        landmarker = null
    }

    // ── Letterbox：與 MediaPipePoseHelper 相同邏輯 ──────────────────────────────

    private fun letterbox(src: Bitmap): Pair<Bitmap, LboxParams> {
        val t      = LBOX_SIZE.toFloat()
        val scale  = minOf(t / src.width, t / src.height)
        val scaledW = (src.width  * scale).toInt().coerceAtLeast(1)
        val scaledH = (src.height * scale).toInt().coerceAtLeast(1)
        val padX   = (LBOX_SIZE - scaledW) / 2
        val padY   = (LBOX_SIZE - scaledH) / 2

        val output = Bitmap.createBitmap(LBOX_SIZE, LBOX_SIZE, Bitmap.Config.ARGB_8888)
        val canvas = android.graphics.Canvas(output)
        canvas.drawColor(Color.BLACK)
        val scaled = Bitmap.createScaledBitmap(src, scaledW, scaledH, true)
        canvas.drawBitmap(scaled, padX.toFloat(), padY.toFloat(), null)
        scaled.recycle()

        return Pair(output, LboxParams(
            contentXNorm = scaledW / t,
            contentYNorm = scaledH / t,
            padXNorm     = padX / t,
            padYNorm     = padY / t,
        ))
    }
}
