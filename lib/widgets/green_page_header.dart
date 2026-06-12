import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// 全寬綠色漸層頂部面板，統一各頁面標頭風格
///
/// 結構：
///   [leading?]  title / subtitle  [actions...]
///   [bottom?]                        ← 選填，例如篩選列、日期列
class GreenPageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;

  /// 左側元件（返回按鈕、頭像…）
  final Widget? leading;

  /// 右側元件列表
  final List<Widget> actions;

  /// 標題列下方的額外區域（篩選 Chip、日期列…）
  final Widget? bottom;

  /// 是否讓 SafeArea 吃掉頂部安全區（預設 true，直接在最頂層的頁面使用）
  final bool useSafeArea;

  const GreenPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.actions = const [],
    this.bottom,
    this.useSafeArea = true,
  });

  @override
  Widget build(BuildContext context) {
    Widget content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            leading != null ? 4 : kSpaceLG,
            kSpaceSM,
            kSpaceXS,
            bottom != null ? kSpaceXS : kSpaceMD,
          ),
          child: Row(
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 4)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: kOnGradient,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          color: kOnGradient.withValues(alpha: 0.72),
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              ...actions,
            ],
          ),
        ),
        if (bottom != null) bottom!,
      ],
    );

    if (useSafeArea) {
      content = SafeArea(bottom: false, child: content);
    }

    return Container(
      decoration: const BoxDecoration(gradient: kPrimaryGradient),
      child: content,
    );
  }
}
