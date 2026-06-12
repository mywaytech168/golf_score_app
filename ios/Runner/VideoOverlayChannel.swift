import AVFoundation
import CoreGraphics
import Flutter
import UIKit

// MARK: - Channel registration

/// 影片頭像 / 字幕疊加燒錄（mirrors Android VideoOverlayProcessor）。
///
/// AVAssetReader（video composition，自動處理 preferredTransform 轉正）
///   → CoreGraphics 疊加靜態 overlay（圓形頭像 + 字幕）
///   → AVAssetWriter H.264 重新編碼，音軌 passthrough。
func registerVideoOverlayChannel(messenger: FlutterBinaryMessenger) {
  let channel = FlutterMethodChannel(
    name: "video_overlay_channel",
    binaryMessenger: messenger
  )
  channel.setMethodCallHandler { call, result in
    guard call.method == "processVideo",
          let args       = call.arguments as? [String: Any],
          let inputPath  = args["inputPath"]  as? String,
          let outputPath = args["outputPath"] as? String
    else {
      result(FlutterMethodNotImplemented)
      return
    }
    let attachAvatar  = args["attachAvatar"]  as? Bool ?? false
    let avatarPath    = args["avatarPath"]    as? String
    let attachCaption = args["attachCaption"] as? Bool ?? false
    let caption = (args["caption"] as? String ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines)

    DispatchQueue.global(qos: .userInitiated).async {
      do {
        let res = try processVideoOverlay(
          inputPath: inputPath, outputPath: outputPath,
          attachAvatar: attachAvatar, avatarPath: avatarPath,
          attachCaption: attachCaption, caption: caption
        )
        DispatchQueue.main.async { result(res) }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(code: "overlay_failed",
                              message: error.localizedDescription, details: nil))
        }
      }
    }
  }
}

// MARK: - Core pipeline

private func overlayError(_ message: String) -> NSError {
  NSError(domain: "VideoOverlay", code: -1,
          userInfo: [NSLocalizedDescriptionKey: message])
}

