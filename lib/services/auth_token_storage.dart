import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// 當 access + refresh token 雙雙失效，廣播此事件通知 UI 導向登入頁
final sessionExpiredStream = StreamController<void>.broadcast();

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

  /// 刷新失敗（session 完全失效）：清除 tokens 並廣播 sessionExpired
  Future<void> _expireSession() async {
    await clearTokens();
    debugPrint('⚠️ [AuthTokenStorage] Session 已過期，清除 tokens，廣播登出事件');
    sessionExpiredStream.add(null);
  }

  Future<bool> isLoggedIn() async {
    final token = await getAccessToken();
    return token != null && token.isNotEmpty;
  }

  // ── 共用 Token 刷新邏輯 ─────────────────────────────────────
  // 可被多個 HTTP client（VideoServerClient、AnalysisService…）共用

  static const _serverBaseUrl = 'https://tekswing.api.atk.tw';

  bool _isRefreshing = false;
  final List<Completer<bool>> _refreshWaiters = [];

  /// 嘗試使用 refresh token 取得新 access token。
  /// 成功 → 更新儲存並回傳 true；失敗 → 回傳 false。
  /// 多個並發呼叫者只會觸發一次刷新（其餘等待）。
  Future<bool> tryRefreshToken() async {
    if (_isRefreshing) {
      final c = Completer<bool>();
      _refreshWaiters.add(c);
      return c.future;
    }
    _isRefreshing = true;
    debugPrint('🔄 [AuthTokenStorage] 嘗試刷新 Token...');
    try {
      final refreshTokenValue = await getRefreshToken();
      if (refreshTokenValue == null || refreshTokenValue.isEmpty) {
        debugPrint('❌ 沒有可用的 Refresh Token');
        return false;
      }

      final response = await http.post(
        Uri.parse('$_serverBaseUrl/api/auth/refresh-token'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refreshToken': refreshTokenValue}),
      );

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body) as Map<String, dynamic>;
        final newToken   = result['token']        as String?;
        final newRefresh = result['refreshToken'] as String?;
        if (newToken != null && newToken.isNotEmpty) {
          await saveTokens(
            accessToken:  newToken,
            refreshToken: newRefresh,
            userId:       await getUserId()    ?? '',
            userEmail:    await getUserEmail(),
          );
          debugPrint('✅ [AuthTokenStorage] Token 刷新成功');
          for (final w in _refreshWaiters) { w.complete(true); }
          return true;
        }
      }

      debugPrint('❌ [AuthTokenStorage] Token 刷新失敗: ${response.statusCode}');
      for (final w in _refreshWaiters) { w.complete(false); }
      // Refresh token 本身也無效 → 徹底登出並通知 UI
      await _expireSession();
      return false;
    } catch (e) {
      debugPrint('❌ [AuthTokenStorage] Token 刷新異常: $e');
      for (final w in _refreshWaiters) { w.complete(false); }
      return false;
    } finally {
      _refreshWaiters.clear();
      _isRefreshing = false;
    }
  }
}
