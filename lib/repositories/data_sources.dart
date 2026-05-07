import '../models/statistics_response.dart';
import 'result.dart';

/// 本地數據源接口
/// 
/// 定義所有本地存儲操作的契約
abstract class LocalDataSource {
  /// 認證相關
  Future<Result<String?>> getAccessToken();
  Future<Result<void>> saveAccessToken(String token);
  Future<Result<void>> clearAccessToken();

  /// 用戶信息
  Future<Result<Map<String, dynamic>>> getUserProfile();
  Future<Result<void>> saveUserProfile(Map<String, dynamic> profile);
  Future<Result<void>> clearUserProfile();

  /// 統計數據
  Future<Result<StatisticsResponse?>> getTodayStatistics();
  Future<Result<void>> saveTodayStatistics(StatisticsResponse stats);
  Future<Result<StatisticsResponse?>> getAllTimeStatistics();
  Future<Result<void>> saveAllTimeStatistics(StatisticsResponse stats);

  /// 錄制歷史
  Future<Result<List<Map<String, dynamic>>>> getRecordingHistory();
  Future<Result<void>> saveRecording(Map<String, dynamic> recording);
  Future<Result<void>> deleteRecording(String recordingId);

  /// 通用緩存操作
  Future<Result<T?>> getCached<T>(String key);
  Future<Result<void>> saveCached<T>(String key, T value);
  Future<Result<void>> removeCached(String key);
  Future<Result<void>> clearAll();
}

/// 遠程數據源接口
/// 
/// 定義所有遠程 API 操作的契約
abstract class RemoteDataSource {
  /// 認證相關
  Future<Result<Map<String, dynamic>>> signInWithGoogle(String googleToken);
  Future<Result<Map<String, dynamic>>> refreshToken(String refreshToken);
  Future<Result<void>> signOut(String userId);

  /// 用戶信息
  Future<Result<Map<String, dynamic>>> fetchUserProfile(String userId);
  Future<Result<Map<String, dynamic>>> updateUserProfile(
    String userId,
    Map<String, dynamic> profileData,
  );

  /// 統計數據
  Future<Result<StatisticsResponse>> fetchTodayStatistics(String userId);
  Future<Result<StatisticsResponse>> fetchAllTimeStatistics(String userId);
  Future<Result<List<Map<String, dynamic>>>> fetchStatisticsHistory(
    String userId, {
    int? limit,
    int? offset,
  });

  /// 錄制數據
  Future<Result<List<Map<String, dynamic>>>> fetchRecordingHistory(
    String userId, {
    int? limit,
    int? offset,
  });
  Future<Result<String>> uploadRecording(
    String userId,
    String filePath, {
    Map<String, String>? metadata,
    void Function(int, int)? onProgress,
  });
  Future<Result<void>> deleteRecording(String userId, String recordingId);

  /// 視頻上傳
  Future<Result<String>> uploadVideo(
    String filePath, {
    Map<String, String>? metadata,
    void Function(int, int)? onProgress,
  });

  /// 健康檢查
  Future<Result<Map<String, dynamic>>> healthCheck();
}
