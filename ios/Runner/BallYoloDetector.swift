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
    static let inputSize            = 640
    static let confThreshold: Float  = 0.25          // 預設門櫛（對應 Android CONF_THRESHOLD）
    private static let nmsIoU: Float = 0.45
    private static let tileEdgeMargin: Float = 24    // tile 邊緣排除（對應 TILE_EDGE_MARGIN）

    // ── 狀態 ──────────────────────────────────────────────────
    private let lock            = NSLock()
    private var interpreter:    Interpreter?
    private var loadAttempted   = false
    // 輸入 tensor 型態
    private var inIsFloat       = false
    private var inZeroPoint:    Int   = -128
    // 輸出 tensor 量化參數
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

            // 讀取輸入 tensor 型態（FLOAT32 or INT8）
            let inTensor = try interp.input(at: 0)
            inIsFloat = (inTensor.dataType == .float32)
            if !inIsFloat, let qp = inTensor.quantizationParameters {
                inZeroPoint = qp.zeroPoint
            }
            let inType = inIsFloat ? "FLOAT32" : "INT8"
            print("[BallYoloDetector] input: \(inType) zp=\(inZeroPoint)")

            // 讀取輸出量化參數
            let outTensor = try interp.output(at: 0)
            outIsFloat = (outTensor.dataType == .float32)
            if !outIsFloat, let qp = outTensor.quantizationParameters {
                outScale     = qp.scale
                outZeroPoint = qp.zeroPoint
            }
            interpreter = interp
            let shape = outTensor.shape.dimensions
            print("[BallYoloDetector] ✅ 模型載入成功  output=\(shape)  outFloat=\(outIsFloat)")
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
    /// 對 [roiCenterX, roiCenterY] 附近裁切 640×640 patch 並執行推論。
    /// 對應 Android BallYoloDetector.detect()。
    func detect(
        bgraBase:      UnsafePointer<UInt8>,
        bytesPerRow:   Int,
        frameW:        Int,
        frameH:        Int,
        roiCenterX:    Int   = -1,
        roiCenterY:    Int   = -1,
        confThreshold: Float = BallYoloDetector.confThreshold
    ) -> [Detection] {
        guard let interp = interpreter else { return [] }
        let S = BallYoloDetector.inputSize

        // ── 計算 tile 左上角（640×640 crop，以 ROI 中心為中心）────
        let halfSize = S / 2
        let roiX = roiCenterX >= 0 ? roiCenterX : frameW / 2
        let roiY = roiCenterY >= 0 ? roiCenterY : frameH / 2

        let tileLeft: Int
        let tileTop:  Int
        let tileW:    Int
        let tileH:    Int

        if frameW < S || frameH < S {
            tileLeft = 0; tileTop = 0
            tileW = frameW; tileH = frameH
        } else {
            tileLeft = max(0, min(roiX - halfSize, frameW - S))
            tileTop  = max(0, min(roiY - halfSize, frameH - S))
            tileW = S; tileH = S
        }

        let scaleX = Float(tileW) / Float(S)
        let scaleY = Float(tileH) / Float(S)

        // ── 填入 [1, 640, 640, 3] input ──────────────────────────
        do {
            if inIsFloat {
                // FLOAT32：BGRA → RGB pixel/255
                var inputData = Data(count: S * S * 3 * 4)
                inputData.withUnsafeMutableBytes { (ptr: UnsafeMutableRawBufferPointer) in
                    guard let base = ptr.baseAddress?.assumingMemoryBound(to: Float.self) else { return }
                    for y in 0 ..< S {
                        let srcY = min(tileTop + Int(Float(y) * scaleY), frameH - 1)
                        let rowOff = srcY * bytesPerRow
                        for x in 0 ..< S {
                            let srcX = min(tileLeft + Int(Float(x) * scaleX), frameW - 1)
                            let off = rowOff + srcX * 4
                            let b = Float(bgraBase[off]) / 255.0
                            let g = Float(bgraBase[off + 1]) / 255.0
                            let r = Float(bgraBase[off + 2]) / 255.0
                            let idx = (y * S + x) * 3
                            base[idx] = r
                            base[idx + 1] = g
                            base[idx + 2] = b
                        }
                    }
                }
                try interp.copy(inputData, toInputAt: 0)
            } else {
                // INT8：亮度量化 (luma + zeroPoint) → [-128, 127]
                var inputBytes = [Int8](repeating: Int8(clamping: inZeroPoint), count: S * S * 3)
                for y in 0 ..< S {
                    let srcY = min(tileTop + Int(Float(y) * scaleY), frameH - 1)
                    let rowOff = srcY * bytesPerRow
                    for x in 0 ..< S {
                        let srcX = min(tileLeft + Int(Float(x) * scaleX), frameW - 1)
                        let off = rowOff + srcX * 4
                        let b = Int(bgraBase[off])
                        let g = Int(bgraBase[off + 1])
                        let r = Int(bgraBase[off + 2])
                        let luma = (299 * r + 587 * g + 114 * b) / 1000
                        let q = Int8(clamping: luma + inZeroPoint)
                        let idx = (y * S + x) * 3
                        inputBytes[idx] = q
                        inputBytes[idx + 1] = q
                        inputBytes[idx + 2] = q
                    }
                }
                try interp.copy(Data(bytes: inputBytes, count: inputBytes.count), toInputAt: 0)
            }

            try interp.invoke()
            return parseOutput(
                try interp.output(at: 0),
                tileLeft: tileLeft,
                tileTop: tileTop,
                scaleX: scaleX,
                scaleY: scaleY,
                confThreshold: confThreshold
            )
        } catch {
            print("[BallYoloDetector] 推理失敗: \(error)")
            return []
        }
    }

    // MARK: - 解析輸出 [1, 5, 8400]

    private func parseOutput(
        _ tensor:      Tensor,
        tileLeft:      Int,
        tileTop:       Int,
        scaleX:        Float,
        scaleY:        Float,
        confThreshold: Float
    ) -> [Detection] {
        let S      = BallYoloDetector.inputSize
        let MARGIN = BallYoloDetector.tileEdgeMargin
        let n      = 8400
        let bytes  = tensor.data

        func getVal(ch: Int, anchor: Int) -> Float {
            if outIsFloat {
                return bytes.withUnsafeBytes { (rawBuffer: UnsafeRawBufferPointer) in
                    rawBuffer.load(fromByteOffset: (ch * n + anchor) * 4, as: Float.self)
                }
            } else {
                let raw: UInt8 = bytes.withUnsafeBytes { (rawBuffer: UnsafeRawBufferPointer) in
                    rawBuffer.load(fromByteOffset: ch * n + anchor, as: UInt8.self)
                }
                return Float(Int(raw) - outZeroPoint) * outScale
            }
        }

        // 偵測座標格式（normalized [0,1] 或 pixel [0,640]），對應 Android coordScale 邏輯
        var maxConf: Float = 0
        var maxCx:   Float = 0
        for i in 0 ..< n {
            let c = getVal(ch: 4, anchor: i)
            if c > maxConf { maxConf = c; maxCx = getVal(ch: 0, anchor: i) }
        }
        let coordScale: Float = (maxConf > 0.05 && maxCx < 2.0) ? Float(S) : 1.0

        // 篩選 + tile 邊緣排除 + 座標轉回 frame 空間
        var raw: [(cx: Float, cy: Float, w: Float, h: Float, conf: Float)] = []
        for i in 0 ..< n {
            let conf = getVal(ch: 4, anchor: i)
            guard conf >= confThreshold else { continue }

            let cx_tile = getVal(ch: 0, anchor: i) * coordScale
            let cy_tile = getVal(ch: 1, anchor: i) * coordScale
            let w_tile  = getVal(ch: 2, anchor: i) * coordScale
            let h_tile  = getVal(ch: 3, anchor: i) * coordScale

            if cx_tile < MARGIN || cy_tile < MARGIN ||
               cx_tile > Float(S) - MARGIN || cy_tile > Float(S) - MARGIN {
                continue
            }

            raw.append((
                cx:   Float(tileLeft) + cx_tile * scaleX,
                cy:   Float(tileTop)  + cy_tile * scaleY,
                w:    w_tile * scaleX,
                h:    h_tile * scaleY,
                conf: conf
            ))
        }

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
