package com.aethertek.tekswing

import android.content.ContentValues
import android.content.Intent
import android.graphics.Bitmap
import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import android.util.Log
import android.view.KeyEvent
import android.view.WindowManager
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean


class MainActivity: FlutterActivity() {
    private val CHANNEL = "volume_button_channel"
    private val SHARE_CHANNEL = "share_intent_channel"
    private val KEEP_SCREEN_CHANNEL = "keep_screen_on_channel"
    private val AUDIO_EXTRACT_CHANNEL = "audio_extractor_channel"
    private val VIDEO_OVERLAY_CHANNEL = "video_overlay_channel"
    private val TRIMMER_CHANNEL = "com.example.golf_score_app/trimmer"
    private val SKELETON_OVERLAY_CHANNEL = "com.example.golf_score_app/skeleton_overlay"
    private val BALL_TRAJECTORY_CHANNEL = "com.example.golf_score_app/ball_trajectory"
    private val FRAME_EXTRACTOR_CHANNEL = "com.example.golf_score_app/frame_extractor"
    private val POSE_ANALYZER_CHANNEL = "com.example.golf_score_app/pose_analyzer"
    private val PROGRESS_CHANNEL = "com.example.golf_score_app/analysis_progress"
    private val TRANSCODER_CHANNEL = "com.example.golf_score_app/video_transcoder"
    private val GOLF_ANALYSIS_CHANNEL = "com.example.golf_score_app/golf_analysis"
    private val overlayExecutor = Executors.newSingleThreadExecutor()
    private val audioExtractorExecutor = Executors.newSingleThreadExecutor()
    private val skeletonExecutor = Executors.newSingleThreadExecutor()
    private val ballTrajExecutor = Executors.newSingleThreadExecutor()
    private val frameExtractorExecutor = Executors.newSingleThreadExecutor()
    private val transcoderExecutor = Executors.newSingleThreadExecutor()

    // SAF 資料夾選擇：儲存待處理的 MethodChannel.Result，等 Activity result 回來再 resolve
    @Volatile private var pendingFolderResult: io.flutter.plugin.common.MethodChannel.Result? = null
    @Volatile private var pendingFolderSrc: String? = null
    @Volatile private var pendingFolderFileName: String? = null
    private val REQUEST_FOLDER_PICK = 1001

    private val golfAnalysisExecutor = Executors.newSingleThreadExecutor()
    private val logTag = "MainActivity"

    // EventChannel sink：背景執行緒透過 sendProgress() 推送進度到 Dart
    @Volatile private var progressSink: EventChannel.EventSink? = null

    /**
     * 取消旗標：Dart 呼叫 cancel MethodChannel → 設為 true。
     * 各分析迴圈（姿勢分析、骨架渲染）週期性檢查此旗標並提前結束。
     * 每次新操作開始前由 Kotlin 端重設為 false。
     */
    val cancelFlag = AtomicBoolean(false)

