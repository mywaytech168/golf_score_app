package com.example.golf_score_app

import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.util.Log

/**
 * Phase 1 Simple Frame Extractor using MediaMetadataRetriever
 * Purpose: Establish stable baseline for frame extraction + ML Kit pipeline
 * This is intentionally simple and slower, but more reliable for verification
 */
class VideoFrameExtractor {
    private val logTag = "⚙️ VideoFrameExtractor"

    /**
     * Extract RGB Bitmap from video at specified timestamp
     * Uses MediaMetadataRetriever (Phase 1 - stable, slower approach)
     *
     * @param videoPath Path to video file
     * @param timeMs Timestamp in milliseconds
     * @param maxWidth Output width (maintains aspect ratio)
     * @return RGB Bitmap, or null if extraction failed
     */
    fun extractFrameRgb(
        videoPath: String,
        timeMs: Long,
        maxWidth: Int = 720
    ): Bitmap? {
        return try {
            val retriever = MediaMetadataRetriever()
            retriever.setDataSource(videoPath)
            
            // Get frame at timestamp (convert ms to microseconds)
            val timeUs = timeMs * 1000L
            val bitmap: Bitmap? = retriever.getFrameAtTime(
                timeUs,
                MediaMetadataRetriever.OPTION_CLOSEST_SYNC
            )
            
            retriever.release()
            
            if (bitmap == null) {
                Log.w(logTag, "❌ [MMR] Failed to extract frame at ${timeMs}ms")
                return null
            }
            
            Log.d(logTag, "✅ [MMR] Extracted frame: ${bitmap.width}x${bitmap.height} at ${timeMs}ms")
            
            // Scale if necessary (maintain aspect ratio)
            if (bitmap.width != maxWidth) {
                val scaledHeight = (maxWidth.toDouble() / bitmap.width * bitmap.height).toInt()
                val scaledBitmap = Bitmap.createScaledBitmap(bitmap, maxWidth, scaledHeight, true)
                bitmap.recycle()
                Log.d(logTag, "✅ [MMR] Scaled to: ${scaledBitmap.width}x${scaledBitmap.height}")
                return scaledBitmap
            }
            
            bitmap
        } catch (e: Exception) {
            Log.e(logTag, "❌ [MMR] Frame extraction failed: ${e.message}", e)
            null
        }
    }

    /**
     * Get video dimensions (width, height)
     */
    fun getVideoDimensions(videoPath: String): Pair<Int, Int>? {
        return try {
            val retriever = MediaMetadataRetriever()
            retriever.setDataSource(videoPath)
            
            val width = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: 0
            val height = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: 0
            
            retriever.release()
            
            if (width > 0 && height > 0) {
                Pair(width, height)
            } else {
                null
            }
        } catch (e: Exception) {
            Log.e(logTag, "Failed to get video dimensions: ${e.message}", e)
            null
        }
    }

    /**
     * Get video duration in milliseconds
     */
    fun getVideoDuration(videoPath: String): Long {
        return try {
            val retriever = MediaMetadataRetriever()
            retriever.setDataSource(videoPath)
            
            val durationMs = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
            
            retriever.release()
            
            durationMs
        } catch (e: Exception) {
            Log.e(logTag, "Failed to get video duration: ${e.message}", e)
            0L
        }
    }
}
