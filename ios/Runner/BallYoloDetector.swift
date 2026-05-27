import Foundation
import TensorFlowLite

// ============================================================
// YOLOv8n int8 TFLite 高爾夫球偵測器（iOS Swift 側）
//
// 模型規格（golfballyolov8n_int8.tflite）：
//   Input : [1, 640, 640, 3] INT8  (zero_point=-128, scale=1/255)
//   Output: [1, 5, 8400]    FLOAT32 or INT8
//     channels: cx, cy, w, h (in 640×640 pixels), conf (0–1)
//
// 對應 Android 側的 BallYoloDetector.kt。
// ============================================================

final class BallYoloDetector {

    // ── 單例 ──────────────────────────────────────────────────
    static let shared = BallYoloDetector()
    private init() {}

    // ── 常數 ──────────────────────────────────────────────────
    static let inputSize    = 640
    private static let confThreshold: Float = 0.30
    private static let nmsIoU:        Float = 0.45

    // ── 狀態 ──────────────────────────────────────────────────
    private let lock            = NSLock()
    private var interpreter:    Interpreter?
    private var loadAttempted   = false
    private var outIsFloat      = true
    private var outScale:       Float = 1.0
    private var outZeroPoint:   Int   = 0

    var isLoaded: Bool { interpreter != nil }

    // ── 偵測結果型別 ──────────────────────────────────────────
    struct Detection {
        let cx, cy, bboxW, bboxH: Int
        let conf: Float
    }

    // MARK: - 載入模型

    /// 嘗試從 Flutter assets 載入模型，只執行一次。
    /// - Returns: 是否成功載入
    @discardableResult
    func tryLoad() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !loadAttempted else { return isLoaded }
        loadAttempted = true

        // Flutter assets 在 iOS bundle 內路徑為 flutter_assets/...
        guard let modelPath = Bundle.main.path(
            forResource: "golfballyolov8n_int8",
            ofType: "tflite",
            inDirectory: "flutter_assets/models"
        ) else {
            print("[BallYoloDetector] ❌ 模型 asset 未找到")
            return false
        }

