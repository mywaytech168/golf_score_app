import 'dart:ui';

import 'package:flutter/material.dart';
import '../services/pose_estimator_service.dart';

/// Draws keypoints and skeleton lines on top of a camera/video preview.
class PoseOverlayPainter extends CustomPainter {
  PoseOverlayPainter({
    required this.keypoints,
    required this.sourceSize,
    this.showScores = true,
  });

  final List<PoseKeypoint> keypoints;
  final Size sourceSize; // size of the frame used for inference
  final bool showScores;

  static const List<List<int>> _edges = [
    [0, 1],
    [0, 2],
    [1, 3],
    [2, 4],
    [5, 6],
    [5, 7],
    [7, 9],
    [6, 8],
    [8, 10],
    [5, 11],
    [6, 12],
    [11, 12],
    [11, 13],
    [13, 15],
    [12, 14],
    [14, 16],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (keypoints.isEmpty) return;

    final scaleX = size.width;
    final scaleY = size.height;

    final points = <Offset>[];
    for (final kp in keypoints) {
      points.add(Offset(kp.x * scaleX, kp.y * scaleY));
    }

    final linePaint = Paint()
      ..color = Colors.lightGreenAccent.withOpacity(0.9)
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final jointPaint = Paint()
      ..color = Colors.blueAccent.withOpacity(0.9)
      ..style = PaintingStyle.fill;

    // Draw limbs
    for (final edge in _edges) {
      final p1 = points[edge[0]];
      final p2 = points[edge[1]];
      canvas.drawLine(p1, p2, linePaint);
    }

    // Draw joints
    for (int i = 0; i < points.length; i++) {
      canvas.drawCircle(points[i], 4, jointPaint);
      if (showScores) {
        final score = keypoints[i].score;
        final text = score.toStringAsFixed(2);
        final tp = TextPainter(
          text: TextSpan(
            text: text,
            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, points[i] + const Offset(6, -6));
      }
    }
  }

  @override
  bool shouldRepaint(covariant PoseOverlayPainter oldDelegate) {
    return oldDelegate.keypoints != keypoints ||
        oldDelegate.sourceSize != sourceSize ||
        oldDelegate.showScores != showScores;
  }
}
