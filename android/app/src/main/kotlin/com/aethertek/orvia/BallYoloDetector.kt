package com.aethertek.orvia

import android.content.res.AssetManager
import android.util.Log
import com.aethertek.orvia.BuildConfig
import org.tensorflow.lite.DataType
import org.tensorflow.lite.Interpreter
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.max
import kotlin.math.min

/**
 * YOLOv8n TFLite 高爾夫球偵測器。
 *
 * 模型規格（golfballyolov8n_int8.tflite — 實際 FLOAT32 export）：
 *   Input : [1, 640, 640, 3] FLOAT32，pixel/255（0~1 normalized）
 *   Output: [1, 5, 8400] FLOAT32
 *     channels: cx(px), cy(px), w(px), h(px), conf — 相對於 640×640 input
 *
 * 此模型以 SAHI 訓練，每次推論只接受 640×640 的「裁切區域」。
 * 呼叫端（BallYoloExtractor）負責維護 ROI 中心，並傳入 roiCenterX / roiCenterY。
 *
 * detect() 回傳座標已轉換回原始 frame 座標空間。
 */
class BallYoloDetector(private val assetManager: AssetManager) {

    companion object {
        private const val TAG = "BallYoloDetector"
        private const val MODEL_ASSET =
            "flutter_assets/assets/models/golfballyolov8n_int8.tflite"
        const val INPUT_SIZE     = 640
        private const val CONF_THRESHOLD = 0.25f
        private const val NMS_IOU        = 0.45f
        // tile 邊緣 margin：排除距邊界太近的偵測（false positive 常出現在 tile 角落）
        private const val TILE_EDGE_MARGIN = 24f  // pixels in tile space (640×640)
    }

    private var interpreter: Interpreter? = null

    // 輸入 tensor 型態
    private var inIsFloat   = false
    private var inZeroPoint = -128

    // 輸出 tensor 量化參數
    private var outIsFloat   = true
    private var outScale     = 1.0f
    private var outZeroPoint = 0
    private var detectionOutputIdx = 0

    // 可重用 buffer（tryLoad 後依實際型態分配）
    private var inputBuf:  ByteBuffer? = null
    private var outputBuf: ByteBuffer? = null

    // debug 計數
    private var detectCallCount = 0

    // coordScale 快取：模型格式不會改變，第一次確認後不再掃 8400 anchors
    private var cachedCoordScale: Float? = null

    val isLoaded: Boolean get() = interpreter != null

    // ──────────────────────────────────────────────────────────────

    fun tryLoad(): Boolean {
        return try {
            val bytes = assetManager.open(MODEL_ASSET).use { it.readBytes() }
            val modelBuf = ByteBuffer.allocateDirect(bytes.size).apply {
                order(ByteOrder.nativeOrder()); put(bytes); rewind()
            }
            val opts = Interpreter.Options().apply { setNumThreads(4) }
            interpreter = Interpreter(modelBuf, opts)

            // 讀取輸入型態 → 決定 buffer 大小與填值方式
            interpreter!!.getInputTensor(0).also { t ->
                inIsFloat   = (t.dataType() == DataType.FLOAT32)
                inZeroPoint = t.quantizationParams().zeroPoint
                val elemBytes = if (inIsFloat) 4 else 1
                Log.d(TAG, "Input shape=${t.shape().toList()} type=${t.dataType()} " +
                    "inIsFloat=$inIsFloat elemBytes=$elemBytes")
                inputBuf = ByteBuffer.allocateDirect(INPUT_SIZE * INPUT_SIZE * 3 * elemBytes)
                    .apply { order(ByteOrder.nativeOrder()) }
            }

            // 列出所有 output tensors（debug）
            val outCount = interpreter!!.outputTensorCount
            Log.d(TAG, "=== YOLOv8 outputs: count=$outCount ===")
            for (i in 0 until outCount) {
                val t = interpreter!!.getOutputTensor(i)
                Log.d(TAG, "  out[$i] shape=${t.shape().toList()} type=${t.dataType()} " +
                    "scale=${t.quantizationParams().scale} zp=${t.quantizationParams().zeroPoint}")
            }

            // 找到 [*, 5, 8400] 偵測 tensor
            findDetectionOutputTensor()?.also { (idx, tensor) ->
                detectionOutputIdx = idx
                outIsFloat   = tensor.dataType() == DataType.FLOAT32
                outScale     = tensor.quantizationParams().scale
                outZeroPoint = tensor.quantizationParams().zeroPoint
                val elemBytes = if (outIsFloat) 4 else 1
                outputBuf = ByteBuffer.allocateDirect(5 * 8400 * elemBytes)
                    .apply { order(ByteOrder.nativeOrder()) }
                Log.d(TAG, "Detection output[$idx] type=${tensor.dataType()} outIsFloat=$outIsFloat")
            } ?: run {
                Log.w(TAG, "Cannot find detection output tensor")
                interpreter?.close(); interpreter = null; return false
            }

            Log.d(TAG, "YOLOv8 loaded OK " +
                "(in=${if (inIsFloat) "FLOAT32" else "INT8"} " +
                "out=${if (outIsFloat) "FLOAT32" else "INT8"})")
            true
        } catch (e: Exception) {
            Log.w(TAG, "Cannot load YOLOv8 model: $e"); false
        }
    }

