import AVFoundation
import CoreGraphics
import Flutter
import UIKit

// MARK: - 匯出合成器（iOS）
//
// 一次 decode → 同一 CGContext 疊「軌跡 / 骨架 / 浮水印」→ 一次 encode。
// 鏡像 Android ExportComposerRenderer；reader/writer 迴圈沿用 SkeletonOverlayChannel。
//
// AVVideoComposition(propertiesOf:) 自動套用 preferredTransform → renderSize 為
// display 方向；軌跡 trackPts（coded 空間）在 clip 為直立(rotation 0)時 coded==display，
// 與 Android 等價。helper 全自帶（ec 前綴）避免與 SkeletonOverlayChannel 的 file-private 衝突。

// MARK: - Data model

private struct EcLandmark {
  var xPx: Float
  var yPx: Float
  let xNorm: Float
  let yNorm: Float
  let visibility: Float
}

private let ecConnections: [(Int, Int)] = [
  (0,1),(1,2),(2,3),(3,7), (0,4),(4,5),(5,6),(6,8), (9,10),
  (11,13),(13,15),(15,17),(17,19),(19,15),(15,21),
  (12,14),(14,16),(16,18),(18,20),(20,16),(16,22),
  (11,12),(12,24),(24,23),(23,11),
  (23,25),(25,27),(27,29),(29,31),(31,27),
  (24,26),(26,28),(28,30),(30,32),(32,28),
]
private let ecLeft:  Set<Int> = [1,2,3,7,9,11,13,15,17,19,21,23,25,27,29,31]
private let ecRight: Set<Int> = [4,5,6,8,10,12,14,16,18,20,22,24,26,28,30,32]

private struct EcTrackPt { let sec: Double; let x: CGFloat; let y: CGFloat }

// MARK: - Channel registration

func registerExportComposerChannel(messenger: FlutterBinaryMessenger) {
  let channel = FlutterMethodChannel(
    name: "com.example.golf_score_app/export_composer",
    binaryMessenger: messenger
  )
  channel.setMethodCallHandler { call, result in
    guard call.method == "compose",
          let args       = call.arguments as? [String: Any],
          let clipPath   = args["clipPath"]   as? String,
          let outputPath = args["outputPath"] as? String
    else {
      result(FlutterMethodNotImplemented)
      return
    }
    let csvPath       = args["csvPath"]       as? String          // nullable
    let watermarkPath = args["watermarkPath"] as? String          // nullable
    let startSec      = (args["startSec"] as? NSNumber)?.doubleValue ?? 0.0
    let quality       = args["quality"] as? String ?? "STANDARD"
    let trackRaw      = (args["trackPts"] as? [[String: Any]]) ?? []
    let hitGlow       = (args["hitGlow"]   as? NSNumber)?.boolValue ?? false
    let sweetSpot     = (args["sweetSpot"] as? NSNumber)?.boolValue ?? false
    let impactSec     = (args["impactSec"] as? NSNumber)?.doubleValue   // nullable
    let goodShot      = (args["goodShot"]  as? NSNumber)?.boolValue     // nullable
    let passCount     = (args["passCount"] as? NSNumber)?.intValue ?? 0

    DispatchQueue.global(qos: .userInitiated).async {
      do {
        let ok = try ecCompose(
          clipPath: clipPath, csvPath: csvPath, startSec: startSec,
          trackRaw: trackRaw, watermarkPath: watermarkPath,
          hitGlow: hitGlow, sweetSpot: sweetSpot, impactSec: impactSec,
          goodShot: goodShot, passCount: passCount,
          outputPath: outputPath, quality: quality
        )
        DispatchQueue.main.async { result(ok ? outputPath : nil) }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(code: "compose_failed", message: error.localizedDescription, details: nil))
        }
      }
    }
  }
}

// MARK: - Core pipeline

