import AVFoundation
import CoreGraphics
import Flutter

// MARK: - Types

private struct BlobConfig {
  var diffThresh: Int    = 18
  var areaLo:    Int    = 5
  var areaHi:    Int    = 600
  var circMin:   Double = 0.30
  var morphK:    Int    = 3
}

private struct BlobResult {
  let cx: Int; let cy: Int
  let area: Int; let circ: Double; let diffMean: Double
}

private struct TrackPoint {
  let x: Int; let y: Int; let ptsUs: Int64
}

// MARK: - Channel registration

func registerBallTrajectoryChannel(messenger: FlutterBinaryMessenger) {
  let channel = FlutterMethodChannel(
    name: "com.example.golf_score_app/ball_trajectory",
    binaryMessenger: messenger
  )
  channel.setMethodCallHandler { call, result in
    switch call.method {

    case "extractBlobs", "extractBlobsWithConfig":
      guard let args      = call.arguments as? [String: Any],
            let videoPath = args["videoPath"] as? String else {
        result(FlutterMethodNotImplemented); return
      }
      var cfg = BlobConfig()
      if let c = args["config"] as? [String: Any] {
        cfg.diffThresh = (c["diffThresh"] as? NSNumber)?.intValue    ?? cfg.diffThresh
        cfg.areaLo     = (c["areaLo"]     as? NSNumber)?.intValue    ?? cfg.areaLo
        cfg.areaHi     = (c["areaHi"]     as? NSNumber)?.intValue    ?? cfg.areaHi
        cfg.circMin    = (c["circMin"]     as? NSNumber)?.doubleValue ?? cfg.circMin
        cfg.morphK     = (c["morphK"]      as? NSNumber)?.intValue    ?? cfg.morphK
      }
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          let out = try btExtractBlobs(videoPath: videoPath, config: cfg)
          DispatchQueue.main.async { result(out) }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(code: "extract_failed", message: error.localizedDescription, details: nil))
          }
        }
      }

    case "renderOverlay":
      guard let args       = call.arguments as? [String: Any],
            let inputPath  = args["inputPath"]  as? String,
            let outputPath = args["outputPath"] as? String,
            let rawPts     = args["trackPts"]   as? [[String: Any]] else {
        result(FlutterMethodNotImplemented); return
      }
      let roiSize = (args["roiSize"] as? NSNumber)?.intValue ?? 0
      let quality = args["quality"] as? String ?? "STANDARD"
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          let ok = try btRenderOverlay(
            inputPath: inputPath, outputPath: outputPath,
            rawTrackPts: rawPts, roiSize: roiSize, quality: quality)
          DispatchQueue.main.async { result(ok) }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(code: "render_failed", message: error.localizedDescription, details: nil))
          }
        }
      }

    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

// MARK: - Blob extraction

private func btExtractBlobs(videoPath: String, config: BlobConfig) throws -> [String: Any] {
  let asset = AVURLAsset(url: URL(fileURLWithPath: videoPath))
  guard let videoTrack = asset.tracks(withMediaType: .video).first else {
    throw NSError(domain: "BallTrajectory", code: -1,
                  userInfo: [NSLocalizedDescriptionKey: "找不到視頻軌道"])
  }

  let composition = AVVideoComposition(propertiesOf: asset)
  let displayW    = Int(composition.renderSize.width)
  let displayH    = Int(composition.renderSize.height)
  let fps         = Double(max(1, videoTrack.nominalFrameRate))
  let totalFrames = max(1, Int(CMTimeGetSeconds(asset.duration) * fps))
  let pixCount    = displayW * displayH

  let reader = try AVAssetReader(asset: asset)
  let readerOut = AVAssetReaderVideoCompositionOutput(
    videoTracks: asset.tracks(withMediaType: .video),
    videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
  )
  readerOut.videoComposition = composition
  readerOut.alwaysCopiesSampleData = false
  reader.add(readerOut)
  guard reader.startReading() else {
    throw reader.error ?? NSError(domain: "BallTrajectory", code: -2,
                                  userInfo: [NSLocalizedDescriptionKey: "reader 啟動失敗"])
  }

  var frames: [[String: Any]] = []
  var prevY: [UInt8]? = nil
  var frameIdx: Int = 0

  while reader.status == .reading {
    guard let sample: CMSampleBuffer = readerOut.copyNextSampleBuffer() else { break }

    if let result: BtFrameResult = autoreleasepool(invoking: {
      btProcessFrame(
        sample: sample, config: config,
        pixCount: pixCount, displayW: displayW, displayH: displayH,
        prevY: prevY)
    }) {
      frames.append(result.entry)
      prevY = result.currY
      frameIdx += 1

      if frameIdx % 10 == 0 {
        let prog: Double = min(0.95, Double(frameIdx) / Double(totalFrames))
        AnalysisProgressSink.shared.send(
          op: "extractBlobs", progress: prog,
          label: "球體偵測中 \(Int(prog * 100))%", current: frameIdx, total: totalFrames)
      }
    }
  }

  AnalysisProgressSink.shared.send(
    op: "extractBlobs", progress: 1.0, label: "球體偵測完成",
    current: frameIdx, total: frameIdx)

  return ["fps": fps, "width": displayW, "height": displayH, "frames": frames]
}

