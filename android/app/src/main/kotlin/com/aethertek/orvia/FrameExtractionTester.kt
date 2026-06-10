package com.aethertek.orvia

import android.media.MediaMetadataRetriever
import android.graphics.Bitmap
import android.util.Log

object FrameExtractionTester {
    private const val TAG = "[MMR-TEST]"
    
    fun testExtractFrame(videoPath: String, timeMs: Int = 0) {
        Log.i(TAG, "Starting frame extraction test for: $videoPath at ${timeMs}ms")
        
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(videoPath)
            Log.i(TAG, "Data source set successfully")
            
            // Get video dimensions
            val width = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: 0
            val height = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: 0
            Log.i(TAG, "Video dimensions: ${width}x${height}")
            
            // Get frame count
            val duration = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0
            Log.i(TAG, "Video duration: ${duration}ms")
            
            // Extract frame
            val timeUs = timeMs * 1000L
            val bitmap = retriever.getFrameAtTime(timeUs, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
            
            if (bitmap != null) {
                Log.i(TAG, "✅ Frame extracted: ${bitmap.width}x${bitmap.height}, ${bitmap.byteCount} bytes")
                Log.i(TAG, "Bitmap config: ${bitmap.config}")
                bitmap.recycle()
            } else {
                Log.e(TAG, "❌ Frame extraction returned null")
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error: ${e.message}", e)
        } finally {
            try {
                retriever.release()
                Log.i(TAG, "Retriever released")
            } catch (e: Exception) {
                Log.e(TAG, "Error releasing retriever: ${e.message}")
            }
        }
    }
}
