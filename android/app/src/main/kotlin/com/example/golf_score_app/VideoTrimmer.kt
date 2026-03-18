package com.example.golf_score_app

import android.content.Context
import android.net.Uri
import androidx.media3.common.MediaItem
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.Transformer
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

class VideoTrimmer(private val context: Context) {

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
            result.error("invalid_args", "缺少 srcPath / dstPath / startMs / endMs", null)
            return
        }

        val srcFile = File(srcPath)
        if (!srcFile.exists()) {
            result.error("file_not_found", "來源影片不存在: $srcPath", null)
            return
        }

        // 1️⃣ MediaItem（裁切）
        val mediaItem = MediaItem.Builder()
            .setUri(Uri.fromFile(srcFile))
            .setClippingConfiguration(
                MediaItem.ClippingConfiguration.Builder()
                    .setStartPositionMs(startMs)
                    .setEndPositionMs(endMs)
                    .build()
            )
            .build()

        // 2️⃣ EditedMediaItem
        val editedMediaItem = EditedMediaItem.Builder(mediaItem).build()

        // 3️⃣ EditedMediaItemSequence
        val sequence = EditedMediaItemSequence(editedMediaItem)

        // 4️⃣ Composition（⚠️ 沒有 .build()）
        val composition = Composition.Builder(listOf(sequence)).build()

        // 確保輸出目錄存在
        File(dstPath).parentFile?.mkdirs()

        val transformer = Transformer.Builder(context)
            .addListener(
                object : Transformer.Listener {

                    override fun onCompleted(
                        composition: Composition,
                        exportResult: ExportResult
                    ) {
                        result.success(true)
                    }

                    override fun onError(
                        composition: Composition,
                        exportResult: ExportResult,
                        exportException: ExportException
                    ) {
                        result.error(
                            "transform_error",
                            exportException.errorCodeName,
                            null
                        )
                    }
                }
            )
            .build()

        try {
            transformer.start(composition, dstPath)
        } catch (e: Exception) {
            result.error("transform_start_error", e.message, null)
        }
    }
}