private func processVideoOverlay(
  inputPath: String, outputPath: String,
  attachAvatar: Bool, avatarPath: String?,
  attachCaption: Bool, caption: String
) throws -> [String: Any] {
  guard FileManager.default.fileExists(atPath: inputPath) else {
    throw overlayError("input video not found: \(inputPath)")
  }

  let avatarOK = attachAvatar
    && (avatarPath.map { FileManager.default.fileExists(atPath: $0) } ?? false)
  let captionOK = attachCaption && !caption.isEmpty

  // 無可疊加內容（例如頭像檔不存在）→ 維持舊行為：複製原檔，burned=false
  if !avatarOK && !captionOK {
    let dstURL = URL(fileURLWithPath: outputPath)
    try FileManager.default.createDirectory(
      at: dstURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? FileManager.default.removeItem(at: dstURL)
    try FileManager.default.copyItem(at: URL(fileURLWithPath: inputPath), to: dstURL)
    return ["path": outputPath, "burned": false]
  }

  // ── 1. Asset / reader（video composition 自動轉正 preferredTransform）──
  let asset = AVURLAsset(url: URL(fileURLWithPath: inputPath))
  guard let videoTrack = asset.tracks(withMediaType: .video).first else {
    throw overlayError("no video track in: \(inputPath)")
  }
  let composition = AVVideoComposition(propertiesOf: asset)
  let displayW    = Int(composition.renderSize.width)
  let displayH    = Int(composition.renderSize.height)
  let fps         = Double(max(1, videoTrack.nominalFrameRate))

  let reader = try AVAssetReader(asset: asset)
  let videoOut = AVAssetReaderVideoCompositionOutput(
    videoTracks: asset.tracks(withMediaType: .video),
    videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
  )
  videoOut.videoComposition = composition
  videoOut.alwaysCopiesSampleData = false
  reader.add(videoOut)

  // 音軌 passthrough（outputSettings nil → 原樣複製）
  var audioOut: AVAssetReaderTrackOutput?
  if let audioTrack = asset.tracks(withMediaType: .audio).first {
    let out = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: nil)
    out.alwaysCopiesSampleData = false
    if reader.canAdd(out) { reader.add(out); audioOut = out }
  }

  // ── 2. Writer ─────────────────────────────────────────────
  let outURL = URL(fileURLWithPath: outputPath)
  try? FileManager.default.removeItem(at: outURL)
  try FileManager.default.createDirectory(
    at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)
  let writer  = try AVAssetWriter(url: outURL, fileType: .mp4)
  let bitRate = calcBitRate(w: displayW, h: displayH, fps: fps, quality: "STANDARD")
  let videoSets: [String: Any] = [
    AVVideoCodecKey:  AVVideoCodecType.h264,
    AVVideoWidthKey:  displayW,
    AVVideoHeightKey: displayH,
    AVVideoCompressionPropertiesKey: [
      AVVideoAverageBitRateKey:      bitRate,
      AVVideoProfileLevelKey:        AVVideoProfileLevelH264MainAutoLevel,
      AVVideoMaxKeyFrameIntervalKey: max(1, Int(fps)),
    ],
  ]
  let videoIn = AVAssetWriterInput(mediaType: .video, outputSettings: videoSets)
  videoIn.expectsMediaDataInRealTime = false
  let adaptor = AVAssetWriterInputPixelBufferAdaptor(
    assetWriterInput: videoIn,
    sourcePixelBufferAttributes: [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
      kCVPixelBufferWidthKey  as String: displayW,
      kCVPixelBufferHeightKey as String: displayH,
    ]
  )
  writer.add(videoIn)

  var audioIn: AVAssetWriterInput?
  if audioOut != nil {
    let input = AVAssetWriterInput(mediaType: .audio, outputSettings: nil)
    input.expectsMediaDataInRealTime = false
    if writer.canAdd(input) { writer.add(input); audioIn = input }
  }

  guard reader.startReading() else {
    throw reader.error ?? overlayError("reader 啟動失敗")
  }
  writer.startWriting()
  writer.startSession(atSourceTime: .zero)

  // ── 3. 靜態 overlay（僅繪製一次）──────────────────────────
  let overlayCG = makeStaticOverlay(
    w: displayW, h: displayH,
    avatarPath: avatarOK ? avatarPath : nil,
    caption: captionOK ? caption : nil
  )

  // ── 4. 影片幀迴圈（decode → draw → encode）───────────────
  let group = DispatchGroup()
  var encodedFrames = 0

  group.enter()
  let videoQueue = DispatchQueue(label: "video_overlay.video")
  videoIn.requestMediaDataWhenReady(on: videoQueue) {
    while videoIn.isReadyForMoreMediaData {
      guard let sample = videoOut.copyNextSampleBuffer() else {
        videoIn.markAsFinished()
        group.leave()
        return
      }
      autoreleasepool {
        guard let srcBuf = CMSampleBufferGetImageBuffer(sample),
              let pool   = adaptor.pixelBufferPool else { return }
        var dstBufOpt: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &dstBufOpt) == kCVReturnSuccess,
              let dstBuf = dstBufOpt else { return }

        CVPixelBufferLockBaseAddress(srcBuf, .readOnly)
        CVPixelBufferLockBaseAddress(dstBuf, [])
        defer {
          CVPixelBufferUnlockBaseAddress(srcBuf, .readOnly)
          CVPixelBufferUnlockBaseAddress(dstBuf, [])
        }
        guard let srcBase = CVPixelBufferGetBaseAddress(srcBuf),
              let dstBase = CVPixelBufferGetBaseAddress(dstBuf) else { return }
        let srcBPR = CVPixelBufferGetBytesPerRow(srcBuf)
        let dstBPR = CVPixelBufferGetBytesPerRow(dstBuf)
        if srcBPR == dstBPR {
          memcpy(dstBase, srcBase, dstBPR * displayH)
        } else {
          let copyW = min(srcBPR, dstBPR)
          for row in 0..<displayH {
            memcpy(dstBase + row * dstBPR, srcBase + row * srcBPR, copyW)
          }
        }

        // 疊加 overlay：CGContext.draw 會把影像頂端對到 Quartz 高 y 端
        // （= CVPixelBuffer row 0 = 畫面頂端），因此無需翻轉座標。
        if let overlayCG = overlayCG,
           let ctx = CGContext(
             data: dstBase, width: displayW, height: displayH,
             bitsPerComponent: 8, bytesPerRow: dstBPR,
             space: CGColorSpaceCreateDeviceRGB(),
             bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
               | CGBitmapInfo.byteOrder32Little.rawValue
           ) {
          ctx.draw(overlayCG, in: CGRect(x: 0, y: 0, width: displayW, height: displayH))
        }

        let pts = CMSampleBufferGetPresentationTimeStamp(sample)
        if adaptor.append(dstBuf, withPresentationTime: pts) { encodedFrames += 1 }
      }
    }
  }

  // ── 5. 音軌迴圈（passthrough）─────────────────────────────
  if let audioIn = audioIn, let audioOut = audioOut {
    group.enter()
    let audioQueue = DispatchQueue(label: "video_overlay.audio")
    audioIn.requestMediaDataWhenReady(on: audioQueue) {
      while audioIn.isReadyForMoreMediaData {
        guard let sample = audioOut.copyNextSampleBuffer() else {
          audioIn.markAsFinished()
          group.leave()
          return
        }
        audioIn.append(sample)
      }
    }
  }

  group.wait()

  // ── 6. Finish ─────────────────────────────────────────────
  let sema = DispatchSemaphore(value: 0)
  writer.finishWriting { sema.signal() }
  sema.wait()

  let ok = writer.status == .completed && encodedFrames > 0
  if !ok {
    try? FileManager.default.removeItem(at: outURL)
    throw writer.error ?? reader.error ?? overlayError("video overlay encoding failed")
  }
  return ["path": outputPath, "burned": true]
}

