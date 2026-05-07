import '../utils/exceptions.dart';
import '../utils/logger.dart';
import 'result.dart';
import 'data_sources.dart';

/// 認證 Repository
/// 
/// 統一管理認證邏輯，協調本地和遠程數據源
class AuthRepository {
  final LocalDataSource _localDataSource;
  final RemoteDataSource _remoteDataSource;

  AuthRepository({
    required LocalDataSource localDataSource,
    required RemoteDataSource remoteDataSource,
  })  : _localDataSource = localDataSource,
        _remoteDataSource = remoteDataSource;

  /// 簽入 Google
  /// 返回包含 accessToken, refreshToken, userId 等信息的結果
  Future<Result<Map<String, dynamic>>> signInWithGoogle(String googleToken) async {
    try {
      Logger.info('開始 Google 登入', tag: 'AuthRepository');

      // 調用遠程服務獲取令牌
      final authData = await _remoteDataSource.signInWithGoogle(googleToken);

      // 提取令牌
      final accessToken = authData['accessToken'] as String?;
      final refreshToken = authData['refreshToken'] as String?;

      if (accessToken == null || refreshToken == null) {
        throw AuthException(
          message: '無效的認證響應: 缺少令牌',
        );
      }

      // 保存令牌到本地
      await _localDataSource.saveAccessToken(accessToken, refreshToken);
      Logger.info('Google 登入成功，令牌已保存', tag: 'AuthRepository');

      return Success(authData);
    } on AppException {
      rethrow;
    } catch (e, st) {
      Logger.error('Google 登入失敗: $e', tag: 'AuthRepository');
      return Failure(
        AuthException(
          message: '登入失敗: $e',
          originalException: e is Exception ? e : Exception(e),
        ),
        st,
      );
    }
  }

  /// 刷新令牌
  Future<Result<String>> refreshToken(String currentRefreshToken) async {
    try {
      Logger.info('刷新認證令牌', tag: 'AuthRepository');

      final authData = await _remoteDataSource.refreshToken(currentRefreshToken);
      
      final newAccessToken = authData['accessToken'] as String?;
      final newRefreshToken = authData['refreshToken'] as String?;

      if (newAccessToken == null) {
        throw InvalidTokenException('無法從響應中獲取新令牌');
      }

      // 保存新令牌到本地
      await _localDataSource.saveAccessToken(
        newAccessToken,
        newRefreshToken ?? currentRefreshToken,
      );
      Logger.info('令牌刷新成功', tag: 'AuthRepository');

      return Success(newAccessToken);
    } on InvalidTokenException {
      rethrow;
    } catch (e, st) {
      Logger.error('令牌刷新失敗: $e', tag: 'AuthRepository');
      return Failure(
        AuthException(
          message: '刷新令牌失敗: $e',
          originalException: e is Exception ? e : Exception(e),
        ),
        st,
      );
    }
  }

  /// 簽出
  Future<Result<void>> signOut() async {
    try {
      Logger.info('開始簽出用戶', tag: 'AuthRepository');

      // 獲取當前令牌以便調用遠程 API
      final accessToken = await _localDataSource.getAccessToken();
      
      if (accessToken != null) {
        // 調用遠程服務
        try {
          await _remoteDataSource.signOut(accessToken);
        } catch (e) {
          Logger.warning('遠程簽出失敗，但繼續清除本地數據: $e', tag: 'AuthRepository');
        }
      }

      // 清除本地數據
      await _localDataSource.clearAuthTokens();
      await _localDataSource.clearUserProfile();
      await _localDataSource.clearAllCache();
      Logger.info('簽出成功，本地數據已清除', tag: 'AuthRepository');

      return Success(null);
    } catch (e, st) {
      Logger.error('簽出失敗: $e', tag: 'AuthRepository');

      // 嘗試清除本地數據
      try {
        await _localDataSource.clearAuthTokens();
      } catch (_) {}

      return Failure(
        AuthException(
          message: '簽出失敗: $e',
          originalException: e is Exception ? e : Exception(e),
        ),
        st,
      );
    }
  }

  /// 獲取訪問令牌
  Future<Result<String?>> getAccessToken() async {
    try {
      final token = await _localDataSource.getAccessToken();
      return Success(token);
    } catch (e, st) {
      Logger.error('獲取訪問令牌失敗: $e', tag: 'AuthRepository');
      return Failure(
        StorageException(
          message: '無法獲取訪問令牌: $e',
          originalException: e is Exception ? e : Exception(e),
        ),
        st,
      );
    }
  }

  /// 檢查是否已登入
  Future<Result<bool>> isLoggedIn() async {
    try {
      final token = await _localDataSource.getAccessToken();
      final isLoggedIn = token != null && token.isNotEmpty;
      return Success(isLoggedIn);
    } catch (e, st) {
      Logger.error('檢查登入狀態失敗: $e', tag: 'AuthRepository');
      return Failure(
        AuthException(
          message: '無法檢查登入狀態: $e',
          originalException: e is Exception ? e : Exception(e),
        ),
        st,
      );
    }
  }

  /// 清理資源
  void dispose() {
    Logger.debug('Auth repository disposed', tag: 'AuthRepository');
  }
}
