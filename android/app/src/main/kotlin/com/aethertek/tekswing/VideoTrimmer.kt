package com.aethertek.tekswing

import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.media.MediaMuxer
import android.os.Bundle
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.io.RandomAccessFile
import java.nio.ByteBuffer

/**
 * 高爾夫揮桿切片工具。
 *
 * 核心邏輯：
 * ┌────────────────────────────────────────────────────────┐
 * │  trimWithSurface（主路徑）                              │
 * │  decode+encode，輸出精確 [startMs, endMs] 的 clip。    │
 * │  • 不受 GOP 長度影響（I-frame 可能在 startMs 前數秒）  │
 * │  • 第一幀自動成為 I-frame（encoder 無先前參考）         │
 * │  • 輸出 PTS 從 0 開始，clip 時長 = endMs - startMs     │
 * └────────────────────────────────────────────────────────┘
 *
 * 若 Surface pipeline 失敗，fallback 到 trimWithMuxer（raw mux）。
 */
class VideoTrimmer(private val context: android.content.Context) {

    companion object {
        private const val TAG = "VideoTrimmer"
        private const val AUDIO_BUF = 512 * 1024
        private const val TIMEOUT_US = 10_000L
    }

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "trim") { result.notImplemented(); return }

        val args    = call.arguments as? Map<*, *>
        val srcPath = args?.get("srcPath") as? String
        val dstPath = args?.get("dstPath") as? String
        val startMs = (args?.get("startMs") as? Number)?.toLong() ?: 0L
        val endMs   = (args?.get("endMs")   as? Number)?.toLong()

        if (srcPath.isNullOrBlank() || dstPath.isNullOrBlank() || endMs == null) {
            result.error("invalid_args", "缺少 srcPath / dstPath / startMs / endMs", null); return
        }
        if (!File(srcPath).exists()) {
            result.error("file_not_found", "來源影片不存在: $srcPath", null); return
        }

        Thread {
            try {
                // 主路徑：trimWithSurface（decode+encode，精確 5 秒）
                // fallback：trimWithMuxer（raw mux，從 I-frame 開始，clip 可能較長）
                val surfaceMs = trimWithSurface(srcPath, dstPath, startMs, endMs)
                if (surfaceMs != null) {
                    result.success(mapOf("ok" to true, "baseTimeMs" to surfaceMs))
                } else {
                    Log.w(TAG, "trimWithSurface 失敗，fallback to trimWithMuxer")
                    val baseMs = trimWithMuxer(srcPath, dstPath, startMs, endMs)
                    result.success(mapOf("ok" to true, "baseTimeMs" to baseMs))
                }
            } catch (e: Exception) {
                Log.e(TAG, "trim failed", e)
                result.error("trim_error", e.message, null)
            }
        }.start()
    }

    // ──────────────────────────────────────────────────────────────────────
    // 主路徑：Surface decode+encode → 精確 [startMs, endMs] clip
    // ──────────────────────────────────────────────────────────────────────

    /**
     * 使用 MediaCodec Surface pipeline 精確剪切 [startMs, endMs]。
     * 輸出 clip PTS 從 0 開始，時長 = endMs - startMs（通常 5 秒）。
     * 回傳 startMs（= clip 的原始起始時間）；失敗回傳 null。
     */
    private fun trimWithSurface(srcPath: String, dstPath: String, startMs: Long, endMs: Long): Long? {
        val startUs = startMs * 1000L
        val endUs   = endMs   * 1000L
        Log.d(TAG, "[Surface] trimWithSurface start=$startMs end=$endMs")

        // ── 探測來源格式 ──────────────────────────────────────────────────
        val srcExtractor = MediaExtractor()
        try { srcExtractor.setDataSource(srcPath) }
        catch (e: Exception) { Log.e(TAG, "[Surface] 無法開啟來源: $e"); return null }

        var videoIdx = -1; var audioIdx = -1
        for (i in 0 until srcExtractor.trackCount) {
            val mime = srcExtractor.getTrackFormat(i).getString(MediaFormat.KEY_MIME) ?: ""
            if (mime.startsWith("video/") && videoIdx < 0) videoIdx = i
            if (mime.startsWith("audio/") && audioIdx < 0) audioIdx = i
        }
        if (videoIdx < 0) { srcExtractor.release(); Log.e(TAG, "[Surface] 無視訊軌"); return null }

        val vFmt    = srcExtractor.getTrackFormat(videoIdx)
        val srcMime = vFmt.getString(MediaFormat.KEY_MIME) ?: "video/avc"
        val width   = vFmt.getInteger(MediaFormat.KEY_WIDTH)
        val height  = vFmt.getInteger(MediaFormat.KEY_HEIGHT)

        // 真實 fps（用於 encoder KEY_FRAME_RATE hint，不影響實際 PTS 時序）
        // ⚠️ 用 ceil 而非 truncate：7.5fps → 8，避免 encoder 把幀率設低而丟幀
        val fps: Int = MediaMetadataRetriever().use { mmr ->
            mmr.setDataSource(srcPath)
            mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_CAPTURE_FRAMERATE)
                ?.toFloatOrNull()
                    ?.let { kotlin.math.ceil(it.toDouble()).toInt() }
                ?: run {
                    val cnt = mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_FRAME_COUNT)?.toIntOrNull() ?: 0
                    val dur = mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
                    // 用浮點除法再 ceil，確保不截斷：38幀/5.066s = 7.5 → 8
                    if (cnt > 0 && dur > 0)
                        kotlin.math.ceil(cnt * 1000.0 / dur.toDouble()).toInt()
                    else 0
                }
        }.takeIf { it in 1..240 } ?: 30

        // 旋轉角度
        val rotation = MediaMetadataRetriever().use { mmr ->
            mmr.setDataSource(srcPath)
            mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull() ?: 0
        }

        // 位元率（保持接近原始）
        val srcBitrate = MediaMetadataRetriever().use { mmr ->
            mmr.setDataSource(srcPath)
            mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_BITRATE)?.toIntOrNull() ?: 0
        }.takeIf { it > 0 } ?: (width * height * fps / 10)
        val outBitrate = srcBitrate.coerceIn(2_000_000, 20_000_000)

        Log.d(TAG, "[Surface] ${width}x${height} fps=$fps rot=$rotation br=${outBitrate/1_000_000}Mbps")

        // ── 建立 Encoder ──────────────────────────────────────────────────
        val encFmt = MediaFormat.createVideoFormat("video/avc", width, height).apply {
            setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
            setInteger(MediaFormat.KEY_BIT_RATE,      outBitrate)
            setInteger(MediaFormat.KEY_FRAME_RATE,    fps)
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)  // I-frame 每秒
        }
        val encoder = try {
            MediaCodec.createEncoderByType("video/avc")
        } catch (e: Exception) {
            Log.e(TAG, "[Surface] 無法建立 encoder: $e")
            srcExtractor.release(); return null
        }
        encoder.configure(encFmt, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        val inputSurface = encoder.createInputSurface()
        encoder.start()

        // ── 建立 Decoder（輸出到 Encoder Surface）────────────────────────
        val decoder = try {
            MediaCodec.createDecoderByType(srcMime)
        } catch (e: Exception) {
            Log.e(TAG, "[Surface] 無法建立 decoder: $e")
            encoder.stop(); encoder.release(); inputSurface.release()
            srcExtractor.release(); return null
        }
        decoder.configure(vFmt, inputSurface, null, 0)
        decoder.start()

        // ── Muxer ────────────────────────────────────────────────────────
        File(dstPath).parentFile?.mkdirs()
        val muxer = MediaMuxer(dstPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        if (rotation != 0) muxer.setOrientationHint(rotation)

        // 先加入音訊 track（需在 muxer.start() 前完成）
        var videoMuxTrack = -1; var audioMuxTrack = -1; var muxStarted = false

        // ── 音訊 Extractor（raw copy）────────────────────────────────────
        val audioExtractor: MediaExtractor? = if (audioIdx >= 0) {
            MediaExtractor().also { ae ->
                ae.setDataSource(srcPath)
                ae.selectTrack(audioIdx)
                ae.seekTo(startUs, MediaExtractor.SEEK_TO_CLOSEST_SYNC)
            }
        } else null

        // ── 視訊解碼迴圈 ─────────────────────────────────────────────────
        srcExtractor.selectTrack(videoIdx)
        srcExtractor.seekTo(startUs, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)

        val bufInfo  = MediaCodec.BufferInfo()
        var decInEOS = false
        var decOutEOS = false
        var encOutEOS = false
        var audioEOS  = false
        // ⚠️ audioBaseUs 固定為 startUs，讓音訊 PTS 與視訊 PTS 對齊（視訊第一幀 outPts=0）
        // 若用第一個音訊 sample PTS 當 base，可能有幾十 ms 偏差造成 A/V desync
        val audioBaseUs = startUs
        var lastAudioWrittenPts = -1L

        val aBuf     = ByteBuffer.allocate(AUDIO_BUF)
        val aBufInfo = MediaCodec.BufferInfo()

        try {
            while (!encOutEOS) {

                // ── 餵解碼器 ────────────────────────────────────────────
                if (!decInEOS) {
                    val inIdx = decoder.dequeueInputBuffer(0L)
                    if (inIdx >= 0) {
                        val buf  = decoder.getInputBuffer(inIdx)!!
                        val size = srcExtractor.readSampleData(buf, 0)
                        if (size < 0) {
                            decoder.queueInputBuffer(inIdx, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            decInEOS = true
                        } else {
                            decoder.queueInputBuffer(inIdx, 0, size, srcExtractor.sampleTime, 0)
                            srcExtractor.advance()
                        }
                    }
                }

                // ── 解碼輸出 → 選擇性渲染到 Encoder Surface ─────────────
                if (!decOutEOS) {
                    val outIdx = decoder.dequeueOutputBuffer(bufInfo, TIMEOUT_US)
                    when {
                        outIdx == MediaCodec.INFO_TRY_AGAIN_LATER       -> Unit
                        outIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED  -> Unit
                        outIdx >= 0 -> {
                            val pts = bufInfo.presentationTimeUs

                            when {
                                pts < startUs -> {
                                    // 丟棄：pre-start 幀，解碼但不渲染到 encoder surface
                                    // （需要解碼才能維護 decoder 參考幀緩衝）
                                    decoder.releaseOutputBuffer(outIdx, false)
                                }
                                pts < endUs && bufInfo.size > 0 -> {
                                    // 渲染到 Encoder Surface（pts 轉 ns）
                                    // 第一幀不需 requestSyncFrame：encoder 從未見過任何幀，
                                    // 自動以 I-frame 開始。
                                    decoder.releaseOutputBuffer(outIdx, pts * 1000L)
                                }
                                else -> {
                                    // 超過 endUs → 不渲染，並發送 EOS 給 encoder
                                    decoder.releaseOutputBuffer(outIdx, false)
                                    if (!decOutEOS) {
                                        decOutEOS = true
                                        encoder.signalEndOfInputStream()
                                        Log.d(TAG, "[Surface] decoder past endUs ($pts µs)，signalEOS")
                                    }
                                }
                            }

                            if (!decOutEOS &&
                                bufInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                                decOutEOS = true
                                encoder.signalEndOfInputStream()
                                Log.d(TAG, "[Surface] decoder EOS → signalEndOfInputStream")
                            }
                        }
                    }
                }

                // ── 編碼輸出 → Muxer ──────────────────────────────────
                val encIdx = encoder.dequeueOutputBuffer(bufInfo, TIMEOUT_US)
                when {
                    encIdx == MediaCodec.INFO_TRY_AGAIN_LATER -> Unit
                    encIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        if (!muxStarted) {
                            videoMuxTrack = muxer.addTrack(encoder.outputFormat)
                            if (audioExtractor != null) {
                                val aFmt = audioExtractor.getTrackFormat(audioIdx)
                                audioMuxTrack = runCatching { muxer.addTrack(aFmt) }.getOrElse { -1 }
                            }
                            muxer.start()
                            muxStarted = true
                            Log.d(TAG, "[Surface] muxer started: video=$videoMuxTrack audio=$audioMuxTrack")
                        }
                    }
                    encIdx >= 0 -> {
                        // 部分硬體 encoder 透過 Surface 輸入時，presentationTimeUs 實際上是
                        // releaseOutputBuffer 傳入的 nanoseconds 值（未除以 1000）。
                        // 判斷依據：正常 µs 值不應超過 ~1000 秒（1e12 µs）。
                        val rawPts = bufInfo.presentationTimeUs
                        val encPts = if (rawPts > 1_000_000_000_000L) rawPts / 1000L else rawPts

                        if (muxStarted && bufInfo.size > 0 && videoMuxTrack >= 0 &&
                            bufInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG == 0 &&
                            encPts >= startUs) {   // drop 任何仍在 startUs 前的殘留幀
                            // 重置 PTS：clip 從 0 開始
                            bufInfo.presentationTimeUs = encPts - startUs
                            val buf = encoder.getOutputBuffer(encIdx)!!
                            muxer.writeSampleData(videoMuxTrack, buf, bufInfo)
                        }
                        encoder.releaseOutputBuffer(encIdx, false)

                        if (bufInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                            encOutEOS = true
                            Log.d(TAG, "[Surface] encoder EOS")
                        }
                    }
                }

                // ── 音訊 raw copy（穿插在視訊迴圈內） ────────────────────
                if (muxStarted && !audioEOS && audioExtractor != null && audioMuxTrack >= 0) {
                    aBuf.clear()
                    val aSize = audioExtractor.readSampleData(aBuf, 0)
                    val aPts  = audioExtractor.sampleTime

                    if (aSize < 0 || aPts > endUs) {
                        audioEOS = true
                    } else if (aPts >= startUs) {
                        val outApts = aPts - audioBaseUs   // 歸零（相對於 startUs）
                        if (outApts > lastAudioWrittenPts) {
                            aBufInfo.offset             = 0
                            aBufInfo.size               = aSize
                            aBufInfo.presentationTimeUs = outApts
                            aBufInfo.flags              = audioExtractor.sampleFlags and MediaCodec.BUFFER_FLAG_KEY_FRAME
                            muxer.writeSampleData(audioMuxTrack, aBuf, aBufInfo)
                            lastAudioWrittenPts = outApts
                        }
                        audioExtractor.advance()
                    } else {
                        audioExtractor.advance()   // pre-start audio，跳過
                    }
                }
            }

            // ── 剩餘音訊（encoder EOS 後還可能有音訊）───────────────────
            if (muxStarted && audioExtractor != null && audioMuxTrack >= 0) {
                while (true) {
                    aBuf.clear()
                    val aSize = audioExtractor.readSampleData(aBuf, 0)
                    if (aSize < 0) break
                    val aPts = audioExtractor.sampleTime
                    if (aPts > endUs) break
                    if (aPts >= startUs) {
                        val outApts = aPts - audioBaseUs  // audioBaseUs = startUs（已固定）
                        if (outApts > lastAudioWrittenPts) {
                            aBufInfo.offset             = 0
                            aBufInfo.size               = aSize
                            aBufInfo.presentationTimeUs = outApts
                            aBufInfo.flags              = audioExtractor.sampleFlags and MediaCodec.BUFFER_FLAG_KEY_FRAME
                            muxer.writeSampleData(audioMuxTrack, aBuf, aBufInfo)
                            lastAudioWrittenPts = outApts
                        }
                    }
                    audioExtractor.advance()
                }
            }

        } catch (e: Exception) {
            Log.e(TAG, "[Surface] 編碼迴圈異常: $e", e)
            // 清理後 fallback
            runCatching { if (muxStarted) muxer.stop() }
            runCatching { muxer.release() }
            runCatching { decoder.stop(); decoder.release() }
            runCatching { encoder.stop(); encoder.release() }
            runCatching { inputSurface.release() }
            runCatching { srcExtractor.release() }
            runCatching { audioExtractor?.release() }
            runCatching { File(dstPath).delete() }
            return null
        }

        // ── 正常收尾 ─────────────────────────────────────────────────────
        runCatching { if (muxStarted) muxer.stop() }
        runCatching { muxer.release() }
        runCatching { decoder.stop(); decoder.release() }
        runCatching { encoder.stop(); encoder.release() }
        runCatching { inputSurface.release() }
        runCatching { srcExtractor.release() }
        runCatching { audioExtractor?.release() }

        val sizeKb = File(dstPath).length() / 1024
        Log.d(TAG, "[Surface] ✅ 完成 → $dstPath (${sizeKb}KB) startMs=$startMs")
        applyFastStart(dstPath)
        return startMs   // clip 精確從 startMs 開始 → actualBaseMs = startMs
    }

    // ──────────────────────────────────────────────────────────────────────
    // Fallback：raw mux（不解碼，從 I-frame 到 endMs，clip 可能較長）
    // ──────────────────────────────────────────────────────────────────────

    private fun trimWithMuxer(srcPath: String, dstPath: String, startMs: Long, endMs: Long): Long {
        val startUs = startMs * 1000L
        val endUs   = endMs   * 1000L

        val rotation = MediaMetadataRetriever().use { mmr ->
            mmr.setDataSource(srcPath)
            mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull() ?: 0
        }

        val actualFps: Int = MediaMetadataRetriever().use { mmr ->
            mmr.setDataSource(srcPath)
            mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_CAPTURE_FRAMERATE)
                ?.toFloatOrNull()
                    ?.let { kotlin.math.ceil(it.toDouble()).toInt() }
                ?: run {
                    val cnt = mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_FRAME_COUNT)?.toIntOrNull() ?: 0
                    val dur = mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
                    if (cnt > 0 && dur > 0)
                        kotlin.math.ceil(cnt * 1000.0 / dur.toDouble()).toInt()
                    else 0
                }
        }.takeIf { it in 1..240 } ?: 30

        Log.d(TAG, "[Mux] fallback raw mux: startMs=$startMs endMs=$endMs fps=$actualFps rot=$rotation")
        File(dstPath).parentFile?.mkdirs()

        val extractor = MediaExtractor()
        val muxer     = MediaMuxer(dstPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        try {
            extractor.setDataSource(srcPath)
            if (rotation != 0) muxer.setOrientationHint(rotation)

            val trackMap      = mutableMapOf<Int, Int>()
            var videoMuxTrack = -1
            for (i in 0 until extractor.trackCount) {
                val fmt  = extractor.getTrackFormat(i)
                val mime = fmt.getString("mime") ?: continue
                if (mime.startsWith("video/")) {
                    val rawFps = runCatching { fmt.getInteger(MediaFormat.KEY_FRAME_RATE) }.getOrElse { 0 }
                    fmt.setInteger(MediaFormat.KEY_FRAME_RATE, if (rawFps in 1..240) rawFps else actualFps)
                    val muxIdx = muxer.addTrack(fmt)
                    trackMap[i] = muxIdx; videoMuxTrack = muxIdx
                    extractor.selectTrack(i)
                } else if (mime.startsWith("audio/")) {
                    trackMap[i] = muxer.addTrack(fmt)
                    extractor.selectTrack(i)
                }
            }
            if (trackMap.isEmpty()) throw IllegalStateException("no video/audio track found")

            muxer.start()
            extractor.seekTo(startUs, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)

            var baseTimeUs = Long.MIN_VALUE
            val buf        = ByteBuffer.allocate(2 * 1024 * 1024)
            val info       = MediaCodec.BufferInfo()
            val lastPtsUs  = mutableMapOf<Int, Long>()

            while (true) {
                val trackIndex    = extractor.sampleTrackIndex
                if (trackIndex < 0) break
                val sampleTimeUs  = extractor.sampleTime
                if (sampleTimeUs < 0) { extractor.advance(); continue }

                if (baseTimeUs == Long.MIN_VALUE) {
                    baseTimeUs = sampleTimeUs
                    Log.d(TAG, "[Mux] baseTimeUs=${baseTimeUs/1000}ms (offset=${(startUs-baseTimeUs)/1000}ms before start)")
                }
                if (sampleTimeUs > endUs) break

                val muxerTrack = trackMap[trackIndex] ?: run { extractor.advance(); return@run null } ?: continue
                val outPts     = sampleTimeUs - baseTimeUs
                val isVideo    = (muxerTrack == videoMuxTrack)
                val prevPts    = lastPtsUs[muxerTrack] ?: -1L
                if (outPts < 0 || (!isVideo && outPts <= prevPts)) { extractor.advance(); continue }

                buf.clear()
                val size = extractor.readSampleData(buf, 0)
                if (size < 0) break

                info.offset             = 0
                info.size               = size
                info.presentationTimeUs = outPts
                info.flags              = if (extractor.sampleFlags and MediaExtractor.SAMPLE_FLAG_SYNC != 0)
                    MediaCodec.BUFFER_FLAG_KEY_FRAME else 0

                muxer.writeSampleData(muxerTrack, buf, info)
                lastPtsUs[muxerTrack] = outPts
                extractor.advance()
            }

            muxer.stop()
            val actualBaseMs = if (baseTimeUs == Long.MIN_VALUE) startMs else baseTimeUs / 1000L
            Log.d(TAG, "[Mux] done → $dstPath  baseMs=$actualBaseMs")
            applyFastStart(dstPath)
            return actualBaseMs
        } finally {
            runCatching { muxer.release() }
            runCatching { extractor.release() }
        }
    }

    // ──────────────────────────────────────────────────────────────────────
    // FastStart：將 MP4 moov atom 移到檔案最前面
    //
    // Android MediaMuxer 永遠把 moov 寫在 mdat 後面（檔尾）。
    // OpenCV/FFmpeg 開始讀 mdat 時還沒解析到 avcC（在 moov 內），導致：
    //   "non-existing PPS 1 referenced / decode_slice_header error / no frame!"
    // 把 moov 搬到前面後，FFmpeg 第一時間就能讀到 SPS/PPS，錯誤消失。
    //
    // 演算法：
    //   1. 掃描頂層 box：找 ftyp / moov / mdat
    //   2. moov 已在 mdat 前 → 直接返回（已是 faststart）
    //   3. 將 moov 讀入記憶體，修正 stco/co64 的 chunk offset（+delta）
    //   4. 寫出新檔：ftyp → moov（已修正）→ mdat + 其餘 box
    //   5. 原子性替換原檔
    // ──────────────────────────────────────────────────────────────────────

    private fun applyFastStart(path: String) {
        val srcFile = File(path)
        val tmpFile = File("$path.fstmp")
        try {
            data class Box(val type: String, val offset: Long, val size: Long)

            RandomAccessFile(srcFile, "r").use { raf ->
                val fileLen = raf.length()
                val boxes = mutableListOf<Box>()
                var pos = 0L

                // 掃描頂層 box
                while (pos + 8 <= fileLen) {
                    raf.seek(pos)
                    val sizeField = raf.readInt().toLong() and 0xFFFFFFFFL
                    val typeBytes = ByteArray(4).also { raf.readFully(it) }
                    val type = String(typeBytes, Charsets.ISO_8859_1)
                    val boxSize: Long = when (sizeField) {
                        0L -> fileLen - pos
                        1L -> if (pos + 16 <= fileLen) raf.readLong() else break
                        else -> sizeField
                    }
                    if (boxSize < 8 || pos + boxSize > fileLen + 1) break
                    boxes.add(Box(type, pos, boxSize))
                    pos += boxSize
                }

                val ftypBox = boxes.firstOrNull { it.type == "ftyp" }
                val moovBox = boxes.firstOrNull { it.type == "moov" } ?: return
                val mdatBox = boxes.firstOrNull { it.type == "mdat" } ?: return

                // moov 已在 mdat 前 → 不需要搬移
                if (moovBox.offset <= mdatBox.offset) {
                    Log.d(TAG, "[FastStart] moov 已在前面，跳過")
                    return
                }

                // moov 太大（> 64 MB）→ 跳過，避免 OOM
                if (moovBox.size > 64L * 1024 * 1024) {
                    Log.w(TAG, "[FastStart] moov 過大（${moovBox.size / 1024}KB），跳過")
                    return
                }

                // 讀取 moov 到記憶體
                val moovBytes = ByteArray(moovBox.size.toInt())
                raf.seek(moovBox.offset)
                raf.readFully(moovBytes)

                // 計算 moov 搬到前面後，mdat 的位移量
                val newMdatOffset = (ftypBox?.let { it.offset + it.size } ?: 0L) + moovBox.size
                val delta = newMdatOffset - mdatBox.offset
                Log.d(TAG, "[FastStart] oldMdat=${mdatBox.offset} newMdat=$newMdatOffset delta=$delta")

                // 修正 moov 內所有 stco / co64 的 chunk offset
                patchChunkOffsets(moovBytes, 8, moovBytes.size, delta)

                // 寫出新檔
                FileOutputStream(tmpFile).buffered(256 * 1024).use { out ->
                    val copyBuf = ByteArray(256 * 1024)

                    fun copyBox(box: Box) {
                        raf.seek(box.offset)
                        var remaining = box.size
                        while (remaining > 0) {
                            val n = minOf(remaining, copyBuf.size.toLong()).toInt()
                            raf.readFully(copyBuf, 0, n)
                            out.write(copyBuf, 0, n)
                            remaining -= n
                        }
                    }

                    if (ftypBox != null) copyBox(ftypBox)
                    out.write(moovBytes)   // 已修正 offset 的 moov
                    for (box in boxes.sortedBy { it.offset }) {
                        if (box.type == "ftyp" || box.type == "moov") continue
                        copyBox(box)
                    }
                }
            }

            // 原子性替換
            if (!srcFile.delete()) throw RuntimeException("無法刪除原檔")
            if (!tmpFile.renameTo(srcFile)) throw RuntimeException("無法重新命名暫存檔")
            Log.d(TAG, "[FastStart] ✅ moov 搬到最前面")

        } catch (e: Exception) {
            Log.w(TAG, "[FastStart] 失敗（忽略，影片仍可用）: $e")
            runCatching { tmpFile.delete() }
        }
    }

    /** 遞迴走訪 box 樹，找到 stco / co64 並修正 chunk offset。 */
    private fun patchChunkOffsets(data: ByteArray, start: Int, end: Int, delta: Long) {
        var pos = start
        while (pos + 8 <= end) {
            val sizeField = boxInt32(data, pos).toLong() and 0xFFFFFFFFL
            val type = String(data, pos + 4, 4, Charsets.ISO_8859_1)
            val (boxSize, hdrSize) = when (sizeField) {
                0L   -> Pair((end - pos).toLong(), 8)
                1L   -> if (pos + 16 <= end) Pair(boxInt64(data, pos + 8), 16) else return
                else -> Pair(sizeField, 8)
            }
            if (boxSize < 8 || pos + boxSize > end) return

            val bodyStart = pos + hdrSize
            val bodyEnd   = (pos + boxSize).toInt().coerceAtMost(end)

            when (type) {
                "stco" -> {
                    // FullBox header: version(1) + flags(3) = 4 bytes, then entry_count(4)
                    if (bodyEnd - bodyStart < 8) { pos += boxSize.toInt(); continue }
                    val count = boxInt32(data, bodyStart + 4)
                    for (i in 0 until count) {
                        val off = bodyStart + 8 + i * 4
                        if (off + 4 > bodyEnd) break
                        val newVal = ((boxInt32(data, off).toLong() and 0xFFFFFFFFL) + delta).toInt()
                        putInt32(data, off, newVal)
                    }
                }
                "co64" -> {
                    if (bodyEnd - bodyStart < 8) { pos += boxSize.toInt(); continue }
                    val count = boxInt32(data, bodyStart + 4)
                    for (i in 0 until count) {
                        val off = bodyStart + 8 + i * 8
                        if (off + 8 > bodyEnd) break
                        putInt64(data, off, boxInt64(data, off) + delta)
                    }
                }
                // 遞迴走訪容器 box
                "moov", "trak", "mdia", "minf", "stbl", "udta", "meta", "ilst", "dinf" ->
                    patchChunkOffsets(data, bodyStart, bodyEnd, delta)
            }

            pos += boxSize.toInt()
        }
    }

    private fun boxInt32(d: ByteArray, o: Int): Int =
        ((d[o].toInt() and 0xFF) shl 24) or ((d[o+1].toInt() and 0xFF) shl 16) or
        ((d[o+2].toInt() and 0xFF) shl 8)  or  (d[o+3].toInt() and 0xFF)

    private fun putInt32(d: ByteArray, o: Int, v: Int) {
        d[o]   = (v ushr 24).toByte(); d[o+1] = (v ushr 16).toByte()
        d[o+2] = (v ushr  8).toByte(); d[o+3] = v.toByte()
    }

    private fun boxInt64(d: ByteArray, o: Int): Long =
        (boxInt32(d, o).toLong() shl 32) or (boxInt32(d, o + 4).toLong() and 0xFFFFFFFFL)

    private fun putInt64(d: ByteArray, o: Int, v: Long) {
        putInt32(d, o, (v ushr 32).toInt()); putInt32(d, o + 4, v.toInt())
    }
}
