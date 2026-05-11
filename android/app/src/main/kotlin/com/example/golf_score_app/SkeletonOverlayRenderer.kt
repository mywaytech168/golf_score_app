package com.example.golf_score_app

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.media.Image
import android.media.MediaCodec
import android.media.MediaCodecInfo.CodecCapabilities
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.media.MediaMuxer
import android.util.Log
import java.io.File
import kotlin.math.roundToInt

/**
 * 替裁切後的高爾夫揮桿片段渲染骨架疊加影片。
 *
 * 輸入：已裁切的 mp4 片段、原始錄影的 pose_landmarks.csv、片段在原始影片中的起始秒數
 * 輸出：帶有骨架線條的 mp4 影片（輸出幀率與分析取樣率一致，約 15fps）
 *
 * 骨架座標系轉換：
 *   CSV 中的 x_px / y_px 是在縮圖空間（maxWidth=720），
 *   需乘以 scale = clipWidth / poseImgWidth 才能對齊輸出幀。
 */
class SkeletonOverlayRenderer(private val context: Context) {

    companion object {
        private const val TAG = "SkeletonOverlay"

        /** 骨架分析取樣間隔（毫秒），對應 VideoAnalysisService 的 _frameIntervalMs = 67 */
        private const val ANALYSIS_INTERVAL_MS = 67.0

        /** MediaPipe 33-landmark 骨骼連接定義（按人體左/右分色） */
        val CONNECTIONS = listOf(
            // 臉部
            0 to 1, 1 to 2, 2 to 3, 3 to 7,
            0 to 4, 4 to 5, 5 to 6, 6 to 8,
            9 to 10,
            // 左臂（人體左側）
            11 to 13, 13 to 15, 15 to 17, 17 to 19, 19 to 15, 15 to 21,
            // 右臂（人體右側）
            12 to 14, 14 to 16, 16 to 18, 18 to 20, 20 to 16, 16 to 22,
            // 軀幹
            11 to 12, 12 to 24, 24 to 23, 23 to 11,
            // 左腿
            23 to 25, 25 to 27, 27 to 29, 29 to 31, 31 to 27,
            // 右腿
            24 to 26, 26 to 28, 28 to 30, 30 to 32, 32 to 28
        )

        /** 人體左側關節點索引（MediaPipe 定義） */
        val LEFT_LANDMARKS = setOf(1, 2, 3, 7, 9, 11, 13, 15, 17, 19, 21, 23, 25, 27, 29, 31)

        /** 人體右側關節點索引 */
        val RIGHT_LANDMARKS = setOf(4, 5, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30, 32)
    }

    /** 單一關節點的解析資料 */
    private data class LandmarkPoint(
        val xPx: Float,
        val yPx: Float,
        val xNorm: Float,
        val yNorm: Float,
        val visibility: Float
    )

    /**
     * 渲染骨架疊加影片。
     *
     * @param clipPath   已裁切的 mp4 路徑
     * @param csvPath    pose_landmarks.csv 路徑（原始完整錄影的分析結果）
     * @param startSec   片段在原始影片中的起始秒數
     * @param outputPath 輸出 mp4 路徑
     * @return 成功回傳 true，失敗回傳 false
     */
    fun render(
        clipPath: String,
        csvPath: String,
        startSec: Double,
        outputPath: String
    ): Boolean {
        // 1. 解析 CSV
        val frameData = parseCsv(csvPath)
        if (frameData.isEmpty()) {
            Log.w(TAG, "CSV 沒有資料：$csvPath")
            return false
        }

        // 2. 從 CSV 推算骨架影像尺寸（thumbnail 空間）
        val poseSize = inferPoseImageSize(frameData)
        if (poseSize == null) {
            Log.w(TAG, "無法從 CSV 推算骨架影像尺寸")
            return false
        }
        val (poseW, poseH) = poseSize
        Log.d(TAG, "骨架影像尺寸推算: ${poseW}x${poseH}")

        // 3. 讀取片段元資料
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(clipPath)
        } catch (e: Exception) {
            Log.e(TAG, "無法開啟片段: $e")
            return false
        }

