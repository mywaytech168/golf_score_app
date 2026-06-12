import 'package:flutter/material.dart';

/// 即時擊球視覺回饋（RecordScreen / ShotRecordScreen 共用）。
///
/// 每當 [impactCount] 增加（偵測到新的一桿），於相機預覽上播放一次：
///   1. 中性色三層擴散光圈（復用影片查看頁 _SweetSpotRingPainter 的動畫節奏）
///   2. 中央「第 N 桿」彈出膠囊（scale + fade in/out）
///
/// 「擊到了」的即時操作回饋為中性色；甜蜜點品質（金/藍/灰）仍由 postImpact
/// 音訊評分後於回播 / SHOT 結果卡片顯示——即時當下拿不到音訊評分。
class ImpactGlowOverlay extends StatefulWidget {
  /// 累計擊球數；增加時觸發一次特效（與 LiveSwingDetector.onImpact 同步）。
  final int impactCount;

  /// 依當下擊球數產生彈出文字，例如 (n) => '第 $n 桿'。回傳 null 則不顯示文字。
  final String Function(int count)? labelBuilder;

  /// 光圈中心（相對預覽尺寸 0~1）。預設偏下方中央，貼近球/桿頭位置。
  final Alignment center;

  const ImpactGlowOverlay({
    super.key,
    required this.impactCount,
    this.labelBuilder,
    this.center = const Alignment(0.0, 0.35),
  });

  @override
  State<ImpactGlowOverlay> createState() => _ImpactGlowOverlayState();
}

class _ImpactGlowOverlayState extends State<ImpactGlowOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  String? _label; // 觸發當下捕捉，避免動畫進行中數字再變動

  @override
  void didUpdateWidget(ImpactGlowOverlay old) {
    super.didUpdateWidget(old);
    if (widget.impactCount > old.impactCount && widget.impactCount > 0) {
      _label = widget.labelBuilder?.call(widget.impactCount);
      _ctrl.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          final p = _ctrl.value;
          if (p <= 0.0 || p >= 1.0) return const SizedBox.expand();
          return Stack(fit: StackFit.expand, children: [
            CustomPaint(
              painter: _ImpactRingPainter(progress: p, center: widget.center),
            ),
            if (_label != null) _buildLabel(p, _label!),
          ]);
        },
      ),
    );
  }

  Widget _buildLabel(double p, String text) {
    // in: 0→0.18 淡入上滑；hold；out: 0.7→1 淡出
    final opacity = p < 0.18
        ? p / 0.18
        : p > 0.7
            ? ((1.0 - p) / 0.3).clamp(0.0, 1.0)
            : 1.0;
    final scale = 0.85 + 0.15 * (p / 0.18).clamp(0.0, 1.0);
    return Align(
      alignment: Alignment(widget.center.x, widget.center.y - 0.32),
      child: Opacity(
        opacity: opacity,
        child: Transform.scale(
          scale: scale,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white.withValues(alpha: 0.7)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.sports_golf_rounded,
                  color: Colors.white, size: 18),
              const SizedBox(width: 7),
              Text(text,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// 中性色三層擴散光圈，節奏對齊影片查看頁的甜蜜點光圈。
class _ImpactRingPainter extends CustomPainter {
  final double progress; // 0 → 1
  final Alignment center;

  // 中性亮白（即時「擊到了」回饋，不帶甜蜜點品質語意）
  static const Color _color = Color(0xFFF5F7FA);

  const _ImpactRingPainter({required this.progress, required this.center});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(
      size.width * (0.5 + center.x * 0.5),
      size.height * (0.5 + center.y * 0.5),
    );
    final maxR = size.shortestSide * 0.32;

    for (int i = 0; i < 3; i++) {
      final delay = i * 0.18;
      final t = ((progress - delay) / 0.65).clamp(0.0, 1.0);
      if (t <= 0) continue;

      final eased = Curves.easeOut.transform(t);
      final radius = maxR * 0.22 + eased * maxR;
      final opacity = (1.0 - eased).clamp(0.0, 1.0) * 0.85;

      canvas.drawCircle(
        c,
        radius,
        Paint()
          ..color = _color.withValues(alpha: opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.0 + (1.0 - eased) * 2.5,
      );
    }
  }

  @override
  bool shouldRepaint(_ImpactRingPainter old) =>
      old.progress != progress || old.center != center;
}
