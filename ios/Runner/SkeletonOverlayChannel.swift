import AVFoundation
import CoreGraphics
import Flutter

// MARK: - Data model

private struct LandmarkPoint {
  var xPx: Float
  var yPx: Float
  let xNorm: Float
  let yNorm: Float
  let visibility: Float
}

// MARK: - Skeleton topology (mirrors Android SkeletonOverlayRenderer)

private let skeletonConnections: [(Int, Int)] = [
  (0,1),(1,2),(2,3),(3,7), (0,4),(4,5),(5,6),(6,8), (9,10),
  (11,13),(13,15),(15,17),(17,19),(19,15),(15,21),
  (12,14),(14,16),(16,18),(18,20),(20,16),(16,22),
  (11,12),(12,24),(24,23),(23,11),
  (23,25),(25,27),(27,29),(29,31),(31,27),
  (24,26),(26,28),(28,30),(30,32),(32,28),
]
private let leftLandmarks:  Set<Int> = [1,2,3,7,9,11,13,15,17,19,21,23,25,27,29,31]
private let rightLandmarks: Set<Int> = [4,5,6,8,10,12,14,16,18,20,22,24,26,28,30,32]

// MARK: - Channel registration

func registerSkeletonOverlayChannel(messenger: FlutterBinaryMessenger) {
  let channel = FlutterMethodChannel(
    name: "com.example.golf_score_app/skeleton_overlay",
    binaryMessenger: messenger
  )
  channel.setMethodCallHandler { call, result in
    guard call.method == "render",
          let args       = call.arguments as? [String: Any],
          let clipPath   = args["clipPath"]   as? String,
          let csvPath    = args["csvPath"]    as? String,
          let outputPath = args["outputPath"] as? String
    else {
      result(FlutterMethodNotImplemented)
      return
    }
    let startSec = (args["startSec"] as? NSNumber)?.doubleValue ?? 0.0
    let quality  = args["quality"] as? String ?? "STANDARD"

    DispatchQueue.global(qos: .userInitiated).async {
      do {
        let ok = try renderSkeletonOverlay(
          clipPath: clipPath, csvPath: csvPath,
          startSec: startSec, outputPath: outputPath, quality: quality
        )
        DispatchQueue.main.async { result(ok) }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(code: "render_failed", message: error.localizedDescription, details: nil))
        }
      }
    }
  }
}

// MARK: - Core pipeline

private func renderSkeletonOverlay(
  clipPath: String, csvPath: String,
  startSec: Double, outputPath: String, quality: String
) throws -> Bool {

  // 1. Parse CSV → smooth → infer pose image size
  let rawData   = parseCsv(csvPath: csvPath)
  guard !rawData.isEmpty else { return false }
  let frameData  = smoothFrameData(rawData, alpha: 0.35)
  let sortedKeys = frameData.keys.sorted()
  guard let (poseW, poseH) = inferPoseImageSize(frameData) else { return false }

  // 2. Video asset info
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

  // 3. Reader
  let reader = try AVAssetReader(asset: asset)
  let readerOut = AVAssetReaderVideoCompositionOutput(
    videoTracks: asset.tracks(withMediaType: .video),
    videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
  )
  readerOut.videoComposition = composition
  readerOut.alwaysCopiesSampleData = false
  reader.add(readerOut)
  guard reader.startReading() else {
    throw reader.error ?? NSError(domain: "SkeletonOverlay", code: -1,
                                  userInfo: [NSLocalizedDescriptionKey: "reader 啟動失敗"])
  }

  // 4. Writer
  let outURL = URL(fileURLWithPath: outputPath)
  try? FileManager.default.removeItem(at: outURL)
  try FileManager.default.createDirectory(
    at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)
  let writer     = try AVAssetWriter(url: outURL, fileType: .mp4)
  let bitRate    = calcBitRate(w: displayW, h: displayH, fps: fps, quality: quality)
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

  // 5. Frame loop
  var sessionStarted = false
  var frameCount     = 0
  var encodedFrames  = 0

  var shouldBreak = false
  while reader.status == .reading && !shouldBreak {
    autoreleasepool { () -> Void in
      guard let sample = readerOut.copyNextSampleBuffer() else {
        shouldBreak = true
        return
      }
      let pts = CMSampleBufferGetPresentationTimeStamp(sample)
      if !sessionStarted { writer.startSession(atSourceTime: pts); sessionStarted = true }
      guard let srcBuf = CMSampleBufferGetImageBuffer(sample) else { return }

      // Wait for writer before allocating, to avoid pool exhaustion / dropped frames
      while !writerInput.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.005) }
      guard let pool = adaptor.pixelBufferPool else { return }
      var dstBuf: CVPixelBuffer?
      guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &dstBuf) == kCVReturnSuccess,
            let dstBuf = dstBuf else { return }

      // Copy source → destination
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
        for row in 0..<displayH {
          memcpy(dstBase + row * dstBPR, srcBase + row * srcBPR, copyW)
        }
      }

      // Draw skeleton onto destination (still locked)
      let ptsSec      = CMTimeGetSeconds(pts)
      let csvFrameIdx = Int((( startSec + ptsSec) * 1000.0 / 33.0).rounded())
      if let lms = getSmoothedLandmarks(frameData: frameData, target: csvFrameIdx, keys: sortedKeys),
         let ctx = makeCGContext(base: dstBase, w: displayW, h: displayH, bpr: dstBPR) {
        // CVPixelBuffer row-0 = top; Quartz origin is bottom-left → flip Y axis
        ctx.translateBy(x: 0, y: CGFloat(displayH))
        ctx.scaleBy(x: 1, y: -1)
        drawSkeleton(ctx: ctx, landmarks: lms,
                     poseW: poseW, poseH: poseH,
                     displayW: displayW, displayH: displayH,
                     strokeW: strokeW, dotR: dotR)
      }
      // defer handles unlock above

      if adaptor.append(dstBuf, withPresentationTime: pts) { encodedFrames += 1 }
      frameCount += 1

      if frameCount % 10 == 0 && totalFrames > 0 {
        let prog = min(0.95, Double(frameCount) / Double(totalFrames))
        AnalysisProgressSink.shared.send(
          op: "renderSkeleton", progress: prog,
          label: "骨架渲染中 \(Int(prog * 100))%", current: frameCount, total: totalFrames)
      }
    }
  }

  // 6. Finish
  writerInput.markAsFinished()
  let sema = DispatchSemaphore(value: 0)
  writer.finishWriting { sema.signal() }
  sema.wait()

  let ok = writer.status == .completed && encodedFrames > 0
  if !ok { try? FileManager.default.removeItem(at: outURL) }
  if  ok {
    AnalysisProgressSink.shared.send(
      op: "renderSkeleton", progress: 1.0, label: "骨架渲染完成",
      current: frameCount, total: frameCount)
  }
  return ok
}

