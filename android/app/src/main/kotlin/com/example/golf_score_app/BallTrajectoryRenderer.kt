package com.example.golf_score_app

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
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
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sqrt

/**
 * 高爾夫球軌跡追蹤渲染器。
 *
 * 輸入：已含骨架 overlay 的 mp4 片段
 * 輸出：加上球軌跡曲線的 mp4
 *
 * 演算法與 trajectory_tracker_v3_stable.py 對齊：
 *   幀差偵測 → BFS 連通域 → Kalman 濾波 → 四狀態機 → 軌跡繪製
 */
class BallTrajectoryRenderer(private val context: Context) {

    // ----------------------------------------------------------------
    // 設定常數
    // ----------------------------------------------------------------
    companion object {
        private const val TAG = "BallTraj"

        // 偵測
        private const val DIFF_THRESH = 16
        private const val AREA_LO = 4
        private const val AREA_HI = 600         // 手機高解析影像球面積較大
        private const val CIRC_THRESH = 0.40f   // 稍微放寬，對應遠球橢圓
        private const val MORPH_KERNEL = 3      // 形態開運算 3×3 kernel

        // 狀態機
        private const val P1_DEADLINE = 3       // 捕捉 P1 的最大幀數寬限
        private const val WAIT_MAX = 45         // 等不到 P0 上限
        private const val NO_CAND_PATIENCE = 5  // 連續無候選 → 停止
        private const val TOO_MANY_STOP = 35    // 候選過多 → 背景干擾，停止

        // 步長守衛（Kalman 預測距離上限）
        private const val STEP_ABS_MAX = 220f

        // 軌跡繪製
        private val TRAJ_COLOR = Color.argb(230, 255, 210, 30)  // 金黃
        private const val TRAJ_STROKE = 7f
        private const val DOT_RADIUS = 9f

        // 狀態
        private const val S_WAIT_P0 = 0
        private const val S_WAIT_P1 = 1
        private const val S_TRACKING = 2
        private const val S_STOPPED = 3
    }

    // ----------------------------------------------------------------
    // 候選球 blob
    // ----------------------------------------------------------------
    private data class Blob(val cx: Int, val cy: Int, val area: Int, val perim: Int) {
        val circ: Float
            get() = if (perim < 1) 0f
            else (4.0 * Math.PI * area / (perim.toDouble() * perim)).toFloat()
    }

