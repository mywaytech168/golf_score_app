import AVFoundation
import Flutter
import Vision

// Vision framework 關節名稱 → ML Kit landmark index (0-32) 映射表
// ML Kit 共 33 個關鍵點；Vision framework 有 19 個，未覆蓋的索引寫 NaN
private let visionToMLKitIndex: [(VNHumanBodyPoseObservation.JointName, Int)] = [
  (.nose,          0),
  (.leftEye,       2),  (.rightEye,       5),
  (.leftEar,       7),  (.rightEar,        8),
  (.leftShoulder, 11),  (.rightShoulder,  12),
  (.leftElbow,    13),  (.rightElbow,     14),
  (.leftWrist,    15),  (.rightWrist,     16),
  (.leftHip,      23),  (.rightHip,       24),
  (.leftKnee,     25),  (.rightKnee,      26),
  (.leftAnkle,    27),  (.rightAnkle,     28),
]

func registerPoseAnalyzerChannel(messenger: FlutterBinaryMessenger) {
  let channel = FlutterMethodChannel(
    name: "com.example.golf_score_app/pose_analyzer",
    binaryMessenger: messenger
  )
  channel.setMethodCallHandler { call, result in
    guard call.method == "analyzePoseVideo" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard
      let args = call.arguments as? [String: Any],
      let videoPath     = args["videoPath"]     as? String,
      let outputCsvPath = args["outputCsvPath"] as? String
    else {
      result(FlutterError(code: "invalid_args", message: "缺少 videoPath 或 outputCsvPath", details: nil))
      return
    }
    let maxWidth  = (args["maxWidth"]  as? NSNumber)?.intValue ?? 720

    DispatchQueue.global(qos: .userInitiated).async {
      do {
        let csvPath = try analyzeVideoNatively(
          videoPath: videoPath,
          maxWidth: maxWidth,
          outputCsvPath: outputCsvPath
        )
        DispatchQueue.main.async {
          result(["csvPath": csvPath, "status": "completed"])
        }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(code: "analysis_failed", message: error.localizedDescription, details: nil))
        }
      }
    }
  }
}

// MARK: - Core analysis

// fallback fps：只在無法從影片元數據讀到 nominalFrameRate 時使用
private let kFallbackFps: Double = 30.0