private func ecCompose(
  clipPath: String, csvPath: String?, startSec: Double,
  trackRaw: [[String: Any]], watermarkPath: String?,
  hitGlow: Bool, sweetSpot: Bool, impactSec: Double?,
  goodShot: Bool?, passCount: Int,
  outputPath: String, quality: String
) throws -> Bool {
  guard FileManager.default.fileExists(atPath: clipPath) else { return false }

  // 擊球特效啟用判定：需 impactSec；甜蜜點另需 goodShot
  let drawGlow  = hitGlow && impactSec != nil
  let drawSweet = sweetSpot && impactSec != nil && goodShot != nil
  let sweetColor: CGColor = {
    if goodShot == true && passCount >= 4 { return ecColor(255, 215, 0, 1) }  // 金
    if goodShot == true                   { return ecColor(144, 202, 249, 1) } // 藍
    return ecColor(158, 158, 158, 1)                                          // 灰
  }()

  // ── Layer 啟用判定 ─────────────────────────────────────────
  var frameData: [Int: [EcLandmark?]] = [:]
  var sortedKeys: [Int] = []
  var poseW: Float = 1, poseH: Float = 1
  var skeletonOn = false
  if let csvPath = csvPath, FileManager.default.fileExists(atPath: csvPath) {
    let raw = ecParseCsv(csvPath: csvPath)
    if !raw.isEmpty {
      frameData = ecSmooth(raw, alpha: 0.35)
      sortedKeys = frameData.keys.sorted()
      if let (w, h) = ecInferPoseSize(frameData) { poseW = w; poseH = h; skeletonOn = true }
    }
  }

  // 軌跡點：pts 單位為微秒（與 Android trackPts 一致）→ 轉秒，升序
  let trackPts: [EcTrackPt] = trackRaw.compactMap { m in
    guard let xN = m["x"] as? NSNumber, let yN = m["y"] as? NSNumber,
          let pN = m["pts"] as? NSNumber else { return nil }
    return EcTrackPt(sec: pN.doubleValue / 1_000_000.0,
                     x: CGFloat(truncating: xN), y: CGFloat(truncating: yN))
  }.sorted { $0.sec < $1.sec }
  let trajectoryOn = !trackPts.isEmpty

  // 浮水印 CGImage
  let watermarkImg: CGImage? = {
    guard let path = watermarkPath,
          FileManager.default.fileExists(atPath: path),
          let img = UIImage(contentsOfFile: path) else { return nil }
    return img.cgImage
  }()

  // ── Asset / reader（video composition 自動轉正）────────────
  let asset = AVURLAsset(url: URL(fileURLWithPath: clipPath))
  guard let videoTrack = asset.tracks(withMediaType: .video).first else { return false }
  let composition = AVVideoComposition(propertiesOf: asset)
  let displayW    = Int(composition.renderSize.width)
  let displayH    = Int(composition.renderSize.height)
  let fps         = Double(max(1, videoTrack.nominalFrameRate))
  let totalFrames = max(1, Int(CMTimeGetSeconds(asset.duration) * fps))
  let shortSide   = Float(min(displayW, displayH))
  let strokeW     = CGFloat(max(0.8, min(3.0, Double(shortSide / 120.0))))
  let dotR        = CGFloat(max(1.5, min(5.0, Double(shortSide / 100.0))))

  let reader = try AVAssetReader(asset: asset)
  let readerOut = AVAssetReaderVideoCompositionOutput(
    videoTracks: asset.tracks(withMediaType: .video),
    videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
  )
  readerOut.videoComposition = composition
  readerOut.alwaysCopiesSampleData = false
  reader.add(readerOut)
  guard reader.startReading() else {
    throw reader.error ?? NSError(domain: "ExportComposer", code: -1,
                                  userInfo: [NSLocalizedDescriptionKey: "reader 啟動失敗"])
  }

  // ── Writer ─────────────────────────────────────────────────
  let outURL = URL(fileURLWithPath: outputPath)
  try? FileManager.default.removeItem(at: outURL)
  try FileManager.default.createDirectory(
    at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)
  let writer  = try AVAssetWriter(url: outURL, fileType: .mp4)
  let bitRate = calcBitRate(w: displayW, h: displayH, fps: fps, quality: quality)
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
  let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSets)
  writerInput.expectsMediaDataInRealTime = false
  let adaptor = AVAssetWriterInputPixelBufferAdaptor(
    assetWriterInput: writerInput,
    sourcePixelBufferAttributes: [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
      kCVPixelBufferWidthKey  as String: displayW,
      kCVPixelBufferHeightKey as String: displayH,
    ]
  )
  writer.add(writerInput)
  writer.startWriting()

  // 浮水印目標矩形（右下；寬 = 短邊 22%，等比；margin = 短邊 4%）。
  // 注意：繪製 context 已翻 Y 成 top-left 原點，故 y 向下增加。
  var wmRect: CGRect? = nil
  if let wm = watermarkImg {
    let targetW = CGFloat(shortSide) * 0.22
    let scale   = targetW / CGFloat(wm.width)
    let targetH = CGFloat(wm.height) * scale
    let margin  = CGFloat(shortSide) * 0.04
    wmRect = CGRect(x: CGFloat(displayW) - margin - targetW,
                    y: CGFloat(displayH) - margin - targetH,
                    width: targetW, height: targetH)
  }

  // ── Frame loop ─────────────────────────────────────────────
  var sessionStarted = false
  var frameCount = 0
  var encodedFrames = 0
  var trajCursor = 0
  var shouldBreak = false

  while reader.status == .reading && !shouldBreak {
    autoreleasepool { () -> Void in
      guard let sample = readerOut.copyNextSampleBuffer() else { shouldBreak = true; return }
      let pts = CMSampleBufferGetPresentationTimeStamp(sample)
      if !sessionStarted { writer.startSession(atSourceTime: pts); sessionStarted = true }
      guard let srcBuf = CMSampleBufferGetImageBuffer(sample) else { return }

      while !writerInput.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.005) }
      guard let pool = adaptor.pixelBufferPool else { return }
      var dstBuf: CVPixelBuffer?
      guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &dstBuf) == kCVReturnSuccess,
            let dstBuf = dstBuf else { return }

      CVPixelBufferLockBaseAddress(srcBuf, .readOnly)
      CVPixelBufferLockBaseAddress(dstBuf, [])
      defer {
        CVPixelBufferUnlockBaseAddress(srcBuf, .readOnly)
        CVPixelBufferUnlockBaseAddress(dstBuf, [])
      }
      let srcBase = CVPixelBufferGetBaseAddress(srcBuf)!
      let dstBase = CVPixelBufferGetBaseAddress(dstBuf)!
      let srcBPR  = CVPixelBufferGetBytesPerRow(srcBuf)
      let dstBPR  = CVPixelBufferGetBytesPerRow(dstBuf)
      if srcBPR == dstBPR {
        memcpy(dstBase, srcBase, dstBPR * displayH)
      } else {
        let copyW = min(srcBPR, dstBPR)
        for row in 0..<displayH { memcpy(dstBase + row * dstBPR, srcBase + row * srcBPR, copyW) }
      }

      if let ctx = ecMakeContext(base: dstBase, w: displayW, h: displayH, bpr: dstBPR) {
        // CVPixelBuffer row-0 = top；Quartz 原點在左下 → 翻 Y 成 top-left 原點
        ctx.translateBy(x: 0, y: CGFloat(displayH))
        ctx.scaleBy(x: 1, y: -1)

        // 1. 軌跡（top-left 座標，coded==display）
        if trajectoryOn {
          let ptsSec = CMTimeGetSeconds(pts)
          while trajCursor < trackPts.count && trackPts[trajCursor].sec <= ptsSec { trajCursor += 1 }
          if trajCursor >= 1 { ecDrawTrajectory(ctx: ctx, pts: trackPts, count: trajCursor) }
        }

        // 2. 骨架
        if skeletonOn {
          let csvTimeMs = Int(((startSec + CMTimeGetSeconds(pts)) * 1000.0).rounded())
          if let lms = ecGetLandmarks(frameData: frameData, target: csvTimeMs, keys: sortedKeys) {
            ecDrawSkeleton(ctx: ctx, landmarks: lms, poseW: poseW, poseH: poseH,
                           displayW: displayW, displayH: displayH, strokeW: strokeW, dotR: dotR)
          }
        }

        // 2.5 擊球特效（光暈 / 甜蜜點）：以擊球時刻為起點的擴散光圈
        if (drawGlow || drawSweet), let impactSec = impactSec {
          let progress = (CMTimeGetSeconds(pts) - impactSec - 0.12) / 1.1
          if progress >= 0, progress <= 1 {
            let shortF = CGFloat(min(displayW, displayH))
            if drawGlow {
              ecDrawImpactRing(ctx: ctx, progress: progress, color: ecColor(245, 247, 250, 1),
                               cxFrac: 0.5, cyFrac: 0.675, w: displayW, h: displayH, shortSide: shortF)
            }
            if drawSweet {
              ecDrawImpactRing(ctx: ctx, progress: progress, color: sweetColor,
                               cxFrac: 0.5194, cyFrac: 0.8469, w: displayW, h: displayH, shortSide: shortF)
            }
          }
        }

        // 3. 浮水印
        if let wm = watermarkImg, let rect = wmRect {
          ctx.saveGState()
          ctx.setAlpha(0.65)
          ctx.draw(wm, in: rect)
          ctx.restoreGState()
        }
      }

      if adaptor.append(dstBuf, withPresentationTime: pts) { encodedFrames += 1 }
      frameCount += 1

      if frameCount % 10 == 0 && totalFrames > 0 {
        let prog = min(0.95, Double(frameCount) / Double(totalFrames))
        AnalysisProgressSink.shared.send(
          op: "composeExport", progress: prog,
          label: "影片合成中 \(Int(prog * 100))%", current: frameCount, total: totalFrames)
      }
    }
  }

  writerInput.markAsFinished()
  let sema = DispatchSemaphore(value: 0)
  writer.finishWriting { sema.signal() }
  sema.wait()

  let ok = writer.status == .completed && encodedFrames > 0
  if !ok { try? FileManager.default.removeItem(at: outURL) }
  else {
    AnalysisProgressSink.shared.send(
      op: "composeExport", progress: 1.0, label: "影片合成完成",
      current: frameCount, total: frameCount)
  }
  return ok
}

