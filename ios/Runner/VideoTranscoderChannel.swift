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

// MARK: - 主轉檔函數

/// 兩路策略（iOS AVFoundation 原生支援 H.264 / HEVC，不需重新編碼）：
///
///   路徑 A  已是 MP4 容器（任意 codec）→ 直接複製（毫秒級）
///   路徑 B  非 MP4（MOV 等）           → Passthrough remux，只換容器（秒級）
///
/// iOS 分析管線（AVAssetReader / MLKit / audio extractor）全部原生支援 HEVC，
/// 不需降轉 H.264。
private func transcodeToMp4(
  srcPath: String,
  dstPath: String,
  result:  @escaping FlutterResult
) {
  let srcURL = URL(fileURLWithPath: srcPath)
  let dstURL = URL(fileURLWithPath: dstPath)
  let asset  = AVURLAsset(url: srcURL)

  // ── 1. 非同步載入 metadata ──────────────────────────────────
  asset.loadValuesAsynchronously(forKeys: ["playable", "tracks"]) {
    var err: NSError?

    guard asset.statusOfValue(forKey: "playable", error: &err) == .loaded,
          asset.isPlayable else {
      DispatchQueue.main.async {
        result(FlutterError(code: "not_playable",
                            message: "影片格式不支援或損壞：\(srcPath)", details: nil))
      }
      return
    }
    guard !asset.tracks(withMediaType: .video).isEmpty else {
      DispatchQueue.main.async {
        result(FlutterError(code: "no_video_track",
                            message: "找不到視訊軌道：\(srcPath)", details: nil))
      }
      return
    }

    // ── 2. 只看容器格式，不管 codec ───────────────────────────
    let srcExt   = srcURL.pathExtension.lowercased()
    let isMp4Box = srcExt == "mp4" || srcExt == "m4v"

    // 路徑 A：已是 MP4 容器 → 直接複製
    if isMp4Box {
      do {
        try vtPrepareDestination(at: dstURL)
        try FileManager.default.copyItem(at: srcURL, to: dstURL)
        DispatchQueue.main.async { result(dstPath) }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(code: "copy_failed",
                              message: error.localizedDescription, details: nil))
        }
      }
      return
    }

    // 路徑 B：非 MP4（MOV 等）→ Passthrough remux（只換容器，保留原始 codec）
    guard let session = AVAssetExportSession(
      asset: asset, presetName: AVAssetExportPresetPassthrough
    ) else {
      DispatchQueue.main.async {
        result(FlutterError(code: "session_error",
                            message: "無法建立 AVAssetExportSession",
                            details: nil))
      }
      return
    }

    vtRunExportSession(session, dstURL: dstURL, dstPath: dstPath, result: result)
  }
}

// MARK: - Export Session 執行 + 進度推送

private func vtRunExportSession(
  _ session: AVAssetExportSession,
  dstURL:   URL,
  dstPath:  String,
  result:   @escaping FlutterResult
) {
  do {
    try vtPrepareDestination(at: dstURL)
  } catch {
    DispatchQueue.main.async {
      result(FlutterError(code: "prepare_failed",
                          message: error.localizedDescription, details: nil))
    }
    return
  }

  session.outputURL               = dstURL
  session.outputFileType          = .mp4
  session.shouldOptimizeForNetworkUse = true   // moov atom 移至檔頭（faststart）

  // ── 進度推送（每 0.5 秒，透過 AnalysisProgressSink）──────────
  let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
  timer.schedule(deadline: .now() + 0.5, repeating: 0.5)
  timer.setEventHandler {
    let p = Double(session.progress)
    AnalysisProgressSink.shared.send(
      op: "transcode", progress: p,
      label: "轉檔中 \(Int(p * 100))%", current: Int(p * 100), total: 100)
  }
  timer.resume()

  session.exportAsynchronously {
    timer.cancel()
    DispatchQueue.main.async {
      switch session.status {
      case .completed:
        AnalysisProgressSink.shared.send(
          op: "transcode", progress: 1.0,
          label: "轉檔完成", current: 100, total: 100)
        result(dstPath)
      case .failed:
        result(FlutterError(
          code:    "transcode_failed",
          message: session.error?.localizedDescription ?? "轉檔失敗",
          details: nil))
      case .cancelled:
        result(FlutterError(code: "transcode_failed", message: "轉檔已取消", details: nil))
      default:
        result(FlutterError(code: "transcode_failed", message: "未知錯誤", details: nil))
      }
    }
  }
}

// MARK: - 工具函數

/// 建立目標目錄，刪除舊檔
private func vtPrepareDestination(at url: URL) throws {
  try FileManager.default.createDirectory(
    at:  url.deletingLastPathComponent(),
    withIntermediateDirectories: true
  )
  try? FileManager.default.removeItem(at: url)
}
