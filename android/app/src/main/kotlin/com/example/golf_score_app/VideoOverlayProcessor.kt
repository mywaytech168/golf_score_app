package com.example.golf_score_app

import android.content.Context
import android.graphics.*
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import androidx.annotation.WorkerThread
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.BitmapOverlay
import androidx.media3.effect.OverlayEffect
import androidx.media3.effect.OverlaySettings
import androidx.media3.effect.TextureOverlay
import androidx.media3.transformer.Composition
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.TransformationRequest
import androidx.media3.transformer.Transformer
import java.io.File
import java.util.concurrent.CountDownLatch
import kotlin.math.min

@OptIn(UnstableApi::class)
class VideoOverlayProcessor(private val context: Context) {

    /**
     * 透過 Media3 Transformer 將頭像與文字覆蓋到指定影片。
     * - 若未勾選任何覆蓋選項則直接複製來源檔案。
     * - 原生層使用 CountDownLatch 等待轉檔完成，並於錯誤時拋出例外讓 Flutter 顯示提示。
     */
    @WorkerThread
    fun process(
        inputPath: String,
        outputPath: String,
        attachAvatar: Boolean,
        avatarPath: String?,
        attachCaption: Boolean,
        captionText: String
    ): String {
        val inputFile = File(inputPath)
        require(inputFile.exists()) { "來源影片不存在" }

        // 無需覆蓋時僅複製原檔，避免耗費額外時間與系統資源。
        if (!attachAvatar && (!attachCaption || captionText.isBlank())) {
            inputFile.copyTo(File(outputPath), overwrite = true)
            return outputPath
        }

        val (videoWidth, videoHeight) = resolveVideoSize(inputPath)
        if (videoWidth <= 0 || videoHeight <= 0) {
            throw IllegalStateException("無法判斷影片尺寸")
        }

        val overlays = mutableListOf<TextureOverlay>()
        val retainedBitmaps = mutableListOf<Bitmap>() // 保留位圖引用，避免在轉檔期間被回收

        if (attachAvatar && !avatarPath.isNullOrEmpty()) {
            createCircularAvatar(avatarPath, 220)?.let { avatarBitmap ->
                val marginPx = 32
                val anchorX = 1f - (marginPx * 2f / videoWidth)
                val anchorY = 1f - (marginPx * 2f / videoHeight)
                val overlaySettings = OverlaySettings.Builder()
                    .setBackgroundFrameAnchor(anchorX.coerceIn(-1f, 1f), anchorY.coerceIn(-1f, 1f))
                    .setOverlayFrameAnchor(1f, 1f)
                    .setScale(
                        avatarBitmap.width.toFloat() / videoWidth,
                        avatarBitmap.height.toFloat() / videoHeight
                    )
                    .build()
                overlays.add(BitmapOverlay.createStaticBitmapOverlay(avatarBitmap, overlaySettings))
                retainedBitmaps.add(avatarBitmap)
            }
        }

        if (attachCaption && captionText.isNotBlank()) {
            createCaptionBitmap(captionText.trim(), videoWidth)?.let { captionBitmap ->
                val marginPx = 48
                val anchorY = -1f + (marginPx * 2f / videoHeight)
                val overlaySettings = OverlaySettings.Builder()
                    .setBackgroundFrameAnchor(0f, anchorY.coerceIn(-1f, 1f))
                    .setOverlayFrameAnchor(0f, -1f)
                    .setScale(
                        captionBitmap.width.toFloat() / videoWidth,
                        captionBitmap.height.toFloat() / videoHeight
                    )
                    .build()
                overlays.add(BitmapOverlay.createStaticBitmapOverlay(captionBitmap, overlaySettings))
                retainedBitmaps.add(captionBitmap)
            }
        }

        if (overlays.isEmpty()) {
            inputFile.copyTo(File(outputPath), overwrite = true)
            return outputPath
        }

        val outputFile = File(outputPath)
        outputFile.parentFile?.mkdirs()
        if (outputFile.exists()) {
            outputFile.delete()
        }

        val latch = CountDownLatch(1)
        var error: Exception? = null

        // 明確指定輸出影音編碼，避免裝置以預設格式產出播放器無法解析的檔案
        val transformationRequest = TransformationRequest.Builder()
            .setVideoMimeType(MimeTypes.VIDEO_H264)
            .setAudioMimeType(MimeTypes.AUDIO_AAC)
            .build()

        val transformer = Transformer.Builder(context)
            .setTransformationRequest(transformationRequest)
            .setVideoEffects(listOf(OverlayEffect(overlays)))
            .addListener(object : Transformer.Listener {
                override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                    latch.countDown()
                }

                override fun onError(
                    composition: Composition,
                    exportResult: ExportResult,
                    exportException: ExportException
                ) {
                    error = exportException
                    latch.countDown()
                }
            })
            .build()
        // Transformer 建立在方法作用域內，轉檔完成後即失去引用，交由 GC 自行回收底層資源

