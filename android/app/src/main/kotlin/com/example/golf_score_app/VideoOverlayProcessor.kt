package com.example.golf_score_app

import android.content.Context
import java.io.File

class VideoOverlayProcessor(private val context: Context) {
    /**
     * Stub overlay processor: simply copies input video to output.
     * Avoids Media3/ffmpeg complexity for now.
     */
    fun process(
        inputPath: String,
        outputPath: String,
        attachAvatar: Boolean = false,
        avatarPath: String? = null,
        attachCaption: Boolean = false,
        captionText: String = ""
    ): String {
        val inputFile = File(inputPath)
        require(inputFile.exists()) { "input video not found: $inputPath" }
        val outFile = File(outputPath)
        outFile.parentFile?.mkdirs()
        inputFile.copyTo(outFile, overwrite = true)
        return outFile.absolutePath
    }
}
