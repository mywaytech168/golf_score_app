package com.example.golf_score_app

import android.content.Intent
import android.graphics.Bitmap
import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Bundle
import android.util.Log
import android.view.KeyEvent
import android.view.WindowManager
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.Executors

// ✅ Google ML Kit Pose Detection 相關導入
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.pose.Pose
import com.google.mlkit.vision.pose.PoseDetection
import com.google.mlkit.vision.pose.PoseDetector
import com.google.mlkit.vision.pose.defaults.PoseDetectorOptions

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
    private val overlayExecutor = Executors.newSingleThreadExecutor()
    private val audioExtractorExecutor = Executors.newSingleThreadExecutor()
    private val skeletonExecutor = Executors.newSingleThreadExecutor()
    private val ballTrajExecutor = Executors.newSingleThreadExecutor()
    private val frameExtractorExecutor = Executors.newSingleThreadExecutor()
    private val logTag = "MainActivity"
    private val videoTrimmer by lazy { VideoTrimmer(this) }
    private val skeletonRenderer by lazy { SkeletonOverlayRenderer(this) }
    private val ballBlobExtractor      by lazy { BallBlobExtractor() }
    private val trajectoryOverlayRenderer by lazy { TrajectoryOverlayRenderer() }
    
    // ✅ ML Kit Pose Detector (延遲初始化)
    private val poseDetector: PoseDetector by lazy {
        val options = PoseDetectorOptions.Builder()
            .setDetectorMode(PoseDetectorOptions.STREAM_MODE)  // 連續模式，適合視頻分析
            .build()
        PoseDetection.getClient(options)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
                                result.success(
                                    mapOf(
                                        "path" to extraction.path,
                                        "sampleRate" to extraction.sampleRate,
                                        "channels" to extraction.channelCount
                                    )
                                )
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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SKELETON_OVERLAY_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "render") {
                    val clipPath = call.argument<String>("clipPath")
                    val csvPath = call.argument<String>("csvPath")
                    val startSec = call.argument<Double>("startSec") ?: 0.0
                    val outputPath = call.argument<String>("outputPath")

                    if (clipPath.isNullOrBlank() || csvPath.isNullOrBlank() || outputPath.isNullOrBlank()) {
                        result.error("invalid_args", "缺少必要參數", null)
                        return@setMethodCallHandler
                    }

                    skeletonExecutor.execute {
                        try {
                            val ok = skeletonRenderer.render(
                                clipPath = clipPath,
                                csvPath = csvPath,
                                startSec = startSec,
                                outputPath = outputPath
                            )
                            if (!ok) {
                                Log.e(logTag, "骨架渲染失敗，不執行後續流程")
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
                                val data = ballBlobExtractor.extract(inputPath)
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
                                val data = ballBlobExtractor.extract(inputPath, configMap)
                                
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

                    // ── Step 2：Kotlin I/O 層 → 疊加軌跡 ───────────────
                    "renderOverlay" -> {
                        val inputPath  = call.argument<String>("inputPath")
                        val outputPath = call.argument<String>("outputPath")
                        @Suppress("UNCHECKED_CAST")
                        val trackPts   = call.argument<List<Map<String, Any>>>("trackPts")
                        val roiSize    = call.argument<Int>("roiSize") ?: 0  // 可選，預設 0（不繪製 ROI）

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
                    else -> result.notImplemented()
                }
            }
        
        // ✅ 完整 Kotlin 原生方案：一次完成全部視頻分析
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, POSE_ANALYZER_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "analyzePoseVideo" -> {
                        val videoPath = call.argument<String>("videoPath")
                        // Flutter MethodChannel 傳 Dart int 為 Java Long，不能直接用 call.argument<Int>()
                        val targetFps = (call.argument<Any>("targetFps") as? Number)?.toInt() ?: 30
                        val maxWidth  = (call.argument<Any>("maxWidth")  as? Number)?.toInt() ?: 720
                        val outputCsvPath = call.argument<String>("outputCsvPath")
                        Log.i(logTag, "[PoseAnalyzer] targetFps=$targetFps maxWidth=$maxWidth")
                        
                        if (videoPath.isNullOrBlank() || outputCsvPath.isNullOrBlank()) {
                            result.error("invalid_args", "缺少 videoPath 或 outputCsvPath", null)
                            return@setMethodCallHandler
                        }
                        
                        frameExtractorExecutor.execute {
                            try {
                                val csvPath = analyzeVideoNatively(
                                    videoPath,
                                    targetFps,
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
                                        result.error("analysis_failed", "分析失敗", null)
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
    }

    private data class AudioExtractionResult(
        val path: String,
        val sampleRate: Int,
        val channelCount: Int
    )

    @Throws(IOException::class)
    private fun extractAudioToWav(videoPath: String): AudioExtractionResult {
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
            throw IllegalStateException("No audio track found in video.")
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

    
    // ✅ 原生全影片分析：一個 MediaCodec 實例 + ML Kit + 直接寫 CSV
    // 比舊方案（每幀開一個 MediaMetadataRetriever + JNI 傳 1.3MB）快 3-5x
    private fun analyzeVideoNatively(
        videoPath: String,
        targetFps: Int,
        maxWidth: Int,
        outputCsvPath: String
    ): String? {
        // 🎬 記錄輸入參數
        Log.i(logTag, "[PoseAnalyzer] 🎬 開始分析: targetFps=$targetFps maxWidth=$maxWidth videoPath=$videoPath")
        
        val extractor = MediaExtractor()
        var codec: MediaCodec? = null
        var csvWriter: java.io.FileWriter? = null
        var localDetector: com.google.mlkit.vision.pose.PoseDetector? = null

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

            // 🎬 讀取視頻的實際 fps metadata（重要：不能只依賴 targetFps 參數！）
            val actualVideoFps = runCatching {
                videoFormat.getInteger(MediaFormat.KEY_FRAME_RATE)
            }.getOrElse { targetFps }
            Log.i(logTag, "[PoseAnalyzer] 🎬 fps metadata: targetFps=$targetFps, actualVideoFps=$actualVideoFps from format")

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
            codec = MediaCodec.createDecoderByType(mime)
            codec.configure(videoFormat, null, null, 0)
            codec.start()

            // SINGLE_IMAGE_MODE：每幀獨立推理，不觸發 PoseMiniBenchmarkWorker
            // （STREAM_MODE 會在背景啟動 benchmark worker，已知在 beta 版本有 JNI crash 問題）
            localDetector = PoseDetection.getClient(
                PoseDetectorOptions.Builder()
                    .setDetectorMode(PoseDetectorOptions.SINGLE_IMAGE_MODE)
                    .build()
            )

            // CSV 標頭（格式與 PoseFrameModel.toCsvRow 完全對齊：6 值/關鍵點）
            val csvFile = java.io.File(outputCsvPath)
            csvFile.parentFile?.mkdirs()
            csvWriter = java.io.FileWriter(csvFile)
            val header = buildString {
                append("frame,time_sec,pose_update_id")
                for (i in 0..32) append(",lm${i}_xNorm,lm${i}_yNorm,lm${i}_z,lm${i}_visibility,lm${i}_xPx,lm${i}_yPx")
            }
            csvWriter.write(header + "\n")

            val bufferInfo = MediaCodec.BufferInfo()
            var frameCount  = 0
            var decodedFrames = 0  // 🎬 追踪解碼的總幀數
            var poseUpdateId = 0
            var lastLandmarks: List<com.google.mlkit.vision.pose.PoseLandmark>? = null
            var mlKitFailures = 0

            // 🎬 使用實際視頻 fps 計算採樣間隔，而不是硬編碼的 targetFps
            val frameIntervalUs = 1_000_000L / actualVideoFps
            var nextSampleUs   = 0L
            var inputEOS  = false
            var outputEOS = false
            
            // 🎬 容差：允許 ±500 微秒的誤差，防止因 ptsUs 微小偏差導致的採樣邏輯錯誤
            val SAMPLE_TOLERANCE_US = 500L
            
            // 🎬 詳細記錄採樣參數
            Log.i(logTag, "[PoseAnalyzer] 🎬 採樣配置: actualVideoFps=$actualVideoFps, frameIntervalUs=$frameIntervalUs us (${frameIntervalUs/1000.0f}ms)")
            Log.i(logTag, "[PoseAnalyzer] 🎬 初始 nextSampleUs=$nextSampleUs, tolerance=±${SAMPLE_TOLERANCE_US}us")

            val sw = System.currentTimeMillis()

            while (!outputEOS) {
                // ── 餵解碼器 ────────────────────────────
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

                // ── 取解碼輸出 ──────────────────────────
                val outIdx = codec.dequeueOutputBuffer(bufferInfo, 10_000L)
                when {
                    outIdx == MediaCodec.INFO_TRY_AGAIN_LATER -> { /* 繼續 */ }
                    outIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> { /* 繼續 */ }
                    outIdx >= 0 -> {
                        val ptsUs = bufferInfo.presentationTimeUs
                        decodedFrames++

                        // 🎬 詳細診斷：每幀都記錄採樣決策
                        val shouldSample = ptsUs >= nextSampleUs - SAMPLE_TOLERANCE_US && bufferInfo.size > 0
                        if (decodedFrames <= 10 || decodedFrames % 30 == 0) {
                            Log.d(logTag, "[PoseAnalyzer] 幀#$decodedFrames: ptsUs=$ptsUs, nextSample=$nextSampleUs, shouldSample=$shouldSample, diff=${ptsUs - nextSampleUs}")
                        }

                        if (shouldSample) {
                            // 🎬 採樣此幀
                            nextSampleUs = ptsUs + frameIntervalUs
                            val timeSec  = ptsUs / 1_000_000.0
                            
                            // 間隔 30 幀時才記錄一次，避免日誌爆炸
                            if (frameCount % 30 == 0) {
                                Log.d(logTag, "[PoseAnalyzer] ✅ 採樣幀 #$frameCount: ptsUs=$ptsUs μs → 下次採樣=$nextSampleUs μs")
                            }

                            val image = runCatching { codec.getOutputImage(outIdx) }.getOrNull()
                            if (image != null) {
                                try {
                                    // fromMediaImage: ML Kit 直接消費 YUV_420_888 Image，
                                    // 無需手動轉 NV21，rotation 由 ML Kit 內部處理。
                                    // image 必須在 Tasks.await 返回後才能 close（finally 保證順序）。
                                    val inputImage = InputImage.fromMediaImage(image, rotation)

                                    val pose = try {
                                        Tasks.await(localDetector!!.process(inputImage))
                                    } catch (e: Exception) {
                                        mlKitFailures++
                                        Log.w(logTag, "[PoseAnalyzer] ML Kit fail frame=$frameCount (${mlKitFailures}x): ${e.message}")
                                        null
                                    }

                                    val landmarks = pose?.allPoseLandmarks ?: emptyList()

                                    if (landmarks.isNotEmpty()) {
                                        val changed = if (lastLandmarks != null && landmarks.size == lastLandmarks!!.size) {
                                            landmarks.zip(lastLandmarks!!).any { (a, b) ->
                                                kotlin.math.abs(a.position.x - b.position.x) > 0.5f ||
                                                kotlin.math.abs(a.position.y - b.position.y) > 0.5f
                                            }
                                        } else true
                                        if (changed) poseUpdateId++
                                        lastLandmarks = landmarks
                                    }

                                    // ML Kit position 座標在 fromMediaImage 傳入 rotation 後
                                    // 已轉換到 display（旋轉後）的像素空間，用 displayW/H 正規化
                                    val sb = StringBuilder("$frameCount,$timeSec,$poseUpdateId")
                                    if (landmarks.isNotEmpty()) {
                                        val lmMap = landmarks.associateBy { it.landmarkType }
                                        for (idx in 0..32) {
                                            val lm = lmMap[idx]
                                            if (lm != null) {
                                                val xPx = lm.position.x
                                                val yPx = lm.position.y
                                                val z   = runCatching { lm.position3D.z }.getOrElse { 0f }
                                                val vis = lm.inFrameLikelihood
                                                sb.append(",${xPx/displayW},${yPx/displayH},$z,$vis,$xPx,$yPx")
                                            } else {
                                                sb.append(",NaN,NaN,NaN,0.0,NaN,NaN")
                                            }
                                        }
                                    } else {
                                        repeat(33) { sb.append(",NaN,NaN,NaN,0.0,NaN,NaN") }
                                    }
                                    csvWriter.write(sb.toString() + "\n")

                                } finally {
                                    image.close()
                                }
                            } else {
                                // getOutputImage 失敗（少數裝置）：寫空行保持 frameIndex 連貫
                                val sb = StringBuilder("$frameCount,$timeSec,$poseUpdateId")
                                repeat(33) { sb.append(",NaN,NaN,NaN,0.0,NaN,NaN") }
                                csvWriter.write(sb.toString() + "\n")
                            }
                            frameCount++
                        }

                        codec.releaseOutputBuffer(outIdx, false)
                        if ((bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) outputEOS = true
                    }
                }
            }

            csvWriter.flush()
            val elapsedMs = System.currentTimeMillis() - sw
            val fps = if (elapsedMs > 0) "%.1f".format(frameCount * 1000.0 / elapsedMs) else "N/A"
            Log.i(logTag, "[PoseAnalyzer] 📊 処理完成:")
            Log.i(logTag, "[PoseAnalyzer]   總解碼幀: $decodedFrames")
            Log.i(logTag, "[PoseAnalyzer]   已採樣幀: $frameCount")
            Log.i(logTag, "[PoseAnalyzer]   採樣率: ${(frameCount * 100.0 / maxOf(1, decodedFrames)).toInt()}% (${decodedFrames - frameCount} 幀被跳過)")
            Log.i(logTag, "[PoseAnalyzer]   預期幀數: $expectedFrames")
            Log.i(logTag, "[PoseAnalyzer]   差異: ${expectedFrames - frameCount} 幀 (${(frameCount * 100.0 / maxOf(1, expectedFrames)).toInt()}% of expected)")
            Log.i(logTag, "[PoseAnalyzer] done: $frameCount frames, ${elapsedMs}ms, ${fps}fps, mlkit_fail=${mlKitFailures} -> $outputCsvPath")
            if (mlKitFailures > 0) Log.w(logTag, "[PoseAnalyzer] mlkit_fail=${mlKitFailures} frames (version compat or hw accel issue)")
            if (frameCount < expectedFrames * 0.8) {
                Log.w(logTag, "[PoseAnalyzer] ⚠️ 幀數異常: 只寫入 ${(frameCount * 100.0 / maxOf(1, expectedFrames)).toInt()}% 的預期幀數！")
                Log.w(logTag, "[PoseAnalyzer] 💡 原因分析:")
                Log.w(logTag, "[PoseAnalyzer]    - decodedFrames=$decodedFrames (實際解碼)")
                Log.w(logTag, "[PoseAnalyzer]    - expectedFrames=$expectedFrames (理論預期)")
                Log.w(logTag, "[PoseAnalyzer]    - frameCount=$frameCount (實際採樣)")
                Log.w(logTag, "[PoseAnalyzer]    如果 decodedFrames ≈ expectedFrames 但 frameCount << 採樣，是採樣邏輯問題")
                Log.w(logTag, "[PoseAnalyzer]    如果 decodedFrames << expectedFrames，是解碼幀率或時長讀取問題")
            }
            return outputCsvPath

        } catch (e: Exception) {
            Log.e(logTag, "[PoseAnalyzer] 分析失敗: ${e.message}", e)
            return null
        } finally {
            runCatching { localDetector?.close() }
            runCatching { csvWriter?.close() }
            runCatching { codec?.stop(); codec?.release() }
            runCatching { extractor.release() }
        }
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
    
    // ML Kit 骨架檢測
    // ✅ ML Kit 骨架檢測 - 完整實現
    private fun detectPoseWithMLKit(bitmap: Bitmap): List<FloatArray>? {
        return try {
            Log.d(logTag, "[MLKit] 檢測骨架: ${bitmap.width}x${bitmap.height}")
            
            // 建立 InputImage (ML Kit 需要的格式)
            val inputImage = InputImage.fromBitmap(bitmap, 0)
            
            // 執行骨架檢測 (同步操作，在背景線程執行)
            val pose: Pose = Tasks.await(poseDetector.process(inputImage))
            
            // 轉換為 FloatArray 列表
            val landmarks = pose.allPoseLandmarks.map { landmark ->
                // 嘗試獲取 z 值，如果不可用則使用 0
                val zValue = try {
                    val zField = landmark.javaClass.getDeclaredField("z")
                    zField.isAccessible = true
                    zField.getFloat(landmark)
                } catch (e: Exception) {
                    Log.d(logTag, "[MLKit] z 屬性不可用: ${e.message}")
                    0f
                }
                
                floatArrayOf(
                    landmark.position.x,
                    landmark.position.y,
                    zValue,
                    landmark.inFrameLikelihood
                )
            }
            
            Log.d(logTag, "[MLKit] 回傳 ${landmarks.size} 個關鍵點")
            landmarks
            
        } catch (e: Exception) {
            Log.e(logTag, "[MLKit] 檢測例外: ${e.message}", e)
            null
        }
    }
    
    // 比較兩個骨架是否相同（容差：1.0 像素）
    private fun isSamePose(pose1: List<FloatArray>, pose2: List<FloatArray>): Boolean {
        if (pose1.size != pose2.size) return false
        
        // 只比較有效的關鍵點（inFrameLikelihood > 0.1）
        var validCount = 0
        var changeCount = 0
        
        for (i in pose1.indices) {
            val confidence1 = if (pose1[i].size > 3) pose1[i][3] else 0.5f
            val confidence2 = if (pose2[i].size > 3) pose2[i][3] else 0.5f
            
            if (confidence1 > 0.1f && confidence2 > 0.1f) {
                val dx = pose1[i][0] - pose2[i][0]
                val dy = pose1[i][1] - pose2[i][1]
                val distance = kotlin.math.sqrt(dx * dx + dy * dy)
                
                validCount++
                if (distance > 1.0f) {  // 容差 1.0 像素
                    changeCount++
                }
            }
        }
        
        // 如果超過 50% 的有效關鍵點改變了位置，則認為姿態變化了
        return if (validCount > 0) changeCount.toFloat() / validCount > 0.5f else false
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
}
