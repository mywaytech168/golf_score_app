import '../utils/exceptions.dart';
import '../utils/logger.dart';
import 'result.dart';
import 'data_sources.dart';

/// 用戶 Repository
/// 
/// 管理用戶資料和個人信息
class UserRepository {
  final LocalDataSource _localDataSource;
  final RemoteDataSource _remoteDataSource;

  UserRepository({
    required LocalDataSource localDataSource,
    required RemoteDataSource remoteDataSource,
  })  : _localDataSource = localDataSource,
        _remoteDataSource = remoteDataSource;

  /// 清理资源
  void dispose() {
    Logger.debug('User repository disposed', tag: 'UserRepository');
  }

  /// 獲取用戶資料（本地優先）
  Future<Result<Map<String, dynamic>>> getUserProfile(
    String userId, {
    bool forceRefresh = false,
  }) async {
    try {
      Logger.info('獲取用戶資料', tag: 'UserRepository');

      // 先嘗試獲取本地資料
      if (!forceRefresh) {
        final localResult = await _localDataSource.getUserProfile();
        if (localResult.isSuccess) {
          final localData = localResult.getOrNull();
          if (localData != null && localData.isNotEmpty) {
            Logger.info('使用本地用戶資料', tag: 'UserRepository');
            return localResult;
          }
        }
      }

      // 從遠程獲取
      final remoteResult = await _remoteDataSource.fetchUserProfile(userId);

      if (remoteResult.isSuccess) {
        final profile = remoteResult.getOrNull();
        if (profile != null) {
          // 保存到本地
          await _localDataSource.saveUserProfile(profile);
          Logger.info('用戶資料已更新', tag: 'UserRepository');
        }
      }

      return remoteResult;
    } catch (e, st) {
      Logger.error(
        '獲取用戶資料失敗',
        tag: 'UserRepository',
        error: e,
        stackTrace: st,
      );
      return Failure(
        DataException(
          message: '無法獲取用戶資料: $e',
          originalException: e is Exception ? e : Exception(e),
        ),
        st,
      );
    }
  }

  /// 更新用戶資料
  Future<Result<Map<String, dynamic>>> updateUserProfile(
    String userId,
    Map<String, dynamic> profileData,
  ) async {
    try {
      Logger.info('更新用戶資料', tag: 'UserRepository');

      // 調用遠程服務
      final result = await _remoteDataSource.updateUserProfile(
        userId,
        profileData,
      );

      if (result.isSuccess) {
        final updatedProfile = result.getOrNull();
        if (updatedProfile != null) {
          // 更新本地快取
          await _localDataSource.saveUserProfile(updatedProfile);
          Logger.info('用戶資料更新成功', tag: 'UserRepository');
        }
      }

      return result;
    } catch (e, st) {
      Logger.error(
        '更新用戶資料失敗',
        tag: 'UserRepository',
        error: e,
        stackTrace: st,
      );
      return Failure(
        DataException(
          message: '無法更新用戶資料: $e',
          originalException: e is Exception ? e : Exception(e),
        ),
        st,
      );
    }
  }

  /// 更新用戶暱稱
  Future<Result<Map<String, dynamic>>> updateDisplayName(
    String userId,
    String displayName,
  ) async {
    try {
      if (displayName.trim().isEmpty) {
        return Failure(
          ValidationException(
            message: '暱稱不能為空',
            fieldErrors: {'displayName': '请输入有效的暱稱'},
          ),
        );
      }

      return await updateUserProfile(
        userId,
        {'displayName': displayName.trim()},
      );
    } catch (e, st) {
      Logger.error(
        '更新暱稱失敗',
        tag: 'UserRepository',
        error: e,
        stackTrace: st,
      );
      return Failure(
        DataException(
          message: '無法更新暱稱: $e',
          originalException: e is Exception ? e : Exception(e),
        ),
        st,
      );
    }
  }

  /// 更新用戶頭像
  Future<Result<Map<String, dynamic>>> updateAvatar(
    String userId,
    String avatarPath,
  ) async {
    try {
      return await updateUserProfile(
        userId,
        {'avatarPath': avatarPath},
      );
    } catch (e, st) {
      Logger.error(
        '更新頭像失敗',
        tag: 'UserRepository',
        error: e,
        stackTrace: st,
      );
      return Failure(
        DataException(
          message: '無法更新頭像: $e',
          originalException: e is Exception ? e : Exception(e),
        ),
        st,
      );
    }
  }

  /// 清除本地用戶資料
  Future<Result<void>> clearLocalProfile() async {
    try {
      Logger.info('清除本地用戶資料', tag: 'UserRepository');
      return await _localDataSource.clearUserProfile();
    } catch (e, st) {
      Logger.error(
        '清除本地用戶資料失敗',
        tag: 'UserRepository',
        error: e,
        stackTrace: st,
      );
      return Failure(
        StorageException(
          message: '無法清除本地資料: $e',
          originalException: e is Exception ? e : Exception(e),
        ),
        st,
      );
    }
  }

  void dispose() {
    Logger.debug('UserRepository 已銷毀');
  }
}
