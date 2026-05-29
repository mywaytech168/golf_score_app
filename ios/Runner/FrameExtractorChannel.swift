import AVFoundation
import CoreGraphics
import Flutter
import UIKit

func registerFrameExtractorChannel(messenger: FlutterBinaryMessenger) {
  let channel = FlutterMethodChannel(
    name: "com.example.golf_score_app/frame_extractor",
    binaryMessenger: messenger
  )
  channel.setMethodCallHandler { call, result in
    guard let args = call.arguments as? [String: Any] else {
      result(FlutterMethodNotImplemented)
      return
    }
    switch call.method {
    case "extractFrameRgb":
      guard let videoPath = args["videoPath"] as? String else {
        result(FlutterMethodNotImplemented); return
      }
      let timeMs   = (args["timeMs"]   as? NSNumber)?.int64Value ?? 0
      let maxWidth = (args["maxWidth"] as? NSNumber)?.intValue   ?? 720
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          let frameData = try extractFrame(videoPath: videoPath, timeMs: timeMs, maxWidth: maxWidth)
          DispatchQueue.main.async { result(frameData) }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(code: "extract_failed", message: error.localizedDescription, details: nil))
          }
        }
      }
    case "extractFrameJpeg":
      guard let videoPath  = args["videoPath"]  as? String,
            let outputPath = args["outputPath"] as? String else {
        result(FlutterError(code: "invalid_args", message: "缺少 videoPath / outputPath", details: nil))
        return
      }
      let timeMs   = (args["timeMs"]   as? NSNumber)?.int64Value ?? 0
      let quality  = (args["quality"]  as? NSNumber)?.intValue   ?? 80
      let maxWidth = (args["maxWidth"] as? NSNumber)?.intValue   ?? 720
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          let outPath = try extractFrameJpeg(
            videoPath: videoPath, timeMs: timeMs,
            outputPath: outputPath, quality: quality, maxWidth: maxWidth)
          DispatchQueue.main.async { result(outPath) }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(code: "frame_error", message: error.localizedDescription, details: nil))
          }
        }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

private func extractFrame(videoPath: String, timeMs: Int64, maxWidth: Int) throws -> [String: Any] {
  let asset = AVURLAsset(url: URL(fileURLWithPath: videoPath))
  let generator = AVAssetImageGenerator(asset: asset)
  generator.appliesPreferredTrackTransform = true
  generator.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 10)
  generator.requestedTimeToleranceAfter  = CMTime(value: 1, timescale: 10)

  let cgImage = try generator.copyCGImage(at: CMTime(value: timeMs, timescale: 1000), actualTime: nil)

  var outW = cgImage.width
  var outH = cgImage.height
  if maxWidth > 0 && outW > maxWidth {
    let scale = Double(maxWidth) / Double(outW)
    outW = maxWidth
    outH = Int(Double(outH) * scale)
  }

  let colorSpace = CGColorSpaceCreateDeviceRGB()
  guard let ctx = CGContext(
    data: nil, width: outW, height: outH,
    bitsPerComponent: 8, bytesPerRow: outW * 4,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
  ) else {
    throw NSError(domain: "FrameExtractor", code: -1,
                  userInfo: [NSLocalizedDescriptionKey: "無法建立繪圖上下文"])
  }
  ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: outW, height: outH))

  guard let pixelData = ctx.data else {
    throw NSError(domain: "FrameExtractor", code: -2,
                  userInfo: [NSLocalizedDescriptionKey: "無法取得像素資料"])
  }

  let frameSize = outW * outH
  var nv21 = Data(count: frameSize * 3 / 2)
  let rgba = pixelData.assumingMemoryBound(to: UInt8.self)

  nv21.withUnsafeMutableBytes { (ptr: UnsafeMutableRawBufferPointer) in
    guard let base = ptr.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }

    // Y plane  (RGBA→Y)
    for i in 0 ..< frameSize {
      let r = Int(rgba[i * 4])
      let g = Int(rgba[i * 4 + 1])
      let b = Int(rgba[i * 4 + 2])
      let y = (299 * r + 587 * g + 114 * b) / 1000
      base[i] = UInt8(max(0, min(255, y)))
    }

    // UV plane — NV21 layout: V first, then U, 2×2 sub-sampled
    for j in stride(from: 0, to: outH, by: 2) {
      for i in stride(from: 0, to: outW, by: 2) {
        let idx = j * outW + i
        let r = Int(rgba[idx * 4])
        let g = Int(rgba[idx * 4 + 1])
        let b = Int(rgba[idx * 4 + 2])
        let uRaw = (-169 * r - 331 * g + 500 * b) / 1000 + 128
        let vRaw = ( 500 * r - 419 * g -  81 * b) / 1000 + 128
        let u = max(0, min(255, uRaw))
        let v = max(0, min(255, vRaw))
        let uvBase = frameSize + (j / 2) * outW + i
        base[uvBase]     = UInt8(v)
        base[uvBase + 1] = UInt8(u)
      }
    }
  }

  return [
    "width":  outW,
    "height": outH,
    "pixels": FlutterStandardTypedData(bytes: nv21),
  ]
}

// MARK: - extractFrameJpeg（對應 Android OPTION_CLOSEST）

private func extractFrameJpeg(
  videoPath:  String,
  timeMs:     Int64,
  outputPath: String,
  quality:    Int,
  maxWidth:   Int
) throws -> String {
  let asset     = AVURLAsset(url: URL(fileURLWithPath: videoPath))
  let generator = AVAssetImageGenerator(asset: asset)
  generator.appliesPreferredTrackTransform  = true
  // .zero tolerance = 最近幀，對應 Android OPTION_CLOSEST
  generator.requestedTimeToleranceBefore = .zero
  generator.requestedTimeToleranceAfter  = .zero

  let cgImage = try generator.copyCGImage(
    at: CMTime(value: timeMs, timescale: 1000), actualTime: nil)

  var outW = cgImage.width
  var outH = cgImage.height
  if maxWidth > 0 && outW > maxWidth {
    let scale = Double(maxWidth) / Double(outW)
    outW = maxWidth
    outH = max(1, Int(Double(outH) * scale))
  }

  let colorSpace = CGColorSpaceCreateDeviceRGB()
  guard let ctx = CGContext(
    data: nil, width: outW, height: outH,
    bitsPerComponent: 8, bytesPerRow: outW * 4,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
  ) else {
    throw NSError(domain: "FrameExtractor", code: -1,
                  userInfo: [NSLocalizedDescriptionKey: "無法建立繪圖上下文"])
  }
  ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: outW, height: outH))

  guard let scaledCG = ctx.makeImage() else {
    throw NSError(domain: "FrameExtractor", code: -2,
                  userInfo: [NSLocalizedDescriptionKey: "無法建立縮放影像"])
  }

  let uiImage  = UIImage(cgImage: scaledCG)
  let clampedQ = max(0, min(100, quality))
  guard let jpegData = uiImage.jpegData(compressionQuality: CGFloat(clampedQ) / 100.0) else {
    throw NSError(domain: "FrameExtractor", code: -3,
                  userInfo: [NSLocalizedDescriptionKey: "JPEG 編碼失敗"])
  }

  try jpegData.write(to: URL(fileURLWithPath: outputPath))
  return outputPath
}
