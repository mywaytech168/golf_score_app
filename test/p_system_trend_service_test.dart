// PSystemTrendService.computeTrends 純函式測試
//
// 執行: flutter test test/p_system_trend_service_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:golf_score_app/models/p_system_metrics.dart';
import 'package:golf_score_app/services/biomechanics_service.dart';
import 'package:golf_score_app/services/p_system_trend_service.dart';

PSystemMetrics shot(double overall, {BiomechGrade spine = BiomechGrade.good}) {
  return PSystemMetrics(
    pSec: {for (final k in PSystemMetrics.order) k: 0.0},
    perP: {
      'p4': [
        BiomechMetric(
          key: 'spine_tilt',
          value: 0,
          idealLow: 0,
          idealHigh: 1,
          grade: spine,
        ),
      ],
    },
    viewpoint: SwingViewpoint.faceOn,
    overallScore: overall,
  );
}

({DateTime date, PSystemMetrics metrics}) at(int day, PSystemMetrics m) =>
    (date: DateTime(2026, 6, day), metrics: m);

DefectTrend trendOf(List<DefectTrend> ts, String key) =>
    ts.firstWhere((t) => t.metricKey == key);

void main() {
  test('overall 分數上升 → improving', () {
    final ts = PSystemTrendService.computeTrends([
      at(1, shot(30)), at(2, shot(35)), at(3, shot(40)),
      at(4, shot(70)), at(5, shot(80)), at(6, shot(90)),
    ]);
    final o = trendOf(ts, 'overall');
    expect(o.direction, TrendDirection.improving);
    expect(o.delta!, greaterThan(0));
  });

  test('overall 分數下降 → declining', () {
    final ts = PSystemTrendService.computeTrends([
      at(1, shot(90)), at(2, shot(85)), at(3, shot(80)),
      at(4, shot(40)), at(5, shot(30)), at(6, shot(20)),
    ]);
    expect(trendOf(ts, 'overall').direction, TrendDirection.declining);
  });

  test('overall 持平 → stable', () {
    final ts = PSystemTrendService.computeTrends([
      at(1, shot(50)), at(2, shot(52)), at(3, shot(48)),
      at(4, shot(51)), at(5, shot(49)), at(6, shot(50)),
    ]);
    expect(trendOf(ts, 'overall').direction, TrendDirection.stable);
  });

  test('樣本不足（<4）→ insufficient', () {
    final ts = PSystemTrendService.computeTrends([
      at(1, shot(30)), at(2, shot(90)),
    ]);
    expect(trendOf(ts, 'overall').direction, TrendDirection.insufficient);
  });

  test('缺陷指標 spine_tilt 由 bad→good → improving', () {
    final ts = PSystemTrendService.computeTrends([
      at(1, shot(50, spine: BiomechGrade.bad)),
      at(2, shot(50, spine: BiomechGrade.bad)),
      at(3, shot(50, spine: BiomechGrade.good)),
      at(4, shot(50, spine: BiomechGrade.good)),
    ]);
    final s = trendOf(ts, 'spine_tilt');
    expect(s.direction, TrendDirection.improving);
    expect(s.earlyMean, closeTo(20, 1e-9)); // bad=20
    expect(s.lateMean, closeTo(100, 1e-9)); // good=100
  });

  test('亂序輸入仍依日期排序計算', () {
    final ts = PSystemTrendService.computeTrends([
      at(6, shot(90)), at(1, shot(30)), at(4, shot(70)),
      at(2, shot(35)), at(5, shot(80)), at(3, shot(40)),
    ]);
    final o = trendOf(ts, 'overall');
    expect(o.direction, TrendDirection.improving);
    expect(o.series.first.date, DateTime(2026, 6, 1));
    expect(o.series.last.date, DateTime(2026, 6, 6));
  });

  test('完全無此指標資料 → 不輸出該指標', () {
    final ts = PSystemTrendService.computeTrends([at(1, shot(50))]);
    // x_factor / weight_shift / head_move 從未出現 → 不在結果
    expect(ts.any((t) => t.metricKey == 'x_factor'), isFalse);
    expect(ts.any((t) => t.metricKey == 'overall'), isTrue);
  });
}