// MARK: - CSV parsing

private func parseCsv(csvPath: String) -> [Int: [LandmarkPoint?]] {
  guard let content = try? String(contentsOfFile: csvPath, encoding: .utf8) else { return [:] }
  var result: [Int: [LandmarkPoint?]] = [:]
  var skipHeader = true
  for line in content.components(separatedBy: "\n") {
    if skipHeader { skipHeader = false; continue }
    let cols = line.components(separatedBy: ",")
    guard cols.count >= 201,
          let frameIdx = Int(cols[0].trimmingCharacters(in: .whitespaces)) else { continue }
    var lms = [LandmarkPoint?](repeating: nil, count: 33)
    for i in 0..<33 {
      let b = 3 + i * 6
      guard let xNorm = Float(cols[b].trimmingCharacters(in: .whitespaces)),   !xNorm.isNaN,
            let yNorm = Float(cols[b+1].trimmingCharacters(in: .whitespaces)), !yNorm.isNaN,
            let vis   = Float(cols[b+3].trimmingCharacters(in: .whitespaces)),
            let xPx   = Float(cols[b+4].trimmingCharacters(in: .whitespaces)), !xPx.isNaN,
            let yPx   = Float(cols[b+5].trimmingCharacters(in: .whitespaces)), !yPx.isNaN,
            xNorm > 0, yNorm > 0 else { continue }
      lms[i] = LandmarkPoint(xPx: xPx, yPx: yPx, xNorm: xNorm, yNorm: yNorm, visibility: vis)
    }
    result[frameIdx] = lms
  }
  return result
}

// MARK: - Bidirectional EMA smoothing

private func smoothFrameData(_ raw: [Int: [LandmarkPoint?]], alpha: Float) -> [Int: [LandmarkPoint?]] {
  guard raw.count >= 3 else { return raw }
  let sorted = raw.keys.sorted()
  var result = raw

  for lmIdx in 0..<33 {
    // Forward
    var px = Float.nan, py = Float.nan
    for key in sorted {
      guard var lm = result[key]![lmIdx] else { continue }
      if px.isNaN { px = lm.xPx; py = lm.yPx; continue }
      px = alpha * lm.xPx + (1 - alpha) * px
      py = alpha * lm.yPx + (1 - alpha) * py
      lm.xPx = px; lm.yPx = py
      result[key]![lmIdx] = lm
    }
    // Backward
    px = Float.nan; py = Float.nan
    for key in sorted.reversed() {
      guard var lm = result[key]![lmIdx] else { continue }
      if px.isNaN { px = lm.xPx; py = lm.yPx; continue }
      px = alpha * lm.xPx + (1 - alpha) * px
      py = alpha * lm.yPx + (1 - alpha) * py
      lm.xPx = px; lm.yPx = py
      result[key]![lmIdx] = lm
    }
  }
  return result
}

