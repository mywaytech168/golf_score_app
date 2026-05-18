package com.example.golf_score_app

import android.media.Image
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.util.Log
import java.io.File
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/**
 * 球偵測像素層（Kotlin 負責）。
 *
 * 使用 MediaExtractor + MediaCodec 對含骨架的 mp4 逐幀解碼，
 * 對 Y 平面做幀差 + 二值化 + 形態開運算 + BFS 連通域，
 * 以寬鬆門檻輸出每幀候選 blob，由 Dart 層做智慧追蹤決策。
 *
 * 寬鬆門檻（Kotlin 層只做粗篩，不做動態調整）：
 *   diff_thresh = 10
 *   area ∈ [3, 800]
 *   circ ≥ 0.25
 *
 * 回傳格式（MethodChannel 序列化）：
 * {
 *   "fps"    : Double,
 *   "width"  : Int,
 *   "height" : Int,
 *   "frames" : List<Map> 其中每個 Map = {
 *       "ptsUs" : Long,
 *       "blobs" : List<Map> 其中每個 Map = {
 *           "cx"       : Int,
 *           "cy"       : Int,
 *           "area"     : Int,
 *           "circ"     : Double,
 *           "diffMean" : Double
 *       }
 *   }
 * }
 */
class BallBlobExtractor {

    companion object {
        private const val TAG = "BallBlobExtractor"

        // ── 默認偵測門檻（Dart 會透過 MethodChannel 動態調整）──
        private const val DIFF_THRESH_DEFAULT = 18        // 幀差最小值
        private const val AREA_LO_DEFAULT    = 5          // blob 最小面積（像素）
        private const val AREA_HI_DEFAULT    = 600        // blob 最大面積（像素）
        private const val CIRC_MIN_DEFAULT   = 0.30       // 最低圓度
        private const val MORPH_K            = 3          // 形態開運算 kernel 尺寸
    }

    // ────────────────────────────────────────────────────────────
    // 動態檢測配置
    // ────────────────────────────────────────────────────────────
    data class DetectionConfig(
        val diffThresh: Int = DIFF_THRESH_DEFAULT,
        val areaLo: Int = AREA_LO_DEFAULT,
        val areaHi: Int = AREA_HI_DEFAULT,
        val circMin: Double = CIRC_MIN_DEFAULT,
    ) {
        companion object {
            fun fromMap(map: Map<String, Any?>?): DetectionConfig {
                if (map == null) return DetectionConfig()
                return DetectionConfig(
                    diffThresh = (map["diffThresh"] as? Number)?.toInt() ?: DIFF_THRESH_DEFAULT,
                    areaLo = (map["areaLo"] as? Number)?.toInt() ?: AREA_LO_DEFAULT,
                    areaHi = (map["areaHi"] as? Number)?.toInt() ?: AREA_HI_DEFAULT,
                    circMin = (map["circMin"] as? Number)?.toDouble() ?: CIRC_MIN_DEFAULT,
                )
            }
        }
    }

    // ────────────────────────────────────────────────────────────
    // 主入口
    // ────────────────────────────────────────────────────────────

    /**
     * 對 [inputPath] 的影片做逐幀偵測，回傳每幀的 blob 資料列表。
     * [config] - 由 Dart 層動態計算傳入的檢測配置
     * 失敗時回傳 null。
     */
    fun extract(
        inputPath: String,
        config: Map<String, Any?>? = null,
        onProgress: ((op: String, progress: Double, label: String, current: Int, total: Int) -> Unit)? = null,
    ): Map<String, Any>? {
        if (!File(inputPath).exists()) {
            Log.w(TAG, "輸入檔不存在: $inputPath")
            return null
        }

        val detectionConfig = DetectionConfig.fromMap(config)
        Log.d(TAG, "[extract] 使用檢測配置: diffThresh=${detectionConfig.diffThresh}, " +
            "areaLo=${detectionConfig.areaLo}, areaHi=${detectionConfig.areaHi}, " +
            "circMin=${detectionConfig.circMin}")

        // ── 1. 建立 MediaExtractor ──────────────────────────────
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(inputPath)
        } catch (e: Exception) {
            Log.e(TAG, "無法開啟輸入: $e")
            return null
        }

        var videoTrack = -1
        var inputFormat: MediaFormat? = null
        for (i in 0 until extractor.trackCount) {
            val fmt = extractor.getTrackFormat(i)
            if ((fmt.getString(MediaFormat.KEY_MIME) ?: "").startsWith("video/")) {
                videoTrack = i; inputFormat = fmt; break
            }
        }
        if (videoTrack < 0 || inputFormat == null) {
            Log.e(TAG, "找不到視頻 track")
            extractor.release()
            return null
        }
        extractor.selectTrack(videoTrack)

