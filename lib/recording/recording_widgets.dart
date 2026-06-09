import 'package:flutter/material.dart';

/// 錄製畫面共用子 widget（RecordScreen / ShotRecordScreen 共用）。

/// 半透明圓形按鈕容器（用於翻轉相機等）。
class CircleButton extends StatelessWidget {
  final Widget child;
  const CircleButton({super.key, required this.child});

  @override
  Widget build(BuildContext context) => Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Colors.black54,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white24),
        ),
        child: Center(child: child),
      );
}

/// 設定表中的選項 chip（畫質／幀率等）。
class SettingChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const SettingChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF1E8E5A) : const Color(0xFF2A2A2A),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: selected ? const Color(0xFF1E8E5A) : Colors.white12),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? Colors.white : Colors.white54,
              fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
              fontSize: 14,
            ),
          ),
        ),
      );
}

/// 錄製中的全螢幕脈動紅框 —— 戶外強光下最易辨識「正在錄影」的視覺訊號。
/// 不攔截觸控（IgnorePointer），覆蓋在預覽之上。
class RecordingBorderOverlay extends StatefulWidget {
  const RecordingBorderOverlay({super.key});

  @override
  State<RecordingBorderOverlay> createState() => _RecordingBorderOverlayState();
}

class _RecordingBorderOverlayState extends State<RecordingBorderOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, __) => Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: Color.lerp(
                    const Color(0xFFFF1744), const Color(0x66FF1744), _c.value)!,
                width: 5,
              ),
            ),
          ),
        ),
      );
}

/// 錄製中右上角的時間 + 幀數徽章。
class RecordingBadge extends StatelessWidget {
  final Duration elapsed;
  final int frameCount;
  const RecordingBadge({
    super.key,
    required this.elapsed,
    required this.frameCount,
  });

  String get _timeStr {
    final m = elapsed.inMinutes.toString().padLeft(2, '0');
    final s = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 8,
            height: 8,
            decoration:
                const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text('$_timeStr  $frameCount 幀',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ]),
      );
}

/// 左側垂直縮放滑桿（0.0 = 最廣）。
class ZoomSlider extends StatelessWidget {
  final double zoom;
  final ValueChanged<double> onChanged;
  const ZoomSlider({super.key, required this.zoom, required this.onChanged});

  String get _label => zoom == 0.0 ? '最廣' : '${(zoom * 100).round()}%';

  @override
  Widget build(BuildContext context) => Positioned(
        left: 8,
        top: 0,
        bottom: 110,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(_label,
              style: const TextStyle(color: Colors.white70, fontSize: 11)),
          const SizedBox(height: 4),
          Expanded(
              child: RotatedBox(
            quarterTurns: 3,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              ),
              child: Slider(
                value: zoom,
                min: 0.0,
                max: 1.0,
                onChanged: onChanged,
                activeColor: Colors.white,
                inactiveColor: Colors.white24,
              ),
            ),
          )),
          const Icon(Icons.zoom_in_rounded, color: Colors.white54, size: 18),
        ]),
      );
}
