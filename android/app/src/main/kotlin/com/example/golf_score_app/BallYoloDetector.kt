package com.example.golf_score_app

import android.content.res.AssetManager
import android.util.Log
import org.tensorflow.lite.DataType
import org.tensorflow.lite.Interpreter
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.max
import kotlin.math.min

/**
 * YOLOv8n int8 TFLite 高爾夫球偵測器（Kotlin 側）。
 *
 * 模型規格（golfballyolov8n_int8.tflite）：
 *   Input : [1, 640, 640, 3] INT8  (zero_point=-128, scale=1/255)
 *   Output: [1, 5, 8400]    FLOAT32 or INT8
 *     channels: cx, cy, w, h (in 640×640 pixels), conf (0–1)
 *
 * detect() 回傳的座標已縮放回原始 coded-frame 座標空間，
 * 由呼叫端視旋轉角度再做 codedToDisplay 轉換。
 */
class BallYoloDetector(private val assetManager: AssetManager) {

    companion object {
        private const val TAG = "BallYoloDetector"
        // Flutter 資源在 APK 內的路徑前綴
        private const val MODEL_ASSET = "flutter_assets/models/golfballyolov8n_int8.tflite"
        const val INPUT_SIZE = 640
        private const val CONF_THRESHOLD = 0.30f
        private const val NMS_IOU = 0.45f
    }

    private var interpreter: Interpreter? = null

    // 輸入量化參數（int8 模式: zero_point=-128, scale≈1/255）
    private var inZeroPoint: Int = -128

    // 輸出型態與量化參數
    private var outIsFloat = true
    private var outScale   = 1.0f
    private var outZeroPoint = 0

    // 重複使用的 ByteBuffers（避免每幀 GC 壓力）
    private val inputBuf: ByteBuffer by lazy {
        ByteBuffer.allocateDirect(INPUT_SIZE * INPUT_SIZE * 3)
            .apply { order(ByteOrder.nativeOrder()) }
    }
    // outBuf 大小取決於輸出型態，延遲初始化
    private var outputBuf: ByteBuffer? = null

    val isLoaded: Boolean get() = interpreter != null

    // ────────────────────────────────────────────────────────────

    /** 載入模型；失敗時記錄 warning 並回傳 false（不拋例外）。 */
    fun tryLoad(): Boolean {
        return try {
            val fd = assetManager.openFd(MODEL_ASSET)
            val buffer = fd.createInputStream().channel.map(
                java.nio.channels.FileChannel.MapMode.READ_ONLY,
                fd.startOffset, fd.declaredLength,
            )
            val opts = Interpreter.Options().apply { setNumThreads(2) }
            interpreter = Interpreter(buffer, opts)

            // 讀取輸入量化參數
            interpreter!!.getInputTensor(0).also { t ->
                inZeroPoint = t.quantizationParams().zeroPoint
                Log.d(TAG, "Input shape=${t.shape().toList()} type=${t.dataType()} zp=$inZeroPoint")
            }

            // 讀取輸出量化參數
            findDetectionOutputTensor()?.also { (idx, tensor) ->
                outIsFloat   = tensor.dataType() == DataType.FLOAT32
                outScale     = tensor.quantizationParams().scale
                outZeroPoint = tensor.quantizationParams().zeroPoint
                val elemBytes = if (outIsFloat) 4 else 1
                outputBuf = ByteBuffer.allocateDirect(5 * 8400 * elemBytes)
                    .apply { order(ByteOrder.nativeOrder()) }
                Log.d(TAG, "Output[${idx}] shape=${tensor.shape().toList()} " +
                    "type=${tensor.dataType()} float=$outIsFloat scale=$outScale zp=$outZeroPoint")
            } ?: run {
                Log.w(TAG, "Cannot find [1,5,8400] output tensor — detection disabled")
                interpreter?.close(); interpreter = null
                return false
            }

            Log.d(TAG, "YOLOv8 model loaded successfully")
            true
        } catch (e: Exception) {
            Log.w(TAG, "Cannot load YOLOv8 model: $e")
            false
        }
    }