// MARK: - Per-frame processing

private struct BtFrameResult {
  let entry: [String: Any]
  let currY: [UInt8]
}

private func btProcessFrame(
  sample: CMSampleBuffer,
  config: BlobConfig,
  pixCount: Int,
  displayW: Int,
  displayH: Int,
  prevY: [UInt8]?
) -> BtFrameResult? {
  guard let pixBuf: CVPixelBuffer = CMSampleBufferGetImageBuffer(sample) else { return nil }
  let pts: CMTime = CMSampleBufferGetPresentationTimeStamp(sample)
  let ptsSec: Double = CMTimeGetSeconds(pts)
  let ptsUs: Int64 = Int64(ptsSec * 1_000_000)

  CVPixelBufferLockBaseAddress(pixBuf, .readOnly)
  let base = CVPixelBufferGetBaseAddress(pixBuf)!
  let bpr: Int = CVPixelBufferGetBytesPerRow(pixBuf)
  let rgba = base.assumingMemoryBound(to: UInt8.self)

  var currY = [UInt8](repeating: 0, count: pixCount)
  for j in 0..<displayH {
    let rowOff: Int = j * bpr
    let yOff: Int   = j * displayW
    for i in 0..<displayW {
      let o: Int = rowOff + i * 4
      let b = Int(rgba[o]), g = Int(rgba[o + 1]), r = Int(rgba[o + 2])
      let luma: Int = (299 * r + 587 * g + 114 * b) / 1000
      currY[yOff + i] = UInt8(min(255, luma))
    }
  }
  CVPixelBufferUnlockBaseAddress(pixBuf, .readOnly)

  var frameBlobs: [[String: Any]] = []
  if let prev: [UInt8] = prevY {
    // Frame diff: raw intensity + binary mask
    var rawDiff = [UInt8](repeating: 0, count: pixCount)
    var binMask = [UInt8](repeating: 0, count: pixCount)
    for i in 0..<pixCount {
      let d: Int = abs(Int(currY[i]) - Int(prev[i]))
      rawDiff[i] = UInt8(min(255, d))
      binMask[i] = d >= config.diffThresh ? 1 : 0
    }

    // Morphological opening (erode → dilate)
    let opened: [UInt8] = btMorphOpen(mask: binMask, w: displayW, h: displayH, k: config.morphK)

    // BFS 4-connected blob detection
    let blobs: [BlobResult] = btBfsBlobs(
      mask: opened, rawDiff: rawDiff, w: displayW, h: displayH,
      areaLo: config.areaLo, areaHi: config.areaHi, circMin: config.circMin)

    for b in blobs {
      let blobEntry: [String: Any] = [
        "cx": b.cx, "cy": b.cy,
        "area": b.area, "circ": b.circ, "diffMean": b.diffMean,
      ]
      frameBlobs.append(blobEntry)
    }
  }

  return BtFrameResult(entry: ["ptsUs": ptsUs, "blobs": frameBlobs], currY: currY)
}

