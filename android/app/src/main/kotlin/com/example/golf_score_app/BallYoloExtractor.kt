package com.example.golf_score_app

import android.content.res.AssetManager
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.util.Log
import kotlin.math.sqrt

/**
 * YOLOv8 球偵測提取器。
 *
 * 使用與 BallBlobExtractor 相同的 MediaExtractor + MediaCodec 影片解碼管線，
 * 但以 BallYoloDetector（TFLite YOLOv8n int8）取代像素差 BFS 偵測。
 *
 * 回傳格式與 BallBlobExtractor.extract() 完全相同，可無縫替換：
 * {
 *   "fps"    : Double,
 *   "width"  : Int,   // display-space
 *   "height" : Int,
 *   "frames" : List<Map> {
 *       "ptsUs" : Long,
 *       "blobs" : List<Map> {
 *           "cx"       : Int,     // display-space
 *           "cy"       : Int,
 *           "area"     : Int,     // bbox 面積（px²）
 *           "circ"     : Double,  // 固定 1.0（YOLO 偵測到球）
 *           "diffMean" : Double,  // confidence × 50.0（供 BallTracker 評分）
 *       }
 *   }
 * }
 *
 * 若模型載入失敗，extract() 回傳 null，呼叫端應 fallback 至 BallBlobExtractor。
 */
class BallYoloExtractor(assetManager: AssetManager) {

    companion object {
        private const val TAG = "BallYoloExtractor"

        // 預設 ROI 中心（相對比例），與 Dart BallTracker 一致
        // ROI_RATIO_Y: 球在球座上時位於畫面下方約 78%（y≈1498 on 1920px frame）
        // 舊值 0.5646 → tile y[764,1404]，球在 y≈1574 → tile 外面！
        private const val ROI_RATIO_X  = 0.6519f
        private const val ROI_RATIO_Y  = 0.78f

        // 連續 miss 超過此幀數後重置 ROI 至預設位置（僅用於擊球前）
        private const val MAX_MISS_FRAMES = 5

        // 擊球前 ROI 最大移動距離（px）
        private const val MAX_ROI_SHIFT_PRE  = 200f
        // 擊球後 ROI 最大移動距離（px）：球速快，允許更大跳躍
        private const val MAX_ROI_SHIFT_POST = 300f

        // YOLO 信心門檻：擊球前嚴格 / 擊球後放寬（允許高速小球通過）
        private const val CONF_PRE_IMPACT  = 0.25f
        private const val CONF_POST_IMPACT = 0.05f

        // ── 擊球後 ROI 上升追蹤（post-impact ascending scan）──────
        // 高爾夫球擊球後在畫面中以約 120-180px/frame 的速度向上飛行（@30fps 側面鏡頭）
        // 每幀 miss → ROI 向上移動 POST_IMPACT_CHASE_DY px 以追蹤飛球
        private const val POST_IMPACT_CHASE_DY   = 150f  // 每幀向上移動量（px）
        private const val POST_IMPACT_CHASE_DX   = 0f    // 水平漂移（px，0=純垂直追蹤）
        private const val POST_IMPACT_MAX_FRAMES = 20    // 最多追蹤 20 幀（≈0.67s @30fps）
    }

    private val detector = BallYoloDetector(assetManager)

    // ── ROI 追蹤狀態 ────────────────────────────────────────────
    private var roiCx             = -1f   // frame 座標，-1 表示尚未初始化
    private var roiCy             = -1f
    private var missCount         = 0     // 目前連續 miss 幀數
    private var lastGoodCx        = -1f   // 最後一次可信偵測的球位置（miss reset 時優先回到此位置）
    private var lastGoodCy        = -1f
    private var postImpactMisses  = 0     // 擊球後連續 miss 幀數（用於上升追蹤計數）
    /** true 代表模型已成功載入。 */
    fun tryLoadModel(): Boolean = detector.tryLoad()

    // ────────────────────────────────────────────────────────────

