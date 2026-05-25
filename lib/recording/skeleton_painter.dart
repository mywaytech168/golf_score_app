import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

// 18 條骨骼連線（對應 Python SKELETON_EDGES）
const _edges = [
  (PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder),
  (PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow),
  (PoseLandmarkType.leftElbow, PoseLandmarkType.leftWrist),
  (PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow),
  (PoseLandmarkType.rightElbow, PoseLandmarkType.rightWrist),
  (PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip),
  (PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip),
  (PoseLandmarkType.leftHip, PoseLandmarkType.rightHip),
  (PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee),
  (PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle),
  (PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee),
  (PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle),
  (PoseLandmarkType.leftAnkle, PoseLandmarkType.leftHeel),
  (PoseLandmarkType.leftHeel, PoseLandmarkType.leftFootIndex),
  (PoseLandmarkType.leftAnkle, PoseLandmarkType.leftFootIndex),
  (PoseLandmarkType.rightAnkle, PoseLandmarkType.rightHeel),
  (PoseLandmarkType.rightHeel, PoseLandmarkType.rightFootIndex),
  (PoseLandmarkType.rightAnkle, PoseLandmarkType.rightFootIndex),
];

class SkeletonPainter extends CustomPainter {
  final List<Pose> poses;
  final Size imageSize;
  final bool isFrontCamera;
  static const double minVisibility = 0.2;

  SkeletonPainter({
    required this.poses,
    required this.imageSize,
    this.isFrontCamera = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bonePaint = Paint()
      ..color = const Color(0xFF00FFFF)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    final jointPaint = Paint()
      ..color = const Color(0xFF00FF00)
      ..style = PaintingStyle.fill;
    final wristPaint = Paint()
      ..color = const Color(0xFFFF0000) // lm16 右手腕標紅
      ..style = PaintingStyle.fill;

    for (final pose in poses) {
      for (final (a, b) in _edges) {
        final lmA = pose.landmarks[a];
        final lmB = pose.landmarks[b];
        if (lmA == null || lmB == null) continue;
        if (lmA.likelihood < minVisibility || lmB.likelihood < minVisibility) continue;
        canvas.drawLine(_scale(lmA, size), _scale(lmB, size), bonePaint);
      }
      for (final entry in pose.landmarks.entries) {
        final lm = entry.value;
        if (lm.likelihood < minVisibility) continue;
        final isRightWrist = entry.key == PoseLandmarkType.rightWrist;
        canvas.drawCircle(
          _scale(lm, size),
          isRightWrist ? 7 : 4,
          isRightWrist ? wristPaint : jointPaint,
        );
      }
    }
  }

  // 前置鏡頭預覽水平鏡像，landmark X 也需對應鏡像才能對齊人體
  Offset _scale(PoseLandmark lm, Size canvas) {
    final xRatio = lm.x / imageSize.width;
    final scaledX = isFrontCamera
        ? (1.0 - xRatio) * canvas.width
        : xRatio * canvas.width;
    return Offset(scaledX, lm.y / imageSize.height * canvas.height);
  }

  @override
  bool shouldRepaint(SkeletonPainter old) => old.poses != poses;
}
