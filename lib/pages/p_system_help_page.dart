import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/p_system_metrics.dart';
import '../services/p_system_analyzer.dart';
import '../theme/app_theme.dart';

/// P 動作分析說明頁：P1–P10 位置、評分算法、各動作指標說明。
/// 由 video_player_page 的 P-System 卡片「?」鈕進入。
class PSystemHelpPage extends StatelessWidget {
  const PSystemHelpPage({super.key});

  static const _reliable = {'p1', 'p4', 'p7', 'p10'};
  static const _goodColor = kGoodColor;
  static const _warnColor = Color(0xFFFFB74D);
  static const _badColor = Color(0xFFE0584F);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final descColor = Theme.of(context).hintColor;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.pSystemHelpTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Text(l10n.pSystemHelpIntro,
              style: const TextStyle(fontSize: 14, height: 1.5)),
          const SizedBox(height: 22),

          _header(l10n.pSystemHelpPositionsHeader),
          const SizedBox(height: 8),
          ...PSystemMetrics.order.map((k) => _positionRow(l10n, k, descColor)),
          const SizedBox(height: 22),

          _header(l10n.pSystemHelpScoringHeader),
          const SizedBox(height: 8),
          Text(l10n.pSystemHelpScoringBody,
              style: TextStyle(fontSize: 13, height: 1.6, color: descColor)),
          const SizedBox(height: 10),
          Row(children: [
            _gradeChip(l10n.gradeGood, '100', _goodColor),
            const SizedBox(width: 8),
            _gradeChip(l10n.gradeWarn, '60', _warnColor),
            const SizedBox(width: 8),
            _gradeChip(l10n.gradeBad, '20', _badColor),
          ]),
          const SizedBox(height: 22),

          _header(l10n.pSystemHelpMetricsHeader),
          const SizedBox(height: 8),
          _metric(l10n.metricSpineTilt, l10n.metricSpineTiltDesc, descColor),
          _metric(l10n.metricHeadMove, l10n.metricHeadMoveDesc, descColor),
          _metric(l10n.metricXFactor, l10n.metricXFactorDesc, descColor, beta: true),
          _metric(l10n.metricWeightShift, l10n.metricWeightShiftDesc, descColor),
          const SizedBox(height: 22),

          _note(l10n.pSystemHelpViewpoint),
          const SizedBox(height: 10),
          _note(l10n.pSystemHelpBeta),
        ],
      ),
    );
  }

  Widget _header(String text) => Text(text,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800));

  Widget _positionRow(AppLocalizations l10n, String key, Color descColor) {
    final reliable = _reliable.contains(key);
    final color = reliable ? _goodColor : _warnColor;
    // 該位置適用指標 + 良好門檻（與 PSystemAnalyzer 共用常數）
    final thr = PSystemAnalyzer.metricsForPosition(key)
        .map((m) => '${_metricName(l10n, m)} ${_thr(m)}')
        .join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 40,
                child: Text(key.toUpperCase(),
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: color)),
              ),
              Expanded(
                child: Text(_pName(l10n, key),
                    style: const TextStyle(fontSize: 14)),
              ),
              Icon(reliable ? Icons.star_rounded : Icons.adjust_rounded,
                  size: 14, color: color),
              const SizedBox(width: 4),
              Text(reliable ? l10n.pSystemHelpReliable : l10n.pSystemHelpProxy,
                  style: TextStyle(fontSize: 11, color: color)),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 40, top: 2),
            child: Text(thr,
                style: TextStyle(fontSize: 11, height: 1.4, color: descColor)),
          ),
        ],
      ),
    );
  }

  Widget _gradeChip(String label, String score, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.6)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: color)),
          const SizedBox(width: 6),
          Text(score,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w800, color: color)),
        ]),
      );

  Widget _metric(String name, String desc, Color descColor,
          {bool beta = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text(name,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700)),
              if (beta) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: _warnColor.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('beta',
                      style: TextStyle(fontSize: 9, color: _warnColor)),
                ),
              ],
            ]),
            const SizedBox(height: 3),
            Text(desc,
                style: TextStyle(fontSize: 12.5, height: 1.5, color: descColor)),
          ],
        ),
      );

  Widget _note(String text) => Text(text,
      style: const TextStyle(fontSize: 11.5, height: 1.5, color: Colors.grey));

  String _metricName(AppLocalizations l, String key) {
    switch (key) {
      case 'spine_tilt': return l.metricSpineTilt;
      case 'head_move': return l.metricHeadMove;
      case 'x_factor': return l.metricXFactor;
      case 'weight_shift': return l.metricWeightShift;
      default: return key;
    }
  }

  String _thr(String key) {
    switch (key) {
      case 'spine_tilt':
        return '±${PSystemAnalyzer.spineTiltGoodMargin.toStringAsFixed(0)}°';
      case 'head_move':
        return '<${PSystemAnalyzer.headMoveGoodMax}';
      case 'x_factor':
        return '${PSystemAnalyzer.xFactorGoodLow.toStringAsFixed(0)}–${PSystemAnalyzer.xFactorGoodHigh.toStringAsFixed(0)}°';
      case 'weight_shift':
        return '${PSystemAnalyzer.weightShiftGoodLow}–${PSystemAnalyzer.weightShiftGoodHigh}';
      default:
        return '';
    }
  }

  String _pName(AppLocalizations l, String key) {
    switch (key) {
      case 'p1': return l.pLabelP1;
      case 'p2': return l.pLabelP2;
      case 'p3': return l.pLabelP3;
      case 'p4': return l.pLabelP4;
      case 'p5': return l.pLabelP5;
      case 'p6': return l.pLabelP6;
      case 'p7': return l.pLabelP7;
      case 'p8': return l.pLabelP8;
      case 'p9': return l.pLabelP9;
      case 'p10': return l.pLabelP10;
      default: return key.toUpperCase();
    }
  }
}
