import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// 以漸層填色的文字。預設使用品牌漸層 [kOrviaGradient]（Cyan → Blue → Purple）。
///
/// 用 [ShaderMask] + [BlendMode.srcIn] 將漸層裁切到文字字形上，
/// 因此底層 [Text] 的顏色必須為不透明（內部統一設為白色）。
class GradientText extends StatelessWidget {
  const GradientText(
    this.text, {
    super.key,
    this.style,
    this.gradient = kOrviaGradient,
    this.textAlign,
    this.maxLines,
    this.overflow,
  });

  final String text;
  final TextStyle? style;
  final Gradient gradient;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) =>
          gradient.createShader(Rect.fromLTWH(0, 0, bounds.width, bounds.height)),
      child: Text(
        text,
        textAlign: textAlign,
        maxLines: maxLines,
        overflow: overflow,
        style: (style ?? const TextStyle()).copyWith(color: Colors.white),
      ),
    );
  }
}
