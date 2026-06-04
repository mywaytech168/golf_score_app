package com.aethertek.tekswing

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

        // ROI 中心比例（coded 空間，對應 Python FIXED_ROI_CENTER=(1149,406) in 1920×1080）
        // Python workflow: coded 1920×1080 → FLIP_MODE=5(CCW) → algorithm 1920×1080 → FIXED_ROI_CENTER
        private const val ROI_CODED_X  = 1149f / 1920f  // ≈ 0.5984
        private const val ROI_CODED_Y  = 406f  / 1080f  // ≈ 0.3759

        // 連續 miss 超過此幀數後重置 ROI 至預設位置（僅用於擊球前）
        private const val MAX_MISS_FRAMES = 5

        // 擊球前 ROI 最大移動距離（px）
        private const val MAX_ROI_SHIFT_PRE  = 200f
        // 擊球後 ROI 最大移動距離（px）：球速快，允許更大跳躍
        private const val MAX_ROI_SHIFT_POST = 300f

        // YOLO 信心門檻：擊球前嚴格 / 擊球後放寬（允許高速小球通過）
        private const val CONF_PRE_IMPACT  = 0.25f
        private const val CONF_POST_IMPACT = 0.05f

        // tile 邊緣排除距離：擊球前 20f（適中），擊球後 8f（球靠近 tile 邊緣仍可偵測）
        private const val TILE_MARGIN_PRE  = 20f
        private const val TILE_MARGIN_POST = 8f

        // ── 擊球後 ROI 速度追蹤（post-impact velocity chase）──────
        // 使用最近偵測到的速度向量預測下一幀 ROI 位置，而非固定上移
        // 若尚無速度向量，預設向上 POST_IMPACT_CHASE_DY_DEFAULT px
        private const val POST_IMPACT_CHASE_DY_DEFAULT = 150f  // 無速度時的預設向上量（px）
        private const val POST_IMPACT_MAX_FRAMES = 35          // 最多追蹤 35 幀（≈1.17s @30fps）

        // 擊球後 miss 超過此幀數時，在速度預測位置額外執行第二次推論（雙 ROI 搜尋）
        private const val DUAL_ROI_MISS_THRESHOLD = 2
    }

    private val detector = BallYoloDetector(assetManager)

    // YUV 平面緩衝區：懶初始化，第一幀後穩定不再分配（節省 ~3MB/幀 GC）
    private var yRawBuf = ByteArray(0)
    private var uRawBuf = ByteArray(0)
    private var vRawBuf = ByteArray(0)

    // ── ROI 追蹤狀態 ────────────────────────────────────────────
    private var roiCx             = -1f   // coded 空間座標，-1 表示尚未初始化
    private var roiCy             = -1f
    private var missCount         = 0     // 目前連續 miss 幀數
    private var lastGoodCx        = -1f   // 最後一次可信偵測的球位置（miss reset 時優先回到此位置）
    private var lastGoodCy        = -1f
    private var postImpactMisses  = 0     // 擊球後連續 miss 幀數（用於速度追蹤計數）
    // 速度向量：由最後兩次成功偵測計算，miss 時用來預測下一幀 ROI 位置
    private var chaseVelX         = 0f
    private var chaseVelY         = -POST_IMPACT_CHASE_DY_DEFAULT  // 預設向上
    private var prevDetCx         = -1f   // 上一次成功偵測的位置（用於計算速度）
    private var prevDetCy         = -1f
    private var prevDetFrame      = -1    // 上一次成功偵測的幀號（用於 frameGap 修正速度）

    // ── 目前 extract() 的影片參數（供 _handleMiss 使用）────────
    private var _videoW    = 0
    private var _videoH    = 0
    private var _rotation  = 0
    private var _hasVelocity = false  // 至少計算過一次速度向量（第 2 次偵測後）

    /** coded 空間 ROI 中心（Python FIXED_ROI_CENTER=(1149,406) in 1920×1080）*/
    private fun _defaultRoiInCodedSpace(): Pair<Float, Float> =
        Pair(_videoW * ROI_CODED_X, _videoH * ROI_CODED_Y)

    /**
     * 擊球後 ROI 預設追蹤方向（rotation-aware）。
     *
     * 球飛出後 displayY 減少（螢幕向上），依不同 rotation 對應不同 coded 方向：
     *   rot=90 : displayY = codedX  → codedX 減少 → velX = -DEFAULT
     *   rot=270: displayY = W-1-codedX → codedX 增加 → velX = +DEFAULT
     *   rot=180: displayY = H-1-codedY → codedY 增加 → velY = +DEFAULT
     *   rot=0  : coded = display     → codedY 減少 → velY = -DEFAULT
     */
    private fun _defaultChaseVel(): Pair<Float, Float> = when (_rotation) {
        90  -> Pair(-POST_IMPACT_CHASE_DY_DEFAULT, 0f)
        270 -> Pair(+POST_IMPACT_CHASE_DY_DEFAULT, 0f)
        180 -> Pair(0f, +POST_IMPACT_CHASE_DY_DEFAULT)
        else -> Pair(0f, -POST_IMPACT_CHASE_DY_DEFAULT)
    }
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
        prevDetCx        = -1f
        prevDetCy        = -1f
        prevDetFrame     = -1
        _hasVelocity     = false
        // chaseVel 先暫設 0，extract() 讀到 rotation 後立即修正

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

        // 儲存影片參數供 _handleMiss / _defaultRoiInCodedSpace 使用
        _videoW   = videoW
        _videoH   = videoH
        _rotation = rotation
        // rotation-aware 預設追蹤方向（第一次 post-impact miss 未建立速度時使用）
        val (defVx, defVy) = _defaultChaseVel()
        chaseVelX = defVx
        chaseVelY = defVy

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

                    // ── 取 YUV 三個平面（重用類別欄位，避免每幀 ~3MB ByteArray 分配）──
                    val yPlane  = image.planes[0]
                    val uPlane  = image.planes[1]
                    val vPlane  = image.planes[2]
                    val yBufRaw = yPlane.buffer
                    val uBufRaw = uPlane.buffer
                    val vBufRaw = vPlane.buffer
                    val yNeed = yBufRaw.remaining(); if (yRawBuf.size < yNeed) yRawBuf = ByteArray(yNeed); yBufRaw.get(yRawBuf, 0, yNeed)
                    val uNeed = uBufRaw.remaining(); if (uRawBuf.size < uNeed) uRawBuf = ByteArray(uNeed); uBufRaw.get(uRawBuf, 0, uNeed)
                    val vNeed = vBufRaw.remaining(); if (vRawBuf.size < vNeed) vRawBuf = ByteArray(vNeed); vBufRaw.get(vRawBuf, 0, vNeed)
                    val yRaw = yRawBuf; val uRaw = uRawBuf; val vRaw = vRawBuf

                    // ── 首幀初始化 ROI（coded 空間，無需 rotation 轉換）──────
                    if (roiCx < 0f) {
                        val (cx, cy) = _defaultRoiInCodedSpace()
                        roiCx = cx; roiCy = cy
                        Log.d(TAG, "ROI init: coded=(${roiCx.toInt()},${roiCy.toInt()}) " +
                            "ratios=(${ROI_CODED_X},${ROI_CODED_Y}) frame=${videoW}x${videoH}")
                    }

                    // ── 依擊球位置決定動態參數 ──────────────────────
                    val isPostImpact = hitFrame >= 0 && frameCount >= hitFrame
                    val maxShift     = if (isPostImpact) MAX_ROI_SHIFT_POST else MAX_ROI_SHIFT_PRE
                    val confThresh   = if (isPostImpact) CONF_POST_IMPACT  else CONF_PRE_IMPACT
                    val tileMargin   = if (isPostImpact) TILE_MARGIN_POST  else TILE_MARGIN_PRE

                    // ── YOLO 推論（ROI crop，RGB 輸入）───────────
                    val halfTile = BallYoloDetector.INPUT_SIZE / 2f
                    var codedDets = detector.detect(
                        yRaw, yPlane.rowStride,
                        uRaw, uPlane.rowStride, uPlane.pixelStride,
                        vRaw, vPlane.rowStride, vPlane.pixelStride,
                        videoW, videoH,
                        roiCx.toInt(), roiCy.toInt(),
                        confThreshold = confThresh,
                        tileEdgeMargin = tileMargin,
                    )

                    // ── 擊球後雙 ROI 搜尋：主 ROI 無近距離偵測時，在速度預測位置額外推論 ──
                    // 當球速較快，主 ROI（上幀位置）可能已追不上球；
                    // 用已估算的速度向量預測新位置，再跑一次推論，以預測位置為基準做距離過濾。
                    // miss=1 時就立即啟動（原 DUAL_ROI_MISS_THRESHOLD=2 太慢）。
                    var dualRoiBest: FloatArray? = null
                    if (isPostImpact && postImpactMisses >= 1) {
                        val predCx = (roiCx + chaseVelX).coerceIn(halfTile, videoW - halfTile)
                        val predCy = (roiCy + chaseVelY).coerceIn(halfTile, videoH - halfTile)
                        // 僅在預測位置與主 ROI 有明顯差距時才多跑一次（避免重複）
                        val roiDist = sqrt(((predCx - roiCx) * (predCx - roiCx) +
                                           (predCy - roiCy) * (predCy - roiCy)).toDouble()).toFloat()
                        if (roiDist >= 30f) {
                            val predDets = detector.detect(
                                yRaw, yPlane.rowStride,
                                uRaw, uPlane.rowStride, uPlane.pixelStride,
                                vRaw, vPlane.rowStride, vPlane.pixelStride,
                                videoW, videoH,
                                predCx.toInt(), predCy.toInt(),
                                confThreshold = confThresh,
                                tileEdgeMargin = tileMargin,
                            )
                            // 以預測位置為基準過濾（獨立於主 ROI 的 maxShift）
                            val predNearby = predDets.filter { d ->
                                val dx = d[0] - predCx; val dy = d[1] - predCy
                                sqrt((dx * dx + dy * dy).toDouble()) <= MAX_ROI_SHIFT_POST
                            }
                            if (predNearby.isNotEmpty()) {
                                dualRoiBest = predNearby.maxByOrNull { it[4] }
                                Log.d(TAG, "dual-ROI hit frame=$frameCount pred=(${predCx.toInt()},${predCy.toInt()}) +${predNearby.size} dets")
                            }
                        }
                    }

                    // ── 更新 ROI 追蹤狀態，決定最終有效偵測列表 ────────
                    // 用 finalDets 代替覆寫 codedDets，保持原始 YOLO 輸出不變（log 更準確）
                    val finalDets: List<FloatArray>
                    val nearby = codedDets.filter { d ->
                        val dx = d[0] - roiCx; val dy = d[1] - roiCy
                        kotlin.math.sqrt((dx * dx + dy * dy).toDouble()) <= maxShift
                    }
                    if (nearby.isNotEmpty()) {
                        val best = nearby.maxByOrNull { it[4] }!!
                        _applyDetection(best, frameCount)
                        finalDets = listOf(best)
                    } else if (dualRoiBest != null) {
                        // 主 ROI 全部超出 maxShift 或無偵測，但雙 ROI 命中
                        _applyDetection(dualRoiBest, frameCount)
                        finalDets = listOf(dualRoiBest)
                    } else {
                        missCount++
                        _handleMiss(frameCount, isPostImpact, videoW, videoH)
                        finalDets = emptyList()
                    }

                    // [DEBUG] 每 30 幀 log 一次偵測結果
                    if (frameCount % 30 == 0) {
                        Log.d(TAG, "[YOLO] frame=$frameCount roi=(${roiCx.toInt()},${roiCy.toInt()}) " +
                            "rawDets=${codedDets.size} final=${finalDets.size} miss=$missCount " +
                            finalDets.take(3).joinToString { d ->
                                "(cx=${d[0].toInt()},cy=${d[1].toInt()},conf=${"%.2f".format(d[4])})"
                            })
                    }

                    // coded-space 座標（與 Python FLIP_MODE=5 後的演算法空間一致，不做 codedToDisplay 轉換）
                    val blobs: List<Map<String, Any>> = finalDets.map { d ->
                        mapOf(
                            "cx"       to d[0].toInt(),
                            "cy"       to d[1].toInt(),
                            // YOLO bbox 面積 ÷ 16 正規化為 blob-comparable area（6..150）
                            "area"     to ((d[2] * d[3] / 16f).toInt()).coerceIn(6, 150),
                            "circ"     to 1.0,
                            "diffMean" to (d[4] * 50.0).toDouble(),
                        )
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
            "fps"      to fps,
            "width"    to videoW,    // coded 寬（與 Python 演算法空間一致）
            "height"   to videoH,    // coded 高
            "rotation" to rotation,  // 供 Dart 計算 coded-space ROI 中心
            "frames"   to frameList,
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
            // ── 擊球後：速度向量追蹤模式 ────────────────────────
            // 使用從最後兩次偵測計算的速度向量預測球位置（而非固定上移）
            // 若尚未建立速度向量，使用預設向上移動
            postImpactMisses++
            if (postImpactMisses <= POST_IMPACT_MAX_FRAMES) {
                val prevCx = roiCx; val prevCy = roiCy
                // _hasVelocity=true 表示已有從實際偵測計算的速度；否則用 rotation-aware 預設方向
                val effectiveVx: Float
                val effectiveVy: Float
                if (_hasVelocity) {
                    effectiveVx = chaseVelX
                    effectiveVy = chaseVelY
                } else {
                    val (defVx, defVy) = _defaultChaseVel()
                    effectiveVx = defVx
                    effectiveVy = defVy
                }
                roiCx += effectiveVx
                roiCy += effectiveVy
                val halfTile = BallYoloDetector.INPUT_SIZE / 2f
                roiCx = roiCx.coerceIn(halfTile, videoW - halfTile)
                roiCy = roiCy.coerceIn(halfTile, videoH - halfTile)
                Log.d(TAG, "post-impact chase[vel=(${effectiveVx.toInt()},${effectiveVy.toInt()})] " +
                    "frame=$frameCount miss=$postImpactMisses " +
                    "roi=(${prevCx.toInt()},${prevCy.toInt()}) → (${roiCx.toInt()},${roiCy.toInt()})")
            } else {
                // 追蹤超時，放棄（保留最後 ROI 位置，不再移動）
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
                    val (cx, cy) = _defaultRoiInCodedSpace()
                    roiCx = cx; roiCy = cy
                    Log.d(TAG, "ROI reset after $MAX_MISS_FRAMES misses (no lastGood): " +
                        "(${prevCx.toInt()},${prevCy.toInt()}) → " +
                        "(${roiCx.toInt()},${roiCy.toInt()})")
                }
                missCount = 0
            }
        }
    }

    // ────────────────────────────────────────────────────────────

    /**
     * 成功偵測到球時統一更新 ROI 追蹤狀態。
     * 抽出為獨立函數，供主 ROI 和雙 ROI 路徑共用。
     *
     * [frameCount] 用於計算幀間距（frameGap）以修正速度估算：
     * 若中間有 miss 幀，位移應除以 frameGap 才是每幀速度，
     * 否則 miss N 幀後第一個偵測的速度會被高估 N 倍。
     */
    private fun _applyDetection(det: FloatArray, frameCount: Int) {
        if (prevDetCx >= 0f && prevDetFrame >= 0) {
            val frameGap = (frameCount - prevDetFrame).coerceAtLeast(1).toFloat()
            val vx = (det[0] - prevDetCx) / frameGap
            val vy = (det[1] - prevDetCy) / frameGap
            chaseVelX = chaseVelX * 0.5f + vx * 0.5f
            chaseVelY = chaseVelY * 0.5f + vy * 0.5f
            chaseVelX = chaseVelX.coerceIn(-400f, 400f)
            chaseVelY = chaseVelY.coerceIn(-400f, 100f)
            _hasVelocity = true  // 第 2 次偵測後才有真實速度
        }
        prevDetCx        = det[0]
        prevDetCy        = det[1]
        prevDetFrame     = frameCount
        roiCx            = det[0]
        roiCy            = det[1]
        lastGoodCx       = det[0]
        lastGoodCy       = det[1]
        missCount        = 0
        postImpactMisses = 0
    }

}