    // ----------------------------------------------------------------
    // Kalman 濾波器（常速模型，4 維狀態 [px,py,vx,vy]）
    // ----------------------------------------------------------------
    private inner class Kalman2D(private val dt: Float) {
        // 狀態向量
        private val x = FloatArray(4)
        // 協方差矩陣（4×4，row-major）
        private val P = FloatArray(16) { if (it % 5 == 0) 1000f else 0f }
        var initialized = false

        // 系統矩陣 A（常速）
        private val A = floatArrayOf(
            1f, 0f, dt, 0f,
            0f, 1f, 0f, dt,
            0f, 0f, 1f, 0f,
            0f, 0f, 0f, 1f
        )
        // H（量測矩陣：只量 px, py）
        // H = [[1,0,0,0],[0,1,0,0]]
        // Q（過程噪聲）
        private val Q = floatArrayOf(
            3f, 0f, 0f, 0f,
            0f, 3f, 0f, 0f,
            0f, 0f, 120f, 0f,
            0f, 0f, 0f, 120f
        )
        // R（量測噪聲）
        private val R = floatArrayOf(10f, 0f, 0f, 10f)

        fun initFromPoints(p0: Pair<Int, Int>, p1: Pair<Int, Int>) {
            val safedt = max(dt, 1e-6f)
            x[0] = p1.first.toFloat()
            x[1] = p1.second.toFloat()
            x[2] = (p1.first - p0.first) / safedt
            x[3] = (p1.second - p0.second) / safedt
            P[0] = 80f; P[5] = 80f; P[10] = 900f; P[15] = 900f
            initialized = true
        }

        fun predict() {
            // x = A × x
            val nx = FloatArray(4)
            for (i in 0 until 4) {
                var s = 0f
                for (k in 0 until 4) s += A[i * 4 + k] * x[k]
                nx[i] = s
            }
            nx.copyInto(x)
            // P = A × P × A^T + Q
            val AP = mat44Mul(A, P)
            val AT = mat44T(A)
            val APAT = mat44Mul(AP, AT)
            for (i in 0 until 16) P[i] = APAT[i] + Q[i]
        }

        fun update(zx: Float, zy: Float) {
            // y = z - H×x  → y = [zx - x[0], zy - x[1]]
            val yx = zx - x[0]; val yy = zy - x[1]

            // S = H × P × H^T + R  (S is 2×2)
            // H×P: rows 0 and 1 of P
            val HP = floatArrayOf(
                P[0], P[1], P[2], P[3],   // row 0 of P
                P[4], P[5], P[6], P[7]    // row 1 of P
            )
            // HP × H^T: columns 0 and 1 of HP (since H^T = first 2 columns of I4)
            val S = floatArrayOf(HP[0] + R[0], HP[1] + R[1], HP[4] + R[2], HP[5] + R[3])
            val Si = mat22Inv(S) // S^-1

            // K = P × H^T × S^-1
            // P × H^T: columns 0 and 1 of P (4×2)
            val PHt = floatArrayOf(
                P[0], P[4],
                P[1], P[5],
                P[2], P[6],
                P[3], P[7]
            )
            // K = PHt × Si  (4×2 × 2×2 → 4×2)
            val K = FloatArray(8)
            for (i in 0 until 4) {
                K[i * 2 + 0] = PHt[i * 2 + 0] * Si[0] + PHt[i * 2 + 1] * Si[2]
                K[i * 2 + 1] = PHt[i * 2 + 0] * Si[1] + PHt[i * 2 + 1] * Si[3]
            }

            // x = x + K × y
            x[0] += K[0] * yx + K[1] * yy
            x[1] += K[2] * yx + K[3] * yy
            x[2] += K[4] * yx + K[5] * yy
            x[3] += K[6] * yx + K[7] * yy

            // P = (I - K × H) × P
            // K × H: rows = K column × H row
            val KH = FloatArray(16)
            KH[0] = K[0]; KH[1] = K[1]; KH[4] = K[2]; KH[5] = K[3]
            KH[8] = K[4]; KH[9] = K[5]; KH[12] = K[6]; KH[13] = K[7]
            val ImKH = FloatArray(16) { if (it % 5 == 0) 1f - KH[it] else -KH[it] }
            val newP = mat44Mul(ImKH, P)
            newP.copyInto(P)
        }

        fun pos() = Pair(x[0], x[1])
    }

    // ----------------------------------------------------------------
    // 矩陣輔助函式
    // ----------------------------------------------------------------
    private fun mat44Mul(A: FloatArray, B: FloatArray): FloatArray {
        val C = FloatArray(16)
        for (i in 0 until 4) for (j in 0 until 4) {
            var s = 0f
            for (k in 0 until 4) s += A[i * 4 + k] * B[k * 4 + j]
            C[i * 4 + j] = s
        }
        return C
    }

    private fun mat44T(A: FloatArray): FloatArray {
        val B = FloatArray(16)
        for (i in 0 until 4) for (j in 0 until 4) B[i * 4 + j] = A[j * 4 + i]
        return B
    }

    private fun mat22Inv(A: FloatArray): FloatArray {
        val det = A[0] * A[3] - A[1] * A[2]
        if (abs(det) < 1e-8f) return floatArrayOf(1f, 0f, 0f, 1f)
        val inv = 1f / det
        return floatArrayOf(A[3] * inv, -A[1] * inv, -A[2] * inv, A[0] * inv)
    }

    // ----------------------------------------------------------------
    // 主入口
    // ----------------------------------------------------------------
    /**
     * @param inputPath  含骨架的 mp4 片段（SkeletonOverlayRenderer 的輸出）
     * @param outputPath 最終輸出路徑（骨架 + 球軌跡）
     * @return 成功回傳 true
     */
    fun render(inputPath: String, outputPath: String): Boolean {
        if (!File(inputPath).exists()) {
            Log.w(TAG, "輸入檔不存在: $inputPath")
            return false
        }

        // 1. 建立 MediaExtractor
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(inputPath)
        } catch (e: Exception) {
            Log.e(TAG, "無法開啟輸入: $e"); return false
        }

        // 找視頻 track
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

