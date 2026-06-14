import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/p_system_trend_service.dart';
import '../theme/app_theme.dart';

/// 修正追蹤卡：顯示各 P-System 指標（缺陷）隨時間是否改善。
///
/// 吃 [PSystemTrendService.computeTrends] 的結果；無可顯示趨勢時自行回 [SizedBox.shrink]。
class PSystemTrendCard extends StatelessWidget {
  final List<DefectTrend> trends;
  const PSystemTrendCard({super.key, required this.trends});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // 至少要有一個非「資料不足」的趨勢才顯示卡片（否則無資訊量）。
    final shown = trends.where((t) => t.series.isNotEmpty).toList();
    if (shown.every((t) => t.direction == TrendDirection.insufficient)) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.trendTitle,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          ...shown.map((t) => _row(context, l10n, t)),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, AppLocalizations l10n, DefectTrend t) {
    final (icon, color, label) = _dir(l10n, t.direction);
    final deltaStr = (t.delta != null && t.direction != TrendDirection.insufficient)
        ? (t.delta! >= 0 ? '+${t.delta!.round()}' : '${t.delta!.round()}')
        : '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(_metricName(l10n, t.metricKey),
                style: const TextStyle(fontSize: 13)),
          ),
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
          if (deltaStr.isNotEmpty) ...[
            const SizedBox(width: 6),
            Text(deltaStr,
                style: TextStyle(fontSize: 12, color: color.withValues(alpha: 0.8))),
          ],
        ],
      ),
    );
  }

  (IconData, Color, String) _dir(AppLocalizations l10n, TrendDirection d) {
    switch (d) {
      case TrendDirection.improving:
        return (Icons.trending_up, kGoodColor, l10n.trendImproving);
      case TrendDirection.declining:
        return (Icons.trending_down, const Color(0xFFE0584F), l10n.trendDeclining);
      case TrendDirection.stable:
        return (Icons.trending_flat, Colors.grey, l10n.trendStable);
      case TrendDirection.insufficient:
        return (Icons.remove, Colors.grey, l10n.trendInsufficient);
    }
  }

  String _metricName(AppLocalizations l10n, String key) {
    switch (key) {
      case 'overall':
        return l10n.metricOverall;
      case 'spine_tilt':
        return l10n.metricSpineTilt;
      case 'head_move':
        return l10n.metricHeadMove;
      case 'x_factor':
        return l10n.metricXFactor;
      case 'weight_shift':
        return l10n.metricWeightShift;
      default:
        return key;
    }
  }
}