        val clipW = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
            ?.toIntOrNull() ?: 720
        val clipH = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
            ?.toIntOrNull() ?: 1280
        val durationMs = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
            ?.toLongOrNull() ?: 3000L

        val scaleX = clipW.toFloat() / poseW
        val scaleY = clipH.toFloat() / poseH
        Log.d(TAG, "片段: ${clipW}x${clipH} duration=${durationMs}ms scale=${scaleX}x${scaleY}")

        // 4. 根據分析取樣率計算需要渲染的幀列表
        //    輸出幀率 = 1000 / ANALYSIS_INTERVAL_MS ≈ 14.9fps
        val outputFps = (1000.0 / ANALYSIS_INTERVAL_MS).toFloat()
        val analysisIntervalUs = (ANALYSIS_INTERVAL_MS * 1000).toLong()

        // 收集要渲染的幀：每隔 analysisIntervalMs 取一幀
        val framesToRender = mutableListOf<Long>() // clip 內的 timeUs
        var t = 0L
        while (t < durationMs * 1000L) {
            framesToRender.add(t)
            t += analysisIntervalUs
        }
        if (framesToRender.isEmpty()) framesToRender.add(0L)

        Log.d(TAG, "要渲染 ${framesToRender.size} 幀（分析取樣率）")

        // 5. 建立 MediaCodec 編碼器 + MediaMuxer
        val mime = "video/avc"
        val encoder: MediaCodec
        try {
            encoder = MediaCodec.createEncoderByType(mime)
        } catch (e: Exception) {
            Log.e(TAG, "無法建立編碼器: $e")
            retriever.release()
            return false
        }

        val encFormat = MediaFormat.createVideoFormat(mime, clipW, clipH).apply {
            setInteger(MediaFormat.KEY_COLOR_FORMAT, CodecCapabilities.COLOR_FormatYUV420Flexible)
            setInteger(MediaFormat.KEY_BIT_RATE, 3_000_000)
            setInteger(MediaFormat.KEY_FRAME_RATE, outputFps.roundToInt())
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
        }

