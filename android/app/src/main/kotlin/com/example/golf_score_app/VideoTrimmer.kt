package com.example.golf_score_app

import android.content.Context
import android.net.Uri
import androidx.media3.common.MediaItem
import androidx.media3.transformer.TransformationException
import androidx.media3.transformer.Transformer
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Lightweight wrapper around Media3 Transformer to trim a segment into a new file.
 */
class VideoTrimmer(private val context: Context) {
    private val tag = "VideoTrimmer"

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "trim") {
            result.notImplemented()
            return
        }
        val args = call.arguments as? Map<*, *>
        val srcPath = args?.get("srcPath") as? String
        val dstPath = args?.get("dstPath") as? String
        val startMs = (args?.get("startMs") as? Number)?.toLong() ?: 0L
        val endMs = (args?.get("endMs") as? Number)?.toLong()

        if (srcPath.isNullOrBlank() || dstPath.isNullOrBlank() || endMs == null) {
            result.error("invalid_args", "缺少必要參數 srcPath/dstPath/startMs/endMs", null)
            return
        }

        val srcFile = File(srcPath)
        if (!srcFile.exists()) {
            result.error("file_not_found", "來源影片不存在: $srcPath", null)
            return
        }

        val mediaItem = MediaItem.Builder()
            .setUri(Uri.fromFile(srcFile))
            .setClippingConfiguration(
                MediaItem.ClippingConfiguration.Builder()
                    .setStartPositionMs(startMs)
                    .setEndPositionMs(endMs)
                    .build()
            )
            .build()

        val transformer = Transformer.Builder(context)
            .addListener(
                object : Transformer.Listener {
                    override fun onTransformationCompleted(mediaItem: MediaItem) {
                        result.success(true)
                    }

                    override fun onTransformationError(
                        mediaItem: MediaItem,
                        exception: TransformationException
                    ) {
                        result.error("transform_error", exception.message, null)
                    }
                }
            )
            .build()

        // 確保目錄存在
        File(dstPath).parentFile?.mkdirs()

        try {
            transformer.start(mediaItem, dstPath)
        } catch (e: Exception) {
            result.error("transform_start_error", e.message, null)
        }
    }
}
