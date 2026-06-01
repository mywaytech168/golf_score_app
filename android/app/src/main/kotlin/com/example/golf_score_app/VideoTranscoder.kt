package com.example.golf_score_app

import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.media.MediaMuxer
import android.util.Log
import java.io.File
import java.nio.ByteBuffer

/**
 * 影片轉碼器
 *
 * 將非標準格式（mp4v-es、高 bitrate）統一轉為：
 *   - 視訊：H.264/AVC，yuv420p，≤ MAX_VIDEO_BITRATE（12 Mbps）
 *   - 音訊：直接 mux（原格式複製，不重編碼）
 *   - 容器：MP4，moov-at-front（faststart）
 *
 * 若來源已是 H.264 且 bitrate ≤ HIGH_BITRATE_THRESHOLD，
 * 則直接複製（快速路徑，避免不必要的重編碼）。
 */
class VideoTranscoder {

    companion object {
        private const val TAG = "VideoTranscoder"

        /** 輸出 H.264 */
        private const val MIME_AVC = "video/avc"

        /** 輸出 bitrate 上限（12 Mbps），足夠 1080p 30fps 品質 */
        private const val MAX_VIDEO_BITRATE = 12_000_000

        /** 高於此 bitrate 就強制重編（20 Mbps），單位 bps */
        private const val HIGH_BITRATE_THRESHOLD = 20_000_000L

        /** MediaCodec I/O 逾時（10 ms） */
        private const val TIMEOUT_US = 10_000L

        /** 音訊 copy buffer 大小 */
        private const val AUDIO_BUF_SIZE = 512 * 1024
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Public API
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * 主入口：
     *   - 若格式已是標準 H.264 且 bitrate 合理 → 直接複製，回傳 dstPath
     *   - 否則 → Surface pipeline 轉碼，回傳 dstPath
     */
    fun process(srcPath: String, dstPath: String): String {
        File(dstPath).parentFile?.mkdirs()

        if (!needsTranscode(srcPath)) {
            Log.i(TAG, "格式符合標準，直接複製 → $dstPath")
            File(srcPath).copyTo(File(dstPath), overwrite = true)
            return dstPath
        }

        Log.i(TAG, "開始轉碼: $srcPath → $dstPath")
        return runTranscode(srcPath, dstPath)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 判斷是否需要轉碼
    // ─────────────────────────────────────────────────────────────────────────

    private fun needsTranscode(srcPath: String): Boolean {
        val extractor = MediaExtractor()
        return try {
            extractor.setDataSource(srcPath)
            for (i in 0 until extractor.trackCount) {
                val fmt  = extractor.getTrackFormat(i)
                val mime = fmt.getString(MediaFormat.KEY_MIME) ?: continue
                if (!mime.startsWith("video/")) continue

                // 非 H.264 → 必須轉碼
                if (mime != MIME_AVC) {
                    Log.i(TAG, "needsTranscode=true: 視訊 codec=$mime（非 H.264）")
                    return true
                }

                // H.264 但 bitrate 過高 → 重編碼降 bitrate
                val bitrate = readOverallBitrate(srcPath)
                if (bitrate > HIGH_BITRATE_THRESHOLD) {
                    Log.i(TAG, "needsTranscode=true: H.264 但 bitrate=${bitrate / 1_000_000}Mbps > 20Mbps")
                    return true
                }

                Log.i(TAG, "needsTranscode=false: H.264，bitrate=${bitrate / 1_000_000}Mbps")
                return false
            }
            false  // 找不到視訊軌道，不做任何事
        } finally {
            runCatching { extractor.release() }
        }
    }

    /** 讀取整體 bitrate（音訊 + 視訊），單位 bps */
    private fun readOverallBitrate(srcPath: String): Long =
        MediaMetadataRetriever().use { mmr ->
            mmr.setDataSource(srcPath)
            mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_BITRATE)?.toLongOrNull() ?: 0L
        }

    // ─────────────────────────────────────────────────────────────────────────
    // 實際轉碼：MediaCodec Surface Pipeline
    //   Decoder (srcMime) → encoder input Surface → Encoder (H.264)
    //   Audio: MediaExtractor 直接 copy → Muxer
    // ─────────────────────────────────────────────────────────────────────────

    private fun runTranscode(srcPath: String, dstPath: String): String {
        // ── 1. 探測來源格式 ──────────────────────────────────────────────────
        val extractor = MediaExtractor()
        extractor.setDataSource(srcPath)

        var videoIdx = -1
        var audioIdx = -1
        for (i in 0 until extractor.trackCount) {
            val mime = extractor.getTrackFormat(i).getString(MediaFormat.KEY_MIME) ?: ""
            when {
                mime.startsWith("video/") && videoIdx < 0 -> videoIdx = i
                mime.startsWith("audio/") && audioIdx < 0 -> audioIdx = i
            }
        }
        require(videoIdx >= 0) { "找不到視訊軌道" }

        val vFmt     = extractor.getTrackFormat(videoIdx)
        val srcMime  = vFmt.getString(MediaFormat.KEY_MIME) ?: MIME_AVC
        val width    = vFmt.getInteger(MediaFormat.KEY_WIDTH)
        val height   = vFmt.getInteger(MediaFormat.KEY_HEIGHT)
        val fps      = runCatching { vFmt.getInteger(MediaFormat.KEY_FRAME_RATE) }
            .getOrElse { 30 }.coerceIn(1, 60)
        val srcBr    = readSourceVideoBitrate(srcPath, vFmt)
        val outBr    = minOf(srcBr, MAX_VIDEO_BITRATE)
        val rotation = MediaMetadataRetriever().use { mmr ->
            mmr.setDataSource(srcPath)
            mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)
                ?.toIntOrNull() ?: 0
        }

        Log.i(TAG, "轉碼資訊: ${width}x${height} $srcMime " +
                "fps=$fps br=${srcBr / 1_000_000}→${outBr / 1_000_000}Mbps rot=$rotation")

        // ── 2. 建立 Encoder（H.264，Surface 輸入）───────────────────────────
        val encFmt = MediaFormat.createVideoFormat(MIME_AVC, width, height).apply {
            setInteger(MediaFormat.KEY_COLOR_FORMAT,
                MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
            setInteger(MediaFormat.KEY_BIT_RATE,     outBr)
            setInteger(MediaFormat.KEY_FRAME_RATE,   fps)
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
        }
        val encoder = MediaCodec.createEncoderByType(MIME_AVC)
        encoder.configure(encFmt, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        val inputSurface = encoder.createInputSurface()
        encoder.start()

        // ── 3. 建立 Decoder（輸出渲染到 Encoder Surface）────────────────────
        val decodeMime = when (srcMime) {
            "video/dolby-vision" -> {
                vFmt.setString(MediaFormat.KEY_MIME, "video/hevc")
                Log.i(TAG, "Dolby Vision → fallback to video/hevc")
                "video/hevc"
            }
            else -> srcMime
        }
        val decoder = MediaCodec.createDecoderByType(decodeMime)
        decoder.configure(vFmt, inputSurface, null, 0)
        decoder.start()

        // ── 4. Muxer ─────────────────────────────────────────────────────────
        File(dstPath).delete()
        val muxer = MediaMuxer(dstPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        if (rotation != 0) muxer.setOrientationHint(rotation)
        var muxerStarted  = false
        var videoMuxTrack = -1
        var audioMuxTrack = -1

        // ── 5. 音訊 Extractor（不重編碼，直接 mux）──────────────────────────
        val aFmt       = if (audioIdx >= 0) extractor.getTrackFormat(audioIdx) else null
        val aExtractor = if (audioIdx >= 0) {
            MediaExtractor().also { ae ->
                ae.setDataSource(srcPath)
                ae.selectTrack(audioIdx)
            }
        } else null

        // ── 6. 主迴圈：Decode → Surface → Encode → Mux ─────────────────────
        extractor.selectTrack(videoIdx)
        val bufInfo   = MediaCodec.BufferInfo()
        var decInEOS  = false
        var decOutEOS = false
        var encOutEOS = false
        var audioEOS  = false
        val aBuf      = ByteBuffer.allocate(AUDIO_BUF_SIZE)
        val aBufInfo  = MediaCodec.BufferInfo()

        while (!encOutEOS) {

            // ── 餵解碼器輸入 ────────────────────────────────────────────────
            if (!decInEOS) {
                val inIdx = decoder.dequeueInputBuffer(0)
                if (inIdx >= 0) {
                    val buf  = decoder.getInputBuffer(inIdx)!!
                    val size = extractor.readSampleData(buf, 0)
                    if (size < 0) {
                        decoder.queueInputBuffer(inIdx, 0, 0, 0,
                            MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                        decInEOS = true
                    } else {
                        decoder.queueInputBuffer(inIdx, 0, size,
                            extractor.sampleTime, 0)
                        extractor.advance()
                    }
                }
            }

            // ── 解碼輸出 → render to Surface → Encoder 自動取得 ─────────────
            if (!decOutEOS) {
                val outIdx = decoder.dequeueOutputBuffer(bufInfo, TIMEOUT_US)
                when {
                    outIdx == MediaCodec.INFO_TRY_AGAIN_LATER       -> Unit
                    outIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED  -> Unit
                    outIdx >= 0 -> {
                        // 傳入原始 PTS（μs→ns），讓 SurfaceTexture 用來源時間戳，
                        // 避免 encoder 用系統時鐘壓縮 PTS 造成播放加速。
                        val renderTs = if (bufInfo.size > 0) bufInfo.presentationTimeUs * 1000L else -1L
                        if (renderTs >= 0) decoder.releaseOutputBuffer(outIdx, renderTs)
                        else decoder.releaseOutputBuffer(outIdx, false)
                        if (bufInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                            decOutEOS = true
                            encoder.signalEndOfInputStream()
                            Log.d(TAG, "decoder EOS → signalEndOfInputStream")
                        }
                    }
                }
            }

            // ── 編碼輸出 → Muxer ────────────────────────────────────────────
            val encIdx = encoder.dequeueOutputBuffer(bufInfo, TIMEOUT_US)
            when {
                encIdx == MediaCodec.INFO_TRY_AGAIN_LATER      -> Unit
                encIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    if (!muxerStarted) {
                        videoMuxTrack = muxer.addTrack(encoder.outputFormat)
                        if (aFmt != null) {
                            audioMuxTrack = try {
                                muxer.addTrack(aFmt)
                            } catch (e: Exception) {
                                Log.w(TAG, "音訊軌道不相容，略過: ${e.message}")
                                -1
                            }
                        }
                        muxer.start()
                        muxerStarted = true
                        Log.d(TAG, "muxer started: video=$videoMuxTrack audio=$audioMuxTrack")
                    }
                }
                encIdx >= 0 -> {
                    if (muxerStarted && bufInfo.size > 0 &&
                        bufInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG == 0) {
                        muxer.writeSampleData(
                            videoMuxTrack,
                            encoder.getOutputBuffer(encIdx)!!,
                            bufInfo
                        )
                    }
                    encoder.releaseOutputBuffer(encIdx, false)
                    if (bufInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                        encOutEOS = true
                        Log.d(TAG, "encoder EOS")
                    }
                }
            }

            // ── 音訊穿插 mux（一次一個 sample，防止記憶體堆積）──────────────
            if (muxerStarted && !audioEOS && aExtractor != null && audioMuxTrack >= 0) {
                aBuf.clear()
                val aSize = aExtractor.readSampleData(aBuf, 0)
                if (aSize < 0) {
                    audioEOS = true
                } else {
                    aBufInfo.offset             = 0
                    aBufInfo.size               = aSize
                    aBufInfo.presentationTimeUs = aExtractor.sampleTime
                    aBufInfo.flags              = aExtractor.sampleFlags and MediaCodec.BUFFER_FLAG_KEY_FRAME
                    muxer.writeSampleData(audioMuxTrack, aBuf, aBufInfo)
                    aExtractor.advance()
                }
            }
        }

        // ── 7. 剩餘音訊（video EOS 後可能還有音訊）──────────────────────────
        if (muxerStarted && !audioEOS && aExtractor != null && audioMuxTrack >= 0) {
            while (true) {
                aBuf.clear()
                val aSize = aExtractor.readSampleData(aBuf, 0)
                if (aSize < 0) break
                aBufInfo.offset             = 0
                aBufInfo.size               = aSize
                aBufInfo.presentationTimeUs = aExtractor.sampleTime
                aBufInfo.flags              = aExtractor.sampleFlags and MediaCodec.BUFFER_FLAG_KEY_FRAME
                muxer.writeSampleData(audioMuxTrack, aBuf, aBufInfo)
                aExtractor.advance()
            }
        }

        // ── 8. 釋放資源 ──────────────────────────────────────────────────────
        runCatching { decoder.stop();  decoder.release() }
        runCatching { encoder.stop();  encoder.release() }
        runCatching { inputSurface.release() }
        runCatching { if (muxerStarted) muxer.stop() }
        runCatching { muxer.release() }
        runCatching { extractor.release() }
        runCatching { aExtractor?.release() }

        val sizeKb = File(dstPath).length() / 1024
        Log.i(TAG, "轉碼完成 → $dstPath (${sizeKb}KB)")
        return dstPath
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Helper：取得來源視訊 bitrate（優先從 track format，fallback 從 MMR）
    // ─────────────────────────────────────────────────────────────────────────

    private fun readSourceVideoBitrate(srcPath: String, vFmt: MediaFormat): Int {
        val fromFmt = runCatching {
            if (vFmt.containsKey(MediaFormat.KEY_BIT_RATE))
                vFmt.getInteger(MediaFormat.KEY_BIT_RATE)
            else -1
        }.getOrElse { -1 }
        if (fromFmt > 0) return fromFmt

        // MediaFormat 沒有 bitrate key（mp4v-es 常見情況）→ 讀整體 bitrate
        val overall = readOverallBitrate(srcPath).toInt()
        return if (overall > 0) overall else MAX_VIDEO_BITRATE
    }
}