        try {
            encoder.configure(encFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            encoder.start()
        } catch (e: Exception) {
            Log.e(TAG, "編碼器設定失敗: $e")
            encoder.release()
            retriever.release()
            return false
        }

        // 確保輸出目錄存在
        File(outputPath).parentFile?.mkdirs()

        val muxer = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        var videoTrackIndex = -1
        var muxerStarted = false
        val bufferInfo = MediaCodec.BufferInfo()
        var success = false

        try {
            for ((frameIdx, clipTimeUs) in framesToRender.withIndex()) {
                // 6. 從片段取出原始幀
                val bitmap = retriever.getFrameAtTime(
                    clipTimeUs, MediaMetadataRetriever.OPTION_CLOSEST
                )
                if (bitmap == null) {
                    Log.w(TAG, "幀 $frameIdx @${clipTimeUs}us 取得失敗，略過")
                    continue
                }

                // 7. 找對應的 CSV 幀索引
                val clipTimeSec = clipTimeUs / 1_000_000.0
                val origTimeSec = startSec + clipTimeSec
                val csvFrameIdx = (origTimeSec * 1000.0 / ANALYSIS_INTERVAL_MS).roundToInt()

                // 8. 確保 bitmap 為 ARGB_8888 可繪製
                val mutable: Bitmap = bitmap.copy(Bitmap.Config.ARGB_8888, true)
                bitmap.recycle()

                // 9. 繪製骨架
                frameData[csvFrameIdx]?.let { landmarks ->
                    drawSkeleton(Canvas(mutable), landmarks, scaleX, scaleY, clipW, clipH)
                }

                // 10. 餵入編碼器
                val pts = clipTimeUs
                val inputIdx = encoder.dequeueInputBuffer(50_000L)
                if (inputIdx >= 0) {
                    val image = runCatching { encoder.getInputImage(inputIdx) }.getOrNull()
                    if (image != null) {
                        fillYuvImage(image, mutable, clipW, clipH)
                        encoder.queueInputBuffer(inputIdx, 0, 0, pts, 0)
                    } else {
                        val buf = encoder.getInputBuffer(inputIdx)!!
                        val yuv = argbToNv12(mutable, clipW, clipH)
                        buf.clear()
                        buf.put(yuv)
                        encoder.queueInputBuffer(inputIdx, 0, yuv.size, pts, 0)
                    }
                }
                mutable.recycle()

                // 11. 排空編碼器輸出
                drainEncoder(encoder, muxer, bufferInfo, { idx -> videoTrackIndex = idx; muxerStarted = true },
                    { videoTrackIndex }, { muxerStarted }, false)
            }

            // 12. 送出 EOS 並等待所有輸出
            val eosIdx = encoder.dequeueInputBuffer(100_000L)
            if (eosIdx >= 0) {
                encoder.queueInputBuffer(eosIdx, 0, 0,
                    framesToRender.lastOrNull()?.plus(analysisIntervalUs) ?: 0L,
                    MediaCodec.BUFFER_FLAG_END_OF_STREAM)
            }
            drainEncoder(encoder, muxer, bufferInfo, { idx -> videoTrackIndex = idx; muxerStarted = true },
                { videoTrackIndex }, { muxerStarted }, true)

            success = muxerStarted
            Log.d(TAG, "骨架渲染完成: $outputPath")

        } catch (e: Exception) {
            Log.e(TAG, "骨架渲染錯誤: $e", e)
            success = false
        } finally {
            runCatching { encoder.stop() }
            runCatching { encoder.release() }
            runCatching { if (muxerStarted) { muxer.stop(); muxer.release() } else muxer.release() }
            runCatching { retriever.release() }
        }

        if (!success) {
            runCatching { File(outputPath).delete() }
        }
        return success
    }

    // ------------------------------------------------------------------
    // 骨架繪製
    // ------------------------------------------------------------------

    private fun drawSkeleton(
        canvas: Canvas,
        landmarks: Array<LandmarkPoint?>,
        scaleX: Float, scaleY: Float,
        w: Int, h: Int
    ) {
        val strokeW = (w / 120f).coerceIn(3f, 9f)
        val radius = (w / 90f).coerceIn(4f, 12f)

        val linePaint = Paint().apply {
            strokeWidth = strokeW
            style = Paint.Style.STROKE
            isAntiAlias = true
            strokeCap = Paint.Cap.ROUND
        }
        val dotPaint = Paint().apply {
            style = Paint.Style.FILL
            isAntiAlias = true
        }

        // 骨骼連接線
        for ((a, b) in CONNECTIONS) {
            val la = landmarks.getOrNull(a) ?: continue
            val lb = landmarks.getOrNull(b) ?: continue
            if (la.visibility < 0.3f || lb.visibility < 0.3f) continue

            linePaint.color = when {
                a in LEFT_LANDMARKS && b in LEFT_LANDMARKS -> Color.argb(210, 0, 230, 90)
                a in RIGHT_LANDMARKS && b in RIGHT_LANDMARKS -> Color.argb(210, 240, 55, 55)
                else -> Color.argb(210, 255, 215, 0)
            }
            canvas.drawLine(
                la.xPx * scaleX, la.yPx * scaleY,
                lb.xPx * scaleX, lb.yPx * scaleY,
                linePaint
            )
        }

        // 關節點
        for ((i, lm) in landmarks.withIndex()) {
            if (lm == null || lm.visibility < 0.3f) continue
            dotPaint.color = when (i) {
                in LEFT_LANDMARKS -> Color.argb(230, 0, 200, 70)
                in RIGHT_LANDMARKS -> Color.argb(230, 210, 35, 35)
                else -> Color.argb(230, 255, 200, 0)
            }
            canvas.drawCircle(lm.xPx * scaleX, lm.yPx * scaleY, radius, dotPaint)
        }
    }

