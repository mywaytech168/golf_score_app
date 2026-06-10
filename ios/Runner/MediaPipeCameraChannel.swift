import AVFoundation
import CoreGraphics
import Flutter
import MediaPipeTasksVision
import UIKit

/**
 * 高效能相機 Channel：AVFoundation + MediaPipe + 原生骨架合成
 *
 * 雙管線：
 *   - 預覽路徑：CVPixelBuffer → CoreGraphics 繪製骨架 → Flutter Texture
 *   - 錄製路徑：CVPixelBuffer → AVAssetWriter → MP4（與預覽路徑共用同一 buffer，零拷貝）
 *
 * MethodChannel : com.aethertek.orvia/camera_recorder
 * EventChannel  : com.aethertek.orvia/pose_landmarks
 */
@objc class MediaPipeCameraChannel: NSObject, FlutterTexture {

    // ── Flutter channels ───────────────────────────────────────────────────────
    private let methodChannel: FlutterMethodChannel
    private let poseEventChannel: FlutterEventChannel
    fileprivate var poseSink: FlutterEventSink?

    // ── Flutter Texture ────────────────────────────────────────────────────────
    private let registry: FlutterTextureRegistry
    private var textureId: Int64 = -1
    // Latest composited pixel buffer (camera + skeleton)
    private var latestBuffer: CVPixelBuffer?
    private let bufferLock = NSLock()

    // ── Camera session ─────────────────────────────────────────────────────────
    private var captureSession: AVCaptureSession?
    private var currentDevice: AVCaptureDevice?
    private var videoOutput = AVCaptureVideoDataOutput()
    private var audioOutput = AVCaptureAudioDataOutput()
    private let sessionQueue = DispatchQueue(label: "cam.session", qos: .userInitiated)
    private let videoQueue   = DispatchQueue(label: "cam.video",   qos: .userInitiated)
    private let audioQueue   = DispatchQueue(label: "cam.audio",   qos: .userInitiated)

    // ── Recording ──────────────────────────────────────────────────────────────
    private var assetWriter: AVAssetWriter?
    private var videoWriterInput: AVAssetWriterInput?
    private var audioWriterInput: AVAssetWriterInput?   // ★ 音軌
    private var isRecording = false
    private var recordingStarted = false   // first VIDEO sample appended flag（session 由 video 起算）
    // 預備好的 writer（prepareForRecording 先建立，startRecording 直接沿用 → 減少啟動延遲）
    private var preparedWriter: AVAssetWriter?
    private var preparedInput:  AVAssetWriterInput?
    private var preparedAudioInput: AVAssetWriterInput?
    private var preparedPath:   String?
    // ★ AVAssetWriter 實際寫入的暫存檔（finalPath + ".recording"）。
    //   finishWriting 成功後才 rename 成 finalPath，避免錄製中斷 / 失敗時殘留壞檔被播放（missing stsd）。
    private var recordingTmpPath:   String?
    private var recordingFinalPath: String?

    // ── MediaPipe ─────────────────────────────────────────────────────────────
    private var poseLandmarker: PoseLandmarker?
    private var lastLandmarks: [[String: Double]] = []
    private var lastLandmarkLock = NSLock()
    private var poseFrameCount = 0          // every frame — LIVE_STREAM self-throttles on ANE

    // ── State ──────────────────────────────────────────────────────────────────
    private var isFront = false
    private var captureSize = CGSize(width: 1280, height: 720)
    private var targetFps: Double = 30   // 目標幀率（30 或 60），由 openCamera 傳入

    // ── Init ───────────────────────────────────────────────────────────────────

    init(messenger: FlutterBinaryMessenger, registry: FlutterTextureRegistry) {
        self.registry = registry
        methodChannel  = FlutterMethodChannel(name: "com.aethertek.orvia/camera_recorder",
                                              binaryMessenger: messenger)
        poseEventChannel = FlutterEventChannel(name: "com.aethertek.orvia/pose_landmarks",
                                               binaryMessenger: messenger)
        super.init()
        methodChannel.setMethodCallHandler(handleMethodCall)
        poseEventChannel.setStreamHandler(PoseStreamHandler(owner: self))
        setupMediaPipe()
    }

    // ── FlutterTexture ─────────────────────────────────────────────────────────

