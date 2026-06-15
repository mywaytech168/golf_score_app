import 'package:flutter/material.dart';
import 'package:golf_score_app/l10n/app_localizations.dart';
import '../services/audio_analysis_service.dart';
import '../theme/app_theme.dart';

class AudioFeaturePassRow extends StatelessWidget {
  final Map<String, double>? passRates;
  const AudioFeaturePassRow({super.key, required this.passRates});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final feats = AudioAnalysisService.featureLabels.entries.toList();
    final dimColor = context.textHint;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: kSpaceMD, vertical: kSpaceSM),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(kRadiusMD),
        boxShadow: context.cardShadow,
      ),
      child: Row(
        children: feats.asMap().entries.expand<Widget>((e) {
          final i = e.key;
          final feat = e.value;
          final hasData = passRates != null;
          final rate = passRates?[feat.key] ?? 0.0;
          final passed = hasData && rate >= 0.5;
          final color = !hasData
              ? dimColor
              : passed
                  ? kGoodColor
                  : const Color(0xFFE05252);
          return <Widget>[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: hasData ? (passed ? 0.85 : 0.55) : 0.40),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    AudioAnalysisService.localizedFeatureLabel(l10n, feat.key),
                    style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600),
                    textAlign: TextAlign.center,
                  ),
                  Text(
                    hasData ? '${(rate * 100).toStringAsFixed(0)}%' : '—',
                    style: TextStyle(fontSize: 10, color: color),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ];
        }).toList(),
      ),
    );
  }
}
