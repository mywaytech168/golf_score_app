import AVFoundation
import Flutter

func registerTrimmerChannel(messenger: FlutterBinaryMessenger) {
  let channel = FlutterMethodChannel(
    name: "com.example.golf_score_app/trimmer",
    binaryMessenger: messenger
  )
  channel.setMethodCallHandler { call, result in
    guard call.method == "trim" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard
      let args = call.arguments as? [String: Any],
      let srcPath = args["srcPath"] as? String,
      let dstPath = args["dstPath"] as? String,
      let endMsNum = args["endMs"] as? NSNumber
    else {
      result(FlutterError(code: "invalid_args", message: "缺少 srcPath / dstPath / endMs", details: nil))
      return
    }
    let startMs = (args["startMs"] as? NSNumber)?.int64Value ?? 0
    let endMs = endMsNum.int64Value

    guard FileManager.default.fileExists(atPath: srcPath) else {
      result(FlutterError(code: "file_not_found", message: "來源影片不存在: \(srcPath)", details: nil))
      return
    }

    DispatchQueue.global(qos: .userInitiated).async {
      trimVideo(srcPath: srcPath, dstPath: dstPath, startMs: startMs, endMs: endMs, result: result)
    }
  }
}

private func trimVideo(
  srcPath: String, dstPath: String,
  startMs: Int64, endMs: Int64,
  result: @escaping FlutterResult
) {
  let asset = AVURLAsset(url: URL(fileURLWithPath: srcPath))
  // AVAssetExportPresetPassthrough 只能在 I-frame 邊界切割，
  // 導致輸出片段比請求的時間範圍短（從 timeRange 內的第一個 I-frame 開始）。
  // 改用 HighestQuality 重新編碼，可逐幀精準裁切到 startMs/endMs。
  guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
    DispatchQueue.main.async {
      result(FlutterError(code: "trim_error", message: "無法建立 AVAssetExportSession", details: nil))
    }
    return
  }

  let dstURL = URL(fileURLWithPath: dstPath)
  try? FileManager.default.createDirectory(
    at: dstURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
  )
  try? FileManager.default.removeItem(at: dstURL)

  session.outputURL = dstURL
  session.outputFileType = .mp4
  session.timeRange = CMTimeRange(
    start: CMTime(value: startMs, timescale: 1000),
    end:   CMTime(value: endMs,   timescale: 1000)
  )

  session.exportAsynchronously {
    DispatchQueue.main.async {
      switch session.status {
      case .completed:
        result(["ok": true, "baseTimeMs": startMs])
      case .failed:
        result(FlutterError(code: "trim_error", message: session.error?.localizedDescription ?? "剪輯失敗", details: nil))
      case .cancelled:
        result(FlutterError(code: "trim_error", message: "已取消", details: nil))
      default:
        result(FlutterError(code: "trim_error", message: "未知錯誤", details: nil))
      }
    }
  }
}
