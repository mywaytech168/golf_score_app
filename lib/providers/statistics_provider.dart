import 'package:flutter/foundation.dart';
import '../models/statistics_response.dart';
import '../services/statistics_service.dart';

/// 統計數據提供者
/// 
/// 管理揮桿統計數據（今日、昨日、歷史數據）
class StatisticsProvider with ChangeNotifier {
  final StatisticsService _statisticsService = StatisticsService();

  // 狀態變數
  bool _isLoading = false;
  StatisticsResponse? _todayStatistics;
  StatisticsResponse? _allTimeStatistics;
  Map<String, int>? _dailyBreakdown; // 按日期分組的統計
  String? _errorMessage;
  DateTime? _lastRefreshTime;

  // 快取有效期（分鐘）
  static const int _cacheValidityMinutes = 5;

  // Getters
  bool get isLoading => _isLoading;
  StatisticsResponse? get todayStatistics => _todayStatistics;
  StatisticsResponse? get allTimeStatistics => _allTimeStatistics;
  Map<String, int>? get dailyBreakdown => _dailyBreakdown;
  String? get errorMessage => _errorMessage;
  bool get isCacheValid => _lastRefreshTime != null &&
      DateTime.now().difference(_lastRefreshTime!).inMinutes < _cacheValidityMinutes;

  /// 載入今日統計數據
  Future<void> loadTodayStatistics({bool forceRefresh = false}) async {
    // 如果快取有效且不強制刷新，直接返回
    if (!forceRefresh && isCacheValid && _todayStatistics != null) {
      return;
    }

    _isLoading = true;
    notifyListeners();

    try {
      // 從服務獲取數據（這裡簡化處理，實際應調用 API）
      _todayStatistics = _statisticsService.todayStatistics;
      _lastRefreshTime = DateTime.now();
      _errorMessage = null;
    } catch (e) {
      _errorMessage = '載入今日統計數據失敗: $e';
      debugPrint(_errorMessage);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 載入全部時間統計數據
  Future<void> loadAllTimeStatistics({bool forceRefresh = false}) async {
    if (!forceRefresh && isCacheValid && _allTimeStatistics != null) {
      return;
    }

    _isLoading = true;
    notifyListeners();

    try {
      _allTimeStatistics = _statisticsService.statistics;
      _lastRefreshTime = DateTime.now();
      _errorMessage = null;
    } catch (e) {
      _errorMessage = '載入全部時間統計數據失敗: $e';
      debugPrint(_errorMessage);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 刷新所有統計數據
  Future<void> refreshAll() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await loadTodayStatistics(forceRefresh: true);
      await loadAllTimeStatistics(forceRefresh: true);
      _lastRefreshTime = DateTime.now();
    } catch (e) {
      _errorMessage = '刷新統計數據失敗: $e';
      debugPrint(_errorMessage);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 計算今日的關鍵指標
  Map<String, dynamic> getTodayMetrics() {
    if (_todayStatistics == null) {
      return {
        'totalSwings': 0,
        'goodShots': 0,
        'badShots': 0,
        'accuracy': 0.0,
      };
    }

    final stats = _todayStatistics!;
    final total = stats.totalCount;
    final goodShots = stats.goodShot;
    final accuracy = total > 0 ? (goodShots / total * 100).toStringAsFixed(1) : '0.0';

    return {
      'totalSwings': total,
      'goodShots': goodShots,
      'badShots': stats.badShot,
      'accuracy': '$accuracy%',
      'averagePeak': stats.peakValue.average.toStringAsFixed(2),
    };
  }

  /// 獲取進度百分比（與個人紀錄對比）
  double getProgressPercentage() {
    if (_todayStatistics == null || _allTimeStatistics == null) {
      return 0.0;
    }

    final todayAccuracy = _todayStatistics!.totalCount > 0
        ? (_todayStatistics!.goodShot / _todayStatistics!.totalCount)
        : 0.0;

    final allTimeAccuracy = _allTimeStatistics!.totalCount > 0
        ? (_allTimeStatistics!.goodShot / _allTimeStatistics!.totalCount)
        : 0.0;

    if (allTimeAccuracy == 0) return 0.0;
    return (todayAccuracy / allTimeAccuracy).clamp(0.0, 2.0); // 最多顯示 200%
  }

  /// 清除快取
  void clearCache() {
    _todayStatistics = null;
    _allTimeStatistics = null;
    _lastRefreshTime = null;
    notifyListeners();
  }

  /// 清除錯誤訊息
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}