        try {
            transformer.startTransformation(
                MediaItem.fromUri(Uri.fromFile(inputFile)),
                outputPath
            )

            try {
                latch.await()
            } catch (interrupted: InterruptedException) {
                // 若等待期間被中斷，保留例外並恢復執行緒中斷狀態
                Thread.currentThread().interrupt()
                error = interrupted
            }
        }

        retainedBitmaps.forEach { it.recycle() }

        error?.let {
            outputFile.delete()
            throw it
        }

        if (!outputFile.exists()) {
            throw IllegalStateException("轉檔完成後未找到輸出檔案")
        }

        // 確認檔案實際有內容，若轉檔中途失敗會產生 0 byte 檔案
        if (outputFile.length() <= 0) {
            outputFile.delete()
            throw IllegalStateException("輸出檔案大小為 0，判定轉檔失敗")
        }

        // 透過後續解析再次驗證容器結構，確保回傳路徑能被 ExoPlayer 正確載入
        val (outWidth, outHeight) = resolveVideoSize(outputPath)
        if (outWidth <= 0 || outHeight <= 0) {
            outputFile.delete()
            throw IllegalStateException("輸出影片格式異常，播放器無法識別")
        }

        return outputPath
    }

    private fun resolveVideoSize(path: String): Pair<Int, Int> {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(path)
            val width = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
                ?.toIntOrNull() ?: 0
            val height = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
                ?.toIntOrNull() ?: 0
            width to height
        } finally {
            retriever.release()
        }
    }

    private fun createCircularAvatar(path: String, targetSize: Int): Bitmap? {
        val original = BitmapFactory.decodeFile(path) ?: return null
        val size = min(original.width, original.height)
        val offsetX = (original.width - size) / 2
        val offsetY = (original.height - size) / 2
        val square = Bitmap.createBitmap(original, offsetX, offsetY, size, size)
        if (square !== original) {
            original.recycle()
        }
        val scaled = Bitmap.createScaledBitmap(square, targetSize, targetSize, true)
        if (scaled !== square) {
            square.recycle()
        }

        val output = Bitmap.createBitmap(targetSize, targetSize, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(output)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        val rect = Rect(0, 0, targetSize, targetSize)
        canvas.drawARGB(0, 0, 0, 0)
        canvas.drawCircle(targetSize / 2f, targetSize / 2f, targetSize / 2f, paint)
        paint.xfermode = PorterDuffXfermode(PorterDuff.Mode.SRC_IN)
        canvas.drawBitmap(scaled, rect, rect, paint)
        scaled.recycle()

        // 加上白色外框讓頭像在深色背景上仍然清楚
        val borderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            color = Color.WHITE
            strokeWidth = targetSize * 0.04f
        }
        canvas.drawCircle(
            targetSize / 2f,
            targetSize / 2f,
            targetSize / 2f - borderPaint.strokeWidth / 2f,
            borderPaint
        )
        return output
    }

    private fun createCaptionBitmap(text: String, videoWidth: Int): Bitmap? {
        val density = context.resources.displayMetrics.density
        val textPaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            textSize = 18f * density
            typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.NORMAL)
        }

        val maxWidth = (videoWidth * 0.8f).toInt().coerceAtLeast((videoWidth * 0.5f).toInt())
        val staticLayout = buildStaticLayout(text, textPaint, maxWidth)
        val horizontalPadding = (16 * density).toInt()
        val verticalPadding = (12 * density).toInt()
        val bitmapWidth = staticLayout.width + horizontalPadding * 2
        val bitmapHeight = staticLayout.height + verticalPadding * 2

        val bitmap = Bitmap.createBitmap(bitmapWidth, bitmapHeight, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val backgroundPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.parseColor("#B3000000")
        }
        val cornerRadius = 16f * density
        canvas.drawRoundRect(
            RectF(0f, 0f, bitmapWidth.toFloat(), bitmapHeight.toFloat()),
            cornerRadius,
            cornerRadius,
            backgroundPaint
        )
        canvas.translate(horizontalPadding.toFloat(), verticalPadding.toFloat())
        staticLayout.draw(canvas)
        return bitmap
    }

    private fun buildStaticLayout(text: String, paint: TextPaint, width: Int): StaticLayout {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            StaticLayout.Builder.obtain(text, 0, text.length, paint, width)
                .setAlignment(Layout.Alignment.ALIGN_CENTER)
                .setIncludePad(true)
                .build()
        } else {
            @Suppress("DEPRECATION")
            StaticLayout(
                text,
                paint,
                width,
                Layout.Alignment.ALIGN_CENTER,
                1f,
                0f,
                true
            )
        }
    }
}
