import 'package:flutter/material.dart';
import 'dart:math' as math;

class StanceGuideOverlay extends StatelessWidget {
  final bool isVisible;
  final double stanceValue;
  final double swingDirection;

  const StanceGuideOverlay({
    super.key,
    this.isVisible = true, // Make it visible by default
    required this.stanceValue,
    required this.swingDirection,
  });

  @override
  Widget build(BuildContext context) {
    if (!isVisible) {
      return Container(); // Don't show anything if not visible
    }

    return CustomPaint(
      painter: _StancePainter(
        stanceValue: stanceValue,
        swingDirection: swingDirection,
      ),
      child: Container(),
    );
  }
}

class _StancePainter extends CustomPainter {
  final double stanceValue;
  final double swingDirection;

  _StancePainter({required this.stanceValue, required this.swingDirection});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    final centerX = size.width / 2;
    final centerY = size.height / 2;

    // Simple stick figure dimensions
    final headRadius = size.height * 0.05;
    final bodyLength = size.height * 0.2;
    final legLength = size.height * 0.25;
    final armLength = size.height * 0.18;

    // Stance width based on stanceValue
    final stanceWidth = size.width * 0.1 + (size.width * 0.15 * stanceValue);

    // Torso
    final topOfBody = Offset(centerX, centerY - bodyLength / 2);
    final bottomOfBody = Offset(centerX, centerY + bodyLength / 2);
    canvas.drawLine(topOfBody, bottomOfBody, paint);

    // Head
    final headCenter = Offset(centerX, topOfBody.dy - headRadius);
    canvas.drawCircle(headCenter, headRadius, paint);

    // Legs
    final leftFoot = Offset(centerX - stanceWidth / 2, bottomOfBody.dy + legLength);
    final rightFoot = Offset(centerX + stanceWidth / 2, bottomOfBody.dy + legLength);
    canvas.drawLine(bottomOfBody, leftFoot, paint);
    canvas.drawLine(bottomOfBody, rightFoot, paint);

    // Arms (simple representation)
    final shoulderPoint = Offset(centerX, topOfBody.dy + bodyLength * 0.1);
    final leftHand = Offset(shoulderPoint.dx - armLength * 0.8, shoulderPoint.dy + armLength * 0.6);
    final rightHand = Offset(shoulderPoint.dx + armLength * 0.8, shoulderPoint.dy + armLength * 0.6);
    canvas.drawLine(shoulderPoint, leftHand, paint);
    canvas.drawLine(shoulderPoint, rightHand, paint);

    // Swing direction line
    final swingPaint = Paint()
      ..color = Colors.yellowAccent.withOpacity(0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    final lineLength = size.height * 0.3;
    final angleRad = (swingDirection - 90) * (math.pi / 180); // Convert angle
    final startPoint = bottomOfBody;
    final endPoint = Offset(
      startPoint.dx + lineLength * math.cos(angleRad),
      startPoint.dy + lineLength * math.sin(angleRad),
    );

    canvas.drawLine(startPoint, endPoint, swingPaint);
  }

  @override
  bool shouldRepaint(covariant _StancePainter oldDelegate) {
    return oldDelegate.stanceValue != stanceValue || oldDelegate.swingDirection != swingDirection;
  }
}