import 'package:flutter/foundation.dart';

import '../models/recording_history_entry.dart';
import '../models/statistics_response.dart';
import 'recording_history_storage.dart';

/// 從本地錄影歷史 JSON 計算統計數據，取代後端 API
///
/// 對應原 VideoServerClient.getStatistics() 的所有 period 語意：
///   'all'       → 全部紀錄
///   'today'     → 今天
///   'yesterday' → 昨天
///   'day'       → 指定日期（需傳 date: 'YYYY-MM-DD'）
class LocalStatisticsCalculator {
  LocalStatisticsCalculator._();

  static const _tag = '[LocalStats]';

  // ── 主入口 ──────────────────────────────────────────────────

  /// 計算指定期間的統計數據
  ///
  /// [period] - 'all' | 'today' | 'yesterday' | 'day'
  /// [date]   - 當 period == 'day' 時必填，格式 'YYYY-MM-DD'
  static Future<StatisticsResponse> compute({
    String period = 'all',
    String? date,
  }) async {
    final all = await RecordingHistoryStorage.instance.loadHistory();
    final filtered = all.where((e) => _inPeriod(e, period, date)).toList();

    debugPrint('$_tag period=$period date=$date → ${filtered.length}/${all.length} 筆');

    return _aggregate(filtered, period: period, date: date);
  }

  // ── 日期過濾 ─────────────────────────────────────────────────

  static bool _inPeriod(RecordingHistoryEntry e, String period, String? dateStr) {
    final t = e.recordedAt;
    final now = DateTime.now();

    switch (period) {
      case 'today':
        return _sameDay(t, now);
      case 'yesterday':
        return _sameDay(t, now.subtract(const Duration(days: 1)));
      case 'day':
        if (dateStr == null) return false;
        final parts = dateStr.split('-');
        if (parts.length != 3) return false;
        final y = int.tryParse(parts[0]);
        final m = int.tryParse(parts[1]);
        final d = int.tryParse(parts[2]);
        if (y == null || m == null || d == null) return false;
        return t.year == y && t.month == m && t.day == d;
      case 'all':
      default:
        return true;
    }
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  // ── 聚合計算 ─────────────────────────────────────────────────

  static StatisticsResponse _aggregate(
    List<RecordingHistoryEntry> entries, {
    required String period,
    String? date,
  }) {
    final totalCount = entries.length;

    // 已分析的條目（goodShot 不為 null）
    final analyzed = entries.where((e) => e.goodShot != null).toList();
    final goodCount = analyzed.where((e) => e.goodShot == true).length;
    final badCount  = analyzed.where((e) => e.goodShot == false).length;

    // 好球率（以已分析條目計算）
    final analyzedTotal = goodCount + badCount;
    final sweetSpot = analyzedTotal > 0
        ? (goodCount / analyzedTotal) * 100.0
        : 0.0;

    // 聲音清脆度（僅含有數值的條目）
    final crispValues = entries
        .map((e) => e.audioCrispness)
        .whereType<double>()
        .toList();

    final crispAvg = crispValues.isNotEmpty
        ? crispValues.reduce((a, b) => a + b) / crispValues.length
        : 0.0;
    final crispMin = crispValues.isNotEmpty
        ? crispValues.reduce((a, b) => a < b ? a : b)
        : 0.0;

    debugPrint(
      '$_tag → total=$totalCount good=$goodCount bad=$badCount '
      'sweet=${sweetSpot.toStringAsFixed(1)}% '
      'crispAvg=${crispAvg.toStringAsFixed(1)} crispMin=${crispMin.toStringAsFixed(1)}',
    );

    return StatisticsResponse(
      success: true,
      period: period,
      date: date,
      totalCount: totalCount,
      goodShot: goodCount,
      badShot: badCount,
      sweetSpotPercentage: sweetSpot,
      // 揮桿速度目前未存入本地，保留 0 待後續擴充
      peakValue: PeakValueStats(average: 0, maximum: 0),
      audioCrispness: AudioCrispnessStats(average: crispAvg, minimum: crispMin),
    );
  }
}
