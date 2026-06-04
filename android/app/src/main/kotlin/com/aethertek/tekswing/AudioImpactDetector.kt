package com.aethertek.tekswing

import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.util.Log
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * 用 MediaCodec 串流解碼音訊，在解碼過程中直接計算每個窗口的 RMS 能量。
 *
 * ★ 記憶體設計：
 *   不儲存原始 PCM（ArrayList<Short> 裝箱 = OOM on 5+ min videos）
 *   只保留每個窗口的 RMS Double（5 分鐘 ≈ 30,000 個 Double = 240 KB）
 *
 * RMS 窗口大小：WINDOW_MS = 10ms（44100Hz × 2ch → 882 samples / window）
 */
object AudioImpactDetector {

    private const val TAG = "AudioImpactDetector"
    private const val WINDOW_MS = 10        // RMS 窗口毫秒
    private const val SEARCH_SKIP_MS = 500  // 跳過開頭靜音

    // ── 資料類 ────────────────────────────────────────────────────────────────
    /** 串流解碼後的 RMS 列表（每個元素對應一個 WINDOW_MS 窗口的 RMS 值）*/
    private data class RmsData(
        val sampleRate: Int,
        val channels: Int,
        val windowMs: Int,
        val rms: DoubleArray,   // 原始陣列，省記憶體（非裝箱 List<Double>）
    )

    // ── Public API ────────────────────────────────────────────────────────────

    /**
     * 找出影片中最大音訊峰值的毫秒位置（單一最強峰值）。
     * searchStartMs / searchEndMs 可縮小搜尋範圍。
     */
    fun findImpactTime(
        videoPath: String,
        searchStartMs: Long = SEARCH_SKIP_MS.toLong(),
        searchEndMs: Long = -1L,
    ): Long {
        val data = computeRms(videoPath) ?: return -1L
        val startIdx = msToWindowIdx(searchStartMs, data)
        val endIdx   = if (searchEndMs < 0) data.rms.size
                       else msToWindowIdx(searchEndMs, data).coerceAtMost(data.rms.size)

        var maxRms = 0.0; var maxIdx = startIdx
        for (i in startIdx until endIdx) {
            if (data.rms[i] > maxRms) { maxRms = data.rms[i]; maxIdx = i }
        }
        val ms = windowIdxToMs(maxIdx, data)
        Log.i(TAG, "單峰值: ${ms}ms  rms=${"%.4f".format(maxRms)}")
        return ms
    }

    /**
     * 找出影片中所有擊球音訊峰值（複數），按時間排序。
     *
     * @param minGapMs  兩峰值最小間距（預設 2000ms）
     * @param topN      最多回傳幾個峰值
     * @param onProgress 進度回調 (0.0~1.0, label)
     */
    fun findMultiplePeaks(
        videoPath: String,
        searchStartMs: Long = SEARCH_SKIP_MS.toLong(),
        minGapMs: Long = 2000L,
        topN: Int = 20,
        onProgress: ((Double, String) -> Unit)? = null,
    ): List<Long> {
        onProgress?.invoke(0.05, "音訊解碼中…")
        val data = computeRms(videoPath, onProgress = { prog ->
            // 解碼佔 0.05 → 0.80
            onProgress?.invoke(0.05 + prog * 0.75, "掃描聲波 ${(prog * 100).toInt()}%…")
        }) ?: return emptyList()

        onProgress?.invoke(0.82, "分析峰值…")

        val startIdx   = msToWindowIdx(searchStartMs, data)
        val subRms     = data.rms.sliceArray(startIdx until data.rms.size)
        if (subRms.isEmpty()) return emptyList()

        // 自適應門檻：中位數 × 3（過濾背景噪音，保留衝擊峰）
        val sorted    = subRms.clone().also { it.sort() }
        val median    = sorted[sorted.size / 2]
        val threshold = median * 3.0

        // 貪婪選峰（按 RMS 降序，鄰近 minGapMs 內抑制）
        val minGapWindows = (minGapMs / WINDOW_MS).toInt().coerceAtLeast(1)
        data class Entry(val idx: Int, val rms: Double)
        val candidates = subRms.indices
            .filter { subRms[it] >= threshold }
            .map { Entry(startIdx + it, subRms[it]) }
            .sortedByDescending { it.rms }

        val suppressed = BooleanArray(data.rms.size)
        val peaks      = mutableListOf<Long>()
        for (e in candidates) {
            if (peaks.size >= topN) break
            if (e.idx >= suppressed.size || suppressed[e.idx]) continue
            peaks.add(windowIdxToMs(e.idx, data))
            for (i in (e.idx - minGapWindows)..(e.idx + minGapWindows)) {
                if (i in suppressed.indices) suppressed[i] = true
            }
        }

        val result = peaks.sorted()
        onProgress?.invoke(1.0, "偵測完成，共 ${result.size} 個擊球")
        Log.i(TAG, "多峰值: ${result.size} 個  threshold=${"%.4f".format(threshold)}  $result")
        return result
    }

