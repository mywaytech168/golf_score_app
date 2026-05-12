package com.example.golf_score_app

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.media.Image
import android.media.MediaCodec
import android.media.MediaCodecInfo.CodecCapabilities
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import android.util.Log
import java.io.File
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.roundToInt

/**
 * 軌跡疊加渲染器（Kotlin 負責 I/O 與像素層）。
 *
 * 輸入：含骨架的 mp4 + Dart 計算好的 trackPts（List<Map>）
 * 輸出：在原影片上疊加累積球軌跡曲線的 mp4
 *
 * trackPts 每個元素格式：
 *   { "x": Int, "y": Int, "pts": Long }   （pts = presentationTimeUs）
 *
 * 軌跡畫法：
 *   - 對每幀，取所有 pts ≤ 本幀 pts 的軌跡點
 *   - 金黃色折線 + 最新點白色圓點
 *   - 陰影線（黑半透明，稍粗）增強對比
 */
class TrajectoryOverlayRenderer {

    companion object {
        private const val TAG = "TrajOverlay"

        // 軌跡畫筆參數
        private val TRAJ_COLOR    = Color.argb(230, 255, 210, 30)  // 金黃
        private const val TRAJ_STROKE  = 7f
        private const val DOT_RADIUS   = 9f
        private const val SHADOW_ALPHA = 100
        private const val SHADOW_WIDTH = 10f

        // 預快取 Paint（所有 render() 呼叫為序列，共用安全）
        private val shadowPaint by lazy {
            Paint().apply {
                color       = Color.argb(SHADOW_ALPHA, 0, 0, 0)
                strokeWidth = SHADOW_WIDTH
                style       = Paint.Style.STROKE
                isAntiAlias = true
                strokeCap   = Paint.Cap.ROUND
                strokeJoin  = Paint.Join.ROUND
            }
        }
        private val linePaint by lazy {
            Paint().apply {
                color       = TRAJ_COLOR
                strokeWidth = TRAJ_STROKE
                style       = Paint.Style.STROKE
                isAntiAlias = true
                strokeCap   = Paint.Cap.ROUND
                strokeJoin  = Paint.Join.ROUND
            }
        }
        private val dotFillPaint by lazy {
            Paint().apply {
                color       = Color.WHITE
                style       = Paint.Style.FILL
                isAntiAlias = true
            }
        }
        private val dotBorderPaint by lazy {
            Paint().apply {
                color       = TRAJ_COLOR
                strokeWidth = 2f
                style       = Paint.Style.STROKE
                isAntiAlias = true
            }
        }
    }

    // ────────────────────────────────────────────────────────────
    // 主入口
    // ────────────────────────────────────────────────────────────