// MARK: - Frame interpolation

private func getSmoothedLandmarks(
  frameData: [Int: [LandmarkPoint?]], target: Int, keys: [Int]
) -> [LandmarkPoint?]? {
  if let exact = frameData[target] { return exact }
  guard let prevKey = keys.last(where: { $0 < target }),
        let nextKey = keys.first(where: { $0 > target }),
        let prevLms = frameData[prevKey],
        let nextLms = frameData[nextKey] else { return nil }
  let t = Float(target - prevKey) / Float(nextKey - prevKey)
  return (0..<33).map { i in
    switch (prevLms[i], nextLms[i]) {
    case let (a?, b?):
      return LandmarkPoint(
        xPx: a.xPx + (b.xPx - a.xPx) * t, yPx: a.yPx + (b.yPx - a.yPx) * t,
        xNorm: a.xNorm, yNorm: a.yNorm,
        visibility: a.visibility * (1 - t) + b.visibility * t)
    case let (a?, _): return a
    case let (_, b?): return b
    default:          return nil
    }
  }
}

// MARK: - Pose image size inference

private func inferPoseImageSize(_ frameData: [Int: [LandmarkPoint?]]) -> (Float, Float)? {
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

// MARK: - Skeleton drawing

private func drawSkeleton(
  ctx: CGContext,
  landmarks: [LandmarkPoint?],
  poseW: Float, poseH: Float,
  displayW: Int, displayH: Int,
  strokeW: CGFloat, dotR: CGFloat
) {
  let sx = CGFloat(displayW) / CGFloat(poseW)
  let sy = CGFloat(displayH) / CGFloat(poseH)
  ctx.setLineWidth(strokeW)
  ctx.setLineCap(.round)

  for (a, b) in skeletonConnections {
    guard a < landmarks.count, b < landmarks.count,
          let la = landmarks[a], let lb = landmarks[b],
          la.visibility >= 0.3, lb.visibility >= 0.3 else { continue }
    ctx.setStrokeColor(lineColor(a: a, b: b))
    ctx.move(to:    CGPoint(x: CGFloat(la.xPx) * sx, y: CGFloat(la.yPx) * sy))
    ctx.addLine(to: CGPoint(x: CGFloat(lb.xPx) * sx, y: CGFloat(lb.yPx) * sy))
    ctx.strokePath()
  }

  for (i, lm) in landmarks.enumerated() {
    guard let lm = lm, lm.visibility >= 0.3 else { continue }
    ctx.setFillColor(pointColor(i: i))
    let cx = CGFloat(lm.xPx) * sx, cy = CGFloat(lm.yPx) * sy
    ctx.fillEllipse(in: CGRect(x: cx - dotR, y: cy - dotR, width: dotR * 2, height: dotR * 2))
  }
}

private func lineColor(a: Int, b: Int) -> CGColor {
  let al: CGFloat = 210 / 255
  if a == 16 || b == 16 {
    return cgColorRGB(255, 50,  50,  al)
  }
  if leftLandmarks.contains(a) && leftLandmarks.contains(b) {
    return cgColorRGB(0,   230, 90,  al)
  }
  if rightLandmarks.contains(a) && rightLandmarks.contains(b) {
    return cgColorRGB(70,  150, 240, al)
  }
  return cgColorRGB(255, 215, 0, al)
}

private func pointColor(i: Int) -> CGColor {
  let al: CGFloat = 230 / 255
  if i == 16                       { return cgColorRGB(255, 30,  30,  al) }
  if leftLandmarks.contains(i)     { return cgColorRGB(0,   200, 70,  al) }
  if rightLandmarks.contains(i)    { return cgColorRGB(70,  140, 220, al) }
  return cgColorRGB(255, 200, 0, al)
}

// MARK: - Shared helpers

private func makeCGContext(base: UnsafeMutableRawPointer, w: Int, h: Int, bpr: Int) -> CGContext? {
  CGContext(
    data: base, width: w, height: h, bitsPerComponent: 8, bytesPerRow: bpr,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
  )
}

private func cgColorRGB(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat) -> CGColor {
  let comps: [CGFloat] = [r / 255, g / 255, b / 255, a]
  return CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: comps)!
}

func calcBitRate(w: Int, h: Int, fps: Double, quality: String) -> Int {
  switch quality.uppercased() {
  case "SMALL": return max(4_000_000, min(10_000_000, Int(Double(w * h) * fps * 0.50)))
  case "HIGH":  return max(8_000_000, min(40_000_000, Int(Double(w * h) * fps * 1.00)))
  default:      return max(6_000_000, min(20_000_000, Int(Double(w * h) * fps * 0.75)))
  }
}