    fun extract(
        inputPath: String,
        hitSec: Double? = null,
        onProgress: ((op: String, progress: Double, label: String, current: Int, total: Int) -> Unit)? = null,
    ): Map<String, Any>? {

        if (!detector.isLoaded) {
            Log.w(TAG, "YOLO model not loaded, skipping")
            return null
        }
        // 每次新的 extract() 呼叫都重置 ROI 追蹤狀態
        roiCx            = -1f
        roiCy            = -1f
        missCount        = 0
        lastGoodCx       = -1f
        lastGoodCy       = -1f
        postImpactMisses = 0

        if (!java.io.File(inputPath).exists()) {
            Log.w(TAG, "File not found: $inputPath")
            return null
        }

        // ── MediaExtractor ──────────────────────────────────────
        val extractor = MediaExtractor()
        try { extractor.setDataSource(inputPath) }
        catch (e: Exception) { Log.e(TAG, "Cannot open: $e"); return null }

        var videoTrack   = -1
        var inputFormat: MediaFormat? = null
        for (i in 0 until extractor.trackCount) {
            val fmt = extractor.getTrackFormat(i)
            if ((fmt.getString(MediaFormat.KEY_MIME) ?: "").startsWith("video/")) {
                videoTrack = i; inputFormat = fmt; break
            }
        }
        if (videoTrack < 0 || inputFormat == null) {
            Log.e(TAG, "No video track"); extractor.release(); return null
        }
        extractor.selectTrack(videoTrack)

        val videoW    = inputFormat.getInteger(MediaFormat.KEY_WIDTH)
        val videoH    = inputFormat.getInteger(MediaFormat.KEY_HEIGHT)
        val videoMime = inputFormat.getString(MediaFormat.KEY_MIME) ?: "video/avc"
        val fps = runCatching {
            inputFormat.getInteger(MediaFormat.KEY_FRAME_RATE).toDouble()
        }.getOrElse { 30.0 }

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

        val displayW = if (rotation == 90 || rotation == 270) videoH else videoW
        val displayH = if (rotation == 90 || rotation == 270) videoW else videoH

        // 計算擊球幀（-1 表示未知）
        val hitFrame = if (hitSec != null && fps > 0) (hitSec * fps).toInt() else -1
        Log.d(TAG, "Video: ${videoW}x${videoH} → ${displayW}x${displayH} fps=$fps rot=$rotation° hitFrame=$hitFrame")

        // ── Decoder ─────────────────────────────────────────────
        val decoder = try { MediaCodec.createDecoderByType(videoMime) }
        catch (e: Exception) { Log.e(TAG, "Cannot create decoder: $e"); extractor.release(); return null }
        decoder.configure(inputFormat, null, null, 0)
        decoder.start()

        val frameList  = mutableListOf<Map<String, Any>>()
        val bufInfo    = MediaCodec.BufferInfo()
        var inputEos   = false
        var frameCount = 0

        try {
            while (true) {
                // ── 餵輸入 ────────────────────────────────────
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

                // ── 取輸出 ────────────────────────────────────
                val outIdx = decoder.dequeueOutputBuffer(bufInfo, 10_000L)
                if (outIdx == MediaCodec.INFO_TRY_AGAIN_LATER)    continue
                if (outIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) continue
                if (outIdx < 0)                                      continue

                val image = runCatching { decoder.getOutputImage(outIdx) }.getOrNull()
                if (image == null) {
                    decoder.releaseOutputBuffer(outIdx, false)
                    if ((bufInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) break
                    continue
                }

                try {
                    val pts    = bufInfo.presentationTimeUs

                    // ── 取 YUV 三個平面（供 YUV→RGB 轉換，提升球偵測準確率）──
                    val yPlane  = image.planes[0]
                    val uPlane  = image.planes[1]
                    val vPlane  = image.planes[2]
                    val yBuf    = yPlane.buffer
                    val uBuf    = uPlane.buffer
                    val vBuf    = vPlane.buffer
                    val yRaw    = ByteArray(videoH * yPlane.rowStride)
                    val uRaw    = ByteArray(uBuf.remaining())
                    val vRaw    = ByteArray(vBuf.remaining())
                    yBuf.get(yRaw); uBuf.get(uRaw); vBuf.get(vRaw)

                    // ── 首幀初始化 ROI ──────────────────────────
                    if (roiCx < 0f) {
                        roiCx = videoW * ROI_RATIO_X
                        roiCy = videoH * ROI_RATIO_Y
                        Log.d(TAG, "ROI init: (${roiCx.toInt()}, ${roiCy.toInt()}) " +
                            "from ratios ($ROI_RATIO_X, $ROI_RATIO_Y) frame=${videoW}x${videoH}")
                    }

                    // ── 依擊球位置決定動態參數 ──────────────────────
                    val isPostImpact = hitFrame >= 0 && frameCount >= hitFrame
                    val maxShift     = if (isPostImpact) MAX_ROI_SHIFT_POST else MAX_ROI_SHIFT_PRE
                    val confThresh   = if (isPostImpact) CONF_POST_IMPACT  else CONF_PRE_IMPACT

                    // ── YOLO 推論（ROI crop，RGB 輸入）───────────
                    val codedDets = detector.detect(
                        yRaw, yPlane.rowStride,
                        uRaw, uPlane.rowStride, uPlane.pixelStride,
                        vRaw, vPlane.rowStride, vPlane.pixelStride,
                        videoW, videoH,
                        roiCx.toInt(), roiCy.toInt(),
                        confThreshold = confThresh,
                    )

                    // ── 更新 ROI 追蹤狀態 ────────────────────────
                    if (codedDets.isNotEmpty()) {
                        // 選最高 confidence 的偵測，但限制移動距離（防止跳至誤偵測）
                        // 先找距目前 ROI 最近且在 maxShift 範圍內的偵測
                        val nearby = codedDets.filter { d ->
                            val dx = d[0] - roiCx; val dy = d[1] - roiCy
                            kotlin.math.sqrt((dx * dx + dy * dy).toDouble()) <= maxShift
                        }
                        if (nearby.isNotEmpty()) {
                            // 在 ROI 範圍內，取最高 confidence
                            val best = nearby.maxByOrNull { it[4] }!!
                            roiCx            = best[0]
                            roiCy            = best[1]
                            lastGoodCx       = best[0]  // 記錄最後可信球位
                            lastGoodCy       = best[1]
                            missCount        = 0
                            postImpactMisses = 0         // 找到球：重置上升追蹤計數
                        } else {
                            // 所有偵測都超出 maxShift（可能都是誤偵測），不更新 ROI
                            missCount++
                            _handleMiss(frameCount, isPostImpact, videoW, videoH)
                        }
                    } else {
                        missCount++
                        _handleMiss(frameCount, isPostImpact, videoW, videoH)
                    }

                    // [DEBUG] 每 30 幀 log 一次偵測結果
                    if (frameCount % 30 == 0) {
                        Log.d(TAG, "[YOLO] frame=$frameCount roi=(${roiCx.toInt()},${roiCy.toInt()}) " +
                            "dets=${codedDets.size} miss=$missCount " +
                            codedDets.take(3).joinToString { d ->
                                "(cx=${d[0].toInt()},cy=${d[1].toInt()},conf=${"%.2f".format(d[4])})"
                            })
                    }

                    // 轉換到 display-space
                    val blobs: List<Map<String, Any>> = if (rotation == 0) {
                        codedDets.map { d ->
                            mapOf(
                                "cx"       to d[0].toInt(),
                                "cy"       to d[1].toInt(),
                                // YOLO bbox 面積 ÷ 16 正規化為 blob-comparable area（6..150）
                                // BallTracker _areaHiBase=150 以 blob pixel-count 為基準；
                                // YOLO bbox 通常比 blob 大 ~16x（全球 vs 像素差遮罩），故除以 16
                                "area"     to ((d[2] * d[3] / 16f).toInt()).coerceIn(6, 150),
                                "circ"     to 1.0,
                                "diffMean" to (d[4] * 50.0).toDouble(),
                            )
                        }
                    } else {
                        codedDets.map { d ->
                            val (dx, dy) = codedToDisplay(d[0].toInt(), d[1].toInt(), videoW, videoH, rotation)
                            mapOf(
                                "cx"       to dx,
                                "cy"       to dy,
                                // YOLO bbox 面積 ÷ 16 正規化為 blob-comparable area（6..150）
                                // BallTracker _areaHiBase=150 以 blob pixel-count 為基準；
                                // YOLO bbox 通常比 blob 大 ~16x（全球 vs 像素差遮罩），故除以 16
                                "area"     to ((d[2] * d[3] / 16f).toInt()).coerceIn(6, 150),
                                "circ"     to 1.0,
                                "diffMean" to (d[4] * 50.0).toDouble(),
                            )
                        }
                    }

                    frameList.add(mapOf("ptsUs" to pts, "blobs" to blobs))
                    frameCount++

                    if (frameCount % 10 == 0 && totalFrames > 0) {
                        val prog = (frameCount.toDouble() / totalFrames).coerceIn(0.0, 0.95)
                        onProgress?.invoke(
                            "extractBlobs", prog,
                            "球追蹤分析中 ${(prog * 100).toInt()}% [YOLOv8]",
                            frameCount, totalFrames,
                        )
                    }

                } finally {
                    image.close()
                    decoder.releaseOutputBuffer(outIdx, false)
                }

                if ((bufInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) break
            }

        } catch (e: Exception) {
            Log.e(TAG, "YOLO extract failed: $e", e)
        } finally {
            runCatching { decoder.stop(); decoder.release() }
            runCatching { extractor.release() }
        }

        val totalDets = frameList.sumOf { (it["blobs"] as List<*>).size }
        val framesWithDets = frameList.count { (it["blobs"] as List<*>).isNotEmpty() }
        Log.d(TAG, "YOLO done: ${frameList.size} frames, $totalDets detections, " +
            "$framesWithDets frames with hits (${frameList.size.let { if (it>0) framesWithDets*100/it else 0 }}%)")
        onProgress?.invoke("extractBlobs", 1.0, "球追蹤分析完成 [YOLOv8]", frameCount, frameCount)

        return mapOf(
            "fps"    to fps,
            "width"  to displayW,
            "height" to displayH,
            "frames" to frameList,
        )
    }

    // ────────────────────────────────────────────────────────────

    /**
     * 處理單幀無有效偵測的情況。
     *
     * 擊球前：連續 miss 超過 MAX_MISS_FRAMES 後重置 ROI 至最後可信球位（或 preset）。
     * 擊球後：不重置，改為每幀讓 ROI 向上移動 POST_IMPACT_CHASE_DY px（追蹤飛行中的球）。
     *         追蹤超過 POST_IMPACT_MAX_FRAMES 幀仍未找到球才停止。
     */
    private fun _handleMiss(frameCount: Int, isPostImpact: Boolean, videoW: Int, videoH: Int) {
        if (isPostImpact) {
            // ── 擊球後：上升追蹤模式 ────────────────────────────
            postImpactMisses++
            if (postImpactMisses <= POST_IMPACT_MAX_FRAMES) {
                val prevCy = roiCy
                // 每幀向上（y 遞減）並可選水平漂移，clamp 到 tile 不超出畫面邊界
                roiCx += POST_IMPACT_CHASE_DX
                roiCy -= POST_IMPACT_CHASE_DY
                val halfTile = BallYoloDetector.INPUT_SIZE / 2f
                roiCx = roiCx.coerceIn(halfTile, videoW - halfTile)
                roiCy = roiCy.coerceAtLeast(halfTile)
                Log.d(TAG, "post-impact chase↑ frame=$frameCount miss=$postImpactMisses " +
                    "roi=(${roiCx.toInt()},${prevCy.toInt()}) → (${roiCx.toInt()},${roiCy.toInt()})")
            } else {
                // 追蹤超時，放棄本次上升掃描（保留最後 ROI 位置，不再移動）
                Log.d(TAG, "post-impact chase timeout @ frame=$frameCount (>$POST_IMPACT_MAX_FRAMES frames without ball)")
            }
        } else {
            // ── 擊球前：原有重置邏輯 ────────────────────────────
            if (missCount >= MAX_MISS_FRAMES) {
                val prevCx = roiCx; val prevCy = roiCy
                if (lastGoodCx >= 0f) {
                    roiCx = lastGoodCx
                    roiCy = lastGoodCy
                    Log.d(TAG, "ROI reset after $MAX_MISS_FRAMES misses → lastGood: " +
                        "(${prevCx.toInt()},${prevCy.toInt()}) → " +
                        "(${roiCx.toInt()},${roiCy.toInt()})")
                } else {
                    roiCx = videoW * ROI_RATIO_X
                    roiCy = videoH * ROI_RATIO_Y
                    Log.d(TAG, "ROI reset after $MAX_MISS_FRAMES misses (no lastGood): " +
                        "(${prevCx.toInt()},${prevCy.toInt()}) → " +
                        "(${roiCx.toInt()},${roiCy.toInt()})")
                }
                missCount = 0
            }
        }
    }

    // ────────────────────────────────────────────────────────────

    private fun codedToDisplay(
        cx: Int, cy: Int, w: Int, h: Int, rotation: Int,
    ): Pair<Int, Int> = when (rotation) {
        90  -> Pair(h - 1 - cy, cx)
        270 -> Pair(cy, w - 1 - cx)
        180 -> Pair(w - 1 - cx, h - 1 - cy)
        else -> Pair(cx, cy)
    }
}