    /**
     * 在 coded-space 的 Y 平面上偵測高爾夫球。
     *
     * @param yData   Y 平面資料（YUV420）
     * @param yStride Y 平面 rowStride（可能 > videoW）
     * @param frameW  影片 coded width
     * @param frameH  影片 coded height
     * @return 每個偵測結果 FloatArray(5) = [cx_px, cy_px, w_px, h_px, conf]，
     *         座標相對於 coded frame（未旋轉）
     */
    fun detect(
        yData: ByteArray,
        yStride: Int,
        frameW: Int,
        frameH: Int,
    ): List<FloatArray> {
        val interp = interpreter ?: return emptyList()
        val outBuf = outputBuf    ?: return emptyList()

        // ── 1. 建立 [1, 640, 640, 3] INT8 輸入 ──────────────────
        inputBuf.rewind()
        val scaleX = frameW.toFloat() / INPUT_SIZE
        val scaleY = frameH.toFloat() / INPUT_SIZE
        for (y in 0 until INPUT_SIZE) {
            val srcY = (y * scaleY).toInt().coerceIn(0, frameH - 1)
            for (x in 0 until INPUT_SIZE) {
                val srcX = (x * scaleX).toInt().coerceIn(0, frameW - 1)
                val pixel = yData[srcY * yStride + srcX].toInt() and 0xFF
                // int8 quantization: value = pixel + zeroPoint (zeroPoint=-128 → pixel-128)
                val q = (pixel + inZeroPoint).coerceIn(-128, 127).toByte()
                inputBuf.put(q); inputBuf.put(q); inputBuf.put(q) // R=G=B=Y（灰階）
            }
        }
        inputBuf.rewind()

        // ── 2. 推論 ──────────────────────────────────────────────
        outBuf.rewind()
        interp.run(inputBuf, outBuf)
        outBuf.rewind()

        // ── 3. 解析輸出 [channels=5, anchors=8400] ──────────────
        // 輸出記憶體佈局（row-major): [0..8399] = ch0 (cx), [8400..16799] = ch1 (cy), …
        fun getValue(ch: Int, anchor: Int): Float {
            return if (outIsFloat) {
                outBuf.getFloat((ch * 8400 + anchor) * 4)
            } else {
                val b = outBuf.get(ch * 8400 + anchor).toInt()
                (b - outZeroPoint) * outScale
            }
        }

        // ── 4. 篩選 + 縮放座標回 coded frame ───────────────────
        val dets = mutableListOf<FloatArray>()
        for (i in 0 until 8400) {
            val conf = getValue(4, i)
            if (conf < CONF_THRESHOLD) continue
            val cx = getValue(0, i) / INPUT_SIZE * frameW
            val cy = getValue(1, i) / INPUT_SIZE * frameH
            val w  = getValue(2, i) / INPUT_SIZE * frameW
            val h  = getValue(3, i) / INPUT_SIZE * frameH
            dets.add(floatArrayOf(cx, cy, w, h, conf))
        }

        // ── 5. NMS ───────────────────────────────────────────────
        return nonMaxSuppression(dets)
    }

    // ────────────────────────────────────────────────────────────
    // 內部工具
    // ────────────────────────────────────────────────────────────

    /** 找到形狀為 [1, 5, 8400] 的輸出 tensor（最終偵測輸出）。 */
    private fun findDetectionOutputTensor(): Pair<Int, org.tensorflow.lite.Tensor>? {
        val interp = interpreter ?: return null
        val n = interp.outputTensorCount
        // 優先找 [*, 5, 8400]（cx,cy,w,h + 1 class）
        for (i in 0 until n) {
            val t = interp.getOutputTensor(i)
            val s = t.shape()
            if (s.size == 3 && s[1] == 5 && s[2] == 8400) return Pair(i, t)
        }
        // fallback: [*, n_classes+4, 8400]（多類別模型）
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
        val aArea = (ax2 - ax1) * (ay2 - ay1)
        val bArea = (bx2 - bx1) * (by2 - by1)
        return inter / (aArea + bArea - inter)
    }

    fun close() {
        interpreter?.close()
        interpreter = null
    }
}
