import 'package:flutter/material.dart';
import 'package:golf_score_app/l10n/app_localizations.dart';

import '../models/swing_posture.dart';
import '../theme/app_theme.dart';

/// 姿勢分析統計卡片
/// 顯示 1 種完美 + 5 種錯誤姿勢的次數分佈（無資料時顯示全 0，不隱藏）
/// [breakdown] key = SwingPosture label，value = 次數（來自 StatisticsResponse.postureBreakdown）
class PostureBreakdownCard extends StatelessWidget {
  final Map<String, int> breakdown;
  final String? title;

  const PostureBreakdownCard({
    super.key,
    required this.breakdown,
    this.title,
  });

  bool get _hasData => breakdown.values.any((v) => v > 0);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(kSpaceMD),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(kRadiusMD),
        boxShadow: context.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 標題 ──────────────────────────────────────────────
          Row(
            children: [
              const Icon(Icons.accessibility_new_rounded,
                  color: kBrandPrimary, size: 18),
              const SizedBox(width: kSpaceSM),
              Expanded(
                child: Text(
                  title ?? l10n.postureTitle,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: context.textPrimary,
                  ),
                ),
              ),
              if (!_hasData)
                Text(
                  l10n.postureNoData,
                  style: TextStyle(fontSize: 11, color: context.textHint),
                ),
            ],
          ),
          const SizedBox(height: kSpaceMD),

          // ── 2×3 格子（無資料時全格顯示 0） ────────────────────
          GridView.custom(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: kSpaceSM,
              mainAxisSpacing: kSpaceSM,
              mainAxisExtent: 90,
            ),
            childrenDelegate: SliverChildListDelegate(
              SwingPosture.allLabels.map((label) {
                final count = breakdown[label] ?? 0;
                return _PostureTile(label: label, count: count);
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _PostureTile extends StatelessWidget {
  final String label;
  final int count;

  const _PostureTile({required this.label, required this.count});

  @override
  Widget build(BuildContext context) {
    final isPerfect = SwingPosture.isPerfect(label);
    final color = count > 0 ? SwingPosture.color(label) : context.textHint;
    final bgColor = color.withAlpha(isPerfect ? 30 : 20);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(kRadiusSM),
        border: Border.all(
          color: count > 0 ? color.withAlpha(80) : Colors.transparent,
          width: 1,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(SwingPosture.icon(label), color: color, size: 18),
          const SizedBox(height: 4),
          Text(
            count.toString(),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: count > 0 ? color : context.textHint,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            SwingPosture.localizedName(AppLocalizations.of(context), label),
            style: TextStyle(fontSize: 10, color: context.textSecondary),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
