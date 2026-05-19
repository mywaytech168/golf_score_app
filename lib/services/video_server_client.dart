import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'auth_token_storage.dart';
import '../models/statistics_response.dart';

/// 授權異常 - 當 API 返回 401 時拋出
class UnauthorizedException implements Exception {
  final String message;
  UnauthorizedException(this.message);

  @override
  String toString() => message;
}

/// 伺服器 API 客戶端（登入/統計，不含上傳/同步）
class VideoServerClient {
  static const String _baseUrl = 'https://tekswing.api.atk.tw';

  static final VideoServerClient _instance = VideoServerClient._internal();

  factory VideoServerClient() => _instance;

  static VideoServerClient get instance => _instance;

  VideoServerClient._internal();

  /// 是否正在刷新 token（防止重複刷新）
  bool _isRefreshing = false;

  /// 等待刷新完成的 Completer 列表
  final List<Completer<bool>> _refreshWaiters = [];

  /// 獲取認證請求頭
  Future<Map<String, String>> _getAuthHeaders() async {
    final token = await AuthTokenStorage.instance.getAccessToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// 嘗試自動刷新 Token
  Future<bool> _tryRefreshToken() async {
    if (_isRefreshing) {
      final completer = Completer<bool>();
      _refreshWaiters.add(completer);
      return completer.future;
    }

    _isRefreshing = true;
    debugPrint('🔄 嘗試自動刷新 Token...');

    try {
      final refreshTokenValue = await AuthTokenStorage.instance.getRefreshToken();

      if (refreshTokenValue == null || refreshTokenValue.isEmpty) {
        debugPrint('❌ 沒有可用的 Refresh Token');
        return false;
      }

      final response = await http.post(
        Uri.parse('$_baseUrl/api/auth/refresh-token'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refreshToken': refreshTokenValue}),
      );

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['data'] != null && result['data']['accessToken'] != null) {
          await AuthTokenStorage.instance.saveTokens(
            accessToken: result['data']['accessToken'],
            refreshToken: result['data']['refreshToken'],
            userId: result['data']['userId'] ?? await AuthTokenStorage.instance.getUserId() ?? '',
            userEmail: result['data']['email'],
          );
          debugPrint('✅ Token 刷新成功');
          for (final w in _refreshWaiters) {
            w.complete(true);
          }
          _refreshWaiters.clear();
          return true;
        }
      }

      debugPrint('❌ Token 刷新失敗: ${response.statusCode}');
      for (final w in _refreshWaiters) {
        w.complete(false);
      }
      _refreshWaiters.clear();
      return false;
    } catch (e) {
      debugPrint('❌ Token 刷新異常: $e');
      for (final w in _refreshWaiters) {
        w.complete(false);
      }
      _refreshWaiters.clear();
      return false;
    } finally {
      _isRefreshing = false;
    }
  }

  // ============================================================
  // 身份驗證方法
  // ============================================================