    // ------------------------------------------------------------------
    // CSV 解析
    // CSV 格式（寬格式）：
    //   frame, time_sec,
    //   lm0_x_norm, lm0_y_norm, lm0_z, lm0_visibility, lm0_x_px, lm0_y_px,
    //   lm1_x_norm, ..., lm32_y_px
    // 共 2 + 33×6 = 200 欄
    // ------------------------------------------------------------------

    private fun parseCsv(csvPath: String): Map<Int, Array<LandmarkPoint?>> {
        val file = File(csvPath)
        if (!file.exists()) {
            Log.w(TAG, "CSV 不存在: $csvPath")
            return emptyMap()
        }

        val result = mutableMapOf<Int, Array<LandmarkPoint?>>()

        file.bufferedReader().use { reader ->
            // 跳過標頭列
            reader.readLine()
            // 逐列處理（避免在 inline lambda 中使用 continue/break）
            var line = reader.readLine()
            while (line != null) {
                val cols = line.split(",")
                if (cols.size >= 200) {
                    val frameIdx = cols[0].trim().toIntOrNull()
                    if (frameIdx != null) {
                        val landmarks = arrayOfNulls<LandmarkPoint>(33)
                        for (i in 0 until 33) {
                            // 每組 6 欄：x_norm, y_norm, z, visibility, x_px, y_px
                            val base = 2 + i * 6
                            val xNorm = cols[base + 0].trim().toFloatOrNull()?.takeIf { !it.isNaN() }
                            val yNorm = cols[base + 1].trim().toFloatOrNull()?.takeIf { !it.isNaN() }
                            val vis = cols[base + 3].trim().toFloatOrNull() ?: 0f
                            val xPx = cols[base + 4].trim().toFloatOrNull()?.takeIf { !it.isNaN() }
                            val yPx = cols[base + 5].trim().toFloatOrNull()?.takeIf { !it.isNaN() }
                            if (xNorm != null && yNorm != null && xPx != null && yPx != null
                                && xNorm > 0f && yNorm > 0f
                            ) {
                                landmarks[i] = LandmarkPoint(xPx, yPx, xNorm, yNorm, vis)
                            }
                        }
                        result[frameIdx] = landmarks
                    }
                }
                line = reader.readLine()
            }
        }

        Log.d(TAG, "CSV 解析完成：${result.size} 幀")
        return result
    }

    /**
     * 從 CSV 資料推算骨架影像的寬高。
     * 利用 xPx / xNorm = imgWidth（ML Kit 回傳的 pixel 座標 / 正規化座標）。
     */
    private fun inferPoseImageSize(
        frameData: Map<Int, Array<LandmarkPoint?>>
    ): Pair<Float, Float>? {
        for ((_, landmarks) in frameData) {
            for (lm in landmarks) {
                if (lm != null && lm.xNorm > 0.05f && lm.yNorm > 0.05f) {
                    val imgW = lm.xPx / lm.xNorm
                    val imgH = lm.yPx / lm.yNorm
                    if (imgW > 50f && imgH > 50f) return imgW to imgH
                }
            }
        }
        return null
    }

    // ------------------------------------------------------------------
    // 編碼器輔助
    // ------------------------------------------------------------------

