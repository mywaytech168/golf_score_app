import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/statistics_response.dart';
import 'local_statistics_calculator.dart';

/// 統計數據服務 - 統一管理 Data Metrics 和 Analytics 的數據來源
///
/// 數據層級：
/// 1. 本地 JSON 計算數據 (recording_history.json)
/// 2. 本地計算數據 (consistencyScore, comparisonSnapshots)
/// 3. 緩存層 (避免重複讀取)
class StatisticsService {
  static final StatisticsService _instance = StatisticsService._internal();

  factory StatisticsService() {
    return _instance;
  }

  StatisticsService._internal();

  // ============================================================
  // 後端 API 數據
  // ============================================================
  bool _isDisposed = false; // 追蹤是否已被 dispose
  StatisticsResponse? _cachedStatistics; // 緩存的後端統計數據（全部時間）
  StatisticsResponse? _todayStatistics; // 今天的統計數據
  StatisticsResponse? _yesterdayStatistics; // 昨天的統計數據
  bool _isLoadingStatistics = false;
  DateTime? _lastStatisticsLoadTime; // 記錄最後一次加載的時間，用於刷新控制
  final Duration _cacheExpiration = const Duration(minutes: 5); // 緩存有效期

  // ============================================================
  // 本地計算數據
  // ============================================================
  double? _consistencyScore; // 揮桿穩定度（0-1）
  double? _bestSpeedMph; // 歷史紀錄中的最佳揮桿速度
  double? _sweetSpotPercentage; // 甜蜜點命中率百分比
  double? _audioCrispness; // 聲音清脆度（0-100）
  ComparisonSnapshot? _comparisonBefore; // 比較區塊的上一筆紀錄
  ComparisonSnapshot? _comparisonAfter; // 比較區塊的最新紀錄
  bool _isLoadingLocalMetrics = false;

  // ============================================================
  // 流數據（用於訂閱）
  // ============================================================
  final _statisticsController = StreamController<StatisticsResponse?>.broadcast();
  final _localMetricsController = StreamController<LocalMetrics>.broadcast();
  final _loadingStateController = StreamController<LoadingState>.broadcast();

  // ============================================================
  // Public Getters
  // ============================================================

  /// 後端統計數據（全部時間）
  StatisticsResponse? get statistics => _cachedStatistics;

  /// 今天的統計數據
  StatisticsResponse? get todayStatistics => _todayStatistics;

  /// 昨天的統計數據
  StatisticsResponse? get yesterdayStatistics => _yesterdayStatistics;

  /// 本地指標數據
  LocalMetrics get localMetrics => LocalMetrics(
    consistencyScore: _consistencyScore,
    bestSpeedMph: _bestSpeedMph,
    sweetSpotPercentage: _sweetSpotPercentage,
    audioCrispness: _audioCrispness,
    comparisonBefore: _comparisonBefore,
    comparisonAfter: _comparisonAfter,
  );

  /// 合併後的統計數據（用於 Data Metrics 和 Analytics）
  MergedStatistics get mergedStatistics => MergedStatistics(
    // 後端提供的數據
    totalCount: _cachedStatistics?.totalCount ?? 0,
    goodShot: _cachedStatistics?.goodShot ?? 0,
    badShot: _cachedStatistics?.badShot ?? 0,
    sweetSpotPercentage: _cachedStatistics?.sweetSpotPercentage ?? 0,
    peakValueAverage: _cachedStatistics?.peakValue.average ?? 0,
    peakValueMaximum: _cachedStatistics?.peakValue.maximum ?? 0,
    audioCrispnessAverage: _cachedStatistics?.audioCrispness.average ?? 0,
    audioCrispnessMinimum: _cachedStatistics?.audioCrispness.minimum ?? 0,
    // 本地計算的數據
    consistencyScore: _consistencyScore,
    comparisonBefore: _comparisonBefore,
    comparisonAfter: _comparisonAfter,
  );

  /// 加載狀態
  LoadingState get loadingState => LoadingState(
    isLoadingStatistics: _isLoadingStatistics,
    isLoadingLocalMetrics: _isLoadingLocalMetrics,
  );

  // ============================================================
  // Public Methods
  // ============================================================

  /// 初始化服務，同時加載後端統計數據和本地指標
  /// 
  /// 可選的回調函數用於計算本地指標（如果無法注入計算方法）
  Future<void> initialize({
    Future<LocalMetrics> Function()? localMetricsLoader,
  }) async {
    await Future.wait([
      loadAllStatistics(), // 加載全部、今天、昨天的數據
      if (localMetricsLoader != null) _loadLocalMetrics(localMetricsLoader),
    ]);
  }