        do {
            var opts = Interpreter.Options()
            opts.threadCount = 2
            let interp = try Interpreter(modelPath: modelPath, options: opts)
            try interp.allocateTensors()

            // 讀取輸出量化參數
            let outTensor = try interp.output(at: 0)
            outIsFloat = (outTensor.dataType == .float32)
            if !outIsFloat, let qp = outTensor.quantizationParameters {
                outScale     = qp.scale
                outZeroPoint = qp.zeroPoint
            }
            interpreter = interp
            let shape = outTensor.shape.dimensions
            print("[BallYoloDetector] ✅ 模型載入成功  output=\(shape)  float=\(outIsFloat)")
            return true
        } catch {
            print("[BallYoloDetector] ❌ 模型載入失敗: \(error)")
            return false
        }
    }

    // MARK: - 推論

    /// 對一幀 BGRA 像素執行 YOLOv8 偵測
    ///
    /// - Parameters:
    ///   - bgraBase:  CVPixelBuffer BGRA 基址（已 lock）
    ///   - bytesPerRow: CVPixelBuffer 每列位元組數（含 stride padding）
    ///   - frameW:    display-space 影像寬度
    ///   - frameH:    display-space 影像高度
    /// - Returns:     偵測結果（座標在 display-space）
    func detect(
        bgraBase:   UnsafePointer<UInt8>,
        bytesPerRow: Int,
        frameW:     Int,
        frameH:     Int
    ) -> [Detection] {
        guard let interp = interpreter else { return [] }
        let S = BallYoloDetector.inputSize

        // 1. 建立 [1, S, S, 3] INT8 輸入
        //    BGRA → 灰階亮度，再量化：luma-128 → [-128, 127]
        var inputBytes = [Int8](repeating: -128, count: S * S * 3)
        let scaleX = Float(frameW) / Float(S)
        let scaleY = Float(frameH) / Float(S)

        for y in 0 ..< S {
            let srcY   = min(Int(Float(y) * scaleY), frameH - 1)
            let rowOff = srcY * bytesPerRow
            for x in 0 ..< S {
                let srcX = min(Int(Float(x) * scaleX), frameW - 1)
                let off  = rowOff + srcX * 4          // BGRA: B=off, G=off+1, R=off+2
                let b    = Int(bgraBase[off])
                let g    = Int(bgraBase[off + 1])
                let r    = Int(bgraBase[off + 2])
                let luma = (299 * r + 587 * g + 114 * b) / 1000  // BT.601, 0-255
                let q    = Int8(clamping: luma - 128)             // → [-128, 127]
                let idx  = (y * S + x) * 3
                inputBytes[idx] = q; inputBytes[idx+1] = q; inputBytes[idx+2] = q
            }
        }

        // 2. 推論
        do {
            let inputData = Data(bytes: inputBytes, count: inputBytes.count)
            try interp.copy(inputData, toInputAt: 0)
            try interp.invoke()
            return parseOutput(try interp.output(at: 0), frameW: frameW, frameH: frameH)
        } catch {
            print("[BallYoloDetector] 推理失敗: \(error)")
            return []
        }
    }

    // MARK: - 解析輸出 [1, 5, 8400]

    private func parseOutput(_ tensor: Tensor, frameW: Int, frameH: Int) -> [Detection] {
        let S = BallYoloDetector.inputSize
        let n = 8400   // anchors
        let bytes = tensor.data

        // 取得第 ch 通道第 anchor 個 anchor 的值
        func getVal(ch: Int, anchor: Int) -> Float {
            if outIsFloat {
                return bytes.withUnsafeBytes {
                    $0.load(fromByteOffset: (ch * n + anchor) * 4, as: Float.self)
                }
            } else {
                // INT8 輸出：反量化
                let raw: UInt8 = bytes.withUnsafeBytes { $0[ch * n + anchor] }
                return Float(Int(raw) - outZeroPoint) * outScale
            }
        }

        // 過濾置信度
        var raw: [(cx: Float, cy: Float, w: Float, h: Float, conf: Float)] = []
        for i in 0 ..< n {
            let conf = getVal(ch: 4, anchor: i)
            guard conf >= BallYoloDetector.confThreshold else { continue }
            raw.append((
                cx:   getVal(ch: 0, anchor: i) / Float(S) * Float(frameW),
                cy:   getVal(ch: 1, anchor: i) / Float(S) * Float(frameH),
                w:    getVal(ch: 2, anchor: i) / Float(S) * Float(frameW),
                h:    getVal(ch: 3, anchor: i) / Float(S) * Float(frameH),
                conf: conf
            ))
        }

        // NMS 後轉型
        return nms(raw).map { d in
            Detection(
                cx:    Int(d.cx),
                cy:    Int(d.cy),
                bboxW: max(1, Int(d.w)),
                bboxH: max(1, Int(d.h)),
                conf:  d.conf
            )
        }
    }

    // MARK: - NMS

    private func nms(
        _ dets: [(cx: Float, cy: Float, w: Float, h: Float, conf: Float)]
    ) -> [(cx: Float, cy: Float, w: Float, h: Float, conf: Float)] {
        let sorted   = dets.sorted { $0.conf > $1.conf }
        var suppress = [Bool](repeating: false, count: sorted.count)
        var kept     = [(cx: Float, cy: Float, w: Float, h: Float, conf: Float)]()
        for i in sorted.indices {
            guard !suppress[i] else { continue }
            kept.append(sorted[i])
            for j in (i + 1) ..< sorted.count {
                if !suppress[j] && iou(sorted[i], sorted[j]) > BallYoloDetector.nmsIoU {
                    suppress[j] = true
                }
            }
        }
        return kept
    }

    private func iou(
        _ a: (cx: Float, cy: Float, w: Float, h: Float, conf: Float),
        _ b: (cx: Float, cy: Float, w: Float, h: Float, conf: Float)
    ) -> Float {
        let ax1 = a.cx - a.w / 2, ay1 = a.cy - a.h / 2
        let ax2 = a.cx + a.w / 2, ay2 = a.cy + a.h / 2
        let bx1 = b.cx - b.w / 2, by1 = b.cy - b.h / 2
        let bx2 = b.cx + b.w / 2, by2 = b.cy + b.h / 2
        let ix1 = max(ax1, bx1), iy1 = max(ay1, by1)
        let ix2 = min(ax2, bx2), iy2 = min(ay2, by2)
        guard ix2 > ix1 && iy2 > iy1 else { return 0 }
        let inter = (ix2 - ix1) * (iy2 - iy1)
        let aArea = (ax2 - ax1) * (ay2 - ay1)
        let bArea = (bx2 - bx1) * (by2 - by1)
        return inter / (aArea + bArea - inter)
    }
}