// MARK: - Morphological helpers

private func btMorphOpen(mask: [UInt8], w: Int, h: Int, k: Int) -> [UInt8] {
  btMorphDilate(mask: btMorphErode(mask: mask, w: w, h: h, k: k), w: w, h: h, k: k)
}

private func btMorphErode(mask: [UInt8], w: Int, h: Int, k: Int) -> [UInt8] {
  let half = k / 2
  var out = [UInt8](repeating: 0, count: w * h)
  for j in 0..<h {
    for i in 0..<w {
      var keep = true
      outer: for dy in -half...half {
        for dx in -half...half {
          let ni = i + dx, nj = j + dy
          if ni < 0 || ni >= w || nj < 0 || nj >= h || mask[nj * w + ni] == 0 {
            keep = false; break outer
          }
        }
      }
      out[j * w + i] = keep ? 1 : 0
    }
  }
  return out
}

private func btMorphDilate(mask: [UInt8], w: Int, h: Int, k: Int) -> [UInt8] {
  let half = k / 2
  var out = [UInt8](repeating: 0, count: w * h)
  for j in 0..<h {
    for i in 0..<w {
      guard mask[j * w + i] != 0 else { continue }
      for dy in -half...half {
        for dx in -half...half {
          let ni = i + dx, nj = j + dy
          if ni >= 0 && ni < w && nj >= 0 && nj < h { out[nj * w + ni] = 1 }
        }
      }
    }
  }
  return out
}

// MARK: - BFS blob detection

private func btBfsBlobs(
  mask: [UInt8], rawDiff: [UInt8],
  w: Int, h: Int,
  areaLo: Int, areaHi: Int, circMin: Double
) -> [BlobResult] {
  var visited = [Bool](repeating: false, count: w * h)
  var blobs   = [BlobResult]()

  for start in 0..<(w * h) {
    guard mask[start] != 0 && !visited[start] else { continue }

    var queue   = [Int](); queue.reserveCapacity(64)
    var pixels  = [Int](); pixels.reserveCapacity(64)
    queue.append(start); pixels.append(start)
    visited[start] = true
    var qi = 0

    while qi < queue.count {
      let cur = queue[qi]; qi += 1
      let ci = cur % w, cj = cur / w
      for (di, dj) in [(-1,0),(1,0),(0,-1),(0,1)] {
        let ni = ci + di, nj = cj + dj
        guard ni >= 0 && ni < w && nj >= 0 && nj < h else { continue }
        let nb = nj * w + ni
        guard !visited[nb] && mask[nb] != 0 else { continue }
        visited[nb] = true
        queue.append(nb); pixels.append(nb)
      }
    }

    let area = pixels.count
    guard area >= areaLo && area <= areaHi else { continue }

    var sumX = 0, sumY = 0, sumDiff = 0, perim = 0
    for px in pixels {
      let xi = px % w, yj = px / w
      sumX += xi; sumY += yj; sumDiff += Int(rawDiff[px])
      for (di, dj) in [(-1,0),(1,0),(0,-1),(0,1)] {
        let ni = xi + di, nj = yj + dj
        if ni < 0 || ni >= w || nj < 0 || nj >= h || mask[nj * w + ni] == 0 { perim += 1 }
      }
    }

    let circ = perim > 0 ? 4 * Double.pi * Double(area) / Double(perim * perim) : 0.0
    guard circ >= circMin else { continue }

    blobs.append(BlobResult(
      cx: sumX / area, cy: sumY / area, area: area,
      circ: circ, diffMean: Double(sumDiff) / Double(area)))
  }
  return blobs
}

// MARK: - Trajectory overlay rendering