    func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
        bufferLock.lock()
        defer { bufferLock.unlock() }
        guard let buf = latestBuffer else { return nil }
        return .passRetained(buf)
    }

    // ── MediaPipe setup ────────────────────────────────────────────────────────

    private func setupMediaPipe() {
        guard let path = findModelPath() else {
            print("[MediaPipeCamera] pose_landmarker_lite.task not found in any bundle location")
            return
        }
        do {
            let opts = PoseLandmarkerOptions()
            opts.baseOptions.modelAssetPath = path
            opts.baseOptions.delegate       = .GPU   // GPU + ANE acceleration
            opts.runningMode                = .liveStream
            opts.numPoses                   = 1
            opts.minPoseDetectionConfidence = 0.5
            opts.minPosePresenceConfidence  = 0.5
            opts.minTrackingConfidence      = 0.5
            opts.poseLandmarkerLiveStreamDelegate = self
            poseLandmarker = try PoseLandmarker(options: opts)
            print("[MediaPipeCamera] PoseLandmarker ready (GPU)")
        } catch {
            print("[MediaPipeCamera] PoseLandmarker init failed: \(error)")
        }
    }

    // ── MethodChannel ─────────────────────────────────────────────────────────

    private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any]
        switch call.method {
        case "openCamera":
            let facing  = args?["facing"] as? Int ?? 1
            let quality = args?["quality"] as? String ?? "hd"
            let fps     = args?["fps"] as? Int ?? 30
            isFront = (facing == 0)
            targetFps = (fps >= 60) ? 60 : 30
            openCamera(quality: quality, result: result)

        case "prepareForRecording":
            guard let path = args?["path"] as? String else {
                result(FlutterError(code: "invalid_args", message: "path required", details: nil)); return
            }
            prepareForRecording(path: path, result: result)

        case "startRecording":
            guard let path = args?["path"] as? String else {
                result(FlutterError(code: "invalid_args", message: "path required", details: nil)); return
            }
            startRecording(path: path, result: result)

        case "stopRecording":
            stopRecording(result: result)

        case "setZoom":
            let zoom = args?["zoom"] as? Double ?? 0.0
            setZoom(frac: zoom)
            result(nil)

        case "setVideoStabilization": result(nil)
        case "isVideoStabilizationSupported": result(false)

        case "switchCamera":
            isFront = !isFront
            let quality = (captureSize.width >= 1920) ? "fhd" : "hd"
            openCamera(quality: quality, result: result)

        case "dispose":
            dispose(); result(nil)

        case "destroy":
            dispose(); result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // ── Open camera ───────────────────────────────────────────────────────────

    private func openCamera(quality: String, result: @escaping FlutterResult) {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.captureSession?.stopRunning()
            self.captureSession = nil

            let session = AVCaptureSession()
            session.beginConfiguration()

            // Preset & capture size
            if quality == "fhd" {
                session.sessionPreset = .hd1920x1080
                self.captureSize = CGSize(width: 1920, height: 1080)
            } else {
                session.sessionPreset = .hd1280x720
                self.captureSize = CGSize(width: 1280, height: 720)
            }

            // Camera input
            let pos: AVCaptureDevice.Position = self.isFront ? .front : .back
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: pos),
                  let input  = try? AVCaptureDeviceInput(device: device) else {
                DispatchQueue.main.async {
                    result(FlutterError(code: "no_camera", message: "Cannot open camera", details: nil))
                }
                return
            }
            session.addInput(input)
            self.currentDevice = device

            // ── 音訊輸入：麥克風 → AVCaptureAudioDataOutput（錄進 mp4 音軌）──────────
            //   注意：App 另有 PCM 收音管線（flutter_audio_capture）做擊球聲分析，
            //   兩者共用麥克風，故 AVAudioSession 須設為可混音的 record 類別。
            self.configureAudioSession()
            if let mic = AVCaptureDevice.default(for: .audio),
               let micInput = try? AVCaptureDeviceInput(device: mic),
               session.canAddInput(micInput) {
                session.addInput(micInput)
                self.audioOutput = AVCaptureAudioDataOutput()
                self.audioOutput.setSampleBufferDelegate(self, queue: self.audioQueue)
                if session.canAddOutput(self.audioOutput) {
                    session.addOutput(self.audioOutput)
                }
            } else {
                print("[MediaPipeCamera] mic unavailable → recording will have no audio track")
            }

            // Lock to target fps (30 or 60) if supported
            let fps = self.targetFps
            if let format = self.bestFormat(for: device, minFps: fps) {
                let ts = CMTimeScale(fps)
                try? device.lockForConfiguration()
                device.activeFormat = format
                device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: ts)
                device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: ts)
                device.unlockForConfiguration()
                print("[MediaPipeCamera] Locked to \(Int(fps))fps")
            }

            // BGRA pixel output for CoreGraphics drawing
            self.videoOutput = AVCaptureVideoDataOutput()
            self.videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            self.videoOutput.alwaysDiscardsLateVideoFrames = true
            self.videoOutput.setSampleBufferDelegate(self, queue: self.videoQueue)
            session.addOutput(self.videoOutput)

            // Fix orientation
            if let conn = self.videoOutput.connection(with: .video) {
                conn.videoOrientation = .portrait
                if self.isFront { conn.isVideoMirrored = true }
            }

            session.commitConfiguration()
            session.startRunning()
            self.captureSession = session

            // Register Flutter Texture
            DispatchQueue.main.async {
                // Unregister old texture
                if self.textureId != -1 {
                    self.registry.unregisterTexture(self.textureId)
                }
                let tid = self.registry.register(self)
                self.textureId = tid
                let w = Int(self.captureSize.width)
                let h = Int(self.captureSize.height)
                result([
                    "textureId":                  tid,
                    "width":                      w,
                    "height":                     h,
                    "sensorOrientation":          0,    // rotation handled in Swift
                    "supportsVideoStabilization": false,
                ])
            }
        }
    }

    // ── AVAudioSession：允許錄音且與其他收音端（flutter_audio_capture）混用 ─────────
    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord,
                                    mode: .videoRecording,
                                    options: [.mixWithOthers, .defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
        } catch {
            print("[MediaPipeCamera] AVAudioSession config failed: \(error)")
        }
    }

    // ── Model path resolution (Flutter assets live in App.framework/flutter_assets/) ──

    private func findModelPath() -> String? {
        // 1. Flutter assets: App.framework/flutter_assets/assets/models/
        if let appFramework = Bundle.main.bundleURL
            .appendingPathComponent("Frameworks/App.framework")
            .absoluteString.removingPercentEncoding.flatMap({ URL(string: "file://" + $0) }),
           let b = Bundle(url: appFramework),
           let p = b.path(forResource: "flutter_assets/assets/models/pose_landmarker_lite",
                          ofType: "task") {
            return p
        }
        // 2. Copied directly into main bundle (Xcode resource)
        if let p = Bundle.main.path(forResource: "pose_landmarker_lite", ofType: "task") {
            return p
        }
        // 3. flutter_assets sub-path inside main bundle
        if let p = Bundle.main.path(forResource: "pose_landmarker_lite",
                                    ofType: "task",
                                    inDirectory: "flutter_assets/assets/models") {
            return p
        }
        return nil
    }

    // ── 60fps format search ────────────────────────────────────────────────────

    private func bestFormat(for device: AVCaptureDevice, minFps: Float64) -> AVCaptureDevice.Format? {
        return device.formats.last { fmt in
            let dims = CMVideoFormatDescriptionGetDimensions(fmt.formatDescription)
            let w = Int(dims.width)
            let h = Int(dims.height)
            guard w == Int(captureSize.width) || h == Int(captureSize.height) else { return false }
            return fmt.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= minFps }
        }
    }

    // ── Writer 建構（prepare 與 start 共用）──────────────────────────────────────

    /// 回傳 (writer, videoInput, audioInput?)；audioInput 為 nil 表示此次無音軌（麥克風不可用）。
    private func makeWriter(path finalPath: String)
        -> (AVAssetWriter, AVAssetWriterInput, AVAssetWriterInput?)? {
        let tmpPath = finalPath + ".recording"
        recordingFinalPath = finalPath
        recordingTmpPath   = tmpPath
        let url = URL(fileURLWithPath: tmpPath)
        // 若舊檔殘留，先移除避免 AVAssetWriter 建立失敗
        try? FileManager.default.removeItem(at: url)
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else {
            recordingTmpPath = nil; recordingFinalPath = nil
            return nil
        }
        let w = Int(captureSize.width)
        let h = Int(captureSize.height)
        let settings: [String: Any] = [
            AVVideoCodecKey:  AVVideoCodecType.h264,
            AVVideoWidthKey:  w,
            AVVideoHeightKey: h,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey:  (w >= 1920) ? 16_000_000 : 8_000_000,
                AVVideoProfileLevelKey:    AVVideoProfileLevelH264HighAutoLevel,
                AVVideoMaxKeyFrameIntervalKey: Int(targetFps),
            ],
        ]
        let wrInput = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        wrInput.expectsMediaDataInRealTime = true
        guard writer.canAdd(wrInput) else { return nil }
        writer.add(wrInput)

        // ── 音軌 input（AAC）──────────────────────────────────────────────────
        var audioInput: AVAssetWriterInput? = nil
        let audioSettings: [String: Any] = [
            AVFormatIDKey:         kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey:       44_100,
            AVEncoderBitRateKey:   128_000,
        ]
        let aInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        aInput.expectsMediaDataInRealTime = true
        if writer.canAdd(aInput) {
            writer.add(aInput)
            audioInput = aInput
        }
        return (writer, wrInput, audioInput)
    }

    // ── Prepare recording（預備 writer，與 Android prepareForRecording 對齊）───────

    private func prepareForRecording(path: String, result: @escaping FlutterResult) {
        sessionQueue.async { [weak self] in
            guard let self = self else { result(nil); return }
            // 已預備同一路徑 or 正在錄製 → 略過
            if self.preparedPath == path || self.isRecording {
                DispatchQueue.main.async { result(nil) }; return
            }
            self.preparedWriter = nil; self.preparedInput = nil
            self.preparedAudioInput = nil; self.preparedPath = nil
            guard let (writer, input, audioInput) = self.makeWriter(path: path) else {
                DispatchQueue.main.async {
                    result(FlutterError(code: "writer_error", message: "Cannot prepare AVAssetWriter", details: nil))
                }
                return
            }
            self.preparedWriter = writer
            self.preparedInput  = input
            self.preparedAudioInput = audioInput
            self.preparedPath   = path
            DispatchQueue.main.async { result(nil) }
        }
    }

    // ── Start recording ───────────────────────────────────────────────────────

    private func startRecording(path: String, result: @escaping FlutterResult) {
        sessionQueue.async { [weak self] in
            guard let self = self, !self.isRecording else { result(nil); return }

            let writer: AVAssetWriter
            let wrInput: AVAssetWriterInput
            let aInput: AVAssetWriterInput?
            if self.preparedPath == path, let pw = self.preparedWriter, let pi = self.preparedInput {
                // 沿用預備好的 writer
                writer = pw; wrInput = pi; aInput = self.preparedAudioInput
                self.preparedWriter = nil; self.preparedInput = nil
                self.preparedAudioInput = nil; self.preparedPath = nil
            } else {
                self.preparedWriter = nil; self.preparedInput = nil
                self.preparedAudioInput = nil; self.preparedPath = nil
                guard let (w, i, a) = self.makeWriter(path: path) else {
                    DispatchQueue.main.async {
                        result(FlutterError(code: "writer_error", message: "Cannot create AVAssetWriter", details: nil))
                    }
                    return
                }
                writer = w; wrInput = i; aInput = a
            }
            self.assetWriter       = writer
            self.videoWriterInput  = wrInput
            self.audioWriterInput  = aInput
            self.isRecording       = true
            self.recordingStarted  = false
            DispatchQueue.main.async { result(nil) }
        }
    }

    // ── Stop recording ────────────────────────────────────────────────────────

    private func stopRecording(result: @escaping FlutterResult) {
        sessionQueue.async { [weak self] in
            guard let self = self, self.isRecording else {
                DispatchQueue.main.async { result(nil) }; return
            }
            self.isRecording = false
            let tmp      = self.recordingTmpPath
            let finalDst = self.recordingFinalPath
            let started  = self.recordingStarted

            // 從未 append 任何 frame（startSession 沒被呼叫）→ 不可能產生有效檔，直接判失敗
            guard started, let writer = self.assetWriter else {
                self.cleanupFailedRecording(tmp: tmp)
                self.assetWriter = nil; self.videoWriterInput = nil; self.audioWriterInput = nil
                DispatchQueue.main.async {
                    result(FlutterError(code: "record_failed",
                                        message: "Recording produced no valid frames", details: nil))
                }
                return
            }

            self.videoWriterInput?.markAsFinished()
            self.audioWriterInput?.markAsFinished()
            writer.finishWriting {
                let ok = (writer.status == .completed)
                self.assetWriter = nil; self.videoWriterInput = nil; self.audioWriterInput = nil
                self.recordingTmpPath = nil; self.recordingFinalPath = nil

                if ok, let tmp = tmp, let finalDst = finalDst {
                    let renamed = self.atomicRename(from: tmp, to: finalDst)
                    DispatchQueue.main.async {
                        if renamed { result(true) }
                        else {
                            try? FileManager.default.removeItem(atPath: tmp)
                            result(FlutterError(code: "record_failed",
                                                message: "Rename failed", details: nil))
                        }
                    }
                } else {
                    // finishWriting 失敗（status == .failed）→ 刪壞檔、回報失敗
                    if let err = writer.error { print("[MediaPipeCamera] finishWriting failed: \(err)") }
                    self.cleanupFailedRecording(tmp: tmp)
                    DispatchQueue.main.async {
                        result(FlutterError(code: "record_failed",
                                            message: "AVAssetWriter finish failed", details: nil))
                    }
                }
            }
        }
    }

    /// 刪除未封口 / 失敗的暫存檔，並清空狀態。
    private func cleanupFailedRecording(tmp: String?) {
        if let tmp = tmp { try? FileManager.default.removeItem(atPath: tmp) }
        recordingTmpPath = nil; recordingFinalPath = nil
    }

    /// 暫存檔原子 rename 成最終檔（先確保目標不存在）。
    private func atomicRename(from tmp: String, to final: String) -> Bool {
        let fm = FileManager.default
        // 空檔（0 bytes）視為失敗
        let attrs = try? fm.attributesOfItem(atPath: tmp)
        let size  = (attrs?[.size] as? Int) ?? 0
        guard size > 0 else { return false }
        try? fm.removeItem(atPath: final)
        do { try fm.moveItem(atPath: tmp, toPath: final); return true }
        catch { print("[MediaPipeCamera] rename error: \(error)"); return false }
    }

    // ── Zoom ──────────────────────────────────────────────────────────────────

    private func setZoom(frac: Double) {
        guard let device = currentDevice else { return }
        let min = device.minAvailableVideoZoomFactor
        let max = min(device.maxAvailableVideoZoomFactor, 5.0)
        let level = (min + CGFloat(frac) * (max - min)).clamped(to: min...max)
        try? device.lockForConfiguration()
        device.videoZoomFactor = level
        device.unlockForConfiguration()
    }

    // ── Dispose ───────────────────────────────────────────────────────────────

    private func dispose() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            // 錄製中被 dispose（退出頁面 / 切背景）：取消寫入，未封口的暫存檔必為壞檔 → 刪除
            if self.isRecording, let writer = self.assetWriter, writer.status == .writing {
                writer.cancelWriting()
            }
            self.isRecording = false
            self.cleanupFailedRecording(tmp: self.recordingTmpPath)
            self.captureSession?.stopRunning()
            self.captureSession = nil
            self.assetWriter = nil
            self.videoWriterInput = nil
            self.audioWriterInput = nil
            self.preparedWriter = nil
            self.preparedInput = nil
            self.preparedAudioInput = nil
            self.preparedPath = nil
        }
        poseLandmarker = nil
        if textureId != -1 {
            registry.unregisterTexture(textureId)
            textureId = -1
        }
    }

    // ── Letterboxing state（供 extension 內的 captureOutput / delegate 使用）──

    let lboxSize: Int = 256   // 與 pose_landmarker_lite 模型輸入一致

    // 上一幀的 letterbox 參數（供 delegate 逆還原）
    struct LboxParams {
        let contentXNorm: Double  // scaledW / lboxSize
        let contentYNorm: Double  // scaledH / lboxSize
        let padXNorm:     Double  // padX    / lboxSize
        let padYNorm:     Double  // padY    / lboxSize
    }
    var currentLboxParams: LboxParams = LboxParams(contentXNorm:1,contentYNorm:1,padXNorm:0,padYNorm:0)
    var lastLboxParams:    LboxParams = LboxParams(contentXNorm:1,contentYNorm:1,padXNorm:0,padYNorm:0)
}