    /** 從任意執行緒安全地推送進度事件到 Dart。*/
    private fun sendProgress(op: String, progress: Double, label: String,
                              current: Int = 0, total: Int = 0) {
        runOnUiThread {
            progressSink?.success(mapOf(
                "op"       to op,
                "progress" to progress,
                "label"    to label,
                "current"  to current,
                "total"    to total,
            ))
        }
    }
    private val videoTrimmer by lazy { VideoTrimmer(this) }
    private val skeletonRenderer by lazy { SkeletonOverlayRenderer(this) }
    private val ballBlobExtractor      by lazy { BallBlobExtractor() }
    private val trajectoryOverlayRenderer by lazy { TrajectoryOverlayRenderer() }
    private val ballYoloExtractor      by lazy {
        BallYoloExtractor(applicationContext.assets).also { it.tryLoadModel() }
    }
    
    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_FOLDER_PICK) return

        val result   = pendingFolderResult   ?: return
        val src      = pendingFolderSrc      ?: return
        val fileName = pendingFolderFileName ?: return
        pendingFolderResult = null; pendingFolderSrc = null; pendingFolderFileName = null

        if (resultCode != RESULT_OK || data?.data == null) {
            result.error("cancelled", "使用者取消選擇資料夾", null); return
        }
        val treeUri = data.data!!
        transcoderExecutor.execute {
            try {
                val savedUri = saveToPickedFolder(treeUri, src, fileName)
                runOnUiThread { result.success(savedUri) }
            } catch (e: Exception) {
                Log.e(logTag, "[pickFolderAndSave] 失敗: ${e.message}", e)
                runOnUiThread { result.error("save_failed", e.message, null) }
            }
        }
    }

    // 獨立 Camera2 channel：低解析度分析幀 + 錄製控制
    private var cameraRecorderChannel: CameraRecorderChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ── Camera2 錄製 + 分析 Channel ────────────────────────────
        cameraRecorderChannel = CameraRecorderChannel(
            this,
            flutterEngine.renderer,                      // TextureRegistry
            flutterEngine.dartExecutor.binaryMessenger,
        )

        // ── 分析進度 EventChannel ────────────────────────────────
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, PROGRESS_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    progressSink = events
                }
                override fun onCancel(arguments: Any?) {
                    progressSink = null
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { _, _ -> }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SHARE_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "shareToPackage") {
                    val packageName = call.argument<String>("packageName")
                    val filePath = call.argument<String>("filePath")
                    val mimeType = call.argument<String>("mimeType") ?: "video/*"
                    val text = call.argument<String>("text")

                    if (packageName.isNullOrBlank() || filePath.isNullOrBlank()) {
                        result.error("invalid_args", "缺少必要參數", null)
                        return@setMethodCallHandler
                    }

                    val file = File(filePath)
                    if (!file.exists()) {
                        result.error("file_not_found", "找不到指定影片檔案", null)
                        return@setMethodCallHandler
                    }

                    val uri: Uri = FileProvider.getUriForFile(
                        this,
                        "${applicationContext.packageName}.fileprovider",
                        file
                    )

                    val intent = Intent(Intent.ACTION_SEND).apply {
                        type = mimeType
                        setPackage(packageName)
                        putExtra(Intent.EXTRA_STREAM, uri)
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        if (!text.isNullOrEmpty()) {
                            putExtra(Intent.EXTRA_TEXT, text)
                        }
                    }

                    val resolveInfo = intent.resolveActivity(packageManager)
                    if (resolveInfo == null) {
                        result.success(false)
                        return@setMethodCallHandler
                    }

                    try {
                        grantUriPermission(
                            packageName,
                            uri,
                            Intent.FLAG_GRANT_READ_URI_PERMISSION
                        )
                        startActivity(intent)
                        result.success(true)
                    } catch (error: Exception) {
                        result.success(false)
                    }
                } else {
                    result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, KEEP_SCREEN_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "enable" -> {
                        // 於 UI 執行緒設置常亮旗標，避免錄影過程被系統休眠打斷
                        runOnUiThread {
                            window?.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        }
                        result.success(null)
                    }
                    "disable" -> {
                        // 還原旗標，返回其他頁面時即可恢復預設休眠
                        runOnUiThread {
                            window?.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AUDIO_EXTRACT_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "extractAudio") {
                    val videoPath = call.argument<String>("videoPath")
                    if (videoPath.isNullOrBlank()) {
                        result.error("invalid_args", "缺少必要的影片路徑參數", null)
                        return@setMethodCallHandler
                    }
                    audioExtractorExecutor.execute {
                        try {
                            val extraction = extractAudioToWav(videoPath)
                            runOnUiThread {
                                if (extraction == null) {
                                    // 無音訊軌 — 正常情況，以 no_audio=true 通知 Dart 端略過音訊分析
                                    result.success(mapOf("no_audio" to true, "path" to null))
                                } else {
                                    result.success(
                                        mapOf(
                                            "path" to extraction.path,
                                            "sampleRate" to extraction.sampleRate,
                                            "channels" to extraction.channelCount
                                        )
                                    )
                                }
                            }
                        } catch (error: Exception) {
                            Log.e(logTag, "音訊抽取失敗: ${error.message}", error)
                            runOnUiThread {
                                result.error("extract_failed", error.message, null)
                            }
                        }
                    }
                } else {
                    result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, VIDEO_OVERLAY_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "processVideo") {
                    val inputPath = call.argument<String>("inputPath")
                    val outputPath = call.argument<String>("outputPath")
                    val attachAvatar = call.argument<Boolean>("attachAvatar") ?: false
                    val avatarPath = call.argument<String>("avatarPath")
                    val attachCaption = call.argument<Boolean>("attachCaption") ?: false
                    val caption = call.argument<String>("caption") ?: ""

                    if (inputPath.isNullOrBlank() || outputPath.isNullOrBlank()) {
                        result.error("invalid_args", "缺少必要參數", null)
                        return@setMethodCallHandler
                    }

                    Log.i(
                        logTag,
                        "收到影片覆蓋請求，input=$inputPath，output=$outputPath，頭像=$attachAvatar，字幕=$attachCaption"
                    )

                    overlayExecutor.execute {
                        try {
                            val processor = VideoOverlayProcessor(applicationContext)
                            val finalPath = processor.process(
                                inputPath = inputPath,
                                outputPath = outputPath,
                                attachAvatar = attachAvatar,
                                avatarPath = avatarPath,
                                attachCaption = attachCaption,
                                captionText = caption
                            )
                            Log.i(logTag, "覆蓋流程成功，回傳路徑=$finalPath")
                            runOnUiThread { result.success(finalPath) }
                        } catch (error: Exception) {
                            Log.e(logTag, "覆蓋流程失敗：${error.message}", error)
                            runOnUiThread {
                                result.error("overlay_failed", error.message, null)
                            }
                        }
                    }
                } else {
                    result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, TRIMMER_CHANNEL)
            .setMethodCallHandler { call, result ->
                videoTrimmer.handle(call, result)
            }
        // ── 影片轉碼（匯入時統一轉為標準 H.264 MP4）─────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, TRANSCODER_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method != "transcodeToMp4") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val srcPath = call.argument<String>("srcPath")
                val dstPath = call.argument<String>("dstPath")
                if (srcPath.isNullOrBlank() || dstPath.isNullOrBlank()) {
                    result.error("invalid_args", "缺少 srcPath / dstPath", null)
                    return@setMethodCallHandler
                }
                transcoderExecutor.execute {
                    try {
                        val outPath = VideoTranscoder().process(srcPath, dstPath, onProgress = ::sendProgress)
                        runOnUiThread { result.success(outPath) }
                    } catch (e: Exception) {
                        Log.e(logTag, "轉碼失敗: ${e.message}", e)
                        runOnUiThread { result.error("transcode_failed", e.message, null) }
                    }
                }
            }
        // ── 影片匯出到 Downloads ────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.example.golf_score_app/video_export")
            .setMethodCallHandler { call, result ->
                val srcPath  = call.argument<String>("srcPath")
                val fileName = call.argument<String>("fileName")
                when (call.method) {
                    "saveToDownloads" -> {
                        if (srcPath.isNullOrBlank() || fileName.isNullOrBlank()) {
                            result.error("invalid_args", "缺少 srcPath / fileName", null); return@setMethodCallHandler
                        }
                        transcoderExecutor.execute {
                            try {
                                val savedPath = saveVideoToDownloads(srcPath, fileName)
                                runOnUiThread { result.success(savedPath) }
                            } catch (e: Exception) {
                                Log.e(logTag, "saveToDownloads 失敗: ${e.message}", e)
                                runOnUiThread { result.error("save_failed", e.message, null) }
                            }
                        }
                    }
                    "pickFolderAndSave" -> {
                        if (srcPath.isNullOrBlank() || fileName.isNullOrBlank()) {
                            result.error("invalid_args", "缺少 srcPath / fileName", null); return@setMethodCallHandler
                        }
                        pendingFolderResult   = result
                        pendingFolderSrc      = srcPath
                        pendingFolderFileName = fileName
                        runOnUiThread {
                            @Suppress("DEPRECATION")
                            startActivityForResult(
                                Intent(Intent.ACTION_OPEN_DOCUMENT_TREE),
                                REQUEST_FOLDER_PICK
                            )
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SKELETON_OVERLAY_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "render") {
                    val clipPath = call.argument<String>("clipPath")
                    val csvPath = call.argument<String>("csvPath")
                    val startSec = call.argument<Double>("startSec") ?: 0.0
                    val outputPath = call.argument<String>("outputPath")
                    val quality = ExportQuality.fromString(call.argument<String>("quality"))

                    if (clipPath.isNullOrBlank() || csvPath.isNullOrBlank() || outputPath.isNullOrBlank()) {
                        result.error("invalid_args", "缺少必要參數", null)
                        return@setMethodCallHandler
                    }

                    cancelFlag.set(false)   // 新操作開始前重設取消旗標
                    skeletonExecutor.execute {
                        try {
                            val ok = skeletonRenderer.render(
                                clipPath = clipPath,
                                csvPath = csvPath,
                                startSec = startSec,
                                outputPath = outputPath,
                                quality = quality,
                                onProgress = ::sendProgress,
                                shouldCancel = { cancelFlag.get() },
                            )
                            if (!ok) {
                                Log.e(logTag, "骨架渲染失敗或已取消，不執行後續流程")
                            }
                            runOnUiThread { result.success(ok) }
                        } catch (e: Exception) {
                            Log.e(logTag, "骨架渲染失敗: ${e.message}", e)
                            runOnUiThread { result.error("render_failed", e.message, null) }
                        }
                    }
                } else {
                    result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BALL_TRAJECTORY_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {

                    // ── Step 1：Kotlin 像素層 → 每幀 blob ──────────────
                    "extractBlobs" -> {
                        val inputPath = call.argument<String>("inputPath")
                        if (inputPath.isNullOrBlank()) {
                            result.error("invalid_args", "缺少 inputPath", null)
                            return@setMethodCallHandler
                        }
                        ballTrajExecutor.execute {
                            try {
                                val data = ballBlobExtractor.extract(inputPath, onProgress = ::sendProgress)
                                runOnUiThread {
                                    if (data != null) result.success(data)
                                    else result.error("extract_failed", "blob 偵測失敗", null)
                                }
                            } catch (e: Exception) {
                                Log.e(logTag, "blob 偵測例外: ${e.message}", e)
                                runOnUiThread { result.error("extract_failed", e.message, null) }
                            }
                        }
                    }

                    // ── [Week 3] Step 1b：動態配置版本 → 每幀 blob ──────────────
                    "extractBlobsWithConfig" -> {
                        val inputPath = call.argument<String>("inputPath")
                        @Suppress("UNCHECKED_CAST")
                        val configMap = call.argument<Map<String, Any?>>("config")
                        val roiSize = call.argument<Int>("roiSize") ?: 400

                        if (inputPath.isNullOrBlank()) {
                            result.error("invalid_args", "缺少 inputPath", null)
                            return@setMethodCallHandler
                        }

                        ballTrajExecutor.execute {
                            try {
                                // 直接傳遞 configMap，extract() 會自己內部調用 DetectionConfig.fromMap
                                val data = ballBlobExtractor.extract(inputPath, configMap, onProgress = ::sendProgress)
                                
                                runOnUiThread {
                                    if (data != null) result.success(data)
                                    else result.error("extract_failed", "blob 偵測失敗", null)
                                }
                            } catch (e: Exception) {
                                Log.e(logTag, "blob 偵測例外: ${e.message}", e)
                                runOnUiThread { result.error("extract_failed", e.message, null) }
                            }
                        }
                    }

                    // ── [YOLOv8] TFLite 模式 → 每幀 blob ─────────────────
                    "extractBlobsYolo" -> {
                        val inputPath = call.argument<String>("inputPath")
                        if (inputPath.isNullOrBlank()) {
                            result.error("invalid_args", "缺少 inputPath", null)
                            return@setMethodCallHandler
                        }
                        // hitSec：由 Dart 傳入擊球時間（秒），用於 post-impact ROI 擴張與低信心閾值
                        val hitSec = call.argument<Double>("hitSec")
                        ballTrajExecutor.execute {
                            try {
                                val data = ballYoloExtractor.extract(inputPath, hitSec = hitSec, onProgress = ::sendProgress)
                                runOnUiThread {
                                    if (data != null) result.success(data)
                                    else result.error("yolo_failed", "YOLOv8 偵測失敗（模型未載入或解碼錯誤）", null)
                                }
                            } catch (e: Exception) {
                                Log.e(logTag, "YOLOv8 偵測例外: ${e.message}", e)
                                runOnUiThread { result.error("yolo_failed", e.message, null) }
                            }
                        }
                    }

                    // ── Step 2：Kotlin I/O 層 → 疊加軌跡 ───────────────
                    "renderOverlay" -> {
                        val inputPath  = call.argument<String>("inputPath")
                        val outputPath = call.argument<String>("outputPath")
                        @Suppress("UNCHECKED_CAST")
                        val trackPts   = call.argument<List<Map<String, Any>>>("trackPts")
                        val roiSize    = call.argument<Int>("roiSize") ?: 0  // 可選，預設 0（不繪製 ROI）
                        val quality    = ExportQuality.fromString(call.argument<String>("quality"))

                        if (inputPath.isNullOrBlank() || outputPath.isNullOrBlank()) {
                            result.error("invalid_args", "缺少 inputPath / outputPath", null)
                            return@setMethodCallHandler
                        }

                        ballTrajExecutor.execute {
                            try {
                                val ok = trajectoryOverlayRenderer.render(
                                    inputPath  = inputPath,
                                    outputPath = outputPath,
                                    trackPts   = trackPts ?: emptyList(),
                                    roiSize    = roiSize,
                                    quality    = quality,
                                    onProgress = ::sendProgress,
                                )
                                runOnUiThread { result.success(ok) }
                            } catch (e: Exception) {
                                Log.e(logTag, "軌跡疊加失敗: ${e.message}", e)
                                runOnUiThread { result.error("render_failed", e.message, null) }
                            }
                        }
                    }

                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FRAME_EXTRACTOR_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "extractFrameRgb" -> {
                        val videoPath = call.argument<String>("videoPath")
                        val timeMs = (call.argument<Int>("timeMs") ?: 0).toLong()
                        val maxWidth = call.argument<Int>("maxWidth") ?: 720

                        if (videoPath.isNullOrBlank()) {
                            result.error("invalid_args", "缺少 videoPath", null)
                            return@setMethodCallHandler
                        }

                        frameExtractorExecutor.execute {
                            try {
                                val bitmap = extractFrameWithMediaCodec(videoPath, timeMs, maxWidth)

                                if (bitmap != null) {
                                    // 🔧 確保 Bitmap 配置正確 (ARGB_8888)
                                    val workingBitmap = if (bitmap.config != Bitmap.Config.ARGB_8888) {
                                        Log.w(logTag, "[MediaCodec] Bitmap config is ${bitmap.config}, converting to ARGB_8888")
                                        val converted = bitmap.copy(Bitmap.Config.ARGB_8888, false)
                                        bitmap.recycle()
                                        converted
                                    } else {
                                        bitmap
                                    }
                                    
                                    // 轉為 NV21 (YUV 4:2:0) byte array
                                    val bitmapWidth = workingBitmap.width
                                    val bitmapHeight = workingBitmap.height
                                    val pixels = IntArray(bitmapWidth * bitmapHeight)
                                    workingBitmap.getPixels(pixels, 0, bitmapWidth, 0, 0, bitmapWidth, bitmapHeight)
                                    
                                    // NV21 = Y plane + UV plane (width * height * 1.5 bytes total)
                                    val frameSize = bitmapWidth * bitmapHeight
                                    val nv21 = ByteArray((frameSize * 1.5).toInt())
                                    
                                    // Y plane
                                    for (i in 0 until frameSize) {
                                        val r = (pixels[i] shr 16) and 0xFF
                                        val g = (pixels[i] shr 8) and 0xFF
                                        val b = pixels[i] and 0xFF
                                        val y = (0.299 * r + 0.587 * g + 0.114 * b).toInt().coerceIn(0, 255).toByte()
                                        nv21[i] = y
                                    }
                                    
                                    // UV plane (NV21: V, U interleaved)
                                    val uvOffset = frameSize
                                    for (j in 0 until bitmapHeight step 2) {
                                        for (i in 0 until bitmapWidth step 2) {
                                            val idx = j * bitmapWidth + i
                                            val r = (pixels[idx] shr 16) and 0xFF
                                            val g = (pixels[idx] shr 8) and 0xFF
                                            val b = pixels[idx] and 0xFF
                                            
                                            val u = ((-0.169 * r - 0.331 * g + 0.5 * b) + 128).toInt().coerceIn(0, 255).toByte()
                                            val v = ((0.5 * r - 0.419 * g - 0.081 * b) + 128).toInt().coerceIn(0, 255).toByte()
                                            
                                            nv21[uvOffset + (j / 2) * bitmapWidth + i] = v
                                            nv21[uvOffset + (j / 2) * bitmapWidth + i + 1] = u
                                        }
                                    }
                                    
                                    workingBitmap.recycle()
                                    
                                    // 📊 Debug: 詳細日誌
                                    Log.i(logTag, "[MediaCodec] Frame NV21: ${bitmapWidth}x${bitmapHeight}, bytes=${nv21.size}")

                                    runOnUiThread {
                                        result.success(mapOf(
                                            "width" to bitmapWidth,
                                            "height" to bitmapHeight,
                                            "pixels" to nv21
                                        ))
                                    }
                                } else {
                                    runOnUiThread {
                                        result.error("extract_failed", "提取幀失敗", null)
                                    }
                                }
                            } catch (e: Exception) {
                                Log.e(logTag, "幀提取例外: ${e.message}", e)
                                runOnUiThread {
                                    result.error("extract_failed", e.message, null)
                                }
                            }
                        }
                    }
                    // ── 精確關鍵禎 JPEG 提取（使用 OPTION_CLOSEST 解碼任意幀）──
                    "extractFrameJpeg" -> {
                        val videoPath  = call.argument<String>("videoPath")
                        val timeMs     = (call.argument<Int>("timeMs") ?: 0).toLong()
                        val outputPath = call.argument<String>("outputPath")
                        val quality    = call.argument<Int>("quality") ?: 80
                        val maxWidth   = call.argument<Int>("maxWidth") ?: 720

                        if (videoPath.isNullOrBlank() || outputPath.isNullOrBlank()) {
                            result.error("invalid_args", "缺少 videoPath 或 outputPath", null)
                            return@setMethodCallHandler
                        }

                        frameExtractorExecutor.execute {
                            try {
                                val retriever = MediaMetadataRetriever()
                                retriever.setDataSource(videoPath)
                                // OPTION_CLOSEST 解碼最近的任意幀（非僅 sync 幀），適合揮桿精確定位
                                val timeUs = timeMs * 1000L
                                val raw = retriever.getFrameAtTime(timeUs, MediaMetadataRetriever.OPTION_CLOSEST)
                                retriever.release()

                                if (raw == null) {
                                    runOnUiThread { result.error("frame_error", "無法提取幀 at ${timeMs}ms", null) }
                                    return@execute
                                }

                                val bitmap = if (maxWidth > 0 && raw.width > maxWidth) {
                                    val scale = maxWidth.toFloat() / raw.width
                                    val h = (raw.height * scale).toInt().coerceAtLeast(1)
                                    val scaled = Bitmap.createScaledBitmap(raw, maxWidth, h, true)
                                    raw.recycle()
                                    scaled
                                } else raw

                                FileOutputStream(outputPath).use { fos ->
                                    bitmap.compress(Bitmap.CompressFormat.JPEG, quality, fos)
                                }
                                bitmap.recycle()
                                Log.i(logTag, "[extractFrameJpeg] ✅ ${timeMs}ms → $outputPath")
                                runOnUiThread { result.success(outputPath) }
                            } catch (e: Exception) {
                                Log.e(logTag, "[extractFrameJpeg] ❌ ${e.message}", e)
                                runOnUiThread { result.error("frame_error", e.message, null) }
                            }
                        }
                    }

                    else -> result.notImplemented()
                }
            }

        // ✅ 完整 Kotlin 原生方案：一次完成全部視頻分析
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, POSE_ANALYZER_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "analyzePoseVideo" -> {
                        val videoPath = call.argument<String>("videoPath")
                        val maxWidth  = (call.argument<Any>("maxWidth")  as? Number)?.toInt() ?: 720
                        val outputCsvPath = call.argument<String>("outputCsvPath")
                        Log.i(logTag, "[PoseAnalyzer] maxWidth=$maxWidth (fps 由影片元數據自主決定)")

                        if (videoPath.isNullOrBlank() || outputCsvPath.isNullOrBlank()) {
                            result.error("invalid_args", "缺少 videoPath 或 outputCsvPath", null)
                            return@setMethodCallHandler
                        }

                        cancelFlag.set(false)   // 新操作開始前重設取消旗標
                        frameExtractorExecutor.execute {
                            try {
                                val csvPath = analyzeVideoNatively(
                                    videoPath,
                                    maxWidth,
                                    outputCsvPath
                                )

                                runOnUiThread {
                                    if (csvPath != null) {
                                        result.success(mapOf(
                                            "csvPath" to csvPath,
                                            "status" to "completed"
                                        ))
                                    } else {
                                        result.error("analysis_failed", "分析失敗或已取消", null)
                                    }
                                }
                            } catch (e: Exception) {
                                Log.e(logTag, "[PoseAnalyzer] 分析例外: ${e.message}", e)
                                runOnUiThread {
                                    result.error("analysis_failed", e.message, null)
                                }
                            }
                        }
                    }
                    // ── 取消當前正在進行的分析操作 ────────────────────────────────
                    "cancel" -> {
                        cancelFlag.set(true)
                        Log.i(logTag, "[PoseAnalyzer] 收到取消請求，cancelFlag=true")
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        // ── V2 骨架分析：音訊峰值 + 局部 ML Kit（±1 秒，≈30 幀）──────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, GOLF_ANALYSIS_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // ── V2 多擊球音訊峰值偵測（長影片「偵測擊球」V2 路徑）──────
                    "findAudioPeaks" -> {
                        val videoPath   = call.argument<String>("videoPath")
                        val startMs     = (call.argument<Any>("searchStartMs") as? Number)?.toLong() ?: 500L
                        val minGapMs    = (call.argument<Any>("minGapMs")      as? Number)?.toLong() ?: 2000L
                        val topN        = (call.argument<Any>("topN")          as? Number)?.toInt()  ?: 20

                        if (videoPath.isNullOrBlank()) {
                            result.error("invalid_args", "缺少 videoPath", null)
                            return@setMethodCallHandler
                        }
                        golfAnalysisExecutor.execute {
                            try {
                                val peaks = AudioImpactDetector.findMultiplePeaks(
                                    videoPath, startMs, minGapMs, topN,
                                    onProgress = { prog, label ->
                                        sendProgress("findAudioPeaks", prog, label)
                                    }
                                )
                                runOnUiThread { result.success(peaks) }
                            } catch (e: Exception) {
                                Log.e(logTag, "[findAudioPeaks] 失敗: ${e.message}", e)
                                runOnUiThread { result.error("peaks_failed", e.message, null) }
                            }
                        }
                    }

                    "analyzeVideo" -> {
                        val videoPath      = call.argument<String>("videoPath")
                        val searchStartMs  = (call.argument<Any>("searchStartMs") as? Number)?.toLong() ?: 500L
                        val searchEndMs    = (call.argument<Any>("searchEndMs")   as? Number)?.toLong() ?: -1L
                        val windowMs       = (call.argument<Any>("windowMs")      as? Number)?.toLong() ?: 1000L
                        val maxWidth       = (call.argument<Any>("maxWidth")      as? Number)?.toInt()  ?: 720

                        if (videoPath.isNullOrBlank()) {
                            result.error("invalid_args", "缺少 videoPath", null)
                            return@setMethodCallHandler
                        }

                        golfAnalysisExecutor.execute {
                            try {
                                val analysisResult = runGolfAnalysisPipeline(
                                    videoPath, searchStartMs, searchEndMs, windowMs, maxWidth
                                )
                                runOnUiThread {
                                    if (analysisResult != null) result.success(analysisResult)
                                    else result.error("not_found", "找不到明確的擊球動作", null)
                                }
                            } catch (e: Exception) {
                                Log.e(logTag, "[GolfAnalysis] 失敗: ${e.message}", e)
                                runOnUiThread { result.error("analysis_failed", e.message, null) }
                            }
                        }
                    }

                    // ── V3 專用：已知音訊峰值 candidateMs，直接做局部骨架分析 ──────────────
                    // 跳過 runGolfAnalysisPipeline 內部的音訊重偵測，避免冗餘。
                    // 骨架分析窗口：[candidateMs - windowMs, candidateMs + windowMs]
                    "analyzeVideoAtCandidate" -> {
                        val videoPath    = call.argument<String>("videoPath")
                        val candidateMs  = (call.argument<Any>("candidateMs") as? Number)?.toLong() ?: 0L
                        val windowMs     = (call.argument<Any>("windowMs")    as? Number)?.toLong() ?: 3000L
                        val maxWidth     = (call.argument<Any>("maxWidth")    as? Number)?.toInt()  ?: 720

                        if (videoPath.isNullOrBlank()) {
                            result.error("invalid_args", "缺少 videoPath", null)
                            return@setMethodCallHandler
                        }

                        cancelFlag.set(false)
                        golfAnalysisExecutor.execute {
                            try {
                                val analysisResult = runGolfSkeletonOnCandidate(
                                    videoPath, candidateMs, windowMs, maxWidth
                                )
                                runOnUiThread {
                                    if (analysisResult != null) result.success(analysisResult)
                                    else result.error("not_found", "骨架分析未找到擊球", null)
                                }
                            } catch (e: Exception) {
                                Log.e(logTag, "[GolfAnalysis.V3] 失敗: ${e.message}", e)
                                runOnUiThread { result.error("analysis_failed", e.message, null) }
                            }
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean {
        if (keyCode == KeyEvent.KEYCODE_VOLUME_DOWN) {
            MethodChannel(flutterEngine!!.dartExecutor.binaryMessenger, CHANNEL)
                .invokeMethod("volume_down", null)
            return true
        }
        return super.onKeyDown(keyCode, event)
    }

    override fun onDestroy() {
        super.onDestroy()
        overlayExecutor.shutdown()
        audioExtractorExecutor.shutdown()
        skeletonExecutor.shutdown()
        ballTrajExecutor.shutdown()
        frameExtractorExecutor.shutdown()
        transcoderExecutor.shutdown()
        golfAnalysisExecutor.shutdown()
    }

    private data class AudioExtractionResult(
        val path: String,
        val sampleRate: Int,
        val channelCount: Int
    )

    /** 從影片提取音訊並轉存為 WAV。若影片無音訊軌則回傳 null（不拋例外）。 */
    @Throws(IOException::class)
    private fun extractAudioToWav(videoPath: String): AudioExtractionResult? {
        val extractor = MediaExtractor()
        extractor.setDataSource(videoPath)

        var audioTrackIndex = -1
        var format: MediaFormat? = null
        for (i in 0 until extractor.trackCount) {
            val candidate = extractor.getTrackFormat(i)
            val mime = candidate.getString(MediaFormat.KEY_MIME) ?: continue
            if (mime.startsWith("audio/")) {
                audioTrackIndex = i
                format = candidate
                break
            }
        }

        if (audioTrackIndex < 0 || format == null) {
            extractor.release()
            Log.i(logTag, "影片無音訊軌，略過音訊提取：$videoPath")
            return null  // ← 正常情況，不拋例外
        }

        extractor.selectTrack(audioTrackIndex)
        val mime = format.getString(MediaFormat.KEY_MIME)!!
        var sampleRate = format.getIntegerOrDefault(MediaFormat.KEY_SAMPLE_RATE, 44100)
        var channelCount = format.getIntegerOrDefault(MediaFormat.KEY_CHANNEL_COUNT, 1)
        var pcmEncoding = format.getIntegerOrDefault(
            MediaFormat.KEY_PCM_ENCODING,
            AudioFormat.ENCODING_PCM_16BIT
        )

        val codec = MediaCodec.createDecoderByType(mime)
        codec.configure(format, null, null, 0)
        codec.start()

        val outputFile = File(applicationContext.cacheDir, "audio_extract_${System.currentTimeMillis()}.wav")
        var totalBytes = 0

        try {
            FileOutputStream(outputFile).use { outputStream ->
                outputStream.write(ByteArray(44))

                val bufferInfo = MediaCodec.BufferInfo()
                val timeoutUs = 10000L
                var sawInputEOS = false
                var finished = false

                while (!finished) {
                    if (!sawInputEOS) {
                        val inputIndex = codec.dequeueInputBuffer(timeoutUs)
                        if (inputIndex >= 0) {
                            val inputBuffer = codec.getInputBuffer(inputIndex)
                            if (inputBuffer != null) {
                                val sampleSize = extractor.readSampleData(inputBuffer, 0)
                                if (sampleSize < 0) {
                                    codec.queueInputBuffer(
                                        inputIndex,
                                        0,
                                        0,
                                        0,
                                        MediaCodec.BUFFER_FLAG_END_OF_STREAM
                                    )
                                    sawInputEOS = true
                                } else {
                                    val presentationTimeUs = extractor.sampleTime
                                    codec.queueInputBuffer(
                                        inputIndex,
                                        0,
                                        sampleSize,
                                        presentationTimeUs,
                                        0
                                    )
                                    extractor.advance()
                                }
                            }
                        }
                    }

                    when (val outputIndex = codec.dequeueOutputBuffer(bufferInfo, timeoutUs)) {
                        MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                            val newFormat = codec.outputFormat
                            sampleRate = newFormat.getIntegerOrDefault(MediaFormat.KEY_SAMPLE_RATE, sampleRate)
                            channelCount = newFormat.getIntegerOrDefault(MediaFormat.KEY_CHANNEL_COUNT, channelCount)
                            pcmEncoding = newFormat.getIntegerOrDefault(
                                MediaFormat.KEY_PCM_ENCODING,
                                pcmEncoding
                            )
                        }

                        MediaCodec.INFO_TRY_AGAIN_LATER -> {
                            // no-op, loop
                        }

                        else -> {
                            if (outputIndex >= 0) {
                                val outputBuffer = codec.getOutputBuffer(outputIndex)
                                if (outputBuffer != null && bufferInfo.size > 0) {
                                    val chunk = ByteArray(bufferInfo.size)
                                    outputBuffer.get(chunk)
                                    outputBuffer.clear()
                                    val bytes = when (pcmEncoding) {
                                        AudioFormat.ENCODING_PCM_FLOAT -> convertFloatToPcm16(chunk)
                                        AudioFormat.ENCODING_PCM_8BIT -> convert8BitToPcm16(chunk)
                                        else -> chunk
                                    }
                                    outputStream.write(bytes)
                                    totalBytes += bytes.size
                                }
                                codec.releaseOutputBuffer(outputIndex, false)
                                if ((bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                                    finished = true
                                }
                            }
                        }
                    }
                }
            }
        } finally {
            codec.stop()
            codec.release()
            extractor.release()
        }

        writeWavHeader(outputFile, totalBytes, sampleRate, channelCount, 16)
        return AudioExtractionResult(outputFile.absolutePath, sampleRate, channelCount)
    }

    
    // ── V2 分析管線：音訊峰值 → 局部 ML Kit → 回傳 impactTimeMs + skeletonJson ──
    private fun runGolfAnalysisPipeline(
        videoPath: String,
        searchStartMs: Long,
        searchEndMs: Long,
        windowMs: Long,      // 峰值前後各擷取幾毫秒（預設 1000ms）
        maxWidth: Int,
    ): Map<String, Any>? {
        Log.i(logTag, "[GolfAnalysis] 開始 V2 分析: $videoPath")

        // Step 1：音訊峰值偵測
        sendProgress("golfAnalysis", 0.05, "音訊掃描中…")
        val audioPeakMs = AudioImpactDetector.findImpactTime(videoPath, searchStartMs, searchEndMs)
        Log.i(logTag, "[GolfAnalysis] 音訊峰值: ${audioPeakMs}ms")

        val hasAudio = audioPeakMs >= 0L
        // 無音訊時取影片中段作為 impactTimeMs
        val impactTimeMs: Long = if (hasAudio) audioPeakMs else {
            android.media.MediaMetadataRetriever().use { mmr ->
                mmr.setDataSource(videoPath)
                mmr.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_DURATION)
                    ?.toLongOrNull() ?: 5000L
            } / 2
        }

        // V2 = 純音訊分析，不做骨架偵測
        sendProgress("golfAnalysis", 1.0, "音訊分析完成")
        Log.i(logTag, "[GolfAnalysis] V2 完成: impactMs=$impactTimeMs hasAudio=$hasAudio")

        if (!hasAudio) {
            Log.w(logTag, "[GolfAnalysis] V2 無音訊軌，以影片中段為 impactTimeMs")
        }

        return mapOf(
            "impactTimeMs"  to impactTimeMs,
            "audioPeakMs"   to audioPeakMs,
            "hasAudio"      to hasAudio,
            "skeletonJson"  to "[]",
            "frameCount"    to 0,
            "videoPath"     to videoPath,
        )
    }

    /**
     * V3 局部骨架分析：直接用已知的 [candidateMs]（音訊峰值），
     * 跳過 runGolfAnalysisPipeline 內部的重複音訊偵測。
     *
     * 分析窗口：[candidateMs - windowMs, candidateMs + windowMs]（共 2×windowMs）
     * 從窗口內的骨架找右腕 Y 最低點 → 精確 impactTimeMs。
     * 回傳與 runGolfAnalysisPipeline 相同格式的 Map，方便 Dart 端統一處理。
     */
    /**
     * V3 局部骨架分析（MediaCodec 順序解碼版本）。
     *
     * 核心優化：
     * ・使用 MediaExtractor.seekTo(SEEK_TO_PREVIOUS_SYNC) 找到 I-frame，
     *   然後用 MediaCodec 依序解碼直到 endMs — 一次 seek，不重複開檔。
     * ・比 extractFrameBitmapAt 的「每幀隨機 seek + new MMR」快 10-30×。
     * ・只對 [startMs, endMs] 內的幀執行 ML Kit，窗口外的幀只解碼不分析。
     *
     * 分析窗口：[candidateMs - windowMs, candidateMs + windowMs]（共 2×windowMs）
     * 右腕 Y 最高（螢幕 Y 最大 = 最低點）= 精確 impactMs。
     */
    private fun runGolfSkeletonOnCandidate(
        videoPath: String,
        candidateMs: Long,
        windowMs: Long,
        maxWidth: Int,
    ): Map<String, Any>? {
        val startUs = (candidateMs - windowMs).coerceAtLeast(0L) * 1000L
        val endUs   = (candidateMs + windowMs) * 1000L
        Log.i(logTag, "[GolfAnalysis.V3] candidate=${candidateMs}ms window=±${windowMs}ms " +
              "→ [${startUs/1000}ms, ${endUs/1000}ms]")
        sendProgress("golfAnalysis", 0.02, "V3 骨架準備中…")

        // ── 取得影片旋轉 ──────────────────────────────────────────────
        val rotation = android.media.MediaMetadataRetriever().use { mmr ->
            mmr.setDataSource(videoPath)
            mmr.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)
                ?.toIntOrNull() ?: 0
        }

        // ── MediaExtractor 開啟影片，找視訊 track ──────────────────────
        val extractor = android.media.MediaExtractor()
        try { extractor.setDataSource(videoPath) }
        catch (e: Exception) {
            Log.e(logTag, "[GolfAnalysis.V3] 無法開啟影片: $e"); return null
        }

        var videoTrackIdx = -1
        var inputFormat: android.media.MediaFormat? = null
        for (i in 0 until extractor.trackCount) {
            val fmt = extractor.getTrackFormat(i)
            val mime = fmt.getString(android.media.MediaFormat.KEY_MIME) ?: ""
            if (mime.startsWith("video/")) { videoTrackIdx = i; inputFormat = fmt; break }
        }
        if (videoTrackIdx < 0 || inputFormat == null) {
            extractor.release(); Log.e(logTag, "[GolfAnalysis.V3] 無視訊 track"); return null
        }
        extractor.selectTrack(videoTrackIdx)

        val videoW = inputFormat.getInteger(android.media.MediaFormat.KEY_WIDTH)
        val videoH = inputFormat.getInteger(android.media.MediaFormat.KEY_HEIGHT)
        val displayW = if (rotation == 90 || rotation == 270) videoH else videoW
        val displayH = if (rotation == 90 || rotation == 270) videoW else videoH

        // ── Seek 到 I-frame（只 seek 一次）──────────────────────────────
        extractor.seekTo(startUs, android.media.MediaExtractor.SEEK_TO_PREVIOUS_SYNC)

        // ── 建立 MediaCodec 解碼器 ────────────────────────────────────
        val mime = inputFormat.getString(android.media.MediaFormat.KEY_MIME) ?: "video/avc"
        val decoder = try {
            android.media.MediaCodec.createDecoderByType(mime)
        } catch (e: Exception) {
            extractor.release(); Log.e(logTag, "[GolfAnalysis.V3] 無法建立解碼器: $e"); return null
        }
        decoder.configure(inputFormat, null, null, 0)
        decoder.start()

        // ── MediaPipe 骨架偵測器 ──────────────────────────────────────
        val mpAnalyzerV3 = MediaPipeVideoAnalyzer(this)
        if (!mpAnalyzerV3.setup()) {
            extractor.release()
            Log.e(logTag, "[GolfAnalysis.V3] MediaPipe 初始化失敗"); return null
        }

        val bufInfo  = android.media.MediaCodec.BufferInfo()
        var inputEos = false
        val rightYList     = mutableListOf<Pair<Long, Float>>()  // (timeMs, Y display)
        val rightXList     = mutableListOf<Float>()              // X display（與 rightYList 等長）
        val skeletonFrames = mutableListOf<Map<String, Any>>()   // 完整骨架資料（供 CSV 寫出）
        var frameCount     = 0
        var analyzedFrames = 0

        // 估算窗口內幀數（僅用於進度顯示）
        val estFrames = ((endUs - startUs) / 33_333L).toInt().coerceAtLeast(1)

        // NV21 緩衝區（ML Kit 直接吃 NV21）
        var nv21Buf = ByteArray(0)
        var yBuf = ByteArray(0); var uBuf = ByteArray(0); var vBuf = ByteArray(0)

        try {
            while (true) {
                // 餵解碼器
                if (!inputEos) {
                    val inIdx = decoder.dequeueInputBuffer(0L)
                    if (inIdx >= 0) {
                        val buf = decoder.getInputBuffer(inIdx)!!
                        val size = extractor.readSampleData(buf, 0)
                        if (size < 0) {
                            decoder.queueInputBuffer(inIdx, 0, 0, 0,
                                android.media.MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputEos = true
                        } else {
                            decoder.queueInputBuffer(inIdx, 0, size, extractor.sampleTime, 0)
                            extractor.advance()
                        }
                    }
                }

                // 取解碼輸出
                val outIdx = decoder.dequeueOutputBuffer(bufInfo, 10_000L)
                if (outIdx == android.media.MediaCodec.INFO_TRY_AGAIN_LATER) continue
                if (outIdx == android.media.MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) continue
                if (outIdx < 0) continue

                val isEos = (bufInfo.flags and android.media.MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0
                val ptsUs = bufInfo.presentationTimeUs

                // 超過分析窗口 → 停止
                if (ptsUs > endUs) {
                    decoder.releaseOutputBuffer(outIdx, false); break
                }

                if (cancelFlag.get()) {
                    decoder.releaseOutputBuffer(outIdx, false)
                    Log.i(logTag, "[GolfAnalysis.V3] 取消"); break
                }

                // 窗口內的幀才跑 ML Kit
                if (ptsUs >= startUs) {
                    val image = runCatching { decoder.getOutputImage(outIdx) }.getOrNull()
                    if (image != null) {
                        try {
                            // YUV → NV21（供 nv21ToBitmap → MediaPipe）
                            val yP = image.planes[0]; val uP = image.planes[1]; val vP = image.planes[2]
                            val yStride = yP.rowStride; val uvStride = uP.rowStride
                            val uvPixelStride = uP.pixelStride
                            val yNeeded = yP.buffer.remaining()
                            val uNeeded = uP.buffer.remaining(); val vNeeded = vP.buffer.remaining()
                            if (yBuf.size < yNeeded) yBuf = ByteArray(yNeeded)
                            if (uBuf.size < uNeeded) uBuf = ByteArray(uNeeded)
                            if (vBuf.size < vNeeded) vBuf = ByteArray(vNeeded)
                            yP.buffer.get(yBuf, 0, yNeeded)
                            uP.buffer.get(uBuf, 0, uNeeded)
                            vP.buffer.get(vBuf, 0, vNeeded)

                            // 目標尺寸（含旋轉）
                            val targetW = if (maxWidth > 0 && displayW > maxWidth) maxWidth else displayW
                            val scale   = targetW.toFloat() / displayW
                            val targetH = (displayH * scale).toInt().coerceAtLeast(1)
                            val nv21Len = targetW * targetH * 3 / 2
                            if (nv21Buf.size < nv21Len) nv21Buf = ByteArray(nv21Len)

                            NativeLib.yuvToNv21(
                                yBuf, uBuf, vBuf, yStride, uvStride, uvPixelStride,
                                videoW, videoH, rotation, displayW, displayH, targetW, targetH, nv21Buf,
                            )

                            // NV21（已旋轉至直式）→ Bitmap → MediaPipe
                            val bmp = nv21ToBitmap(nv21Buf, targetW, targetH)
                            val mpLms = try { mpAnalyzerV3.detect(bmp) } finally { bmp.recycle() }

                            // MediaPipe 回傳歸一化 [0,1]，相對於 targetW×targetH（已含旋轉+縮放）
                            // 因此 xNorm = xDisplay/displayW，yNorm = yDisplay/displayH（直接可用）
                            val rw = mpLms.getOrNull(16)
                            if (rw != null && (rw["vis"] as? Double ?: 0.0) >= 0.3) {
                                val xDisplay = (rw["x"] as Double) * displayW
                                val yDisplay = (rw["y"] as Double) * displayH
                                rightYList.add(ptsUs / 1000L to yDisplay.toFloat())
                                rightXList.add(xDisplay.toFloat())
                            }

                            // 收集完整骨架資料（供 ClipPipelineService 寫成 pose_landmarks.csv）
                            if (mpLms.isNotEmpty()) {
                                val lmList = mpLms.mapIndexed { idx, lm ->
                                    val xNorm = lm["x"] as? Double ?: 0.0
                                    val yNorm = lm["y"] as? Double ?: 0.0
                                    mapOf(
                                        "type"  to idx,
                                        "x"     to (xNorm * displayW).toFloat(),
                                        "y"     to (yNorm * displayH).toFloat(),
                                        "z"     to (lm["z"] as? Double ?: 0.0).toFloat(),
                                        "vis"   to (lm["vis"] as? Double ?: 0.0).toFloat(),
                                        "xNorm" to xNorm.toFloat(),
                                        "yNorm" to yNorm.toFloat(),
                                    )
                                }
                                skeletonFrames.add(mapOf("timeMs" to ptsUs / 1000L, "landmarks" to lmList))
                            }

                            analyzedFrames++
                        } finally {
                            image.close()
                        }
                    }
                    frameCount++

                    val prog = 0.05 + (frameCount.toDouble() / estFrames).coerceIn(0.0, 0.95) * 0.90
                    sendProgress("golfAnalysis", prog, "V3 骨架分析 ${(prog * 100).toInt()}%")
                }

                decoder.releaseOutputBuffer(outIdx, false)
                if (isEos) break
            }
        } finally {
            runCatching { decoder.stop(); decoder.release() }
            runCatching { extractor.release() }
            runCatching { mpAnalyzerV3.close() }
        }

        // ── 過濾驗證 + 精確 impact 偵測 ──────────────────────────────────────────
        //
        // 正確演算法（參考 long_cli.py _detect_speed_y_low_segments）：
        //   1. 計算右腕幀間速度
        //   2. 找 FAST（速度峰值）—— 應靠近音訊峰值
        //   3. 在 FAST ±0.5s 內找 Y_LOW（Y 最大 = 右腕最低點 = 擊球瞬間）
        //   4. 過濾：幀數、Y 跨幅、FAST 速度、impact 偏移
        //
        // 這修正了「誤把準備姿勢(address)的靜態 Y_LOW 當成擊球」的 bug。

        // 過濾 1：右腕偵測幀數不足
        if (rightYList.size < 8) {
            sendProgress("golfAnalysis", 1.0, "V3 過濾：右腕偵測不足 (${rightYList.size} 幀)")
            Log.i(logTag, "[GolfAnalysis.V3] 🚫 排除 candidate=${candidateMs}ms：幀數不足 (${rightYList.size})")
            return null
        }

        // ── 計算幀間速度（px/frame）─────────────────────────────────────────
        val ysOnly = rightYList.map { it.second }
        val xs     = rightXList.toList()
        val speed  = FloatArray(rightYList.size)
        for (idx in 1 until rightYList.size) {
            val dx = xs[idx]  - xs[idx - 1]
            val dy = ysOnly[idx] - ysOnly[idx - 1]
            speed[idx] = Math.sqrt((dx * dx + dy * dy).toDouble()).toFloat()
        }
        // 3-frame moving average 平滑速度
        val smoothSpeed = FloatArray(speed.size)
        for (idx in speed.indices) {
            val l = maxOf(0, idx - 1); val r = minOf(speed.size - 1, idx + 1)
            smoothSpeed[idx] = (speed[l] + speed[idx] + speed[r]) / 3f
        }

        // ── 找 FAST（速度最高點），限定在音訊峰值 ±windowMs 內 ──────────────
        val fastIdx = smoothSpeed.indices.maxByOrNull { smoothSpeed[it] } ?: 0
        val fastMs  = rightYList[fastIdx].first
        val fastSpeed = smoothSpeed[fastIdx]

        // 過濾 2：FAST 速度太低（揮桿動作不明顯）
        val minFastSpeed = maxOf(displayH * 0.003f, 4f)  // 至少 0.3% 幀高或 4px/frame
        if (fastSpeed < minFastSpeed) {
            sendProgress("golfAnalysis", 1.0, "V3 過濾：揮桿速度不足 (${fastSpeed.toInt()}px/frame < ${minFastSpeed.toInt()})")
            Log.i(logTag, "[GolfAnalysis.V3] 🚫 排除 candidate=${candidateMs}ms：FAST 速度不足 ($fastSpeed < $minFastSpeed)")
            return null
        }

        // 過濾 3：FAST 偏離音訊峰值太遠（音訊與骨架不對應）
        val maxDrift = (windowMs * 3 / 4)
        if (Math.abs(fastMs - candidateMs) > maxDrift) {
            sendProgress("golfAnalysis", 1.0, "V3 過濾：FAST 偏離音訊峰值過遠 (${Math.abs(fastMs - candidateMs)}ms)")
            Log.i(logTag, "[GolfAnalysis.V3] 🚫 排除 candidate=${candidateMs}ms：FAST 偏移 ${Math.abs(fastMs - candidateMs)}ms > $maxDrift ms")
            return null
        }

        // ── 在 FAST ±0.5s 內找 Y_LOW（右腕最低點 = impact）────────────────
        val yLowWindowMs = 500L
        val yLowCandidates = rightYList.filterIndexed { idx, _ ->
            val t = rightYList[idx].first
            t >= fastMs - yLowWindowMs && t <= fastMs + yLowWindowMs
        }
        val (impactMs, impactY) = if (yLowCandidates.isNotEmpty())
            yLowCandidates.maxByOrNull { it.second }!!
        else
            rightYList[fastIdx]  // fallback: 直接用 FAST 時刻

        // 過濾 4：Y 跨幅不足（TOP→impact 位移太小，不是揮桿）
        //   取 impact 前的 Y 最小值（TOP = 右腕最高點）
        val preImpactYList = rightYList.filter { it.first < impactMs }
        val topY = preImpactYList.minOfOrNull { it.second } ?: ysOnly.min()
        val ySpan = impactY - topY
        val minYSpan = maxOf(displayH * 0.04f, 20f)
        if (ySpan < minYSpan) {
            sendProgress("golfAnalysis", 1.0, "V3 過濾：TOP→impact 幅度不足 (${ySpan.toInt()}px < ${minYSpan.toInt()}px)")
            Log.i(logTag, "[GolfAnalysis.V3] 🚫 排除 candidate=${candidateMs}ms：Y 跨幅不足 ($ySpan < $minYSpan px)")
            return null
        }

        sendProgress("golfAnalysis", 1.0, "V3 分析完成 (${rightYList.size} 幀有效)")
        Log.i(logTag, "[GolfAnalysis.V3] ✅ impactMs=$impactMs FAST=${fastMs}ms speed=${fastSpeed.toInt()}px/fr ySpan=${ySpan.toInt()}px candidate=${candidateMs}ms 偏移=${impactMs - candidateMs}ms skeletonFrames=${skeletonFrames.size}")

        val skeletonJson = org.json.JSONArray(skeletonFrames.map { frame ->
            @Suppress("UNCHECKED_CAST")
            val lms = frame["landmarks"] as List<Map<String, Any>>
            org.json.JSONObject().apply {
                put("timeMs", frame["timeMs"])
                put("landmarks", org.json.JSONArray(lms.map { lm ->
                    org.json.JSONObject().apply {
                        put("type",  lm["type"])
                        put("x",     lm["x"]); put("y", lm["y"]); put("z", lm["z"])
                        put("vis",   lm["vis"])
                        put("xNorm", lm["xNorm"]); put("yNorm", lm["yNorm"])
                    }
                }))
            }
        }).toString()

        return mapOf(
            "impactTimeMs" to impactMs,
            "audioPeakMs"  to candidateMs,
            "hasAudio"     to true,
            "skeletonJson" to skeletonJson,
            "frameCount"   to analyzedFrames,
            "videoPath"    to videoPath,
        )
    }

    /** 用 MediaMetadataRetriever 取得指定毫秒的 Bitmap（含旋轉修正與縮放）。 */
    private fun extractFrameBitmapAt(videoPath: String, timeMs: Long, maxWidth: Int, rotation: Int): android.graphics.Bitmap? {
        return try {
            val mmr = android.media.MediaMetadataRetriever()
            mmr.setDataSource(videoPath)
            val raw = mmr.getFrameAtTime(timeMs * 1000L, android.media.MediaMetadataRetriever.OPTION_CLOSEST)
            mmr.release()
            if (raw == null) return null

            // 旋轉修正
            val rotated = if (rotation != 0) {
                val matrix = android.graphics.Matrix().apply { postRotate(rotation.toFloat()) }
                val r = android.graphics.Bitmap.createBitmap(raw, 0, 0, raw.width, raw.height, matrix, true)
                raw.recycle(); r
            } else raw

            // 縮放到 maxWidth
            if (maxWidth > 0 && rotated.width > maxWidth) {
                val scale = maxWidth.toFloat() / rotated.width
                val h = (rotated.height * scale).toInt().coerceAtLeast(1)
                val scaled = android.graphics.Bitmap.createScaledBitmap(rotated, maxWidth, h, true)
                rotated.recycle(); scaled
            } else rotated
        } catch (e: Exception) {
            Log.w(logTag, "[GolfAnalysis] extractFrameBitmapAt ${timeMs}ms 失敗: ${e.message}")
            null
        }
    }

    // ✅ 原生全影片分析：一個 MediaCodec 實例 + ML Kit + 直接寫 CSV
    // 比舊方案（每幀開一個 MediaMetadataRetriever + JNI 傳 1.3MB）快 3-5x
    // fallback fps：只在無法從影片格式讀到 KEY_FRAME_RATE 時使用
    private val FALLBACK_FPS = 30

    private fun analyzeVideoNatively(
        videoPath: String,
        maxWidth: Int,
        outputCsvPath: String
    ): String? {
        // 🎬 記錄輸入參數
        Log.i(logTag, "[PoseAnalyzer] 🎬 開始分析: maxWidth=$maxWidth videoPath=$videoPath")
        
        val extractor = MediaExtractor()
        var codec: MediaCodec? = null
        var csvWriter: java.io.Writer? = null          // ② BufferedWriter（改宣告型態）
        val mediaPipeAnalyzer = MediaPipeVideoAnalyzer(this)
        var inferThread: Thread? = null                // ① 推論執行緒（在 finally 中 join）

        try {
            extractor.setDataSource(videoPath)

            // 讀旋轉 metadata（portrait video 通常是 coded 1280×720 + rotation=90）
            val rotation = MediaMetadataRetriever().use { mmr ->
                mmr.setDataSource(videoPath)
                mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)
                    ?.toIntOrNull() ?: 0
            }

            var videoTrackIndex = -1
            for (i in 0 until extractor.trackCount) {
                val fmt = extractor.getTrackFormat(i)
                if ((fmt.getString(MediaFormat.KEY_MIME) ?: "").startsWith("video/")) {
                    videoTrackIndex = i; break
                }
            }
            if (videoTrackIndex < 0) { Log.e(logTag, "[PoseAnalyzer] 找不到視頻軌道"); return null }

            val videoFormat = extractor.getTrackFormat(videoTrackIndex)
            val codedW = videoFormat.getInteger(MediaFormat.KEY_WIDTH)
            val codedH = videoFormat.getInteger(MediaFormat.KEY_HEIGHT)
            val mime   = videoFormat.getString(MediaFormat.KEY_MIME) ?: ""

            // 採樣率 = 影片實際 fps（KEY_FRAME_RATE），讀不到時 fallback 為 FALLBACK_FPS=30
            val actualVideoFps = runCatching {
                videoFormat.getInteger(MediaFormat.KEY_FRAME_RATE)
            }.getOrElse { FALLBACK_FPS }
            Log.i(logTag, "[PoseAnalyzer] 🎬 actualVideoFps=$actualVideoFps (fallback=$FALLBACK_FPS)")

            // display 尺寸（旋轉修正後的正確寬高）
            val displayW = if (rotation == 90 || rotation == 270) codedH else codedW
            val displayH = if (rotation == 90 || rotation == 270) codedW else codedH

            val durationMs = MediaMetadataRetriever().use { mmr ->
                mmr.setDataSource(videoPath)
                mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
            }
            val expectedFrames = (durationMs * actualVideoFps / 1000L).toInt()  // 🎬 使用實際 fps 計算期望幀數
            Log.i(logTag, "[PoseAnalyzer] 📊 時長檢測: durationMs=$durationMs")
            Log.i(logTag, "[PoseAnalyzer] 📊 幀數計算: $expectedFrames = ($durationMs ms × $actualVideoFps fps / 1000)")
            Log.i(logTag, "[PoseAnalyzer] coded=${codedW}x${codedH} display=${displayW}x${displayH} rotation=$rotation duration=${durationMs}ms actualVideoFps=$actualVideoFps expected≈$expectedFrames")

            extractor.selectTrack(videoTrackIndex)
            // Dolby Vision containers are typically HEVC-compatible; fall back to video/hevc
            // on devices that lack a hardware Dolby Vision decoder (NAME_NOT_FOUND error).
            val decodeMime = if (mime == "video/dolby-vision") "video/hevc" else mime
            if (decodeMime != mime) {
                videoFormat.setString(MediaFormat.KEY_MIME, decodeMime)
                Log.i(logTag, "[PoseAnalyzer] Dolby Vision → falling back to $decodeMime")
            }
            codec = MediaCodec.createDecoderByType(decodeMime)
            codec.configure(videoFormat, null, null, 0)
            codec.start()

            // MediaPipe IMAGE 模式：每幀同步推理，取代 ML Kit PoseDetector
            if (!mediaPipeAnalyzer.setup()) {
                Log.e(logTag, "[PoseAnalyzer] MediaPipe 初始化失敗，分析中止")
                return null
            }

            // CSV 標頭（格式與 PoseFrameModel.toCsvRow 完全對齊：6 值/關鍵點）
            val csvFile = java.io.File(outputCsvPath)
            csvFile.parentFile?.mkdirs()
            // ② BufferedWriter 64KB：減少 syscall 次數（原 FileWriter 每 write() 呼叫即 flush）
            csvWriter = java.io.BufferedWriter(java.io.FileWriter(csvFile), 65536)
            val header = buildString {
                append("frame,time_sec,pose_update_id")
                for (i in 0..32) append(",lm${i}_x_norm,lm${i}_y_norm,lm${i}_z,lm${i}_visibility,lm${i}_x_px,lm${i}_y_px")
            }
            csvWriter.write(header + "\n")

            val bufferInfo   = MediaCodec.BufferInfo()
            var decodedFrames = 0
            val inferFailures = java.util.concurrent.atomic.AtomicInteger(0)

            val frameIntervalUs  = 1_000_000L / actualVideoFps
            var nextSampleUs     = 0L
            var inputEOS         = false
            var outputEOS        = false
            val SAMPLE_TOLERANCE_US = 500L

            Log.i(logTag, "[PoseAnalyzer] 🎬 採樣配置: fps=$actualVideoFps interval=${frameIntervalUs}µs")

            // ── ① 並行 Pipeline：解碼執行緒 + MediaPipe 推論執行緒 ─────────
            // [解碼 F1]──[解碼 F2]──[解碼 F3]──...
            //                  └──[MediaPipe F1]──[MediaPipe F2]──...
            // 佇列容量 = 3：解碼最多超前 3 幀（back-pressure）

            data class FramePacket(
                val image: android.media.Image?,   // null=無影像（getOutputImage 失敗）或 EOS
                val outIdx: Int,                   // -1=不需要 releaseOutputBuffer
                val ptsUs: Long,
                val frameIdx: Int,
                val isEos: Boolean = false,
            )

            val imageQueue = java.util.concurrent.ArrayBlockingQueue<FramePacket>(3)
            val inferError  = java.util.concurrent.atomic.AtomicReference<Throwable?>(null)

            // ── 縮圖配置（1080p → 720p 只搬 0.7MB 給 ML Kit，省 ~20-30%）──────
            // maxWidth=720：720p 影片 needsScale=false（已是目標大小）
            //               1080p 影片 needsScale=true → C 縮到 720p 再傳 ML Kit
            val needsScale  = maxWidth > 0 && displayW > maxWidth
            val scaledW: Int; val scaledH: Int
            if (needsScale) {
                val ratio = maxWidth.toFloat() / displayW
                scaledW = maxWidth
                // 高度四捨五入到偶數（YUV 要求）
                scaledH = ((displayH * ratio).toInt() + 1) and -2
                Log.i(logTag, "[PoseAnalyzer] 縮圖: ${displayW}×${displayH} → ${scaledW}×${scaledH}（省 GPU 搬運量 ${displayW * displayH * 3 / 2 / 1024}KB → ${scaledW * scaledH * 3 / 2 / 1024}KB）")
            } else {
                scaledW = displayW; scaledH = displayH
            }

            // 推論執行緒的獨立狀態（僅在此執行緒存取，無需同步）
            var inferFrameCount = 0
            var poseUpdateId    = 0
            var lastMpLandmarks: List<Map<String, Any>>? = null
            // 預分配 StringBuilder，避免每幀分配
            val rowSb        = StringBuilder(512)
            val localCodec   = codec  // 捕捉 non-null 參照供推論執行緒使用
            // NV21 轉換緩衝區（含旋轉 + 縮放，兩條路徑共用）
            var yBufInfer    = ByteArray(0)
            var uBufInfer    = ByteArray(0)
            var vBufInfer    = ByteArray(0)
            val nv21OutBuf   = ByteArray(scaledW * scaledH * 3 / 2)

            val sw = System.currentTimeMillis()

            // ── 啟動 MediaPipe 推論執行緒 ──────────────────────────────────
            inferThread = Thread({
                try {
                    while (true) {
                        val pkt = imageQueue.take()
                        if (pkt.isEos) break

                        try {
                            // ── YUV → NV21（含旋轉＋縮放）→ Bitmap → MediaPipe ──────
                            val mpLandmarks: List<Map<String, Any>> = pkt.image?.let { img ->
                                val bufs = imageToNv21Scaled(
                                    img, codedW, codedH, rotation,
                                    scaledW, scaledH, nv21OutBuf,
                                    yBufInfer, uBufInfer, vBufInfer,
                                )
                                yBufInfer = bufs[0]; uBufInfer = bufs[1]; vBufInfer = bufs[2]
                                val bmp = nv21ToBitmap(nv21OutBuf, scaledW, scaledH)
                                try {
                                    mediaPipeAnalyzer.detect(bmp)
                                } catch (e: Exception) {
                                    inferFailures.incrementAndGet()
                                    Log.w(logTag, "[PoseAnalyzer] MediaPipe fail #${pkt.frameIdx}: ${e.message}")
                                    emptyList()
                                } finally {
                                    bmp.recycle()
                                }
                            } ?: emptyList()

                            // poseUpdateId 追蹤（以歸一化座標差異判斷）
                            if (mpLandmarks.isNotEmpty()) {
                                val prev = lastMpLandmarks
                                val changed = prev == null || prev.size != mpLandmarks.size ||
                                    mpLandmarks.zip(prev).any { (a, b) ->
                                        val ax = a["x"] as? Double ?: 0.0
                                        val bx = b["x"] as? Double ?: 0.0
                                        val ay = a["y"] as? Double ?: 0.0
                                        val by_ = b["y"] as? Double ?: 0.0
                                        kotlin.math.abs(ax - bx) > 0.002 || kotlin.math.abs(ay - by_) > 0.002
                                    }
                                if (changed) poseUpdateId++
                                lastMpLandmarks = mpLandmarks
                            }

                            // CSV 行（格式與 ML Kit 路徑完全相同：xNorm,yNorm,z,vis,xPx,yPx）
                            val timeSec = pkt.ptsUs / 1_000_000.0
                            rowSb.clear()
                            rowSb.append(pkt.frameIdx).append(',')
                                 .append(timeSec).append(',')
                                 .append(poseUpdateId)
                            if (mpLandmarks.isNotEmpty()) {
                                for (i in 0..32) {
                                    val lm = mpLandmarks.getOrNull(i)
                                    if (lm != null) {
                                        val xNorm = lm["x"] as? Double ?: Double.NaN
                                        val yNorm = lm["y"] as? Double ?: Double.NaN
                                        val z     = lm["z"] as? Double ?: Double.NaN
                                        val vis   = lm["vis"] as? Double ?: 0.0
                                        rowSb.append(',').append(xNorm)
                                             .append(',').append(yNorm)
                                             .append(',').append(z)
                                             .append(',').append(vis)
                                             .append(',').append(if (xNorm.isNaN()) "NaN" else xNorm * displayW)
                                             .append(',').append(if (yNorm.isNaN()) "NaN" else yNorm * displayH)
                                    } else {
                                        rowSb.append(",NaN,NaN,NaN,0.0,NaN,NaN")
                                    }
                                }
                            } else {
                                repeat(33) { rowSb.append(",NaN,NaN,NaN,0.0,NaN,NaN") }
                            }
                            csvWriter!!.write(rowSb.toString())
                            csvWriter!!.write("\n")
                            inferFrameCount++

                        } finally {
                            // Image 必須先 close，才能 releaseOutputBuffer
                            runCatching { pkt.image?.close() }
                            if (pkt.outIdx >= 0) runCatching { localCodec!!.releaseOutputBuffer(pkt.outIdx, false) }
                        }
                    }
                } catch (e: Throwable) {
                    inferError.set(e)
                }
            }, "PoseInferThread").apply { isDaemon = true; start() }

            // ── 解碼主迴圈（在當前執行緒）──────────────────────────────────
            var queuedFrames = 0  // 已進 queue 的幀數（包含空幀），用於 frameIdx

            while (!outputEOS) {
                // 餵解碼器輸入
                if (!inputEOS) {
                    val inIdx = codec.dequeueInputBuffer(0L)
                    if (inIdx >= 0) {
                        val buf  = codec.getInputBuffer(inIdx)!!
                        val size = extractor.readSampleData(buf, 0)
                        if (size < 0) {
                            codec.queueInputBuffer(inIdx, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputEOS = true
                        } else {
                            codec.queueInputBuffer(inIdx, 0, size, extractor.sampleTime, 0)
                            extractor.advance()
                        }
                    }
                }

                // 取解碼輸出
                val outIdx = codec.dequeueOutputBuffer(bufferInfo, 10_000L)
                when {
                    outIdx == MediaCodec.INFO_TRY_AGAIN_LATER -> { }
                    outIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> { }
                    outIdx >= 0 -> {
                        val ptsUs = bufferInfo.presentationTimeUs
                        decodedFrames++

                        val shouldSample = ptsUs >= nextSampleUs - SAMPLE_TOLERANCE_US && bufferInfo.size > 0
                        if (decodedFrames <= 5 || decodedFrames % 60 == 0) {
                            Log.d(logTag, "[PoseAnalyzer] 幀#$decodedFrames ptsUs=$ptsUs sample=$shouldSample")
                        }

                        if (shouldSample) {
                            nextSampleUs = ptsUs + frameIntervalUs
                            val image = runCatching { codec.getOutputImage(outIdx) }.getOrNull()

                            if (image != null) {
                                // 送給推論執行緒（佇列滿時阻塞 → 自然 back-pressure）
                                // ⚠️ 不在此 releaseOutputBuffer，由推論執行緒負責
                                imageQueue.put(FramePacket(image, outIdx, ptsUs, queuedFrames))
                            } else {
                                // getOutputImage 失敗：送空封包，推論執行緒寫 NaN 行
                                imageQueue.put(FramePacket(null, -1, ptsUs, queuedFrames))
                                codec.releaseOutputBuffer(outIdx, false)
                            }
                            queuedFrames++
                        } else {
                            codec.releaseOutputBuffer(outIdx, false)
                        }

                        // 進度推送（保留在解碼執行緒，不影響推論）
                        if (decodedFrames % 10 == 0 && expectedFrames > 0) {
                            val prog = (decodedFrames.toDouble() / expectedFrames).coerceIn(0.0, 0.95)
                            sendProgress("analyzePose", prog,
                                "骨架分析中 ${(prog * 100).toInt()}%", decodedFrames, expectedFrames)
                        }

                        if ((bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) outputEOS = true
                    }
                }

                // ── 取消檢查（每幀後，讓解碼迴圈能及時停止）──────────────────
                if (cancelFlag.get()) {
                    Log.i(logTag, "[PoseAnalyzer] 偵測到取消旗標，提前結束解碼（已處理 $decodedFrames 幀）")
                    break
                }
            }

            // 送 EOS 給推論執行緒並等待完成（確保所有幀都寫入 CSV）
            imageQueue.put(FramePacket(null, -1, 0L, -1, isEos = true))
            inferThread!!.join()
            inferError.get()?.let { throw RuntimeException("PoseInferThread failed", it) }

            csvWriter!!.flush()
            val elapsedMs   = System.currentTimeMillis() - sw
            val throughput  = if (elapsedMs > 0) "%.1f".format(inferFrameCount * 1000.0 / elapsedMs) else "N/A"
            val failCount   = inferFailures.get()
            Log.i(logTag, "[PoseAnalyzer] 📊 處理完成（MediaPipe 並行 Pipeline）:")
            Log.i(logTag, "[PoseAnalyzer]   總解碼幀: $decodedFrames，已採樣: $inferFrameCount，預期: $expectedFrames")
            Log.i(logTag, "[PoseAnalyzer]   採樣率: ${(inferFrameCount * 100.0 / maxOf(1, decodedFrames)).toInt()}%")
            Log.i(logTag, "[PoseAnalyzer] done: $inferFrameCount frames, ${elapsedMs}ms, ${throughput}fps, mediapipe_fail=$failCount → $outputCsvPath")
            sendProgress("analyzePose", 1.0, "骨架分析完成", inferFrameCount, inferFrameCount)
            if (failCount > 0) Log.w(logTag, "[PoseAnalyzer] mediapipe_fail=$failCount frames")
            if (inferFrameCount < expectedFrames * 0.8) {
                Log.w(logTag, "[PoseAnalyzer] ⚠️ 幀數異常: 只採樣 ${(inferFrameCount * 100.0 / maxOf(1, expectedFrames)).toInt()}% (decoded=$decodedFrames expected=$expectedFrames)")
            }
            return outputCsvPath

        } catch (e: Exception) {
            Log.e(logTag, "[PoseAnalyzer] 分析失敗: ${e.message}", e)
            return null
        } finally {
            // ① 必須在 codec.release() 之前 join inferThread，
            //    否則推論執行緒可能在 codec 釋放後仍嘗試 releaseOutputBuffer → crash
            runCatching {
                // 若 inferThread 尚未收到 EOS，強制送一個（異常路徑）
                // offer() 不阻塞：若 queue 已滿或已有 EOS，忽略
                (inferThread as? Thread)?.let { t ->
                    if (t.isAlive) {
                        t.interrupt()  // 喚醒可能在 imageQueue.take() 阻塞的執行緒
                        t.join(3_000L) // 最多等 3 秒
                    }
                }
            }
            runCatching { mediaPipeAnalyzer.close() }
            runCatching { csvWriter?.close() }
            runCatching { codec?.stop(); codec?.release() }
            runCatching { extractor.release() }
        }
    }

    /** NV21 ByteArray → Bitmap（JPEG 中轉，處理旋轉後的直式影像）。*/
    private fun nv21ToBitmap(nv21: ByteArray, w: Int, h: Int): Bitmap {
        val yuvImg = android.graphics.YuvImage(nv21, android.graphics.ImageFormat.NV21, w, h, null)
        val out = java.io.ByteArrayOutputStream()
        yuvImg.compressToJpeg(android.graphics.Rect(0, 0, w, h), 88, out)
        val bytes = out.toByteArray()
        return android.graphics.BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
            ?: Bitmap.createBitmap(1, 1, Bitmap.Config.ARGB_8888)
    }

    // YUV420 Image → NV21（含旋轉 + nearest-neighbor downscale）
    // 回傳更新後的 yBuf/uBuf/vBuf（延遲擴容，避免每幀 GC）
    private fun imageToNv21Scaled(
        image: android.media.Image,
        codedW: Int, codedH: Int, rotation: Int,
        outW: Int, outH: Int,
        nv21: ByteArray,
        yBufIn: ByteArray, uBufIn: ByteArray, vBufIn: ByteArray
    ): Array<ByteArray> {
        val yP = image.planes[0]; val uP = image.planes[1]; val vP = image.planes[2]
        val yStride      = yP.rowStride
        val uvStride     = uP.rowStride
        val uvPixStride  = uP.pixelStride

        val ySize = yP.buffer.remaining()
        val uSize = uP.buffer.remaining()
        val vSize = vP.buffer.remaining()
        val yBuf = if (yBufIn.size >= ySize) yBufIn else ByteArray(ySize)
        val uBuf = if (uBufIn.size >= uSize) uBufIn else ByteArray(uSize)
        val vBuf = if (vBufIn.size >= vSize) vBufIn else ByteArray(vSize)
        yP.buffer.get(yBuf, 0, ySize)
        uP.buffer.get(uBuf, 0, uSize)
        vP.buffer.get(vBuf, 0, vSize)

        // source display 尺寸（旋轉後的正確方向）
        val srcW = if (rotation == 90 || rotation == 270) codedH else codedW
        val srcH = if (rotation == 90 || rotation == 270) codedW else codedH

        val uvBase = outW * outH
        for (dy in 0 until outH) {
            for (dx in 0 until outW) {
                val sx = (dx.toLong() * srcW / outW).toInt()
                val sy = (dy.toLong() * srcH / outH).toInt()
                val ci: Int; val cj: Int
                when (rotation) {
                    90  -> { ci = sy;           cj = codedH - 1 - sx }
                    270 -> { ci = codedW-1-sy;  cj = sx              }
                    180 -> { ci = codedW-1-sx;  cj = codedH-1-sy    }
                    else-> { ci = sx;           cj = sy              }
                }
                val yIdx = cj * yStride + ci
                nv21[dy * outW + dx] = if (yIdx < ySize) yBuf[yIdx] else 16
                if (dy % 2 == 0 && dx % 2 == 0) {
                    val uvOff = (cj / 2) * uvStride + (ci / 2) * uvPixStride
                    val base  = uvBase + (dy / 2) * outW + dx
                    if (base + 1 < nv21.size) {
                        // NV21: V 先，U 後
                        nv21[base]     = if (uvOff < vSize) vBuf[uvOff] else 128.toByte()
                        nv21[base + 1] = if (uvOff < uSize) uBuf[uvOff] else 128.toByte()
                    }
                }
            }
        }
        return arrayOf(yBuf, uBuf, vBuf)
    }
    
    // ✅ 方案 A: MediaExtractor + MediaCodec 精確幀提取 (改進版)
    private fun extractFrameWithMediaCodec(videoPath: String, timeMs: Long, maxWidth: Int): Bitmap? {
        val extractor = MediaExtractor()
        var codec: MediaCodec? = null
        
        try {
            extractor.setDataSource(videoPath)
            
            // 找到視頻軌道
            var videoTrackIndex = -1
            for (i in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(i)
                val mime = format.getString(MediaFormat.KEY_MIME) ?: ""
                if (mime.startsWith("video/")) {
                    videoTrackIndex = i
                    break
                }
            }
            
            if (videoTrackIndex < 0) {
                Log.e(logTag, "[MediaCodec] 找不到視頻軌道")
                return null
            }
            
            val videoFormat = extractor.getTrackFormat(videoTrackIndex)
            val videoWidth = videoFormat.getInteger(MediaFormat.KEY_WIDTH)
            val videoHeight = videoFormat.getInteger(MediaFormat.KEY_HEIGHT)
            val mime = videoFormat.getString(MediaFormat.KEY_MIME) ?: ""
            
            // 獲取幀率計算容差
            val fps = runCatching {
                videoFormat.getInteger(MediaFormat.KEY_FRAME_RATE).toDouble()
            }.getOrElse { 30.0 }
            val frameDurationMs = 1000.0 / fps
            val timeTolerance = (frameDurationMs * 1.5).toLong()  // 1.5 幀的容差
            
            Log.d(logTag, "[MediaCodec] 視頻: ${videoWidth}x${videoHeight}, mime=$mime, fps=$fps, 容差=${timeTolerance}ms")
            
            extractor.selectTrack(videoTrackIndex)
            
            // 建立解碼器
            codec = MediaCodec.createDecoderByType(mime)
            codec.configure(videoFormat, null, null, 0)
            codec.start()
            
            // Seek 到指定時間戳（微秒）
            val timeUs = timeMs * 1000L
            extractor.seekTo(timeUs, MediaExtractor.SEEK_TO_CLOSEST_SYNC)
            
            val bufferInfo = MediaCodec.BufferInfo()
            var decodedFrame: Bitmap? = null
            var inputEos = false
            var framesDecoded = 0
            var maxAttempts = 1000  // ⬆️ 增加上限（之前 100 太小）
            
            while (maxAttempts-- > 0) {
                // 【1】餵輸入數據到解碼器
                if (!inputEos) {
                    val inputIndex = codec.dequeueInputBuffer(1000)
                    if (inputIndex >= 0) {
                        val inputBuffer = codec.getInputBuffer(inputIndex)
                        if (inputBuffer != null) {
                            val sampleSize = extractor.readSampleData(inputBuffer, 0)
                            if (sampleSize >= 0) {
                                codec.queueInputBuffer(
                                    inputIndex,
                                    0,
                                    sampleSize,
                                    extractor.sampleTime,
                                    0
                                )
                                extractor.advance()
                            } else {
                                codec.queueInputBuffer(
                                    inputIndex,
                                    0,
                                    0,
                                    0,
                                    MediaCodec.BUFFER_FLAG_END_OF_STREAM
                                )
                                inputEos = true
                                Log.d(logTag, "[MediaCodec] 📨 已發送 EOS 標誌")
                            }
                        }
                    }
                }
                
                // 【2】讀取解碼輸出
                val outputIndex = codec.dequeueOutputBuffer(bufferInfo, 1000)
                
                when {
                    outputIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        Log.d(logTag, "[MediaCodec] 📋 輸出格式已更改")
                        continue
                    }
                    outputIndex == MediaCodec.INFO_TRY_AGAIN_LATER -> {
                        // 沒有輸出，繼續
                        continue
                    }
                    outputIndex >= 0 -> {
                        val outputBuffer = codec.getOutputBuffer(outputIndex)
                        if (outputBuffer != null && bufferInfo.size > 0) {
                            val presentationTimeUs = bufferInfo.presentationTimeUs
                            val frameTimeMs = presentationTimeUs / 1000L
                            framesDecoded++
                            
                            // ⬆️ 使用動態容差而不是固定 ±33ms
                            val timeDiff = kotlin.math.abs(frameTimeMs - timeMs)
                            
                            if (timeDiff <= timeTolerance) {
                                decodedFrame = decodeYuvToRgb(
                                    outputBuffer,
                                    videoWidth,
                                    videoHeight,
                                    maxWidth
                                )
                                Log.d(logTag, "[MediaCodec] ✅ 成功提取幀 @ ${frameTimeMs}ms (目標: ${timeMs}ms, 差異: ${timeDiff}ms)")
                                codec.releaseOutputBuffer(outputIndex, false)
                                break
                            } else {
                                Log.d(logTag, "[MediaCodec] ⏭️ 跳過幀 @ ${frameTimeMs}ms (目標: ${timeMs}ms, 差異: ${timeDiff}ms)")
                            }
                        }
                        codec.releaseOutputBuffer(outputIndex, false)
                    }
                }
                
                if ((bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                    Log.w(logTag, "[MediaCodec] 到達流末尾 (已解碼 $framesDecoded 幀)")
                    break
                }
            }
            
            if (decodedFrame == null) {
                Log.e(logTag, "[MediaCodec] ❌ 提取失敗: 已解碼 $framesDecoded 幀，未找到目標幀 @ ${timeMs}ms")
            }
            
            return decodedFrame
            
        } catch (e: Exception) {
            Log.e(logTag, "[MediaCodec] ❌ 提取異常: ${e.message}", e)
            return null
        } finally {
            try {
                codec?.stop()
                codec?.release()
            } catch (e: Exception) {
                Log.e(logTag, "[MediaCodec] 釋放 codec 失敗: ${e.message}")
            }
            try {
                extractor.release()
            } catch (e: Exception) {
                Log.e(logTag, "[MediaCodec] 釋放 extractor 失敗: ${e.message}")
            }
        }
    }
    
    // YUV420 → RGB 轉換（用於 MediaCodec 輸出）
    private fun decodeYuvToRgb(
        yuvBuffer: java.nio.ByteBuffer,
        width: Int,
        height: Int,
        maxWidth: Int
    ): Bitmap? {
        return try {
            val size = width * height
            val yuv = ByteArray(size * 3 / 2)
            yuvBuffer.get(yuv)
            
            val argbData = IntArray(size)
            yuvToArgb(yuv, width, height, argbData)
            
            val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            bitmap.setPixels(argbData, 0, width, 0, 0, width, height)
            
            // 縮放到 maxWidth
            if (bitmap.width > maxWidth) {
                val scaledHeight = (maxWidth.toDouble() / bitmap.width * bitmap.height).toInt()
                val scaledBitmap = Bitmap.createScaledBitmap(bitmap, maxWidth, scaledHeight, true)
                bitmap.recycle()
                scaledBitmap
            } else {
                bitmap
            }
        } catch (e: Exception) {
            Log.e(logTag, "[YUVConvert] 轉換失敗: ${e.message}", e)
            null
        }
    }
    
    // YUV420 (I420) → ARGB 轉換
    private fun yuvToArgb(yuv420: ByteArray, width: Int, height: Int, argb: IntArray) {
        val ySize = width * height
        val uvSize = width * height / 4
        
        for (y in 0 until height) {
            for (x in 0 until width) {
                val index = y * width + x
                val yValue = (yuv420[index].toInt() and 0xFF)
                
                // U 和 V 在 I420 格式中分開
                val uvIndex = ySize + (y / 2) * (width / 2) + (x / 2)
                val uValue = (yuv420[uvIndex].toInt() and 0xFF) - 128
                val vValue = (yuv420[uvIndex + uvSize].toInt() and 0xFF) - 128
                
                // YUV 轉 RGB
                val r = (yValue + 1.402f * vValue).toInt().coerceIn(0, 255)
                val g = (yValue - 0.344f * uValue - 0.714f * vValue).toInt().coerceIn(0, 255)
                val b = (yValue + 1.772f * uValue).toInt().coerceIn(0, 255)
                
                argb[index] = (0xFF shl 24) or (r shl 16) or (g shl 8) or b
            }
        }
    }

    private fun MediaFormat.getIntegerOrDefault(key: String, default: Int): Int {
        return if (containsKey(key)) getInteger(key) else default
    }

    private fun convertFloatToPcm16(data: ByteArray): ByteArray {
        val floatBuffer = ByteBuffer.wrap(data)
            .order(ByteOrder.nativeOrder())
            .asFloatBuffer()
        val out = ByteBuffer.allocate(floatBuffer.remaining() * 2)
            .order(ByteOrder.LITTLE_ENDIAN)
        while (floatBuffer.hasRemaining()) {
            val sample = floatBuffer.get().coerceIn(-1f, 1f)
            val shortSample = (sample * Short.MAX_VALUE).toInt().toShort()
            out.putShort(shortSample)
        }
        return out.array()
    }

    private fun convert8BitToPcm16(data: ByteArray): ByteArray {
        val out = ByteBuffer.allocate(data.size * 2)
            .order(ByteOrder.LITTLE_ENDIAN)
        for (value in data) {
            val centered = (value.toInt() and 0xFF) - 128
            out.putShort((centered shl 8).toShort())
        }
        return out.array()
    }

    private fun writeWavHeader(
        file: File,
        pcmDataLength: Int,
        sampleRate: Int,
        channelCount: Int,
        bitsPerSample: Int
    ) {
        val byteRate = sampleRate * channelCount * bitsPerSample / 8
        val blockAlign = (channelCount * bitsPerSample / 8).toShort()
        val header = ByteBuffer.allocate(44)
            .order(ByteOrder.LITTLE_ENDIAN)
            .put("RIFF".toByteArray(Charsets.US_ASCII))
            .putInt(36 + pcmDataLength)
            .put("WAVE".toByteArray(Charsets.US_ASCII))
            .put("fmt ".toByteArray(Charsets.US_ASCII))
            .putInt(16)
            .putShort(1.toShort())
            .putShort(channelCount.toShort())
            .putInt(sampleRate)
            .putInt(byteRate)
            .putShort(blockAlign)
            .putShort(bitsPerSample.toShort())
            .put("data".toByteArray(Charsets.US_ASCII))
            .putInt(pcmDataLength)
            .array()

        RandomAccessFile(file, "rw").use { raf ->
            raf.seek(0)
            raf.write(header)
        }
    }

    // ── 影片存到 Downloads ─────────────────────────────────────────────────────
    /**
     * 將 [srcPath] 的影片複製到系統 Downloads 資料夾，回傳儲存路徑（字串）。
     *
     * Android 10+ (API 29)：使用 MediaStore，無需額外權限
     * Android 9-  (API 28)：使用 Environment.DIRECTORY_DOWNLOADS（需 WRITE_EXTERNAL_STORAGE）
     */
    @Throws(Exception::class)
    private fun saveVideoToDownloads(srcPath: String, fileName: String): String {
        val src = java.io.File(srcPath)
        require(src.exists()) { "來源檔案不存在: $srcPath" }
        val mime = if (fileName.lowercase().endsWith(".mov")) "video/quicktime" else "video/mp4"

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            // ── Android 10+ MediaStore ────────────────────────────────────────
            val resolver = applicationContext.contentResolver
            val values   = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, fileName)
                put(MediaStore.Downloads.MIME_TYPE,    mime)
                put(MediaStore.Downloads.IS_PENDING,   1)
            }
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw Exception("MediaStore insert 失敗")

            resolver.openOutputStream(uri)?.use { out ->
                src.inputStream().use { it.copyTo(out) }
            }
            values.clear()
            values.put(MediaStore.Downloads.IS_PENDING, 0)
            resolver.update(uri, values, null, null)

            Log.i(logTag, "[saveToDownloads] ✅ MediaStore: $fileName")
            uri.toString()   // 回傳 content URI 字串
        } else {
            // ── Android 9- Environment ────────────────────────────────────────
            val downloadsDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
            downloadsDir.mkdirs()
            val dst = java.io.File(downloadsDir, fileName)
            src.copyTo(dst, overwrite = true)
            Log.i(logTag, "[saveToDownloads] ✅ 舊版: ${dst.absolutePath}")
            dst.absolutePath
        }
    }

    /**
     * 將 [srcPath] 的影片寫入使用者透過 SAF 選取的資料夾，回傳儲存位置 URI 字串。
     */
    @Throws(Exception::class)
    private fun saveToPickedFolder(treeUri: android.net.Uri, srcPath: String, fileName: String): String {
        val src      = java.io.File(srcPath)
        require(src.exists()) { "來源檔案不存在: $srcPath" }
        val mime     = if (fileName.lowercase().endsWith(".mov")) "video/quicktime" else "video/mp4"
        val resolver = applicationContext.contentResolver

        val treeDoc  = androidx.documentfile.provider.DocumentFile.fromTreeUri(applicationContext, treeUri)
            ?: throw Exception("無法存取選取的資料夾")
        val newDoc   = treeDoc.createFile(mime, fileName)
            ?: throw Exception("無法在選取資料夾建立檔案")

        resolver.openOutputStream(newDoc.uri)?.use { out ->
            src.inputStream().use { it.copyTo(out) }
        } ?: throw Exception("無法開啟輸出串流")

        Log.i(logTag, "[pickFolderAndSave] ✅ 儲存到: ${newDoc.uri}")
        return newDoc.uri.toString()
    }
}
