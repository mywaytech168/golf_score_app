package com.aethertek.orvia

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageFormat
import android.graphics.Matrix
import android.graphics.Rect
import android.graphics.YuvImage
import android.hardware.camera2.*
import android.media.Image
import android.media.ImageReader
import android.media.MediaRecorder
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import android.util.Range
import android.util.Size
import android.view.Surface
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import java.io.ByteArrayOutputStream

/**
 * 高效能相機 Channel：Camera2 + MediaPipe + 原生骨架合成
 *
 * ┌────────────────────────────────────────────────────────────────────────┐
 * │  雙管線架構（解析度分流）                                                 │
 * │                                                                          │
 * │  Camera2                                                                 │
 * │    ├── previewReader  (1280×720 YUV)  ← 顯示管線                        │
 * │    │     copy NV21 → cameraHandler.close() → renderHandler              │
 * │    │     → JPEG Bitmap → 骨架 → SurfaceProducer (Flutter Texture)        │
 * │    │                                                                      │
 * │    ├── analysisReader (640×360 YUV)   ← AI 分析管線                     │
 * │    │     copy NV21 → cameraHandler.close() → renderHandler              │
 * │    │     → Bitmap → 旋轉 → 縮圖 270×480 → MediaPipe Letterbox          │
 * │    │     → EventChannel → LiveSwingDetector (Dart)                       │
 * │    │                                                                      │
 * │    └── MediaRecorder  (1920×1080 H264) ← 錄製管線（錄製中才加入）       │
 * └────────────────────────────────────────────────────────────────────────┘
 *
 * FPS：由 selectFpsRange() 從裝置能力中選取最高固定幀率，防止 AE 自動降到 8fps。
 * 防震：OIS + EIS 全程關閉，確保骨架座標與畫面像素一致。
 * 關閉：listener→stopRepeating→abortCaptures→session→readers→device，零競態。
 */