// MARK: - Trajectory drawing

private func ecDrawTrajectory(ctx: CGContext, pts: [EcTrackPt], count: Int) {
  guard count >= 1 else { return }
  let trajColor  = ecColor(255, 210, 30, 230 / 255)
  let shadow     = ecColor(0, 0, 0, 100 / 255)
  if count >= 2 {
    // 陰影線
    ctx.setLineCap(.round); ctx.setLineJoin(.round)
    ctx.setStrokeColor(shadow); ctx.setLineWidth(10)
    ctx.move(to: CGPoint(x: pts[0].x, y: pts[0].y))
    for i in 1..<count { ctx.addLine(to: CGPoint(x: pts[i].x, y: pts[i].y)) }
    ctx.strokePath()
    // 主線
    ctx.setStrokeColor(trajColor); ctx.setLineWidth(7)
    ctx.move(to: CGPoint(x: pts[0].x, y: pts[0].y))
    for i in 1..<count { ctx.addLine(to: CGPoint(x: pts[i].x, y: pts[i].y)) }
    ctx.strokePath()
  }
  // 最新點圓點（白填 + 金邊）
  let last = pts[count - 1]
  let r: CGFloat = 9
  ctx.setFillColor(ecColor(255, 255, 255, 1))
  ctx.fillEllipse(in: CGRect(x: last.x - r, y: last.y - r, width: r * 2, height: r * 2))
  ctx.setStrokeColor(trajColor); ctx.setLineWidth(2)
  ctx.strokeEllipse(in: CGRect(x: last.x - r, y: last.y - r, width: r * 2, height: r * 2))
}

