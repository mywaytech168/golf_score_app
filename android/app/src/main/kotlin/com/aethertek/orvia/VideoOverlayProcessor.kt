package com.aethertek.orvia

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Shader
import android.media.MediaCodec
import android.media.MediaCodecInfo.CodecCapabilities
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.media.MediaMuxer
import android.util.Log
import java.io.File
import java.nio.ByteBuffer
import kotlin.math.roundToInt

/**
 * 影片頭像 / 字幕疊加燒錄。
 *
 * 採用 MediaExtractor + MediaCodec 順序解碼（與 SkeletonOverlayRenderer 相同架構），
 * 逐幀解碼 → Native C YUV→NV12（含旋轉）→ 疊加靜態 overlay → 重新編碼 H.264，
 * 並以 MediaMuxer 原樣複製音軌（passthrough）。
 *
 * 疊加內容（皆為靜態，僅繪製一次後逐幀 composite）：
 *   - 頭像：圓形裁切 + 半透明深色底，置於左下角
 *   - 字幕：白字 + 陰影 + 半透明圓角底，底部置中，字級隨解析度縮放
 */
class VideoOverlayProcessor(private val context: Context) {

    companion object {
        private const val TAG = "VideoOverlay"
    }

    /**
     * 將頭像 / 字幕燒錄至影片。
     * 成功回傳 {"path": 輸出路徑, "burned": 是否真的燒錄}；失敗丟出例外（呼叫端轉為 channel error）。
     * 無可疊加內容（如頭像檔不存在）時退回複製原檔，burned=false。
     */
    fun process(
        inputPath: String,
        outputPath: String,
        attachAvatar: Boolean = false,
        avatarPath: String? = null,
        attachCaption: Boolean = false,
        captionText: String = ""
    ): Map<String, Any> {
        val inputFile = File(inputPath)
        require(inputFile.exists()) { "input video not found: $inputPath" }

        val wantAvatar = attachAvatar && !avatarPath.isNullOrBlank() && File(avatarPath).exists()
        val wantCaption = attachCaption && captionText.isNotBlank()
        if (!wantAvatar && !wantCaption) {
            // 沒有任何可疊加內容（例如頭像檔不存在）→ 維持舊行為：複製原檔
            Log.w(TAG, "無可疊加內容（avatar=$attachAvatar path=$avatarPath caption=$attachCaption）→ 複製原檔")
            val outFile = File(outputPath)
            outFile.parentFile?.mkdirs()
            inputFile.copyTo(outFile, overwrite = true)
            return mapOf("path" to outFile.absolutePath, "burned" to false)
        }

        // ── 1. 開啟視訊軌 ────────────────────────────────────────
        val extractor = MediaExtractor()
        extractor.setDataSource(inputPath)
        var videoTrack = -1; var inputFormat: MediaFormat? = null
        for (i in 0 until extractor.trackCount) {
            val fmt = extractor.getTrackFormat(i)
            if ((fmt.getString(MediaFormat.KEY_MIME) ?: "").startsWith("video/")) {
                videoTrack = i; inputFormat = fmt; break
            }
        }
        if (videoTrack < 0 || inputFormat == null) {
            extractor.release()
            throw IllegalArgumentException("no video track in: $inputPath")
        }
        extractor.selectTrack(videoTrack)

        val videoW    = inputFormat.getInteger(MediaFormat.KEY_WIDTH)
        val videoH    = inputFormat.getInteger(MediaFormat.KEY_HEIGHT)
        val videoMime = inputFormat.getString(MediaFormat.KEY_MIME) ?: "video/avc"

        // 真實 fps / rotation / duration（同 SkeletonOverlayRenderer 作法）
        var rotation = 0; var durationMs = 0L; var fps = 30f
        MediaMetadataRetriever().use { mmr ->
            mmr.setDataSource(inputPath)
            rotation = mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)
                ?.toIntOrNull() ?: 0
            durationMs = mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                ?.toLongOrNull() ?: 0L
            fps = mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_CAPTURE_FRAMERATE)
                ?.toFloatOrNull()
                ?: run {
                    val cnt = mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_FRAME_COUNT)?.toIntOrNull() ?: 0
                    if (cnt > 0 && durationMs > 0) cnt * 1000f / durationMs.toFloat() else null
                }
                ?: runCatching { inputFormat.getInteger(MediaFormat.KEY_FRAME_RATE).toFloat() }.getOrElse { 30f }
            if (fps !in 1f..240f) fps = 30f
        }

        // 輸出以 display 尺寸編碼（旋轉後的正方向），不在 MP4 寫 rotation metadata
        val displayW = if (rotation == 90 || rotation == 270) videoH else videoW
        val displayH = if (rotation == 90 || rotation == 270) videoW else videoH
        Log.d(TAG, "input: coded=${videoW}x${videoH} display=${displayW}x${displayH} fps=$fps rotation=$rotation° avatar=$wantAvatar caption=$wantCaption")

        // ── 2. 解碼器 / 編碼器 ───────────────────────────────────
        val decoder = MediaCodec.createDecoderByType(videoMime)
        decoder.configure(inputFormat, null, null, 0)
        decoder.start()

        val quality = ExportQuality.STANDARD
        val bitRate = (displayW.toLong() * displayH * fps * quality.bppCoeff)
            .toLong().coerceIn(quality.minBitRate, quality.maxBitRate).toInt()
        val encW = (displayW + 15) and -16
        val encH = (displayH + 15) and -16
        val encoder = MediaCodec.createEncoderByType("video/avc")
        val encFmt = MediaFormat.createVideoFormat("video/avc", encW, encH).apply {
            setInteger(MediaFormat.KEY_COLOR_FORMAT, CodecCapabilities.COLOR_FormatYUV420SemiPlanar)
            setInteger(MediaFormat.KEY_BIT_RATE, bitRate)
            setInteger(MediaFormat.KEY_FRAME_RATE, fps.roundToInt())
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
        }
        encoder.configure(encFmt, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        encoder.start()

        // ── 3. Muxer + 音軌 passthrough 準備 ─────────────────────
        File(outputPath).parentFile?.mkdirs()
        val muxer = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        val audioExtractor = MediaExtractor()
        var audioFormat: MediaFormat? = null
        try {
            audioExtractor.setDataSource(inputPath)
            for (i in 0 until audioExtractor.trackCount) {
                val fmt = audioExtractor.getTrackFormat(i)
                if ((fmt.getString(MediaFormat.KEY_MIME) ?: "").startsWith("audio/")) {
                    audioExtractor.selectTrack(i)
                    audioFormat = fmt
                    break
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "音軌探測失敗，僅輸出視訊: $e")
        }

        var muxVideoTrack = -1
        var muxAudioTrack = -1
        var muxStarted = false

        // ── 4. 靜態 overlay 繪製（僅一次）────────────────────────
        val overlayBmp = Bitmap.createBitmap(encW, encH, Bitmap.Config.ARGB_8888)
        drawStaticOverlay(
            Canvas(overlayBmp), encW, encH,
            avatarPath = if (wantAvatar) avatarPath else null,
            caption = if (wantCaption) captionText.trim() else null,
        )

        // ── 5. 逐幀解碼 → composite → 編碼 ───────────────────────
        val decBufInfo = MediaCodec.BufferInfo()
        val encBufInfo = MediaCodec.BufferInfo()
        val nv12Buf = ByteArray(encW * encH + encW * encH / 2)
        var yBuf = ByteArray(0); var uBuf = ByteArray(0); var vBuf = ByteArray(0)
        var inputEos = false
        var frameCount = 0
        var samplesWritten = 0
        var lastDecodedPtsUs = 0L
        var success = false

        try {
            while (true) {
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

                val outIdx = decoder.dequeueOutputBuffer(decBufInfo, 10_000L)
                if (outIdx == MediaCodec.INFO_TRY_AGAIN_LATER) continue
                if (outIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) continue
                if (outIdx < 0) continue

                val isEos = (decBufInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0
                val image = runCatching { decoder.getOutputImage(outIdx) }.getOrNull()
                if (image == null) {
                    decoder.releaseOutputBuffer(outIdx, false)
                    if (isEos) break
                    continue
                }
                if (isEos && decBufInfo.size == 0) {
                    image.close()
                    decoder.releaseOutputBuffer(outIdx, false)
                    break
                }

                try {
                    val pts = decBufInfo.presentationTimeUs
                    lastDecodedPtsUs = pts

                    val yP = image.planes[0]; val uP = image.planes[1]; val vP = image.planes[2]
                    val yNeeded = yP.buffer.remaining(); if (yBuf.size < yNeeded) yBuf = ByteArray(yNeeded); yP.buffer.get(yBuf, 0, yNeeded)
                    val uNeeded = uP.buffer.remaining(); if (uBuf.size < uNeeded) uBuf = ByteArray(uNeeded); uP.buffer.get(uBuf, 0, uNeeded)
                    val vNeeded = vP.buffer.remaining(); if (vBuf.size < vNeeded) vBuf = ByteArray(vNeeded); vP.buffer.get(vBuf, 0, vNeeded)
                    NativeLib.yuvToNv12(
                        yBuf, uBuf, vBuf, yP.rowStride, uP.rowStride, uP.pixelStride,
                        videoW, videoH, rotation, displayW, displayH, encW, encH, nv12Buf,
                    )
                    NativeLib.compositeOverlay(overlayBmp, encW, encH, nv12Buf)

                    val encInIdx = encoder.dequeueInputBuffer(50_000L)
                    if (encInIdx >= 0) {
                        val buf = encoder.getInputBuffer(encInIdx)!!
                        buf.clear()
                        buf.put(nv12Buf, 0, nv12Buf.size)
                        encoder.queueInputBuffer(encInIdx, 0, nv12Buf.size, pts, 0)
                        frameCount++
                    } else {
                        Log.w(TAG, "dequeueInputBuffer 返回 $encInIdx，略過幀 pts=$pts")
                    }

                    drainEncoder(
                        encoder, muxer, encBufInfo,
                        onVideoFormat = { fmt ->
                            muxVideoTrack = muxer.addTrack(fmt)
                            audioFormat?.let { muxAudioTrack = muxer.addTrack(it) }
                            muxer.start(); muxStarted = true
                        },
                        getTrack = { muxVideoTrack },
                        isMuxed  = { muxStarted },
                        eos      = false,
                        onSampleWritten = { samplesWritten++ },
                    )
                } finally {
                    image.close()
                    decoder.releaseOutputBuffer(outIdx, false)
                }

                if (isEos) break
            }

            // ── EOS ──────────────────────────────────────────────
            if (frameCount <= 0) {
                Log.e(TAG, "frameCount=0，編碼器沒有收到任何幀")
            } else {
                var eosIdx = -1; var eosTries = 0
                while (eosIdx < 0 && eosTries < 20) {
                    eosIdx = encoder.dequeueInputBuffer(100_000L); eosTries++
                }
                if (eosIdx >= 0) {
                    val oneFrameUs = if (fps > 0) (1_000_000.0 / fps).toLong() else 33_333L
                    encoder.queueInputBuffer(eosIdx, 0, 0, lastDecodedPtsUs + oneFrameUs, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                }
                drainEncoder(
                    encoder, muxer, encBufInfo,
                    onVideoFormat = { fmt ->
                        muxVideoTrack = muxer.addTrack(fmt)
                        audioFormat?.let { muxAudioTrack = muxer.addTrack(it) }
                        muxer.start(); muxStarted = true
                    },
                    getTrack = { muxVideoTrack },
                    isMuxed  = { muxStarted },
                    eos      = true,
                    onSampleWritten = { samplesWritten++ },
                )
            }

            // ── 音軌 passthrough ────────────────────────────────
            if (muxStarted && muxAudioTrack >= 0 && audioFormat != null) {
                val maxSize = runCatching {
                    audioFormat.getInteger(MediaFormat.KEY_MAX_INPUT_SIZE)
                }.getOrElse { 256 * 1024 }.coerceAtLeast(4096)
                val audioBuf = ByteBuffer.allocate(maxSize)
                val audioInfo = MediaCodec.BufferInfo()
                var audioSamples = 0
                while (true) {
                    val size = audioExtractor.readSampleData(audioBuf, 0)
                    if (size < 0) break
                    audioInfo.set(0, size, audioExtractor.sampleTime, audioExtractor.sampleFlags)
                    muxer.writeSampleData(muxAudioTrack, audioBuf, audioInfo)
                    audioSamples++
                    audioExtractor.advance()
                }
                Log.d(TAG, "音軌複製完成: $audioSamples samples")
            }

            success = muxStarted && samplesWritten > 0
            Log.d(TAG, if (success) "✅ 燒錄完成: $frameCount 幀 → $outputPath"
                       else "❌ 燒錄失敗: frames=$frameCount samples=$samplesWritten")
        } catch (e: Exception) {
            Log.e(TAG, "燒錄錯誤: $e", e)
            success = false
        } finally {
            runCatching { overlayBmp.recycle() }
            runCatching { decoder.stop(); decoder.release() }
            runCatching { encoder.stop(); encoder.release() }
            runCatching { extractor.release() }
            runCatching { audioExtractor.release() }
            runCatching {
                if (muxStarted) { muxer.stop(); muxer.release() } else muxer.release()
            }
        }

        if (!success) {
            runCatching { File(outputPath).delete() }
            throw IllegalStateException("video overlay encoding failed")
        }
        return mapOf("path" to File(outputPath).absolutePath, "burned" to true)
    }

    // ────────────────────────────────────────────────────────────
    // 靜態 overlay 繪製
    // ────────────────────────────────────────────────────────────

    private fun drawStaticOverlay(
        canvas: Canvas,
        w: Int, h: Int,
        avatarPath: String?,
        caption: String?,
    ) {
        canvas.drawColor(Color.TRANSPARENT)
        val shortSide = minOf(w, h).toFloat()
        val margin = shortSide * 0.04f

        // ── 字幕：底部置中，白字 + 陰影 + 半透明圓角底 ──────────
        if (!caption.isNullOrBlank()) {
            val textPaint = Paint().apply {
                isAntiAlias = true
                color = Color.WHITE
                textSize = (shortSide / 22f).coerceIn(18f, 72f)
                textAlign = Paint.Align.CENTER
                setShadowLayer(textSize * 0.08f, 0f, textSize * 0.05f, Color.argb(180, 0, 0, 0))
            }
            val fm = textPaint.fontMetrics
            val textW = textPaint.measureText(caption).coerceAtMost(w - margin * 2)
            val padH = textPaint.textSize * 0.6f
            val padV = textPaint.textSize * 0.35f
            val baselineY = h - margin - padV - fm.descent
            val bgPaint = Paint().apply {
                isAntiAlias = true
                color = Color.argb(110, 0, 0, 0)
            }
            val bgRect = RectF(
                w / 2f - textW / 2f - padH,
                baselineY + fm.ascent - padV,
                w / 2f + textW / 2f + padH,
                baselineY + fm.descent + padV,
            )
            canvas.drawRoundRect(bgRect, padV, padV, bgPaint)
            canvas.drawText(caption, w / 2f, baselineY, textPaint)
        }

        // ── 頭像：左下角圓形裁切 + 半透明深色底環 ────────────────
        if (avatarPath != null) {
            val src = runCatching { BitmapFactory.decodeFile(avatarPath) }.getOrNull()
            if (src == null) {
                Log.w(TAG, "頭像解碼失敗，略過: $avatarPath")
                return
            }
            val avatarR = shortSide * 0.085f
            val ringW = avatarR * 0.12f
            val cx = margin + ringW + avatarR
            val cy = h - margin - ringW - avatarR
            // 半透明深色底（比頭像略大一圈）
            canvas.drawCircle(cx, cy, avatarR + ringW, Paint().apply {
                isAntiAlias = true
                color = Color.argb(130, 0, 0, 0)
            })
            // 圓形裁切頭像（BitmapShader，中心裁切等比填滿）
            val side = minOf(src.width, src.height).toFloat()
            val scale = (avatarR * 2f) / side
            val shader = BitmapShader(src, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP)
            shader.setLocalMatrix(Matrix().apply {
                postTranslate(-src.width / 2f, -src.height / 2f)
                postScale(scale, scale)
                postTranslate(cx, cy)
            })
            canvas.drawCircle(cx, cy, avatarR, Paint().apply {
                isAntiAlias = true
                this.shader = shader
            })
            src.recycle()
        }
    }

    // ────────────────────────────────────────────────────────────
    // 編碼器排空（同 SkeletonOverlayRenderer 策略）
    // ────────────────────────────────────────────────────────────

    private fun drainEncoder(
        encoder: MediaCodec, muxer: MediaMuxer, info: MediaCodec.BufferInfo,
        onVideoFormat: (MediaFormat) -> Unit, getTrack: () -> Int, isMuxed: () -> Boolean,
        eos: Boolean,
        onSampleWritten: () -> Unit = {},
    ) {
        var tryAgainCount = 0
        var drainedSamples = 0
        val maxTryAgainCount = 50

        while (true) {
            val idx = encoder.dequeueOutputBuffer(info, 10_000L)
            when {
                idx == MediaCodec.INFO_TRY_AGAIN_LATER -> {
                    tryAgainCount++
                    if (eos && tryAgainCount > maxTryAgainCount) {
                        Log.w(TAG, "drainEncoder: EOS timeout（drained=$drainedSamples）")
                        break
                    }
                    if (!eos) break
                }
                idx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    tryAgainCount = 0
                    onVideoFormat(encoder.outputFormat)
                }
                idx >= 0 -> {
                    tryAgainCount = 0
                    val buf = encoder.getOutputBuffer(idx)
                    if (buf != null && info.size > 0 && isMuxed()) {
                        buf.position(info.offset); buf.limit(info.offset + info.size)
                        muxer.writeSampleData(getTrack(), buf, info)
                        onSampleWritten()
                        drainedSamples++
                    }
                    encoder.releaseOutputBuffer(idx, false)
                    if ((info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) break
                }
            }
        }
    }
}
