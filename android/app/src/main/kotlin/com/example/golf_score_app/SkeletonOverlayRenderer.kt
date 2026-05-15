package com.example.golf_score_app

import android.content.Context
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
import kotlin.math.roundToInt

/**
 * 替裁切後的高爾夫揮桿片段渲染骨架疊加影片。
 *
 * 採用 MediaExtractor + MediaCodec 順序解碼（與 TrajectoryOverlayRenderer 相同架構），
 * 逐幀解碼 → 繪製骨架 → 重新編碼，輸出保留原始幀率與解析度。
 *
 * 骨架座標系轉換：
 *   CSV 中的 x_px / y_px 是在縮圖空間（maxWidth=720），
 *   需乘以 scale = clipWidth / poseImgWidth 才能對齊輸出幀。
 */
class SkeletonOverlayRenderer(private val context: Context) {

    companion object {
        private const val TAG = "SkeletonOverlay"

        /** 骨架分析取樣間隔（毫秒），對應 VideoAnalysisService 的 _frameIntervalMs = 33 */
        private const val ANALYSIS_INTERVAL_MS = 33.0

        val CONNECTIONS = listOf(
            // 臉部
            0 to 1, 1 to 2, 2 to 3, 3 to 7,
            0 to 4, 4 to 5, 5 to 6, 6 to 8,
            9 to 10,
            // 左臂
            11 to 13, 13 to 15, 15 to 17, 17 to 19, 19 to 15, 15 to 21,
            // 右臂
            12 to 14, 14 to 16, 16 to 18, 18 to 20, 20 to 16, 16 to 22,
            // 軀幹
            11 to 12, 12 to 24, 24 to 23, 23 to 11,
            // 左腿
            23 to 25, 25 to 27, 27 to 29, 29 to 31, 31 to 27,
            // 右腿
            24 to 26, 26 to 28, 28 to 30, 30 to 32, 32 to 28,
        )

        val LEFT_LANDMARKS  = setOf(1, 2, 3, 7, 9, 11, 13, 15, 17, 19, 21, 23, 25, 27, 29, 31)
        val RIGHT_LANDMARKS = setOf(4, 5, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30, 32)
    }

    private data class LandmarkPoint(
        val xPx: Float, val yPx: Float,
        val xNorm: Float, val yNorm: Float,
        val visibility: Float,
    )

    // 每個 clip 生命週期內重用（避免每幀 new Paint GC 壓力）
    private val linePaint = Paint().apply {
        style = Paint.Style.STROKE; isAntiAlias = true; strokeCap = Paint.Cap.ROUND
    }
    private val dotPaint = Paint().apply {
        style = Paint.Style.FILL; isAntiAlias = true
    }

    // ────────────────────────────────────────────────────────────
    // 主入口
    // ────────────────────────────────────────────────────────────

    fun render(
        clipPath: String,
        csvPath: String,
        startSec: Double,
        outputPath: String,
    ): Boolean {
        // 1. 解析 CSV
        val frameData = parseCsv(csvPath)
        if (frameData.isEmpty()) {
            Log.w(TAG, "CSV 沒有資料：$csvPath"); return false
        }

        // 2. 推算骨架影像尺寸（thumbnail 空間）
        val poseSize = inferPoseImageSize(frameData)
        if (poseSize == null) {
            Log.w(TAG, "無法從 CSV 推算骨架影像尺寸"); return false
        }
        val (poseW, poseH) = poseSize
        Log.d(TAG, "骨架影像尺寸推算: ${poseW}x${poseH}")

        // 3. MediaExtractor 開啟輸入片段
        val extractor = MediaExtractor()
        try { extractor.setDataSource(clipPath) }
        catch (e: Exception) { Log.e(TAG, "無法開啟片段: $e"); return false }

        var videoTrack = -1; var inputFormat: MediaFormat? = null
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
        val fps       = runCatching {
            inputFormat.getInteger(MediaFormat.KEY_FRAME_RATE).toFloat()
        }.getOrElse { 30f }
        
        val rotation = android.media.MediaMetadataRetriever().use { mmr ->
            mmr.setDataSource(clipPath)
            mmr.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)
                ?.toIntOrNull() ?: 0
        }
        // 輸出以 display 尺寸編碼（旋轉後的正方向），不在 MP4 寫 rotation metadata
        val displayW = if (rotation == 90 || rotation == 270) videoH else videoW
        val displayH = if (rotation == 90 || rotation == 270) videoW else videoH
        Log.d(TAG, "片段: coded=${videoW}x${videoH} display=${displayW}x${displayH} fps=$fps poseSize=${poseW}x${poseH} rotation=$rotation°")