private func analyzeVideoNatively(
  videoPath: String,
  maxWidth: Int,
  outputCsvPath: String
) throws -> String {
  let asset = AVURLAsset(url: URL(fileURLWithPath: videoPath))

  guard let videoTrack = asset.tracks(withMediaType: .video).first else {
    throw NSError(domain: "PoseAnalyzer", code: -1,
                  userInfo: [NSLocalizedDescriptionKey: "找不到視頻軌道"])
  }

  // --- 取得視頻參數 ---
  let naturalSize  = videoTrack.naturalSize
  let transform    = videoTrack.preferredTransform
  // 採樣率 = 影片實際 fps（nominalFrameRate）
  // 60fps 影片以 60fps 取骨架，30fps 影片以 30fps 取骨架，無需 Dart 側指定
  let actualFps    = Double(videoTrack.nominalFrameRate > 0 ? videoTrack.nominalFrameRate : Float(kFallbackFps))
  let durationSec  = CMTimeGetSeconds(asset.duration)

  // 套用 preferredTransform 計算 display 尺寸
  let displaySize = naturalSize.applying(transform)
  let displayW    = abs(displaySize.width)
  let displayH    = abs(displaySize.height)

  // 縮放係數（限制寬度為 maxWidth）
  let scale: CGFloat = (maxWidth > 0 && displayW > CGFloat(maxWidth))
    ? CGFloat(maxWidth) / displayW
    : 1.0
  let outW = Int(displayW * scale)
  let outH = Int(displayH * scale)

  // 決定傳給 Vision 的影像方向（對應 preferredTransform 的旋轉）
  let orientation = imageOrientationFrom(transform: transform)

  // --- 設定 AVAssetReader ---
  let reader = try AVAssetReader(asset: asset)
  let outputSettings: [String: Any] = [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
  ]
  let trackOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: outputSettings)
  trackOutput.alwaysCopiesSampleData = false
  reader.add(trackOutput)
  guard reader.startReading() else {
    throw reader.error ?? NSError(domain: "PoseAnalyzer", code: -2,
                                  userInfo: [NSLocalizedDescriptionKey: "無法啟動 AVAssetReader"])
  }

  // --- 準備 CSV 輸出 ---
  let csvURL = URL(fileURLWithPath: outputCsvPath)
  try FileManager.default.createDirectory(
    at: csvURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
  )

  // 使用 OutputStream 逐行寫入，避免巨大字串佔記憶體
  guard let stream = OutputStream(toFileAtPath: outputCsvPath, append: false) else {
    throw NSError(domain: "PoseAnalyzer", code: -3,
                  userInfo: [NSLocalizedDescriptionKey: "無法建立 CSV 輸出檔"])
  }
  stream.open()
  defer { stream.close() }

  // 標頭（與 PoseCsvWriter.header 完全一致）
  var header = "frame,time_sec,pose_update_id"
  for i in 0 ..< 33 {
    header += ",lm\(i)_x_norm,lm\(i)_y_norm,lm\(i)_z,lm\(i)_visibility,lm\(i)_x_px,lm\(i)_y_px"
  }
  header += "\n"
  streamWrite(stream, string: header)

  // --- 逐幀分析 ---
  let poseRequest      = VNDetectHumanBodyPoseRequest()
  let frameIntervalSec = 1.0 / actualFps
  let toleranceSec     = 0.001
  let expectedFrames   = max(1, Int(durationSec * actualFps))

  var nextSampleSec  = 0.0
  var frameCount     = 0
  var decodedFrames  = 0
  var poseUpdateId   = 0
  var lastPxMap: [Int: (CGFloat, CGFloat)] = [:]

  var shouldBreak = false
  while reader.status == .reading && !shouldBreak {
    autoreleasepool { () -> Void in
      guard let sampleBuffer = trackOutput.copyNextSampleBuffer() else {
        shouldBreak = true
        return
      }
      let pts    = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
      let ptsSec = CMTimeGetSeconds(pts)
      decodedFrames += 1

      guard ptsSec >= nextSampleSec - toleranceSec else { return }
      nextSampleSec = ptsSec + frameIntervalSec

      let timeSec = ptsSec

      // 取得 CVPixelBuffer
      guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
        streamWrite(stream, string: nanRow(frame: frameCount, timeSec: timeSec, poseUpdateId: poseUpdateId))
        frameCount += 1
        return
      }

      // 若需要縮放，先用 CIContext 縮小
      let workBuffer: CVPixelBuffer
      if scale < 0.99 {
        workBuffer = scalePixelBuffer(pixelBuffer, toWidth: outW, height: outH) ?? pixelBuffer
      } else {
        workBuffer = pixelBuffer
      }

      // Vision 推理
      let handler = VNImageRequestHandler(cvPixelBuffer: workBuffer, orientation: orientation, options: [:])
      try? handler.perform([poseRequest])
      let observation = poseRequest.results?.first

      // 取出 landmark map
      let lmMap = landmarkMap(from: observation, frameW: CGFloat(outW), frameH: CGFloat(outH))

      // 偵測 pose 是否更新
      if !lmMap.isEmpty {
        let changed = lmMap.contains { (idx, pt) in
          guard let last = lastPxMap[idx] else { return true }
          return abs(pt.0 - last.0) > 0.5 || abs(pt.1 - last.1) > 0.5
        }
        if changed {
          poseUpdateId += 1
          lastPxMap = lmMap.mapValues { ($0.0, $0.1) }
        }
      }

      // 寫 CSV 行
      var row = "\(frameCount),\(timeSec),\(poseUpdateId)"
      for i in 0 ..< 33 {
        if let pt = lmMap[i] {
          let (xPx, yPx, conf) = pt
          row += ",\(xPx / CGFloat(outW)),\(yPx / CGFloat(outH)),0.0,\(conf),\(xPx),\(yPx)"
        } else {
          row += ",NaN,NaN,NaN,0.0,NaN,NaN"
        }
      }
      row += "\n"
      streamWrite(stream, string: row)
      frameCount += 1

      // 每 10 幀推一次進度
      if decodedFrames % 10 == 0 {
        let prog = min(0.95, Double(decodedFrames) / Double(expectedFrames))
        AnalysisProgressSink.shared.send(
          op: "analyzePose",
          progress: prog,
          label: "骨架分析中 \(Int(prog * 100))%",
          current: decodedFrames,
          total: expectedFrames
        )
      }
    }
  }

  AnalysisProgressSink.shared.send(
    op: "analyzePose", progress: 1.0,
    label: "骨架分析完成", current: frameCount, total: frameCount
  )
  return outputCsvPath
}

