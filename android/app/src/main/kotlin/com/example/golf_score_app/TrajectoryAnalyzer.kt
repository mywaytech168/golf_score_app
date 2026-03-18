package com.example.golf_score_app

/**
 * Placeholder implementation to unblock compilation on devices without OpenCV.
 * Replace with real OpenCV-based analyzer when OpenCV is added to the project.
 */
class TrajectoryAnalyzer {
    data class Result(
        val hitFrame: Int,
        val initBall: Map<String, Any>,
        val polyfit: Map<String, Double>,
        val points: List<Map<String, Any>>
    )

    fun analyze(videoPath: String): Result {
        // TODO: integrate OpenCV. For now return dummy points so Flutter can render overlay.
        val dummyPoints = (0..15).map { i ->
            mapOf("frame" to i, "x" to 80 + i * 10, "y" to 600 - i * 18, "isInlier" to 1)
        }
        return Result(
            hitFrame = 5,
            initBall = mapOf("x" to 80, "y" to 600, "r" to 10),
            polyfit = mapOf("a" to -0.0005, "b" to -0.2, "c" to 600.0),
            points = dummyPoints
        )
    }
}
