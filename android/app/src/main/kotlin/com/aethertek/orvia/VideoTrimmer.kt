package com.aethertek.orvia

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

        val args         = call.arguments as? Map<*, *>
        val srcPath        = args?.get("srcPath") as? String
        val dstPath        = args?.get("dstPath") as? String
        val startMs        = (args?.get("startMs")      as? Number)?.toLong() ?: 0L
        val endMs          = (args?.get("endMs")        as? Number)?.toLong()
        val targetWidth    = (args?.get("targetWidth")  as? Number)?.toInt()
        val targetHeight   = (args?.get("targetHeight") as? Number)?.toInt()
        val flipHorizontal = (args?.get("flipHorizontal") as? Boolean) ?: false

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
                val surfaceMs = trimWithSurface(srcPath, dstPath, startMs, endMs, targetWidth, targetHeight, flipHorizontal)
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
    private fun trimWithSurface(srcPath: String, dstPath: String, startMs: Long, endMs: Long,
                               targetWidth: Int? = null, targetHeight: Int? = null,
                               flipHorizontal: Boolean = false): Long? {
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

        // ① 先計算 display 尺寸（套用 rotation 後的顯示方向）
        val hasRotation = rotation == 90 || rotation == 270
        val (dispW, dispH) = if (hasRotation) Pair(height, width) else Pair(width, height)

        // ② 目標輸出尺寸（Encoder 設定）
        //   - EGL 路徑（needEgl=true）：encoder 必須設成旋轉後的直式尺寸（如 720×1280）
        //     若 target 有傳入：直接使用（ClipPipeline 傳入直式）；
        //     否則用 dispW×dispH（display 尺寸，已考量旋轉），確保 encoder 不是橫式
        //   - 直接 Surface 路徑：沿用來源橫式尺寸，靠 orientationHint 告知播放器旋轉
        //   ★ 必須先算 dispW/dispH，再算 encWidth/encHeight，最後算 needEgl/needResize
        val encWidthRaw  = targetWidth  ?: dispW
        val encHeightRaw = targetHeight ?: dispH

        // ③ 確認是否需要 EGL
        val needResize = (dispW != encWidthRaw || dispH != encHeightRaw)
        val needEgl    = hasRotation || needResize
        val encWidth   = encWidthRaw
        val encHeight  = encHeightRaw

        Log.d(TAG, "[Surface] src=${width}x${height} disp=${dispW}x${dispH} enc=${encWidth}x${encHeight} " +
                   "fps=$fps rot=$rotation needEgl=${needEgl}(rot=$hasRotation,resize=$needResize) br=${outBitrate/1_000_000}Mbps")

        // ── 建立 Encoder ──────────────────────────────────────────────────
        val encFmt = MediaFormat.createVideoFormat("video/avc", encWidth, encHeight).apply {
            setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
            setInteger(MediaFormat.KEY_BIT_RATE,      outBitrate)
            setInteger(MediaFormat.KEY_FRAME_RATE,    fps)
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)  // I-frame 每秒，提升切片對齊機率
            // ★ 每個 IDR 幀前內嵌 SPS/PPS（解碼密碼本）：
            //   確保每個切片開頭的關鍵幀可獨立解碼，防止播放器在第 2+ 個切片
            //   因缺少 SPS/PPS 而出現綠屏或卡死。(API 29+ 正式常數相同字串)
            setInteger("prepend-sps-pps-to-idr-keyframes", 1)
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

        // ── EGL processor（尺寸不符時，在 decoder → encoder 間做 rotate+scale）
        val eglProc: EglSurfaceProcessor? = if (needEgl) {
            try {
                EglSurfaceProcessor(inputSurface).also { it.setup(width, height) }
            } catch (e: Exception) {
                Log.w(TAG, "[Surface] EGL setup 失敗，fallback 直接 Surface: $e")
                null
            }
        } else null

        // decoder 的輸出 Surface：有 EGL 時用 EglSurfaceProcessor.decoderSurface，否則直接用 encoder inputSurface
        val decoderOutputSurface = eglProc?.decoderSurface ?: inputSurface

        // ── 建立 Decoder（輸出到 Encoder Surface 或 EGL SurfaceTexture）───
        val decoder = try {
            MediaCodec.createDecoderByType(srcMime)
        } catch (e: Exception) {
            Log.e(TAG, "[Surface] 無法建立 decoder: $e")
            eglProc?.release()
            encoder.stop(); encoder.release(); inputSurface.release()
            srcExtractor.release(); return null
        }
        // ★ 剝除 rotation metadata 再餵 decoder：
        //   Surface 輸出模式下，decoder 會把 format 裡的 rotation-degrees 自動套用
        //   （透過 SurfaceTexture transform matrix，shader 的 uTexMatrix 已吃進去），
        //   EGL 的 MVP 再轉一次 → 雙重旋轉（歷史：rotateM(-90) 輸出 -90°、+90 輸出 +90°，
        //   誤差恰等於 MVP 角度 = 證據）。清成 0 讓旋轉完全由 MVP 控制，跨裝置行為一致。
        vFmt.setInteger(MediaFormat.KEY_ROTATION, 0)
        decoder.configure(vFmt, decoderOutputSurface, null, 0)
        decoder.start()
        // ★ 診斷側轉問題：codec 實作不同（c2.qti vs c2.android…）對剝除 KEY_ROTATION
        //   的行為可能不一致 → 留名比對正常/側轉兩種輸出
        Log.i(TAG, "[Surface] decoder=${decoder.name} rot=$rotation needEgl=$needEgl " +
                   "src=${width}x${height} enc=${encWidth}x${encHeight}")

        // ── Muxer ────────────────────────────────────────────────────────
        File(dstPath).parentFile?.mkdirs()
        val muxer = MediaMuxer(dstPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)

        // ★ orientation hint 依據「實際使用的路徑」決定，而非意圖（needEgl）：
        //
        //   eglProc != null（EGL 路徑成功）：
        //     - EGL 已將 rotation bake 進 pixels（encoder 輸出已是直式）
        //     - 輸出尺寸 encWidth×encHeight 已是直式（如 720×1280）
        //     - 必須設 hint = 0，否則播放器再轉 90° → 影片旋轉 +90° 疊加 BUG
        //
        //   eglProc == null（EGL setup 失敗或不需要，直接 Surface 路徑）：
        //     - decoder 直接輸出原始橫式幀到 encoder
        //     - 輸出仍是橫式（如 1920×1080），需要 hint = rotation 讓播放器旋轉
        //     - 不設 hint 或 hint=0 會讓播放器顯示橫式影片（BUG）
        val hintForMuxer = if (eglProc != null) 0 else rotation
        muxer.setOrientationHint(hintForMuxer)
        Log.d(TAG, "[Surface] muxer orientationHint=$hintForMuxer " +
                   "(eglProc=${eglProc != null}, srcRotation=$rotation, enc=${encWidth}x${encHeight})")

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
                            val isCodecConfig = bufInfo.flags and
                                MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0

                            when {
                                isCodecConfig -> {
                                    // SPS/PPS config frame：消耗但不渲染
                                    decoder.releaseOutputBuffer(outIdx, false)
                                }
                                pts < startUs -> {
                                    // pre-start catch-up：解碼但不渲染到 encoder surface
                                    // （需要解碼才能維護 decoder 參考幀緩衝）
                                    decoder.releaseOutputBuffer(outIdx, false)
                                }
                                pts < endUs -> {
                                    // ★ 移除 `bufInfo.size > 0` 判斷：
                                    //   Surface 模式的 MediaCodec decoder 在 Snapdragon 等硬體上
                                    //   bufInfo.size 永遠為 0（frame 送到 SurfaceTexture，不在 ByteBuffer）
                                    //   加上此判斷會導致 startMs>0 的所有幀被誤判為「無效」→ 10KB 空影片
                                    val outPtsUs = pts - startUs   // clip 內相對 PTS
                                    if (eglProc != null) {
                                        // EGL 路徑：渲染到 SurfaceTexture，再由 shader 旋轉+縮放到 encoder
                                        decoder.releaseOutputBuffer(outIdx, true)  // render=true
                                        eglProc.awaitAndRender(
                                            rotationDeg     = rotation,
                                            dstWidth        = encWidth,
                                            dstHeight       = encHeight,
                                            ptsUs           = outPtsUs,
                                            flipHorizontal  = flipHorizontal
                                        )
                                    } else {
                                        // 直接 Surface 路徑（尺寸相符時）
                                        decoder.releaseOutputBuffer(outIdx, pts * 1000L)
                                    }
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
                        // eglPresentationTimeANDROID 傳入的 nanoseconds 值（未除以 1000）。
                        // 判斷依據：正常 µs 值不應超過 ~1000 秒（1e12 µs）。
                        val rawPts = bufInfo.presentationTimeUs
                        val encPts = if (rawPts > 1_000_000_000_000L) rawPts / 1000L else rawPts

                        // ★ PTS 路徑修正：
                        //
                        //   EGL 路徑（eglProc != null）：
                        //     awaitAndRender 傳入 ptsUs = pts - startUs（已歸零）
                        //     → encoder 輸出 encPts ≈ 0~clip長度（相對值）
                        //     → clipPts = encPts（直接使用，不再扣 startUs）
                        //     → 舊邏輯 encPts - startUs = 相對值 - 大數 → 負 PTS！
                        //     → 舊篩選器 encPts >= startUs 對相對值永遠 FALSE → IDR 被丟！→ 綠屏！
                        //
                        //   直接 Surface 路徑（eglProc == null）：
                        //     releaseOutputBuffer(outIdx, pts * 1000L)（絕對 nanoseconds）
                        //     → encPts ≈ pts（絕對 µs）
                        //     → clipPts = encPts - startUs（歸零為相對值）
                        //     → 篩選器 encPts >= startUs 正確過濾 pre-start 殘留
                        val clipPts: Long
                        val shouldWrite: Boolean
                        if (eglProc != null) {
                            // EGL：PTS 已是 0-based，直接使用
                            clipPts = encPts
                            shouldWrite = clipPts >= 0L   // 防止任何非預期的負值
                        } else {
                            // 直接路徑：PTS 是絕對值，需扣 startUs
                            clipPts = encPts - startUs
                            shouldWrite = clipPts >= 0L   // 過濾 pre-start 殘留幀
                        }

                        if (muxStarted && bufInfo.size > 0 && videoMuxTrack >= 0 &&
                            bufInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG == 0 &&
                            shouldWrite) {
                            bufInfo.presentationTimeUs = clipPts
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
            runCatching { eglProc?.release() }
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
        runCatching { eglProc?.release() }
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