private func btRenderOverlay(
  inputPath: String, outputPath: String,
  rawTrackPts: [[String: Any]], roiSize: Int, quality: String
) throws -> Bool {

  let pts: [TrackPoint] = rawTrackPts.compactMap { d in
    guard let x = (d["x"]   as? NSNumber)?.intValue,
          let y = (d["y"]   as? NSNumber)?.intValue,
          let t = (d["pts"] as? NSNumber)?.int64Value else { return nil }
    return TrackPoint(x: x, y: y, ptsUs: t)
  }.sorted { $0.ptsUs < $1.ptsUs }

  let asset = AVURLAsset(url: URL(fileURLWithPath: inputPath))
  guard let videoTrack = asset.tracks(withMediaType: .video).first else { return false }

  let composition = AVVideoComposition(propertiesOf: asset)
  let displayW    = Int(composition.renderSize.width)
  let displayH    = Int(composition.renderSize.height)
  let fps         = Double(max(1, videoTrack.nominalFrameRate))
  let totalFrames = max(1, Int(CMTimeGetSeconds(asset.duration) * fps))

  // Reader
  let reader = try AVAssetReader(asset: asset)
  let readerOut = AVAssetReaderVideoCompositionOutput(
    videoTracks: asset.tracks(withMediaType: .video),
    videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
  )
  readerOut.videoComposition = composition
  readerOut.alwaysCopiesSampleData = false
  reader.add(readerOut)
  guard reader.startReading() else {
    throw reader.error ?? NSError(domain: "BallTrajectory", code: -3,
                                  userInfo: [NSLocalizedDescriptionKey: "reader 啟動失敗"])
  }

  // Writer
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

  var sessionStarted = false
  var frameCount = 0, encodedFrames = 0

  while reader.status == .reading {
    guard let sample = readerOut.copyNextSampleBuffer() else { break }
    let framePts = CMSampleBufferGetPresentationTimeStamp(sample)
    if !sessionStarted { writer.startSession(atSourceTime: framePts); sessionStarted = true }
    guard let srcBuf = CMSampleBufferGetImageBuffer(sample) else { continue }

    // Wait for writer before allocating, to avoid pool exhaustion / dropped frames
    while !writerInput.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.005) }
    guard let pool = adaptor.pixelBufferPool else { continue }
    var dstBuf: CVPixelBuffer?
    guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &dstBuf) == kCVReturnSuccess,
          let dstBuf = dstBuf else { continue }

    CVPixelBufferLockBaseAddress(srcBuf, .readOnly)
    CVPixelBufferLockBaseAddress(dstBuf, [])
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
    CVPixelBufferUnlockBaseAddress(srcBuf, .readOnly)

    let frameUs   = Int64(CMTimeGetSeconds(framePts) * 1_000_000)
    let visiblePts = btBinarySearchLast(pts: pts, upToUs: frameUs)

    if !visiblePts.isEmpty,
       let ctx = btMakeCGContext(base: dstBase, w: displayW, h: displayH, bpr: dstBPR) {
      // CVPixelBuffer row-0 = top; Quartz origin is bottom-left → flip Y axis
      ctx.translateBy(x: 0, y: CGFloat(displayH))
      ctx.scaleBy(x: 1, y: -1)
      btDrawTrajectory(ctx: ctx, pts: visiblePts, roiSize: roiSize, w: displayW, h: displayH)
    }
    CVPixelBufferUnlockBaseAddress(dstBuf, [])

    if adaptor.append(dstBuf, withPresentationTime: framePts) { encodedFrames += 1 }
    frameCount += 1

    if frameCount % 10 == 0 && totalFrames > 0 {
      let prog = min(0.95, Double(frameCount) / Double(totalFrames))
      AnalysisProgressSink.shared.send(
        op: "renderTrajectory", progress: prog,
        label: "軌跡渲染中 \(Int(prog * 100))%", current: frameCount, total: totalFrames)
    }
  }

  writerInput.markAsFinished()
  let sema = DispatchSemaphore(value: 0)
  writer.finishWriting { sema.signal() }
  sema.wait()

  let ok = writer.status == .completed && encodedFrames > 0
  if !ok { try? FileManager.default.removeItem(at: outURL) }
  if  ok {
    AnalysisProgressSink.shared.send(
      op: "renderTrajectory", progress: 1.0, label: "軌跡渲染完成",
      current: frameCount, total: frameCount)
  }
  return ok
}

// MARK: - Trajectory drawing

