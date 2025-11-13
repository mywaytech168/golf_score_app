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
      setupKeepScreenChannel(messenger: controller.binaryMessenger)
      setupAudioExtractorChannel(messenger: controller.binaryMessenger)
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func setupKeepScreenChannel(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "keep_screen_on_channel",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { call, result in
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

  private func setupAudioExtractorChannel(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "audio_extractor_channel",
      binaryMessenger: messenger
    )

    channel.setMethodCallHandler { [weak self] call, result in
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
                "path": extraction.path,
                "sampleRate": extraction.sampleRate,
                "channels": extraction.channels,
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

  private func extractAudio(toWavFrom videoPath: String) throws -> (path: String, sampleRate: Int, channels: Int) {
    let url = URL(fileURLWithPath: videoPath)
    let asset = AVURLAsset(url: url)
    guard let track = asset.tracks(withMediaType: .audio).first else {
      throw NSError(domain: "AudioExtractor", code: -1, userInfo: [NSLocalizedDescriptionKey: "影片中找不到音訊軌道"])
    }

    var sampleRate = 44100
    var channels = 1
    if let desc = track.formatDescriptions.first as? CMAudioFormatDescription,
       let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc)?.pointee {
      sampleRate = Int(asbd.mSampleRate)
      channels = Int(asbd.mChannelsPerFrame)
    }

    let outputSettings: [String: Any] = [
      AVFormatIDKey: kAudioFormatLinearPCM,
      AVSampleRateKey: sampleRate,
      AVNumberOfChannelsKey: channels,
      AVLinearPCMIsFloatKey: false,
      AVLinearPCMBitDepthKey: 16,
      AVLinearPCMIsBigEndianKey: false,
      AVLinearPCMIsNonInterleaved: false,
    ]

    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
    reader.add(output)

    guard reader.startReading() else {
      throw reader.error ?? NSError(domain: "AudioExtractor", code: -2, userInfo: [NSLocalizedDescriptionKey: "無法啟動音訊讀取"])
    }

    let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    let outputURL = tempDir.appendingPathComponent("audio_extract_\(Int(Date().timeIntervalSince1970 * 1000)).wav")
    FileManager.default.createFile(atPath: outputURL.path, contents: Data(count: 44), attributes: nil)

    guard let handle = try? FileHandle(forWritingTo: outputURL) else {
      throw NSError(domain: "AudioExtractor", code: -3, userInfo: [NSLocalizedDescriptionKey: "無法建立暫存檔案"])
    }
    defer {
      try? handle.close()
    }

    try handle.seek(toOffset: 44)
    var totalBytes = 0

    while reader.status == .reading {
      guard
        let sampleBuffer = output.copyNextSampleBuffer(),
        let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer)
      else {
        break
      }

      let length = CMBlockBufferGetDataLength(blockBuffer)
      var data = Data(count: length)
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
      throw reader.error ?? NSError(domain: "AudioExtractor", code: -4, userInfo: [NSLocalizedDescriptionKey: "音訊讀取失敗"])
    }

    writeWavHeader(
      fileURL: outputURL,
      pcmBytes: totalBytes,
      sampleRate: sampleRate,
      channels: channels,
      bitsPerSample: 16
    )
    return (path: outputURL.path, sampleRate: sampleRate, channels: channels)
  }

  private func writeWavHeader(
    fileURL: URL,
    pcmBytes: Int,
    sampleRate: Int,
    channels: Int,
    bitsPerSample: Int
  ) {
    let byteRate = sampleRate * channels * bitsPerSample / 8
    let blockAlign = UInt16(channels * bitsPerSample / 8)
    var header = Data()
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