  /// 本地帳號登入
  Future<Map<String, dynamic>> loginLocal({
    required String username,
    required String password,
  }) async {
    try {
      final url = Uri.parse('$_baseUrl/api/auth/login');
      debugPrint('🔑 本地登入 → $url');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': username, 'password': password}),
      );

      debugPrint('📥 Response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        // 支援兩種格式：根層級 {token, user} 或包裹在 data 內
        final data = result['data'];
        if (data != null) {
          await AuthTokenStorage.instance.saveTokens(
            accessToken: data['accessToken'] ?? data['token'] ?? '',
            refreshToken: data['refreshToken'],
            userId: data['userId'] ?? data['id'] ?? '',
            userEmail: data['email'],
          );
        } else if (result['token'] != null) {
          final user = result['user'];
          await AuthTokenStorage.instance.saveTokens(
            accessToken: result['token'] ?? '',
            refreshToken: result['refreshToken'],
            userId: user?['id']?.toString() ?? '',
            userEmail: user?['email'],
          );
        }
        return result;
      } else {
        final errorJson = jsonDecode(response.body);
        return {
          'success': false,
          'message': errorJson['message'] ?? '登入失敗: ${response.statusCode}',
        };
      }
    } catch (e) {
      debugPrint('❌ 登入異常: $e');
      return {'success': false, 'message': '登入錯誤: $e'};
    }
  }

  /// 本地帳號註冊
  Future<Map<String, dynamic>> registerLocal({
    required String username,
    required String email,
    required String password,
    required String displayName,
  }) async {
    try {
      final url = Uri.parse('$_baseUrl/api/auth/register');
      debugPrint('📝 本地註冊 → $url');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          'email': email,
          'password': password,
          'displayName': displayName,
        }),
      );

      debugPrint('📥 Response: ${response.statusCode}');

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final errorJson = jsonDecode(response.body);
        return {
          'success': false,
          'message': errorJson['message'] ?? '註冊失敗: ${response.statusCode}',
        };
      }
    } catch (e) {
      debugPrint('❌ 註冊異常: $e');
      return {'success': false, 'message': '註冊錯誤: $e'};
    }
  }

  /// Google OAuth 登入
  Future<Map<String, dynamic>> loginWithGoogle({
    required String idToken,
    required String email,
    required String? displayName,
    required String? avatarUrl,
  }) async {
    try {
      final url = Uri.parse('$_baseUrl/api/auth/google-login');
      debugPrint('🔍 Google 登入 → $url');
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'idToken': idToken,
              'email': email,
              'displayName': displayName ?? email,
              'avatarUrl': avatarUrl ?? '',
            }),
          )
          .timeout(const Duration(seconds: 10));

      debugPrint('📥 Response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['token'] != null) {
          final userId = result['user']?['id'] ?? '';
          final userEmail = result['user']?['email'];
          await AuthTokenStorage.instance.saveTokens(
            accessToken: result['token'],
            refreshToken: result['refreshToken'],
            userId: userId,
            userEmail: userEmail,
          );
        }
        return result;
      } else {
        try {
          final errorJson = jsonDecode(response.body);
          return {
            'success': false,
            'message': errorJson['message'] ?? 'Google 登入失敗: ${response.statusCode}',
          };
        } catch (_) {
          return {'success': false, 'message': 'Google 登入失敗: ${response.statusCode}'};
        }
      }
    } on TimeoutException {
      return {'success': false, 'message': 'Google 登入超時，請檢查網絡連接'};
    } catch (e) {
      debugPrint('❌ Google 登入異常: $e');
      return {'success': false, 'message': 'Google 登入錯誤: $e'};
    }
  }

  /// 刷新 Token
  Future<Map<String, dynamic>> refreshToken(String refreshToken) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/auth/refresh-token'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refreshToken': refreshToken}),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        return {'success': false, 'message': '刷新 Token 失敗'};
      }
    } catch (e) {
      return {'success': false, 'message': '刷新 Token 錯誤: $e'};
    }
  }

  // ============================================================
  // 統計數據
  // ============================================================

  Future<StatisticsResponse?> getStatistics({
    required String period,
    String? date,
    bool isRetry = false,
  }) async {
    try {
      final headers = await _getAuthHeaders();
      final url = Uri.parse('$_baseUrl/api/statistics').replace(
        queryParameters: {
          'period': period,
          if (date != null) 'date': date,
        },
      );

      debugPrint('📊 獲取統計數據: period=$period');
      final response = await http.get(url, headers: headers);
      debugPrint('📥 Response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return StatisticsResponse.fromJson(json);
      } else if (response.statusCode == 401 && !isRetry) {
        final refreshSuccess = await _tryRefreshToken();
        if (refreshSuccess) {
          return getStatistics(period: period, date: date, isRetry: true);
        }
        throw UnauthorizedException('統計數據獲取失敗: ${response.statusCode}');
      } else {
        debugPrint('❌ 統計數據獲取失敗: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      if (e is UnauthorizedException) rethrow;
      debugPrint('❌ 統計數據異常: $e');
      return null;
    }
  }
}