        // 4. 建立解碼器
        val decoder = try {
            MediaCodec.createDecoderByType(videoMime)
        } catch (e: Exception) {
            Log.e(TAG, "無法建立解碼器: $e"); extractor.release(); return false
        }
        decoder.configure(inputFormat, null, null, 0)
        decoder.start()

        // 5. 建立編碼器
        val encoder = try {
            MediaCodec.createEncoderByType("video/avc")
        } catch (e: Exception) {
            Log.e(TAG, "無法建立編碼器: $e")
            decoder.stop(); decoder.release(); extractor.release(); return false
        }
        // 骨架疊加限制在 720p（長邊），避免 JVM 像素迴圈在 1080p 耗費過久
        // 1080p：2,073,600 pixels → 720p：291,600 pixels（~7x 加速）
        val maxLongSide = 720
        val srcLong = maxOf(displayW, displayH)
        val sc = if (srcLong > maxLongSide) maxLongSide.toFloat() / srcLong else 1.0f
        fun scaleEven(v: Int) = if (sc < 1f) ((v * sc).roundToInt().let { if (it % 2 != 0) it + 1 else it }) else v
        val skelW = scaleEven(displayW)
        val skelH = scaleEven(displayH)
        // 部分硬體編碼器要求寬高為 16 的倍數
        val encW = (skelW + 15) and -16
        val encH = (skelH + 15) and -16
        val bitRate = (skelW.toLong() * skelH * fps * 0.8)
            .toLong().coerceIn(2_000_000L, 8_000_000L).toInt()
        val encFmt = MediaFormat.createVideoFormat("video/avc", encW, encH).apply {
            setInteger(MediaFormat.KEY_COLOR_FORMAT, CodecCapabilities.COLOR_FormatYUV420SemiPlanar)
            setInteger(MediaFormat.KEY_BIT_RATE, bitRate)
            setInteger(MediaFormat.KEY_FRAME_RATE, fps.roundToInt())
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
        }
        Log.d(TAG, "骨架編碼: ${encW}x${encH}（display=${displayW}x${displayH}，scale=%.2f）bitRate=${bitRate/1_000_000}Mbps".format(sc))
        encoder.configure(encFmt, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        encoder.start()

        // 6. 建立 Muxer
        File(outputPath).parentFile?.mkdirs()
        val muxer      = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        var muxTrack   = -1
        var muxStarted = false

        val decBufInfo = MediaCodec.BufferInfo()
        val encBufInfo = MediaCodec.BufferInfo()
        var inputEos   = false
        var frameCount = 0
        var encodedFrames = 0
        var drainedOutputs = 0
        var samplesWritten = 0
        var success    = false

        // ── 預配置可重用緩衝區 ────────────────────────────────────
        // 優化：YUV → NV12 直接轉換，省去 YUV→RGB→NV12 的中間層
        // 骨架單獨畫在透明 overlay，再 composite 進 NV12（稀疏操作）
        val nv12Buf       = ByteArray(encW * encH + encW * encH / 2)
        val overlayBmp    = Bitmap.createBitmap(encW, encH, Bitmap.Config.ARGB_8888)
        val overlayCanvas = Canvas(overlayBmp)
        val overlayPixels = IntArray(encW * encH)
        // 骨架繪製參數：基於編碼尺寸（Canvas 是 encW×encH）
        val encShortSide = minOf(encW, encH).toFloat()
        linePaint.strokeWidth = (encShortSide / 80f).coerceIn(2f, 7f)
        val skeletonRadius = (encShortSide / 60f).coerceIn(3f, 9f)

        try {
            while (true) {
                // ── 餵解碼器 ────────────────────────────────────
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

                // ── 取解碼輸出 ──────────────────────────────────
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

                    // ── 計算對應的 CSV 幀索引 ────────────────────
                    val clipTimeSec = pts / 1_000_000.0
                    val origTimeSec = startSec + clipTimeSec
                    val csvFrameIdx = (origTimeSec * 1000.0 / ANALYSIS_INTERVAL_MS).roundToInt()

                    // ── 1. YUV → NV12 直接轉換 + downscale to encW×encH（~7x 加速）──
                    yuvToNv12WithRotation(image, videoW, videoH, rotation, displayW, displayH, encW, encH, nv12Buf)
                    // srcW=displayW, srcH=displayH：原始解析度作為 source

                    // ── 2. 骨架疊加（透明 overlay → composite 進 NV12）──
                    overlayBmp.eraseColor(android.graphics.Color.TRANSPARENT)
                    frameData[csvFrameIdx]?.let { landmarks ->
                        drawSkeleton(overlayCanvas, landmarks, poseW, poseH, encW, encH, skeletonRadius)
                    }
                    compositeSkeleton(overlayBmp, overlayPixels, encW, encH, nv12Buf)

                    // ── 3. 餵編碼器 ─────────────────────────────
                    val encInIdx = encoder.dequeueInputBuffer(50_000L)
                    // 使用浮點除法避免 fps.toLong() 截斷（如 29.97→29）
                    val ptsUs = (frameCount.toDouble() * 1_000_000.0 / fps).toLong()

                    if (encInIdx >= 0) {
                        val buf = encoder.getInputBuffer(encInIdx)!!
                        buf.clear()
                        buf.put(nv12Buf, 0, nv12Buf.size)
                        encoder.queueInputBuffer(encInIdx, 0, nv12Buf.size, ptsUs, 0)
                        frameCount++
                    } else {
                        Log.w(TAG, "dequeueInputBuffer 返回 $encInIdx，略過幀 pts=$ptsUs")
                    }

                    drainEncoder(
                        encoder, muxer, encBufInfo,
                        setTrack = { t -> muxTrack = t; muxStarted = true },
                        getTrack = { muxTrack },
                        isMuxed  = { muxStarted },
                        eos      = false,
                        onSampleWritten = { encodedFrames++; samplesWritten++ },
                    )

                } finally {
                    image.close()
                    decoder.releaseOutputBuffer(outIdx, false)
                }

                if ((decBufInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) break
            }

            // ── EOS ─────────────────────────────────────────────
            Log.d(TAG, "Signaling EOS to encoder, current queuedFrames=$frameCount")
            
            // 檢查是否有幀被 queue 了
            if (frameCount <= 0) {
                Log.e(TAG, "CRITICAL: frameCount=0，編碼器沒有收到任何幀，停止處理")
                success = false
                encodedFrames = 0
            } else {
                // ✅ 持續重試直到取得 EOS 輸入緩衝區（同 TrajectoryOverlayRenderer 的 20 次策略）
                var eosIdx = -1; var eosTries = 0
                while (eosIdx < 0 && eosTries < 20) {
                    eosIdx = encoder.dequeueInputBuffer(100_000L); eosTries++
                }
                if (eosIdx >= 0) {
                    val ptsUs = (frameCount.toDouble() * 1_000_000.0 / fps).toLong()
                    encoder.queueInputBuffer(eosIdx, 0, 0, ptsUs, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                    Log.d(TAG, "EOS queued at index $eosIdx after $eosTries tries, frameCount=$frameCount, ptsUs=$ptsUs")
                } else {
                    Log.w(TAG, "Failed to get EOS input buffer after $eosTries tries")
                }
                
                Log.d(TAG, "Draining encoder with eos=true")
                drainEncoder(
                    encoder, muxer, encBufInfo,
                    setTrack = { t -> muxTrack = t; muxStarted = true },
                    getTrack = { muxTrack },
                    isMuxed  = { muxStarted },
                    eos      = true,
                    onSampleWritten = { encodedFrames++; samplesWritten++ },
                )
                Log.d(TAG, "Encoder drained, encodedFrames=$encodedFrames")
            }

            // ✅ 驗證編碼幀數：已有輸出即視為成功
            if (encodedFrames > 0 && samplesWritten > 0) {
                success = muxStarted
                Log.d(TAG, "✅ SUCCESS: renderedFrames=$frameCount, encodedFrames=$encodedFrames, samplesWritten=$samplesWritten")
                Log.d(TAG, "骨架渲染完成: $frameCount 幀 → $outputPath")
            } else {
                Log.e(TAG, "❌ ERROR: encodedFrames=$encodedFrames, samplesWritten=$samplesWritten")
                Log.e(TAG, "Skeleton MP4 編碼失敗: renderedFrames=$frameCount, encodedFrames=$encodedFrames, drainedOutputs=$drainedOutputs, samplesWritten=$samplesWritten")
                success = false
            }

        } catch (e: Exception) {
            Log.e(TAG, "骨架渲染錯誤: $e", e)
        } finally {
            runCatching { overlayBmp.recycle() }
            runCatching { decoder.stop(); decoder.release() }
            runCatching { encoder.stop(); encoder.release() }
            runCatching { extractor.release() }
            runCatching {
                if (muxStarted) { muxer.stop(); muxer.release() } else muxer.release()
            }
        }

        if (!success) {
            Log.e(TAG, "Skeleton overlay failed, deleting: $outputPath")
            Log.e(TAG, "Final stats: renderedFrames=$frameCount, encodedFrames=$encodedFrames, samplesWritten=$samplesWritten")
            runCatching { File(outputPath).delete() }
        }
        return success
    }

    // ────────────────────────────────────────────────────────────
    // 骨架繪製
    // ────────────────────────────────────────────────────────────

    private fun drawSkeleton(
        canvas: Canvas,
        landmarks: Array<LandmarkPoint?>,
        poseW: Float, poseH: Float,
        displayW: Int, displayH: Int,
        radius: Float,
    ) {
        val scaleX = displayW.toFloat() / poseW
        val scaleY = displayH.toFloat() / poseH

        for ((a, b) in CONNECTIONS) {
            val la = landmarks.getOrNull(a) ?: continue
            val lb = landmarks.getOrNull(b) ?: continue
            if (la.visibility < 0.3f || lb.visibility < 0.3f) continue
            linePaint.color = when {
                a in LEFT_LANDMARKS  && b in LEFT_LANDMARKS  -> Color.argb(210, 0, 230, 90)
                a in RIGHT_LANDMARKS && b in RIGHT_LANDMARKS -> Color.argb(210, 240, 55, 55)
                else                                          -> Color.argb(210, 255, 215, 0)
            }
            canvas.drawLine(la.xPx * scaleX, la.yPx * scaleY,
                            lb.xPx * scaleX, lb.yPx * scaleY, linePaint)
        }

        for ((i, lm) in landmarks.withIndex()) {
            if (lm == null || lm.visibility < 0.3f) continue
            dotPaint.color = when (i) {
                in LEFT_LANDMARKS  -> Color.argb(230, 0, 200, 70)
                in RIGHT_LANDMARKS -> Color.argb(230, 210, 35, 35)
                else               -> Color.argb(230, 255, 200, 0)
            }
            canvas.drawCircle(lm.xPx * scaleX, lm.yPx * scaleY, radius, dotPaint)
        }
    }

    // ────────────────────────────────────────────────────────────
    // CSV 解析
    // ────────────────────────────────────────────────────────────

    private fun parseCsv(csvPath: String): Map<Int, Array<LandmarkPoint?>> {
        val file = File(csvPath)
        if (!file.exists()) { Log.w(TAG, "CSV 不存在: $csvPath"); return emptyMap() }

        val result = mutableMapOf<Int, Array<LandmarkPoint?>>()
        file.bufferedReader().use { reader ->
            reader.readLine() // 跳過標頭
            var line = reader.readLine()
            while (line != null) {
                val cols = line.split(",")
                if (cols.size >= 201) {
                    val frameIdx = cols[0].trim().toIntOrNull()
                    if (frameIdx != null) {
                        val landmarks = arrayOfNulls<LandmarkPoint>(33)
                        for (i in 0 until 33) {
                            val base  = 3 + i * 6
                            val xNorm = cols[base + 0].trim().toFloatOrNull()?.takeIf { !it.isNaN() }
                            val yNorm = cols[base + 1].trim().toFloatOrNull()?.takeIf { !it.isNaN() }
                            val vis   = cols[base + 3].trim().toFloatOrNull() ?: 0f
                            val xPx   = cols[base + 4].trim().toFloatOrNull()?.takeIf { !it.isNaN() }
                            val yPx   = cols[base + 5].trim().toFloatOrNull()?.takeIf { !it.isNaN() }
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

    private fun inferPoseImageSize(
        frameData: Map<Int, Array<LandmarkPoint?>>,
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

    // ────────────────────────────────────────────────────────────
    // YUV → NV12 直接轉換（含旋轉，無 RGB 中間層）
    // ────────────────────────────────────────────────────────────

    /**
     * 將 YUV420 Image 直接旋轉並寫入 NV12 緩衝區，完全跳過 RGB 中間層。
     *
     * 舊方法：YUV→RGB（6 mul/pixel）+ RGB→NV12（6 mul/pixel）= 12 mul/pixel
     * 新方法：直接複製 Y byte + UV byte，含旋轉座標映射 = 0 mul/pixel
     */
    /**
     * YUV420 → NV12，支援旋轉 + 降解析度（nearest-neighbor）。
     * 迴圈以輸出 (encW×encH) 為準，每個輸出像素映射回 source (srcW×srcH) 再映射到 coded 空間。
     * 無 RGB 中間層：Y/UV byte 直接複製，0 乘法/pixel。
     */
    private fun yuvToNv12WithRotation(
        image: Image,
        codedW: Int, codedH: Int,
        rotation: Int,
        srcW: Int, srcH: Int,    // 原始 display 解析度
        encW: Int, encH: Int,    // 輸出編碼解析度（可小於 srcW×srcH）
        nv12: ByteArray,
    ) {
        val yP = image.planes[0]; val uP = image.planes[1]; val vP = image.planes[2]
        val yStride       = yP.rowStride
        val uvStride      = uP.rowStride
        val uvPixelStride = uP.pixelStride
        val yBytes = ByteArray(yP.buffer.remaining()).also { yP.buffer.get(it) }
        val uBytes = ByteArray(uP.buffer.remaining()).also { uP.buffer.get(it) }
        val vBytes = ByteArray(vP.buffer.remaining()).also { vP.buffer.get(it) }

        val uvBase = encW * encH
        for (dy in 0 until encH) {
            for (dx in 0 until encW) {
                // Nearest-neighbor downscaling: output pixel → source pixel
                val sx = (dx.toLong() * srcW / encW).toInt()
                val sy = (dy.toLong() * srcH / encH).toInt()
                val ci: Int; val cj: Int
                when (rotation) {
                    90  -> { ci = sy;           cj = codedH - 1 - sx }
                    270 -> { ci = codedW-1-sy;  cj = sx               }
                    180 -> { ci = codedW-1-sx;  cj = codedH-1-sy     }
                    else-> { ci = sx;           cj = sy               }
                }
                val yIdx = cj * yStride + ci
                nv12[dy * encW + dx] = if (yIdx < yBytes.size) yBytes[yIdx] else 16
                if (dy % 2 == 0 && dx % 2 == 0) {
                    val uvOff = (cj / 2) * uvStride + (ci / 2) * uvPixelStride
                    val base  = uvBase + (dy / 2) * encW + dx
                    if (base + 1 < nv12.size) {
                        nv12[base]     = if (uvOff < uBytes.size) uBytes[uvOff] else 128.toByte()
                        nv12[base + 1] = if (uvOff < vBytes.size) vBytes[uvOff] else 128.toByte()
                    }
                }
            }
        }
    }

    /**
     * 將骨架 overlay（ARGB Bitmap）composite 進已填好的 NV12 緩衝區。
     * 只處理非透明像素（骨架線條），對完整幀而言是稀疏操作（<1% 像素）。
     */
    private fun compositeSkeleton(
        overlay: Bitmap, pixels: IntArray,
        w: Int, h: Int,
        nv12: ByteArray,
    ) {
        overlay.getPixels(pixels, 0, w, 0, 0, w, h)
        val uvBase = w * h
        for (j in 0 until h) {
            for (i in 0 until w) {
                val argb  = pixels[j * w + i]
                val alpha = (argb ushr 24) and 0xFF
                if (alpha < 16) continue
                val r = (argb shr 16) and 0xFF
                val g = (argb shr 8)  and 0xFF
                val b = argb          and 0xFF
                val yv = (((66 * r + 129 * g + 25 * b + 128) shr 8) + 16).coerceIn(16, 235)
                val yIdx = j * w + i
                nv12[yIdx] = if (alpha >= 240) yv.toByte()
                             else (((nv12[yIdx].toInt() and 0xFF) * (255 - alpha) + yv * alpha + 127) / 255).toByte()
                if (j % 2 == 0 && i % 2 == 0) {
                    val u    = (((-38 * r - 74 * g + 112 * b + 128) shr 8) + 128).coerceIn(16, 240)
                    val v    = (((112 * r - 94 * g - 18 * b + 128) shr 8) + 128).coerceIn(16, 240)
                    val base = uvBase + (j / 2) * w + i
                    if (base + 1 < nv12.size) {
                        nv12[base]     = if (alpha >= 240) u.toByte()
                                         else (((nv12[base].toInt()     and 0xFF) * (255 - alpha) + u * alpha + 127) / 255).toByte()
                        nv12[base + 1] = if (alpha >= 240) v.toByte()
                                         else (((nv12[base + 1].toInt() and 0xFF) * (255 - alpha) + v * alpha + 127) / 255).toByte()
                    }
                }
            }
        }
    }

    // ────────────────────────────────────────────────────────────
    // 編碼器排空
    // ────────────────────────────────────────────────────────────

    private fun drainEncoder(
        encoder: MediaCodec, muxer: MediaMuxer, info: MediaCodec.BufferInfo,
        setTrack: (Int) -> Unit, getTrack: () -> Int, isMuxed: () -> Boolean,
        eos: Boolean,
        onSampleWritten: () -> Unit = {},
    ) {
        var tryAgainCount = 0
        var drainedSamples = 0  // ✅ 追蹤 drainEncoder 內的輸出
        val maxTryAgainCount = 50  // 防止無限迴圈
        
        while (true) {
            val idx = encoder.dequeueOutputBuffer(info, 10_000L)
            when {
                idx == MediaCodec.INFO_TRY_AGAIN_LATER -> {
                    tryAgainCount++
                    if (eos && tryAgainCount > maxTryAgainCount) {
                        // 如果已經有輸出，即使 timeout 也視為成功
                        if (drainedSamples > 0) {
                            Log.w(TAG, "drainEncoder: EOS timeout 後已有 $drainedSamples 個輸出，視為成功")
                            break
                        } else {
                            Log.e(TAG, "drainEncoder: Timeout after $maxTryAgainCount TRY_AGAIN_LATER，且無輸出")
                            break
                        }
                    }
                    
                    // 非 EOS 模式下立即退出
                    if (!eos) break
                }
                idx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    tryAgainCount = 0
                    val t = muxer.addTrack(encoder.outputFormat)
                    muxer.start(); setTrack(t)
                }
                idx >= 0 -> {
                    tryAgainCount = 0
                    val buf = encoder.getOutputBuffer(idx)
                    if (buf != null && info.size > 0 && isMuxed()) {
                        buf.position(info.offset); buf.limit(info.offset + info.size)
                        muxer.writeSampleData(getTrack(), buf, info)
                        onSampleWritten()
                        drainedSamples++
                    } else {
                        Log.w(TAG, "writeSampleData skip: buf=$buf, size=${info.size}, isMuxed=${isMuxed()}")
                    }
                    encoder.releaseOutputBuffer(idx, false)
                    if ((info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) break
                }
            }
        }
    }
}
