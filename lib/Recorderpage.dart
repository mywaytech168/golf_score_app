import 'package:flutter/material.dart';
import 'dart:math';

class WaveformPainter extends CustomPainter {
  final List<double> waveform;

  WaveformPainter(this.waveform);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.green
      ..strokeWidth = 2.0;

    final midY = size.height / 2;
    final scaleX = size.width / waveform.length;
    final scaleY = size.height / 2 / 160; // 假設 -160 dB 到 0 dB 範圍

    for (int i = 0; i < waveform.length - 1; i++) {
      final x1 = i * scaleX;
      final y1 = midY - waveform[i] * scaleY;
      final x2 = (i + 1) * scaleX;
      final y2 = midY - waveform[i + 1] * scaleY;
      canvas.drawLine(Offset(x1, y1), Offset(x2, y2), paint);
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}
