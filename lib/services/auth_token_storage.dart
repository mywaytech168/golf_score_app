import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 認證令牌存儲服務
/// 使用 flutter_secure_storage 加密存儲 JWT，防止明文讀取
class AuthTokenStorage {
  static const String _accessTokenKey  = 'auth_access_token';
  static const String _refreshTokenKey = 'auth_refresh_token';
  static const String _userIdKey       = 'auth_user_id';
  static const String _userEmailKey    = 'auth_user_email';

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  AuthTokenStorage._();
  static final AuthTokenStorage instance = AuthTokenStorage._();

  Future<void> saveTokens({
    required String accessToken,
    required String? refreshToken,
    required String userId,
    required String? userEmail,
  }) async {
    await _storage.write(key: _accessTokenKey, value: accessToken);
    if (refreshToken != null) {
      await _storage.write(key: _refreshTokenKey, value: refreshToken);
    }
    await _storage.write(key: _userIdKey, value: userId);
    if (userEmail != null) {
      await _storage.write(key: _userEmailKey, value: userEmail);
    }
  }

  Future<String?> getAccessToken()  async => _storage.read(key: _accessTokenKey);
  Future<String?> getRefreshToken() async => _storage.read(key: _refreshTokenKey);
  Future<String?> getUserId()       async => _storage.read(key: _userIdKey);
  Future<String?> getUserEmail()    async => _storage.read(key: _userEmailKey);

  Future<void> clearTokens() async => _storage.deleteAll();

  Future<bool> isLoggedIn() async {
    final token = await getAccessToken();
    return token != null && token.isNotEmpty;
  }
}
