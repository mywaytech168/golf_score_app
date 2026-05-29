package com.example.golf_score_app

import android.content.Context
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.media.MediaMuxer
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.ByteBuffer

class VideoTrimmer(private val context: Context) {

    companion object {
        private const val TAG = "VideoTrimmer"
        private const val BUFFER_SIZE = 2 * 1024 * 1024 // 2 MB
    }

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "trim") {
            result.notImplemented()
            return
        }

        val args = call.arguments as? Map<*, *>
        val srcPath = args?.get("srcPath") as? String
        val dstPath = args?.get("dstPath") as? String
        val startMs = (args?.get("startMs") as? Number)?.toLong() ?: 0L
        val endMs = (args?.get("endMs") as? Number)?.toLong()

        if (srcPath.isNullOrBlank() || dstPath.isNullOrBlank() || endMs == null) {
            result.error("invalid_args", "缺少 srcPath / dstPath / startMs / endMs", null)
            return
        }

        val srcFile = File(srcPath)
        if (!srcFile.exists()) {
            result.error("file_not_found", "來源影片不存在: $srcPath", null)
            return
        }

        Thread {
            try {
                val baseTimeMs = trimWithMuxer(srcPath, dstPath, startMs, endMs)
                result.success(mapOf("ok" to true, "baseTimeMs" to baseTimeMs))
            } catch (e: Exception) {
                Log.e(TAG, "trim failed", e)
                result.error("trim_error", e.message, null)
            }
        }.start()
    }

    // 回傳 clip 實際起始時間（ms），即首個寫入 sample 的 PTS（key frame 時間）
    private fun trimWithMuxer(srcPath: String, dstPath: String, startMs: Long, endMs: Long): Long {
        val startUs = startMs * 1000L
        val endUs   = endMs  * 1000L

        // Read rotation metadata from source
        val rotation = MediaMetadataRetriever().use { mmr ->
            mmr.setDataSource(srcPath)
            mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)
                ?.toIntOrNull() ?: 0
        }
        Log.d(TAG, "src rotation=$rotation startMs=$startMs endMs=$endMs")

        File(dstPath).parentFile?.mkdirs()

        val extractor = MediaExtractor()
        val muxer = MediaMuxer(dstPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        try {
            extractor.setDataSource(srcPath)
            if (rotation != 0) muxer.setOrientationHint(rotation)

            // Map extractor track index → muxer track index
            val trackMap = mutableMapOf<Int, Int>()
            for (i in 0 until extractor.trackCount) {
                val fmt  = extractor.getTrackFormat(i)
                val mime = fmt.getString("mime") ?: continue
                if (mime.startsWith("video/")) {
                    // ✅ 明確讀取源幀率，避免 mux 後遺失
                    val srcFps = runCatching {
                        fmt.getInteger(MediaFormat.KEY_FRAME_RATE)
                    }.getOrElse { 30 }  // 預設 30fps
                    fmt.setInteger(MediaFormat.KEY_FRAME_RATE, srcFps)
                    
                    // 🎬 明確記錄 fps 來源
                    val fpsFromMetadata = runCatching { fmt.getInteger(MediaFormat.KEY_FRAME_RATE) }.getOrNull()
                    Log.d(TAG, "[VideoTrimmer] 🎬 fps 檢測: metadata=$fpsFromMetadata → 使用=$srcFps")
                    
                    trackMap[i] = muxer.addTrack(fmt)
                    extractor.selectTrack(i)
                } else if (mime.startsWith("audio/")) {
                    trackMap[i] = muxer.addTrack(fmt)
                    extractor.selectTrack(i)
                }
            }
            if (trackMap.isEmpty()) throw IllegalStateException("no video/audio track found")

            muxer.start()

            // Seek to the nearest sync frame AT OR BEFORE startUs.
            // We write from this key frame (not from startUs) so the clip
            // always begins with an I-frame and is decodeable by any player.
            extractor.seekTo(startUs, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)

            // baseTimeUs = PTS of the first sample actually written.
            // All subsequent PTSs are rebased to this so the clip starts at PTS 0.
            var baseTimeUs = Long.MIN_VALUE

            // adjustedEndUs is recalculated once baseTimeUs is known so the output
            // clip is always exactly (endMs - startMs) ms long regardless of where
            // the previous sync frame lands.
            val requestedDurationUs = endUs - startUs
            var adjustedEndUs = endUs   // overwritten after first sample

            val buf  = ByteBuffer.allocate(BUFFER_SIZE)
            val info = android.media.MediaCodec.BufferInfo()

            while (true) {
                val trackIndex = extractor.sampleTrackIndex
                if (trackIndex < 0) break                  // EOS

                val sampleTimeUs = extractor.sampleTime

                if (baseTimeUs == Long.MIN_VALUE) {
                    baseTimeUs   = sampleTimeUs
                    // Clip ends exactly requestedDuration after the keyframe start.
                    adjustedEndUs = baseTimeUs + requestedDurationUs
                    Log.d(TAG, "baseTimeUs=${baseTimeUs/1000}ms adjustedEndUs=${adjustedEndUs/1000}ms (requested end=${endUs/1000}ms)")
                }

                if (sampleTimeUs > adjustedEndUs) break    // past adjusted end — stop

                val muxerTrack = trackMap[trackIndex]
                if (muxerTrack == null) { extractor.advance(); continue }

                buf.clear()
                val size = extractor.readSampleData(buf, 0)
                if (size < 0) break

                info.offset = 0
                info.size   = size
                info.presentationTimeUs = sampleTimeUs - baseTimeUs
                info.flags  = if (extractor.sampleFlags and MediaExtractor.SAMPLE_FLAG_SYNC != 0)
                    android.media.MediaCodec.BUFFER_FLAG_KEY_FRAME else 0

                muxer.writeSampleData(muxerTrack, buf, info)
                extractor.advance()
            }

            muxer.stop()
            val actualBaseMs = if (baseTimeUs == Long.MIN_VALUE) startMs else baseTimeUs / 1000L
            Log.d(TAG, "trim done → $dstPath  baseMs=$actualBaseMs (requested startMs=$startMs)")
            return actualBaseMs
        } finally {
            runCatching { muxer.release() }
            runCatching { extractor.release() }
        }
    }
}
