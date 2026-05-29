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
            let videoPath = (args["inputPath"] ?? args["videoPath"]) as? String else {
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

    case "extractBlobsYolo":
      guard let args      = call.arguments as? [String: Any],
            let videoPath = args["inputPath"] as? String else {
        result(FlutterMethodNotImplemented); return
      }
      let hitSec = (args["hitSec"] as? NSNumber)?.doubleValue
      BallYoloDetector.shared.tryLoad()
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          let out: [String: Any]
          if BallYoloDetector.shared.isLoaded {
            out = try btExtractBlobsYolo(videoPath: videoPath, hitSec: hitSec)
          } else {
            // YOLO 未能載入時回退到傳統 blob 偵測
            print("[BallTrajectory] ⚠️ YOLO 未載入，回退到 blob 偵測")
            out = try btExtractBlobs(videoPath: videoPath, config: BlobConfig())
          }
          DispatchQueue.main.async { result(out) }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(code: "extract_failed", message: error.localizedDescription, details: nil))
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

  // ── 降採樣 2x：處理解析度降為 1/4，速度提升 ~4x ─────────────
  let procW    = max(1, displayW / 2)
  let procH    = max(1, displayH / 2)
  let pixCount = procW * procH

  // 面積門檻對應縮放（半解析度下面積縮 4 倍）
  var scaledCfg = config
  scaledCfg.areaLo = max(1, config.areaLo / 4)
  scaledCfg.areaHi = max(2, config.areaHi / 4)

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
        sample: sample, config: scaledCfg,
        pixCount: pixCount, procW: procW, procH: procH,
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

  // 回傳原始 displayW/H 供 Dart 端座標系對齊
  return ["fps": fps, "width": displayW, "height": displayH, "frames": frames]
}

// MARK: - YOLO blob extraction