private func btBinarySearchLast(pts: [TrackPoint], upToUs: Int64) -> [TrackPoint] {
  var lo = 0, hi = pts.count
  while lo < hi {
    let mid = (lo + hi) / 2
    if pts[mid].ptsUs <= upToUs { lo = mid + 1 } else { hi = mid }
  }
  return Array(pts.prefix(lo))
}

private func btDrawTrajectory(
  ctx: CGContext, pts: [TrackPoint], roiSize: Int, w: Int, h: Int
) {
  guard pts.count >= 1 else { return }

  let goldColor    = btCGColor(255, 210,  30, 230 / 255.0)
  let shadowColor  = btCGColor(  0,   0,   0, 100 / 255.0)
  let whiteColor   = btCGColor(255, 255, 255, 1.0)
  let cyanColor    = btCGColor(  0, 255, 255, 150 / 255.0)

  ctx.setLineCap(.round)
  ctx.setLineJoin(.round)

  // Shadow lines (offset 1px)
  if pts.count >= 2 {
    ctx.setStrokeColor(shadowColor)
    ctx.setLineWidth(3)
    ctx.beginPath()
    ctx.move(to: CGPoint(x: CGFloat(pts[0].x) + 1, y: CGFloat(pts[0].y) + 1))
    for p in pts.dropFirst() {
      ctx.addLine(to: CGPoint(x: CGFloat(p.x) + 1, y: CGFloat(p.y) + 1))
    }
    ctx.strokePath()
  }

  // Gold trajectory lines
  if pts.count >= 2 {
    ctx.setStrokeColor(goldColor)
    ctx.setLineWidth(2.5)
    ctx.beginPath()
    ctx.move(to: CGPoint(x: CGFloat(pts[0].x), y: CGFloat(pts[0].y)))
    for p in pts.dropFirst() {
      ctx.addLine(to: CGPoint(x: CGFloat(p.x), y: CGFloat(p.y)))
    }
    ctx.strokePath()
  }

  // White dot at latest point
  let last = pts.last!
  let dotR: CGFloat = 5
  ctx.setFillColor(whiteColor)
  ctx.setStrokeColor(goldColor)
  ctx.setLineWidth(2)
  ctx.fillEllipse(in: CGRect(x: CGFloat(last.x) - dotR, y: CGFloat(last.y) - dotR,
                              width: dotR * 2, height: dotR * 2))
  ctx.strokeEllipse(in: CGRect(x: CGFloat(last.x) - dotR, y: CGFloat(last.y) - dotR,
                                width: dotR * 2, height: dotR * 2))

  // ROI dashed rectangle + crosshair
  guard roiSize > 0 else { return }
  let half = CGFloat(roiSize) / 2
  let rx = CGFloat(last.x) - half, ry = CGFloat(last.y) - half
  let roiRect = CGRect(x: rx, y: ry, width: CGFloat(roiSize), height: CGFloat(roiSize))

  ctx.setStrokeColor(cyanColor)
  ctx.setLineWidth(1.5)
  ctx.setLineDash(phase: 0, lengths: [6, 4])
  ctx.stroke(roiRect)
  ctx.setLineDash(phase: 0, lengths: [])

  // Crosshair
  ctx.setLineWidth(1)
  let cx = CGFloat(last.x), cy = CGFloat(last.y)
  ctx.move(to: CGPoint(x: rx, y: cy)); ctx.addLine(to: CGPoint(x: rx + CGFloat(roiSize), y: cy))
  ctx.move(to: CGPoint(x: cx, y: ry)); ctx.addLine(to: CGPoint(x: cx, y: ry + CGFloat(roiSize)))
  ctx.strokePath()
}

// MARK: - Local CGContext / color helpers

private func btMakeCGContext(base: UnsafeMutableRawPointer, w: Int, h: Int, bpr: Int) -> CGContext? {
  CGContext(
    data: base, width: w, height: h, bitsPerComponent: 8, bytesPerRow: bpr,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
  )
}

private func btCGColor(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat) -> CGColor {
  CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [r / 255, g / 255, b / 255, a])!
}
