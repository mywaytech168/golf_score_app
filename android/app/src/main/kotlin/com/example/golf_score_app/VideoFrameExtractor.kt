package com.example.golf_score_app

import android.graphics.Bitmap
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.util.Log
import java.io.Closeable
import java.nio.ByteBuffer

/**
 * 使用 MediaExtractor + MediaCodec 直接解碼視頻幀為 RGB Bitmap。
 *
 * 設計為 Closeable，跨多幀重用 MediaExtractor 和 MediaCodec，
 * 避免每幀重建解碼器的 20-50ms 固定開銷。
 *
 * 使用方式：
 *   val extractor = VideoFrameExtractor()
 *   extractor.use { ext ->
 *       frames.forEach { ms -> ext.extractFrameRgb(path, ms, 720) }
 *   }
 */
class VideoFrameExtractor : Closeable {
    private val logTag = "VideoFrameExtractor"

    private var mediaExtractor: MediaExtractor? = null
    private var decoder: MediaCodec? = null
    private var currentPath: String? = null
    private var videoWidth: Int = 0
    private var videoHeight: Int = 0

    /**
     * 從視頻指定時間戳提取 RGB Bitmap。
     * 相同路徑重複呼叫時，複用 MediaExtractor + MediaCodec（無 setup 開銷）。
     */
    fun extractFrameRgb(
        videoPath: String,
        timeMs: Long,
        maxWidth: Int = 720
    ): Bitmap? {
        return try {
            if (currentPath != videoPath) openVideo(videoPath)
            val ext = mediaExtractor ?: return null
            val dec = decoder ?: return null

            ext.seekTo(timeMs * 1000L, MediaExtractor.SEEK_TO_CLOSEST_SYNC)

            val scaledHeight = if (videoWidth > 0)
                (maxWidth.toDouble() / videoWidth * videoHeight).toInt()
            else maxWidth * 16 / 9

            decodeFrame(ext, dec, videoWidth, videoHeight, maxWidth, scaledHeight)
        } catch (e: Exception) {
            Log.e(logTag, "提取幀失敗 ${timeMs}ms: ${e.message}")
            // 解碼器可能已損壞，下次呼叫時重新開啟
            closeDecoder()
            null
        }
    }

    private fun openVideo(videoPath: String) {
        closeDecoder()

        val ext = MediaExtractor()
        ext.setDataSource(videoPath)

        var videoTrack = -1
        var format: MediaFormat? = null
        for (i in 0 until ext.trackCount) {
            val f = ext.getTrackFormat(i)
            if (f.getString(MediaFormat.KEY_MIME)?.startsWith("video/") == true) {
                videoTrack = i; format = f; break
            }
        }
        if (videoTrack < 0 || format == null) {
            Log.e(logTag, "找不到視頻軌道: $videoPath")
            ext.release(); return
        }

        ext.selectTrack(videoTrack)
        videoWidth  = format.getInteger(MediaFormat.KEY_WIDTH)
        videoHeight = format.getInteger(MediaFormat.KEY_HEIGHT)

        val mime = format.getString(MediaFormat.KEY_MIME) ?: "video/avc"
        val dec = MediaCodec.createDecoderByType(mime)
        dec.configure(format, null, null, 0)
        dec.start()

        mediaExtractor = ext
        decoder = dec
        currentPath = videoPath
        Log.d(logTag, "VideoFrameExtractor 開啟: $videoPath (${videoWidth}x${videoHeight})")
    }

    private fun closeDecoder() {
        runCatching { decoder?.stop(); decoder?.release() }
        runCatching { mediaExtractor?.release() }
        decoder = null; mediaExtractor = null; currentPath = null
    }

    override fun close() = closeDecoder()

    // ── 解碼單幀（重用已 start 的 decoder）──────────────────────

    private fun decodeFrame(
        extractor: MediaExtractor,
        decoder: MediaCodec,
        videoWidth: Int,
        videoHeight: Int,
        scaledWidth: Int,
        scaledHeight: Int
    ): Bitmap? {
        val bufferInfo = MediaCodec.BufferInfo()
        val timeoutUs  = 5_000L
        var outputBitmap: Bitmap? = null
        var attempts = 0

        // 提交輸入
        val inIdx = decoder.dequeueInputBuffer(timeoutUs)
        if (inIdx >= 0) {
            val inputBuf = decoder.getInputBuffer(inIdx)!!
            val size = extractor.readSampleData(inputBuf, 0)
            if (size > 0) {
                decoder.queueInputBuffer(inIdx, 0, size, extractor.sampleTime, 0)
            } else {
                decoder.queueInputBuffer(inIdx, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
            }
        }

        // 讀取輸出
        while (attempts < 100 && outputBitmap == null) {
            val outIdx = decoder.dequeueOutputBuffer(bufferInfo, timeoutUs)
            when {
                outIdx >= 0 -> {
                    val outBuf = decoder.getOutputBuffer(outIdx)
                    if (outBuf != null && bufferInfo.size > 0) {
                        outputBitmap = nv12ToRgbBitmap(outBuf, videoWidth, videoHeight, scaledWidth, scaledHeight)
                    }
                    decoder.releaseOutputBuffer(outIdx, false)
                    break
                }
                outIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> { /* 繼續 */ }
                else -> { /* TRY_AGAIN_LATER 繼續等 */ }
            }
            attempts++
        }

        // flush decoder 以便下次 seek 後能正常解碼
        decoder.flush()

        return outputBitmap
    }

    private fun nv12ToRgbBitmap(
        nv12Buffer: ByteBuffer,
        width: Int, height: Int,
        scaledWidth: Int, scaledHeight: Int
    ): Bitmap {
        val rgbArray = IntArray(scaledWidth * scaledHeight)
        val data = ByteArray(nv12Buffer.remaining())
        nv12Buffer.get(data)
        val ySize = width * height
        var rgbIndex = 0
        for (y in 0 until scaledHeight) {
            for (x in 0 until scaledWidth) {
                val srcX = (x.toDouble() / scaledWidth * width).toInt().coerceIn(0, width - 1)
                val srcY = (y.toDouble() / scaledHeight * height).toInt().coerceIn(0, height - 1)
                val yIndex = srcY * width + srcX
                val uvX = srcX / 2; val uvY = srcY / 2
                val uvIndex = ySize + uvY * width + uvX * 2
                if (yIndex >= data.size || uvIndex + 1 >= data.size) {
                    rgbArray[rgbIndex++] = 0xFF000000.toInt(); continue
                }
                val yVal = (data[yIndex].toInt() and 0xFF) - 16
                // NV12: U first, V second
                val uVal = (data[uvIndex].toInt() and 0xFF) - 128
                val vVal = (data[uvIndex + 1].toInt() and 0xFF) - 128
                val r = ((298 * yVal + 409 * vVal) / 256).coerceIn(0, 255)
                val g = ((298 * yVal - 100 * uVal - 208 * vVal) / 256).coerceIn(0, 255)
                val b = ((298 * yVal + 516 * uVal) / 256).coerceIn(0, 255)
                rgbArray[rgbIndex++] = (0xFF shl 24) or (r shl 16) or (g shl 8) or b
            }
        }
        val bitmap = Bitmap.createBitmap(scaledWidth, scaledHeight, Bitmap.Config.ARGB_8888)
        bitmap.setPixels(rgbArray, 0, scaledWidth, 0, 0, scaledWidth, scaledHeight)
        return bitmap
    }
}
