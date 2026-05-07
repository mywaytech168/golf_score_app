import '../models/statistics_response.dart';
import '../utils/exceptions.dart';
import '../utils/logger.dart';
import 'result.dart';
import 'data_sources.dart';

/// 統計數據 Repository
/// 
/// 管理揮桿統計數據的獲取和緩存
class StatisticsRepository {
  final LocalDataSource _localDataSource;
  final RemoteDataSource _remoteDataSource;

  // 快取有效期（分鐘）
  static const int cacheValidityMinutes = 5;
  DateTime? _lastFetchTime;

  StatisticsRepository({
    required LocalDataSource localDataSource,
    required RemoteDataSource remoteDataSource,
  })  : _localDataSource = localDataSource,
        _remoteDataSource = remoteDataSource;

  /// 清理资源
  void dispose() {
    Logger.debug('Statistics repository disposed', tag: 'StatisticsRepository');
    _lastFetchTime = null;
  }

  /// 獲取今日統計數據
  Future<Result<StatisticsResponse>> getTodayStatistics(
    String userId, {
    bool forceRefresh = false,
  }) async {
    try {
      Logger.info('獲取今日統計數據', tag: 'StatisticsRepository');

      // 檢查快取
      if (!forceRefresh && _isCacheValid()) {
        final cachedResult = await _localDataSource.getTodayStatistics();
        if (cachedResult.isSuccess) {
          final cached = cachedResult.getOrNull();
          if (cached != null) {
            Logger.info('使用緩存的今日統計數據', tag: 'StatisticsRepository');
            return Success(cached);
          }
        }
      }

      // 從遠程獲取
      final remoteResult = await _remoteDataSource.fetchTodayStatistics(userId);

      if (remoteResult.isSuccess) {
        final stats = remoteResult.getOrNull();
        if (stats != null) {
          // 保存到本地快取
          await _localDataSource.saveTodayStatistics(stats);
          _lastFetchTime = DateTime.now();
          Logger.info('今日統計數據已更新', tag: 'StatisticsRepository');
        }
      }

      return remoteResult;
    } catch (e, st) {
      Logger.error(
        '獲取今日統計數據失敗',
        tag: 'StatisticsRepository',
        error: e,
        stackTrace: st,
      );
      return Failure(
        DataException(
          message: '無法獲取統計數據: $e',
          originalException: e is Exception ? e : Exception(e),
        ),
        st,
      );
    }
  }

  /// 獲取全部時間統計數據
  Future<Result<StatisticsResponse>> getAllTimeStatistics(
    String userId, {
    bool forceRefresh = false,
  }) async {
    try {
      Logger.info('獲取全時間統計數據', tag: 'StatisticsRepository');

      // 檢查快取
      if (!forceRefresh && _isCacheValid()) {
        final cachedResult = await _localDataSource.getAllTimeStatistics();
        if (cachedResult.isSuccess) {
          final cached = cachedResult.getOrNull();
          if (cached != null) {
            Logger.info('使用緩存的全時間統計數據', tag: 'StatisticsRepository');
            return Success(cached);
          }
        }
      }

      // 從遠程獲取
      final remoteResult = await _remoteDataSource.fetchAllTimeStatistics(userId);

      if (remoteResult.isSuccess) {
        final stats = remoteResult.getOrNull();
        if (stats != null) {
          // 保存到本地快取
          await _localDataSource.saveAllTimeStatistics(stats);
          _lastFetchTime = DateTime.now();
          Logger.info('全時間統計數據已更新', tag: 'StatisticsRepository');
        }
      }

      return remoteResult;
    } catch (e, st) {
      Logger.error(
        '獲取全時間統計數據失敗',
        tag: 'StatisticsRepository',
        error: e,
        stackTrace: st,
      );
      return Failure(
        DataException(
          message: '無法獲取統計數據: $e',
          originalException: e is Exception ? e : Exception(e),
        ),
        st,
      );
    }
  }

  /// 獲取統計數據歷史
  Future<Result<List<Map<String, dynamic>>>> getStatisticsHistory(
    String userId, {
    int? limit,
    int? offset,
  }) async {
    try {
      Logger.info(
        '獲取統計數據歷史',
        tag: 'StatisticsRepository',
      );

      final result = await _remoteDataSource.fetchStatisticsHistory(
        userId,
        limit: limit,
        offset: offset,
      );

      return result;
    } catch (e, st) {
      Logger.error(
        '獲取統計數據歷史失敗',
        tag: 'StatisticsRepository',
        error: e,
        stackTrace: st,
      );
      return Failure(
        DataException(
          message: '無法獲取統計數據歷史: $e',
          originalException: e is Exception ? e : Exception(e),
        ),
        st,
      );
    }
  }

  /// 刷新所有統計數據
  Future<Result<Map<String, dynamic>>> refreshAll(String userId) async {
    try {
      Logger.info('刷新所有統計數據', tag: 'StatisticsRepository');

      final todayResult = await getTodayStatistics(userId, forceRefresh: true);
      final allTimeResult = await getAllTimeStatistics(userId, forceRefresh: true);

      if (todayResult.isSuccess && allTimeResult.isSuccess) {
        return Success({
          'today': todayResult.getOrNull(),
          'allTime': allTimeResult.getOrNull(),
          'timestamp': DateTime.now().toIso8601String(),
        });
      }

      final error = todayResult.getErrorOrNull() ?? allTimeResult.getErrorOrNull();
      return Failure(error ?? Exception('刷新失敗'));
    } catch (e, st) {
      Logger.error(
        '刷新統計數據失敗',
        tag: 'StatisticsRepository',
        error: e,
        stackTrace: st,
      );
      return Failure(
        DataException(
          message: '無法刷新統計數據: $e',
          originalException: e is Exception ? e : Exception(e),
        ),
        st,
      );
    }
  }

  /// 清除快取
  Future<Result<void>> clearCache() async {
    try {
      _lastFetchTime = null;
      Logger.info('統計數據快取已清除', tag: 'StatisticsRepository');
      return const Success(null);
    } catch (e, st) {
      return Failure(
        StorageException(
          message: '無法清除快取: $e',
          originalException: e is Exception ? e : Exception(e),
        ),
        st,
      );
    }
  }

  /// 檢查快取是否仍然有效
  bool _isCacheValid() {
    if (_lastFetchTime == null) return false;
    final now = DateTime.now();
    final difference = now.difference(_lastFetchTime!);
    return difference.inMinutes < cacheValidityMinutes;
  }

  void dispose() {
    Logger.debug('StatisticsRepository 已銷毀');
  }
}