// ── AVCaptureVideoDataOutputSampleBufferDelegate ───────────────────────────────

extension MediaPipeCameraChannel: AVCaptureVideoDataOutputSampleBufferDelegate,
                                   AVCaptureAudioDataOutputSampleBufferDelegate {

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        // ── 音訊 buffer：只在 video 已起算 session 後 append（保持影音時間軸一致）──
        if output is AVCaptureAudioDataOutput {
            guard isRecording, recordingStarted,
                  let writer = assetWriter, writer.status == .writing,
                  let aInput = audioWriterInput, aInput.isReadyForMoreMediaData else { return }
            aInput.append(sampleBuffer)
            return
        }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // ── 1. Write CLEAN frame to AVAssetWriter first ──────────────────────
        //    ★ 必須在畫骨架之前 append，否則骨架會被燒進錄製影片（與 Android 對齊：錄乾淨原片）。
        if isRecording, let writer = assetWriter, let wrInput = videoWriterInput {
            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            if writer.status == .unknown {
                writer.startWriting()
                writer.startSession(atSourceTime: pts)
                recordingStarted = true
            }
            if writer.status == .writing && wrInput.isReadyForMoreMediaData {
                wrInput.append(sampleBuffer)
            }
        }

        // ── 2. Composite skeleton onto a COPY (preview only, keeps recording clean) ──
        let composited = compositedPreviewBuffer(from: pixelBuffer)

        // ── 3. Update Flutter Texture ────────────────────────────────────────
        bufferLock.lock()
        latestBuffer = composited ?? pixelBuffer
        bufferLock.unlock()
        if textureId != -1 {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.registry.textureFrameAvailable(self.textureId)
            }
        }

        // ── 4. MediaPipe pose detection with Letterboxing ────────────────────
        //    CVPixelBuffer (BGRA portrait) → letterbox 256×256 → MPImage → detectAsync
        //    逆座標還原在 poseLandmarker(_:didFinishDetection:) delegate 中執行
        poseFrameCount += 1
        let tsMs = Int(CACurrentMediaTime() * 1000)
        if let lboxBuffer = letterboxPixelBuffer(pixelBuffer, targetSize: lboxSize) {
            lastLandmarkLock.lock()
            lastLboxParams = currentLboxParams
            lastLandmarkLock.unlock()
            do {
                let mpImage = try MPImage(pixelBuffer: lboxBuffer)
                try poseLandmarker?.detectAsync(image: mpImage, timestampInMilliseconds: tsMs)
            } catch { /* ignore */ }
        }
    }

    // ── Letterboxing helpers ──────────────────────────────────────────────────

    /// CVPixelBuffer (任意尺寸) → 等比例縮放填黑邊 → targetSize×targetSize BGRA buffer
    private func letterboxPixelBuffer(_ src: CVPixelBuffer, targetSize: Int) -> CVPixelBuffer? {
        let srcW = CVPixelBufferGetWidth(src)
        let srcH = CVPixelBufferGetHeight(src)
        let t    = CGFloat(targetSize)
        let scale   = min(t / CGFloat(srcW), t / CGFloat(srcH))
        let scaledW = Int((CGFloat(srcW) * scale).rounded())
        let scaledH = Int((CGFloat(srcH) * scale).rounded())
        let padX    = (targetSize - scaledW) / 2
        let padY    = (targetSize - scaledH) / 2

        // 紀錄本幀的 letterbox 參數
        currentLboxParams = LboxParams(
            contentXNorm: Double(scaledW) / Double(targetSize),
            contentYNorm: Double(scaledH) / Double(targetSize),
            padXNorm:     Double(padX)    / Double(targetSize),
            padYNorm:     Double(padY)    / Double(targetSize)
        )

        // 建立目標 CVPixelBuffer
        var outBuf: CVPixelBuffer?
        let attrs = [kCVPixelBufferCGImageCompatibilityKey: true,
                     kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary
        guard CVPixelBufferCreate(kCFAllocatorDefault, targetSize, targetSize,
                                  kCVPixelFormatType_32BGRA, attrs, &outBuf) == kCVReturnSuccess,
              let dst = outBuf else { return nil }

        CVPixelBufferLockBaseAddress(src, .readOnly)
        CVPixelBufferLockBaseAddress(dst, [])
        defer {
            CVPixelBufferUnlockBaseAddress(src, .readOnly)
            CVPixelBufferUnlockBaseAddress(dst, [])
        }

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let dstData = CVPixelBufferGetBaseAddress(dst),
              let ctx = CGContext(
                  data: dstData, width: targetSize, height: targetSize,
                  bitsPerComponent: 8,
                  bytesPerRow: CVPixelBufferGetBytesPerRow(dst),
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue |
                              CGBitmapInfo.byteOrder32Little.rawValue
              ) else { return nil }

        // 黑色背景
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: targetSize, height: targetSize))

        // 繪製縮放後的原始畫面
        if let srcData = CVPixelBufferGetBaseAddress(src),
           let srcCtx = CGContext(
               data: srcData, width: srcW, height: srcH,
               bitsPerComponent: 8,
               bytesPerRow: CVPixelBufferGetBytesPerRow(src),
               space: colorSpace,
               bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue |
                           CGBitmapInfo.byteOrder32Little.rawValue
           ),
           let cgImg = srcCtx.makeImage() {
            ctx.draw(cgImg, in: CGRect(x: padX, y: padY, width: scaledW, height: scaledH))
        }
        return dst
    }

    // ── Preview compositing（在複製出的 buffer 上畫骨架，不動到錄製用的原 buffer）──

    /// 若有骨架資料，回傳一份「複製 + 骨架」的 buffer 供預覽；無骨架則回 nil（呼叫端改用原 buffer）。
    private func compositedPreviewBuffer(from src: CVPixelBuffer) -> CVPixelBuffer? {
        lastLandmarkLock.lock()
        let hasPose = !lastLandmarks.isEmpty
        lastLandmarkLock.unlock()
        guard hasPose else { return nil }
        guard let copy = copyPixelBuffer(src) else { return nil }
        return drawSkeletonOnBuffer(copy)   // 就地畫在 copy 上
    }

    /// 複製一份相同尺寸/格式的 BGRA CVPixelBuffer（深拷貝像素）。
    private func copyPixelBuffer(_ src: CVPixelBuffer) -> CVPixelBuffer? {
        let w   = CVPixelBufferGetWidth(src)
        let h   = CVPixelBufferGetHeight(src)
        let fmt = CVPixelBufferGetPixelFormatType(src)
        var dstOpt: CVPixelBuffer?
        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:],
        ] as CFDictionary
        guard CVPixelBufferCreate(kCFAllocatorDefault, w, h, fmt, attrs, &dstOpt) == kCVReturnSuccess,
              let dst = dstOpt else { return nil }

        CVPixelBufferLockBaseAddress(src, .readOnly)
        CVPixelBufferLockBaseAddress(dst, [])
        defer {
            CVPixelBufferUnlockBaseAddress(src, .readOnly)
            CVPixelBufferUnlockBaseAddress(dst, [])
        }
        guard let s = CVPixelBufferGetBaseAddress(src),
              let d = CVPixelBufferGetBaseAddress(dst) else { return nil }
        let srcBpr = CVPixelBufferGetBytesPerRow(src)
        let dstBpr = CVPixelBufferGetBytesPerRow(dst)
        if srcBpr == dstBpr {
            memcpy(d, s, srcBpr * h)
        } else {
            let rowBytes = min(srcBpr, dstBpr)
            for row in 0..<h {
                memcpy(d.advanced(by: row * dstBpr), s.advanced(by: row * srcBpr), rowBytes)
            }
        }
        return dst
    }

    // ── CoreGraphics skeleton overlay ────────────────────────────────────────

    private func drawSkeletonOnBuffer(_ buffer: CVPixelBuffer) -> CVPixelBuffer? {
        lastLandmarkLock.lock()
        let lms = lastLandmarks
        lastLandmarkLock.unlock()
        guard !lms.isEmpty else { return nil }   // no pose yet → return nil (use raw)

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        let w   = CVPixelBufferGetWidth(buffer)
        let h   = CVPixelBufferGetHeight(buffer)
        let ptr = CVPixelBufferGetBaseAddress(buffer)
        let bpr = CVPixelBufferGetBytesPerRow(buffer)

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: ptr, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: bpr,
                                  space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue |
                                              CGBitmapInfo.byteOrder32Little.rawValue) else {
            return nil
        }

        // CGContext(data:) has origin at bottom-left (y increases upward), but CVPixelBuffer
        // stores rows top-down (row 0 = top of image). Flip the context so y=0 maps to the
        // top of the pixel buffer, matching MediaPipe's normalized coordinate convention.
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        ctx.setLineCap(.round)

        // Bone edges (same indices as Android SkeletonRenderer)
        let edges: [(Int, Int)] = [
            (0,1),(1,2),(2,3),(3,7),(0,4),(4,5),(5,6),(6,8),(9,10),
            (11,12),(11,13),(13,15),(12,14),(14,16),
            (11,23),(12,24),(23,24),
            (23,25),(25,27),(27,29),(29,31),(27,31),
            (24,26),(26,28),(28,30),(30,32),(28,32),
            (15,17),(15,19),(15,21),(17,19),
            (16,18),(16,20),(16,22),(18,20),
        ]

        ctx.setStrokeColor(UIColor.cyan.cgColor)
        ctx.setLineWidth(4)

        for (a, b) in edges {
            guard a < lms.count, b < lms.count else { continue }
            let la = lms[a]; let lb = lms[b]
            let visA = la["vis"] ?? 0; let visB = lb["vis"] ?? 0
            guard visA > 0.3, visB > 0.3 else { continue }
            let ax = CGFloat(la["x"] ?? 0) * CGFloat(w)
            let ay = CGFloat(la["y"] ?? 0) * CGFloat(h)
            let bx = CGFloat(lb["x"] ?? 0) * CGFloat(w)
            let by = CGFloat(lb["y"] ?? 0) * CGFloat(h)
            ctx.move(to: CGPoint(x: ax, y: ay))
            ctx.addLine(to: CGPoint(x: bx, y: by))
        }
        ctx.strokePath()

        // Joint circles
        for (i, lm) in lms.enumerated() {
            let vis = lm["vis"] ?? 0
            guard vis > 0.3 else { continue }
            let cx = CGFloat(lm["x"] ?? 0) * CGFloat(w)
            let cy = CGFloat(lm["y"] ?? 0) * CGFloat(h)
            let r: CGFloat = (i == 16) ? 14 : 7
            let color = (i == 16) ? UIColor.red : UIColor.green
            ctx.setFillColor(color.cgColor)
            ctx.fillEllipse(in: CGRect(x: cx - r, y: cy - r, width: r*2, height: r*2))
        }

        // Return same buffer (we drew in-place)
        return buffer
    }
}

