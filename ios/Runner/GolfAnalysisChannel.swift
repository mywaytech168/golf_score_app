import AVFoundation
import Flutter
import MediaPipeTasksVision

// MARK: - Registration
//
// com.example.golf_score_app/golf_analysis
// 對齊 Android MainActivity 的 GOLF_ANALYSIS_CHANNEL：
//   - findAudioPeaks         多擊球音訊峰值偵測（V2 長影片路徑）
//   - analyzeVideo           V2 純音訊分析（單一最強峰值）
//   - analyzeVideoAtCandidate V3 局部 MediaPipe 骨架分析（±windowMs 窗口）

private let gaQueue = DispatchQueue(label: "golf.analysis", qos: .userInitiated)

func registerGolfAnalysisChannel(messenger: FlutterBinaryMessenger) {
  FlutterMethodChannel(
    name: "com.example.golf_score_app/golf_analysis",
    binaryMessenger: messenger
  ).setMethodCallHandler { call, result in
    let args = call.arguments as? [String: Any] ?? [:]

    switch call.method {
    case "findAudioPeaks":
      guard let videoPath = args["videoPath"] as? String, !videoPath.isEmpty else {
        result(FlutterError(code: "invalid_args", message: "缺少 videoPath", details: nil))
        return
      }
      let startMs  = (args["searchStartMs"] as? NSNumber)?.int64Value ?? 500
      let minGapMs = (args["minGapMs"]      as? NSNumber)?.int64Value ?? 2000
      let topN     = (args["topN"]          as? NSNumber)?.intValue   ?? 20
      gaQueue.async {
        let peaks = GolfAudioImpactDetector.findMultiplePeaks(
          videoPath: videoPath, searchStartMs: startMs, minGapMs: minGapMs, topN: topN
        ) { prog, label in
          AnalysisProgressSink.shared.send(op: "findAudioPeaks", progress: prog, label: label)
        }
        DispatchQueue.main.async { result(peaks.map { NSNumber(value: $0) }) }
      }

    case "analyzeVideo":
      guard let videoPath = args["videoPath"] as? String, !videoPath.isEmpty else {
        result(FlutterError(code: "invalid_args", message: "缺少 videoPath", details: nil))
        return
      }
      let startMs = (args["searchStartMs"] as? NSNumber)?.int64Value ?? 500
      let endMs   = (args["searchEndMs"]   as? NSNumber)?.int64Value ?? -1
      gaQueue.async {
        let map = gaRunAudioPipeline(videoPath: videoPath, searchStartMs: startMs, searchEndMs: endMs)
        DispatchQueue.main.async { result(map) }
      }

    case "analyzeVideoAtCandidate":
      guard let videoPath = args["videoPath"] as? String, !videoPath.isEmpty else {
        result(FlutterError(code: "invalid_args", message: "缺少 videoPath", details: nil))
        return
      }
      let candidateMs = (args["candidateMs"] as? NSNumber)?.int64Value ?? 0
      let windowMs    = (args["windowMs"]    as? NSNumber)?.int64Value ?? 3000
      let maxWidth    = (args["maxWidth"]    as? NSNumber)?.intValue   ?? 720
      gaQueue.async {
        do {
          if let map = try gaRunSkeletonOnCandidate(
            videoPath: videoPath, candidateMs: candidateMs,
            windowMs: windowMs, maxWidth: maxWidth
          ) {
            DispatchQueue.main.async { result(map) }
          } else {
            DispatchQueue.main.async {
              result(FlutterError(code: "not_found", message: "骨架分析未找到擊球", details: nil))
            }
          }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(code: "analysis_failed", message: error.localizedDescription, details: nil))
          }
        }
      }

    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

// MARK: - V2 純音訊管線（對齊 Android runGolfAnalysisPipeline）

private func gaRunAudioPipeline(videoPath: String, searchStartMs: Int64, searchEndMs: Int64) -> [String: Any] {
  AnalysisProgressSink.shared.send(op: "golfAnalysis", progress: 0.05, label: "音訊掃描中…")
  let audioPeakMs = GolfAudioImpactDetector.findImpactTime(
    videoPath: videoPath, searchStartMs: searchStartMs, searchEndMs: searchEndMs)
  let hasAudio = audioPeakMs >= 0

  // 無音訊時取影片中段作為 impactTimeMs
  let impactTimeMs: Int64
  if hasAudio {
    impactTimeMs = audioPeakMs
  } else {
    let asset = AVURLAsset(url: URL(fileURLWithPath: videoPath))
    let durMs = Int64(CMTimeGetSeconds(asset.duration) * 1000)
    impactTimeMs = (durMs > 0 ? durMs : 5000) / 2
  }

  AnalysisProgressSink.shared.send(op: "golfAnalysis", progress: 1.0, label: "音訊分析完成")
  return [
    "impactTimeMs": NSNumber(value: impactTimeMs),
    "audioPeakMs":  NSNumber(value: audioPeakMs),
    "hasAudio":     hasAudio,
    "skeletonJson": "[]",
    "frameCount":   0,
    "videoPath":    videoPath,
  ]
}

// MARK: - V3 局部骨架分析（對齊 Android runGolfSkeletonOnCandidate）
//
// AVAssetReader 限定 timeRange 順序解碼 → MediaPipe PoseLandmarker (video mode)
// 演算法：FAST（右腕速度峰值）→ FAST±0.5s 內 Y_LOW（右腕最低點）= impact
// 過濾：幀數 ≥8、FAST 速度、FAST 偏離音訊峰值、TOP→impact Y 跨幅

private func gaRunSkeletonOnCandidate(
  videoPath: String, candidateMs: Int64, windowMs: Int64, maxWidth: Int
) throws -> [String: Any]? {
  let startMs = max(0, candidateMs - windowMs)
  let endMs   = candidateMs + windowMs
  AnalysisProgressSink.shared.send(op: "golfAnalysis", progress: 0.02, label: "V3 骨架準備中…")

  let asset = AVURLAsset(url: URL(fileURLWithPath: videoPath))
  guard let track = asset.tracks(withMediaType: .video).first else {
    NSLog("[GolfAnalysis.V3] 無視訊 track")
    return nil
  }

  // ── 顯示尺寸（套用 preferredTransform 後）與縮放 ─────────────────────
  let natural = track.naturalSize
  let t = track.preferredTransform
  let displayRect = CGRect(origin: .zero, size: natural).applying(t)
  let displayW = abs(displayRect.width)
  let displayH = abs(displayRect.height)
  guard displayW > 0, displayH > 0 else { return nil }

  let scale = (maxWidth > 0 && displayW > CGFloat(maxWidth))
    ? CGFloat(maxWidth) / displayW : 1.0
  // 偶數尺寸（BGRA 無硬性要求，但與 Android targetW 對齊行為一致）
  let targetW = max(2, Int(displayW * scale) & ~1)
  let targetH = max(2, Int(displayH * scale) & ~1)

  // ── VideoComposition：旋轉修正 + 縮放（解碼輸出即為直式小圖）────────
  var xform = t.concatenating(
    CGAffineTransform(translationX: -displayRect.minX, y: -displayRect.minY))
  xform = xform.concatenating(CGAffineTransform(scaleX: scale, y: scale))

  let instruction = AVMutableVideoCompositionInstruction()
  instruction.timeRange = CMTimeRange(start: .zero, duration: asset.duration)
  let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
  layerInstruction.setTransform(xform, at: .zero)
  instruction.layerInstructions = [layerInstruction]

  let composition = AVMutableVideoComposition()
  composition.instructions = [instruction]
  composition.renderSize = CGSize(width: targetW, height: targetH)
  let fps = track.nominalFrameRate > 1 ? track.nominalFrameRate : 30
  composition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps.rounded()))

  // ── AVAssetReader 限定 [startMs, endMs] ──────────────────────────────
  let reader = try AVAssetReader(asset: asset)
  reader.timeRange = CMTimeRange(
    start: CMTime(value: startMs, timescale: 1000),
    end:   CMTime(value: endMs,   timescale: 1000))

  let output = AVAssetReaderVideoCompositionOutput(
    videoTracks: [track],
    videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
  output.videoComposition = composition
  output.alwaysCopiesSampleData = false
  reader.add(output)

  // ── MediaPipe PoseLandmarker（video mode）────────────────────────────
  guard let modelPath = gaFindPoseModelPath() else {
    NSLog("[GolfAnalysis.V3] pose_landmarker_lite.task not found")
    return nil
  }
  let opts = PoseLandmarkerOptions()
  opts.baseOptions.modelAssetPath = modelPath
  opts.runningMode = .video
  opts.numPoses = 1
  opts.minPoseDetectionConfidence = 0.5
  opts.minPosePresenceConfidence = 0.5
  opts.minTrackingConfidence = 0.5
  let landmarker = try PoseLandmarker(options: opts)

  guard reader.startReading() else {
    throw reader.error ?? NSError(domain: "GolfAnalysis", code: -1,
      userInfo: [NSLocalizedDescriptionKey: "無法啟動影片讀取"])
  }

  var rightTimesMs: [Int64] = []     // 右腕有效幀時間
  var rightYs: [Float] = []          // 右腕 Y（display px）
  var rightXs: [Float] = []          // 右腕 X（display px）
  var skeletonFrames: [[String: Any]] = []
  var frameCount = 0
  var analyzedFrames = 0
  var lastTsMs: Int64 = -1
  let estFrames = max(1, Int((endMs - startMs) * Int64(fps.rounded()) / 1000))

  while reader.status == .reading {
    var shouldBreak = false
    autoreleasepool {
      guard let sample = output.copyNextSampleBuffer() else { shouldBreak = true; return }
      defer { CMSampleBufferInvalidate(sample) }
      guard let pixelBuffer = CMSampleBufferGetImageBuffer(sample) else { return }

      let pts = CMSampleBufferGetPresentationTimeStamp(sample)
      var ptsMs = Int64(CMTimeGetSeconds(pts) * 1000)
      // video mode 要求 timestamp 嚴格遞增
      if ptsMs <= lastTsMs { ptsMs = lastTsMs + 1 }
      lastTsMs = ptsMs

      guard let mpImage = try? MPImage(pixelBuffer: pixelBuffer),
            let detection = try? landmarker.detect(
              videoFrame: mpImage, timestampInMilliseconds: Int(ptsMs))
      else { frameCount += 1; return }

      if let landmarks = detection.landmarks.first, !landmarks.isEmpty {
        // 右腕 = MediaPipe index 16；歸一化座標相對於已旋轉+縮放的輸出
        if landmarks.count > 16 {
          let rw = landmarks[16]
          let vis = rw.visibility?.floatValue ?? 0
          if vis >= 0.3 {
            rightTimesMs.append(ptsMs)
            rightXs.append(Float(rw.x) * Float(displayW))
            rightYs.append(Float(rw.y) * Float(displayH))
          }
        }
        // 完整骨架（與 Android skeletonJson 結構一致）
        var lmList: [[String: Any]] = []
        lmList.reserveCapacity(landmarks.count)
        for (idx, lm) in landmarks.enumerated() {
          lmList.append([
            "type":  idx,
            "x":     lm.x * Float(displayW),
            "y":     lm.y * Float(displayH),
            "z":     lm.z,
            "vis":   lm.visibility?.floatValue ?? 0,
            "xNorm": lm.x,
            "yNorm": lm.y,
          ])
        }
        skeletonFrames.append(["timeMs": NSNumber(value: ptsMs), "landmarks": lmList])
        analyzedFrames += 1
      }

      frameCount += 1
      let prog = 0.05 + min(0.95, Double(frameCount) / Double(estFrames)) * 0.90
      AnalysisProgressSink.shared.send(
        op: "golfAnalysis", progress: prog, label: "V3 骨架分析 \(Int(prog * 100))%")
    }
    if shouldBreak { break }
  }

  if reader.status == .failed {
    throw reader.error ?? NSError(domain: "GolfAnalysis", code: -2,
      userInfo: [NSLocalizedDescriptionKey: "影片解碼失敗"])
  }

  // ── 過濾 1：右腕偵測幀數不足 ─────────────────────────────────────────
  if rightTimesMs.count < 8 {
    AnalysisProgressSink.shared.send(
      op: "golfAnalysis", progress: 1.0, label: "V3 過濾：右腕偵測不足 (\(rightTimesMs.count) 幀)")
    NSLog("[GolfAnalysis.V3] 排除 candidate=%lldms：幀數不足 (%d)", candidateMs, rightTimesMs.count)
    return nil
  }

  // ── 幀間速度 + 3-frame 平滑 ─────────────────────────────────────────
  var speed = [Float](repeating: 0, count: rightTimesMs.count)
  for i in 1..<rightTimesMs.count {
    let dx = rightXs[i] - rightXs[i - 1]
    let dy = rightYs[i] - rightYs[i - 1]
    speed[i] = (dx * dx + dy * dy).squareRoot()
  }
  var smoothSpeed = [Float](repeating: 0, count: speed.count)
  for i in speed.indices {
    let l = max(0, i - 1), r = min(speed.count - 1, i + 1)
    smoothSpeed[i] = (speed[l] + speed[i] + speed[r]) / 3
  }

  // ── FAST（速度峰值）─────────────────────────────────────────────────
  let fastIdx = smoothSpeed.indices.max(by: { smoothSpeed[$0] < smoothSpeed[$1] }) ?? 0
  let fastMs = rightTimesMs[fastIdx]
  let fastSpeed = smoothSpeed[fastIdx]

  // 過濾 2：FAST 速度太低
  let minFastSpeed = max(Float(displayH) * 0.003, 4)
  if fastSpeed < minFastSpeed {
    AnalysisProgressSink.shared.send(
      op: "golfAnalysis", progress: 1.0,
      label: "V3 過濾：揮桿速度不足 (\(Int(fastSpeed))px/frame < \(Int(minFastSpeed)))")
    NSLog("[GolfAnalysis.V3] 排除 candidate=%lldms：FAST 速度不足", candidateMs)
    return nil
  }

  // 過濾 3：FAST 偏離音訊峰值太遠
  let maxDrift = windowMs * 3 / 4
  if abs(fastMs - candidateMs) > maxDrift {
    AnalysisProgressSink.shared.send(
      op: "golfAnalysis", progress: 1.0,
      label: "V3 過濾：FAST 偏離音訊峰值過遠 (\(abs(fastMs - candidateMs))ms)")
    NSLog("[GolfAnalysis.V3] 排除 candidate=%lldms：FAST 偏移過大", candidateMs)
    return nil
  }

  // ── FAST ±0.5s 內找 Y_LOW（右腕最低點 = impact）──────────────────────
  let yLowWindowMs: Int64 = 500
  var impactMs = fastMs
  var impactY = rightYs[fastIdx]
  var bestY = -Float.greatestFiniteMagnitude
  for i in rightTimesMs.indices {
    let tMs = rightTimesMs[i]
    if tMs >= fastMs - yLowWindowMs, tMs <= fastMs + yLowWindowMs, rightYs[i] > bestY {
      bestY = rightYs[i]
      impactMs = tMs
      impactY = rightYs[i]
    }
  }

  // 過濾 4：TOP→impact Y 跨幅不足
  var topY = Float.greatestFiniteMagnitude
  for i in rightTimesMs.indices where rightTimesMs[i] < impactMs {
    topY = min(topY, rightYs[i])
  }
  if topY == .greatestFiniteMagnitude { topY = rightYs.min() ?? impactY }
  let ySpan = impactY - topY
  let minYSpan = max(Float(displayH) * 0.04, 20)
  if ySpan < minYSpan {
    AnalysisProgressSink.shared.send(
      op: "golfAnalysis", progress: 1.0,
      label: "V3 過濾：TOP→impact 幅度不足 (\(Int(ySpan))px < \(Int(minYSpan))px)")
    NSLog("[GolfAnalysis.V3] 排除 candidate=%lldms：Y 跨幅不足", candidateMs)
    return nil
  }

  AnalysisProgressSink.shared.send(
    op: "golfAnalysis", progress: 1.0, label: "V3 分析完成 (\(rightTimesMs.count) 幀有效)")
  NSLog("[GolfAnalysis.V3] impactMs=%lld FAST=%lldms candidate=%lldms frames=%d",
        impactMs, fastMs, candidateMs, analyzedFrames)

  let jsonData = try JSONSerialization.data(withJSONObject: skeletonFrames)
  let skeletonJson = String(data: jsonData, encoding: .utf8) ?? "[]"

  return [
    "impactTimeMs": NSNumber(value: impactMs),
    "audioPeakMs":  NSNumber(value: candidateMs),
    "hasAudio":     true,
    "skeletonJson": skeletonJson,
    "frameCount":   analyzedFrames,
    "videoPath":    videoPath,
  ]
}