// MARK: - Impact ring drawing（光暈 / 甜蜜點共用）

// 三層延遲擴散圈，節奏鏡像 ImpactGlowOverlay._ImpactRingPainter（解析度無關）。
private func ecDrawImpactRing(
  ctx: CGContext, progress: Double, color: CGColor,
  cxFrac: CGFloat, cyFrac: CGFloat, w: Int, h: Int, shortSide: CGFloat
) {
  let cx = CGFloat(w) * cxFrac
  let cy = CGFloat(h) * cyFrac
  let maxR = shortSide * 0.32
  let baseStroke = max(2.0, shortSide / 360.0)
  let comps = color.components ?? [1, 1, 1, 1]
  for i in 0..<3 {
    let delay = Double(i) * 0.18
    let t = min(1.0, max(0.0, (progress - delay) / 0.65))
    if t <= 0 { continue }
    let eased = CGFloat(1.0 - (1.0 - t) * (1.0 - t))  // easeOut 近似
    let radius = maxR * 0.22 + eased * maxR
    let opacity = max(0, min(1, 1 - eased)) * 0.85
    ctx.setStrokeColor(ecColor(comps[0] * 255, comps[1] * 255, comps[2] * 255, opacity))
    ctx.setLineWidth(baseStroke + (1 - eased) * baseStroke * 0.8)
    ctx.strokeEllipse(in: CGRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2))
  }
}

