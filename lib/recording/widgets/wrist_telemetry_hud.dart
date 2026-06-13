import 'package:flutter/material.dart';
import '../live_swing_detector.dart';

/// 除錯 HUD：即時顯示左手/右手腕的垂直位置（Y）與速度（歸一化）。
/// 半透明深底、等寬數字，置於預覽角落不擋主要畫面。IgnorePointer 不攔觸控。
class WristTelemetryHud extends StatelessWidget {
  final LiveSwingDetector detector;
  const WristTelemetryHud({super.key, required this.detector});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ValueListenableBuilder<SwingTelemetry>(
        valueListenable: detector.telemetry,
        builder: (context, t, _) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _row('L', t.leftY, t.leftSpeed, const Color(0xFF4A7FFF)),
                const SizedBox(height: 2),
                _row('R', t.rightY, t.rightSpeed, const Color(0xFF00E5CC)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _row(String label, double? y, double speed, Color color) {
    final yStr = y == null ? '--' : y.toStringAsFixed(3);
    final sStr = speed.toStringAsFixed(3);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          alignment: Alignment.center,
          child: Text(label,
              style: TextStyle(
                  color: color, fontSize: 11, fontWeight: FontWeight.w900)),
        ),
        const SizedBox(width: 4),
        Text('Y $yStr  v $sStr',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontFamily: 'monospace',
                fontFeatures: [FontFeature.tabularFigures()])),
      ],
    );
  }
}
