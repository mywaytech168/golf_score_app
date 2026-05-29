import 'dart:math';
import 'package:flutter/material.dart';
import '../services/chart_data_service.dart';

/// 聲音波形橫條，顯示在影片播放器底部。
/// 高度約 68px，包含波形圖（CustomPaint）與下方指標列。
class AudioWaveformStrip extends StatelessWidget {
  const AudioWaveformStrip({
    super.key,
    required this.rmsPoints,
    required this.totalSeconds,
    this.hitSecond,
    this.currentSecond,
    this.spectralCentroid,
    this.peakDbfs,
    this.onSeek,
  });

  final List<ChartPoint> rmsPoints;
  final double totalSeconds;
  final double? hitSecond;
  final double? currentSecond;
  final double? spectralCentroid;
  final double? peakDbfs;
  final ValueChanged<double>? onSeek;

  // ── 指標計算 ──────────────────────────────────────────────────

  int get _crispScore {
    final c = spectralCentroid;
    if (c == null) return 0;
    // centroid ~4600 Hz → 約 92 分；5000+ → 100
    return (c / 50).clamp(0.0, 100.0).round();
  }

  String get _peakLabel {
    final p = peakDbfs;
    if (p == null) return '--';
    if (p > -8) return '高';
    if (p > -18) return '中';
    return '低';
  }

  Color get _peakColor {
    final p = peakDbfs;
    if (p == null) return Colors.white38;
    if (p > -8) return const Color(0xFF4CAF50);
    if (p > -18) return const Color(0xFFFFA726);
    return const Color(0xFFEF5350);
  }

  String get _freqChar {
    final c = spectralCentroid;
    if (c == null) return '--';
    if (c > 4000) return '偏清脆';
    if (c > 3000) return '中音';
    return '偏悶';
  }

  // ── Seek 手勢 ─────────────────────────────────────────────────

  void _seek(double dx, double width) {
    if (onSeek == null || totalSeconds <= 0) return;
    onSeek!((dx / width).clamp(0.0, 1.0) * totalSeconds);
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF080808),
      height: 68,
      child: Column(
        children: [
          // ── 指標列（18px）─────────────────────────────────────
          SizedBox(
            height: 18,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  const Text(
                    'AUDIO',
                    style: TextStyle(
                      color: Colors.white24,
                      fontSize: 8,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (spectralCentroid != null) ...[
                    _chip('清脆度 $_crispScore', const Color(0xFF1E8E5A)),
                    const SizedBox(width: 5),
                    _chip('峰值 $_peakLabel', _peakColor),
                    const SizedBox(width: 5),
                    _chip(_freqChar, Colors.white38),
                  ],
                ],
              ),
            ),
          ),
          // ── 波形（50px）───────────────────────────────────────
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth;
                return GestureDetector(
                  onTapDown: (d) => _seek(d.localPosition.dx, w),
                  onHorizontalDragUpdate: (d) => _seek(d.localPosition.dx, w),
                  child: CustomPaint(
                    painter: _WaveformPainter(
                      points: rmsPoints,
                      totalSeconds: totalSeconds,
                      hitSecond: hitSecond,
                      currentSecond: currentSecond,
                    ),
                    child: const SizedBox.expand(),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(3),
      border: Border.all(color: color.withValues(alpha: 0.38), width: 0.5),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: color,
        fontSize: 9,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

// ════════════════════════════════════════════════════════════════
// CustomPainter
// ════════════════════════════════════════════════════════════════

class _WaveformPainter extends CustomPainter {
  const _WaveformPainter({
    required this.points,
    required this.totalSeconds,
    this.hitSecond,
    this.currentSecond,
  });

  final List<ChartPoint> points;
  final double totalSeconds;
  final double? hitSecond;
  final double? currentSecond;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty || totalSeconds <= 0) return;

    const int numBars = 90;
    const double barGap = 1.5;
    final double barW = (size.width - (numBars - 1) * barGap) / numBars;

    // 每個 bar 取區段內最大振幅
    final buckets = List<double>.filled(numBars, 0.0);
    for (final pt in points) {
      final bi = ((pt.x / totalSeconds) * numBars).floor().clamp(0, numBars - 1);
      // rms_dbfs: -60 ~ 0 → normalize 0~1；-55 為底噪截止
      final h = ((pt.y + 60) / 55).clamp(0.0, 1.0);
      if (h > buckets[bi]) buckets[bi] = h;
    }

    final double cursorRatio =
        currentSecond != null ? (currentSecond! / totalSeconds).clamp(0.0, 1.0) : -1.0;

    final int hitBarIdx = hitSecond != null
        ? ((hitSecond! / totalSeconds) * numBars).floor().clamp(0, numBars - 1)
        : -1;

    final paintPlayed = Paint()..color = const Color(0xFF1E8E5A);
    final paintFuture = Paint()..color = Colors.white.withValues(alpha: 0.22);
    final paintHit    = Paint()..color = const Color(0xFFFF8F00);
    final paintGlow   = Paint()
      ..color = const Color(0xFFFF8F00).withValues(alpha: 0.30)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    for (int i = 0; i < numBars; i++) {
      final x = i * (barW + barGap);
      final normH = max(buckets[i], 0.06);
      final h = normH * (size.height - 8);
      final top = size.height - h;
      final rect = Rect.fromLTWH(x, top, barW, h);
      final rr = RRect.fromRectAndRadius(rect, const Radius.circular(1.5));

      final isHit = i == hitBarIdx;
      final isPlayed = cursorRatio >= 0 && (i + 0.5) / numBars <= cursorRatio;

      if (isHit) {
        // 擊球瞬間：暈光 + 實心橘色
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x - 2, 2, barW + 4, size.height - 4),
            const Radius.circular(2),
          ),
          paintGlow,
        );
        canvas.drawRRect(rr, paintHit);
      } else {
        canvas.drawRRect(rr, isPlayed ? paintPlayed : paintFuture);
      }
    }

    // 擊球時間小三角
    if (hitBarIdx >= 0) {
      final cx = hitBarIdx * (barW + barGap) + barW / 2;
      final path = Path()
        ..moveTo(cx - 4, 1)
        ..lineTo(cx + 4, 1)
        ..lineTo(cx, 7)
        ..close();
      canvas.drawPath(path, Paint()..color = const Color(0xFFFF8F00));
    }

    // 播放游標
    if (cursorRatio >= 0) {
      canvas.drawRect(
        Rect.fromLTWH(cursorRatio * size.width - 0.75, 0, 1.5, size.height),
        Paint()..color = Colors.white.withValues(alpha: 0.88),
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.currentSecond != currentSecond ||
      old.hitSecond != hitSecond ||
      old.totalSeconds != totalSeconds;
}
