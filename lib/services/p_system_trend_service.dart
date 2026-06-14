import 'package:path/path.dart' as p;

import '../models/p_system_metrics.dart';
import '../models/recording_history_entry.dart';
import 'biomechanics_service.dart';
import 'recording_history_storage.dart';

/// 修正追蹤趨勢方向。
enum TrendDirection {
  improving, // 後期明顯優於前期
  declining, // 後期明顯差於前期
  stable,    // 無顯著變化
  insufficient, // 樣本不足
}

/// 單一指標（缺陷）的隨時間趨勢：每桿一個 0-100「好度」（越高越好），
/// 以早/晚窗均值差判定是否改善。
class DefectTrend {
  /// 'overall' | 'spine_tilt' | 'head_move' | 'x_factor' | 'weight_shift'
  final String metricKey;

  /// 依時間排序的每桿好度（0-100，越高越好）。
  final List<({DateTime date, double goodness})> series;

  final TrendDirection direction;
  final double? earlyMean;
  final double? lateMean;

  const DefectTrend({
    required this.metricKey,
    required this.series,
    required this.direction,
    this.earlyMean,
    this.lateMean,
  });

  /// 改善幅度（晚 − 早）；不足時為 null。
  double? get delta =>
      (earlyMean == null || lateMean == null) ? null : lateMean! - earlyMean!;
}

/// 把每桿 P-System 角度/分數時間序列化，輸出各缺陷「是否隨時間改善」的趨勢。
///
/// 純裝置端：核心 [computeTrends] 為純函式（吃時間排序的 PSystemMetrics）；
/// [loadRecent] 從錄影歷史的 clip 讀各自 `angles.json`（[PSystemMetrics.load]）。
class PSystemTrendService {
  PSystemTrendService._();

  /// 追蹤的指標集（overall + 角度量化指標）。
  static const List<String> trackedKeys = [
    'overall', 'spine_tilt', 'head_move', 'x_factor', 'weight_shift'
  ];

  /// 判定改善/退步的好度差門檻（避免雜訊誤報）。
  static const double _deltaThreshold = 6.0;

  /// 最少樣本數，未達標為 insufficient。
  static const int _minShots = 4;

  static double _goodness(BiomechGrade g) {
    switch (g) {
      case BiomechGrade.good:
        return 100;
      case BiomechGrade.warn:
        return 60;
      case BiomechGrade.bad:
        return 20;
      case BiomechGrade.unknown:
        return double.nan; // 不計入
    }
  }

  /// 單桿某指標的好度（0-100）：跨所有 P 位置該指標 grade 的平均；
  /// 'overall' 直接用 overallScore。無資料回 null。
  static double? _shotGoodness(PSystemMetrics m, String key) {
    if (key == 'overall') return m.overallScore;
    final vals = <double>[];
    for (final metrics in m.perP.values) {
      for (final bm in metrics) {
        if (bm.key != key) continue;
        final g = _goodness(bm.grade);
        if (!g.isNaN) vals.add(g);
      }
    }
    if (vals.isEmpty) return null;
    return vals.reduce((a, b) => a + b) / vals.length;
  }

  /// 純函式核心：時間排序的每桿 metrics → 各指標趨勢。
  static List<DefectTrend> computeTrends(
      List<({DateTime date, PSystemMetrics metrics})> shots) {
    final sorted = [...shots]..sort((a, b) => a.date.compareTo(b.date));
    final out = <DefectTrend>[];

    for (final key in trackedKeys) {
      final series = <({DateTime date, double goodness})>[];
      for (final s in sorted) {
        final g = _shotGoodness(s.metrics, key);
        if (g != null) series.add((date: s.date, goodness: g));
      }
      if (series.isEmpty) continue; // 此指標完全無資料 → 不輸出

      if (series.length < _minShots) {
        out.add(DefectTrend(
          metricKey: key,
          series: series,
          direction: TrendDirection.insufficient,
        ));
        continue;
      }

      final half = series.length ~/ 2;
      final early = series.take(half).map((e) => e.goodness);
      final late = series.skip(series.length - half).map((e) => e.goodness);
      final earlyMean = early.reduce((a, b) => a + b) / half;
      final lateMean = late.reduce((a, b) => a + b) / half;
      final d = lateMean - earlyMean;
      final dir = d > _deltaThreshold
          ? TrendDirection.improving
          : d < -_deltaThreshold
              ? TrendDirection.declining
              : TrendDirection.stable;
      out.add(DefectTrend(
        metricKey: key,
        series: series,
        direction: dir,
        earlyMean: earlyMean,
        lateMean: lateMean,
      ));
    }
    return out;
  }

  /// 從錄影歷史讀近期 clip 的 angles.json，算趨勢。無資料回空清單。
  static Future<List<DefectTrend>> loadRecent({int maxClips = 40}) async {
    final history = await RecordingHistoryStorage.instance.loadHistory();
    final clips = history
        .where((e) => e.videoType == VideoType.localClip)
        .toList()
      ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt)); // 新→舊
    final shots = <({DateTime date, PSystemMetrics metrics})>[];
    for (final e in clips.take(maxClips)) {
      final m = await PSystemMetrics.load(p.dirname(e.filePath));
      if (m != null) shots.add((date: e.recordedAt, metrics: m));
    }
    return computeTrends(shots);
  }
}
