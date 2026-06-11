import 'package:flutter/material.dart';

import 'pose_result.dart';

// 骨骼連線：對齊 Android 原生 SkeletonOverlayRenderer.CONNECTIONS（含臉部全 33 點拓樸）
const _edges = [
  // 臉部
  (0, 1), (1, 2), (2, 3), (3, 7),
  (0, 4), (4, 5), (5, 6), (6, 8),
  (9, 10),
  // 左臂
  (11, 13), (13, 15), (15, 17), (17, 19), (19, 15), (15, 21),
  // 右臂
  (12, 14), (14, 16), (16, 18), (18, 20), (20, 16), (16, 22),
  // 軀幹
  (11, 12), (12, 24), (24, 23), (23, 11),
  // 左腿
  (23, 25), (25, 27), (27, 29), (29, 31), (31, 27),
  // 右腿
  (24, 26), (26, 28), (28, 30), (30, 32), (32, 28),
];

// 與原生一致的左右側地標分組（用於配色）
const _leftLandmarks = {1, 2, 3, 7, 9, 11, 13, 15, 17, 19, 21, 23, 25, 27, 29, 31};
const _rightLandmarks = {4, 5, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30, 32};

// 配色（對齊原生）：右腕紅、左臂綠、右臂藍、軀幹腿黃
const _colRightWrist = Color(0xD2FF3232); // 紅
const _colLeftLine = Color(0xD200E65A); // 綠
const _colRightLine = Color(0xD24696F0); // 藍
const _colOther = Color(0xD2FFD700); // 黃
const _dotRightWrist = Color(0xE6FF1E1E);
const _dotLeft = Color(0xE600C846);
const _dotRight = Color(0xE64690DC);
const _dotOther = Color(0xE6FFC800);

class SkeletonPainter extends CustomPainter {
  final NativePoseResult pose;
  final bool isFrontCamera;

  // 對齊原生燒錄版：visibility 門檻 0.3
  static const double minVisibility = 0.3;

  const SkeletonPainter({
    required this.pose,
    this.isFrontCamera = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (pose.isEmpty) return;
    final lms = pose.landmarks;

    // 線寬 / 點半徑：以原生即時預覽為基準（SkeletonRenderer.kt 在 360px 短邊
    // 的 preview bitmap 上用線寬 6 / 節點 10 / 右腕 18）再縮細 75%，按短邊比例縮放
    final shortSide = size.shortestSide;
    final strokeWidth = shortSide * (4.5 / 360.0);
    final radius = shortSide * (7.5 / 360.0);
    final wristRadius = shortSide * (13.5 / 360.0);

    final linePaint = Paint()
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final dotPaint = Paint()..style = PaintingStyle.fill;

    for (final (a, b) in _edges) {
      if (a >= lms.length || b >= lms.length) continue;
      final lmA = lms[a];
      final lmB = lms[b];
      if (lmA.visibility < minVisibility || lmB.visibility < minVisibility) continue;
      linePaint.color = _lineColor(a, b);
      canvas.drawLine(_toOffset(lmA, size), _toOffset(lmB, size), linePaint);
    }

    for (var i = 0; i < lms.length; i++) {
      final lm = lms[i];
      if (lm.visibility < minVisibility) continue;
      dotPaint.color = _dotColor(i);
      canvas.drawCircle(_toOffset(lm, size), i == 16 ? wristRadius : radius, dotPaint);
    }
  }

  Color _lineColor(int a, int b) {
    if (a == 16 || b == 16) return _colRightWrist;
    if (_leftLandmarks.contains(a) && _leftLandmarks.contains(b)) return _colLeftLine;
    if (_rightLandmarks.contains(a) && _rightLandmarks.contains(b)) return _colRightLine;
    return _colOther;
  }

  Color _dotColor(int i) {
    if (i == 16) return _dotRightWrist;
    if (_leftLandmarks.contains(i)) return _dotLeft;
    if (_rightLandmarks.contains(i)) return _dotRight;
    return _dotOther;
  }

  // MediaPipe 回傳歸一化座標（已含 sensor rotation）
  Offset _toOffset(NativePoseLandmark lm, Size canvas) {
    final nx = isFrontCamera ? (1.0 - lm.x) : lm.x;
    return Offset(nx * canvas.width, lm.y * canvas.height);
  }

  @override
  bool shouldRepaint(SkeletonPainter old) =>
      old.pose != pose || old.isFrontCamera != isFrontCamera;
}