// MARK: - Skeleton drawing

private func ecDrawSkeleton(
  ctx: CGContext, landmarks: [EcLandmark?],
  poseW: Float, poseH: Float, displayW: Int, displayH: Int,
  strokeW: CGFloat, dotR: CGFloat
) {
  let sx = CGFloat(displayW) / CGFloat(poseW)
  let sy = CGFloat(displayH) / CGFloat(poseH)
  ctx.setLineWidth(strokeW); ctx.setLineCap(.round)
  for (a, b) in ecConnections {
    guard a < landmarks.count, b < landmarks.count,
          let la = landmarks[a], let lb = landmarks[b],
          la.visibility >= 0.3, lb.visibility >= 0.3 else { continue }
    ctx.setStrokeColor(ecLineColor(a: a, b: b))
    ctx.move(to:    CGPoint(x: CGFloat(la.xPx) * sx, y: CGFloat(la.yPx) * sy))
    ctx.addLine(to: CGPoint(x: CGFloat(lb.xPx) * sx, y: CGFloat(lb.yPx) * sy))
    ctx.strokePath()
  }
  for (i, lm) in landmarks.enumerated() {
    guard let lm = lm, lm.visibility >= 0.3 else { continue }
    ctx.setFillColor(ecPointColor(i: i))
    let cx = CGFloat(lm.xPx) * sx, cy = CGFloat(lm.yPx) * sy
    ctx.fillEllipse(in: CGRect(x: cx - dotR, y: cy - dotR, width: dotR * 2, height: dotR * 2))
  }
}

private func ecLineColor(a: Int, b: Int) -> CGColor {
  let al: CGFloat = 210 / 255
  if a == 16 || b == 16 { return ecColor(255, 50, 50, al) }
  if ecLeft.contains(a) && ecLeft.contains(b) { return ecColor(0, 230, 90, al) }
  if ecRight.contains(a) && ecRight.contains(b) { return ecColor(70, 150, 240, al) }
  return ecColor(255, 215, 0, al)
}

private func ecPointColor(i: Int) -> CGColor {
  let al: CGFloat = 230 / 255
  if i == 16 { return ecColor(255, 30, 30, al) }
  if ecLeft.contains(i) { return ecColor(0, 200, 70, al) }
  if ecRight.contains(i) { return ecColor(70, 140, 220, al) }
  return ecColor(255, 200, 0, al)
}

// MARK: - CSV parse / smooth / interpolate / infer