    /**
     * 排空編碼器輸出緩衝區並寫入 Muxer。
     * [endOfStream] = true 時持續等待直到收到 EOS。
     */
    private fun drainEncoder(
        encoder: MediaCodec,
        muxer: MediaMuxer,
        bufferInfo: MediaCodec.BufferInfo,
        onTrackAdded: (Int) -> Unit,
        trackIndexProvider: () -> Int,
        muxerStartedProvider: () -> Boolean,
        endOfStream: Boolean
    ) {
        val timeoutUs = if (endOfStream) 100_000L else 0L
        while (true) {
            val outIdx = encoder.dequeueOutputBuffer(bufferInfo, timeoutUs)
            when {
                outIdx == MediaCodec.INFO_TRY_AGAIN_LATER -> {
                    if (!endOfStream) break
                }
                outIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    val newFormat = encoder.outputFormat
                    val trackIdx = muxer.addTrack(newFormat)
                    muxer.start()
                    onTrackAdded(trackIdx)
                }
                outIdx >= 0 -> {
                    val buf = encoder.getOutputBuffer(outIdx)
                    val isEos = (bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0

                    if (buf != null && bufferInfo.size > 0 && muxerStartedProvider()) {
                        buf.position(bufferInfo.offset)
                        buf.limit(bufferInfo.offset + bufferInfo.size)
                        muxer.writeSampleData(trackIndexProvider(), buf, bufferInfo)
                    }
                    encoder.releaseOutputBuffer(outIdx, false)
                    if (isEos) break
                }
            }
        }
    }

    /**
     * 將 ARGB_8888 Bitmap 寫入 MediaCodec Image（YUV420Flexible，處理 NV12 / I420 兩種 layout）。
     */
    private fun fillYuvImage(image: Image, bitmap: Bitmap, w: Int, h: Int) {
        val pixels = IntArray(w * h)
        bitmap.getPixels(pixels, 0, w, 0, 0, w, h)

        val yPlane = image.planes[0]
        val uPlane = image.planes[1]
        val vPlane = image.planes[2]

        val yBuf = yPlane.buffer
        val uBuf = uPlane.buffer
        val vBuf = vPlane.buffer
        val yStride = yPlane.rowStride
        val uvStride = uPlane.rowStride
        val uvPixelStride = uPlane.pixelStride // 1 = I420, 2 = NV12

        for (j in 0 until h) {
            for (i in 0 until w) {
                val p = pixels[j * w + i]
                val r = (p shr 16) and 0xFF
                val g = (p shr 8) and 0xFF
                val b = p and 0xFF
                val y = ((66 * r + 129 * g + 25 * b + 128) shr 8) + 16
                yBuf.put(j * yStride + i, y.toByte())

                if (j % 2 == 0 && i % 2 == 0) {
                    val u = ((-38 * r - 74 * g + 112 * b + 128) shr 8) + 128
                    val v = ((112 * r - 94 * g - 18 * b + 128) shr 8) + 128
                    val uvOff = (j / 2) * uvStride + (i / 2) * uvPixelStride
                    uBuf.put(uvOff, u.toByte())
                    vBuf.put(uvOff, v.toByte())
                }
            }
        }
    }

    /**
     * 備援用：將 ARGB_8888 Bitmap 轉換為 NV12 (YUV420SemiPlanar) 位元組陣列。
     */
    private fun argbToNv12(bitmap: Bitmap, w: Int, h: Int): ByteArray {
        val pixels = IntArray(w * h)
        bitmap.getPixels(pixels, 0, w, 0, 0, w, h)
        val nv12 = ByteArray(w * h + (w * h / 2))

        for (j in 0 until h) {
            for (i in 0 until w) {
                val p = pixels[j * w + i]
                val r = (p shr 16) and 0xFF
                val g = (p shr 8) and 0xFF
                val b = p and 0xFF
                val y = ((66 * r + 129 * g + 25 * b + 128) shr 8) + 16
                nv12[j * w + i] = y.toByte()

                if (j % 2 == 0 && i % 2 == 0) {
                    val u = ((-38 * r - 74 * g + 112 * b + 128) shr 8) + 128
                    val v = ((112 * r - 94 * g - 18 * b + 128) shr 8) + 128
                    // NV12: UV plane interleaved U,V; one pair per 2×2 block
                    val uvBase = w * h + (j / 2) * w + (i / 2) * 2
                    if (uvBase + 1 < nv12.size) {
                        nv12[uvBase] = u.toByte()
                        nv12[uvBase + 1] = v.toByte()
                    }
                }
            }
        }
        return nv12
    }
}
