package com.example.golf_score_app

import android.content.Intent
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
import java.util.concurrent.Executors

class MainActivity: FlutterActivity() {
    private val CHANNEL = "volume_button_channel"
    private val SHARE_CHANNEL = "share_intent_channel"
    private val KEEP_SCREEN_CHANNEL = "keep_screen_on_channel"
    private val VIDEO_OVERLAY_CHANNEL = "video_overlay_channel"
    private val overlayExecutor = Executors.newSingleThreadExecutor()
    private val logTag = "MainActivity"

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
    }
}
