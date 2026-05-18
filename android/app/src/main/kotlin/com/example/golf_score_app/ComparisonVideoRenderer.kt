package com.example.golf_score_app

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.media.Image
import android.media.MediaCodec
import android.media.MediaCodecInfo.CodecCapabilities
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.media.MediaMuxer
import android.util.Log
import java.io.File
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * 並排比較影片渲染器。
 *
 * 同時解碼兩支影片，支援以 hitSecond 為基準的對軸對齊，
 * 將每幀並排合成後以 H.264 編碼輸出單一 MP4，讓播放器只需一個 controller。
 */
class ComparisonVideoRenderer {

    companion object {
        private const val TAG   = "CompareRenderer"
        private const val OUT_H = 720  // 每個 panel 的目標高度
    }

    private val paintLabel = Paint().apply {
        color = Color.WHITE; textSize = 36f; isAntiAlias = true; isFakeBoldText = true
    }
    private val paintBgA = Paint().apply {
        color = Color.argb(180, 30, 142, 90); style = Paint.Style.FILL
    }
    private val paintBgB = Paint().apply {
        color = Color.argb(180, 21, 101, 192); style = Paint.Style.FILL
    }

    // ────────────────────────────────────────────────────────────
    // 主入口
    // ────────────────────────────────────────────────────────────