private func ecParseCsv(csvPath: String) -> [Int: [EcLandmark?]] {
  guard let content = try? String(contentsOfFile: csvPath, encoding: .utf8) else { return [:] }
  var result: [Int: [EcLandmark?]] = [:]
  var skipHeader = true
  for line in content.components(separatedBy: "\n") {
    if skipHeader { skipHeader = false; continue }
    let cols = line.components(separatedBy: ",")
    guard cols.count >= 201 else { continue }
    guard let timeSec = Double(cols[1].trimmingCharacters(in: .whitespaces)) else { continue }
    let timeMs = Int((timeSec * 1000.0).rounded())
    var lms = [EcLandmark?](repeating: nil, count: 33)
    for i in 0..<33 {
      let b = 3 + i * 6
      guard let xNorm = Float(cols[b].trimmingCharacters(in: .whitespaces)),   !xNorm.isNaN,
            let yNorm = Float(cols[b+1].trimmingCharacters(in: .whitespaces)), !yNorm.isNaN,
            let vis   = Float(cols[b+3].trimmingCharacters(in: .whitespaces)),
            let xPx   = Float(cols[b+4].trimmingCharacters(in: .whitespaces)), !xPx.isNaN,
            let yPx   = Float(cols[b+5].trimmingCharacters(in: .whitespaces)), !yPx.isNaN,
            xNorm > 0, yNorm > 0 else { continue }
      lms[i] = EcLandmark(xPx: xPx, yPx: yPx, xNorm: xNorm, yNorm: yNorm, visibility: vis)
    }
    result[timeMs] = lms
  }
  return result
}

private func ecSmooth(_ raw: [Int: [EcLandmark?]], alpha: Float) -> [Int: [EcLandmark?]] {
  guard raw.count >= 3 else { return raw }
  let sorted = raw.keys.sorted()
  var result = raw
  for lmIdx in 0..<33 {
    var px = Float.nan, py = Float.nan
    for key in sorted {
      guard let arr = result[key], lmIdx < arr.count, var lm = arr[lmIdx] else { continue }
      if px.isNaN { px = lm.xPx; py = lm.yPx; continue }
      px = alpha * lm.xPx + (1 - alpha) * px
      py = alpha * lm.yPx + (1 - alpha) * py
      lm.xPx = px; lm.yPx = py
      result[key]?[lmIdx] = lm
    }
    px = Float.nan; py = Float.nan
    for key in sorted.reversed() {
      guard let arr = result[key], lmIdx < arr.count, var lm = arr[lmIdx] else { continue }
      if px.isNaN { px = lm.xPx; py = lm.yPx; continue }
      px = alpha * lm.xPx + (1 - alpha) * px
      py = alpha * lm.yPx + (1 - alpha) * py
      lm.xPx = px; lm.yPx = py
      result[key]?[lmIdx] = lm
    }
  }
  return result
}

private func ecGetLandmarks(frameData: [Int: [EcLandmark?]], target: Int, keys: [Int]) -> [EcLandmark?]? {
  if let exact = frameData[target] { return exact }
  guard let prevKey = keys.last(where: { $0 < target }),
        let nextKey = keys.first(where: { $0 > target }),
        let prevLms = frameData[prevKey],
        let nextLms = frameData[nextKey] else { return nil }
  let t = Float(target - prevKey) / Float(nextKey - prevKey)
  return (0..<33).map { i in
    switch (prevLms[i], nextLms[i]) {
    case let (a?, b?):
      return EcLandmark(
        xPx: a.xPx + (b.xPx - a.xPx) * t, yPx: a.yPx + (b.yPx - a.yPx) * t,
        xNorm: a.xNorm, yNorm: a.yNorm,
        visibility: a.visibility * (1 - t) + b.visibility * t)
    case let (a?, _): return a
    case let (_, b?): return b
    default:          return nil
    }
  }
}

private func ecInferPoseSize(_ frameData: [Int: [EcLandmark?]]) -> (Float, Float)? {
  for (_, lms) in frameData {
    for case let lm? in lms {
      if lm.xNorm > 0.05 && lm.yNorm > 0.05 {
        let w = lm.xPx / lm.xNorm, h = lm.yPx / lm.yNorm
        if w > 50 && h > 50 { return (w, h) }
      }
    }
  }
  return nil
}

// MARK: - Helpers

private func ecMakeContext(base: UnsafeMutableRawPointer, w: Int, h: Int, bpr: Int) -> CGContext? {
  CGContext(
    data: base, width: w, height: h, bitsPerComponent: 8, bytesPerRow: bpr,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
  )
}

private func ecColor(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat) -> CGColor {
  CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [r / 255, g / 255, b / 255, a])!
}