// ── PoseLandmarkerLiveStreamDelegate ──────────────────────────────────────────

extension MediaPipeCameraChannel: PoseLandmarkerLiveStreamDelegate {
    func poseLandmarker(_ poseLandmarker: PoseLandmarker,
                        didFinishDetection result: PoseLandmarkerResult?,
                        timestampInMilliseconds: Int,
                        error: Error?) {
        guard let result = result, !result.landmarks.isEmpty else {
            lastLandmarkLock.lock()
            lastLandmarks = []
            lastLandmarkLock.unlock()
            return
        }

        // 逆 Letterbox 還原：從 256×256 正方形座標 → 原始直式影像座標
        let params = lastLboxParams
        let lms: [[String: Double]] = result.landmarks[0].map { lm in
            let origX: Double
            let origY: Double
            if params.contentXNorm > 0 && params.contentYNorm > 0 {
                origX = ((Double(lm.x) - params.padXNorm) / params.contentXNorm)
                    .clamped(to: 0...1)
                origY = ((Double(lm.y) - params.padYNorm) / params.contentYNorm)
                    .clamped(to: 0...1)
            } else {
                origX = Double(lm.x)
                origY = Double(lm.y)
            }
            return ["x": origX, "y": origY,
                    "z": Double(lm.z), "vis": Double(lm.visibility ?? 0)]
        }

        lastLandmarkLock.lock()
        lastLandmarks = lms
        lastLandmarkLock.unlock()

        // Push to Flutter EventChannel for LiveSwingDetector
        guard let sink = poseSink else { return }
        DispatchQueue.main.async {
            sink(["landmarks": lms, "ts": timestampInMilliseconds])
        }
    }
}

// ── FlutterStreamHandler ───────────────────────────────────────────────────────

private class PoseStreamHandler: NSObject, FlutterStreamHandler {
    weak var owner: MediaPipeCameraChannel?
    init(owner: MediaPipeCameraChannel) { self.owner = owner }
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        owner?.poseSink = events; return nil
    }
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        owner?.poseSink = nil; return nil
    }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