    /**
     * @param inputPath  含骨架的 mp4
     * @param outputPath 輸出路徑（骨架 + 球軌跡）
     * @param trackPts   Dart 回傳的軌跡點 List<Map>，
     *                   每個 Map 含 "x"(Int), "y"(Int), "pts"(Long)
     * @return 成功回傳 true
     */
    fun render(
        inputPath: String,
        outputPath: String,
        trackPts: List<Map<String, Any>>,
    ): Boolean {
        if (!File(inputPath).exists()) {
            Log.w(TAG, "輸入檔不存在: $inputPath"); return false
        }

        // 將 trackPts 轉為 (ptsUs, x, y) 列表，以 ptsUs 排序
        val sortedPts: List<Triple<Long, Int, Int>> = trackPts
            .map { m ->
                val pts = when (val v = m["pts"]) {
                    is Long   -> v
                    is Int    -> v.toLong()
                    is Number -> v.toLong()
                    else      -> 0L
                }
                val x = (m["x"] as? Number)?.toInt() ?: 0
                val y = (m["y"] as? Number)?.toInt() ?: 0
                Triple(pts, x, y)
            }
            .sortedBy { it.first }

        Log.d(TAG, "軌跡點數=${sortedPts.size}，輸入=$inputPath")

        // ── 建立 MediaExtractor ─────────────────────────────────
        val extractor = MediaExtractor()
        try { extractor.setDataSource(inputPath) }
        catch (e: Exception) { Log.e(TAG, "無法開啟輸入: $e"); return false }

        var videoTrack = -1
        var inputFormat: MediaFormat? = null
        for (i in 0 until extractor.trackCount) {
            val fmt = extractor.getTrackFormat(i)
            if ((fmt.getString(MediaFormat.KEY_MIME) ?: "").startsWith("video/")) {
                videoTrack = i; inputFormat = fmt; break
            }
        }
        if (videoTrack < 0 || inputFormat == null) {
            Log.e(TAG, "找不到視頻 track"); extractor.release(); return false
        }
        extractor.selectTrack(videoTrack)

        val videoW    = inputFormat.getInteger(MediaFormat.KEY_WIDTH)
        val videoH    = inputFormat.getInteger(MediaFormat.KEY_HEIGHT)
        val videoMime = inputFormat.getString(MediaFormat.KEY_MIME) ?: "video/avc"
        val fps       = runCatching { inputFormat.getInteger(MediaFormat.KEY_FRAME_RATE).toFloat() }
                            .getOrElse { 15f }
        val encW = (videoW + 15) and -16
        val encH = (videoH + 15) and -16

        // ── 建立解碼器 ──────────────────────────────────────────
        val decoder = try {
            MediaCodec.createDecoderByType(videoMime)
        } catch (e: Exception) {
            Log.e(TAG, "無法建立解碼器: $e"); extractor.release(); return false
        }
        decoder.configure(inputFormat, null, null, 0)
        decoder.start()

        // ── 建立編碼器 ──────────────────────────────────────────
        val encoder = try {
            MediaCodec.createEncoderByType("video/avc")
        } catch (e: Exception) {
            Log.e(TAG, "無法建立編碼器: $e")
            decoder.stop(); decoder.release(); extractor.release(); return false
        }
        val encFmt = MediaFormat.createVideoFormat("video/avc", encW, encH).apply {
            setInteger(MediaFormat.KEY_COLOR_FORMAT, CodecCapabilities.COLOR_FormatYUV420SemiPlanar)
            setInteger(MediaFormat.KEY_BIT_RATE, 4_000_000)
            setInteger(MediaFormat.KEY_FRAME_RATE, fps.roundToInt())
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
        }
        encoder.configure(encFmt, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        encoder.start()

        File(outputPath).parentFile?.mkdirs()
        val muxer   = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        var muxTrack   = -1
        var muxStarted    = false
        var encodedFrames = 0

        val decBufInfo = MediaCodec.BufferInfo()
        val encBufInfo = MediaCodec.BufferInfo()
        var inputEos   = false
        var success    = false

        // ── 預分配可重用緩衝區（避免每幀 ~13MB GC 壓力）────────
        val yuvPixels  = IntArray(videoW * videoH)
        val encPixels  = IntArray(encW   * encH)
        val nv12Buf    = ByteArray(encW * encH + encW * encH / 2)
        val frameBmp   = Bitmap.createBitmap(videoW, videoH, Bitmap.Config.ARGB_8888)
        val padBmp     = if (encW != videoW || encH != videoH)
                             Bitmap.createBitmap(encW, encH, Bitmap.Config.ARGB_8888)
                         else null

        try {
            while (true) {
                // ── 餵解碼器 ───────────────────────────────────
                if (!inputEos) {
                    val inIdx = decoder.dequeueInputBuffer(0L)
                    if (inIdx >= 0) {
                        val buf  = decoder.getInputBuffer(inIdx)!!
                        val size = extractor.readSampleData(buf, 0)
                        if (size < 0) {
                            decoder.queueInputBuffer(
                                inIdx, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM
                            )
                            inputEos = true
                        } else {
                            decoder.queueInputBuffer(inIdx, 0, size, extractor.sampleTime, 0)
                            extractor.advance()
                        }
                    }
                }

                // ── 取解碼輸出 ─────────────────────────────────
                val outIdx = decoder.dequeueOutputBuffer(decBufInfo, 10_000L)
                if (outIdx == MediaCodec.INFO_TRY_AGAIN_LATER) continue
                if (outIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) continue
                if (outIdx < 0) continue

                val image = runCatching { decoder.getOutputImage(outIdx) }.getOrNull()
                if (image == null) {
                    decoder.releaseOutputBuffer(outIdx, false)
                    if ((decBufInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) break
                    continue
                }

                try {
                    val pts = decBufInfo.presentationTimeUs

                    // ── YUV → Bitmap（重用 frameBmp + yuvPixels）──
                    yuvFillPixels(image, videoW, videoH, yuvPixels)
                    frameBmp.setPixels(yuvPixels, 0, videoW, 0, 0, videoW, videoH)

                    // ── 找出本幀應顯示的軌跡點（二分搜尋，O(log n)）──
                    val visibleEnd = sortedPts.binarySearchLast { it.first <= pts }
                    if (visibleEnd >= 0) {
                        val visible = sortedPts.subList(0, visibleEnd + 1)
                        if (visible.size >= 2) drawTrajectory(Canvas(frameBmp), visible)
                        else drawDot(Canvas(frameBmp), visible[0].second, visible[0].third)
                    }

                    // ── Bitmap → 編碼器（重用 encPixels + nv12Buf）──
                    val encInIdx = encoder.dequeueInputBuffer(50_000L)
                    if (encInIdx >= 0) {
                        val srcBmp = if (padBmp != null) {
                            Canvas(padBmp).drawBitmap(frameBmp, 0f, 0f, null); padBmp
                        } else frameBmp
                        bitmapFillNv12(srcBmp, encW, encH, encPixels, nv12Buf)
                        val buf = encoder.getInputBuffer(encInIdx)!!
                        buf.clear()
                        buf.put(nv12Buf, 0, nv12Buf.size)
                        encoder.queueInputBuffer(encInIdx, 0, nv12Buf.size, pts, 0)
                    }

                    drainEncoder(
                        encoder, muxer, encBufInfo,
                        setTrack   = { t -> muxTrack = t; muxStarted = true },
                        getTrack   = { muxTrack },
                        isMuxed    = { muxStarted },
                        onFrame    = { encodedFrames++ },
                        eos        = false,
                    )

                } finally {
                    image.close()
                    decoder.releaseOutputBuffer(outIdx, false)
                }

                if ((decBufInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) break
            }

            // ── EOS：持續重試直到取得輸入緩衝區槽 ─────────────────
            Log.d(TAG, "Signaling EOS to encoder, encodedFrames=$encodedFrames")
            var eosIdx = -1
            var eosTries = 0
            while (eosIdx < 0 && eosTries < 20) {
                eosIdx = encoder.dequeueInputBuffer(100_000L)
                eosTries++
            }
            if (eosIdx >= 0) {
                encoder.queueInputBuffer(eosIdx, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                Log.d(TAG, "EOS queued at idx=$eosIdx after $eosTries tries")
            } else {
                Log.w(TAG, "Failed to get EOS input buffer after $eosTries tries")
            }
            drainEncoder(
                encoder, muxer, encBufInfo,
                setTrack = { t -> muxTrack = t; muxStarted = true },
                getTrack = { muxTrack },
                isMuxed  = { muxStarted },
                onFrame  = { encodedFrames++ },
                eos      = true,
            )

            success = encodedFrames > 0
            Log.d(TAG, "完成 → $outputPath (encodedFrames=$encodedFrames)")

        } catch (e: Exception) {
            Log.e(TAG, "渲染失敗: $e", e)
        } finally {
            runCatching { frameBmp.recycle() }
            runCatching { padBmp?.recycle() }
            runCatching { decoder.stop(); decoder.release() }
            runCatching { encoder.stop(); encoder.release() }
            runCatching { extractor.release() }
            runCatching {
                if (muxStarted) { muxer.stop(); muxer.release() } else muxer.release()
            }
        }

        if (!success) runCatching { File(outputPath).delete() }
        return success
    }

    // ────────────────────────────────────────────────────────────
    // 軌跡繪製
    // ────────────────────────────────────────────────────────────

    private fun drawTrajectory(canvas: Canvas, pts: List<Triple<Long, Int, Int>>) {
        if (pts.size < 2) {
            if (pts.size == 1) drawDot(canvas, pts[0].second, pts[0].third)
            return
        }

        // 使用 companion object 快取的 Paint（避免每幀 4× new Paint()）
        // 陰影線
        for (i in 1 until pts.size) {
            canvas.drawLine(
                pts[i - 1].second.toFloat(), pts[i - 1].third.toFloat(),
                pts[i].second.toFloat(),     pts[i].third.toFloat(),
                shadowPaint,
            )
        }
        // 主線
        for (i in 1 until pts.size) {
            canvas.drawLine(
                pts[i - 1].second.toFloat(), pts[i - 1].third.toFloat(),
                pts[i].second.toFloat(),     pts[i].third.toFloat(),
                linePaint,
            )
        }
        // 最新點圓點
        val last = pts.last()
        canvas.drawCircle(last.second.toFloat(), last.third.toFloat(), DOT_RADIUS, dotFillPaint)
        canvas.drawCircle(last.second.toFloat(), last.third.toFloat(), DOT_RADIUS, dotBorderPaint)
    }

    private fun drawDot(canvas: Canvas, x: Int, y: Int) {
        canvas.drawCircle(x.toFloat(), y.toFloat(), DOT_RADIUS, dotFillPaint)
    }

    // ────────────────────────────────────────────────────────────
    // YUV Image → IntArray  /  Bitmap → NV12 ByteArray (in-place)
    // ────────────────────────────────────────────────────────────

    /** Decode YUV420 image into pre-allocated ARGB pixels array (no heap alloc). */
    private fun yuvFillPixels(image: Image, w: Int, h: Int, pixels: IntArray) {
        val yP  = image.planes[0]
        val uP  = image.planes[1]
        val vP  = image.planes[2]
        val yStride       = yP.rowStride
        val uvStride      = uP.rowStride
        val uvPixelStride = uP.pixelStride

        // Bulk-copy ByteBuffers to ByteArrays — avoids per-pixel JVM virtual calls
        val yBytes = ByteArray(yP.buffer.remaining()).also { yP.buffer.get(it) }
        val uBytes = ByteArray(uP.buffer.remaining()).also { uP.buffer.get(it) }
        val vBytes = ByteArray(vP.buffer.remaining()).also { vP.buffer.get(it) }

        for (j in 0 until h) {
            for (i in 0 until w) {
                val yv    = (yBytes[j * yStride + i].toInt() and 0xFF) - 16
                val uvOff = (j / 2) * uvStride + (i / 2) * uvPixelStride
                val u     = (uBytes[uvOff].toInt() and 0xFF) - 128
                val v     = (vBytes[uvOff].toInt() and 0xFF) - 128
                val r = ((298 * yv + 409 * v + 128) shr 8).coerceIn(0, 255)
                val g = ((298 * yv - 100 * u - 208 * v + 128) shr 8).coerceIn(0, 255)
                val b = ((298 * yv + 516 * u + 128) shr 8).coerceIn(0, 255)
                pixels[j * w + i] = (0xFF shl 24) or (r shl 16) or (g shl 8) or b
            }
        }
    }

    /** Encode Bitmap into pre-allocated NV12 byte array (no heap alloc). */
    private fun bitmapFillNv12(bmp: Bitmap, w: Int, h: Int, pixels: IntArray, nv12: ByteArray) {
        bmp.getPixels(pixels, 0, w, 0, 0, w, h)
        val uvBase = w * h
        for (j in 0 until h) {
            for (i in 0 until w) {
                val p = pixels[j * w + i]
                val r = (p shr 16) and 0xFF; val g = (p shr 8) and 0xFF; val b = p and 0xFF
                nv12[j * w + i] = (((66 * r + 129 * g + 25 * b + 128) shr 8) + 16).toByte()
                if (j % 2 == 0 && i % 2 == 0) {
                    val u = ((-38 * r - 74 * g + 112 * b + 128) shr 8) + 128
                    val v = ((112 * r - 94 * g - 18 * b + 128) shr 8) + 128
                    val base = uvBase + (j / 2) * w + (i / 2) * 2
                    if (base + 1 < nv12.size) { nv12[base] = u.toByte(); nv12[base + 1] = v.toByte() }
                }
            }
        }
    }

    /** Returns index of last element satisfying [predicate], or -1. */
    private inline fun <T> List<T>.binarySearchLast(predicate: (T) -> Boolean): Int {
        var lo = 0; var hi = size - 1; var result = -1
        while (lo <= hi) {
            val mid = (lo + hi) ushr 1
            if (predicate(this[mid])) { result = mid; lo = mid + 1 } else hi = mid - 1
        }
        return result
    }

    // ────────────────────────────────────────────────────────────
    // 編碼器排空
    // ────────────────────────────────────────────────────────────

    private fun drainEncoder(
        encoder: MediaCodec, muxer: MediaMuxer, info: MediaCodec.BufferInfo,
        setTrack: (Int) -> Unit, getTrack: () -> Int, isMuxed: () -> Boolean,
        onFrame: (() -> Unit)? = null,
        eos: Boolean,
    ) {
        var tryAgainCount = 0
        var samplesWritten = 0
        val maxTryAgain = 50  // prevent infinite loop: 50 × 10ms = 500ms max

        while (true) {
            val idx = encoder.dequeueOutputBuffer(info, 10_000L)
            when {
                idx == MediaCodec.INFO_TRY_AGAIN_LATER -> {
                    if (!eos) break
                    tryAgainCount++
                    Log.d(TAG, "drainEncoder TRY_AGAIN_LATER ($tryAgainCount/$maxTryAgain) eos=true samples=$samplesWritten")
                    if (tryAgainCount > maxTryAgain) {
                        Log.w(TAG, "drainEncoder EOS timeout — samples=$samplesWritten")
                        break
                    }
                }
                idx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    tryAgainCount = 0
                    val t = muxer.addTrack(encoder.outputFormat)
                    muxer.start(); setTrack(t)
                    Log.d(TAG, "drainEncoder FORMAT_CHANGED, mux track=$t")
                }
                idx >= 0 -> {
                    tryAgainCount = 0
                    val buf = encoder.getOutputBuffer(idx)
                    if (buf != null && info.size > 0 && isMuxed()) {
                        buf.position(info.offset); buf.limit(info.offset + info.size)
                        muxer.writeSampleData(getTrack(), buf, info)
                        onFrame?.invoke()
                        samplesWritten++
                    }
                    encoder.releaseOutputBuffer(idx, false)
                    if ((info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                        Log.d(TAG, "drainEncoder EOS received, samples=$samplesWritten")
                        break
                    }
                }
            }
        }
    }
}