// ── 模型路徑（同 MediaPipeCameraChannel.findModelPath 的查找順序）──────

private func gaFindPoseModelPath() -> String? {
  if let appFramework = Bundle.main.bundleURL
      .appendingPathComponent("Frameworks/App.framework")
      .absoluteString.removingPercentEncoding.flatMap({ URL(string: "file://" + $0) }),
     let b = Bundle(url: appFramework),
     let p = b.path(forResource: "flutter_assets/assets/models/pose_landmarker_lite",
                    ofType: "task") {
    return p
  }
  if let p = Bundle.main.path(forResource: "pose_landmarker_lite", ofType: "task") {
    return p
  }
  if let p = Bundle.main.path(forResource: "pose_landmarker_lite", ofType: "task",
                              inDirectory: "flutter_assets/assets/models") {
    return p
  }
  return nil
}

// MARK: - 音訊峰值偵測（對齊 Android AudioImpactDetector）
//
// 串流解碼 PCM16 → 每 10ms 窗口 RMS（不存原始 PCM）
// 多峰值：自適應門檻 = 中位數 × 3，貪婪選峰 + minGap 抑制

enum GolfAudioImpactDetector {
  private static let windowMs: Int64 = 10

  /// 單一最強峰值毫秒位置；無音訊軌回傳 -1
  static func findImpactTime(videoPath: String, searchStartMs: Int64, searchEndMs: Int64) -> Int64 {
    guard let rms = computeRms(videoPath: videoPath, onProgress: nil), !rms.isEmpty else { return -1 }
    let startIdx = min(rms.count, max(0, Int(searchStartMs / windowMs)))
    let endIdx = searchEndMs < 0 ? rms.count : min(rms.count, Int(searchEndMs / windowMs))
    guard startIdx < endIdx else { return -1 }

    var maxRms = 0.0
    var maxIdx = startIdx
    for i in startIdx..<endIdx where rms[i] > maxRms {
      maxRms = rms[i]; maxIdx = i
    }
    return Int64(maxIdx) * windowMs + windowMs / 2
  }