    // ── 核心：串流解碼 → 直接累計 RMS（不存原始 PCM）──────────────────────────

    /**
     * 解碼整條音訊軌，串流計算每 [WINDOW_MS] 毫秒的 RMS。
     * 每個輸出緩衝區直接累加到當前窗口的 sumSq，不存 Short。
     *
     * @param onProgress 解碼進度回調 (0.0~1.0)；需要影片時長才能精確計算，
     *                   若元數據缺時長則改以解碼幀數估算。
     */
    private fun computeRms(
        videoPath: String,
        onProgress: ((Double) -> Unit)? = null,
    ): RmsData? {
        val extractor = MediaExtractor()
        var codec: MediaCodec? = null
        try {
            extractor.setDataSource(videoPath)

            // 找音訊軌
            var trackIdx = -1; var format: MediaFormat? = null
            for (i in 0 until extractor.trackCount) {
                val fmt = extractor.getTrackFormat(i)
                if ((fmt.getString(MediaFormat.KEY_MIME) ?: "").startsWith("audio/")) {
                    trackIdx = i; format = fmt; break
                }
            }
            if (trackIdx < 0 || format == null) { Log.i(TAG, "無音訊軌"); return null }
            extractor.selectTrack(trackIdx)

            val mime       = format.getString(MediaFormat.KEY_MIME)!!
            val sampleRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            val channels   = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)

            // 影片時長（微秒），用於進度計算；讀不到就設 -1
            val durationUs: Long = runCatching {
                format.getLong(MediaFormat.KEY_DURATION).takeIf { it > 0 } ?: -1L
            }.getOrElse { -1L }

            codec = MediaCodec.createDecoderByType(mime)
            codec.configure(format, null, null, 0)
            codec.start()

            // 窗口大小（樣本數，含多聲道）
            val windowSamples = (sampleRate * WINDOW_MS / 1000) * channels
            if (windowSamples <= 0) return null

            // 預估窗口總數（用於動態分配，不足時 ArrayList 自動擴容）
            val estimatedWindows = if (durationUs > 0)
                ((durationUs / 1000L) / WINDOW_MS + 1).toInt().coerceAtLeast(100)
            else 60_000  // 預設 10 分鐘上限
            val rmsList = ArrayList<Double>(estimatedWindows)

            // 當前窗口的累計狀態（純 primitive，無裝箱）
            var winSumSq      = 0.0
            var winSampleCount = 0
            var lastProgressPct = -1
            val bufInfo = MediaCodec.BufferInfo()
            var inputEos = false; var outputEos = false
            // 可重用解碼緩衝區（延遲分配，避免每幀 new）
            var pcmFloat: FloatArray? = null
            var pcmBytes: ByteArray? = null

            while (!outputEos) {
                // 餵輸入
                if (!inputEos) {
                    val inIdx = codec.dequeueInputBuffer(5000L)
                    if (inIdx >= 0) {
                        val buf  = codec.getInputBuffer(inIdx)!!
                        val size = extractor.readSampleData(buf, 0)
                        if (size < 0) {
                            codec.queueInputBuffer(inIdx, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputEos = true
                        } else {
                            codec.queueInputBuffer(inIdx, 0, size, extractor.sampleTime, 0)
                            extractor.advance()
                        }
                    }
                }

                // 取輸出
                val outIdx = codec.dequeueOutputBuffer(bufInfo, 5000L)
                when {
                    outIdx == MediaCodec.INFO_TRY_AGAIN_LATER -> {}
                    outIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {}
                    outIdx >= 0 -> {
                        val buf = codec.getOutputBuffer(outIdx)
                        if (buf != null && bufInfo.size > 0) {
                            val enc = if (codec.outputFormat.containsKey(MediaFormat.KEY_PCM_ENCODING))
                                codec.outputFormat.getInteger(MediaFormat.KEY_PCM_ENCODING)
                            else AudioFormat.ENCODING_PCM_16BIT

                            // ── 串流累加 RMS（不存 Short，直接計算）────────────────
                            val slice = buf.duplicate().order(ByteOrder.nativeOrder())
                            slice.position(0); slice.limit(bufInfo.size)

                            when (enc) {
                                AudioFormat.ENCODING_PCM_FLOAT -> {
                                    val count = bufInfo.size / 4
                                    if (pcmFloat == null || pcmFloat!!.size < count) pcmFloat = FloatArray(count)
                                    slice.asFloatBuffer().get(pcmFloat!!, 0, count)
                                    for (i in 0 until count) {
                                        val v = pcmFloat!![i].toDouble().coerceIn(-1.0, 1.0)
                                        winSumSq += v * v; winSampleCount++
                                        if (winSampleCount >= windowSamples) {
                                            rmsList.add(Math.sqrt(winSumSq / windowSamples))
                                            winSumSq = 0.0; winSampleCount = 0
                                        }
                                    }
                                }
                                AudioFormat.ENCODING_PCM_8BIT -> {
                                    val count = bufInfo.size
                                    if (pcmBytes == null || pcmBytes!!.size < count) pcmBytes = ByteArray(count)
                                    slice.get(pcmBytes!!, 0, count)
                                    for (i in 0 until count) {
                                        val v = ((pcmBytes!![i].toInt() and 0xFF) - 128) / 128.0
                                        winSumSq += v * v; winSampleCount++
                                        if (winSampleCount >= windowSamples) {
                                            rmsList.add(Math.sqrt(winSumSq / windowSamples))
                                            winSumSq = 0.0; winSampleCount = 0
                                        }
                                    }
                                }
                                else -> { // PCM_16BIT
                                    val sb = slice.asShortBuffer()
                                    while (sb.hasRemaining()) {
                                        val v = sb.get().toDouble() / Short.MAX_VALUE
                                        winSumSq += v * v; winSampleCount++
                                        if (winSampleCount >= windowSamples) {
                                            rmsList.add(Math.sqrt(winSumSq / windowSamples))
                                            winSumSq = 0.0; winSampleCount = 0
                                        }
                                    }
                                }
                            }

                            // 進度推送（每 5% 一次）
                            if (onProgress != null && durationUs > 0) {
                                val pct = ((bufInfo.presentationTimeUs * 20) / durationUs).toInt().coerceIn(0, 20)
                                if (pct != lastProgressPct) {
                                    lastProgressPct = pct
                                    onProgress.invoke(pct / 20.0)
                                }
                            }
                        }
                        codec.releaseOutputBuffer(outIdx, false)
                        if ((bufInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) outputEos = true
                    }
                }
            }

            // 最後一個不完整窗口也加入
            if (winSampleCount > 0) {
                rmsList.add(Math.sqrt(winSumSq / winSampleCount))
            }

            if (rmsList.isEmpty()) return null
            Log.i(TAG, "RMS 計算完成: ${rmsList.size} 窗口，記憶體=${rmsList.size * 8 / 1024}KB")
            return RmsData(sampleRate, channels, WINDOW_MS, rmsList.toDoubleArray())

        } catch (e: Exception) {
            Log.e(TAG, "computeRms 失敗: ${e.message}", e)
            return null
        } finally {
            runCatching { codec?.stop(); codec?.release() }
            runCatching { extractor.release() }
        }
    }

    // ── 工具函式 ─────────────────────────────────────────────────────────────

    /** 毫秒 → 窗口索引（floor） */
    private fun msToWindowIdx(ms: Long, data: RmsData): Int =
        (ms / data.windowMs).toInt().coerceIn(0, data.rms.size)

    /** 窗口索引中心 → 毫秒 */
    private fun windowIdxToMs(idx: Int, data: RmsData): Long =
        (idx.toLong() * data.windowMs) + (data.windowMs / 2)
}
