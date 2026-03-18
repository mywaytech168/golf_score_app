package com.example.golf_score_app

import android.content.Intent
import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
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

class MainActivity: FlutterActivity() {
    private val CHANNEL = "volume_button_channel"
    private val SHARE_CHANNEL = "share_intent_channel"
    private val KEEP_SCREEN_CHANNEL = "keep_screen_on_channel"
    private val AUDIO_EXTRACT_CHANNEL = "audio_extractor_channel"
    private val VIDEO_OVERLAY_CHANNEL = "video_overlay_channel"
    private val TRIMMER_CHANNEL = "com.example.golf_score_app/trimmer"
    private val TRAJECTORY_CHANNEL = "com.example.golf_score_app/trajectory"
    private val overlayExecutor = Executors.newSingleThreadExecutor()
    private val audioExtractorExecutor = Executors.newSingleThreadExecutor()
    private val trajectoryExecutor = Executors.newSingleThreadExecutor()
    private val logTag = "MainActivity"
    private val videoTrimmer by lazy { VideoTrimmer(this) }
    private val trajectoryAnalyzer by lazy { TrajectoryAnalyzer() }

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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, TRAJECTORY_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "analyzeTrajectory") {
                    val videoPath = call.argument<String>("videoPath")
                    if (videoPath.isNullOrBlank()) {
                        result.error("invalid_args", "videoPath is empty", null)
                        return@setMethodCallHandler
                    }
                    trajectoryExecutor.execute {
                        try {
                            val r = trajectoryAnalyzer.analyze(videoPath)
                            runOnUiThread {
                                result.success(
                                    mapOf(
                                        "hit_frame" to r.hitFrame,
                                        "init_ball" to r.initBall,
                                        "polyfit" to r.polyfit,
                                        "points" to r.points
                                    )
                                )
                            }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("analysis_failed", e.message, null) }
                        }
                    }
                } else {
                    result.notImplemented()
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
        trajectoryExecutor.shutdown()
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
