import 'package:flutter/material.dart';

class StanceGuideOverlay extends StatelessWidget {
  final bool isVisible;
  final double stanceValue; // 保留介面（目前固定縮放用）
  final double swingDirection; // 保留介面（未使用）
  final String assetPath;

  const StanceGuideOverlay({
    super.key,
    this.isVisible = true,
    required this.stanceValue,
    required this.swingDirection,
    this.assetPath = 'assets/overlays/stance_overlay.png',
  });

  @override
  Widget build(BuildContext context) {
    if (!isVisible) return const SizedBox.shrink();

    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxW = constraints.maxWidth == double.infinity ? 300.0 : constraints.maxWidth;
          final width = maxW * (0.65 + 0.1 * stanceValue.clamp(0, 1));
          return Center(
            child: Image.asset(
              assetPath,
              width: width,
              fit: BoxFit.contain,
              opacity: const AlwaysStoppedAnimation(0.85),
            ),
          );
        },
      ),
    );
  }
}