// MARK: - Static overlay rendering

/// 一次性繪製 overlay（透明底）：
///   - 字幕：底部置中，白字 + 陰影 + 半透明圓角底，字級隨解析度縮放
///   - 頭像：左下角圓形裁切 + 半透明深色底環
private func makeStaticOverlay(
  w: Int, h: Int, avatarPath: String?, caption: String?
) -> CGImage? {
  let size = CGSize(width: w, height: h)
  let shortSide = CGFloat(min(w, h))
  let margin = shortSide * 0.04

  let format = UIGraphicsImageRendererFormat()
  format.scale = 1
  format.opaque = false
  let renderer = UIGraphicsImageRenderer(size: size, format: format)

  let image = renderer.image { rendererCtx in
    let ctx = rendererCtx.cgContext

    // ── 字幕 ────────────────────────────────────────────────
    if let caption = caption, !caption.isEmpty {
      let fontSize = min(72, max(18, shortSide / 22))
      let shadow = NSShadow()
      shadow.shadowColor = UIColor.black.withAlphaComponent(0.7)
      shadow.shadowOffset = CGSize(width: 0, height: fontSize * 0.05)
      shadow.shadowBlurRadius = fontSize * 0.08
      let attrs: [NSAttributedString.Key: Any] = [
        .font: UIFont.systemFont(ofSize: fontSize, weight: .semibold),
        .foregroundColor: UIColor.white,
        .shadow: shadow,
      ]
      let text = NSAttributedString(string: caption, attributes: attrs)
      var textSize = text.size()
      textSize.width = min(textSize.width, CGFloat(w) - margin * 2)
      let padH = fontSize * 0.6
      let padV = fontSize * 0.35
      let textOrigin = CGPoint(
        x: (CGFloat(w) - textSize.width) / 2,
        y: CGFloat(h) - margin - padV - textSize.height
      )
      let bgRect = CGRect(
        x: textOrigin.x - padH, y: textOrigin.y - padV,
        width: textSize.width + padH * 2, height: textSize.height + padV * 2
      )
      ctx.setFillColor(UIColor.black.withAlphaComponent(0.43).cgColor)
      UIBezierPath(roundedRect: bgRect, cornerRadius: padV).fill()
      text.draw(in: CGRect(origin: textOrigin, size: textSize))
    }

    // ── 頭像 ────────────────────────────────────────────────
    if let avatarPath = avatarPath, let avatar = UIImage(contentsOfFile: avatarPath) {
      let avatarR = shortSide * 0.085
      let ringW = avatarR * 0.12
      let cx = margin + ringW + avatarR
      let cy = CGFloat(h) - margin - ringW - avatarR
      // 半透明深色底（比頭像略大一圈）
      ctx.setFillColor(UIColor.black.withAlphaComponent(0.51).cgColor)
      ctx.fillEllipse(in: CGRect(
        x: cx - avatarR - ringW, y: cy - avatarR - ringW,
        width: (avatarR + ringW) * 2, height: (avatarR + ringW) * 2))
      // 圓形裁切（aspect-fill 置中）
      let circleRect = CGRect(
        x: cx - avatarR, y: cy - avatarR, width: avatarR * 2, height: avatarR * 2)
      ctx.saveGState()
      UIBezierPath(ovalIn: circleRect).addClip()
      let imgW = avatar.size.width, imgH = avatar.size.height
      let scale = max(circleRect.width / imgW, circleRect.height / imgH)
      let drawRect = CGRect(
        x: circleRect.midX - imgW * scale / 2,
        y: circleRect.midY - imgH * scale / 2,
        width: imgW * scale, height: imgH * scale)
      avatar.draw(in: drawRect)
      ctx.restoreGState()
    }
  }

  return image.cgImage
}
