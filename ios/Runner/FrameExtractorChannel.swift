import AVFoundation
import CoreGraphics
import Flutter

func registerFrameExtractorChannel(messenger: FlutterBinaryMessenger) {
  let channel = FlutterMethodChannel(
    name: "com.example.golf_score_app/frame_extractor",
    binaryMessenger: messenger
  )
  channel.setMethodCallHandler { call, result in
    guard call.method == "extractFrameRgb",
          let args = call.arguments as? [String: Any],
          let videoPath = args["videoPath"] as? String
    else {
      result(FlutterMethodNotImplemented)
      return
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

  nv21.withUnsafeMutableBytes { ptr in
    guard let base = ptr.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }

    // Y plane  (RGBA→Y)
    for i in 0 ..< frameSize {
      let r = Int(rgba[i * 4])
      let g = Int(rgba[i * 4 + 1])
      let b = Int(rgba[i * 4 + 2])
      base[i] = UInt8(min(255, max(0, (299 * r + 587 * g + 114 * b) / 1000)))
    }

    // UV plane — NV21 layout: V first, then U, 2×2 sub-sampled
    for j in stride(from: 0, to: outH, by: 2) {
      for i in stride(from: 0, to: outW, by: 2) {
        let idx = j * outW + i
        let r = Int(rgba[idx * 4])
        let g = Int(rgba[idx * 4 + 1])
        let b = Int(rgba[idx * 4 + 2])
        let u = max(0, min(255, (-169 * r - 331 * g + 500 * b) / 1000 + 128))
        let v = max(0, min(255, ( 500 * r - 419 * g -  81 * b) / 1000 + 128))
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