private func btExtractBlobsYolo(videoPath: String, hitSec: Double? = nil) throws -> [String: Any] {
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

  // ── ROI 追蹤常數（對應 Android BallYoloExtractor）────────────
  let ROI_RATIO_X:              Float = 0.6519
  let ROI_RATIO_Y:              Float = 0.78
  let MAX_MISS_FRAMES                 = 5
  let MAX_ROI_SHIFT_PRE:        Float = 200
  let MAX_ROI_SHIFT_POST:       Float = 300
  let CONF_PRE_IMPACT:          Float = 0.25
  let CONF_POST_IMPACT:         Float = 0.05
  let POST_IMPACT_CHASE_DY:     Float = 150
  let POST_IMPACT_MAX_FRAMES          = 20

  // ── ROI 追蹤狀態 ──────────────────────────────────────────────
  var roiCx:           Float = Float(displayW) * ROI_RATIO_X
  var roiCy:           Float = Float(displayH) * ROI_RATIO_Y
  var missCount              = 0
  var lastGoodCx:      Float = -1
  var lastGoodCy:      Float = -1
  var postImpactMisses       = 0
  let hitFrame               = hitSec.map { Int($0 * fps) } ?? -1

  var frames: [[String: Any]] = []
  var frameIdx: Int = 0

  while reader.status == .reading {
    guard let sample: CMSampleBuffer = readerOut.copyNextSampleBuffer() else { break }

    // 在 autoreleasepool 內取得偵測結果，ROI 更新在外部進行
    var ptsUs:      Int64 = 0
    var detections: [BallYoloDetector.Detection] = []
    var frameOk = false

    autoreleasepool {
      guard let pixBuf = CMSampleBufferGetImageBuffer(sample) else { return }
      let pts = CMSampleBufferGetPresentationTimeStamp(sample)
      ptsUs = Int64(CMTimeGetSeconds(pts) * 1_000_000)

      CVPixelBufferLockBaseAddress(pixBuf, .readOnly)
      defer { CVPixelBufferUnlockBaseAddress(pixBuf, .readOnly) }
      guard let base = CVPixelBufferGetBaseAddress(pixBuf) else { return }

      let bpr  = CVPixelBufferGetBytesPerRow(pixBuf)
      let rgba = base.assumingMemoryBound(to: UInt8.self)

      let isPostImpact = hitFrame >= 0 && frameIdx >= hitFrame
      let confThresh   = isPostImpact ? CONF_POST_IMPACT : CONF_PRE_IMPACT

      detections = BallYoloDetector.shared.detect(
        bgraBase: rgba, bytesPerRow: bpr,
        frameW: displayW, frameH: displayH,
        roiCenterX: Int(roiCx), roiCenterY: Int(roiCy),
        confThreshold: confThresh)
      frameOk = true
    }

    guard frameOk else { continue }

    // ── 更新 ROI 追蹤狀態 ────────────────────────────────────
    let isPostImpact = hitFrame >= 0 && frameIdx >= hitFrame
    let maxShift: Float = isPostImpact ? MAX_ROI_SHIFT_POST : MAX_ROI_SHIFT_PRE

    let nearby = detections.filter { d in
      let dx = Float(d.cx) - roiCx; let dy = Float(d.cy) - roiCy
      return (dx * dx + dy * dy).squareRoot() <= maxShift
    }

    if let best = nearby.max(by: { $0.conf < $1.conf }) {
      roiCx = Float(best.cx); roiCy = Float(best.cy)
      lastGoodCx = roiCx; lastGoodCy = roiCy
      missCount = 0; postImpactMisses = 0
    } else {
      missCount += 1
      // _handleMiss 邏輯
      if isPostImpact {
        postImpactMisses += 1
        if postImpactMisses <= POST_IMPACT_MAX_FRAMES {
          roiCy -= POST_IMPACT_CHASE_DY  // 每幀向上追蹤飛球
          let halfTile = Float(BallYoloDetector.inputSize) / 2
          roiCx = max(halfTile, min(roiCx, Float(displayW) - halfTile))
          roiCy = max(halfTile, roiCy)
        }
      } else {
        if missCount >= MAX_MISS_FRAMES {
          roiCx = lastGoodCx >= 0 ? lastGoodCx : Float(displayW) * ROI_RATIO_X
          roiCy = lastGoodCy >= 0 ? lastGoodCy : Float(displayH) * ROI_RATIO_Y
          missCount = 0
        }
      }
    }

    // ── 組建 entry ────────────────────────────────────────────
    let blobs: [[String: Any]] = detections.map { d in
      // YOLO bbox 面積 ÷ 16 正規化為 blob-comparable area（對應 Android）
      let area = max(6, min(150, d.bboxW * d.bboxH / 16))
      return ["cx": d.cx, "cy": d.cy, "area": area, "circ": 1.0,
              "diffMean": Double(d.conf) * 50.0]
    }
    frames.append(["ptsUs": ptsUs, "blobs": blobs])
    frameIdx += 1

    if frameIdx % 10 == 0 {
      let prog: Double = min(0.95, Double(frameIdx) / Double(totalFrames))
      AnalysisProgressSink.shared.send(
        op: "extractBlobs", progress: prog,
        label: "YOLO偵測中 \(Int(prog * 100))%", current: frameIdx, total: totalFrames)
    }
  }

  AnalysisProgressSink.shared.send(
    op: "extractBlobs", progress: 1.0, label: "YOLO偵測完成",
    current: frameIdx, total: frameIdx)

  return ["fps": fps, "width": displayW, "height": displayH, "frames": frames]
}

// MARK: - Per-frame processing

private struct BtFrameResult {
  let entry: [String: Any]
  let currY: [UInt8]
}

