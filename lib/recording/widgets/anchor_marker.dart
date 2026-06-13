import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// 擊球錨點標記：使用者點選預覽畫面設定的球位（準備點＝擊球點）。
/// 中央十字 + 外圈，醒目但不擋畫面。32×32，外部以中心對位。
class AnchorMarker extends StatelessWidget {
  const AnchorMarker({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        width: 32,
        height: 32,
        child: CustomPaint(painter: _AnchorPainter()),
      ),
    );
  }
}

class _AnchorPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = kOrviaMint;
    canvas.drawCircle(c, 13, ring..color = Colors.black54..strokeWidth = 3.5);
    canvas.drawCircle(c, 13, ring..color = kOrviaMint..strokeWidth = 2);
    // 十字
    final cross = Paint()..color = kOrviaMint..strokeWidth = 2;
    canvas.drawLine(Offset(c.dx - 8, c.dy), Offset(c.dx + 8, c.dy), cross);
    canvas.drawLine(Offset(c.dx, c.dy - 8), Offset(c.dx, c.dy + 8), cross);
    canvas.drawCircle(c, 2, Paint()..color = kOrviaMint);
  }

  @override
  bool shouldRepaint(_AnchorPainter old) => false;
}
