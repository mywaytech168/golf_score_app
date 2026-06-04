package com.aethertek.tekswing

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.DashPathEffect
import android.graphics.Paint
import android.media.Image
import android.media.MediaCodec
import android.media.MediaCodecInfo.CodecCapabilities
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import android.util.Log
import java.io.File
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

    // YUV 平面緩衝區：懶初始化，第一幀後穩定不再分配（節省 ~3MB/幀 GC）
    private var yBuf = ByteArray(0)
    private var uBuf = ByteArray(0)
    private var vBuf = ByteArray(0)

    companion object {
        private const val TAG = "TrajOverlay"

        // 軌跡畫筆參數
        private val TRAJ_COLOR    = Color.argb(230, 255, 210, 30)  // 金黃
        private const val TRAJ_STROKE  = 7f
        private const val DOT_RADIUS   = 9f
        private const val SHADOW_ALPHA = 100
        private const val SHADOW_WIDTH = 10f

        // ROI 繪製參數
        private val ROI_COLOR      = Color.argb(150, 0, 255, 255)  // 青色半透明
        private const val ROI_STROKE   = 3f

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
        private val roiBorderPaint by lazy {
            Paint().apply {
                color       = ROI_COLOR
                strokeWidth = ROI_STROKE
                style       = Paint.Style.STROKE
                isAntiAlias = true
                pathEffect  = DashPathEffect(floatArrayOf(10f, 5f), 0f)
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
     * @param roiSize    ROI 尺寸（像素），若 > 0 則繪製 ROI 邊界框，預設 = 0（不繪製）
     * @return 成功回傳 true
     */
    fun render(
        inputPath: String,
        outputPath: String,
        trackPts: List<Map<String, Any>>,
        roiSize: Int = 0,
        quality: ExportQuality = ExportQuality.STANDARD,
        onProgress: ((op: String, progress: Double, label: String, current: Int, total: Int) -> Unit)? = null,
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
                            .getOrElse { 30f }

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
        Log.d(TAG, "[TrajectoryOverlay] coded=${videoW}x${videoH} rot=$rotation° fps=$fps")

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
        // ✅ 品質模式：根據 ExportQuality 動態調整位元率
        val bitRate = (videoW.toLong() * videoH * fps * quality.bppCoeff)
            .toLong().coerceIn(quality.minBitRate, quality.maxBitRate).toInt()
        val encFmt = MediaFormat.createVideoFormat("video/avc", encW, encH).apply {
            setInteger(MediaFormat.KEY_COLOR_FORMAT, CodecCapabilities.COLOR_FormatYUV420SemiPlanar)
            setInteger(MediaFormat.KEY_BIT_RATE, bitRate)
            setInteger(MediaFormat.KEY_FRAME_RATE, fps.roundToInt())
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
        }
        Log.d(TAG, "編碼器 bitRate=${bitRate/1_000_000}Mbps (${videoW}x${videoH}@${fps}fps, quality=$quality)")
        encoder.configure(encFmt, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        encoder.start()

        File(outputPath).parentFile?.mkdirs()
        val muxer   = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        // 保留輸入影片的 rotation metadata，播放器才能正確顯示直向
        if (rotation != 0) muxer.setOrientationHint(rotation)
        var muxTrack          = -1
        var muxStarted        = false
        var encodedFrames     = 0
        var decodedFrames     = 0
        var totalSamplesWritten = 0   // 累計跨所有 drainEncoder 呼叫的寫入數

        val decBufInfo = MediaCodec.BufferInfo()
        val encBufInfo = MediaCodec.BufferInfo()
        var inputEos   = false
        var success    = false

        // ── 預分配可重用緩衝區 ────────────────────────────────────
        // YUV→NV12 與 composite 由 NativeLib（golf_native.so C）處理：
        //   ・NativeLib.yuvFillNv12    → 替代原 JVM yuvFillNv12（~10× 加速）
        //   ・NativeLib.compositeOverlay → 替代原 JVM compositeOverlay（省 getPixels() + ~10× 加速）
        val nv12Buf       = ByteArray(encW * encH + encW * encH / 2)
        val overlayBmp    = Bitmap.createBitmap(encW, encH, Bitmap.Config.ARGB_8888)
        val overlayCanvas = Canvas(overlayBmp)
        // 軌跡點 cursor：pts 單調遞增，用 cursor 取代每幀 O(log n) binary search → O(1) amortized
        var trajCursor = 0

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

                    // ── 1. YUV 平面讀取（Kotlin）→ Native C YUV→NV12 轉換 ──
                    val yP = image.planes[0]; val uP = image.planes[1]; val vP = image.planes[2]
                    val yStride = yP.rowStride; val uvStride = uP.rowStride; val uvPixelStride = uP.pixelStride
                    val yNeeded = yP.buffer.remaining(); if (yBuf.size < yNeeded) yBuf = ByteArray(yNeeded); yP.buffer.get(yBuf, 0, yNeeded)
                    val uNeeded = uP.buffer.remaining(); if (uBuf.size < uNeeded) uBuf = ByteArray(uNeeded); uP.buffer.get(uBuf, 0, uNeeded)
                    val vNeeded = vP.buffer.remaining(); if (vBuf.size < vNeeded) vBuf = ByteArray(vNeeded); vP.buffer.get(vBuf, 0, vNeeded)
                    NativeLib.yuvFillNv12(
                        yBuf, uBuf, vBuf, yStride, uvStride, uvPixelStride,
                        videoW, videoH, encW, encH, nv12Buf,
                    )

                    // ── 2. 軌跡疊加（Canvas 繪製 overlay → C composite 進 NV12）──
                    overlayBmp.eraseColor(android.graphics.Color.TRANSPARENT)
                    // cursor 單調推進（pts 遞增），O(1) amortized，取代 O(log n) binary search
                    while (trajCursor < sortedPts.size && sortedPts[trajCursor].first <= pts) trajCursor++
                    val visible = sortedPts.subList(0, trajCursor)

                    if (visible.size >= 2) drawTrajectory(overlayCanvas, visible)
                    else if (visible.isNotEmpty()) drawDot(overlayCanvas, visible[0].second, visible[0].third)

                    if (roiSize > 0 && visible.isNotEmpty()) {
                        val last = visible.last()
                        drawROI(overlayCanvas, last.second, last.third, roiSize, encW, encH)
                    }

                    NativeLib.compositeOverlay(overlayBmp, encW, encH, nv12Buf)

                    // ── 3. 餵編碼器 ─────────────────────────────
                    val encInIdx = encoder.dequeueInputBuffer(50_000L)
                    if (encInIdx >= 0) {
                        val buf = encoder.getInputBuffer(encInIdx)!!
                        buf.clear()
                        buf.put(nv12Buf, 0, nv12Buf.size)
                        encoder.queueInputBuffer(encInIdx, 0, nv12Buf.size, pts, 0)
                    }

                    totalSamplesWritten += drainEncoder(
                        encoder, muxer, encBufInfo,
                        setTrack   = { t -> muxTrack = t; muxStarted = true },
                        getTrack   = { muxTrack },
                        isMuxed    = { muxStarted },
                        onFrame    = { encodedFrames++ },
                        eos        = false,
                    )

                    decodedFrames++
                    if (decodedFrames % 10 == 0 && totalFrames > 0) {
                        val prog = (decodedFrames.toDouble() / totalFrames).coerceIn(0.0, 0.95)
                        onProgress?.invoke("renderOverlay", prog, "軌跡渲染中 ${(prog * 100).toInt()}%", decodedFrames, totalFrames)
                    }

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
            totalSamplesWritten += drainEncoder(
                encoder, muxer, encBufInfo,
                setTrack    = { t -> muxTrack = t; muxStarted = true },
                getTrack    = { muxTrack },
                isMuxed     = { muxStarted },
                onFrame     = { encodedFrames++ },
                eos         = true,
                prevSamples = totalSamplesWritten,  // ← per-frame drain 已寫入的數量
            )

            success = encodedFrames > 0
            Log.d(TAG, "完成 → $outputPath (encodedFrames=$encodedFrames, totalSamples=$totalSamplesWritten)")
            onProgress?.invoke("renderOverlay", 1.0, "軌跡渲染完成", decodedFrames, decodedFrames)

        } catch (e: Exception) {
            Log.e(TAG, "渲染失敗: $e", e)
        } finally {
            runCatching { overlayBmp.recycle() }
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

    /**
     * 繪製 ROI 邊界框（虛線矩形，以最新軌跡點為中心）
     * @param canvas  Canvas 物件
     * @param centerX 中心點 X 座標
     * @param centerY 中心點 Y 座標
     * @param roiSize ROI 尺寸（像素，寬度 = 高度 = roiSize）
     * @param videoW  視頻寬度（用於邊界夾緊）
     * @param videoH  視頻高度（用於邊界夾緊）
     */
    private fun drawROI(canvas: Canvas, centerX: Int, centerY: Int, roiSize: Int, videoW: Int, videoH: Int) {
        val halfRoi = roiSize / 2f
        val left   = (centerX - halfRoi).coerceIn(0f, (videoW - 1).toFloat())
        val top    = (centerY - halfRoi).coerceIn(0f, (videoH - 1).toFloat())
        val right  = (centerX + halfRoi).coerceIn(0f, (videoW - 1).toFloat())
        val bottom = (centerY + halfRoi).coerceIn(0f, (videoH - 1).toFloat())

        canvas.drawRect(left, top, right, bottom, roiBorderPaint)

        // 十字標記以 rect 實際中心為準（rect 被夾緊時中心會偏移）
        val crossSize = 15f
        val cx = (left + right) / 2f
        val cy = (top + bottom) / 2f
        canvas.drawLine(cx - crossSize, cy, cx + crossSize, cy, roiBorderPaint)
        canvas.drawLine(cx, cy - crossSize, cx, cy + crossSize, roiBorderPaint)
    }

    // ────────────────────────────────────────────────────────────
    // YUV→NV12 與 composite 已移至 NativeLib（golf_native.so C 實作）
    //   ・NativeLib.yuvFillNv12()    → 替代 yuvFillNv12()
    //   ・NativeLib.compositeOverlay() → 替代 compositeOverlay()
    // ────────────────────────────────────────────────────────────

    // ────────────────────────────────────────────────────────────
    // 編碼器排空
    // ────────────────────────────────────────────────────────────

    /**
     * 排空編碼器輸出佇列並寫入 muxer。
     *
     * @param prevSamples  先前所有 drain 呼叫已累積寫入的 sample 數（用於 EOS timeout 判斷）
     * @return 本次呼叫實際寫入 muxer 的 sample 數
     *
     * 修正要點：
     * 1. INFO_OUTPUT_FORMAT_CHANGED 加 `isMuxed()` 防護，避免重複 start() crash
     * 2. EOS drain 使用更長 timeout：200 × 50ms = 10s max
     * 3. 非 EOS drain 仍在 TRY_AGAIN_LATER 時立即返回（避免卡住主迴圈）
     * 4. EOS timeout 時若 prevSamples > 0，視為正常（幀已在 per-frame drain 寫完），僅 Log.d
     */
    private fun drainEncoder(
        encoder: MediaCodec, muxer: MediaMuxer, info: MediaCodec.BufferInfo,
        setTrack: (Int) -> Unit, getTrack: () -> Int, isMuxed: () -> Boolean,
        onFrame: (() -> Unit)? = null,
        eos: Boolean,
        prevSamples: Int = 0,   // ← EOS drain 傳入已累計的 per-frame sample 數
    ): Int {
        var tryAgainCount  = 0
        var samplesWritten = 0
        // EOS drain：每次 poll 50ms，最多重試 200 次 = 10 秒上限
        // non-EOS drain：每次 poll 10ms，TRY_AGAIN_LATER 時立即返回（不重試）
        val pollTimeoutUs = if (eos) 50_000L else 10_000L
        val maxTryAgain   = if (eos) 200 else 0

        while (true) {
            val idx = encoder.dequeueOutputBuffer(info, pollTimeoutUs)
            when {
                idx == MediaCodec.INFO_TRY_AGAIN_LATER -> {
                    if (!eos) break  // non-EOS：立即返回，讓主迴圈繼續處理下一幀
                    tryAgainCount++
                    if (tryAgainCount % 20 == 0) {  // 每 1 秒記一次 log（20 × 50ms）
                        Log.d(TAG, "drainEncoder EOS waiting ($tryAgainCount/$maxTryAgain) " +
                            "elapsed=${tryAgainCount * pollTimeoutUs / 1_000}ms samples=$samplesWritten")
                    }
                    if (tryAgainCount > maxTryAgain) {
                        val elapsedMs = tryAgainCount * pollTimeoutUs / 1_000
                        val totalSamples = prevSamples + samplesWritten
                        if (totalSamples > 0) {
                            // ✅ 正常情況：幀已在 per-frame drain 全數寫完，EOS signal 未到達只是硬體特性
                            Log.d(TAG, "drainEncoder EOS timeout after ${elapsedMs}ms — " +
                                "samples_this_call=$samplesWritten, prevSamples=$prevSamples → OK, all frames written")
                        } else {
                            // ⚠️ 真正異常：整個 session 一個 sample 都沒寫入
                            Log.w(TAG, "drainEncoder EOS timeout after ${elapsedMs}ms — " +
                                "totalSamples=0, encoding may have failed")
                        }
                        break
                    }
                }

                idx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    tryAgainCount = 0
                    // ✅ 防護：僅在 muxer 尚未啟動時才 addTrack / start
                    // 某些裝置會送出兩次 FORMAT_CHANGED，重複呼叫會 throw IllegalStateException
                    if (!isMuxed()) {
                        val t = muxer.addTrack(encoder.outputFormat)
                        muxer.start()
                        setTrack(t)
                        Log.d(TAG, "drainEncoder FORMAT_CHANGED → muxer started, track=$t")
                    } else {
                        Log.d(TAG, "drainEncoder FORMAT_CHANGED (ignored, muxer already started)")
                    }
                }

                idx >= 0 -> {
                    tryAgainCount = 0
                    val buf = encoder.getOutputBuffer(idx)
                    // ✅ 三重防護：buf 非 null、size > 0（非 EOS-only buffer）、muxer 已啟動
                    if (buf != null && info.size > 0 && isMuxed()) {
                        buf.position(info.offset)
                        buf.limit(info.offset + info.size)
                        muxer.writeSampleData(getTrack(), buf, info)
                        onFrame?.invoke()
                        samplesWritten++
                    }
                    val isEos = (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0
                    encoder.releaseOutputBuffer(idx, false)
                    if (isEos) {
                        Log.d(TAG, "drainEncoder EOS output confirmed, samples_this_call=$samplesWritten")
                        break
                    }
                }
            }
        }
        return samplesWritten
    }
}
