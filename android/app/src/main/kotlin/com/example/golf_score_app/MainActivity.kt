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

                    // ── Step 2：Kotlin I/O 層 → 疊加軌跡 ───────────────
                    "renderOverlay" -> {
                        val inputPath  = call.argument<String>("inputPath")
                        val outputPath = call.argument<String>("outputPath")
                        @Suppress("UNCHECKED_CAST")
                        val trackPts   = call.argument<List<Map<String, Any>>>("trackPts")

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
                        val targetFps = call.argument<Int>("targetFps") ?: 15
                        val maxWidth = call.argument<Int>("maxWidth") ?: 480
                        val outputCsvPath = call.argument<String>("outputCsvPath")
                        
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

    
    // ✅ 方案 B: 完整 Kotlin 原生方案 - 一次開啟 MediaExtractor/MediaCodec + ML Kit + CSV
    private fun analyzeVideoNatively(
        videoPath: String,
        targetFps: Int,
        maxWidth: Int,
        outputCsvPath: String
    ): String? {
        val extractor = MediaExtractor()
        var codec: MediaCodec? = null
        var csvWriter: java.io.FileWriter? = null
        
        try {
            extractor.setDataSource(videoPath)
            
            // 找到視頻軌道和時長
            var videoTrackIndex = -1
            var videoDurationUs = 0L
            for (i in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(i)
                val mime = format.getString(MediaFormat.KEY_MIME) ?: ""
                if (mime.startsWith("video/")) {
                    videoTrackIndex = i
                    videoDurationUs = format.getLong(MediaFormat.KEY_DURATION)
                    break
                }
            }
            
            if (videoTrackIndex < 0) {
                Log.e(logTag, "[PoseAnalyzer] 找不到視頻軌道")
                return null
            }
            
            val videoFormat = extractor.getTrackFormat(videoTrackIndex)
            val videoWidth = videoFormat.getInteger(MediaFormat.KEY_WIDTH)
            val videoHeight = videoFormat.getInteger(MediaFormat.KEY_HEIGHT)
            val frameRate = if (videoFormat.containsKey(MediaFormat.KEY_FRAME_RATE)) {
                videoFormat.getInteger(MediaFormat.KEY_FRAME_RATE)
            } else {
                30  // 默認假設 30fps
            }
            val mime = videoFormat.getString(MediaFormat.KEY_MIME) ?: ""
            
            Log.i(logTag, "[PoseAnalyzer] 視頻: ${videoWidth}x${videoHeight}, fps=$frameRate, duration=${videoDurationUs/1000}ms")
            
            extractor.selectTrack(videoTrackIndex)
            
            // 建立解碼器
            codec = MediaCodec.createDecoderByType(mime)
            codec.configure(videoFormat, null, null, 0)
            codec.start()
            
            // 計算採樣間隔（微秒）
            val frameIntervalUs = (1000000L / targetFps)
            var nextSampleTimeUs = 0L
            
            // 初始化 CSV
            val csvFile = java.io.File(outputCsvPath)
            csvFile.parentFile?.mkdirs()
            csvWriter = java.io.FileWriter(csvFile)
            
            // CSV 標頭
            csvWriter.write("frame,time_sec,pose_update_id")
            for (i in 0..32) {  // 33 個關鍵點 (0-32)
                csvWriter.write(",lm${i}_x,lm${i}_y,lm${i}_z,lm${i}_confidence")
            }
            csvWriter.write("\n")
            
            val bufferInfo = MediaCodec.BufferInfo()
            var frameCount = 0
            var poseUpdateId = 0
            var lastPoseLandmarks: List<FloatArray>? = null
            
            // 解碼整支影片
            var inputEOS = false
            var outputEOS = false
            var maxDecodeAttempts = 200
            
            while (!outputEOS && maxDecodeAttempts-- > 0) {
                // 餵入數據
                if (!inputEOS) {
                    val inputIndex = codec.dequeueInputBuffer(10000)
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
                                inputEOS = true
                            }
                        }
                    }
                }
                
                // 提取輸出
                val outputIndex = codec.dequeueOutputBuffer(bufferInfo, 10000)
                if (outputIndex >= 0) {
                    val outputBuffer = codec.getOutputBuffer(outputIndex)
                    if (outputBuffer != null && bufferInfo.size > 0) {
                        val presentationTimeUs = bufferInfo.presentationTimeUs
                        
                        // ✅ 根據 targetFps 採樣
                        if (presentationTimeUs >= nextSampleTimeUs) {
                            nextSampleTimeUs = presentationTimeUs + frameIntervalUs
                            
                            // 解碼 YUV → RGB → ML Kit
                            val bitmap = decodeYuvToRgb(outputBuffer, videoWidth, videoHeight, maxWidth)
                            if (bitmap != null) {
                                // ML Kit 骨架檢測
                                val landmarks = detectPoseWithMLKit(bitmap)
                                bitmap.recycle()
                                
                                // 檢查是否變化
                                val hasChanged = if (lastPoseLandmarks != null && landmarks != null) {
                                    isSamePose(lastPoseLandmarks!!, landmarks)
                                } else {
                                    landmarks != null
                                }
                                
                                if (hasChanged) poseUpdateId++
                                
                                // 寫入 CSV
                                if (landmarks != null) {
                                    val timeMs = presentationTimeUs / 1000L
                                    val timeSec = timeMs / 1000.0
                                    csvWriter.write("$frameCount,$timeSec,$poseUpdateId")
                                    
                                    for (lm in landmarks) {
                                        // 格式: x, y, z, confidence
                                        val x = lm.getOrNull(0) ?: 0f
                                        val y = lm.getOrNull(1) ?: 0f
                                        val z = lm.getOrNull(2) ?: 0f
                                        val confidence = lm.getOrNull(3) ?: 0f
                                        csvWriter.write(",$x,$y,$z,$confidence")
                                    }
                                    csvWriter.write("\n")
                                    
                                    Log.d(logTag, "[PoseAnalyzer] Frame $frameCount @ ${timeMs}ms, pose_id=$poseUpdateId")
                                    frameCount++
                                    lastPoseLandmarks = landmarks
                                }
                            }
                        }
                    }
                    codec.releaseOutputBuffer(outputIndex, false)
                }
                
                if ((bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                    outputEOS = true
                }
            }
            
            csvWriter.flush()
            Log.i(logTag, "[PoseAnalyzer] ✅ 完成：$frameCount 幀已寫入 $outputCsvPath")
            
            return outputCsvPath
            
        } catch (e: Exception) {
            Log.e(logTag, "[PoseAnalyzer] 分析失敗: ${e.message}", e)
            return null
        } finally {
            try {
                csvWriter?.close()
            } catch (e: Exception) {
                Log.e(logTag, "[PoseAnalyzer] 關閉 CSV 失敗: ${e.message}")
            }
            try {
                codec?.stop()
                codec?.release()
            } catch (e: Exception) {
                Log.e(logTag, "[PoseAnalyzer] 釋放 codec 失敗: ${e.message}")
            }
            try {
                extractor.release()
            } catch (e: Exception) {
                Log.e(logTag, "[PoseAnalyzer] 釋放 extractor 失敗: ${e.message}")
            }
        }
    }
    
    // ML Kit 骨架檢測
    // ✅ ML Kit 骨架檢測 - 完整實現
    private fun detectPoseWithMLKit(bitmap: Bitmap): List<FloatArray>? {
        return try {
            Log.d(logTag, "[MLKit] 檢測骨架: ${bitmap.width}x${bitmap.height}")
            
            // 建立 InputImage (ML Kit 需要的格式)
            val inputImage = InputImage.fromBitmap(bitmap, 0)
            
            // 執行骨架檢測 (同步操作，在背景線程執行)
            val pose: Pose = poseDetector.process(inputImage)
                .addOnSuccessListener { detectedPose ->
                    Log.d(logTag, "[MLKit] ✅ 檢測成功，找到 ${detectedPose.allPoseLandmarks.size} 個關鍵點")
                }
                .addOnFailureListener { e ->
                    Log.e(logTag, "[MLKit] ❌ 檢測失敗: ${e.message}")
                }
                .getResult()  // 阻塞等待結果
            
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
