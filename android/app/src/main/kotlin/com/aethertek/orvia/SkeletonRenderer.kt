package com.aethertek.orvia

import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint

/**
 * 在 Android Canvas 上繪製 MediaPipe 33 個骨骼點。
 *
 * 座標：landmarks 為 MediaPipe 歸一化座標（0-1），
 * [imgW]/[imgH] 為目前 Canvas 的像素尺寸。
 *
 * 從 MediaPipe 的 PoseLandmarker.POSE_LANDMARKS 直接取骨骼連線定義。
 */
object SkeletonRenderer {

    // 與 PoseLandmarker.POSE_LANDMARKS 一致的骨骼連線對（start, end）
    private val EDGES = arrayOf(
        intArrayOf(0, 1),   intArrayOf(1, 2),   intArrayOf(2, 3),   intArrayOf(3, 7),
        intArrayOf(0, 4),   intArrayOf(4, 5),   intArrayOf(5, 6),   intArrayOf(6, 8),
        intArrayOf(9, 10),
        intArrayOf(11, 12), intArrayOf(11, 13), intArrayOf(13, 15),
        intArrayOf(12, 14), intArrayOf(14, 16),
        intArrayOf(11, 23), intArrayOf(12, 24), intArrayOf(23, 24),
        intArrayOf(23, 25), intArrayOf(25, 27), intArrayOf(27, 29), intArrayOf(29, 31), intArrayOf(27, 31),
        intArrayOf(24, 26), intArrayOf(26, 28), intArrayOf(28, 30), intArrayOf(30, 32), intArrayOf(28, 32),
        intArrayOf(15, 17), intArrayOf(15, 19), intArrayOf(15, 21), intArrayOf(17, 19),
        intArrayOf(16, 18), intArrayOf(16, 20), intArrayOf(16, 22), intArrayOf(18, 20),
    )

    private val bonePaint = Paint().apply {
        color = Color.CYAN
        strokeWidth = 6f
        style = Paint.Style.STROKE
        isAntiAlias = true
    }
    private val jointPaint = Paint().apply {
        color = Color.GREEN
        style = Paint.Style.FILL
        isAntiAlias = true
    }
    private val wristPaint = Paint().apply {
        color = Color.RED
        style = Paint.Style.FILL
        isAntiAlias = true
    }

    private const val MIN_VIS = 0.3f

    /**
     * [landmarks] 33 個地標，每個為 Map("x", "y", "z", "vis")，歸一化 0-1。
     * 座標已由 MediaPipe 旋轉補正，直接對應螢幕顯示空間。
     */
    fun draw(
        canvas: Canvas,
        landmarks: List<Map<String, Any>>,
        imgW: Int,
        imgH: Int,
        mirrorX: Boolean = false,
    ) {
        if (landmarks.size < 17) return

        fun nx(raw: Float) = if (mirrorX) (1f - raw) * imgW else raw * imgW

        // 骨骼連線
        for (edge in EDGES) {
            val a = edge[0]; val b = edge[1]
            if (a >= landmarks.size || b >= landmarks.size) continue
            val lmA = landmarks[a]; val lmB = landmarks[b]
            val visA = (lmA["vis"] as? Double)?.toFloat() ?: 0f
            val visB = (lmB["vis"] as? Double)?.toFloat() ?: 0f
            if (visA < MIN_VIS || visB < MIN_VIS) continue
            val ax = nx((lmA["x"] as? Double)?.toFloat() ?: 0f)
            val ay = ((lmA["y"] as? Double)?.toFloat() ?: 0f) * imgH
            val bx = nx((lmB["x"] as? Double)?.toFloat() ?: 0f)
            val by = ((lmB["y"] as? Double)?.toFloat() ?: 0f) * imgH
            canvas.drawLine(ax, ay, bx, by, bonePaint)
        }

        // 關節點
        for (i in landmarks.indices) {
            val lm  = landmarks[i]
            val vis = (lm["vis"] as? Double)?.toFloat() ?: 0f
            if (vis < MIN_VIS) continue
            val cx = nx((lm["x"] as? Double)?.toFloat() ?: 0f)
            val cy = ((lm["y"] as? Double)?.toFloat() ?: 0f) * imgH
            val radius = if (i == 16) 18f else 10f   // 右手腕加大
            canvas.drawCircle(cx, cy, radius, if (i == 16) wristPaint else jointPaint)
        }
    }
}