    // ──────────────────────────────────────────────────────────────

    /**
     * 對 [roiCenterX, roiCenterY] 附近裁切出 640×640 patch 並執行推論。
     *
     * @param roiCenterX      ROI 中心 X（frame 座標）
     * @param roiCenterY      ROI 中心 Y（frame 座標）
     * @param tileEdgeMargin  tile 邊緣排除距離（pixels in tile space）；
     *                        預設 24f；擊球後可降低至 8f 讓高速球靠近邊緣也能通過
     * @return 偵測列表，FloatArray(5) = [cx_frame, cy_frame, w_px, h_px, conf]
     *         座標已轉換回原始 frame 座標空間
     */
    fun detect(
        yData:   ByteArray, yStride: Int,
        uData:   ByteArray, uStride: Int, uPixelStride: Int,
        vData:   ByteArray, vStride: Int, vPixelStride: Int,
        frameW: Int,
        frameH: Int,
        roiCenterX: Int,
        roiCenterY: Int,
        // 允許呼叫端動態調整：擊球後可降低至 0.05f 讓微小/高速球也能通過
        confThreshold: Float = CONF_THRESHOLD,
        // 擊球後可降低至 8f，避免高速球在 tile 邊緣被過濾
        tileEdgeMargin: Float = TILE_EDGE_MARGIN,
    ): List<FloatArray> {
        val interp = interpreter ?: return emptyList()
        val inBuf  = inputBuf   ?: return emptyList()
        val outBuf = outputBuf  ?: return emptyList()

        // ── 計算 tile 左上角（640×640 crop，以 ROI 中心為中心）────────
        val halfSize = INPUT_SIZE / 2   // 320
        val tileLeft: Int
        val tileTop: Int
        val tileW: Int
        val tileH: Int

        if (frameW < INPUT_SIZE || frameH < INPUT_SIZE) {
            // frame 比模型輸入小 → 全 frame 縮放（保留相容性）
            tileLeft = 0; tileTop = 0
            tileW = frameW; tileH = frameH
        } else {
            // 正常情況：裁 640×640，對齊 frame 邊界
            tileLeft = (roiCenterX - halfSize).coerceIn(0, frameW - INPUT_SIZE)
            tileTop  = (roiCenterY - halfSize).coerceIn(0, frameH - INPUT_SIZE)
            tileW = INPUT_SIZE; tileH = INPUT_SIZE
        }

        // ── 填入 [1, 640, 640, 3] input（Native C 加速）─────────────
        // 原 JVM 迴圈 640×640=40萬次，由 NativeLib.fillYoloInput 替代。
        // 使用 GetDirectBufferAddress 直接寫入 inBuf（ByteBuffer.allocateDirect），零複製。
        inBuf.rewind()
        NativeLib.fillYoloInput(
            yData, yStride,
            uData, uStride, uPixelStride,
            vData, vStride, vPixelStride,
            frameW, frameH,
            tileLeft, tileTop, tileW, tileH,
            INPUT_SIZE,
            inBuf,
            inIsFloat,
            inZeroPoint,
        )
        inBuf.rewind()

        // ── 推論 ─────────────────────────────────────────────────
        outBuf.rewind()
        interp.runForMultipleInputsOutputs(
            arrayOf(inBuf),
            hashMapOf(detectionOutputIdx to outBuf) as Map<Int, Any>
        )
        outBuf.rewind()

        // ── 解析輸出 [5, 8400] ──────────────────────────────────
        fun getValue(ch: Int, anchor: Int): Float =
            if (outIsFloat) outBuf.getFloat((ch * 8400 + anchor) * 4)
            else (outBuf.get(ch * 8400 + anchor).toInt() - outZeroPoint) * outScale

        // ── 偵測模型輸出座標格式（normalized [0,1] 或 pixel [0,640]）───
        // 模型格式不會改變，只在第一次確認，之後直接用快取值（省 8400 次 ByteBuffer 讀取/幀）
        val coordScale: Float
        if (cachedCoordScale != null) {
            coordScale = cachedCoordScale!!
        } else {
            var maxConfForScale = 0f; var maxCxForScale = 0f
            for (i in 0 until 8400) {
                val c = getValue(4, i)
                if (c > maxConfForScale) { maxConfForScale = c; maxCxForScale = getValue(0, i) }
            }
            coordScale = if (maxConfForScale > 0.05f && maxCxForScale < 2.0f) INPUT_SIZE.toFloat() else 1.0f
            if (maxConfForScale > 0.05f) {  // 有足夠信心才鎖定格式
                cachedCoordScale = coordScale
                Log.d(TAG, "coordScale locked=$coordScale (maxConf=${"%.4f".format(maxConfForScale)} maxCx_raw=${"%.4f".format(maxCxForScale)})")
            }
        }

        // debug：每 20 次 detect 完整掃描（僅 debug build，避免 release 浪費 8400 次讀取）
        detectCallCount++
        if (BuildConfig.DEBUG && detectCallCount % 20 == 0) {
            val coordFormat = if (coordScale > 1f) "normalized→scaled" else "pixel"
            val LOW_THRESH = 0.10f
            data class Det(val conf: Float, val cx: Float, val cy: Float, val w: Float, val h: Float)
            val topDets = mutableListOf<Det>()
            for (i in 0 until 8400) {
                val c = getValue(4, i)
                val cx = getValue(0, i) * coordScale
                val cy = getValue(1, i) * coordScale
                if (c >= LOW_THRESH) topDets.add(Det(c, cx, cy, getValue(2,i) * coordScale, getValue(3,i) * coordScale))
            }
            topDets.sortByDescending { it.conf }
            val topStr = topDets.take(5).joinToString(" | ") {
                val inEdge = it.cx < tileEdgeMargin || it.cy < tileEdgeMargin ||
                             it.cx > INPUT_SIZE - tileEdgeMargin || it.cy > INPUT_SIZE - tileEdgeMargin
                "conf=${"%.3f".format(it.conf)} tile=(${"%.1f".format(it.cx)},${"%.1f".format(it.cy)}) ${if (inEdge) "EDGE" else "OK"}"
            }
            Log.d(TAG, "[debug#$detectCallCount] roi=(${roiCenterX},${roiCenterY}) tile=($tileLeft,$tileTop) coordFormat=$coordFormat")
            if (topDets.isNotEmpty()) {
                Log.d(TAG, "[debug#$detectCallCount] top-${minOf(5, topDets.size)} above 0.10: $topStr")
            } else {
                Log.d(TAG, "[debug#$detectCallCount] ⚠️ 無任何偵測超過 0.10")
            }
        }

        // ── 篩選 + 座標轉換回 frame 空間 ────────────────────────
        val scaleX = tileW.toFloat() / INPUT_SIZE
        val scaleY = tileH.toFloat() / INPUT_SIZE
        val dets = mutableListOf<FloatArray>()
        for (i in 0 until 8400) {
            val conf = getValue(4, i)
            if (conf < confThreshold) continue

            // 模型輸出座標：依 coordScale 統一轉為 pixel [0, 640]
            val cx_tile = getValue(0, i) * coordScale
            val cy_tile = getValue(1, i) * coordScale
            val w_tile  = getValue(2, i) * coordScale
            val h_tile  = getValue(3, i) * coordScale

            // 排除 tile 邊緣的 false positive（YOLOv8 anchor grid 在邊界常產生噪訊）
            // tileEdgeMargin 由呼叫端控制：正常=24f，擊球後=8f（允許高速球靠邊緣）
            if (cx_tile < tileEdgeMargin || cy_tile < tileEdgeMargin ||
                cx_tile > INPUT_SIZE - tileEdgeMargin ||
                cy_tile > INPUT_SIZE - tileEdgeMargin) continue

            // 轉回 frame 座標
            val cx = tileLeft + cx_tile * scaleX
            val cy = tileTop  + cy_tile * scaleY
            val w  = w_tile   * scaleX
            val h  = h_tile   * scaleY
            dets.add(floatArrayOf(cx, cy, w, h, conf))
        }

        return nonMaxSuppression(dets)
    }