// MARK: - Helpers

/// Vision normalized (bottom-left) → pixel (top-left) + confidence
private func landmarkMap(
  from obs: VNHumanBodyPoseObservation?,
  frameW: CGFloat, frameH: CGFloat
) -> [Int: (CGFloat, CGFloat, CGFloat)] {
  guard let obs = obs else { return [:] }
  var map: [Int: (CGFloat, CGFloat, CGFloat)] = [:]
  for (jointName, mlkitIdx) in visionToMLKitIndex {
    guard let pt = try? obs.recognizedPoint(jointName), pt.confidence > 0.1 else { continue }
    let xPx = pt.location.x * frameW
    let yPx = (1.0 - pt.location.y) * frameH  // flip Y: Vision bottom-left → ML Kit top-left
    map[mlkitIdx] = (xPx, yPx, CGFloat(pt.confidence))
  }
  return map
}

private func nanRow(frame: Int, timeSec: Double, poseUpdateId: Int) -> String {
  var row = "\(frame),\(timeSec),\(poseUpdateId)"
  for _ in 0 ..< 33 { row += ",NaN,NaN,NaN,0.0,NaN,NaN" }
  row += "\n"
  return row
}

private func streamWrite(_ stream: OutputStream, string: String) {
  guard let data = string.data(using: .utf8) else { return }
  _ = data.withUnsafeBytes { ptr in
    stream.write(ptr.bindMemory(to: UInt8.self).baseAddress!, maxLength: data.count)
  }
}

/// Convert AVAssetTrack.preferredTransform to CGImagePropertyOrientation for Vision.
private func imageOrientationFrom(transform t: CGAffineTransform) -> CGImagePropertyOrientation {
  // portrait iPhone: b==1 → raw frame is rotated 90° CW → Vision needs .right
  if t.b == 1.0  && t.c == -1.0 { return .right  }
  if t.b == -1.0 && t.c == 1.0  { return .left   }
  if t.a == -1.0 && t.d == -1.0 { return .down   }
  return .up
}

// Shared CIContext — created once, reused across all frames (GPU context is expensive to build)
private let sharedCIContext = CIContext(options: [.useSoftwareRenderer: false])

/// Downsample a CVPixelBuffer using CIContext.
private func scalePixelBuffer(_ src: CVPixelBuffer, toWidth w: Int, height h: Int) -> CVPixelBuffer? {
  let ciImage = CIImage(cvPixelBuffer: src)
  let scaleX  = CGFloat(w) / CGFloat(CVPixelBufferGetWidth(src))
  let scaleY  = CGFloat(h) / CGFloat(CVPixelBufferGetHeight(src))
  let scaled  = ciImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

  var dst: CVPixelBuffer?
  let attrs: [CFString: Any] = [
    kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
    kCVPixelBufferWidthKey:           w,
    kCVPixelBufferHeightKey:          h,
  ]
  guard CVPixelBufferCreate(kCFAllocatorDefault, w, h, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &dst) == kCVReturnSuccess,
        let dst = dst else { return nil }

  sharedCIContext.render(scaled, to: dst)
  return dst
}
