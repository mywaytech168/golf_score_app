import '../utils/exceptions.dart';
import '../utils/logger.dart';
import 'result.dart';
import 'data_sources.dart';

/// 錄制 Repository
/// 
/// 管理錄制會話、上傳和歷史相關的操作
class RecordingRepository {
  final LocalDataSource _localDataSource;
  final RemoteDataSource _remoteDataSource;

  RecordingRepository({
    required LocalDataSource localDataSource,
    required RemoteDataSource remoteDataSource,
  })  : _localDataSource = localDataSource,
        _remoteDataSource = remoteDataSource;

  /// 清理资源
  void dispose() {
    Logger.debug('Recording repository disposed', tag: 'RecordingRepository');
  }

  /// 獲取本地錄制歷史
  Future<Result<List<Map<String, dynamic>>>> getLocalRecordingHistory() async {
    try {
      Logger.info('獲取本地錄制歷史', tag: 'RecordingRepository');
      return await _localDataSource.getRecordingHistory();
    } catch (e, st) {
      Logger.error(
        '獲取本地錄制歷史失敗',
        tag: 'RecordingRepository',
        error: e,
        stackTrace: st,
      );
      return Failure(
        StorageException(
          message: '無法獲取本地錄制歷史: $e',
          originalException: e is Exception ? e : Exception(e),
        ),
        st,
      );
    }
  }

  /// 獲取遠程錄制歷史
  Future<Result<List<Map<String, dynamic>>>> getRemoteRecordingHistory(
    String userId, {
    int? limit,
    int? offset,
  }) async {
    try {
      Logger.info(
        '獲取遠程錄制歷史',
        tag: 'RecordingRepository',
      );
      return await _remoteDataSource.fetchRecordingHistory(
        userId,
        limit: limit,
        offset: offset,
      );
    } catch (e, st) {
      Logger.error(
        '獲取遠程錄制歷史失敗',
        tag: 'RecordingRepository',
        error: e,
        stackTrace: st,
      );
      return Failure(
        DataException(
          message: '無法獲取遠程錄制歷史: $e',
          originalException: e is Exception ? e : Exception(e),
        ),
        st,
      );
    }
  }

  /// 保存本地錄制
  Future<Result<void>> saveLocalRecording(
    Map<String, dynamic> recordingData,
  ) async {
    try {
      Logger.info('保存本地錄制', tag: 'RecordingRepository');
      return await _localDataSource.saveRecording(recordingData);
    } catch (e, st) {
      Logger.error(
        '保存本地錄制失敗',
        tag: 'RecordingRepository',
        error: e,
        stackTrace: st,
      );
      return Failure(
        StorageException(
          message: '無法保存本地錄制: $e',
          originalException: e is Exception ? e : Exception(e),
        ),
        st,
      );
    }
  }

  /// 上傳錄制
  Future<Result<String>> uploadRecording(
    String userId,
    String filePath, {
    Map<String, String>? metadata,
    void Function(int, int)? onProgress,
  }) async {
    try {
      Logger.info(
        '開始上傳錄制',
        tag: 'RecordingRepository',
      );

      final result = await _remoteDataSource.uploadRecording(
        userId,
        filePath,
        metadata: metadata,
        onProgress: onProgress,
      );

      if (result.isSuccess) {
        final recordingId = result.getOrNull();
        if (recordingId != null) {
          Logger.info(
            '錄制上傳成功 (ID: $recordingId)',
            tag: 'RecordingRepository',
          );
        }
      }

      return result;
    } catch (e, st) {
      Logger.error(
        '上傳錄制失敗',
        tag: 'RecordingRepository',
        error: e,
        stackTrace: st,
      );
      return Failure(
        DataException(
          message: '無法上傳錄制: $e',
          originalException: e is Exception ? e : Exception(e),
        ),
        st,
      );
    }
  }

  /// 刪除本地錄制
  Future<Result<void>> deleteLocalRecording(String recordingId) async {
    try {
      Logger.info(
        '刪除本地錄制',
        tag: 'RecordingRepository',
      );
      return await _localDataSource.deleteRecording(recordingId);
    } catch (e, st) {
      Logger.error(
        '刪除本地錄制失敗',
        tag: 'RecordingRepository',
        error: e,
        stackTrace: st,
      );
      return Failure(
        StorageException(
          message: '無法刪除本地錄制: $e',
          originalException: e is Exception ? e : Exception(e),
        ),
        st,
      );
    }
  }

  /// 刪除遠程錄制
  Future<Result<void>> deleteRemoteRecording(
    String userId,
    String recordingId,
  ) async {
    try {
      Logger.info(
        '刪除遠程錄制',
        tag: 'RecordingRepository',
      );
      return await _remoteDataSource.deleteRecording(userId, recordingId);
    } catch (e, st) {
      Logger.error(
        '刪除遠程錄制失敗',
        tag: 'RecordingRepository',
        error: e,
        stackTrace: st,
      );
      return Failure(
        DataException(
          message: '無法刪除遠程錄制: $e',
          originalException: e is Exception ? e : Exception(e),
        ),
        st,
      );
    }
  }

  /// 上傳視頻
  Future<Result<String>> uploadVideo(
    String filePath, {
    Map<String, String>? metadata,
    void Function(int, int)? onProgress,
  }) async {
    try {
      Logger.info('開始上傳視頻', tag: 'RecordingRepository');

      final result = await _remoteDataSource.uploadVideo(
        filePath,
        metadata: metadata,
        onProgress: onProgress,
      );

      if (result.isSuccess) {
        Logger.info('視頻上傳成功', tag: 'RecordingRepository');
      }

      return result;
    } catch (e, st) {
      Logger.error(
        '上傳視頻失敗',
        tag: 'RecordingRepository',
        error: e,
        stackTrace: st,
      );
      return Failure(
        DataException(
          message: '無法上傳視頻: $e',
          originalException: e is Exception ? e : Exception(e),
        ),
        st,
      );
    }
  }

  void dispose() {
    Logger.debug('RecordingRepository 已銷毀');
  }
}