    // ──────────────────────────────────────────────────────────────

    private fun findDetectionOutputTensor(): Pair<Int, org.tensorflow.lite.Tensor>? {
        val interp = interpreter ?: return null
        val n = interp.outputTensorCount
        for (i in 0 until n) {
            val t = interp.getOutputTensor(i)
            val s = t.shape()
            if (s.size == 3 && s[1] == 5 && s[2] == 8400) return Pair(i, t)
        }
        for (i in 0 until n) {
            val t = interp.getOutputTensor(i)
            val s = t.shape()
            if (s.size == 3 && s[2] == 8400) return Pair(i, t)
        }
        return null
    }

    private fun nonMaxSuppression(dets: List<FloatArray>): List<FloatArray> {
        if (dets.isEmpty()) return emptyList()
        val sorted = dets.sortedByDescending { it[4] }
        val suppressed = BooleanArray(sorted.size)
        val kept = mutableListOf<FloatArray>()
        for (i in sorted.indices) {
            if (suppressed[i]) continue
            kept.add(sorted[i])
            for (j in i + 1 until sorted.size) {
                if (!suppressed[j] && iou(sorted[i], sorted[j]) > NMS_IOU) suppressed[j] = true
            }
        }
        return kept
    }

    private fun iou(a: FloatArray, b: FloatArray): Float {
        val ax1 = a[0] - a[2] / 2f; val ay1 = a[1] - a[3] / 2f
        val ax2 = a[0] + a[2] / 2f; val ay2 = a[1] + a[3] / 2f
        val bx1 = b[0] - b[2] / 2f; val by1 = b[1] - b[3] / 2f
        val bx2 = b[0] + b[2] / 2f; val by2 = b[1] + b[3] / 2f
        val ix1 = max(ax1, bx1); val iy1 = max(ay1, by1)
        val ix2 = min(ax2, bx2); val iy2 = min(ay2, by2)
        if (ix2 <= ix1 || iy2 <= iy1) return 0f
        val inter = (ix2 - ix1) * (iy2 - iy1)
        return inter / ((ax2-ax1)*(ay2-ay1) + (bx2-bx1)*(by2-by1) - inter)
    }

    fun close() {
        interpreter?.close(); interpreter = null
        inputBuf = null; outputBuf = null
    }
}
