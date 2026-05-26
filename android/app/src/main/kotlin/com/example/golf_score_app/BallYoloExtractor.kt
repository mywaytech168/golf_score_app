package com.example.golf_score_app

import android.content.res.AssetManager
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.util.Log

/**
 * YOLOv8 球偵測提取器。
 *
 * 使用與 BallBlobExtractor 相同的 MediaExtractor + MediaCodec 影片解碼管線，
 * 但以 BallYoloDetector（TFLite YOLOv8n int8）取代像素差 BFS 偵測。
 *
 * 回傳格式與 BallBlobExtractor.extract() 完全相同，可無縫替換：
 * {
 *   "fps"    : Double,
 *   "width"  : Int,   // display-space
 *   "height" : Int,
 *   "frames" : List<Map> {
 *       "ptsUs" : Long,
 *       "blobs" : List<Map> {
 *           "cx"       : Int,     // display-space
 *           "cy"       : Int,
 *           "area"     : Int,     // bbox 面積（px²）
 *           "circ"     : Double,  // 固定 1.0（YOLO 偵測到球）
 *           "diffMean" : Double,  // confidence × 50.0（供 BallTracker 評分）
 *       }
 *   }
 * }
 *
 * 若模型載入失敗，extract() 回傳 null，呼叫端應 fallback 至 BallBlobExtractor。
 */
class BallYoloExtractor(assetManager: AssetManager) {

    companion object {
        private const val TAG = "BallYoloExtractor"
    }

    private val detector = BallYoloDetector(assetManager)

    /** true 代表模型已成功載入。 */
    fun tryLoadModel(): Boolean = detector.tryLoad()

    // ────────────────────────────────────────────────────────────

