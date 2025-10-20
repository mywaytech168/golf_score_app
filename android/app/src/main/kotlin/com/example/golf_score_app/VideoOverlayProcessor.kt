package com.example.golf_score_app

import android.content.Context
import android.graphics.*
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import android.util.Log
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
    companion object {
        private const val TAG = "VideoOverlayProcessor"
    }

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

        // ---------- 記錄輸入參數 ----------
        Log.i(
            TAG,
            "開始覆蓋影片，來源=${inputFile.absolutePath}，輸出=$outputPath，頭像=$attachAvatar，字幕=$attachCaption"
        )

        // 無需覆蓋時僅複製原檔，避免耗費額外時間與系統資源。
        if (!attachAvatar && (!attachCaption || captionText.isBlank())) {
            inputFile.copyTo(File(outputPath), overwrite = true)
            Log.d(TAG, "未勾選覆蓋選項，直接複製原始影片。")
            return outputPath
        }

        val (videoWidth, videoHeight) = resolveVideoSize(inputPath)
        if (videoWidth <= 0 || videoHeight <= 0) {
            throw IllegalStateException("無法判斷影片尺寸")
        }
        Log.d(TAG, "解析影片尺寸完成：${videoWidth}x$videoHeight。")

        val overlays = mutableListOf<TextureOverlay>()
        val retainedBitmaps = mutableListOf<Bitmap>() // 保留位圖引用，避免在轉檔期間被回收

        if (attachAvatar && !avatarPath.isNullOrEmpty()) {
            Log.d(TAG, "準備建立頭像覆蓋，來源=$avatarPath。")
            val targetSize = calculateAvatarSize(videoWidth, videoHeight)
            createCircularAvatar(avatarPath, targetSize)?.let { avatarBitmap ->
                val marginPx = calculateAvatarMargin(videoWidth, videoHeight)
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
                Log.d(TAG, "頭像覆蓋建立完成，實際尺寸=${avatarBitmap.width}x${avatarBitmap.height}。")
            }
        }

        if (attachCaption && captionText.isNotBlank()) {
            Log.d(TAG, "準備建立字幕覆蓋，內容長度=${captionText.length}。")
            createCaptionBitmap(captionText.trim(), videoWidth, videoHeight)?.let { captionBitmap ->
                val marginPx = calculateCaptionMargin(videoHeight)
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
                Log.d(TAG, "字幕覆蓋建立完成，實際尺寸=${captionBitmap.width}x${captionBitmap.height}。")
            }
        }

        if (overlays.isEmpty()) {
            inputFile.copyTo(File(outputPath), overwrite = true)
            Log.w(TAG, "未成功建立任何覆蓋，回退為原檔複製。")
            return outputPath
        }

        val outputFile = File(outputPath)
        outputFile.parentFile?.mkdirs()
        if (outputFile.exists()) {
            outputFile.delete()
        }
        Log.d(TAG, "輸出目錄確認完成，開始執行 Transformer。")

        val latch = CountDownLatch(1)
        var error: Exception? = null

        // 明確指定輸出影音編碼，避免裝置以預設格式產出播放器無法解析的檔案
        val transformationRequest = TransformationRequest.Builder()
            .setVideoMimeType(MimeTypes.VIDEO_H264)
            .setAudioMimeType(MimeTypes.AUDIO_AAC)
            .build()

        // ---------- 建立專用執行緒 ----------
        val transformerThread = HandlerThread("VideoOverlayTransformer").apply {
            // 以專用執行緒執行 Transformer，避免被主執行緒阻塞
            start()
        }
        val transformerHandler = Handler(transformerThread.looper)

        val transformer = Transformer.Builder(context)
            .setTransformationRequest(transformationRequest)
            .setVideoEffects(listOf(OverlayEffect(overlays)))
            .setLooper(transformerThread.looper)
            .addListener(object : Transformer.Listener {
                override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                    Log.i(TAG, "Transformer 完成匯出，耗時=${exportResult.durationMs}ms。")
                    latch.countDown()
                }

                override fun onError(
                    composition: Composition,
                    exportResult: ExportResult,
                    exportException: ExportException
                ) {
                    Log.e(TAG, "Transformer 匯出失敗：${exportException.message}", exportException)
                    error = exportException
                    latch.countDown()
                }
            })
            .build()
        // Transformer 建立在方法作用域內，轉檔完成後即失去引用，交由 GC 自行回收底層資源

        val startLatch = CountDownLatch(1)

        try {
            Log.d(TAG, "開始執行轉檔流程，指定執行緒=${transformerThread.name}。")
            transformerHandler.post {
                try {
                    Log.d(TAG, "已在執行緒 ${Thread.currentThread().name} 啟動 Transformer。")
                    transformer.startTransformation(
                        MediaItem.fromUri(Uri.fromFile(inputFile)),
                        outputPath
                    )
                } catch (startException: Exception) {
                    // 啟動流程若發生錯誤，直接記錄並結束等待
                    error = startException
                    Log.e(TAG, "轉檔流程啟動失敗：${startException.message}", startException)
                    latch.countDown()
                } finally {
                    startLatch.countDown()
                }
            }

            try {
                startLatch.await()
            } catch (interrupted: InterruptedException) {
                Thread.currentThread().interrupt()
                error = interrupted
                Log.e(TAG, "等待啟動結果時被中斷：${interrupted.message}", interrupted)
            }

            if (error == null) {
                try {
                    latch.await()
                } catch (interrupted: InterruptedException) {
                    // 若等待期間被中斷，保留例外並恢復執行緒中斷狀態
                    Thread.currentThread().interrupt()
                    error = interrupted
                    Log.e(TAG, "等待轉檔結果時被中斷：${interrupted.message}", interrupted)
                }
            }
        } finally {
            // ---------- 結束執行緒 ----------
            Log.d(TAG, "結束 Transformer 執行緒釋放資源。")
            transformerThread.quitSafely()
            try {
                transformerThread.join()
            } catch (joinError: InterruptedException) {
                // 若等待執行緒結束時被中斷，記錄後恢復中斷狀態
                Thread.currentThread().interrupt()
                Log.w(TAG, "等待 Transformer 執行緒結束被中斷：${joinError.message}")
            }
        }

        retainedBitmaps.forEach { it.recycle() }
        Log.d(TAG, "釋放覆蓋位圖資源完成。")

        error?.let {
            outputFile.delete()
            Log.e(TAG, "轉檔流程最終失敗，輸出檔案已清除。", it)
            throw it
        }

        if (!outputFile.exists()) {
            Log.e(TAG, "轉檔完成後找不到輸出檔案。")
            throw IllegalStateException("轉檔完成後未找到輸出檔案")
        }

        // 確認檔案實際有內容，若轉檔中途失敗會產生 0 byte 檔案
        if (outputFile.length() <= 0) {
            outputFile.delete()
            Log.e(TAG, "輸出檔案大小為 0，判定轉檔失敗。")
            throw IllegalStateException("輸出檔案大小為 0，判定轉檔失敗")
        }

        // 透過後續解析再次驗證容器結構，確保回傳路徑能被 ExoPlayer 正確載入
        val (outWidth, outHeight) = resolveVideoSize(outputPath)
        if (outWidth <= 0 || outHeight <= 0) {
            outputFile.delete()
            Log.e(TAG, "輸出影片格式異常，寬=$outWidth，高=$outHeight。")
            throw IllegalStateException("輸出影片格式異常，播放器無法識別")
        }

        Log.i(TAG, "覆蓋流程完成，輸出=${outputFile.absolutePath}，尺寸=${outWidth}x$outHeight。")

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
            Log.v(TAG, "解析影片尺寸：path=$path，width=$width，height=$height。")
            width to height
        } finally {
            retriever.release()
        }
    }

    private fun calculateAvatarSize(videoWidth: Int, videoHeight: Int): Int {
        // 以影片較短邊計算頭像尺寸，放大係數以提升可讀性，同時設定更高上下限維持彈性
        val base = min(videoWidth, videoHeight)
        return (base * 0.32f).toInt().coerceIn(320, 520)
    }

    private fun calculateAvatarMargin(videoWidth: Int, videoHeight: Int): Int {
        // 依畫面尺寸縮放邊距，確保放大頭像後仍與邊界保持距離
        val base = maxOf(videoWidth, videoHeight)
        return (base * 0.04f).toInt().coerceIn(36, 96)
    }

    private fun createCircularAvatar(path: String, targetSize: Int): Bitmap? {
        // 嘗試以取樣方式載入圖片，避免超高解析度頭像造成記憶體不足
        val original = try {
            decodeSampledBitmap(path, targetSize * 2)
        } catch (oom: OutOfMemoryError) {
            Log.e(TAG, "載入頭像發生 OOM：$path", oom)
            null
        } ?: return null
        Log.d(TAG, "頭像原始尺寸=${original.width}x${original.height}。")
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
        Log.d(TAG, "頭像圓形化完成，目標尺寸=$targetSize。")
        return output
    }

    private fun decodeSampledBitmap(path: String, targetSize: Int): Bitmap? {
        val boundOptions = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, boundOptions)

        val originalWidth = boundOptions.outWidth
        val originalHeight = boundOptions.outHeight
        if (originalWidth <= 0 || originalHeight <= 0) {
            Log.w(TAG, "頭像檔案無法解析尺寸：$path")
            return null
        }

        // 動態計算取樣倍數，確保讀入尺寸不會遠大於需求
        val minSide = min(originalWidth, originalHeight).coerceAtLeast(1)
        var sampleSize = 1
        while ((minSide / sampleSize) > targetSize.coerceAtLeast(1) * 2) {
            sampleSize *= 2
        }
        Log.d(
            TAG,
            "頭像解碼設定：原始=${originalWidth}x${originalHeight}，target=$targetSize，sampleSize=$sampleSize。"
        )

        val decodeOptions = BitmapFactory.Options().apply {
            inSampleSize = sampleSize
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }

        val bitmap = BitmapFactory.decodeFile(path, decodeOptions)
        if (bitmap == null) {
            Log.w(TAG, "頭像解碼結果為空：$path")
        }
        return bitmap
    }

    private fun calculateCaptionMargin(videoHeight: Int): Int {
        // 根據影片高度設定內縮距離，讓字幕留出足夠空間
        return (videoHeight * 0.06f).toInt().coerceIn(48, 120)
    }

    private fun createCaptionBitmap(text: String, videoWidth: Int, videoHeight: Int): Bitmap? {
        val density = context.resources.displayMetrics.density
        val dynamicTextSizePx = calculateCaptionTextSize(videoWidth, videoHeight)
        val textPaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            textSize = dynamicTextSizePx
            typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.NORMAL)
        }

        val maxWidth = (videoWidth * 0.85f).toInt().coerceAtLeast((videoWidth * 0.55f).toInt())
        val staticLayout = buildStaticLayout(text, textPaint, maxWidth)
        val horizontalPadding = (22 * density).toInt()
        val verticalPadding = (18 * density).toInt()
        val bitmapWidth = staticLayout.width + horizontalPadding * 2
        val bitmapHeight = staticLayout.height + verticalPadding * 2
        Log.d(TAG, "字幕位圖資訊：maxWidth=$maxWidth，實際尺寸=${bitmapWidth}x$bitmapHeight。")

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
        Log.d(TAG, "字幕位圖建立完成。")
        return bitmap
    }

    private fun calculateCaptionTextSize(videoWidth: Int, videoHeight: Int): Float {
        // 文字大小同樣取較短邊為基準，調高係數讓字幕在分享影片中更明顯
        val base = min(videoWidth, videoHeight)
        val sizePx = base * 0.065f
        return sizePx.coerceIn(64f, 108f)
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
