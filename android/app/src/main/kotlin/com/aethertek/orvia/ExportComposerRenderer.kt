package com.aethertek.orvia

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.RectF
import android.media.MediaCodec
import android.media.MediaCodecInfo.CodecCapabilities
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.media.MediaMuxer
import android.util.Log
import java.io.File
import kotlin.math.roundToInt

/**
 * 匯出合成器：一次解碼 → 依序疊「軌跡 / 骨架 / 浮水印」於同一張 overlay → 一次編碼。
 *
 * 取代原先「skeleton.mp4 一遍、trajectory 再一遍」的 2-pass 串接（畫質只損一次），
 * 並新增浮水印 layer（免費版強制）。任一 layer 皆可選，全關時等同重編碼原片＋浮水印。
 *
 * 座標處理沿用既有兩個渲染器的已驗證邏輯：
 *   ・rotation-aware YUV→NV12（display 空間，同 SkeletonOverlayRenderer）
 *   ・骨架 CSV(thumbnail 空間) → display 縮放
 *   ・軌跡 trackPts(coded 空間) 直接畫於 display（等價既有 ensureFinalVideo）
 */
class ExportComposerRenderer(private val context: android.content.Context) {

    companion object {
        private const val TAG = "ExportComposer"

        // 骨架連線與左右標記（同 SkeletonOverlayRenderer）
        val CONNECTIONS = listOf(
            0 to 1, 1 to 2, 2 to 3, 3 to 7,
            0 to 4, 4 to 5, 5 to 6, 6 to 8,
            9 to 10,
            11 to 13, 13 to 15, 15 to 17, 17 to 19, 19 to 15, 15 to 21,
            12 to 14, 14 to 16, 16 to 18, 18 to 20, 20 to 16, 16 to 22,
            11 to 12, 12 to 24, 24 to 23, 23 to 11,
            23 to 25, 25 to 27, 27 to 29, 29 to 31, 31 to 27,
            24 to 26, 26 to 28, 28 to 30, 30 to 32, 32 to 28,
        )
        val LEFT_LANDMARKS  = setOf(1, 2, 3, 7, 9, 11, 13, 15, 17, 19, 21, 23, 25, 27, 29, 31)
        val RIGHT_LANDMARKS = setOf(4, 5, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30, 32)

        // 軌跡畫筆參數（同 TrajectoryOverlayRenderer）
        private val TRAJ_COLOR    = Color.argb(230, 255, 210, 30)
        private const val TRAJ_STROKE  = 7f
        private const val DOT_RADIUS   = 9f
        private const val SHADOW_ALPHA = 100
        private const val SHADOW_WIDTH = 10f
    }

    private data class LandmarkPoint(
        val xPx: Float, val yPx: Float,
        val xNorm: Float, val yNorm: Float,
        val visibility: Float,
    )

    // 重用 Paint（避免每幀 GC）
    private val linePaint = Paint().apply {
        style = Paint.Style.STROKE; isAntiAlias = true; strokeCap = Paint.Cap.ROUND
    }
    private val dotPaint = Paint().apply { style = Paint.Style.FILL; isAntiAlias = true }
    private val trajShadowPaint = Paint().apply {
        color = Color.argb(SHADOW_ALPHA, 0, 0, 0); strokeWidth = SHADOW_WIDTH
        style = Paint.Style.STROKE; isAntiAlias = true
        strokeCap = Paint.Cap.ROUND; strokeJoin = Paint.Join.ROUND
    }
    private val trajLinePaint = Paint().apply {
        color = TRAJ_COLOR; strokeWidth = TRAJ_STROKE
        style = Paint.Style.STROKE; isAntiAlias = true
        strokeCap = Paint.Cap.ROUND; strokeJoin = Paint.Join.ROUND
    }
    private val trajDotFill = Paint().apply { color = Color.WHITE; style = Paint.Style.FILL; isAntiAlias = true }
    private val trajDotBorder = Paint().apply {
        color = TRAJ_COLOR; strokeWidth = 2f; style = Paint.Style.STROKE; isAntiAlias = true
    }
    private val watermarkPaint = Paint().apply { isAntiAlias = true; isFilterBitmap = true; alpha = 165 }