        val videoW = inputFormat.getInteger(MediaFormat.KEY_WIDTH)
        val videoH = inputFormat.getInteger(MediaFormat.KEY_HEIGHT)
        val videoMime = inputFormat.getString(MediaFormat.KEY_MIME) ?: "video/avc"
        val fps = runCatching { inputFormat.getInteger(MediaFormat.KEY_FRAME_RATE).toFloat() }
            .getOrElse { 15f }
        val dt = 1f / max(fps, 1f)
        // ✅ 提取旋轉信息
        val rotation = runCatching {
            inputFormat.getInteger(MediaFormat.KEY_ROTATION)
        }.getOrElse { 0 }
        Log.d(TAG, "輸入: ${videoW}x${videoH} fps=$fps rotation=$rotation° mime=$videoMime")

        // 2. 建立解碼器
        val decoder = try {
            MediaCodec.createDecoderByType(videoMime)
        } catch (e: Exception) {
            Log.e(TAG, "無法建立解碼器: $e"); extractor.release(); return false
        }
        decoder.configure(inputFormat, null, null, 0)
        decoder.start()

        // 3. 建立編碼器
        val encoder = try {
            MediaCodec.createEncoderByType("video/avc")
        } catch (e: Exception) {
            Log.e(TAG, "無法建立編碼器: $e")
            decoder.stop(); decoder.release(); extractor.release(); return false
        }
        val encFmt = MediaFormat.createVideoFormat("video/avc", videoW, videoH).apply {
            setInteger(MediaFormat.KEY_COLOR_FORMAT, CodecCapabilities.COLOR_FormatYUV420Flexible)
            setInteger(MediaFormat.KEY_BIT_RATE, 4_000_000)
            setInteger(MediaFormat.KEY_FRAME_RATE, fps.roundToInt())
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
            // ✅ 保留旋轉信息
            if (rotation != 0) {
                setInteger(MediaFormat.KEY_ROTATION, rotation)
                Log.d(TAG, "編碼器設置旋轉: $rotation°")
            }
        }
        encoder.configure(encFmt, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        encoder.start()

        File(outputPath).parentFile?.mkdirs()
        val muxer = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        var muxTrack = -1
        var muxStarted = false
        var formatChanged = false  // ✅ 追蹤 format change

        // 4. 軌跡狀態
        val kf = Kalman2D(dt)
        var state = S_WAIT_P0
        val trackPts = mutableListOf<Pair<Int, Int>>()
        var p0FrameIdx = -1
        var frameIdx = 0        // ✅ 當前幀計數
        var frameCount = 0      // ✅ 追蹤輸入幀
        var encodedFrames = 0   // ✅ 追蹤編碼幀
        var samplesWritten = 0  // ✅ 追蹤寫入樣本
        var waitFrames = 0      // ✅ 等待計數
        var noCandCount = 0     // ✅ 無候選計數
        var prevYData: ByteArray? = null  // ✅ 上一幀 Y 數據
        var prevYStride = 0     // ✅ 上一幀 stride

        val decBufInfo = MediaCodec.BufferInfo()
        val encBufInfo = MediaCodec.BufferInfo()
        var inputEos = false
        var success = false

        try {
            while (true) {
                // ── 餵解碼器 ──────────────────────────────────────────
                if (!inputEos) {
                    val inIdx = decoder.dequeueInputBuffer(0L)
                    if (inIdx >= 0) {
                        val buf = decoder.getInputBuffer(inIdx)!!
                        val size = extractor.readSampleData(buf, 0)
                        if (size < 0) {
                            decoder.queueInputBuffer(inIdx, 0, 0, 0,
                                MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputEos = true
                        } else {
                            decoder.queueInputBuffer(inIdx, 0, size,
                                extractor.sampleTime, 0)
                            extractor.advance()
                        }
                    }
                }

                // ── 取解碼器輸出 ──────────────────────────────────────
                val outIdx = decoder.dequeueOutputBuffer(decBufInfo, 10_000L)
                if (outIdx == MediaCodec.INFO_TRY_AGAIN_LATER) {
                    if (inputEos) continue else continue
                }
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

                    // ── Y 平面提取（灰階用於球偵測）─────────────────
                    val yPlane = image.planes[0]
                    val yStride = yPlane.rowStride
                    val yBuf = yPlane.buffer
                    val yData = ByteArray(videoH * yStride)
                    yBuf.get(yData)

                    // ── 幀差偵測 ─────────────────────────────────────
                    val candidates: List<Blob>
                    val prevY = prevYData
                    candidates = if (prevY != null && prevY.size == yData.size) {
                        detectBlobs(yData, prevY, videoW, videoH, yStride)
                    } else emptyList()

                    // ── 狀態機 ────────────────────────────────────────
                    when (state) {
                        S_WAIT_P0 -> {
                            waitFrames++
                            val best = candidates.minByOrNull {
                                dist2(it.cx, it.cy, videoW / 2, videoH / 2)
                            }
                            if (best != null) {
                                trackPts.add(best.cx to best.cy)
                                state = S_WAIT_P1
                                p0FrameIdx = frameIdx
                                waitFrames = 0
                            } else if (waitFrames > WAIT_MAX) {
                                Log.d(TAG, "等待 P0 超時")
                                state = S_STOPPED
                            }
                        }

                        S_WAIT_P1 -> {
                            waitFrames++
                            if (frameIdx - p0FrameIdx > P1_DEADLINE) {
                                // P1 超時，重置
                                trackPts.clear(); state = S_WAIT_P0; waitFrames = 0
                            } else {
                                val p0 = trackPts[0]
                                val valid = candidates.filter { c ->
                                    dist(c.cx, c.cy, p0.first, p0.second) > 3f
                                }
                                val best = valid.minByOrNull {
                                    dist2(it.cx, it.cy, p0.first, p0.second)
                                }
                                if (best != null) {
                                    trackPts.add(best.cx to best.cy)
                                    kf.initFromPoints(p0, best.cx to best.cy)
                                    state = S_TRACKING
                                    noCandCount = 0
                                    Log.d(TAG, "開始追蹤: p0=$p0 p1=(${best.cx},${best.cy})")
                                }
                            }
                        }

                        S_TRACKING -> {
                            kf.predict()
                            val (px, py) = kf.pos()

                            if (candidates.isEmpty()) {
                                noCandCount++
                                if (noCandCount > NO_CAND_PATIENCE) {
                                    Log.d(TAG, "連續 $noCandCount 幀無候選，停止")
                                    state = S_STOPPED
                                }
                            } else if (candidates.size >= TOO_MANY_STOP) {
                                Log.d(TAG, "候選過多（${candidates.size}），視為背景，停止")
                                state = S_STOPPED
                            } else {
                                noCandCount = 0
                                val best = candidates.minByOrNull {
                                    dist2(it.cx, it.cy, px.toInt(), py.toInt())
                                }!!
                                val step = dist(best.cx, best.cy, px.toInt(), py.toInt())
                                if (step <= STEP_ABS_MAX) {
                                    kf.update(best.cx.toFloat(), best.cy.toFloat())
                                    trackPts.add(best.cx to best.cy)
                                } else {
                                    Log.d(TAG, "步長 ${step.toInt()} 超過上限，略過此幀")
                                }
                            }
                        }
                    }

                    // ── YUV → Bitmap，繪製軌跡 ────────────────────────
                    val bmp = yuvImageToBitmap(image, videoW, videoH)
                    if (trackPts.size >= 2) {
                        drawTrajectory(Canvas(bmp), trackPts, videoW, videoH)
                    }

                    // ── Bitmap → 編碼器 ───────────────────────────────
                    val encInIdx = encoder.dequeueInputBuffer(50_000L)
                    // ✅ 用 frameCount 計算正確的 pts
                    val ptsUs = frameCount * 1_000_000L / fps.toLong()
                    
                    if (encInIdx >= 0) {
                        val buf = encoder.getInputBuffer(encInIdx)!!
                        val nv12 = bitmapToNv12(bmp, videoW, videoH)
                        buf.clear()
                        buf.put(nv12)
                        encoder.queueInputBuffer(encInIdx, 0, nv12.size, ptsUs, 0)
                    }
                    bmp.recycle()

                    // 排空編碼器輸出
                    drainEncoder(encoder, muxer, encBufInfo,
                        setTrack = { t -> muxTrack = t; muxStarted = true; formatChanged = true },
                        getTrack = { muxTrack },
                        isMuxStarted = { muxStarted },
                        eos = false,
                        onSampleWritten = { encodedFrames++; samplesWritten++ })

                    prevYData = yData
                    prevYStride = yStride
                    frameIdx++    // ✅ 遞增幀索引
                    frameCount++  // ✅ 計數輸入幀

                } finally {
                    image.close()
                    decoder.releaseOutputBuffer(outIdx, false)
                }

                if ((decBufInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) break
            }

            // ── EOS ──────────────────────────────────────────────
            Log.d(TAG, "Signaling EOS to encoder, frameCount=$frameCount")
            
            if (frameCount > 0) {
                val eosIdx = encoder.dequeueInputBuffer(100_000L)
                if (eosIdx >= 0) {
                    val ptsUs = frameCount * 1_000_000L / fps.toLong()
                    encoder.queueInputBuffer(eosIdx, 0, 0, ptsUs,
                        MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                    Log.d(TAG, "EOS queued at index $eosIdx, ptsUs=$ptsUs")
                }
                drainEncoder(encoder, muxer, encBufInfo,
                    setTrack = { t -> muxTrack = t; muxStarted = true; formatChanged = true },
                    getTrack = { muxTrack },
                    isMuxStarted = { muxStarted },
                    eos = true,
                    onSampleWritten = { encodedFrames++; samplesWritten++ })
            }
            
            // ✅ 改進的成功條件判定
            if (formatChanged && encodedFrames > 0 && samplesWritten > 0) {
                Log.d(TAG, "✅ 編碼成功: frameCount=$frameCount, encodedFrames=$encodedFrames, samplesWritten=$samplesWritten")
                
                // ✅ 驗證輸出 MP4 有效性
                if (isValidVideo(outputPath)) {
                    success = true
                    Log.d(TAG, "✅ final.mp4 驗證通過: ${trackPts.size} 軌跡點 → $outputPath")
                } else {
                    Log.e(TAG, "❌ final.mp4 驗證失敗，檔案損壞")
                    success = false
                }
            } else {
                Log.e(TAG, "❌ 編碼失敗: formatChanged=$formatChanged, encodedFrames=$encodedFrames, samplesWritten=$samplesWritten")
                success = false
            }

        } catch (e: Exception) {
            Log.e(TAG, "渲染失敗: $e", e)
            success = false
        } finally {
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

    private fun isValidVideo(path: String): Boolean {
        return try {
            val retriever = android.media.MediaMetadataRetriever()
            retriever.setDataSource(path)
            val hasVideo = retriever.extractMetadata(
                android.media.MediaMetadataRetriever.METADATA_KEY_HAS_VIDEO) == "yes"
            val duration = retriever.extractMetadata(
                android.media.MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
            retriever.release()
            hasVideo && duration > 0
        } catch (e: Exception) {
            Log.e(TAG, "MP4 驗證異常: $e")
            false
        }
    }

    // ----------------------------------------------------------------
    // 幀差偵測 → BFS 連通域 → 候選球列表
    // ----------------------------------------------------------------
    private fun detectBlobs(
        cur: ByteArray, prev: ByteArray,
        w: Int, h: Int, stride: Int
    ): List<Blob> {
        // 1. 幀差 + 二值化
        val binary = BooleanArray(w * h)
        for (j in 0 until h) {
            for (i in 0 until w) {
                val c = cur[j * stride + i].toInt() and 0xFF
                val p = prev[j * stride + i].toInt() and 0xFF
                binary[j * w + i] = abs(c - p) >= DIFF_THRESH
            }
        }

        // 2. 形態學開運算 3×3（侵蝕 → 膨脹）
        val opened = morphOpen(binary, w, h, MORPH_KERNEL)

        // 3. BFS 連通域
        val visited = BooleanArray(w * h)
        val blobs = mutableListOf<Blob>()
        val queue = ArrayDeque<Int>(256)

        for (start in 0 until w * h) {
            if (!opened[start] || visited[start]) continue

            queue.clear()
            queue.add(start)
            visited[start] = true

            var sumX = 0L; var sumY = 0L; var area = 0; var perim = 0

            while (queue.isNotEmpty()) {
                val idx = queue.removeFirst()
                val px = idx % w; val py = idx / w
                sumX += px; sumY += py; area++

                var isBorder = false
                // 4-連通
                val ns = intArrayOf(
                    if (px > 0) idx - 1 else -1,
                    if (px < w - 1) idx + 1 else -1,
                    if (py > 0) idx - w else -1,
                    if (py < h - 1) idx + w else -1
                )
                for (n in ns) {
                    if (n < 0 || !opened[n]) { isBorder = true; continue }
                    if (!visited[n]) { visited[n] = true; queue.add(n) }
                }
                if (isBorder) perim++
            }

            if (area !in AREA_LO..AREA_HI) continue
            val cx = (sumX / area).toInt()
            val cy = (sumY / area).toInt()
            val blob = Blob(cx, cy, area, perim)
            if (blob.circ >= CIRC_THRESH) blobs.add(blob)
        }
        return blobs
    }

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

    // ----------------------------------------------------------------
    // 軌跡繪製
    // ----------------------------------------------------------------
    private fun drawTrajectory(canvas: Canvas, pts: List<Pair<Int, Int>>, w: Int, h: Int, rotation: Int = 0) {
        if (pts.size < 2) return

        // ❌ 不應用旋轉轉換 - 軌跡保持原始座標

        val linePaint = Paint().apply {
            color = TRAJ_COLOR
            strokeWidth = TRAJ_STROKE
            style = Paint.Style.STROKE
            isAntiAlias = true
            strokeCap = Paint.Cap.ROUND
            strokeJoin = Paint.Join.ROUND
        }
        val dotPaint = Paint().apply {
            color = Color.argb(255, 255, 255, 255)
            style = Paint.Style.FILL
            isAntiAlias = true
        }
        val shadowPaint = Paint().apply {
            color = Color.argb(100, 0, 0, 0)
            strokeWidth = TRAJ_STROKE + 3f
            style = Paint.Style.STROKE
            isAntiAlias = true
            strokeCap = Paint.Cap.ROUND
        }

        // 陰影線（略粗，黑色半透明）
        for (i in 1 until pts.size) {
            val x1 = pts[i - 1].first.toFloat()
            val y1 = pts[i - 1].second.toFloat()
            val x2 = pts[i].first.toFloat()
            val y2 = pts[i].second.toFloat()
            canvas.drawLine(x1, y1, x2, y2, shadowPaint)
        }
        // 軌跡線
        for (i in 1 until pts.size) {
            val x1 = pts[i - 1].first.toFloat()
            val y1 = pts[i - 1].second.toFloat()
            val x2 = pts[i].first.toFloat()
            val y2 = pts[i].second.toFloat()
            canvas.drawLine(x1, y1, x2, y2, linePaint)
        }
        // 最新點白色圓點
        val last = pts.last()
        val lastX = last.first.toFloat()
        val lastY = last.second.toFloat()
        canvas.drawCircle(lastX, lastY, DOT_RADIUS, dotPaint)
        canvas.drawCircle(lastX, lastY, DOT_RADIUS, linePaint.apply {
            style = Paint.Style.STROKE; strokeWidth = 2f
        })
    }

    // ----------------------------------------------------------------
    // YUV Image → Bitmap（保留彩色，供骨架可見）
    // ----------------------------------------------------------------
    private fun yuvImageToBitmap(image: Image, w: Int, h: Int): Bitmap {
        val yPlane = image.planes[0]
        val uPlane = image.planes[1]
        val vPlane = image.planes[2]

        val yBuf = yPlane.buffer; val uBuf = uPlane.buffer; val vBuf = vPlane.buffer
        val yStride = yPlane.rowStride
        val uvStride = uPlane.rowStride
        val uvPixelStride = uPlane.pixelStride

        val pixels = IntArray(w * h)
        for (j in 0 until h) {
            for (i in 0 until w) {
                val yv = (yBuf[j * yStride + i].toInt() and 0xFF) - 16
                val uvOff = (j / 2) * uvStride + (i / 2) * uvPixelStride
                val u = (uBuf[uvOff].toInt() and 0xFF) - 128
                val v = (vBuf[uvOff].toInt() and 0xFF) - 128

                val r = ((298 * yv + 409 * v + 128) shr 8).coerceIn(0, 255)
                val g = ((298 * yv - 100 * u - 208 * v + 128) shr 8).coerceIn(0, 255)
                val b = ((298 * yv + 516 * u + 128) shr 8).coerceIn(0, 255)
                pixels[j * w + i] = (0xFF shl 24) or (r shl 16) or (g shl 8) or b
            }
        }
        val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        bmp.setPixels(pixels, 0, w, 0, 0, w, h)
        return bmp
    }

    // ----------------------------------------------------------------
    // Bitmap → YUV420Flexible (Image API)
    // ----------------------------------------------------------------
    private fun bitmapFillYuv(image: Image, bmp: Bitmap, w: Int, h: Int) {
        val pixels = IntArray(w * h)
        bmp.getPixels(pixels, 0, w, 0, 0, w, h)

        val yP = image.planes[0]; val uP = image.planes[1]; val vP = image.planes[2]
        val yBuf = yP.buffer; val uBuf = uP.buffer; val vBuf = vP.buffer
        val yStride = yP.rowStride; val uvStride = uP.rowStride; val uvPixelStride = uP.pixelStride

        for (j in 0 until h) {
            for (i in 0 until w) {
                val p = pixels[j * w + i]
                val r = (p shr 16) and 0xFF; val g = (p shr 8) and 0xFF; val b = p and 0xFF
                val y = ((66 * r + 129 * g + 25 * b + 128) shr 8) + 16
                yBuf.put(j * yStride + i, y.toByte())
                if (j % 2 == 0 && i % 2 == 0) {
                    val u = ((-38 * r - 74 * g + 112 * b + 128) shr 8) + 128
                    val v = ((112 * r - 94 * g - 18 * b + 128) shr 8) + 128
                    val uvOff = (j / 2) * uvStride + (i / 2) * uvPixelStride
                    uBuf.put(uvOff, u.toByte()); vBuf.put(uvOff, v.toByte())
                }
            }
        }
    }

    // ----------------------------------------------------------------
    // Bitmap → NV12 ByteArray（備援）
    // ----------------------------------------------------------------
    private fun bitmapToNv12(bmp: Bitmap, w: Int, h: Int): ByteArray {
        val pixels = IntArray(w * h)
        bmp.getPixels(pixels, 0, w, 0, 0, w, h)
        val nv12 = ByteArray(w * h + w * h / 2)
        for (j in 0 until h) {
            for (i in 0 until w) {
                val p = pixels[j * w + i]
                val r = (p shr 16) and 0xFF; val g = (p shr 8) and 0xFF; val b = p and 0xFF
                val y = ((66 * r + 129 * g + 25 * b + 128) shr 8) + 16
                nv12[j * w + i] = y.toByte()
                if (j % 2 == 0 && i % 2 == 0) {
                    val u = ((-38 * r - 74 * g + 112 * b + 128) shr 8) + 128
                    val v = ((112 * r - 94 * g - 18 * b + 128) shr 8) + 128
                    val uvBase = w * h + (j / 2) * w + (i / 2) * 2
                    if (uvBase + 1 < nv12.size) { nv12[uvBase] = u.toByte(); nv12[uvBase + 1] = v.toByte() }
                }
            }
        }
        return nv12
    }

    // ----------------------------------------------------------------
    // 編碼器排空
    // ----------------------------------------------------------------
    private fun drainEncoder(
        encoder: MediaCodec, muxer: MediaMuxer, info: MediaCodec.BufferInfo,
        setTrack: (Int) -> Unit, getTrack: () -> Int, isMuxStarted: () -> Boolean,
        eos: Boolean,
        onSampleWritten: () -> Unit = {},
    ) {
        var tryAgainCount = 0
        var drainedSamples = 0
        val maxTryAgainCount = 50
        
        while (true) {
            val idx = encoder.dequeueOutputBuffer(info, if (eos) 10_000L else 0L)
            when {
                idx == MediaCodec.INFO_TRY_AGAIN_LATER -> {
                    tryAgainCount++
                    if (eos && tryAgainCount > maxTryAgainCount) {
                        if (drainedSamples > 0) {
                            Log.w(TAG, "drainEncoder: EOS timeout, but got $drainedSamples samples")
                            break
                        } else {
                            Log.e(TAG, "drainEncoder: Timeout with no output")
                            break
                        }
                    }
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
                    if (buf != null && info.size > 0 && isMuxStarted()) {
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

    // ----------------------------------------------------------------
    // 工具
    // ----------------------------------------------------------------
    private fun dist(ax: Int, ay: Int, bx: Int, by: Int): Float {
        val dx = (ax - bx).toFloat(); val dy = (ay - by).toFloat()
        return sqrt(dx * dx + dy * dy)
    }

    private fun dist2(ax: Int, ay: Int, bx: Int, by: Int): Float {
        val dx = (ax - bx).toFloat(); val dy = (ay - by).toFloat()
        return dx * dx + dy * dy
    }
}
