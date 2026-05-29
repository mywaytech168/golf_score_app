import 'package:flutter/material.dart';

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
    return Container(
      padding: const EdgeInsets.all(kSpaceMD),
      decoration: kCardDecoration(radius: kRadiusMD),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 標題 ──────────────────────────────────────────────
          Row(
            children: [
              const Icon(Icons.accessibility_new_rounded,
                  color: kPrimaryGreen, size: 18),
              const SizedBox(width: kSpaceSM),
              Expanded(
                child: Text(
                  title ?? '姿勢分析',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: kTextPrimary,
                  ),
                ),
              ),
              if (!_hasData)
                const Text(
                  '尚無 AI 分析資料',
                  style: TextStyle(fontSize: 11, color: kTextHint),
                ),
            ],
          ),
          const SizedBox(height: kSpaceMD),

          // ── 2×3 格子（無資料時全格顯示 0） ────────────────────
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: kSpaceSM,
            mainAxisSpacing: kSpaceSM,
            childAspectRatio: 1.2,
            children: SwingPosture.allLabels.map((label) {
              final count = breakdown[label] ?? 0;
              return _PostureTile(label: label, count: count);
            }).toList(),
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
    final color = count > 0 ? SwingPosture.color(label) : kTextHint;
    final bgColor = color.withAlpha(isPerfect ? 30 : 20);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
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
              color: count > 0 ? color : kTextHint,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            SwingPosture.zhName(label),
            style: const TextStyle(fontSize: 10, color: kTextSecondary),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