  /// 同時加載全部、今天、昨天的統計數據（從本地 JSON）
  Future<void> loadAllStatistics() async {
    _setLoadingState(isLoadingStatistics: true);

    try {
      // 並行計算三個時期的數據
      final results = await Future.wait([
        LocalStatisticsCalculator.compute(period: 'all'),
        LocalStatisticsCalculator.compute(period: 'today'),
        LocalStatisticsCalculator.compute(period: 'yesterday'),
      ]);

      _cachedStatistics    = results[0]; // 全部
      _todayStatistics     = results[1]; // 今天
      _yesterdayStatistics = results[2]; // 昨天
      _lastStatisticsLoadTime = DateTime.now();

      if (!_isDisposed && !_statisticsController.isClosed) {
        _statisticsController.add(_cachedStatistics);
      }
      debugPrint('✅ 統計數據已從本地 JSON 計算（全部、今天、昨天）');
    } catch (e) {
      debugPrint('❌ 加載統計數據失敗: $e');
    } finally {
      _setLoadingState(isLoadingStatistics: false);
    }
  }

  /// 從本地 JSON 計算統計數據（帶緩存機制）
  Future<StatisticsResponse?> loadStatisticsFromApi({
    String period = 'all',
    String? date,
    bool forceRefresh = false,
  }) async {
    // 'all' period 使用緩存
    if (!forceRefresh &&
        period == 'all' &&
        _cachedStatistics != null &&
        _lastStatisticsLoadTime != null) {
      if (DateTime.now().difference(_lastStatisticsLoadTime!) < _cacheExpiration) {
        debugPrint('📦 使用緩存的統計數據');
        return _cachedStatistics;
      }
    }

    _setLoadingState(isLoadingStatistics: true);

    try {
      final stats = await LocalStatisticsCalculator.compute(
        period: period,
        date: date,
      );

      if (period == 'all') {
        _cachedStatistics = stats;
        _lastStatisticsLoadTime = DateTime.now();
      } else if (period == 'today') {
        _todayStatistics = stats;
      } else if (period == 'yesterday') {
        _yesterdayStatistics = stats;
      }

      if (!_isDisposed && !_statisticsController.isClosed) {
        _statisticsController.add(stats);
      }
      debugPrint('✅ 統計數據已從本地 JSON 計算');

      return stats;
    } catch (e) {
      debugPrint('❌ 加載統計數據失敗: $e');
      return null;
    } finally {
      _setLoadingState(isLoadingStatistics: false);
    }
  }

  /// 更新本地計算的指標
  void setLocalMetrics({
    double? consistencyScore,
    double? bestSpeedMph,
    double? sweetSpotPercentage,
    double? audioCrispness,
    ComparisonSnapshot? comparisonBefore,
    ComparisonSnapshot? comparisonAfter,
  }) {
    if (_isDisposed) {
      debugPrint('⚠️ StatisticsService 已被 dispose，忽略 setLocalMetrics 調用');
      return;
    }

    _consistencyScore = consistencyScore;
    _bestSpeedMph = bestSpeedMph;
    _sweetSpotPercentage = sweetSpotPercentage;
    _audioCrispness = audioCrispness;
    _comparisonBefore = comparisonBefore;
    _comparisonAfter = comparisonAfter;

    // 檢查 controller 是否已關閉
    if (!_localMetricsController.isClosed) {
      _localMetricsController.add(localMetrics);
      debugPrint('✅ 本地指標已更新');
    }
  }

  /// 清除所有緩存和本地數據
  void clear() {
    _cachedStatistics = null;
    _todayStatistics = null;
    _yesterdayStatistics = null;
    _lastStatisticsLoadTime = null;
    _consistencyScore = null;
    _bestSpeedMph = null;
    _sweetSpotPercentage = null;
    _audioCrispness = null;
    _comparisonBefore = null;
    _comparisonAfter = null;
    
    // 檢查 controller 是否已關閉
    if (!_statisticsController.isClosed) {
      _statisticsController.add(null);
    }
    if (!_localMetricsController.isClosed) {
      _localMetricsController.add(localMetrics);
    }
  }

  /// 刷新所有數據
  Future<void> refresh({
    Future<LocalMetrics> Function()? localMetricsLoader,
  }) async {
    clear();
    await initialize(localMetricsLoader: localMetricsLoader);
  }