    private var yBuf = ByteArray(0)
    private var uBuf = ByteArray(0)
    private var vBuf = ByteArray(0)

    /**
     * @param clipPath       乾淨來源片段（clip.mp4 / swing.mp4）
     * @param csvPath        骨架 CSV，null 或不存在 → 不畫骨架
     * @param startSec       片段在原片中的起始秒（對齊 CSV 時間 key）
     * @param trackPts       軌跡點 List<Map{x,y,pts}>，空 → 不畫軌跡
     * @param watermarkPath  浮水印 PNG 路徑，null 或不存在 → 不畫浮水印
     * @param outputPath     輸出 mp4
     */
    fun render(
        clipPath: String,
        csvPath: String?,
        startSec: Double,
        trackPts: List<Map<String, Any>>,
        watermarkPath: String?,
        outputPath: String,
        quality: ExportQuality = ExportQuality.STANDARD,
        onProgress: ((op: String, progress: Double, label: String, current: Int, total: Int) -> Unit)? = null,
        shouldCancel: (() -> Boolean)? = null,
    ): Boolean {
        if (!File(clipPath).exists()) { Log.w(TAG, "來源不存在: $clipPath"); return false }

        // ── 啟用判定 ───────────────────────────────────────────────
        val frameData: Map<Int, Array<LandmarkPoint?>> =
            if (csvPath != null && File(csvPath).exists()) smoothFrameData(parseCsv(csvPath)) else emptyMap()
        val skeletonOn = frameData.isNotEmpty()
        val sortedFrameKeys = if (skeletonOn) frameData.keys.sorted() else emptyList()
        val poseSize = if (skeletonOn) inferPoseImageSize(frameData) else null
        if (skeletonOn && poseSize == null) Log.w(TAG, "無法推算骨架影像尺寸，骨架略過")
        val drawSkeleton = skeletonOn && poseSize != null
        val poseW = poseSize?.first ?: 1f
        val poseH = poseSize?.second ?: 1f

        // 軌跡點 (ptsUs, x, y) 排序
        val sortedPts: List<Triple<Long, Int, Int>> = trackPts.map { m ->
            val pts = when (val v = m["pts"]) {
                is Long -> v; is Int -> v.toLong(); is Number -> v.toLong(); else -> 0L
            }
            Triple(pts, (m["x"] as? Number)?.toInt() ?: 0, (m["y"] as? Number)?.toInt() ?: 0)
        }.sortedBy { it.first }
        val trajectoryOn = sortedPts.isNotEmpty()

        val watermarkBmp: Bitmap? =
            if (watermarkPath != null && File(watermarkPath).exists())
                runCatching { BitmapFactory.decodeFile(watermarkPath) }.getOrNull()
            else null

        Log.d(TAG, "layers: skeleton=$drawSkeleton trajectory=$trajectoryOn watermark=${watermarkBmp != null}")

        // ── MediaExtractor ─────────────────────────────────────────
        val extractor = MediaExtractor()
        try { extractor.setDataSource(clipPath) }
        catch (e: Exception) { Log.e(TAG, "開啟失敗: $e"); watermarkBmp?.recycle(); return false }

        var videoTrack = -1; var inputFormat: MediaFormat? = null
        for (i in 0 until extractor.trackCount) {
            val fmt = extractor.getTrackFormat(i)
            if ((fmt.getString(MediaFormat.KEY_MIME) ?: "").startsWith("video/")) {
                videoTrack = i; inputFormat = fmt; break
            }
        }
        if (videoTrack < 0 || inputFormat == null) {
            Log.e(TAG, "找不到 video track"); extractor.release(); watermarkBmp?.recycle(); return false
        }
        extractor.selectTrack(videoTrack)

        val videoW    = inputFormat.getInteger(MediaFormat.KEY_WIDTH)
        val videoH    = inputFormat.getInteger(MediaFormat.KEY_HEIGHT)
        val videoMime = inputFormat.getString(MediaFormat.KEY_MIME) ?: "video/avc"

        val fps: Float = MediaMetadataRetriever().use { mmr ->
            mmr.setDataSource(clipPath)
            mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_CAPTURE_FRAMERATE)?.toFloatOrNull()
                ?: run {
                    val cnt = mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_FRAME_COUNT)?.toIntOrNull() ?: 0
                    val dur = mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
                    if (cnt > 0 && dur > 0) cnt * 1000f / dur.toFloat() else null
                }
        } ?: runCatching { inputFormat.getInteger(MediaFormat.KEY_FRAME_RATE).toFloat() }.getOrElse { 30f }
            .let { if (it in 1f..240f) it else 30f }

        val rotation = MediaMetadataRetriever().use { mmr ->
            mmr.setDataSource(clipPath)
            mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull() ?: 0
        }
        // 以 display 尺寸編碼（旋轉後正方向），不寫 rotation metadata
        val displayW = if (rotation == 90 || rotation == 270) videoH else videoW
        val displayH = if (rotation == 90 || rotation == 270) videoW else videoH
        val durationMs = MediaMetadataRetriever().use { mmr ->
            mmr.setDataSource(clipPath)
            mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
        }
        val totalFrames = if (fps > 0 && durationMs > 0) (durationMs * fps / 1000.0).toInt().coerceAtLeast(1) else 0

        // ── 解碼器 ─────────────────────────────────────────────────
        val decoder = try { MediaCodec.createDecoderByType(videoMime) }
            catch (e: Exception) { Log.e(TAG, "解碼器建立失敗: $e"); extractor.release(); watermarkBmp?.recycle(); return false }
        decoder.configure(inputFormat, null, null, 0)
        decoder.start()

        // ── 編碼器 ─────────────────────────────────────────────────
        val encoder = try { MediaCodec.createEncoderByType("video/avc") }
            catch (e: Exception) {
                Log.e(TAG, "編碼器建立失敗: $e")
                decoder.stop(); decoder.release(); extractor.release(); watermarkBmp?.recycle(); return false
            }
        val bitRate = (displayW.toLong() * displayH * fps * quality.bppCoeff)
            .toLong().coerceIn(quality.minBitRate, quality.maxBitRate).toInt()
        val encW = (displayW + 15) and -16
        val encH = (displayH + 15) and -16
        val encFmt = MediaFormat.createVideoFormat("video/avc", encW, encH).apply {
            setInteger(MediaFormat.KEY_COLOR_FORMAT, CodecCapabilities.COLOR_FormatYUV420SemiPlanar)
            setInteger(MediaFormat.KEY_BIT_RATE, bitRate)
            setInteger(MediaFormat.KEY_FRAME_RATE, fps.roundToInt())
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
        }
        encoder.configure(encFmt, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        encoder.start()

        File(outputPath).parentFile?.mkdirs()
        val muxer = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        var muxTrack = -1; var muxStarted = false

        val decBufInfo = MediaCodec.BufferInfo()
        val encBufInfo = MediaCodec.BufferInfo()
        var inputEos = false; var frameCount = 0
        var encodedFrames = 0; var samplesWritten = 0
        var success = false; var lastDecodedPtsUs = 0L

        val nv12Buf = ByteArray(encW * encH + encW * encH / 2)
        val overlayBmp = Bitmap.createBitmap(encW, encH, Bitmap.Config.ARGB_8888)
        val overlayCanvas = Canvas(overlayBmp)
        val encShortSide = minOf(encW, encH).toFloat()
        linePaint.strokeWidth = (encShortSide / 120f).coerceIn(0.8f, 3f)
        val skeletonRadius = (encShortSide / 100f).coerceIn(1.5f, 5f)

        // 浮水印目標矩形（右下角，寬 = 短邊 22%，等比；margin = 短邊 4%）
        val wmRect: RectF? = watermarkBmp?.let { bmp ->
            val targetW = encShortSide * 0.22f
            val scale = targetW / bmp.width
            val targetH = bmp.height * scale
            val margin = encShortSide * 0.04f
            RectF(encW - margin - targetW, encH - margin - targetH, encW - margin, encH - margin)
        }
        val wmSrc: Rect? = watermarkBmp?.let { Rect(0, 0, it.width, it.height) }

        var trajCursor = 0

        try {
            while (true) {
                if (!inputEos) {
                    val inIdx = decoder.dequeueInputBuffer(0L)
                    if (inIdx >= 0) {
                        val buf = decoder.getInputBuffer(inIdx)!!
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
                    if (isEos) break else continue
                }
                if (isEos && decBufInfo.size == 0) {
                    image.close(); decoder.releaseOutputBuffer(outIdx, false); break
                }

                try {
                    val pts = decBufInfo.presentationTimeUs
                    lastDecodedPtsUs = pts
                    val csvTimeMs = ((startSec + pts / 1_000_000.0) * 1000.0).roundToInt()

                    // 1. YUV → NV12（rotation-aware，display 空間）
                    val yP = image.planes[0]; val uP = image.planes[1]; val vP = image.planes[2]
                    val yStride = yP.rowStride; val uvStride = uP.rowStride; val uvPixelStride = uP.pixelStride
                    val yN = yP.buffer.remaining(); if (yBuf.size < yN) yBuf = ByteArray(yN); yP.buffer.get(yBuf, 0, yN)
                    val uN = uP.buffer.remaining(); if (uBuf.size < uN) uBuf = ByteArray(uN); uP.buffer.get(uBuf, 0, uN)
                    val vN = vP.buffer.remaining(); if (vBuf.size < vN) vBuf = ByteArray(vN); vP.buffer.get(vBuf, 0, vN)
                    NativeLib.yuvToNv12(
                        yBuf, uBuf, vBuf, yStride, uvStride, uvPixelStride,
                        videoW, videoH, rotation, displayW, displayH, encW, encH, nv12Buf,
                    )

                    // 2. 疊 layer（同一張 overlay canvas）
                    overlayBmp.eraseColor(Color.TRANSPARENT)

                    if (trajectoryOn) {
                        while (trajCursor < sortedPts.size && sortedPts[trajCursor].first <= pts) trajCursor++
                        val visible = sortedPts.subList(0, trajCursor)
                        if (visible.size >= 2) drawTrajectory(overlayCanvas, visible)
                        else if (visible.isNotEmpty()) drawTrajDot(overlayCanvas, visible[0].second, visible[0].third)
                    }

                    if (drawSkeleton) {
                        getSmoothedLandmarks(frameData, csvTimeMs, sortedFrameKeys)?.let { lms ->
                            drawSkeleton(overlayCanvas, lms, poseW, poseH, encW, encH, skeletonRadius)
                        }
                    }

                    if (watermarkBmp != null && wmRect != null && wmSrc != null) {
                        overlayCanvas.drawBitmap(watermarkBmp, wmSrc, wmRect, watermarkPaint)
                    }

                    // 3. composite + encode
                    NativeLib.compositeOverlay(overlayBmp, encW, encH, nv12Buf)

                    val encInIdx = encoder.dequeueInputBuffer(50_000L)
                    if (encInIdx >= 0) {
                        val buf = encoder.getInputBuffer(encInIdx)!!
                        buf.clear(); buf.put(nv12Buf, 0, nv12Buf.size)
                        encoder.queueInputBuffer(encInIdx, 0, nv12Buf.size, pts, 0)
                        frameCount++
                        if (frameCount % 10 == 0 && totalFrames > 0) {
                            val prog = (frameCount.toDouble() / totalFrames).coerceIn(0.0, 0.95)
                            onProgress?.invoke("composeExport", prog, "影片合成中 ${(prog * 100).toInt()}%", frameCount, totalFrames)
                        }
                    }

                    drainEncoder(encoder, muxer, encBufInfo,
                        setTrack = { t -> muxTrack = t; muxStarted = true },
                        getTrack = { muxTrack }, isMuxed = { muxStarted }, eos = false,
                        onSampleWritten = { encodedFrames++; samplesWritten++ })

                } finally {
                    image.close(); decoder.releaseOutputBuffer(outIdx, false)
                }

                if (shouldCancel?.invoke() == true) { Log.i(TAG, "取消：$frameCount 幀"); break }
                if (isEos) break
            }

            if (frameCount > 0) {
                var eosIdx = -1; var tries = 0
                while (eosIdx < 0 && tries < 20) { eosIdx = encoder.dequeueInputBuffer(100_000L); tries++ }
                if (eosIdx >= 0) {
                    val oneFrameUs = if (fps > 0) (1_000_000.0 / fps).toLong() else 33_333L
                    encoder.queueInputBuffer(eosIdx, 0, 0, lastDecodedPtsUs + oneFrameUs, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                }
                drainEncoder(encoder, muxer, encBufInfo,
                    setTrack = { t -> muxTrack = t; muxStarted = true },
                    getTrack = { muxTrack }, isMuxed = { muxStarted }, eos = true,
                    onSampleWritten = { encodedFrames++; samplesWritten++ })
            }

            success = encodedFrames > 0 && samplesWritten > 0 && muxStarted
            if (success) onProgress?.invoke("composeExport", 1.0, "影片合成完成", frameCount, frameCount)
            Log.d(TAG, "完成 success=$success frames=$frameCount encoded=$encodedFrames → $outputPath")

        } catch (e: Exception) {
            Log.e(TAG, "合成錯誤: $e", e)
        } finally {
            runCatching { overlayBmp.recycle() }
            runCatching { watermarkBmp?.recycle() }
            runCatching { decoder.stop(); decoder.release() }
            runCatching { encoder.stop(); encoder.release() }
            runCatching { extractor.release() }
            runCatching { if (muxStarted) { muxer.stop(); muxer.release() } else muxer.release() }
        }

        if (!success) runCatching { File(outputPath).delete() }
        return success
    }

    // ── 繪製：骨架 ──────────────────────────────────────────────
    private fun drawSkeleton(
        canvas: Canvas, landmarks: Array<LandmarkPoint?>,
        poseW: Float, poseH: Float, displayW: Int, displayH: Int, radius: Float,
    ) {
        val scaleX = displayW.toFloat() / poseW
        val scaleY = displayH.toFloat() / poseH
        for ((a, b) in CONNECTIONS) {
            val la = landmarks.getOrNull(a) ?: continue
            val lb = landmarks.getOrNull(b) ?: continue
            if (la.visibility < 0.3f || lb.visibility < 0.3f) continue
            linePaint.color = when {
                a == 16 || b == 16 -> Color.argb(210, 255, 50, 50)
                a in LEFT_LANDMARKS && b in LEFT_LANDMARKS -> Color.argb(210, 0, 230, 90)
                a in RIGHT_LANDMARKS && b in RIGHT_LANDMARKS && a != 16 && b != 16 -> Color.argb(210, 70, 150, 240)
                else -> Color.argb(210, 255, 215, 0)
            }
            canvas.drawLine(la.xPx * scaleX, la.yPx * scaleY, lb.xPx * scaleX, lb.yPx * scaleY, linePaint)
        }
        for ((i, lm) in landmarks.withIndex()) {
            if (lm == null || lm.visibility < 0.3f) continue
            dotPaint.color = when {
                i == 16 -> Color.argb(230, 255, 30, 30)
                i in LEFT_LANDMARKS -> Color.argb(230, 0, 200, 70)
                i in RIGHT_LANDMARKS && i != 16 -> Color.argb(230, 70, 140, 220)
                else -> Color.argb(230, 255, 200, 0)
            }
            canvas.drawCircle(lm.xPx * scaleX, lm.yPx * scaleY, radius, dotPaint)
        }
    }

    // ── 繪製：軌跡 ──────────────────────────────────────────────
    private fun drawTrajectory(canvas: Canvas, pts: List<Triple<Long, Int, Int>>) {
        for (i in 1 until pts.size) {
            canvas.drawLine(pts[i - 1].second.toFloat(), pts[i - 1].third.toFloat(),
                pts[i].second.toFloat(), pts[i].third.toFloat(), trajShadowPaint)
        }
        for (i in 1 until pts.size) {
            canvas.drawLine(pts[i - 1].second.toFloat(), pts[i - 1].third.toFloat(),
                pts[i].second.toFloat(), pts[i].third.toFloat(), trajLinePaint)
        }
        val last = pts.last()
        canvas.drawCircle(last.second.toFloat(), last.third.toFloat(), DOT_RADIUS, trajDotFill)
        canvas.drawCircle(last.second.toFloat(), last.third.toFloat(), DOT_RADIUS, trajDotBorder)
    }

    private fun drawTrajDot(canvas: Canvas, x: Int, y: Int) {
        canvas.drawCircle(x.toFloat(), y.toFloat(), DOT_RADIUS, trajDotFill)
    }

    // ── CSV 解析 / 平滑 / 查詢（同 SkeletonOverlayRenderer）──────
    private fun smoothFrameData(
        raw: Map<Int, Array<LandmarkPoint?>>, alpha: Float = 0.35f,
    ): Map<Int, Array<LandmarkPoint?>> {
        if (raw.size < 3) return raw
        val sorted = raw.keys.sorted()
        val result = raw.mapValues { (_, lms) -> lms.copyOf() }.toMutableMap()
        for (lmIdx in 0 until 33) {
            var px = Float.NaN; var py = Float.NaN
            for (key in sorted) {
                val lm = result[key]?.get(lmIdx) ?: continue
                if (px.isNaN()) { px = lm.xPx; py = lm.yPx; continue }
                px = alpha * lm.xPx + (1f - alpha) * px
                py = alpha * lm.yPx + (1f - alpha) * py
                result[key]!![lmIdx] = lm.copy(xPx = px, yPx = py)
            }
            px = Float.NaN; py = Float.NaN
            for (key in sorted.reversed()) {
                val lm = result[key]?.get(lmIdx) ?: continue
                if (px.isNaN()) { px = lm.xPx; py = lm.yPx; continue }
                px = alpha * lm.xPx + (1f - alpha) * px
                py = alpha * lm.yPx + (1f - alpha) * py
                result[key]!![lmIdx] = lm.copy(xPx = px, yPx = py)
            }
        }
        return result
    }

    private fun getSmoothedLandmarks(
        frameData: Map<Int, Array<LandmarkPoint?>>, targetIdx: Int, sortedKeys: List<Int>,
    ): Array<LandmarkPoint?>? {
        frameData[targetIdx]?.let { return it }
        val prevKey = sortedKeys.lastOrNull { it < targetIdx } ?: return null
        val nextKey = sortedKeys.firstOrNull { it > targetIdx } ?: return null
        val prevLms = frameData[prevKey] ?: return null
        val nextLms = frameData[nextKey] ?: return null
        val t = (targetIdx - prevKey).toFloat() / (nextKey - prevKey).toFloat()
        return Array(33) { i ->
            val a = prevLms[i]; val b = nextLms[i]
            when {
                a != null && b != null -> a.copy(
                    xPx = a.xPx + (b.xPx - a.xPx) * t,
                    yPx = a.yPx + (b.yPx - a.yPx) * t,
                    visibility = a.visibility * (1f - t) + b.visibility * t,
                )
                else -> a ?: b
            }
        }
    }

    private fun parseCsv(csvPath: String): Map<Int, Array<LandmarkPoint?>> {
        val file = File(csvPath)
        if (!file.exists()) return emptyMap()
        val result = mutableMapOf<Int, Array<LandmarkPoint?>>()
        file.bufferedReader().use { reader ->
            reader.readLine()
            var line = reader.readLine()
            while (line != null) {
                val cols = line.split(",")
                if (cols.size >= 201) {
                    val timeSec = cols[1].trim().toDoubleOrNull()
                    if (timeSec != null) {
                        val timeMs = (timeSec * 1000.0).roundToInt()
                        val landmarks = arrayOfNulls<LandmarkPoint>(33)
                        for (i in 0 until 33) {
                            val base = 3 + i * 6
                            val xNorm = cols[base + 0].trim().toFloatOrNull()?.takeIf { !it.isNaN() }
                            val yNorm = cols[base + 1].trim().toFloatOrNull()?.takeIf { !it.isNaN() }
                            val vis   = cols[base + 3].trim().toFloatOrNull() ?: 0f
                            val xPx   = cols[base + 4].trim().toFloatOrNull()?.takeIf { !it.isNaN() }
                            val yPx   = cols[base + 5].trim().toFloatOrNull()?.takeIf { !it.isNaN() }
                            if (xNorm != null && yNorm != null && xPx != null && yPx != null && xNorm > 0f && yNorm > 0f) {
                                landmarks[i] = LandmarkPoint(xPx, yPx, xNorm, yNorm, vis)
                            }
                        }
                        result[timeMs] = landmarks
                    }
                }
                line = reader.readLine()
            }
        }
        return result
    }

    private fun inferPoseImageSize(frameData: Map<Int, Array<LandmarkPoint?>>): Pair<Float, Float>? {
        for ((_, landmarks) in frameData) {
            for (lm in landmarks) {
                if (lm != null && lm.xNorm > 0.05f && lm.yNorm > 0.05f) {
                    val imgW = lm.xPx / lm.xNorm; val imgH = lm.yPx / lm.yNorm
                    if (imgW > 50f && imgH > 50f) return imgW to imgH
                }
            }
        }
        return null
    }

    // ── 編碼器排空（同 SkeletonOverlayRenderer）─────────────────
    private fun drainEncoder(
        encoder: MediaCodec, muxer: MediaMuxer, info: MediaCodec.BufferInfo,
        setTrack: (Int) -> Unit, getTrack: () -> Int, isMuxed: () -> Boolean,
        eos: Boolean, onSampleWritten: () -> Unit = {},
    ) {
        var tryAgainCount = 0; var drainedSamples = 0; val maxTryAgain = 50
        while (true) {
            val idx = encoder.dequeueOutputBuffer(info, 10_000L)
            when {
                idx == MediaCodec.INFO_TRY_AGAIN_LATER -> {
                    tryAgainCount++
                    if (eos && tryAgainCount > maxTryAgain) break
                    if (!eos) break
                }
                idx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    if (!isMuxed()) { val t = muxer.addTrack(encoder.outputFormat); muxer.start(); setTrack(t) }
                }
                idx >= 0 -> {
                    tryAgainCount = 0
                    val buf = encoder.getOutputBuffer(idx)
                    if (buf != null && info.size > 0 && isMuxed()) {
                        buf.position(info.offset); buf.limit(info.offset + info.size)
                        muxer.writeSampleData(getTrack(), buf, info)
                        onSampleWritten(); drainedSamples++
                    }
                    encoder.releaseOutputBuffer(idx, false)
                    if ((info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) break
                }
            }
        }
    }
}