        val videoW    = inputFormat.getInteger(MediaFormat.KEY_WIDTH)
        val videoH    = inputFormat.getInteger(MediaFormat.KEY_HEIGHT)
        val videoMime = inputFormat.getString(MediaFormat.KEY_MIME) ?: "video/avc"
        val fps       = runCatching {
            inputFormat.getInteger(MediaFormat.KEY_FRAME_RATE).toDouble()
        }.getOrElse { 30.0 }  // ✅ 改為 30fps，保持與原錄影一致
        
        // 🎬 明確記錄 fps 來源
        val fpsFromMetadata = runCatching { inputFormat.getInteger(MediaFormat.KEY_FRAME_RATE) }.getOrNull()
        Log.d(TAG, "[BallBlobExtractor] 🎬 fps 檢測: metadata=${fpsFromMetadata} → 使用=$fps")

        val (rotation, totalFrames) = android.media.MediaMetadataRetriever().use { mmr ->
            mmr.setDataSource(inputPath)
            val rot = mmr.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)
                ?.toIntOrNull() ?: 0
            val durationMs = mmr.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_DURATION)
                ?.toLongOrNull() ?: 0L
            val frames = if (fps > 0) (durationMs * fps / 1000.0).toInt() else 0
            Pair(rot, frames)
        }

        val displayW = if (rotation == 90 || rotation == 270) videoH else videoW
        val displayH = if (rotation == 90 || rotation == 270) videoW else videoH

        Log.d(TAG, "[BallBlobExtractor] 影片: coded=${videoW}x${videoH} display=${displayW}x${displayH} fps=$fps mime=$videoMime rotation=$rotation°")

        // ── 2. 建立解碼器 ───────────────────────────────────────
        val decoder = try {
            MediaCodec.createDecoderByType(videoMime)
        } catch (e: Exception) {
            Log.e(TAG, "無法建立解碼器: $e")
            extractor.release()
            return null
        }
        decoder.configure(inputFormat, null, null, 0)
        decoder.start()

        // ── 3. 逐幀解碼 ─────────────────────────────────────────
        val frameList  = mutableListOf<Map<String, Any>>()
        val bufInfo    = MediaCodec.BufferInfo()
        var inputEos   = false
        var prevYData  : ByteArray? = null
        var frameCount = 0

        try {
            while (true) {
                // 餵解碼器
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

                // 取解碼輸出
                val outIdx = decoder.dequeueOutputBuffer(bufInfo, 10_000L)
                if (outIdx == MediaCodec.INFO_TRY_AGAIN_LATER) continue
                if (outIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) continue
                if (outIdx < 0) continue

                val image = runCatching { decoder.getOutputImage(outIdx) }.getOrNull()
                if (image == null) {
                    decoder.releaseOutputBuffer(outIdx, false)
                    if ((bufInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) break
                    continue
                }

                try {
                    val pts     = bufInfo.presentationTimeUs
                    val yPlane  = image.planes[0]
                    val yStride = yPlane.rowStride
                    val yBuf    = yPlane.buffer
                    val yRaw    = ByteArray(videoH * yStride)
                    yBuf.get(yRaw)

                    // 幀差偵測在 coded-space 執行（避免昂貴的 Y 平面旋轉）
                    // blob 座標最後再轉換到 display-space
                    val prevY = prevYData
                    val codedBlobs = if (prevY != null && prevY.size == yRaw.size) {
                        detectBlobs(yRaw, prevY, videoW, videoH, yStride, detectionConfig)
                    } else {
                        emptyList()
                    }

                    // 只對 blob 重心做座標轉換（O(numBlobs)，遠比逐像素旋轉快）
                    val blobs: List<Map<String, Any>> = if (rotation == 0) codedBlobs else {
                        codedBlobs.map { b ->
                            val (dx, dy) = codedToDisplay(
                                b["cx"] as Int, b["cy"] as Int, videoW, videoH, rotation
                            )
                            mapOf(
                                "cx"       to dx,
                                "cy"       to dy,
                                "area"     to b["area"]!!,
                                "circ"     to b["circ"]!!,
                                "diffMean" to b["diffMean"]!!,
                            )
                        }
                    }

                    frameList.add(mapOf(
                        "ptsUs" to pts,
                        "blobs" to blobs,
                    ))

                    prevYData = yRaw
                    frameCount++

                    if (frameCount % 10 == 0 && totalFrames > 0) {
                        val prog = (frameCount.toDouble() / totalFrames).coerceIn(0.0, 0.95)
                        onProgress?.invoke("extractBlobs", prog, "球追蹤分析中 ${(prog * 100).toInt()}%", frameCount, totalFrames)
                    }

                } finally {
                    image.close()
                    decoder.releaseOutputBuffer(outIdx, false)
                }

                if ((bufInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) break
            }

        } catch (e: Exception) {
            Log.e(TAG, "偵測失敗: $e", e)
        } finally {
            runCatching { decoder.stop(); decoder.release() }
            runCatching { extractor.release() }
        }

        Log.d(TAG, "完成: ${frameList.size} 幀，合計 ${frameList.sumOf { (it["blobs"] as List<*>).size }} 個 blob")
        onProgress?.invoke("extractBlobs", 1.0, "球追蹤分析完成", frameCount, frameCount)

        return mapOf(
            "fps"    to fps,
            "width"  to displayW,
            "height" to displayH,
            "frames" to frameList,
        )
    }

    // ────────────────────────────────────────────────────────────
    // Blob 座標轉換（coded-space → display-space）
    // ────────────────────────────────────────────────────────────

    /** 將單一像素座標從 coded-space 轉換到 display-space。 */
    private fun codedToDisplay(
        cx: Int, cy: Int, w: Int, h: Int, rotation: Int,
    ): Pair<Int, Int> = when (rotation) {
        90  -> Pair(h - 1 - cy, cx)           // displayW=h, displayH=w
        270 -> Pair(cy, w - 1 - cx)            // displayW=h, displayH=w
        180 -> Pair(w - 1 - cx, h - 1 - cy)
        else -> Pair(cx, cy)
    }

    // ────────────────────────────────────────────────────────────
    // 幀差偵測 → 形態開運算 → BFS 連通域
    // ────────────────────────────────────────────────────────────

    private fun detectBlobs(
        cur: ByteArray, prev: ByteArray,
        w: Int, h: Int, stride: Int,
        config: DetectionConfig = DetectionConfig(),
    ): List<Map<String, Any>> {

        // 1. 幀差 + 二值化
        //    同時保留每像素差值（供 diffMean 計算）
        val diff   = ByteArray(w * h)
        val binary = BooleanArray(w * h)
        for (j in 0 until h) {
            for (i in 0 until w) {
                val d = abs(
                    (cur[j * stride + i].toInt() and 0xFF) -
                    (prev[j * stride + i].toInt() and 0xFF)
                )
                diff[j * w + i]   = d.toByte()
                binary[j * w + i] = d >= config.diffThresh  // ← 使用動態參數
            }
        }

        // 2. 形態學開運算 3×3（侵蝕 → 膨脹）
        val opened = morphOpen(binary, w, h, MORPH_K)

        // 3. BFS 連通域（4-連通）
        val visited = BooleanArray(w * h)
        val blobs   = mutableListOf<Map<String, Any>>()
        val queue   = ArrayDeque<Int>(256)

        for (start in 0 until w * h) {
            if (!opened[start] || visited[start]) continue

            queue.clear()
            queue.add(start)
            visited[start] = true

            var sumX      = 0L
            var sumY      = 0L
            var area      = 0
            var perim     = 0
            var diffSum   = 0L   // 用於 diffMean

            while (queue.isNotEmpty()) {
                val idx  = queue.removeFirst()
                val px   = idx % w
                val py   = idx / w
                sumX    += px
                sumY    += py
                area++
                diffSum += diff[idx].toInt() and 0xFF

                var isBorder = false
                val ns = intArrayOf(
                    if (px > 0)     idx - 1 else -1,
                    if (px < w - 1) idx + 1 else -1,
                    if (py > 0)     idx - w else -1,
                    if (py < h - 1) idx + w else -1,
                )
                for (n in ns) {
                    if (n < 0 || !opened[n]) { isBorder = true; continue }
                    if (!visited[n]) { visited[n] = true; queue.add(n) }
                }
                if (isBorder) perim++
            }

            // 面積篩選（使用動態參數）
            if (area !in config.areaLo..config.areaHi) continue

            // 圓度
            val circ = if (perim < 1) 0.0
                       else 4.0 * Math.PI * area / (perim.toDouble() * perim)
            if (circ < config.circMin) continue  // ← 使用動態參數

            val cx       = (sumX / area).toInt()
            val cy       = (sumY / area).toInt()
            val diffMean = diffSum.toDouble() / area

            blobs.add(mapOf(
                "cx"       to cx,
                "cy"       to cy,
                "area"     to area,
                "circ"     to circ,
                "diffMean" to diffMean,
            ))
        }

        return blobs
    }

    // ────────────────────────────────────────────────────────────
    // 形態學開運算（侵蝕 + 膨脹）
    // ────────────────────────────────────────────────────────────

    private fun morphOpen(binary: BooleanArray, w: Int, h: Int, k: Int): BooleanArray {
        val r = k / 2
        // 侵蝕
        val eroded = BooleanArray(w * h)
        for (j in r until h - r) {
            for (i in r until w - r) {
                var all = true
                outer@ for (dj in -r..r) {
                    for (di in -r..r) {
                        if (!binary[(j + dj) * w + (i + di)]) { all = false; break@outer }
                    }
                }
                eroded[j * w + i] = all
            }
        }
        // 膨脹
        val dilated = BooleanArray(w * h)
        for (j in r until h - r) {
            for (i in r until w - r) {
                var any = false
                outer@ for (dj in -r..r) {
                    for (di in -r..r) {
                        if (eroded[(j + dj) * w + (i + di)]) { any = true; break@outer }
                    }
                }
                dilated[j * w + i] = any
            }
        }
        return dilated
    }
}