  // ============================================================
  // Streams (用於訂閱更新)
  // ============================================================

  /// 監聽後端統計數據的變化
  Stream<StatisticsResponse?> watchStatistics() => _statisticsController.stream;

  /// 監聽本地指標的變化
  Stream<LocalMetrics> watchLocalMetrics() => _localMetricsController.stream;

  /// 監聽加載狀態的變化
  Stream<LoadingState> watchLoadingState() => _loadingStateController.stream;

  // ============================================================
  // Private Methods
  // ============================================================

  Future<void> _loadLocalMetrics(Future<LocalMetrics> Function() loader) async {
    _setLoadingState(isLoadingLocalMetrics: true);
    try {
      final metrics = await loader();
      setLocalMetrics(
        consistencyScore: metrics.consistencyScore,
        bestSpeedMph: metrics.bestSpeedMph,
        sweetSpotPercentage: metrics.sweetSpotPercentage,
        audioCrispness: metrics.audioCrispness,
        comparisonBefore: metrics.comparisonBefore,
        comparisonAfter: metrics.comparisonAfter,
      );
    } catch (e) {
      debugPrint('❌ 加載本地指標失敗: $e');
    } finally {
      _setLoadingState(isLoadingLocalMetrics: false);
    }
  }

  void _setLoadingState({
    bool? isLoadingStatistics,
    bool? isLoadingLocalMetrics,
  }) {
    if (_isDisposed) {
      return;
    }
    if (isLoadingStatistics != null) {
      _isLoadingStatistics = isLoadingStatistics;
    }
    if (isLoadingLocalMetrics != null) {
      _isLoadingLocalMetrics = isLoadingLocalMetrics;
    }
    if (!_loadingStateController.isClosed) {
      _loadingStateController.add(loadingState);
    }
  }

  // ============================================================
  // Cleanup
  // ============================================================

  void dispose() {
    _isDisposed = true;
    _statisticsController.close();
    _localMetricsController.close();
    _loadingStateController.close();
  }
}

/// 本地計算的指標數據模型
class LocalMetrics {
  final double? consistencyScore; // 揮桿穩定度（0-1）
  final double? bestSpeedMph; // 歷史紀錄中的最佳揮桿速度
  final double? sweetSpotPercentage; // 甜蜜點命中率百分比
  final double? audioCrispness; // 聲音清脆度（0-100）
  final ComparisonSnapshot? comparisonBefore; // 比較區塊的上一筆紀錄
  final ComparisonSnapshot? comparisonAfter; // 比較區塊的最新紀錄

  LocalMetrics({
    this.consistencyScore,
    this.bestSpeedMph,
    this.sweetSpotPercentage,
    this.audioCrispness,
    this.comparisonBefore,
    this.comparisonAfter,
  });
}

/// 合併後的統計數據（後端 + 本地）
class MergedStatistics {
  // 後端提供的數據
  final int totalCount;
  final int goodShot;
  final int badShot;
  final double sweetSpotPercentage;
  final double peakValueAverage;
  final double peakValueMaximum;
  final double audioCrispnessAverage;
  final double audioCrispnessMinimum;
  // 本地計算的數據
  final double? consistencyScore;
  final ComparisonSnapshot? comparisonBefore;
  final ComparisonSnapshot? comparisonAfter;

  MergedStatistics({
    required this.totalCount,
    required this.goodShot,
    required this.badShot,
    required this.sweetSpotPercentage,
    required this.peakValueAverage,
    required this.peakValueMaximum,
    required this.audioCrispnessAverage,
    required this.audioCrispnessMinimum,
    this.consistencyScore,
    this.comparisonBefore,
    this.comparisonAfter,
  });
}

/// 加載狀態
class LoadingState {
  final bool isLoadingStatistics;
  final bool isLoadingLocalMetrics;

  bool get isLoading => isLoadingStatistics || isLoadingLocalMetrics;

  LoadingState({
    required this.isLoadingStatistics,
    required this.isLoadingLocalMetrics,
  });
}

/// 比較數據快照
class ComparisonSnapshot {
  final String entryId; // 錄影紀錄 ID
  final String recordedAtLabel; // 錄製時間標籤
  final double? speedMph; // 揮桿速度
  final double? impactClarity; // 擊球清脆度
  final double? audioCrispness; // 聲音清脆度

  ComparisonSnapshot({
    required this.entryId,
    required this.recordedAtLabel,
    this.speedMph,
    this.impactClarity,
    this.audioCrispness,
  });
}