private func btProcessFrame(
  sample:   CMSampleBuffer,
  config:   BlobConfig,
  pixCount: Int,       // = procW * procH（降採樣後）
  procW:    Int,       // = displayW / 2
  procH:    Int,       // = displayH / 2
  prevY:    [UInt8]?
) -> BtFrameResult? {
  guard let pixBuf: CVPixelBuffer = CMSampleBufferGetImageBuffer(sample) else { return nil }
  let pts:   CMTime  = CMSampleBufferGetPresentationTimeStamp(sample)
  let ptsUs: Int64   = Int64(CMTimeGetSeconds(pts) * 1_000_000)

  CVPixelBufferLockBaseAddress(pixBuf, .readOnly)
  let base = CVPixelBufferGetBaseAddress(pixBuf)!
  let bpr: Int = CVPixelBufferGetBytesPerRow(pixBuf)
  let rgba = base.assumingMemoryBound(to: UInt8.self)

  // ── Luma 轉換（降採樣 2x：每隔一個像素取樣）──────────────────
  // 快速 luma：(77R + 150G + 29B) >> 8 ≈ 0.301R + 0.586G + 0.113B
  // 比 /1000 快（位移代替除法），誤差 < 0.5
  var currY = [UInt8](repeating: 0, count: pixCount)
  for j in 0..<procH {
    let srcJ   = j &* 2
    let rowOff = srcJ &* bpr
    let yOff   = j &* procW
    for i in 0..<procW {
      let o = rowOff &+ (i &* 2) &* 4
      let b = Int(rgba[o])
      let g = Int(rgba[o &+ 1])
      let r = Int(rgba[o &+ 2])
      currY[yOff &+ i] = UInt8((77 &* r &+ 150 &* g &+ 29 &* b) >> 8)
    }
  }
  CVPixelBufferUnlockBaseAddress(pixBuf, .readOnly)

  var frameBlobs: [[String: Any]] = []
  if let prev: [UInt8] = prevY {
    // ── Frame diff：UInt8 直接運算，省掉 Int 轉換 ─────────────
    var rawDiff = [UInt8](repeating: 0, count: pixCount)
    var binMask = [UInt8](repeating: 0, count: pixCount)
    let thresh  = UInt8(clamping: config.diffThresh)
    for i in 0..<pixCount {
      let a = currY[i], b = prev[i]
      let d = a > b ? a &- b : b &- a   // abs diff，無 overflow
      rawDiff[i] = d
      binMask[i] = d >= thresh ? 1 : 0
    }

    // ── 形態學開運算（分離式 1D：H→V × 2，O(2k) vs 原本 O(k²)）
    let opened: [UInt8] = btMorphOpen(mask: binMask, w: procW, h: procH, k: config.morphK)

    // ── BFS blob 偵測 ─────────────────────────────────────────
    let blobs: [BlobResult] = btBfsBlobs(
      mask: opened, rawDiff: rawDiff, w: procW, h: procH,
      areaLo: config.areaLo, areaHi: config.areaHi, circMin: config.circMin)

    for b in blobs {
      // 座標還原到 display-space（×2）
      let blobEntry: [String: Any] = [
        "cx": b.cx * 2, "cy": b.cy * 2,
        "area": b.area * 4,              // 面積縮放還原
        "circ": b.circ, "diffMean": b.diffMean,
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

// 分離式 Erode：先水平再垂直，O(2k) per pixel 取代原本 O(k²)
// 對矩形結構元素（k×k 全 1）結果完全等價
private func btMorphErode(mask: [UInt8], w: Int, h: Int, k: Int) -> [UInt8] {
  guard k > 1 else { return mask }
  let half = k / 2

  // Pass 1：水平 erosion
  var temp = [UInt8](repeating: 0, count: w * h)
  for j in 0..<h {
    let base = j * w
    for i in 0..<w {
      let lo = i >= half ? i - half : 0
      let hi = i + half < w ? i + half : w - 1
      var keep: UInt8 = 1
      var di = lo
      while di <= hi {
        if mask[base + di] == 0 { keep = 0; break }
        di &+= 1
      }
      temp[base + i] = keep
    }
  }

  // Pass 2：垂直 erosion
  var out = [UInt8](repeating: 0, count: w * h)
  for j in 0..<h {
    let lo = j >= half ? j - half : 0
    let hi = j + half < h ? j + half : h - 1
    for i in 0..<w {
      var keep: UInt8 = 1
      var dj = lo
      while dj <= hi {
        if temp[dj * w + i] == 0 { keep = 0; break }
        dj &+= 1
      }
      out[j * w + i] = keep
    }
  }
  return out
}

// 分離式 Dilate：先水平再垂直
private func btMorphDilate(mask: [UInt8], w: Int, h: Int, k: Int) -> [UInt8] {
  guard k > 1 else { return mask }
  let half = k / 2

  // Pass 1：水平 dilation
  var temp = [UInt8](repeating: 0, count: w * h)
  for j in 0..<h {
    let base = j * w
    for i in 0..<w {
      let lo = i >= half ? i - half : 0
      let hi = i + half < w ? i + half : w - 1
      var any: UInt8 = 0
      var di = lo
      while di <= hi {
        if mask[base + di] != 0 { any = 1; break }
        di &+= 1
      }
      temp[base + i] = any
    }
  }

  // Pass 2：垂直 dilation
  var out = [UInt8](repeating: 0, count: w * h)
  for j in 0..<h {
    let lo = j >= half ? j - half : 0
    let hi = j + half < h ? j + half : h - 1
    for i in 0..<w {
      var any: UInt8 = 0
      var dj = lo
      while dj <= hi {
        if temp[dj * w + i] != 0 { any = 1; break }
        dj &+= 1
      }
      out[j * w + i] = any
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