    /**
     * @param pathA     左側影片路徑
     * @param pathB     右側影片路徑
     * @param outputPath 輸出合併 MP4 路徑
     * @param hitSecA   A 影片擊球時刻（秒），對軸基準，預設 0
     * @param hitSecB   B 影片擊球時刻（秒），對軸基準，預設 0
     * @param onProgress 進度回調
     */
    fun render(
        pathA: String, pathB: String, outputPath: String,
        hitSecA: Double = 0.0, hitSecB: Double = 0.0,
        onProgress: ((op: String, progress: Double, label: String, current: Int, total: Int) -> Unit)? = null,
    ): Boolean {
        if (!File(pathA).exists() || !File(pathB).exists()) {
            Log.w(TAG, "輸入檔不存在: A=$pathA  B=$pathB"); return false
        }

        // ── 影片 metadata ─────────────────────────────────────
        val (durA, rotA) = getVideoMeta(pathA)
        val (durB, rotB) = getVideoMeta(pathB)

        // 對軸計算
        val minT      = -min(hitSecA, hitSecB)
        val maxT      = min(durA - hitSecA, durB - hitSecB)
        val startSecA = (hitSecA + minT).coerceIn(0.0, durA)
        val startSecB = (hitSecB + minT).coerceIn(0.0, durB)
        val clipDurSec = maxT - minT
        if (clipDurSec <= 0.01) { Log.e(TAG, "clipDurSec=$clipDurSec 太短"); return false }

        val startUsA = (startSecA * 1_000_000L).toLong()
        val startUsB = (startSecB * 1_000_000L).toLong()
        val endRelUs  = (clipDurSec * 1_000_000L).toLong()

        Log.d(TAG, "A: dur=$durA rot=$rotA startSec=$startSecA | B: dur=$durB rot=$rotB startSec=$startSecB | clip=$clipDurSec s")

        // ── 開啟 extractor + 取得影片格式 ─────────────────────
        val (extA, fmtA) = openVideoExtractor(pathA) ?: return false
        val (extB, fmtB) = openVideoExtractor(pathB) ?: return false

        val codedWA = fmtA.getInteger(MediaFormat.KEY_WIDTH)
        val codedHA = fmtA.getInteger(MediaFormat.KEY_HEIGHT)
        val mimeA   = fmtA.getString(MediaFormat.KEY_MIME) ?: "video/avc"
        val codedWB = fmtB.getInteger(MediaFormat.KEY_WIDTH)
        val codedHB = fmtB.getInteger(MediaFormat.KEY_HEIGHT)
        val mimeB   = fmtB.getString(MediaFormat.KEY_MIME) ?: "video/avc"

        // 旋轉後的顯示尺寸
        val dispWA = if (rotA == 90 || rotA == 270) codedHA else codedWA
        val dispHA = if (rotA == 90 || rotA == 270) codedWA else codedHA
        val dispWB = if (rotB == 90 || rotB == 270) codedHB else codedWB
        val dispHB = if (rotB == 90 || rotB == 270) codedWB else codedHB

        // Panel 尺寸（縮放至 OUT_H，保持寬高比）
        val panelWA = ((dispWA.toLong() * OUT_H / dispHA + 1) and -2L).toInt()
        val panelWB = ((dispWB.toLong() * OUT_H / dispHB + 1) and -2L).toInt()
        val outW    = ((panelWA + panelWB + 15) and -16)
        val outH    = ((OUT_H + 15) and -16)

        val fps        = 30f
        val fpsUs      = (1_000_000.0 / fps).toLong()
        val totalFrames = (clipDurSec * fps).toInt().coerceAtLeast(1)

        Log.d(TAG, "panelA=${panelWA}x$OUT_H panelB=${panelWB}x$OUT_H out=${outW}x${outH} ~$totalFrames f")

        // Seek 到對齊起始點
        if (startUsA > 0) extA.seekTo(startUsA, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
        if (startUsB > 0) extB.seekTo(startUsB, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)

        // ── 解碼器 ────────────────────────────────────────────
        val decA = try {
            MediaCodec.createDecoderByType(mimeA).also { it.configure(fmtA, null, null, 0); it.start() }
        } catch (e: Exception) {
            Log.e(TAG, "解碼器A失敗: $e"); extA.release(); extB.release(); return false
        }
        val decB = try {
            MediaCodec.createDecoderByType(mimeB).also { it.configure(fmtB, null, null, 0); it.start() }
        } catch (e: Exception) {
            Log.e(TAG, "解碼器B失敗: $e")
            decA.stop(); decA.release(); extA.release(); extB.release(); return false
        }

        // ── 編碼器 + Muxer ────────────────────────────────────
        val bitRate = (outW.toLong() * outH * fps * 0.6).toLong().coerceIn(4_000_000L, 16_000_000L).toInt()
        val encFmt  = MediaFormat.createVideoFormat("video/avc", outW, outH).apply {
            setInteger(MediaFormat.KEY_COLOR_FORMAT, CodecCapabilities.COLOR_FormatYUV420SemiPlanar)
            setInteger(MediaFormat.KEY_BIT_RATE, bitRate)
            setInteger(MediaFormat.KEY_FRAME_RATE, fps.roundToInt())
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
        }
        val encoder = try {
            MediaCodec.createEncoderByType("video/avc").also {
                it.configure(encFmt, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE); it.start()
            }
        } catch (e: Exception) {
            Log.e(TAG, "編碼器失敗: $e")
            decA.stop(); decA.release(); decB.stop(); decB.release()
            extA.release(); extB.release(); return false
        }

        File(outputPath).parentFile?.mkdirs()
        val muxer     = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        var muxTrack  = -1; var muxStarted = false

        // ── 共用緩衝區（避免每幀 GC）──────────────────────────
        val yuvBufA   = IntArray(codedWA * codedHA)
        val yuvBufB   = IntArray(codedWB * codedHB)
        val rawBmpA   = Bitmap.createBitmap(codedWA, codedHA, Bitmap.Config.ARGB_8888)
        val rawBmpB   = Bitmap.createBitmap(codedWB, codedHB, Bitmap.Config.ARGB_8888)
        val outBmp    = Bitmap.createBitmap(outW, outH, Bitmap.Config.ARGB_8888)
        val encPixels = IntArray(outW * outH)
        val nv12Buf   = ByteArray(outW * outH + outW * outH / 2)
        val outCanvas = Canvas(outBmp)

        val decBufA = MediaCodec.BufferInfo()
        val decBufB = MediaCodec.BufferInfo()
        val encBuf  = MediaCodec.BufferInfo()

        // 解碼器狀態
        var inEosA = false; var outEosA = false
        var inEosB = false; var outEosB = false
        var curBmpA: Bitmap? = null; var relPtsA = Long.MIN_VALUE
        var curBmpB: Bitmap? = null; var relPtsB = Long.MIN_VALUE

        var targetUs    = 0L; var encPtsUs = 0L
        var encodedFrames = 0; var rendered = 0
        var success     = false

        try {
            while (targetUs <= endRelUs) {

                // ── 推進解碼器 A 到 targetUs ──────────────────
                var aIter = 0
                while (relPtsA < targetUs && !outEosA && aIter++ < 400) {
                    if (!inEosA) {
                        val i = decA.dequeueInputBuffer(0L)
                        if (i >= 0) {
                            val buf = decA.getInputBuffer(i)!!
                            val sz  = extA.readSampleData(buf, 0)
                            if (sz < 0) {
                                decA.queueInputBuffer(i, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                                inEosA = true
                            } else {
                                decA.queueInputBuffer(i, 0, sz, extA.sampleTime, 0)
                                extA.advance()
                            }
                        }
                    }
                    val o = decA.dequeueOutputBuffer(decBufA, 2_000L)
                    if (o == MediaCodec.INFO_TRY_AGAIN_LATER || o == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) continue
                    if (o < 0) continue
                    val absRel = decBufA.presentationTimeUs - startUsA
                    if (absRel >= 0) {
                        val img = runCatching { decA.getOutputImage(o) }.getOrNull()
                        if (img != null) {
                            try {
                                yuvFillPixels(img, codedWA, codedHA, yuvBufA)
                                rawBmpA.setPixels(yuvBufA, 0, codedWA, 0, 0, codedWA, codedHA)
                                val disp   = rotateBitmap(rawBmpA, rotA)
                                val scaled = Bitmap.createScaledBitmap(disp, panelWA, OUT_H, true)
                                if (rotA != 0) disp.recycle()
                                curBmpA?.recycle(); curBmpA = scaled
                                relPtsA = absRel
                            } finally { img.close() }
                        }
                    }
                    decA.releaseOutputBuffer(o, false)
                    if ((decBufA.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                        outEosA = true; break
                    }
                }

                // ── 推進解碼器 B 到 targetUs ──────────────────
                var bIter = 0
                while (relPtsB < targetUs && !outEosB && bIter++ < 400) {
                    if (!inEosB) {
                        val i = decB.dequeueInputBuffer(0L)
                        if (i >= 0) {
                            val buf = decB.getInputBuffer(i)!!
                            val sz  = extB.readSampleData(buf, 0)
                            if (sz < 0) {
                                decB.queueInputBuffer(i, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                                inEosB = true
                            } else {
                                decB.queueInputBuffer(i, 0, sz, extB.sampleTime, 0)
                                extB.advance()
                            }
                        }
                    }
                    val o = decB.dequeueOutputBuffer(decBufB, 2_000L)
                    if (o == MediaCodec.INFO_TRY_AGAIN_LATER || o == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) continue
                    if (o < 0) continue
                    val absRel = decBufB.presentationTimeUs - startUsB
                    if (absRel >= 0) {
                        val img = runCatching { decB.getOutputImage(o) }.getOrNull()
                        if (img != null) {
                            try {
                                yuvFillPixels(img, codedWB, codedHB, yuvBufB)
                                rawBmpB.setPixels(yuvBufB, 0, codedWB, 0, 0, codedWB, codedHB)
                                val disp   = rotateBitmap(rawBmpB, rotB)
                                val scaled = Bitmap.createScaledBitmap(disp, panelWB, OUT_H, true)
                                if (rotB != 0) disp.recycle()
                                curBmpB?.recycle(); curBmpB = scaled
                                relPtsB = absRel
                            } finally { img.close() }
                        }
                    }
                    decB.releaseOutputBuffer(o, false)
                    if ((decBufB.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                        outEosB = true; break
                    }
                }

                // ── 合成並編碼 ────────────────────────────────
                val fa = curBmpA; val fb = curBmpB
                if (fa != null || fb != null) {
                    outCanvas.drawColor(Color.BLACK)
                    fa?.let { outCanvas.drawBitmap(it, 0f, 0f, null) }
                    fb?.let { outCanvas.drawBitmap(it, panelWA.toFloat(), 0f, null) }
                    drawLabel(outCanvas, "A", 8f, paintBgA)
                    drawLabel(outCanvas, "B", panelWA + 8f, paintBgB)

                    val encIdx = encoder.dequeueInputBuffer(50_000L)
                    if (encIdx >= 0) {
                        bitmapFillNv12(outBmp, outW, outH, encPixels, nv12Buf)
                        val buf = encoder.getInputBuffer(encIdx)!!
                        buf.clear(); buf.put(nv12Buf, 0, nv12Buf.size)
                        encoder.queueInputBuffer(encIdx, 0, nv12Buf.size, encPtsUs, 0)
                        encPtsUs += fpsUs
                    }
                    drainEncoder(encoder, muxer, encBuf,
                        { t -> muxTrack = t; muxStarted = true }, { muxTrack }, { muxStarted },
                        { encodedFrames++ }, false)

                    rendered++
                    if (rendered % 5 == 0) {
                        val p = (rendered.toDouble() / totalFrames).coerceIn(0.0, 0.95)
                        onProgress?.invoke("renderComparison", p, "合成中 ${(p * 100).toInt()}%", rendered, totalFrames)
                    }
                }

                if (outEosA && outEosB) break
                targetUs += fpsUs
            }

            // ── EOS ───────────────────────────────────────────
            var eosIdx = -1; var tries = 0
            while (eosIdx < 0 && tries++ < 20) eosIdx = encoder.dequeueInputBuffer(100_000L)
            if (eosIdx >= 0) encoder.queueInputBuffer(eosIdx, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
            drainEncoder(encoder, muxer, encBuf,
                { t -> muxTrack = t; muxStarted = true }, { muxTrack }, { muxStarted },
                { encodedFrames++ }, true)

            success = encodedFrames > 0
            Log.d(TAG, "完成 → $outputPath (encoded=$encodedFrames rendered=$rendered)")
            onProgress?.invoke("renderComparison", 1.0, "合成完成", rendered, rendered)

        } catch (e: Exception) {
            Log.e(TAG, "渲染失敗: $e", e)
        } finally {
            runCatching { curBmpA?.recycle(); curBmpB?.recycle() }
            runCatching { rawBmpA.recycle(); rawBmpB.recycle(); outBmp.recycle() }
            runCatching { decA.stop(); decA.release() }
            runCatching { decB.stop(); decB.release() }
            runCatching { encoder.stop(); encoder.release() }
            runCatching { extA.release(); extB.release() }
            runCatching { if (muxStarted) { muxer.stop(); muxer.release() } else muxer.release() }
        }

        if (!success) runCatching { File(outputPath).delete() }
        return success
    }

    // ────────────────────────────────────────────────────────────
    // UI 輔助
    // ────────────────────────────────────────────────────────────

    private fun drawLabel(canvas: Canvas, text: String, x: Float, bgPaint: Paint) {
        canvas.drawRoundRect(x, 8f, x + 46f, 50f, 6f, 6f, bgPaint)
        canvas.drawText(text, x + 8f, 42f, paintLabel)
    }

    // ────────────────────────────────────────────────────────────
    // 影片 metadata
    // ────────────────────────────────────────────────────────────

    private fun getVideoMeta(path: String): Pair<Double, Int> =
        MediaMetadataRetriever().use { mmr ->
            mmr.setDataSource(path)
            val dur = mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                ?.toLongOrNull()?.div(1000.0) ?: 0.0
            val rot = mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)
                ?.toIntOrNull() ?: 0
            Pair(dur, rot)
        }

    /** 開啟 MediaExtractor，選定視頻 track，回傳 (extractor, format)。失敗回傳 null。 */
    private fun openVideoExtractor(path: String): Pair<MediaExtractor, MediaFormat>? {
        val ext = MediaExtractor()
        try {
            ext.setDataSource(path)
            for (i in 0 until ext.trackCount) {
                val fmt = ext.getTrackFormat(i)
                if ((fmt.getString(MediaFormat.KEY_MIME) ?: "").startsWith("video/")) {
                    ext.selectTrack(i)
                    return Pair(ext, fmt)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "openVideoExtractor 失敗 $path: $e")
        }
        ext.release()
        return null
    }

    // ────────────────────────────────────────────────────────────
    // 像素工具（複製自 TrajectoryOverlayRenderer）
    // ────────────────────────────────────────────────────────────

    private fun rotateBitmap(src: Bitmap, degrees: Int): Bitmap {
        if (degrees == 0) return src
        val m = Matrix().also { it.postRotate(degrees.toFloat()) }
        return Bitmap.createBitmap(src, 0, 0, src.width, src.height, m, true)
    }

    private fun yuvFillPixels(image: Image, w: Int, h: Int, pixels: IntArray) {
        val yP = image.planes[0]; val uP = image.planes[1]; val vP = image.planes[2]
        val yStride = yP.rowStride; val uvStride = uP.rowStride; val uvPixelStride = uP.pixelStride
        val yBytes = ByteArray(yP.buffer.remaining()).also { yP.buffer.get(it) }
        val uBytes = ByteArray(uP.buffer.remaining()).also { uP.buffer.get(it) }
        val vBytes = ByteArray(vP.buffer.remaining()).also { vP.buffer.get(it) }
        for (j in 0 until h) {
            for (i in 0 until w) {
                val yv  = (yBytes[j * yStride + i].toInt() and 0xFF) - 16
                val off = (j / 2) * uvStride + (i / 2) * uvPixelStride
                val u   = (uBytes[off].toInt() and 0xFF) - 128
                val v   = (vBytes[off].toInt() and 0xFF) - 128
                val r   = ((298 * yv + 409 * v + 128) shr 8).coerceIn(0, 255)
                val g   = ((298 * yv - 100 * u - 208 * v + 128) shr 8).coerceIn(0, 255)
                val b   = ((298 * yv + 516 * u + 128) shr 8).coerceIn(0, 255)
                pixels[j * w + i] = (0xFF shl 24) or (r shl 16) or (g shl 8) or b
            }
        }
    }

    private fun bitmapFillNv12(bmp: Bitmap, w: Int, h: Int, pixels: IntArray, nv12: ByteArray) {
        bmp.getPixels(pixels, 0, w, 0, 0, w, h)
        val uvBase = w * h
        for (j in 0 until h) {
            for (i in 0 until w) {
                val p = pixels[j * w + i]
                val r = (p shr 16) and 0xFF; val g = (p shr 8) and 0xFF; val b = p and 0xFF
                nv12[j * w + i] = (((66 * r + 129 * g + 25 * b + 128) shr 8) + 16).toByte()
                if (j % 2 == 0 && i % 2 == 0) {
                    val u    = ((-38 * r - 74 * g + 112 * b + 128) shr 8) + 128
                    val v    = ((112 * r - 94 * g - 18 * b + 128) shr 8) + 128
                    val base = uvBase + (j / 2) * w + (i / 2) * 2
                    if (base + 1 < nv12.size) { nv12[base] = u.toByte(); nv12[base + 1] = v.toByte() }
                }
            }
        }
    }

    private fun drainEncoder(
        encoder: MediaCodec, muxer: MediaMuxer, info: MediaCodec.BufferInfo,
        setTrack: (Int) -> Unit, getTrack: () -> Int, isMuxed: () -> Boolean,
        onFrame: (() -> Unit)? = null, eos: Boolean,
    ) {
        var retryCount = 0
        while (true) {
            val idx = encoder.dequeueOutputBuffer(info, 10_000L)
            when {
                idx == MediaCodec.INFO_TRY_AGAIN_LATER -> {
                    if (!eos) break
                    if (++retryCount > 50) { Log.w(TAG, "drainEncoder EOS timeout"); break }
                }
                idx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    retryCount = 0
                    val t = muxer.addTrack(encoder.outputFormat); muxer.start(); setTrack(t)
                }
                idx >= 0 -> {
                    retryCount = 0
                    val buf = encoder.getOutputBuffer(idx)
                    if (buf != null && info.size > 0 && isMuxed()) {
                        buf.position(info.offset); buf.limit(info.offset + info.size)
                        muxer.writeSampleData(getTrack(), buf, info); onFrame?.invoke()
                    }
                    encoder.releaseOutputBuffer(idx, false)
                    if ((info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) break
                }
            }
        }
    }
}