  /// 所有擊球峰值（升序）；無音訊軌回傳空陣列
  static func findMultiplePeaks(
    videoPath: String, searchStartMs: Int64, minGapMs: Int64, topN: Int,
    onProgress: ((Double, String) -> Void)?
  ) -> [Int64] {
    onProgress?(0.05, "音訊解碼中…")
    guard let rms = computeRms(videoPath: videoPath, onProgress: { prog in
      onProgress?(0.05 + prog * 0.75, "掃描聲波 \(Int(prog * 100))%…")
    }), !rms.isEmpty else { return [] }

    onProgress?(0.82, "分析峰值…")
    let startIdx = min(rms.count, max(0, Int(searchStartMs / windowMs)))
    guard startIdx < rms.count else { return [] }
    let subRms = Array(rms[startIdx...])

    // 自適應門檻：中位數 × 3
    let median = subRms.sorted()[subRms.count / 2]
    let threshold = median * 3.0

    let minGapWindows = max(1, Int(minGapMs / windowMs))
    let candidates = subRms.indices
      .filter { subRms[$0] >= threshold }
      .map { (idx: startIdx + $0, rms: subRms[$0]) }
      .sorted { $0.rms > $1.rms }

    var suppressed = [Bool](repeating: false, count: rms.count)
    var peaks: [Int64] = []
    for c in candidates {
      if peaks.count >= topN { break }
      if c.idx >= suppressed.count || suppressed[c.idx] { continue }
      peaks.append(Int64(c.idx) * windowMs + windowMs / 2)
      for i in max(0, c.idx - minGapWindows)...min(suppressed.count - 1, c.idx + minGapWindows) {
        suppressed[i] = true
      }
    }

    let sortedPeaks = peaks.sorted()
    onProgress?(1.0, "偵測完成，共 \(sortedPeaks.count) 個擊球")
    return sortedPeaks
  }

