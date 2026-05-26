import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    if let controller = window?.rootViewController as? FlutterViewController {
      let m = controller.binaryMessenger

      // ── 已實作的 channel ─────────────────────────────────────
      setupKeepScreenChannel(messenger: m)
      setupAudioExtractorChannel(messenger: m)

      // ── 分析進度 EventChannel ────────────────────────────────
      FlutterEventChannel(
        name: "com.example.golf_score_app/analysis_progress",
        binaryMessenger: m
      ).setStreamHandler(AnalysisProgressSink.shared)

      // ── 新增 MethodChannel 實作 ──────────────────────────────
      setupShareChannel(messenger: m)
      setupVideoOverlayChannel(messenger: m)
      registerTrimmerChannel(messenger: m)
      registerFrameExtractorChannel(messenger: m)
      registerPoseAnalyzerChannel(messenger: m)

      // ── 骨架疊加 / 球體軌跡 ──────────────────────────────────
      registerSkeletonOverlayChannel(messenger: m)
      registerBallTrajectoryChannel(messenger: m)

      // ── Stub channels（iOS 尚未實作）────────────────────────
      setupStubChannel(name: "volume_button_channel", messenger: m)
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

// MARK: - Keep screen on

private extension AppDelegate {
  func setupKeepScreenChannel(messenger: FlutterBinaryMessenger) {
    FlutterMethodChannel(name: "keep_screen_on_channel", binaryMessenger: messenger)
      .setMethodCallHandler { call, result in
        switch call.method {
        case "enable":
          UIApplication.shared.isIdleTimerDisabled = true
          result(nil)
        case "disable":
          UIApplication.shared.isIdleTimerDisabled = false
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
  }
}

// MARK: - Audio extractor

private extension AppDelegate {
  func setupAudioExtractorChannel(messenger: FlutterBinaryMessenger) {
    FlutterMethodChannel(name: "audio_extractor_channel", binaryMessenger: messenger)
      .setMethodCallHandler { [weak self] call, result in
        guard call.method == "extractAudio" else {
          result(FlutterMethodNotImplemented)
          return
        }
        guard
          let arguments = call.arguments as? [String: Any],
          let videoPath = arguments["videoPath"] as? String,
          !videoPath.isEmpty
        else {
          result(FlutterError(code: "invalid_args", message: "缺少影片路徑參數", details: nil))
          return
        }

        DispatchQueue.global(qos: .userInitiated).async {
          do {
            let extraction = try self?.extractAudio(toWavFrom: videoPath)
            DispatchQueue.main.async {
              if let extraction = extraction {
                result([
                  "path":       extraction.path,
                  "sampleRate": extraction.sampleRate,
                  "channels":   extraction.channels,
                ])
              } else {
                result(FlutterError(code: "extract_failed", message: "未知的錯誤", details: nil))
              }
            }
          } catch {
            DispatchQueue.main.async {
              result(FlutterError(code: "extract_failed", message: error.localizedDescription, details: nil))
            }
          }
        }
      }
  }

  func extractAudio(toWavFrom videoPath: String) throws -> (path: String, sampleRate: Int, channels: Int) {
    let url   = URL(fileURLWithPath: videoPath)
    let asset = AVURLAsset(url: url)
    guard let track = asset.tracks(withMediaType: .audio).first else {
      throw NSError(domain: "AudioExtractor", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "影片中找不到音訊軌道"])
    }

    var sampleRate = 44100
    var channels   = 1

    if let desc = track.formatDescriptions.first {
      let formatDesc = desc as! CMFormatDescription
      if CMFormatDescriptionGetMediaType(formatDesc) == kCMMediaType_Audio,
         let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)?.pointee {
        sampleRate = Int(asbd.mSampleRate)
        channels   = Int(asbd.mChannelsPerFrame)
      }
    }

    let outputSettings: [String: Any] = [
      AVFormatIDKey:             kAudioFormatLinearPCM,
      AVSampleRateKey:           sampleRate,
      AVNumberOfChannelsKey:     channels,
      AVLinearPCMIsFloatKey:     false,
      AVLinearPCMBitDepthKey:    16,
      AVLinearPCMIsBigEndianKey: false,
      AVLinearPCMIsNonInterleaved: false,
    ]

    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
    reader.add(output)

    guard reader.startReading() else {
      throw reader.error ?? NSError(domain: "AudioExtractor", code: -2,
                                    userInfo: [NSLocalizedDescriptionKey: "無法啟動音訊讀取"])
    }

    let tempDir   = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    let outputURL = tempDir.appendingPathComponent("audio_extract_\(Int(Date().timeIntervalSince1970 * 1000)).wav")
    FileManager.default.createFile(atPath: outputURL.path, contents: Data(count: 44), attributes: nil)

    guard let handle = try? FileHandle(forWritingTo: outputURL) else {
      throw NSError(domain: "AudioExtractor", code: -3,
                    userInfo: [NSLocalizedDescriptionKey: "無法建立暫存檔案"])
    }
    defer { try? handle.close() }

    try handle.seek(toOffset: 44)
    var totalBytes = 0

    while reader.status == .reading {
      guard
        let sampleBuffer = output.copyNextSampleBuffer(),
        let blockBuffer  = CMSampleBufferGetDataBuffer(sampleBuffer)
      else { break }

      let length = CMBlockBufferGetDataLength(blockBuffer)
      var data   = Data(count: length)
      data.withUnsafeMutableBytes { pointer in
        if let baseAddress = pointer.baseAddress {
          CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: baseAddress)
        }
      }
      handle.write(data)
      totalBytes += length
      CMSampleBufferInvalidate(sampleBuffer)
    }

    if reader.status == .failed || reader.status == .unknown {
      throw reader.error ?? NSError(domain: "AudioExtractor", code: -4,
                                    userInfo: [NSLocalizedDescriptionKey: "音訊讀取失敗"])
    }

    writeWavHeader(fileURL: outputURL, pcmBytes: totalBytes,
                   sampleRate: sampleRate, channels: channels, bitsPerSample: 16)
    return (path: outputURL.path, sampleRate: sampleRate, channels: channels)
  }

  func writeWavHeader(fileURL: URL, pcmBytes: Int, sampleRate: Int, channels: Int, bitsPerSample: Int) {
    let byteRate   = sampleRate * channels * bitsPerSample / 8
    let blockAlign = UInt16(channels * bitsPerSample / 8)
    var header     = Data()
    header.append("RIFF".data(using: .ascii)!)
    header.append(UInt32(36 + pcmBytes).littleEndianData)
    header.append("WAVE".data(using: .ascii)!)
    header.append("fmt ".data(using: .ascii)!)
    header.append(UInt32(16).littleEndianData)
    header.append(UInt16(1).littleEndianData)
    header.append(UInt16(channels).littleEndianData)
    header.append(UInt32(sampleRate).littleEndianData)
    header.append(UInt32(byteRate).littleEndianData)
    header.append(blockAlign.littleEndianData)
    header.append(UInt16(bitsPerSample).littleEndianData)
    header.append("data".data(using: .ascii)!)
    header.append(UInt32(pcmBytes).littleEndianData)

    if let handle = try? FileHandle(forWritingTo: fileURL) {
      try? handle.seek(toOffset: 0)
      handle.write(header)
      try? handle.close()
    }
  }
}

