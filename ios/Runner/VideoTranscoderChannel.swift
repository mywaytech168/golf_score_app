import AVFoundation
import Flutter

func registerVideoTranscoderChannel(messenger: FlutterBinaryMessenger) {
  let channel = FlutterMethodChannel(
    name: "com.example.golf_score_app/video_transcoder",
    binaryMessenger: messenger
  )
  channel.setMethodCallHandler { call, result in
    guard call.method == "transcodeToMp4" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard
      let args    = call.arguments as? [String: Any],
      let srcPath = args["srcPath"] as? String,
      let dstPath = args["dstPath"] as? String
    else {
      result(FlutterError(code: "invalid_args", message: "缺少 srcPath / dstPath", details: nil))
      return
    }

    DispatchQueue.global(qos: .userInitiated).async {
      transcodeToMp4(srcPath: srcPath, dstPath: dstPath, result: result)
    }
  }
}

/// 驗證影片並重新轉檔為標準 MP4（H.264 + AAC + faststart）
/// - 使用 AVAssetExportPresetHighestQuality：H.264 視訊 + AAC 音訊
/// - outputFileType = .mp4：MP4 容器
/// - shouldOptimizeForNetworkUse = true：moov atom 移至檔頭（faststart）
private func transcodeToMp4(
  srcPath: String,
  dstPath: String,
  result: @escaping FlutterResult
) {
  let srcURL = URL(fileURLWithPath: srcPath)
  let dstURL = URL(fileURLWithPath: dstPath)

  // ── 1. 驗證來源影片 ──────────────────────────────────────────
  let asset = AVURLAsset(url: srcURL)

  guard asset.isPlayable else {
    DispatchQueue.main.async {
      result(FlutterError(
        code: "not_playable",
        message: "影片格式不支援或檔案損壞：\(srcPath)",
        details: nil
      ))
    }
    return
  }

  guard !asset.tracks(withMediaType: .video).isEmpty else {
    DispatchQueue.main.async {
      result(FlutterError(
        code: "no_video_track",
        message: "找不到視訊軌道：\(srcPath)",
        details: nil
      ))
    }
    return
  }

  // ── 2. 建立 export session（H.264 + AAC → MP4）───────────────
  guard let session = AVAssetExportSession(
    asset: asset,
    presetName: AVAssetExportPresetHighestQuality
  ) else {
    DispatchQueue.main.async {
      result(FlutterError(
        code: "session_error",
        message: "無法建立 AVAssetExportSession",
        details: nil
      ))
    }
    return
  }

  // 確保目標目錄存在，刪除舊檔
  try? FileManager.default.createDirectory(
    at: dstURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
  )
  try? FileManager.default.removeItem(at: dstURL)

  session.outputURL               = dstURL
  session.outputFileType          = .mp4
  session.shouldOptimizeForNetworkUse = true  // faststart：moov atom 移至檔頭

  // ── 3. 執行轉檔 ──────────────────────────────────────────────
  session.exportAsynchronously {
    DispatchQueue.main.async {
      switch session.status {
      case .completed:
        result(dstPath)
      case .failed:
        result(FlutterError(
          code: "transcode_failed",
          message: session.error?.localizedDescription ?? "轉檔失敗",
          details: nil
        ))
      case .cancelled:
        result(FlutterError(code: "transcode_failed", message: "轉檔已取消", details: nil))
      default:
        result(FlutterError(code: "transcode_failed", message: "未知錯誤", details: nil))
      }
    }
  }
}