  /// 串流解碼音訊軌為 PCM16，計算每 10ms 窗口 RMS。無音訊軌回傳 nil。
  private static func computeRms(videoPath: String, onProgress: ((Double) -> Void)?) -> [Double]? {
    let asset = AVURLAsset(url: URL(fileURLWithPath: videoPath))
    guard let track = asset.tracks(withMediaType: .audio).first else { return nil }

    var sampleRate = 44100
    var channels = 1
    if let desc = track.formatDescriptions.first,
       CFGetTypeID(desc as CFTypeRef) == CMFormatDescriptionGetTypeID() {
      let formatDesc = desc as! CMFormatDescription
      if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)?.pointee {
        sampleRate = Int(asbd.mSampleRate)
        channels = Int(asbd.mChannelsPerFrame)
      }
    }

    let outputSettings: [String: Any] = [
      AVFormatIDKey:               kAudioFormatLinearPCM,
      AVSampleRateKey:             sampleRate,
      AVNumberOfChannelsKey:       channels,
      AVLinearPCMIsFloatKey:       false,
      AVLinearPCMBitDepthKey:      16,
      AVLinearPCMIsBigEndianKey:   false,
      AVLinearPCMIsNonInterleaved: false,
    ]

    guard let reader = try? AVAssetReader(asset: asset) else { return nil }
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
    output.alwaysCopiesSampleData = false
    reader.add(output)
    guard reader.startReading() else { return nil }

