import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'auth_token_storage.dart';

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
        // 後端回傳 { token, refreshToken }（camelCase，無 data wrapper）
        final newToken = result['token'] as String?;
        final newRefresh = result['refreshToken'] as String?;
        if (newToken != null && newToken.isNotEmpty) {
          await AuthTokenStorage.instance.saveTokens(
            accessToken: newToken,
            refreshToken: newRefresh,
            userId: await AuthTokenStorage.instance.getUserId() ?? '',
            userEmail: await AuthTokenStorage.instance.getUserEmail(),
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
  // 方案管理
  // ============================================================

  /// 取得目前方案與今日用量
  ///
  /// 回傳格式：
  /// ```json
  /// { "plan": "free|pro|elite", "dailyLimit": 10, "todayUsed": 3 }
  /// ```
  Future<Map<String, dynamic>?> getPlanStatus({bool isRetry = false}) async {
    try {
      final headers = await _getAuthHeaders();
      final url = Uri.parse('$_baseUrl/api/user/plan');

      debugPrint('📋 取得方案狀態 → $url');
      final response = await http.get(url, headers: headers);
      debugPrint('📥 Response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        // 支援 { data: {...} } 或直接回傳欄位
        return (json['data'] as Map<String, dynamic>?) ?? json;
      } else if (response.statusCode == 401 && !isRetry) {
        final ok = await _tryRefreshToken();
        if (ok) return getPlanStatus(isRetry: true);
        throw UnauthorizedException('取得方案失敗: 401');
      } else {
        debugPrint('❌ 取得方案失敗: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      if (e is UnauthorizedException) rethrow;
      debugPrint('❌ 取得方案異常: $e');
      return null;
    }
  }

  /// 付款後向後端驗證並升級方案
  ///
  /// [plan]          - 'pro' | 'elite'
  /// [store]         - 'google_pay' | 'google_play' | 'app_store'
  /// [purchaseToken] - Google Pay token / Play purchase token / App Store receipt
  Future<bool> purchasePlan(
    String plan,
    String store,
    String purchaseToken, {
    String? productId,
    bool isRetry = false,
  }) async {
    try {
      final headers = await _getAuthHeaders();
      final url = Uri.parse('$_baseUrl/api/user/plan/purchase');

      debugPrint('💳 購買方案 → plan=$plan store=$store');
      final response = await http.post(
        url,
        headers: headers,
        body: jsonEncode({
          'plan': plan,
          'store': store,
          'purchaseToken': purchaseToken,
          if (productId != null) 'productId': productId,
        }),
      );
      debugPrint('📥 Response: ${response.statusCode}');

      if (response.statusCode == 200) {
        return true;
      } else if (response.statusCode == 401 && !isRetry) {
        final ok = await _tryRefreshToken();
        if (ok) return purchasePlan(plan, store, purchaseToken, productId: productId, isRetry: true);
        throw UnauthorizedException('購買方案失敗: 401');
      } else {
        debugPrint('❌ 購買方案失敗: ${response.statusCode} ${response.body}');
        return false;
      }
    } catch (e) {
      if (e is UnauthorizedException) rethrow;
      debugPrint('❌ 購買方案異常: $e');
      return false;
    }
  }

  // ============================================================
  // 獎勵系統
  // ============================================================

  /// 取得獎勵狀態
  ///
  /// 回傳格式：
  /// ```json
  /// { "bonusBalls": 8, "adClaimedToday": 2,
  ///   "feedbackClaimedToday": false,
  ///   "inviteCode": "ABC123", "inviteCount": 1 }
  /// ```
  Future<Map<String, dynamic>?> getRewardStatus({bool isRetry = false}) async {
    try {
      final headers = await _getAuthHeaders();
      final url = Uri.parse('$_baseUrl/api/user/rewards');
      debugPrint('🎁 取得獎勵狀態 → $url');
      final response = await http.get(url, headers: headers);
      debugPrint('📥 Response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return (json['data'] as Map<String, dynamic>?) ?? json;
      } else if (response.statusCode == 401 && !isRetry) {
        final ok = await _tryRefreshToken();
        if (ok) return getRewardStatus(isRetry: true);
        throw UnauthorizedException('取得獎勵失敗: 401');
      } else {
        debugPrint('❌ 取得獎勵失敗: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      if (e is UnauthorizedException) rethrow;
      debugPrint('❌ 取得獎勵異常: $e');
      return null;
    }
  }

  /// 認領看廣告獎勵（每日上限 5 次）
  ///
  /// 回傳格式：`{ "balls": 1, "adClaimedToday": 3 }`
  Future<Map<String, dynamic>?> claimAdReward({bool isRetry = false}) async {
    try {
      final headers = await _getAuthHeaders();
      final url = Uri.parse('$_baseUrl/api/user/rewards/ad');
      debugPrint('📺 認領廣告獎勵 → $url');
      final response = await http.post(url, headers: headers);
      debugPrint('📥 Response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return (json['data'] as Map<String, dynamic>?) ?? json;
      } else if (response.statusCode == 401 && !isRetry) {
        final ok = await _tryRefreshToken();
        if (ok) return claimAdReward(isRetry: true);
        throw UnauthorizedException('廣告獎勵失敗: 401');
      } else {
        debugPrint('❌ 廣告獎勵失敗: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      if (e is UnauthorizedException) rethrow;
      debugPrint('❌ 廣告獎勵異常: $e');
      return null;
    }
  }

  /// 取得使用者邀請碼
  Future<String?> getInviteCode({bool isRetry = false}) async {
    try {
      final headers = await _getAuthHeaders();
      final url = Uri.parse('$_baseUrl/api/user/invite-code');
      debugPrint('🔗 取得邀請碼 → $url');
      final response = await http.get(url, headers: headers);
      debugPrint('📥 Response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final data = (json['data'] as Map<String, dynamic>?) ?? json;
        return data['code'] as String?;
      } else if (response.statusCode == 401 && !isRetry) {
        final ok = await _tryRefreshToken();
        if (ok) return getInviteCode(isRetry: true);
        throw UnauthorizedException('取得邀請碼失敗: 401');
      } else {
        debugPrint('❌ 取得邀請碼失敗: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      if (e is UnauthorizedException) rethrow;
      debugPrint('❌ 取得邀請碼異常: $e');
      return null;
    }
  }

  /// 提交問題回饋並認領獎勵（每日限 1 次）
  ///
  /// [type] = 'bug' | 'feature' | 'other'
  /// 回傳格式：`{ "balls": 2 }`
  Future<Map<String, dynamic>?> submitFeedback({
    required String type,
    required String text,
    bool isRetry = false,
  }) async {
    try {
      final headers = await _getAuthHeaders();
      final url = Uri.parse('$_baseUrl/api/user/rewards/feedback');
      debugPrint('💬 提交回饋 → $url');
      final response = await http.post(
        url,
        headers: headers,
        body: jsonEncode({'type': type, 'text': text}),
      );
      debugPrint('📥 Response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return (json['data'] as Map<String, dynamic>?) ?? json;
      } else if (response.statusCode == 401 && !isRetry) {
        final ok = await _tryRefreshToken();
        if (ok) return submitFeedback(type: type, text: text, isRetry: true);
        throw UnauthorizedException('提交回饋失敗: 401');
      } else {
        debugPrint('❌ 提交回饋失敗: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      if (e is UnauthorizedException) rethrow;
      debugPrint('❌ 提交回饋異常: $e');
      return null;
    }
  }

  /// 上傳本地分析資料並認領獎勵
  ///
  /// [sessions] = 精簡錄影記錄清單（不含影片二進位）
  /// 回傳格式：`{ "balls": 3, "uploaded": 5 }`
  Future<Map<String, dynamic>?> claimUploadReward({
    required List<Map<String, dynamic>> sessions,
    bool isRetry = false,
  }) async {
    try {
      final headers = await _getAuthHeaders();
      final url = Uri.parse('$_baseUrl/api/user/rewards/upload');
      debugPrint('☁️ 上傳資料獎勵 → $url (${sessions.length} 筆)');
      final response = await http.post(
        url,
        headers: headers,
        body: jsonEncode({'sessions': sessions}),
      );
      debugPrint('📥 Response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return (json['data'] as Map<String, dynamic>?) ?? json;
      } else if (response.statusCode == 401 && !isRetry) {
        final ok = await _tryRefreshToken();
        if (ok) return claimUploadReward(sessions: sessions, isRetry: true);
        throw UnauthorizedException('上傳獎勵失敗: 401');
      } else {
        debugPrint('❌ 上傳獎勵失敗: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      if (e is UnauthorizedException) rethrow;
      debugPrint('❌ 上傳獎勵異常: $e');
      return null;
    }
  }
}