class CameraRecorderChannel(
    private val context: Context,
    private val textureRegistry: TextureRegistry,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    companion object {
        private const val TAG = "CameraRecorderCh"
        const val METHOD_CHANNEL = "com.aethertek.orvia/camera_recorder"
        const val POSE_CHANNEL   = "com.aethertek.orvia/pose_landmarks"

        // ── 解析度分流 ─────────────────────────────────────────────────────
        // ★ 優化：預覽降至 640×360（足夠即時顯示，YUV→JPEG→Bitmap 負擔↓70%）
        //   錄製仍保持 1920×1080 / 1280×720（MediaRecorder 走獨立 Surface）
        private const val PREVIEW_W = 640;   private const val PREVIEW_H = 360
        // AI 分析管線：360×202（預覽的 0.56× 尺寸，骨架偵測足夠，延遲↓5fps）
        private const val ANALYSIS_W = 360;  private const val ANALYSIS_H = 202
        // MediaPipe 送入尺寸（旋轉後直式，9:16）
        private const val POSE_W = 270;      private const val POSE_H = 480
        // JPEG 品質：預覽 35（快速），足夠）
        private const val JPEG_QUALITY_PREVIEW = 35
        private const val JPEG_QUALITY_ANALYSIS = 35
        // analysisReader 超過此毫秒數沒輸出 → 判定 stale，改由 preview 補 MediaPipe。
        // 每幀都嘗試送進 MediaPipe，analysisInFlight permit 做 back-pressure（忙時自動跳過）。
        private const val ANALYSIS_STALE_MS = 1000L
        // ★ 2 幀 in-flight：CPU 轉換（~24ms）與 GPU 推論（~33ms）pipeline 重疊，
        //   吞吐上限從 convert+infer+空轉(~105ms) 變成 max(convert, infer)(~33ms)。
        //   實測 9-10fps → 預期 20-25fps。LIVE_STREAM 內部 queue 可吸收 2 幀。
        private const val MAX_ANALYSIS_IN_FLIGHT = 2
        // permit 全滿且超過此毫秒無任何釋放 → 判定 MediaPipe 靜默丟幀（FlowLimiter
        // 不回呼）造成 permit 洩漏，強制歸零重啟管線。
        private const val PERMIT_STALL_RESET_MS = 2000L
    }

    // ── Flutter channels ──────────────────────────────────────────────────────
    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL)
    private val poseChannel   = EventChannel(messenger, POSE_CHANNEL)
    private var poseSink: EventChannel.EventSink? = null

    // ── Threads ────────────────────────────────────────────────────────────────
    private val cameraThread  = HandlerThread("CameraThread").also { it.start() }
    private val cameraHandler = Handler(cameraThread.looper)
    private val renderThread  = HandlerThread("RenderThread").also { it.start() }
    private val renderHandler = Handler(renderThread.looper)
    // ★ imageThread：專用於 ImageReader.onImageAvailable 回呼。
    //   必須與 cameraHandler 分離，否則 setRepeatingRequest → waitUntilIdle() 在
    //   cameraHandler 上 block 時，onImageAvailable 無法釋放 buffer → HAL 永久 stall
    //   → waitUntilIdle 無法完成 → 畫面卡在第一幀（deadlock）。
    private val imageThread   = HandlerThread("ImageThread").also { it.start() }
    private val imageHandler  = Handler(imageThread.looper)
    // ★ analysisThread：專用於分析幀轉換（NV21→Bitmap→detectAsync）。
    //   與 renderThread 分離：預覽繪製（onDisplayNv21）不再與分析轉換互搶，
    //   且單一 looper 序列執行保證 detectAsync 時間戳單調遞增。
    private val analysisThread  = HandlerThread("AnalysisThread").also { it.start() }
    private val analysisHandler = Handler(analysisThread.looper)
    private val mainHandler   = Handler(Looper.getMainLooper())

    // ── Camera2 objects ───────────────────────────────────────────────────────
    private val cameraManager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
    @Volatile private var cameraDevice   : CameraDevice?         = null
    @Volatile private var captureSession : CameraCaptureSession? = null
    @Volatile private var previewReader  : ImageReader?          = null  // 顯示
    @Volatile private var analysisReader : ImageReader?          = null  // AI 分析
    @Volatile private var mediaRecorder  : MediaRecorder?        = null
    @Volatile private var isRecording     = false
    // preparedRecPath 已移至 camera operation serialization 區塊

    private var currentFacing         = CameraCharacteristics.LENS_FACING_BACK
    private var currentCameraId       : String? = null
    private var recordW = 1920; private var recordH = 1080  // 錄製解析度（預設 FHD）
    private var recordFps = 30                              // 錄製/預覽目標幀率（30 或 60）
    private var sensorOrientation     = 90
    @Volatile private var openResultReplied = false

    // ── 裝置能力快取 ──────────────────────────────────────────────────────────
    private var supportsStabilization = false
    private var stabEnabled           = true     // 使用者偏好（但 OIS/EIS 一律關閉）
    private var hasOis                = false    // 裝置是否有 OIS
    private var previewFpsRange       : Range<Int> = Range(30, 30)  // 預覽固定 FPS
    // ★ 實際採用的 reader 尺寸：openCamera 時從 HAL 支援清單挑選（可能與目標常數不同）
    private var previewSize  : Size = Size(PREVIEW_W, PREVIEW_H)
    private var analysisSize : Size = Size(ANALYSIS_W, ANALYSIS_H)

    // ── Flutter Texture (SurfaceProducer) ─────────────────────────────────────
    private var surfaceProducer: TextureRegistry.SurfaceProducer? = null

    // ── Skeleton data ─────────────────────────────────────────────────────────
    @Volatile private var lastLandmarks: List<Map<String, Any>> = emptyList()

    // ── MediaPipe ─────────────────────────────────────────────────────────────
    private val poseHelper = MediaPipePoseHelper(
        context = context,
        onResult = { lms, ts ->
            lastLandmarks = lms
            val sink = poseSink ?: return@MediaPipePoseHelper
            mainHandler.post { sink.success(mapOf("landmarks" to lms, "ts" to ts)) }
        },
        onFrameDone = { releaseAnalysisPermit() },
    )

    // ── Rendering state ───────────────────────────────────────────────────────
    @Volatile private var isRendering = false
    @Volatile private var analysisFallbackFromPreview = false
    @Volatile private var lastAnalysisFrameAtMs = 0L
    @Volatile private var previewFrameSeq = 0

    // ── Camera operation serialization ────────────────────────────────────────
    // 防止 openCamera / prepareForRecording / startRecording / switchCamera 並發，
    // 避免 waitUntilIdle timeout → CameraThread FATAL EXCEPTION。
    @Volatile private var cameraOpRunning = false
    private var preparedRecPath: String? = null   // 已預備好的錄影路徑（= 最終 swing.mp4）
    @Volatile private var isPreparingRecording = false
    // ★ MediaRecorder 實際寫入的暫存檔（finalPath + ".recording"）。
    //   prepare() 會佔用此檔且 moov 未封口，stop() 成功後才 rename 成 finalPath，
    //   避免 prewarm 半成品污染 swing.mp4 被播放器讀到（missing stsd）。
    private var recordingTmpPath: String? = null
    private var recordingFinalPath: String? = null

    // ── Init ──────────────────────────────────────────────────────────────────

    init {
        methodChannel.setMethodCallHandler(this)
        poseChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(a: Any?, s: EventChannel.EventSink?) { poseSink = s }
            override fun onCancel(a: Any?) { poseSink = null }
        })
        cameraHandler.post {
            try { poseHelper.setup() }
            catch (e: Throwable) { Log.e(TAG, "poseHelper.setup failed: $e") }
        }
    }

    // ── MethodChannel ─────────────────────────────────────────────────────────

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        Log.d(TAG, "onMethodCall: ${call.method}")
        when (call.method) {
            "openCamera" -> {
                val facing  = call.argument<Int>("facing") ?: CameraCharacteristics.LENS_FACING_BACK
                val quality = call.argument<String>("quality") ?: "hd"
                val fps     = call.argument<Int>("fps") ?: 30
                runCameraOp("openCamera", result) { openCamera(facing, quality, fps, result) }
            }
            "prepareForRecording" -> {
                val path = call.argument<String>("path")
                    ?: return result.error("invalid_args", "path required", null)
                runCameraOp("prepareForRecording", result) { prepareForRecordingOnCamera(path, result) }
            }
            "startRecording" -> {
                val path = call.argument<String>("path")
                    ?: return result.error("invalid_args", "path required", null)
                runCameraOp("startRecording", result) { startRecordingOnCamera(path, result) }
            }
            "stopRecording"  -> cameraHandler.post { stopRecordingOnCamera(result) }
            "setZoom" -> {
                val zoom = (call.argument<Double>("zoom") ?: 0.0).toFloat()
                cameraHandler.post { applyZoom(zoom) }
                result.success(null)
            }
            "setVideoStabilization" -> {
                stabEnabled = call.argument<Boolean>("enabled") ?: true
                result.success(null)
            }
            "isVideoStabilizationSupported" -> {
                val id = currentCameraId ?: findCameraId(CameraCharacteristics.LENS_FACING_BACK)
                result.success(if (id != null) checkStabilization(id) else false)
            }
            "switchCamera" -> {
                currentFacing = if (currentFacing == CameraCharacteristics.LENS_FACING_BACK)
                    CameraCharacteristics.LENS_FACING_FRONT else CameraCharacteristics.LENS_FACING_BACK
                runCameraOp("switchCamera", result) {
                    openCamera(currentFacing, if (recordW >= 1920) "fhd" else "hd", recordFps, result)
                }
            }
            "dispose" -> {
                // 錄影頁關閉：等 native camera/session/surface 真的關完，再回覆 Dart。
                cameraHandler.post {
                    closeOnCamera()
                    mainHandler.post { result.success(null) }
                }
            }
            "destroy" -> {
                // App / Plugin 真正銷毀：完整關閉 MediaPipe + HandlerThreads。
                // 呼叫後這個 CameraRecorderChannel 實例不可再 openCamera。
                cameraHandler.post {
                    destroyOnCamera()
                    mainHandler.post { result.success(null) }
                }
            }
            else -> result.notImplemented()
        }
    }

    /**
     * 序列化所有 Camera 操作（openCamera / prepareForRecording / startRecording / switchCamera）。
     *
     * 防止並發呼叫 createCaptureSession → waitUntilIdle timeout → CameraThread crash。
     * block 本身負責呼叫 result.success/error，並在完成後呼叫 releaseOp()。
     * 若目前有 op 正在執行，直接回覆 camera_busy error。
     */
    private fun runCameraOp(name: String, result: MethodChannel.Result, block: () -> Unit) {
        if (cameraOpRunning) {
            Log.w(TAG, "runCameraOp: $name ignored, another op running")
            mainHandler.post { result.error("camera_busy", "$name: camera busy", null) }
            return
        }
        cameraOpRunning = true
        Log.d(TAG, "runCameraOp: $name start")
        cameraHandler.post {
            try { block() }
            catch (e: Exception) {
                Log.e(TAG, "runCameraOp: $name threw $e")
                releaseOp(name)
                mainHandler.post { runCatching { result.error("camera_op_error", e.message, null) } }
            }
        }
    }

    /** camera op 完成（含非同步 onConfigured / onConfigureFailed）後呼叫，解除鎖定 */
    private fun releaseOp(name: String) {
        cameraOpRunning = false
        Log.d(TAG, "runCameraOp: $name done")
    }

    // ── Open camera ───────────────────────────────────────────────────────────

    private fun openCamera(facing: Int, quality: String, fps: Int, result: MethodChannel.Result) {
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA)
            != PackageManager.PERMISSION_GRANTED) {
            releaseOp("openCamera")
            mainHandler.post { result.error("permission", "Camera permission not granted", null) }
            return
        }
        // ★ 麥克風權限：buildRecorder() 第一步即 setAudioSource(MIC)，未授權會讓 prepare()
        //   直接丟例外、prewarm 永遠失敗。提前檢查並回報明確錯誤碼，由 Dart 引導使用者。
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO)
            != PackageManager.PERMISSION_GRANTED) {
            releaseOp("openCamera")
            mainHandler.post { result.error("permission_audio", "Microphone permission not granted", null) }
            return
        }

        currentFacing = facing
        val cameraId = findCameraId(facing) ?: run {
            releaseOp("openCamera")
            mainHandler.post { result.error("no_camera", "No camera for facing=$facing", null) }
            return
        }
        currentCameraId = cameraId

        // 錄製解析度：FHD 1920×1080 或 HD 1280×720
        recordW = if (quality == "fhd") 1920 else 1280
        recordH = if (quality == "fhd") 1080 else 720
        recordFps = if (fps >= 60) 60 else 30

        // 查詢裝置能力
        sensorOrientation     = getSensorOrientation(cameraId)
        supportsStabilization = checkStabilization(cameraId)
        hasOis                = checkOis(cameraId)
        previewFpsRange       = selectFpsRange(cameraId, targetFps = recordFps)
        previewSize           = selectYuvSize(cameraId, PREVIEW_W, PREVIEW_H)
        analysisSize          = selectYuvSize(cameraId, ANALYSIS_W, ANALYSIS_H)

        Log.d(TAG, "openCamera: facing=$facing quality=$quality ${recordW}×${recordH} " +
                   "sensorOri=$sensorOrientation fps=$previewFpsRange ois=$hasOis")

        // SurfaceProducer 必須在 main thread 建立（Flutter Texture）
        val displayW = if (sensorOrientation == 90 || sensorOrientation == 270) recordH else recordW
        val displayH = if (sensorOrientation == 90 || sensorOrientation == 270) recordW else recordH
        val oldProducer = surfaceProducer

        mainHandler.post {
            val producer = textureRegistry.createSurfaceProducer()
            surfaceProducer = producer
            producer.setSize(displayW, displayH)

            // SurfaceProducer / Flutter Texture 必須在 main thread release。
            // 不要放在 cameraHandler，避免 Surface.release 未明確呼叫與資源競態。
            runCatching { oldProducer?.release() }

        cameraHandler.post {
            closeSessionAndCamera()   // 先乾淨關閉舊資源

            // ── 開啟 CameraDevice ─────────────────────────────────────────────
            openResultReplied = false
            try {
                setupImageReaders(producer)
                cameraManager.openCamera(cameraId, object : CameraDevice.StateCallback() {
                    override fun onOpened(cam: CameraDevice) {
                        cameraDevice = cam
                        startPreviewSession(cam, producer, result)
                    }
                    override fun onDisconnected(cam: CameraDevice) {
                        runCatching { cam.close() }; cameraDevice = null
                    }
                    override fun onError(cam: CameraDevice, err: Int) {
                        runCatching { cam.close() }; cameraDevice = null
                        if (openResultReplied) {
                            // 已成功開啟後才突發 serious error（錄製中等）→ 最後一道保險：自動復原。
                            Log.e(TAG, "CameraDevice onError $err after open → recover")
                            recoverCamera()
                        } else {
                            // 初次開啟就失敗：回報 Dart，由上層決定（不自動復原，避免與重試衝突）。
                            replyOpenError(result, "Camera error $err")
                        }
                    }
                }, cameraHandler)
            } catch (e: Exception) {
                // setupImageReaders 或 openCamera 失敗：清掉半初始化的 readers，避免洩漏
                runCatching { previewReader?.close()  }; previewReader  = null
                runCatching { analysisReader?.close() }; analysisReader = null
                releaseOp("openCamera")
                replyOpenError(result, e.message ?: "openCamera failed")
            }
        }
        } // mainHandler.post
    }

    /**
     * 建立 previewReader（顯示）與 analysisReader（AI 分析）兩條 ImageReader 管線。
     * openCamera 與 recoverCamera 共用；listener 在 imageHandler 上執行避免 deadlock。
     */
    private fun setupImageReaders(producer: TextureRegistry.SurfaceProducer) {
        val isFront = (currentFacing == CameraCharacteristics.LENS_FACING_FRONT)

        // ── previewReader：顯示管線 ──────────────────────────────────────────
        previewReader = ImageReader.newInstance(previewSize.width, previewSize.height, ImageFormat.YUV_420_888, 3)
            .also { ir ->
                ir.setOnImageAvailableListener({ reader ->
                    var img: Image? = null
                    var nv21: ByteArray? = null
                    var imgTimestampNs = 0L
                    var imgW = 0; var imgH = 0
                    try {
                        img = reader.acquireLatestImage() ?: return@setOnImageAvailableListener
                        imgTimestampNs = img.timestamp   // ★ 在 close 前取感測器時間戳
                        imgW = img.width; imgH = img.height   // ★ 用實際尺寸，HAL 可能不照要求吐
                        nv21 = yuv420ToNv21Fast(img)
                    } catch (e: Exception) {
                        Log.w(TAG, "preview NV21 copy: $e")
                    } finally {
                        img?.close()   // ★ 雷打不動：必在 finally 關閉，絕不傳遞 Image 物件
                    }
                    val data = nv21 ?: return@setOnImageAvailableListener
                    val tsNs = imgTimestampNs

                    if (!isRendering) {
                        isRendering = true
                        renderHandler.post {
                            onDisplayNv21(data, imgW, imgH, sensorOrientation, isFront, producer)
                        }
                    }
                    val nowMs = SystemClock.uptimeMillis()
                    val analysisStale = nowMs - lastAnalysisFrameAtMs > ANALYSIS_STALE_MS
                    if (analysisFallbackFromPreview || analysisStale) {
                        val seq = previewFrameSeq++
                        if (seq % 30 == 0) {
                            Log.w(TAG, "analysis stale/fallback: from preview, " +
                                "stale=${nowMs - lastAnalysisFrameAtMs}ms recording=$isRecording")
                        }
                        watchdogResetStalledPermits()
                        if (tryAcquireAnalysisPermit()) {
                            analysisHandler.post {
                                onAnalysisNv21(data, imgW, imgH, sensorOrientation, isFront, tsNs)
                            }
                        }
                    }
                }, imageHandler)  // ★ imageHandler（非 cameraHandler）避免 deadlock
            }

        // ── analysisReader：AI 分析管線 ─────────────────────────────────────
        analysisReader = ImageReader.newInstance(analysisSize.width, analysisSize.height, ImageFormat.YUV_420_888, 4)
            .also { ir ->
                ir.setOnImageAvailableListener({ reader ->
                    var img: Image? = null
                    var nv21: ByteArray? = null
                    var imgTimestampNs = 0L
                    var imgW = 0; var imgH = 0
                    try {
                        img = reader.acquireLatestImage() ?: return@setOnImageAvailableListener
                        // ★ gate 前移：permits 用盡時直接丟幀（仍須 acquire+close 排空佇列），
                        //   不做 NV21 複製 — 省下被丟幀的 1.5-3.5ms CPU 與 346KB 配置。
                        lastAnalysisFrameAtMs = SystemClock.uptimeMillis()
                        analysisFallbackFromPreview = false
                        watchdogResetStalledPermits()
                        if (analysisInFlight.get() >= MAX_ANALYSIS_IN_FLIGHT) {
                            return@setOnImageAvailableListener
                        }
                        imgTimestampNs = img.timestamp
                        imgW = img.width; imgH = img.height
                        nv21 = yuv420ToNv21Fast(img)
                    } catch (e: Exception) {
                        Log.w(TAG, "analysis NV21 copy: $e")
                    } finally {
                        img?.close()
                    }
                    val data = nv21 ?: return@setOnImageAvailableListener

                    if (tryAcquireAnalysisPermit()) {
                        val tsNs = imgTimestampNs
                        analysisHandler.post {
                            onAnalysisNv21(data, imgW, imgH, sensorOrientation, isFront, tsNs)
                        }
                    }
                }, imageHandler)
            }
    }

    // ── Camera 自動復原 ─────────────────────────────────────────────────────────
    @Volatile private var recovering = false

    /** no-op result：內部復原重開相機時用，不對 Dart 回覆 */
    private val noopResult = object : MethodChannel.Result {
        override fun success(result: Any?) {}
        override fun error(code: String, message: String?, details: Any?) {}
        override fun notImplemented() {}
    }

    /**
     * 相機進入 serious error（HAL drain timeout、createCaptureSession 連續失敗）時，
     * 完整 close + 重開 CameraDevice，**沿用同一個 SurfaceProducer（textureId 不變）**，
     * 使用者無需離開頁面即可恢復預覽與後續錄製。
     */
    private fun recoverCamera() {
        if (recovering) { Log.w(TAG, "recoverCamera: already recovering, skip"); return }
        val producer = surfaceProducer
        val camId    = currentCameraId
        if (producer == null || camId == null) {
            Log.w(TAG, "recoverCamera: no producer/camId, skip"); return
        }
        recovering = true
        Log.w(TAG, "recoverCamera: closing wedged camera and reopening (textureId preserved)")

        // 關閉壞掉的資源（保留 surfaceProducer / texture）
        runCatching { previewReader?.setOnImageAvailableListener(null, null) }
        runCatching { analysisReader?.setOnImageAvailableListener(null, null) }
        runCatching { captureSession?.stopRepeating() }
        runCatching { captureSession?.close() }; captureSession = null
        runCatching { previewReader?.close()  }; previewReader  = null
        runCatching { analysisReader?.close() }; analysisReader = null
        runCatching { mediaRecorder?.release() }; mediaRecorder = null
        runCatching { cameraDevice?.close()   }; cameraDevice   = null
        isRecording = false; preparedRecPath = null
        recordingTmpPath = null; recordingFinalPath = null

        // 延遲讓 HAL 釋放連線後再重開
        cameraHandler.postDelayed({
            if (surfaceProducer == null) { recovering = false; return@postDelayed }
            openResultReplied = true   // 不對任何 Dart result 回覆（內部復原）
            try {
                setupImageReaders(producer)
                cameraManager.openCamera(camId, object : CameraDevice.StateCallback() {
                    override fun onOpened(cam: CameraDevice) {
                        cameraDevice = cam
                        startPreviewSession(cam, producer, noopResult)
                        recovering = false
                        Log.d(TAG, "recoverCamera: reopened OK")
                    }
                    override fun onDisconnected(cam: CameraDevice) {
                        runCatching { cam.close() }; cameraDevice = null; recovering = false
                    }
                    override fun onError(cam: CameraDevice, err: Int) {
                        runCatching { cam.close() }; cameraDevice = null; recovering = false
                        Log.e(TAG, "recoverCamera: reopen onError $err (giving up)")
                    }
                }, cameraHandler)
            } catch (e: Exception) {
                Log.e(TAG, "recoverCamera: reopen threw $e")
                runCatching { previewReader?.close()  }; previewReader  = null
                runCatching { analysisReader?.close() }; analysisReader = null
                recovering = false
            }
        }, 400)
    }

    private fun replyOpenError(result: MethodChannel.Result, msg: String) {
        if (!openResultReplied) {
            openResultReplied = true
            mainHandler.post { result.error("camera_error", msg, null) }
        }
    }

    // ── Preview session ───────────────────────────────────────────────────────

    private fun startPreviewSession(
        cam: CameraDevice,
        producer: TextureRegistry.SurfaceProducer,
        result: MethodChannel.Result,
    ) {
        val pr = previewReader ?: return
        val ar = analysisReader ?: return

        cam.createCaptureSession(
            listOf(pr.surface, ar.surface),
            object : CameraCaptureSession.StateCallback() {
                override fun onConfigured(s: CameraCaptureSession) {
                    captureSession = s
                    issuePreviewRequest(s, cam, pr.surface, ar.surface)
                    releaseOp("openCamera")
                    if (!openResultReplied) {
                        openResultReplied = true
                        mainHandler.post {
                            result.success(mapOf(
                                "textureId"                  to producer.id(),
                                "width"                      to if (sensorOrientation == 90 || sensorOrientation == 270) recordH else recordW,
                                "height"                     to if (sensorOrientation == 90 || sensorOrientation == 270) recordW else recordH,
                                "sensorOrientation"          to 0,
                                "supportsVideoStabilization" to supportsStabilization,
                            ))
                        }
                    }
                }
                override fun onConfigureFailed(s: CameraCaptureSession) {
                    releaseOp("openCamera")
                    replyOpenError(result, "Preview session configure failed")
                }
            },
            cameraHandler
        )
    }

    private fun issuePreviewRequest(
        s: CameraCaptureSession, cam: CameraDevice,
        previewSurface: Surface, analysisSurface: Surface,
    ) {
        try {
            val req = cam.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW).apply {
                addTarget(previewSurface)
                addTarget(analysisSurface)
                set(CaptureRequest.CONTROL_AF_MODE,  CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_VIDEO)
                set(CaptureRequest.CONTROL_AE_MODE,  CaptureRequest.CONTROL_AE_MODE_ON)
                set(CaptureRequest.CONTROL_AWB_MODE, CaptureRequest.CONTROL_AWB_MODE_AUTO)
                // ★ 鎖定固定 FPS：防止 AE 自動降到 8fps
                set(CaptureRequest.CONTROL_AE_TARGET_FPS_RANGE, previewFpsRange)
                applyStabilizationOff()
            }
            s.setRepeatingRequest(req.build(), null, cameraHandler)
            // 給 analysisReader 500ms 緩衝，避免第一幀 preview 就誤判 stale
            lastAnalysisFrameAtMs = SystemClock.uptimeMillis()
            analysisFallbackFromPreview = false
            previewFrameSeq = 0
            Log.d(TAG, "issuePreviewRequest: fps=$previewFpsRange")
        } catch (e: Exception) { Log.w(TAG, "issuePreviewRequest: $e") }
    }

    // ── Prepare + Start recording ──────────────────────────────────────────────

    /**
     * ★ 零閃爍方案：提前建立含 MediaRecorder 的 CaptureSession。
     *
     * 修復：
     *  1. 先 stop/abort/close 舊 session，防止 waitUntilIdle timeout
     *  2. createCaptureSession 外層 try/catch，不讓 CameraThread 崩潰
     *  3. onConfigured/onConfigureFailed 都呼叫 releaseOp 解除序列化鎖
     *  4. 重複呼叫同一路徑直接返回（releaseOp 必須呼叫）
     */
    private fun prepareForRecordingOnCamera(path: String, result: MethodChannel.Result) {
        // ── 已預備同一路徑 or 正在錄製中 → 直接返回 ──────────────────────────
        if (preparedRecPath == path || isRecording) {
            Log.d(TAG, "prepareForRecording: already prepared or recording, skip")
            releaseOp("prepareForRecording")
            mainHandler.post { result.success(null) }
            return
        }

        val cam = cameraDevice
        val pr  = previewReader
        if (cam == null || pr == null) {
            releaseOp("prepareForRecording")
            mainHandler.post { result.error("no_camera", "Camera not ready", null) }
            return
        }
        val ar = analysisReader

        // ── 清理之前未使用的預備錄製器 ────────────────────────────────────────
        runCatching { mediaRecorder?.release() }; mediaRecorder = null
        preparedRecPath = null

        // ── ★ 先停掉舊 session，防止 waitUntilIdle timeout ────────────────────
        stopSessionSafely()

        val rec = buildRecorder(path) ?: run {
            releaseOp("prepareForRecording")
            mainHandler.post { result.error("recorder_error", "MediaRecorder prepare failed", null) }
            return
        }
        mediaRecorder = rec

        // ── ★ 2-stream 錄製方案：session 只含 preview + recorder（不含 analysisReader）。
        //   本機 HAL 無法同時餵滿 preview(YUV)+analysis(YUV)+recorder(1080p) 三條串流，
        //   recorder 會被餓死 → rec.stop() -1007。錄製期間改由 preview frame 降頻做 MediaPipe
        //   分析（analysisFallbackFromPreview），把串流數壓到 2 條，recorder 才收得到 frame。
        //   預備階段先只跑 preview-only request（不餵 recorder），start 時才把 recorder 加入。
        val surfaces = listOf(pr.surface, rec.surface)
        try {
            cam.createCaptureSession(surfaces, object : CameraCaptureSession.StateCallback() {
                override fun onConfigured(s: CameraCaptureSession) {
                    captureSession = s
                    analysisFallbackFromPreview = true   // 錄製期間骨架改吃 preview frame
                    issuePreviewOnly(s, cam, pr.surface)
                    preparedRecPath = path
                    releaseOp("prepareForRecording")
                    Log.d(TAG, "prepareForRecording ✅ session ready (2-stream) for: $path")
                    mainHandler.post { result.success(null) }
                }
                override fun onConfigureFailed(s: CameraCaptureSession) {
                    runCatching { rec.release() }; mediaRecorder = null; preparedRecPath = null
                    releaseOp("prepareForRecording")
                    Log.w(TAG, "prepareForRecording ❌ onConfigureFailed → recover")
                    mainHandler.post { result.error("prep_session_failed", "Prepare session failed", null) }
                    recoverCamera()
                }
            }, cameraHandler)
        } catch (e: Exception) {
            runCatching { rec.release() }; mediaRecorder = null; preparedRecPath = null
            releaseOp("prepareForRecording")
            Log.e(TAG, "prepareForRecording createCaptureSession exception → recover: $e")
            mainHandler.post { result.error("prep_session_exception", e.message, null) }
            recoverCamera()
        }
    }

    /**
     * 安全停止目前 CaptureSession（不 close CameraDevice）。
     * 在重建 session 前呼叫，防止 waitUntilIdle timeout。
     */
    private fun stopSessionSafely() {
        val s = captureSession ?: return
        runCatching { s.stopRepeating() }
        runCatching { s.abortCaptures() }
        runCatching { s.close() }
        captureSession = null
        Log.d(TAG, "stopSessionSafely: old session closed")
    }

    /**
     * 開始錄製。
     *
     * 若已呼叫 prepareForRecording(path) 且 session 已就緒：
     *   → 只執行 rec.start() + 切換 CaptureRequest target，**不重建 Session，無閃爍**。
     *
     * 若未預備（fallback）：
     *   → 舊流程（建立新 Session），可能閃爍。
     */
    private fun startRecordingOnCamera(path: String, result: MethodChannel.Result) {
        Log.d(TAG, "startRecordingOnCamera: enter path=$path " +
            "prepared=$preparedRecPath rec=${mediaRecorder != null} session=${captureSession != null}")

        val cam = cameraDevice   ?: run { releaseOp("startRecording"); mainHandler.post { result.error("no_camera",   "Camera not open",    null) }; return }
        val pr  = previewReader  ?: run { releaseOp("startRecording"); mainHandler.post { result.error("no_preview",  "Preview reader N/A", null) }; return }

        // ── ★ 零閃爍路徑：session 已預備，直接開始錄製 ────────────────────────
        val preparedRec = mediaRecorder
        if (preparedRecPath == path && preparedRec != null && captureSession != null) {
            Log.d(TAG, "startRecordingOnCamera: use pre-warmed path")
            val s   = captureSession!!
            val rec = preparedRec
            try {
                // ★ 2-stream：把 recorder 加入 repeating request（preview+recorder），分析吃 preview。
                Log.d(TAG, "startRecordingOnCamera: before issueRecordRequest (2-stream)")
                analysisFallbackFromPreview = true
                issueRecordRequest(s, cam, pr.surface, rec.surface)
                Log.d(TAG, "startRecordingOnCamera: before rec.start")
                rec.start()
                Log.d(TAG, "startRecordingOnCamera: after rec.start")
                isRecording = true
                preparedRecPath = null
                releaseOp("startRecording")
                Log.d(TAG, "startRecording ✅ (no-flash, pre-warmed): $path")
                mainHandler.post { result.success(null) }
            } catch (e: Exception) {
                releaseOp("startRecording")
                Log.e(TAG, "startRecording (pre-warmed) failed: $e")
                mainHandler.post { result.error("recorder_error", e.message, null) }
            }
            return
        }

        // ── Fallback：未預備，先 stop 舊 session 再以 2-stream 重建 ────────────
        //   ★ 直接走 preview+recorder 兩條串流（不含 analysisReader），避免 3-stream
        //     餓死 recorder（-1007）。錄製期間骨架改吃 preview frame。
        Log.w(TAG, "startRecording: no pre-warm for $path → fallback (2-stream, may flash)")

        runCatching { mediaRecorder?.release() }; mediaRecorder = null; preparedRecPath = null

        // ★ 先停掉舊 session，防止 waitUntilIdle timeout
        stopSessionSafely()

        val rec = buildRecorder(path) ?: run {
            releaseOp("startRecording")
            mainHandler.post { result.error("recorder_error", "MediaRecorder prepare failed", null) }
            return
        }
        mediaRecorder = rec
        val recSurface = rec.surface

        try {
            val surfaces = listOf(pr.surface, recSurface)
            cam.createCaptureSession(surfaces, object : CameraCaptureSession.StateCallback() {
                override fun onConfigured(s: CameraCaptureSession) {
                    captureSession = s
                    analysisFallbackFromPreview = true
                    issueRecordRequest(s, cam, pr.surface, recSurface)
                    rec.start(); isRecording = true
                    releaseOp("startRecording")
                    Log.d(TAG, "startRecording (fallback 2-stream): $path ${recordW}×${recordH}")
                    mainHandler.post { result.success(null) }
                }
                override fun onConfigureFailed(s: CameraCaptureSession) {
                    runCatching { rec.release() }; mediaRecorder = null
                    releaseOp("startRecording")
                    Log.w(TAG, "startRecording 2-stream session failed → recover")
                    mainHandler.post { result.error("rec_session_failed", "Recording session failed", null) }
                    recoverCamera()
                }
            }, cameraHandler)
        } catch (e: Exception) {
            runCatching { rec.release() }; mediaRecorder = null
            releaseOp("startRecording")
            Log.e(TAG, "startRecording createCaptureSession exception → recover: $e")
            mainHandler.post { result.error("rec_session_exception", e.message, null) }
            recoverCamera()
        }
    }

    /**
     * MediaRecorder 初始化共用函式。
     *
     * ★ 寫入暫存檔 `finalPath + ".recording"`，stop() 成功後才 rename 成 finalPath。
     *   如此 prewarm（prepare 但未 start）或 stop 失敗時，最終 swing.mp4 不會出現壞檔。
     */
    private fun buildRecorder(finalPath: String): MediaRecorder? = try {
        val tmpPath = "$finalPath.recording"
        runCatching { java.io.File(tmpPath).delete() }   // 清掉殘留的舊暫存檔
        recordingFinalPath = finalPath
        recordingTmpPath   = tmpPath
        MediaRecorder().apply {
            // ★ CAMCORDER 音源（錄影調諧、減少 AGC 把底噪拉滿）；
            //   不設定取樣率/位元率時 MediaRecorder 預設為 8kHz/12kbps，
            //   擊球瞬態會被噪音淹沒、無法用於音訊擊球偵測。
            setAudioSource(MediaRecorder.AudioSource.CAMCORDER)
            setVideoSource(MediaRecorder.VideoSource.SURFACE)
            setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            setOutputFile(tmpPath)
            setVideoEncoder(MediaRecorder.VideoEncoder.H264)
            setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            setAudioSamplingRate(44100)
            setAudioEncodingBitRate(128_000)
            setAudioChannels(1)
            setVideoSize(recordW, recordH)         // 橫式：1920×1080 或 1280×720
            setVideoFrameRate(recordFps)
            setVideoEncodingBitRate(if (recordW >= 1920) 15_000_000 else 8_000_000)
            setOrientationHint(sensorOrientation)
            // ★ 中斷防護：檔案超過 2GB 自動安全停止，避免寫到磁碟滿造成壞檔
            setMaxFileSize(2L * 1024 * 1024 * 1024)
            setOnErrorListener { _, what, extra ->
                Log.e(TAG, "MediaRecorder onError what=$what extra=$extra")
            }
            setOnInfoListener { _, what, _ ->
                if (what == MediaRecorder.MEDIA_RECORDER_INFO_MAX_FILESIZE_APPROACHING ||
                    what == MediaRecorder.MEDIA_RECORDER_INFO_MAX_FILESIZE_REACHED) {
                    Log.w(TAG, "MediaRecorder max filesize reached → auto stop")
                    cameraHandler.post { stopRecordingOnCamera(null) }
                }
            }
            prepare()
        }
    } catch (e: Exception) {
        Log.e(TAG, "buildRecorder failed: $e")
        recordingTmpPath = null; recordingFinalPath = null
        null
    }

    /**
     * 預備階段的 preview-only repeating request（只餵 preview，不餵 recorder）。
     * session 已含 recorder surface，但尚未把它加入 request → 不會觸發 encoder。
     */
    private fun issuePreviewOnly(s: CameraCaptureSession, cam: CameraDevice, preview: Surface) {
        try {
            val req = cam.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW).apply {
                addTarget(preview)
                set(CaptureRequest.CONTROL_AF_MODE,  CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_VIDEO)
                set(CaptureRequest.CONTROL_AE_MODE,  CaptureRequest.CONTROL_AE_MODE_ON)
                set(CaptureRequest.CONTROL_AWB_MODE, CaptureRequest.CONTROL_AWB_MODE_AUTO)
                set(CaptureRequest.CONTROL_AE_TARGET_FPS_RANGE, previewFpsRange)
                applyStabilizationOff()
            }
            s.setRepeatingRequest(req.build(), null, cameraHandler)
            previewFrameSeq = 0
            Log.d(TAG, "issuePreviewOnly: 1 target fps=$previewFpsRange")
        } catch (e: Exception) { Log.w(TAG, "issuePreviewOnly: $e") }
    }

    /**
     * 錄製中的 repeating request：preview + recorder 兩條串流（不含 analysisReader）。
     * 掛上 recordCaptureCallback 以確認 recorder surface 真的有收到 frame（診斷 -1007）。
     */
    private fun issueRecordRequest(
        s: CameraCaptureSession, cam: CameraDevice,
        preview: Surface, recorder: Surface,
    ) {
        try {
            val req = cam.createCaptureRequest(CameraDevice.TEMPLATE_RECORD).apply {
                addTarget(preview); addTarget(recorder)
                set(CaptureRequest.CONTROL_AF_MODE,  CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_VIDEO)
                set(CaptureRequest.CONTROL_AE_MODE,  CaptureRequest.CONTROL_AE_MODE_ON)
                set(CaptureRequest.CONTROL_AWB_MODE, CaptureRequest.CONTROL_AWB_MODE_AUTO)
                set(CaptureRequest.CONTROL_AE_TARGET_FPS_RANGE, previewFpsRange)
                applyStabilizationOff()
            }
            s.setRepeatingRequest(req.build(), recordCaptureCallback, cameraHandler)
            lastAnalysisFrameAtMs = SystemClock.uptimeMillis()
            previewFrameSeq = 0
            recordCaptureCount = 0
            recordBufferLost = 0
            Log.d(TAG, "issueRecordRequest: 2 targets (preview+recorder) fps=$previewFpsRange")
        } catch (e: Exception) { Log.w(TAG, "issueRecordRequest: $e") }
    }

    // ── 診斷：錄製請求的 frame 計數 / 掉幀偵測 ────────────────────────────────────
    //   用來確認 recorder surface 是否真的有收到 frame（-1007 = muxer 沒收到任何 frame）。
    @Volatile private var recordCaptureCount = 0
    @Volatile private var recordBufferLost   = 0
    private val recordCaptureCallback = object : CameraCaptureSession.CaptureCallback() {
        override fun onCaptureCompleted(
            session: CameraCaptureSession,
            request: CaptureRequest,
            result: android.hardware.camera2.TotalCaptureResult,
        ) {
            val n = ++recordCaptureCount
            if (n == 1 || n % 30 == 0) Log.d(TAG, "recordCapture: completed=$n lost=$recordBufferLost")
        }
        override fun onCaptureBufferLost(
            session: CameraCaptureSession,
            request: CaptureRequest,
            target: Surface,
            frameNumber: Long,
        ) {
            recordBufferLost++
            val isRec = target == mediaRecorder?.surface
            Log.w(TAG, "recordCapture: BUFFER LOST frame=$frameNumber isRecorderSurface=$isRec total=$recordBufferLost")
        }
    }

    // ── Stop recording ────────────────────────────────────────────────────────

    private fun stopRecordingOnCamera(result: MethodChannel.Result?) {
        if (!isRecording) { mainHandler.post { runCatching { result?.success(null) } }; return }
        val cam = cameraDevice

        // ── ★ 正確的關閉順序（關鍵修復）─────────────────────────────────────
        //   1. stopRepeating()：停止餵 recorder surface（但 session 仍開著）
        //   2. rec.stop() + release()：讓 recorder 在「input surface 仍有效」時封口
        //   3. 之後才 session.close()
        //
        //   若先 close session 再 rec.stop()（先前的順序），recorder 的 input surface
        //   會被 session 拆掉 → stop() -1007 失敗，且突兀的 teardown 會讓 HAL drain
        //   卡死（waitUntilIdle Connection timed out）→ 相機進入 serious error 無法復原。
        try { captureSession?.stopRepeating() } catch (_: Exception) {}

        // ── stop()：失敗 = 檔案損壞（典型 missing stsd），刪暫存檔、回報錯誤 ──
        val rec = mediaRecorder
        val tmp = recordingTmpPath
        val fin = recordingFinalPath
        var recordOk = false
        var stopThrew = false   // ★ stop() 拋例外 = recorder/HAL 異常封口，session 已不可信
        try {
            rec?.stop()
            recordOk = true
        } catch (e: RuntimeException) {
            // 錄製時間過短 / recorder surface 未收到任何 frame → 輸出檔不完整
            stopThrew = true
            Log.e(TAG, "rec.stop FAILED, output is corrupt → delete: $e")
            runCatching { tmp?.let { java.io.File(it).delete() } }
        } catch (e: Exception) {
            stopThrew = true
            Log.e(TAG, "rec.stop unexpected: $e")
            runCatching { tmp?.let { java.io.File(it).delete() } }
        }
        runCatching { rec?.release() }
        mediaRecorder = null; isRecording = false; preparedRecPath = null

        // recorder 停妥後才關閉 session（順序見上方說明）
        try { captureSession?.close() } catch (_: Exception) {}
        captureSession = null

        // stop() 成功 → 暫存檔原子 rename 成最終 swing.mp4（播放端只會拿到完整檔）
        if (recordOk && tmp != null && fin != null) {
            val ok = runCatching {
                val ft = java.io.File(tmp)
                val ff = java.io.File(fin)
                runCatching { ff.delete() }   // 確保目標不存在，rename 才會成功
                ft.length() > 0L && ft.renameTo(ff)
            }.getOrDefault(false)
            if (!ok) {
                Log.e(TAG, "rename tmp→final failed or empty file → treat as failure")
                runCatching { java.io.File(tmp).delete() }
                recordOk = false
            }
        }
        recordingTmpPath = null; recordingFinalPath = null

        // 回報真實結果給 Dart：成功回 success(true)，失敗回 error，讓上層不要播放/上傳壞檔
        fun reply() {
            mainHandler.post {
                runCatching {
                    if (recordOk) result?.success(true)
                    else result?.error("record_failed", "Recording produced no valid frames", null)
                }
            }
        }

        val pr = previewReader
        val ar = analysisReader
        if (cam == null || pr == null) { reply(); return }

        // ── ★ stop() 拋例外時，HAL 已進入 serious-error（drain 卡死）。此時若再對同一
        //   CameraDevice createCaptureSession，會 block 3s 後拋 waitUntilIdle timeout(-110)，
        //   造成 Dart 端 stopRecording >6s，且每次都重蹈覆轍。直接走完整 close+reopen 復原，
        //   不浪費那 3 秒、也不再戳已壞的 HAL。 ──────────────────────────────────────
        if (stopThrew) {
            Log.w(TAG, "stopRecording: rec.stop threw → skip rebuild, recoverCamera directly")
            captureSession = null
            reply()
            recoverCamera()
            return
        }

        // 錄製結束後重建預覽 session（含 analysisReader）
        // ★ 必須 try/catch：createCaptureSession 在 CameraThread 同步階段可能拋
        //   CameraAccessException（waitUntilIdle timeout），未捕捉會 FATAL crash 整個 App。
        val surfaces = listOfNotNull(pr.surface, ar?.surface)
        try {
            cam.createCaptureSession(surfaces, object : CameraCaptureSession.StateCallback() {
                override fun onConfigured(s: CameraCaptureSession) {
                    captureSession = s
                    if (ar != null) issuePreviewRequest(s, cam, pr.surface, ar.surface)
                    Log.d(TAG, "stopRecording: preview session rebuilt ok=$recordOk")
                    reply()
                }
                override fun onConfigureFailed(s: CameraCaptureSession) {
                    Log.w(TAG, "stopRecording: preview session reconfigure failed → recover")
                    captureSession = null
                    reply()
                    recoverCamera()
                }
            }, cameraHandler)
        } catch (e: Exception) {
            // 相機 HAL 卡住（drain timeout / serious error）：先回報結果避免 Dart 卡住，
            // 再自動 close + 重開相機復原（沿用同一 texture，使用者無感）。
            Log.e(TAG, "stopRecording: createCaptureSession threw → recover: $e")
            captureSession = null
            reply()
            recoverCamera()
        }
    }

    // ── Display path：NV21 → Bitmap → 骨架 → SurfaceProducer ─────────────────

    private fun onDisplayNv21(
        nv21: ByteArray, imgW: Int, imgH: Int,
        rotation: Int, isFront: Boolean,
        producer: TextureRegistry.SurfaceProducer,
    ) {
        // ★ isRendering 已由 image listener 設為 true（throttle gate），此處不再重複檢查/設定，
        //   否則 early-return 會跳過 finally，使 isRendering 永久卡 true → 預覽凍結。
        try {
            // NV21 → JPEG → Bitmap（quality 50 ≈ 8ms）
            val yuvImg = YuvImage(nv21, ImageFormat.NV21, imgW, imgH, null)
            val out    = ByteArrayOutputStream()
            yuvImg.compressToJpeg(Rect(0, 0, imgW, imgH), JPEG_QUALITY_PREVIEW, out)
            val raw = BitmapFactory.decodeByteArray(out.toByteArray(), 0, out.size()) ?: return

            // 旋轉至直式顯示方向
            val fullBmp = if (rotation == 0 && !isFront) raw else {
                val m = Matrix().apply {
                    postRotate(rotation.toFloat())
                    if (isFront) postScale(-1f, 1f, raw.width / 2f, raw.height / 2f)
                }
                Bitmap.createBitmap(raw, 0, 0, raw.width, raw.height, m, true)
                    .also { raw.recycle() }
            }

            // 骨架疊加（前鏡頭 display bitmap 已水平翻轉，但 landmarks 座標來自未翻轉的 analysis bitmap，需補 mirrorX）
            val lms = lastLandmarks
            if (lms.isNotEmpty()) {
                SkeletonRenderer.draw(android.graphics.Canvas(fullBmp), lms, fullBmp.width, fullBmp.height, mirrorX = isFront)
            }

            // 寫入 Flutter Texture
            val surface = producer.getSurface()
            if (surface.isValid) {
                try {
                    val c  = surface.lockCanvas(null)
                    val tw = c.width.toFloat();  val th = c.height.toFloat()
                    val bw = fullBmp.width.toFloat(); val bh = fullBmp.height.toFloat()
                    val sc = maxOf(tw / bw, th / bh)
                    val dw = bw * sc; val dh = bh * sc
                    val lx = (tw - dw) / 2f; val ty = (th - dh) / 2f
                    if (lx != 0f || ty != 0f) {
                        Log.w(TAG, "canvas offset: bmp=${bw.toInt()}×${bh.toInt()} canvas=${tw.toInt()}×${th.toInt()} sc=${"%.3f".format(sc)} lx=${"%.1f".format(lx)} ty=${"%.1f".format(ty)}")
                    }
                    c.drawBitmap(fullBmp, null, android.graphics.RectF(lx, ty, lx+dw, ty+dh), null)
                    surface.unlockCanvasAndPost(c)
                } catch (e: Exception) { Log.w(TAG, "lockCanvas: $e") }
            }

            fullBmp.recycle()

        } catch (e: Exception) {
            Log.w(TAG, "onDisplayNv21: $e")
        } finally {
            isRendering = false
        }
    }

    // ── Analysis path：NV21 → Bitmap → MediaPipe ──────────────────────────────
    // 獨立於顯示路徑，輸入已是 640×360 小幀，轉換負擔低

    // ── Analysis in-flight permits（取代舊 isAnalyzing boolean gate）──────────
    // 允許 MAX_ANALYSIS_IN_FLIGHT 幀同時在管線內：一幀在 analysisThread 轉換時，
    // 上一幀可同時在 GPU 推論 → CPU/GPU 重疊，吞吐 ≈ 1/max(convert, infer)。
    private val analysisInFlight = java.util.concurrent.atomic.AtomicInteger(0)
    @Volatile private var lastPermitChangeMs = 0L

    private fun tryAcquireAnalysisPermit(): Boolean {
        while (true) {
            val cur = analysisInFlight.get()
            if (cur >= MAX_ANALYSIS_IN_FLIGHT) return false
            if (analysisInFlight.compareAndSet(cur, cur + 1)) {
                lastPermitChangeMs = SystemClock.uptimeMillis()
                return true
            }
        }
    }

    private fun releaseAnalysisPermit() {
        // 下限 0：重複釋放（error listener 與 result listener 雙回呼等）不得使計數變負
        while (true) {
            val cur = analysisInFlight.get()
            if (cur <= 0) return
            if (analysisInFlight.compareAndSet(cur, cur - 1)) {
                lastPermitChangeMs = SystemClock.uptimeMillis()
                return
            }
        }
    }

    /**
     * Watchdog：permit 全滿且超過 PERMIT_STALL_RESET_MS 無任何變化
     * → MediaPipe 靜默丟幀（FlowLimiter 不回呼任何 listener）造成洩漏，強制歸零。
     * 在 image listener（每幀都會進來）呼叫，無需額外 timer。
     */
    private fun watchdogResetStalledPermits() {
        if (analysisInFlight.get() < MAX_ANALYSIS_IN_FLIGHT) return
        val now = SystemClock.uptimeMillis()
        if (now - lastPermitChangeMs <= PERMIT_STALL_RESET_MS) return
        Log.w(TAG, "analysis permits stalled ${now - lastPermitChangeMs}ms → force reset " +
            "(MediaPipe 疑似丟幀未回呼)")
        analysisInFlight.set(0)
        lastPermitChangeMs = now
    }

    // ★ 單調遞增時間戳：確保跨 Normal/Shot 模式、跨錄製 session，MediaPipe PTS 絕不歸零或倒退
    //   使用感測器硬體時間戳（img.timestamp，開機後奈秒），比 System.currentTimeMillis() 更可靠
    @Volatile private var lastAnalysisTsMs = 0L

    private fun onAnalysisNv21(
        nv21: ByteArray, imgW: Int, imgH: Int,
        rotation: Int, isFront: Boolean,
        imgTimestampNs: Long = 0L,   // ★ 感測器時間戳（ns）；0 表示使用 SystemClock fallback
    ) {
        // ★ permit 已由 image listener 取得（tryAcquireAnalysisPermit）。
        //   釋放契約：本函式內任何「未把幀送進 detectAsync」的路徑（例外、decode
        //   失敗）都必須自行 releaseAnalysisPermit()；成功送出後由 poseHelper.onFrameDone 釋放。
        try {
            val t0 = SystemClock.uptimeMillis()
            // ★ PTS 計算：確保跨切片、跨 Shot 模式時間戳線性遞增
            //   優先使用感測器時間戳（最可靠），fallback 到 SystemClock.uptimeMillis()
            //   嚴禁使用 System.currentTimeMillis()（可能因 NTP 修正向後跳）
            val tsMs = if (imgTimestampNs > 0L) {
                imgTimestampNs / 1_000_000L
            } else {
                SystemClock.uptimeMillis()
            }
            // 確保單調遞增（防止同一毫秒多幀 or 感測器時間戳異常）
            val monotonicTsMs = maxOf(tsMs, lastAnalysisTsMs + 1L)
            lastAnalysisTsMs = monotonicTsMs

            // ★ JNI 直出：NV21 → 旋轉 → 縮放 → letterbox → RGBA 一步完成（~2-3ms），
            //   取代 JPEG 往返 + 多次 Bitmap 配置（~25ms）。前鏡頭不做水平翻轉，
            //   landmarks 在繪圖時補 mirrorX（與舊路徑一致）。
            val lbox = MediaPipePoseHelper.LBOX_SIZE
            val pw = if (rotation == 90 || rotation == 270) imgH else imgW
            val ph = if (rotation == 90 || rotation == 270) imgW else imgH
            val scale = minOf(lbox.toFloat() / pw, lbox.toFloat() / ph)
            val contentW = (pw * scale).toInt().coerceAtLeast(1)
            val contentH = (ph * scale).toInt().coerceAtLeast(1)
            val padX = (lbox - contentW) / 2
            val padY = (lbox - contentH) / 2

            val rgbaBuf = poseHelper.acquireRgbaBuffer()
            try {
                NativeLib.nv21ToRgbaLetterbox(
                    nv21, imgW, imgH, rotation,
                    lbox, contentW, contentH, padX, padY, rgbaBuf,
                )
            } catch (e: Throwable) {
                // JNI 失敗：buffer 歸還 + 釋放 permit（幀不會進 detectAsyncRgba）
                poseHelper.releaseRgbaBuffer(rgbaBuf)
                Log.w(TAG, "nv21ToRgbaLetterbox: $e")
                releaseAnalysisPermit()
                return
            }

            // 轉換段 timing（JNI 直出），統計由 poseHelper 彙整輸出
            poseHelper.noteConvertMs(SystemClock.uptimeMillis() - t0)

            poseHelper.detectAsyncRgba(
                rgbaBuf, contentW, contentH, padX, padY, monotonicTsMs)
            // ★ permit 由 poseHelper.onFrameDone 釋放（detectAsyncRgba 內所有路徑均保證回呼）

        } catch (e: Exception) {
            Log.w(TAG, "onAnalysisNv21: $e")
            releaseAnalysisPermit()  // 例外路徑：detectAsync 未送出，需在此釋放
        }
    }

    // ── YUV_420_888 → NV21（快速 byte 複製，不做 Bitmap 轉換）────────────────
    // ★ 必須在持有 Image 期間呼叫，之後立即 close Image。

    @Volatile private var yuvDebugLogged = false
    private fun yuv420ToNv21Fast(image: Image): ByteArray {
        val w = image.width; val h = image.height
        val nv21 = ByteArray(w * h * 3 / 2)
        val yPlane = image.planes[0]
        val uPlane = image.planes[1]
        val vPlane = image.planes[2]
        val yBuf   = yPlane.buffer
        var offset = 0

        if (!yuvDebugLogged) {
            yuvDebugLogged = true
            Log.w(TAG, "YUVDBG ${w}x$h " +
                "Y[row=${yPlane.rowStride},px=${yPlane.pixelStride},cap=${yBuf.capacity()}] " +
                "U[row=${uPlane.rowStride},px=${uPlane.pixelStride},cap=${uPlane.buffer.capacity()}] " +
                "V[row=${vPlane.rowStride},px=${vPlane.pixelStride},cap=${vPlane.buffer.capacity()}]")
            val ub = uPlane.buffer; val vb = vPlane.buffer
            ub.position(0); vb.position(0)
            val us = IntArray(6) { if (ub.remaining() > 0) ub.get().toInt() and 0xFF else -1 }
            val vs = IntArray(6) { if (vb.remaining() > 0) vb.get().toInt() and 0xFF else -1 }
            Log.w(TAG, "YUVDBG U-samples=${us.joinToString()} V-samples=${vs.joinToString()}")
        }

        for (row in 0 until h) {
            yBuf.position(row * yPlane.rowStride)
            yBuf.get(nv21, offset, w); offset += w
        }
        for (row in 0 until h / 2) {
            for (col in 0 until w / 2) {
                vPlane.buffer.position(row * vPlane.rowStride + col * vPlane.pixelStride)
                nv21[offset++] = vPlane.buffer.get()
                uPlane.buffer.position(row * uPlane.rowStride + col * uPlane.pixelStride)
                nv21[offset++] = uPlane.buffer.get()
            }
        }
        return nv21
    }

    // ── Zoom ─────────────────────────────────────────────────────────────────

    private fun applyZoom(frac: Float) {
        val s   = captureSession ?: return
        val cam = cameraDevice   ?: return
        val id  = currentCameraId ?: return
        val chars  = cameraManager.getCameraCharacteristics(id)
        val maxZ   = chars.get(CameraCharacteristics.SCALER_AVAILABLE_MAX_DIGITAL_ZOOM) ?: 1f
        val sensor = chars.get(CameraCharacteristics.SENSOR_INFO_ACTIVE_ARRAY_SIZE) ?: return
        val ratio  = 1f + frac * (maxZ - 1f)
        val cropW  = (sensor.width()  / ratio).toInt()
        val cropH  = (sensor.height() / ratio).toInt()
        val cropX  = (sensor.width()  - cropW) / 2
        val cropY  = (sensor.height() - cropH) / 2
        val pr = previewReader ?: return
        val ar = analysisReader

        val tpl = if (isRecording) CameraDevice.TEMPLATE_RECORD else CameraDevice.TEMPLATE_PREVIEW
        val surfaces = buildList<Surface> {
            add(pr.surface)
            ar?.let { add(it.surface) }
            if (isRecording) mediaRecorder?.surface?.let { add(it) }
        }
        try {
            val req = cam.createCaptureRequest(tpl).apply {
                surfaces.forEach { addTarget(it) }
                set(CaptureRequest.SCALER_CROP_REGION,
                    Rect(cropX, cropY, cropX + cropW, cropY + cropH))
                set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_VIDEO)
                set(CaptureRequest.CONTROL_AE_MODE, CaptureRequest.CONTROL_AE_MODE_ON)
                set(CaptureRequest.CONTROL_AE_TARGET_FPS_RANGE, previewFpsRange)
                applyStabilizationOff()
            }
            s.setRepeatingRequest(req.build(), null, cameraHandler)
        } catch (e: Exception) { Log.w(TAG, "applyZoom: $e") }
    }

    // ── Clean close（解決競態問題）────────────────────────────────────────────
    // 順序：① 解除 listener → ② 停止 capture → ③ 關 session → ④ 關 readers → ⑤ 關 device

    private fun closeSessionAndCamera() {
        // ① 先解除 listener，阻止新的 image 在關閉期間抵達
        runCatching { previewReader?.setOnImageAvailableListener(null, null)  }
        runCatching { analysisReader?.setOnImageAvailableListener(null, null) }

        // ② 停止所有 in-flight capture request
        runCatching { captureSession?.stopRepeating() }
        runCatching { captureSession?.abortCaptures()  }

        // ③ 關閉 session（必須在 readers 和 device 之前）
        runCatching { captureSession?.close()  }; captureSession = null

        // ④ 關閉 ImageReaders
        runCatching { previewReader?.close()   }; previewReader  = null
        runCatching { analysisReader?.close()  }; analysisReader = null

        // ⑤ 關閉 CameraDevice（最後關）
        runCatching { cameraDevice?.close()    }; cameraDevice   = null

        // MediaRecorder 清理
        runCatching { mediaRecorder?.release() }; mediaRecorder  = null
        // 未完成錄製（prewarm 後直接關閉 / 切鏡頭）：刪掉未封口的暫存檔，避免殘留
        runCatching { recordingTmpPath?.let { java.io.File(it).delete() } }
        recordingTmpPath = null; recordingFinalPath = null
        isRecording = false
        preparedRecPath = null
        isPreparingRecording = false
    }

    // 錄影頁 dispose 呼叫：只關 session/camera/surface，thread 和 poseHelper 保持活著
    private fun closeOnCamera() {
        Log.d(TAG, "closeOnCamera: close camera/session only")
        closeSessionAndCamera()
        lastLandmarks = emptyList()
        analysisFallbackFromPreview = false
        previewFrameSeq = 0
        lastAnalysisFrameAtMs = 0L
        lastAnalysisTsMs = 0L
        mainHandler.post {
            runCatching { surfaceProducer?.release() }
            surfaceProducer = null
        }
    }

    // App / Plugin 真正銷毀時呼叫：完整關閉包含 thread 和 poseHelper
    private fun destroyOnCamera() {
        Log.d(TAG, "destroyOnCamera: full destroy")
        closeSessionAndCamera()
        runCatching { poseHelper.close() }
        lastLandmarks = emptyList()
        analysisFallbackFromPreview = false
        previewFrameSeq = 0
        lastAnalysisFrameAtMs = 0L
        lastAnalysisTsMs = 0L
        mainHandler.post {
            runCatching { surfaceProducer?.release() }
            surfaceProducer = null
        }
        runCatching { imageThread.quitSafely() }
        runCatching { renderThread.quitSafely() }
        runCatching { analysisThread.quitSafely() }
        runCatching { cameraThread.quitSafely() }
    }

    // ── CaptureRequest.Builder 擴充：停用 OIS + EIS ───────────────────────────
    // 防止硬體穩定裁剪導致骨架座標偏移。stabEnabled 僅保留 API 相容性，不影響實際行為。

    private fun CaptureRequest.Builder.applyStabilizationOff() {
        set(CaptureRequest.CONTROL_VIDEO_STABILIZATION_MODE,
            CaptureRequest.CONTROL_VIDEO_STABILIZATION_MODE_OFF)
        if (hasOis) {
            set(CaptureRequest.LENS_OPTICAL_STABILIZATION_MODE,
                CaptureRequest.LENS_OPTICAL_STABILIZATION_MODE_OFF)
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    /**
     * 從裝置支援的 AE FPS 範圍中，選取符合 targetFps 的固定幀率（lower == upper），
     * 防止 AE 自動降到 8fps。
     *
     * ★ 優先精準匹配 targetFps（使用者選 30 就鎖 30，選 60 就鎖 60），
     *   找不到才退而求其次選 >= targetFps 的最高上限。
     */
    private fun selectFpsRange(cameraId: String, targetFps: Int = 30): Range<Int> {
        val chars  = cameraManager.getCameraCharacteristics(cameraId)
        val ranges = chars.get(CameraCharacteristics.CONTROL_AE_AVAILABLE_TARGET_FPS_RANGES)
            ?: return Range(targetFps, targetFps)

        Log.d(TAG, "selectFpsRange: available = ${ranges.toList()} target=$targetFps")

        // 1. 精準固定幀率（lower == upper == targetFps）
        ranges.firstOrNull { it.lower == targetFps && it.upper == targetFps }?.let {
            Log.d(TAG, "selectFpsRange: exact fixed $it")
            return it
        }
        // 2. 60fps 要求但無精準固定 → 退回 30fps 固定（避免 AE 降頻）
        if (targetFps >= 60) {
            ranges.firstOrNull { it.lower == 30 && it.upper == 30 }?.let {
                Log.d(TAG, "selectFpsRange: 60 unavailable, fall back to fixed $it")
                return it
            }
        }
        // 3. Fallback：lower >= targetFps 的最高上限
        val fallback = ranges
            .filter { it.lower >= targetFps }
            .maxByOrNull { it.upper }
            ?: Range(targetFps, targetFps)
        Log.d(TAG, "selectFpsRange: fallback $fallback")
        return fallback
    }

    private fun findCameraId(facing: Int): String? =
        cameraManager.cameraIdList.firstOrNull { id ->
            cameraManager.getCameraCharacteristics(id)
                .get(CameraCharacteristics.LENS_FACING) == facing
        }

    private fun getSensorOrientation(id: String): Int =
        cameraManager.getCameraCharacteristics(id)
            .get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 90

    private fun checkStabilization(id: String): Boolean {
        val modes = cameraManager.getCameraCharacteristics(id)
            .get(CameraCharacteristics.CONTROL_AVAILABLE_VIDEO_STABILIZATION_MODES) ?: return false
        return CaptureRequest.CONTROL_VIDEO_STABILIZATION_MODE_ON in modes
    }

    private fun checkOis(id: String): Boolean {
        val modes = cameraManager.getCameraCharacteristics(id)
            .get(CameraCharacteristics.LENS_INFO_AVAILABLE_OPTICAL_STABILIZATION) ?: return false
        return CaptureRequest.LENS_OPTICAL_STABILIZATION_MODE_ON in modes
    }

    /**
     * 從 HAL 支援的 YUV_420_888 輸出尺寸中挑選最接近 target 的尺寸。
     * ★ ImageReader 餵入不支援的尺寸是未定義行為：本機 HAL 會悄悄改吐 640×480，
     *   也有機型直接 configure 失敗。優先挑同長寬比、面積 ≥ target 的最小尺寸。
     */
    private fun selectYuvSize(id: String, targetW: Int, targetH: Int): Size {
        val sizes = cameraManager.getCameraCharacteristics(id)
            .get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
            ?.getOutputSizes(ImageFormat.YUV_420_888)
            ?.toList() ?: return Size(targetW, targetH)
        if (sizes.isEmpty()) return Size(targetW, targetH)
        sizes.firstOrNull { it.width == targetW && it.height == targetH }?.let { return it }

        val targetRatio = targetW.toFloat() / targetH
        val targetArea  = targetW.toLong() * targetH
        val sameRatio = sizes.filter {
            kotlin.math.abs(it.width.toFloat() / it.height - targetRatio) < 0.01f
        }
        val pool = sameRatio.ifEmpty { sizes }
        val atLeast = pool.filter { it.width.toLong() * it.height >= targetArea }
        val picked = (atLeast.ifEmpty { pool })
            .minByOrNull { kotlin.math.abs(it.width.toLong() * it.height - targetArea) }!!
        Log.w(TAG, "selectYuvSize: ${targetW}×$targetH unsupported → ${picked.width}×${picked.height}")
        return picked
    }
}