// MARK: - Share intent

private extension AppDelegate {
  func setupShareChannel(messenger: FlutterBinaryMessenger) {
    FlutterMethodChannel(name: "share_intent_channel", binaryMessenger: messenger)
      .setMethodCallHandler { [weak self] call, result in
        guard call.method == "shareToPackage",
              let args     = call.arguments as? [String: Any],
              let filePath = args["filePath"] as? String
        else {
          result(FlutterMethodNotImplemented)
          return
        }

        let fileURL = URL(fileURLWithPath: filePath)
        guard FileManager.default.fileExists(atPath: filePath) else {
          result(FlutterError(code: "file_not_found", message: "找不到指定檔案", details: nil))
          return
        }

        DispatchQueue.main.async {
          let vc = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
          if let text = args["text"] as? String {
            vc.setValue(text, forKey: "subject")
          }
          // iPad support
          if let popover = vc.popoverPresentationController {
            popover.sourceView = self?.window?.rootViewController?.view
            popover.sourceRect = CGRect(x: UIScreen.main.bounds.midX,
                                        y: UIScreen.main.bounds.midY,
                                        width: 0, height: 0)
            popover.permittedArrowDirections = []
          }
          self?.window?.rootViewController?.present(vc, animated: true)
          result(true)
        }
      }
  }
}

// MARK: - Video overlay (stub that copies file, mirrors Android behaviour)

private extension AppDelegate {
  func setupVideoOverlayChannel(messenger: FlutterBinaryMessenger) {
    FlutterMethodChannel(name: "video_overlay_channel", binaryMessenger: messenger)
      .setMethodCallHandler { call, result in
        guard call.method == "processVideo",
              let args       = call.arguments as? [String: Any],
              let inputPath  = args["inputPath"]  as? String,
              let outputPath = args["outputPath"] as? String
        else {
          result(FlutterMethodNotImplemented)
          return
        }

        DispatchQueue.global(qos: .userInitiated).async {
          do {
            let dstURL = URL(fileURLWithPath: outputPath)
            try FileManager.default.createDirectory(
              at: dstURL.deletingLastPathComponent(),
              withIntermediateDirectories: true
            )
            try? FileManager.default.removeItem(at: dstURL)
            try FileManager.default.copyItem(
              at: URL(fileURLWithPath: inputPath),
              to: dstURL
            )
            DispatchQueue.main.async { result(outputPath) }
          } catch {
            DispatchQueue.main.async {
              result(FlutterError(code: "overlay_failed", message: error.localizedDescription, details: nil))
            }
          }
        }
      }
  }
}

// MARK: - Stub channel (returns notImplemented so Dart can catch gracefully)

private extension AppDelegate {
  func setupStubChannel(name: String, messenger: FlutterBinaryMessenger) {
    FlutterMethodChannel(name: name, binaryMessenger: messenger)
      .setMethodCallHandler { _, result in
        result(FlutterMethodNotImplemented)
      }
  }
}

// MARK: - Data helpers

private extension UInt16 {
  var littleEndianData: Data {
    var value = self.littleEndian
    return Data(bytes: &value, count: MemoryLayout<UInt16>.size)
  }
}

private extension UInt32 {
  var littleEndianData: Data {
    var value = self.littleEndian
    return Data(bytes: &value, count: MemoryLayout<UInt32>.size)
  }
}
