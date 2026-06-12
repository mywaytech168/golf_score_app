import 'package:flutter/material.dart';

import 'package:golf_score_app/l10n/app_localizations.dart';

/// 錄影中指示器（RecordScreen / ShotRecordScreen 共用）：
/// 閃爍紅點 + REC + 已錄時間（mm:ss）+ 幀數，
/// 可選 [impactCount] 顯示「已偵測 N 桿」badge，每偵測到新的一桿短暫高亮。
/// 半透明黑底白字，錄影預覽上深淺主題皆清楚。
class RecordingIndicator extends StatefulWidget {
  final Duration elapsed;
  final int? frameCount;

  /// 即時擊球偵測桿數；null 表示此頁無即時偵測（不顯示 badge）。
  final int? impactCount;

  const RecordingIndicator({
    super.key,
    required this.elapsed,
    this.frameCount,
    this.impactCount,
  });

  @override
  State<RecordingIndicator> createState() => _RecordingIndicatorState();
}

class _RecordingIndicatorState extends State<RecordingIndicator>
    with TickerProviderStateMixin {
  // 紅點脈動（opacity 0.25 ↔ 1.0）
  late final AnimationController _blink = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..repeat(reverse: true);

  // 偵測到新的一桿時 badge 短暫高亮（1 → 0 淡出）
  late final AnimationController _flash = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didUpdateWidget(RecordingIndicator old) {
    super.didUpdateWidget(old);
    final oldCount = old.impactCount ?? 0;
    final newCount = widget.impactCount ?? 0;
    if (newCount > oldCount) {
      _flash.forward(from: 0.0); // 0→1，高亮強度 = 1 - value（亮起後淡出）
    }
  }

  @override
  void dispose() {
    _blink.dispose();
    _flash.dispose();
    super.dispose();
  }

  String get _timeStr {
    final m = widget.elapsed.inMinutes.toString().padLeft(2, '0');
    final s = (widget.elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final impacts = widget.impactCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        // REC 膠囊：紅點 + REC + mm:ss（+ 幀數）
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            FadeTransition(
              opacity: Tween(begin: 0.25, end: 1.0).animate(_blink),
              child: Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: Color(0xFFFF1744),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            const SizedBox(width: 6),
            const Text('REC',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2)),
            const SizedBox(width: 8),
            Text(_timeStr,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    fontFeatures: [FontFeature.tabularFigures()])),
            if (widget.frameCount != null) ...[
              const SizedBox(width: 8),
              Text(l10n.recFrameCount(widget.frameCount!),
                  style: const TextStyle(color: Colors.white70, fontSize: 11)),
            ],
          ]),
        ),
        // 已偵測 N 桿 badge（僅有即時偵測的頁面且偵測到至少一桿才顯示）
        if (impacts != null && impacts > 0) ...[
          const SizedBox(height: 6),
          AnimatedBuilder(
            animation: _flash,
            builder: (_, child) {
              // forward 0→1，高亮強度 = 1 - value（剛偵測到最亮，隨後淡出）
              final t = _flash.isAnimating || _flash.value > 0
                  ? 1.0 - _flash.value
                  : 0.0;
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Color.lerp(Colors.black.withValues(alpha: 0.6),
                      const Color(0xFF1AA87C), t),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: Color.lerp(
                          Colors.white24, Colors.greenAccent, t)!),
                ),
                child: child,
              );
            },
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.sports_golf_rounded,
                  color: Colors.greenAccent, size: 13),
              const SizedBox(width: 5),
              Text(l10n.recDetectedShots(impacts),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
            ]),
          ),
        ],
      ],
    );
  }
}