    fun extract(
        inputPath: String,
        onProgress: ((op: String, progress: Double, label: String, current: Int, total: Int) -> Unit)? = null,
    ): Map<String, Any>? {

        if (!detector.isLoaded) {
            Log.w(TAG, "YOLO model not loaded, skipping")
            return null
        }
        if (!java.io.File(inputPath).exists()) {
            Log.w(TAG, "File not found: $inputPath")
            return null
        }

        // ── MediaExtractor ──────────────────────────────────────
        val extractor = MediaExtractor()
        try { extractor.setDataSource(inputPath) }
        catch (e: Exception) { Log.e(TAG, "Cannot open: $e"); return null }

        var videoTrack   = -1
        var inputFormat: MediaFormat? = null
        for (i in 0 until extractor.trackCount) {
            val fmt = extractor.getTrackFormat(i)
            if ((fmt.getString(MediaFormat.KEY_MIME) ?: "").startsWith("video/")) {
                videoTrack = i; inputFormat = fmt; break
            }
        }
        if (videoTrack < 0 || inputFormat == null) {
            Log.e(TAG, "No video track"); extractor.release(); return null
        }
        extractor.selectTrack(videoTrack)

        val videoW    = inputFormat.getInteger(MediaFormat.KEY_WIDTH)
        val videoH    = inputFormat.getInteger(MediaFormat.KEY_HEIGHT)
        val videoMime = inputFormat.getString(MediaFormat.KEY_MIME) ?: "video/avc"
        val fps = runCatching {
            inputFormat.getInteger(MediaFormat.KEY_FRAME_RATE).toDouble()
        }.getOrElse { 30.0 }

        val (rotation, totalFrames) = android.media.MediaMetadataRetriever().use { mmr ->
            mmr.setDataSource(inputPath)
            val rot = mmr.extractMetadata(
                android.media.MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION
            )?.toIntOrNull() ?: 0
            val durationMs = mmr.extractMetadata(
                android.media.MediaMetadataRetriever.METADATA_KEY_DURATION
            )?.toLongOrNull() ?: 0L
            val frames = if (fps > 0) (durationMs * fps / 1000.0).toInt() else 0
            Pair(rot, frames)
        }

        val displayW = if (rotation == 90 || rotation == 270) videoH else videoW
        val displayH = if (rotation == 90 || rotation == 270) videoW else videoH

        Log.d(TAG, "Video: ${videoW}x${videoH} → ${displayW}x${displayH} fps=$fps rot=$rotation°")

        // ── Decoder ─────────────────────────────────────────────
        val decoder = try { MediaCodec.createDecoderByType(videoMime) }
        catch (e: Exception) { Log.e(TAG, "Cannot create decoder: $e"); extractor.release(); return null }
        decoder.configure(inputFormat, null, null, 0)
        decoder.start()

        val frameList  = mutableListOf<Map<String, Any>>()
        val bufInfo    = MediaCodec.BufferInfo()
        var inputEos   = false
        var frameCount = 0

        try {
            while (true) {
                // ── 餵輸入 ────────────────────────────────────
                if (!inputEos) {
                    val inIdx = decoder.dequeueInputBuffer(0L)
                    if (inIdx >= 0) {
                        val buf  = decoder.getInputBuffer(inIdx)!!
                        val size = extractor.readSampleData(buf, 0)
                        if (size < 0) {
                            decoder.queueInputBuffer(inIdx, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputEos = true
                        } else {
                            decoder.queueInputBuffer(inIdx, 0, size, extractor.sampleTime, 0)
                            extractor.advance()
                        }
                    }
                }

                // ── 取輸出 ────────────────────────────────────
                val outIdx = decoder.dequeueOutputBuffer(bufInfo, 10_000L)
                if (outIdx == MediaCodec.INFO_TRY_AGAIN_LATER)    continue
                if (outIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) continue
                if (outIdx < 0)                                      continue

                val image = runCatching { decoder.getOutputImage(outIdx) }.getOrNull()
                if (image == null) {
                    decoder.releaseOutputBuffer(outIdx, false)
                    if ((bufInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) break
                    continue
                }

                try {
                    val pts    = bufInfo.presentationTimeUs
                    val yPlane = image.planes[0]
                    val yBuf   = yPlane.buffer
                    val yRaw   = ByteArray(videoH * yPlane.rowStride)
                    yBuf.get(yRaw)

                    // YOLO 推論（在 coded-space 執行，無需 prevFrame）
                    val codedDets = detector.detect(yRaw, yPlane.rowStride, videoW, videoH)

                    // 轉換到 display-space
                    val blobs: List<Map<String, Any>> = if (rotation == 0) {
                        codedDets.map { d ->
                            mapOf(
                                "cx"       to d[0].toInt(),
                                "cy"       to d[1].toInt(),
                                "area"     to maxOf(1, (d[2] * d[3]).toInt()),
                                "circ"     to 1.0,
                                "diffMean" to (d[4] * 50.0).toDouble(),
                            )
                        }
                    } else {
                        codedDets.map { d ->
                            val (dx, dy) = codedToDisplay(d[0].toInt(), d[1].toInt(), videoW, videoH, rotation)
                            mapOf(
                                "cx"       to dx,
                                "cy"       to dy,
                                "area"     to maxOf(1, (d[2] * d[3]).toInt()),
                                "circ"     to 1.0,
                                "diffMean" to (d[4] * 50.0).toDouble(),
                            )
                        }
                    }

                    frameList.add(mapOf("ptsUs" to pts, "blobs" to blobs))
                    frameCount++

                    if (frameCount % 10 == 0 && totalFrames > 0) {
                        val prog = (frameCount.toDouble() / totalFrames).coerceIn(0.0, 0.95)
                        onProgress?.invoke(
                            "extractBlobs", prog,
                            "球追蹤分析中 ${(prog * 100).toInt()}% [YOLOv8]",
                            frameCount, totalFrames,
                        )
                    }

                } finally {
                    image.close()
                    decoder.releaseOutputBuffer(outIdx, false)
                }

                if ((bufInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) break
            }

        } catch (e: Exception) {
            Log.e(TAG, "YOLO extract failed: $e", e)
        } finally {
            runCatching { decoder.stop(); decoder.release() }
            runCatching { extractor.release() }
        }

        val totalDets = frameList.sumOf { (it["blobs"] as List<*>).size }
        Log.d(TAG, "YOLO done: ${frameList.size} frames, $totalDets detections")
        onProgress?.invoke("extractBlobs", 1.0, "球追蹤分析完成 [YOLOv8]", frameCount, frameCount)

        return mapOf(
            "fps"    to fps,
            "width"  to displayW,
            "height" to displayH,
            "frames" to frameList,
        )
    }

    // ────────────────────────────────────────────────────────────

    private fun codedToDisplay(
        cx: Int, cy: Int, w: Int, h: Int, rotation: Int,
    ): Pair<Int, Int> = when (rotation) {
        90  -> Pair(h - 1 - cy, cx)
        270 -> Pair(cy, w - 1 - cx)
        180 -> Pair(w - 1 - cx, h - 1 - cy)
        else -> Pair(cx, cy)
    }
}