    let windowSamples = sampleRate * Int(windowMs) / 1000 * channels
    guard windowSamples > 0 else { return nil }

    let durationSec = CMTimeGetSeconds(asset.duration)
    var rmsList: [Double] = []
    if durationSec > 0 {
      rmsList.reserveCapacity(Int(durationSec * 1000 / Double(windowMs)) + 16)
    }

    var winSumSq = 0.0
    var winSampleCount = 0
    var lastProgressPct = -1

    while reader.status == .reading {
      var shouldBreak = false
      autoreleasepool {
        guard let sample = output.copyNextSampleBuffer() else { shouldBreak = true; return }
        defer { CMSampleBufferInvalidate(sample) }
        guard let block = CMSampleBufferGetDataBuffer(sample) else { return }

        let length = CMBlockBufferGetDataLength(block)
        guard length >= 2 else { return }
        var data = Data(count: length)
        data.withUnsafeMutableBytes { ptr in
          if let base = ptr.baseAddress {
            CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: base)
          }
        }

        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
          let samples = raw.bindMemory(to: Int16.self)
          for s in samples {
            let v = Double(Int16(littleEndian: s)) / Double(Int16.max)
            winSumSq += v * v
            winSampleCount += 1
            if winSampleCount >= windowSamples {
              rmsList.append((winSumSq / Double(windowSamples)).squareRoot())
              winSumSq = 0; winSampleCount = 0
            }
          }
        }

        if let onProgress = onProgress, durationSec > 0 {
          let ptsSec = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample))
          let pct = min(20, max(0, Int(ptsSec / durationSec * 20)))
          if pct != lastProgressPct {
            lastProgressPct = pct
            onProgress(Double(pct) / 20.0)
          }
        }
      }
      if shouldBreak { break }
    }

    if winSampleCount > 0 {
      rmsList.append((winSumSq / Double(winSampleCount)).squareRoot())
    }
    return rmsList.isEmpty ? nil : rmsList
  }
}
