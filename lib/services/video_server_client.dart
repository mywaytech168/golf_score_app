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

  /// 獲取認證請求頭
  Future<Map<String, String>> _getAuthHeaders() async {
    final token = await AuthTokenStorage.instance.getAccessToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// 嘗試自動刷新 Token（委派給共用的 AuthTokenStorage.tryRefreshToken）
  Future<bool> _tryRefreshToken() =>
      AuthTokenStorage.instance.tryRefreshToken();

  /// 預設請求逾時時間。山區/弱訊號時避免無限等待造成 UI 卡死。
  static const Duration _defaultTimeout = Duration(seconds: 15);

  /// 統一的 HTTP 送出函式。
  ///
  /// - 一律套用 [_defaultTimeout]（弱訊號保護）。
  /// - [auth] 為 true 時帶上 Bearer token，並在收到 401 時自動刷新 token 重試一次；
  ///   刷新失敗則拋出 [UnauthorizedException]。
  /// - 回傳原始 [http.Response]，由呼叫端依需求解析 body / 狀態碼。
  Future<http.Response> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool auth = true,
    Duration? timeout,
  }) async {
    final url = Uri.parse('$_baseUrl$path');
    final encoded = body == null ? null : jsonEncode(body);

    Future<http.Response> once() async {
      final headers = auth
          ? await _getAuthHeaders()
          : {'Content-Type': 'application/json'};
      final req = switch (method) {
        'GET' => http.get(url, headers: headers),
        'POST' => http.post(url, headers: headers, body: encoded),
        'PATCH' => http.patch(url, headers: headers, body: encoded),
        'PUT' => http.put(url, headers: headers, body: encoded),
        'DELETE' => http.delete(url, headers: headers, body: encoded),
        _ => throw ArgumentError('不支援的 method: $method'),
      };
      return req.timeout(timeout ?? _defaultTimeout);
    }

    var res = await once();
    if (auth && res.statusCode == 401) {
      final ok = await _tryRefreshToken();
      if (!ok) throw UnauthorizedException('$method $path: 401');
      res = await once();
      if (res.statusCode == 401) {
        throw UnauthorizedException('$method $path: 401 (刷新後仍失敗)');
      }
    }
    return res;
  }

  // ============================================================
  // 版本檢查（不需要登入 Token）
  // ============================================================

  /// 查詢最新版本資訊。
  ///
  /// 端點：GET /api/app/version?platform=android|ios&version=1.0.0
  ///
  /// 預期回傳：
  /// ```json
  /// {
  ///   "latestVersion": "1.2.0",
  ///   "minRequiredVersion": "1.1.0",
  ///   "forceUpdate": false,
  ///   "updateUrl": "https://play.google.com/...",
  ///   "releaseNotes": ["修正 A", "新增 B"],
  ///   "releaseDate": "2026-05-25"
  /// }
  /// ```
  /// 若網路異常或後端回傳非 200，回傳 null（呼叫端視為不需更新）。
  Future<Map<String, dynamic>?> checkVersion({
    required String platform,
    required String version,
  }) async {
    try {
      final response = await _send(
        'GET',
        '/api/app/version?platform=$platform&version=$version',
        auth: false,
        timeout: const Duration(seconds: 8),
      );
      debugPrint('📥 版本檢查回應: ${response.statusCode}');

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return (json['data'] as Map<String, dynamic>?) ?? json;
      }
      return null;
    } catch (e) {
      debugPrint('❌ 版本檢查異常: $e');
      return null;
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
      final response = await _send(
        'POST',
        '/api/auth/login',
        auth: false,
        body: {'username': username, 'password': password},
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
    String? inviteCode,
  }) async {
    try {
      final response = await _send(
        'POST',
        '/api/auth/register',
        auth: false,
        body: {
          'username': username,
          'email': email,
          'password': password,
          'displayName': displayName,
          if (inviteCode != null && inviteCode.isNotEmpty)
            'inviteCode': inviteCode.toUpperCase(),
        },
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

  /// 忘記密碼：請求寄送 6 位驗證碼
  Future<Map<String, dynamic>> forgotPassword(String email) async {
    try {
      final response = await _send(
        'POST',
        '/api/auth/forgot-password',
        auth: false,
        body: {'email': email},
      );
      if (response.statusCode == 200) return jsonDecode(response.body);
      final err = jsonDecode(response.body);
      return {'success': false, 'message': err['message'] ?? '寄送失敗'};
    } catch (e) {
      return {'success': false, 'message': '網路錯誤: $e'};
    }
  }

  /// 重設密碼：驗證碼 + 新密碼
  Future<Map<String, dynamic>> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    try {
      final response = await _send(
        'POST',
        '/api/auth/reset-password',
        auth: false,
        body: {
          'email': email,
          'code': code,
          'newPassword': newPassword,
        },
      );
      if (response.statusCode == 200) return jsonDecode(response.body);
      final err = jsonDecode(response.body);
      return {'success': false, 'message': err['message'] ?? '重設失敗'};
    } catch (e) {
      return {'success': false, 'message': '網路錯誤: $e'};
    }
  }

  /// 刷新 Token
  Future<Map<String, dynamic>> refreshToken(String refreshToken) async {
    try {
      final response = await _send(
        'POST',
        '/api/auth/refresh-token',
        auth: false,
        body: {'refreshToken': refreshToken},
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
      final response = await _send('GET', '/api/user/plan');
      debugPrint('📥 Response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        // 支援 { data: {...} } 或直接回傳欄位
        return (json['data'] as Map<String, dynamic>?) ?? json;
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
  /// [store]         - 'google_play' | 'app_store'
  /// [purchaseToken] - Google Pay token / Play purchase token / App Store receipt
  Future<bool> purchasePlan(
    String plan,
    String store,
    String purchaseToken, {
    String? productId,
    bool isRetry = false,
  }) async {
    try {
      debugPrint('💳 購買方案 → plan=$plan store=$store');
      final response = await _send(
        'POST',
        '/api/user/plan/purchase',
        body: {
          'plan': plan,
          'store': store,
          'purchaseToken': purchaseToken,
          if (productId != null) 'productId': productId,
        },
      );
      debugPrint('📥 Response: ${response.statusCode}');

      if (response.statusCode == 200) {
        return true;
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

  /// 購買球數包（consumable 內購）
  ///
  /// [productId] - 'golf_balls_1' | 'golf_balls_5' | 'golf_balls_10' | 'golf_balls_50' | 'golf_balls_100'
  /// [store]     - 'google_play' | 'app_store'
  Future<Map<String, dynamic>?> purchaseBalls(
    String productId,
    String store,
    String purchaseToken, {
    bool isRetry = false,
  }) async {
    try {
      debugPrint('⚾ 購買球包 → productId=$productId store=$store');
      final response = await _send(
        'POST',
        '/api/user/balls/purchase',
        body: {
          'productId': productId,
          'store': store,
          'purchaseToken': purchaseToken,
        },
      );
      debugPrint('📥 Response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return (json['data'] as Map<String, dynamic>?) ?? json;
      } else {
        debugPrint('❌ 購買球包失敗: ${response.statusCode} ${response.body}');
        return null;
      }
    } catch (e) {
      if (e is UnauthorizedException) rethrow;
      debugPrint('❌ 購買球包異常: $e');
      return null;
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
      final response = await _send('GET', '/api/user/rewards');
      debugPrint('📥 Response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return (json['data'] as Map<String, dynamic>?) ?? json;
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
      final response = await _send('POST', '/api/user/rewards/ad');
      debugPrint('📥 Response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return (json['data'] as Map<String, dynamic>?) ?? json;
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

  // ============================================================
  // 使用紀錄
  // ============================================================

  /// 分頁查詢 AI 分析紀錄
  Future<Map<String, dynamic>?> getAnalysisHistory({
    int page = 1,
    int pageSize = 20,
    bool isRetry = false,
  }) async {
    try {
      final response = await _send('GET',
          '/api/user/analysis/history?page=$page&pageSize=$pageSize');

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return (json['data'] as Map<String, dynamic>?) ?? json;
      }
      return null;
    } catch (e) {
      if (e is UnauthorizedException) rethrow;
      debugPrint('❌ 分析紀錄異常: $e');
      return null;
    }
  }

  /// 分頁查詢球數流水帳
  Future<Map<String, dynamic>?> getBallsHistory({
    int page = 1,
    int pageSize = 20,
    bool isRetry = false,
  }) async {
    try {
      final response = await _send('GET',
          '/api/user/balls/history?page=$page&pageSize=$pageSize');

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return (json['data'] as Map<String, dynamic>?) ?? json;
      }
      return null;
    } catch (e) {
      if (e is UnauthorizedException) rethrow;
      debugPrint('❌ 球數紀錄異常: $e');
      return null;
    }
  }

  /// 取得已邀請好友列表
  ///
  /// 回傳格式：
  /// ```json
  /// { "total": 2, "friends": [
  ///   { "displayName": "John", "avatarUrl": null,
  ///     "joinedAt": "2024-01-15T10:00:00Z", "ballsEarned": 5 }, ...
  /// ]}
  /// ```
  Future<Map<String, dynamic>?> getInvitedFriends({bool isRetry = false}) async {
    try {
      final response = await _send('GET', '/api/user/invite/friends');
      debugPrint('📥 Response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return (json['data'] as Map<String, dynamic>?) ?? json;
      } else {
        debugPrint('❌ 取得邀請好友失敗: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      if (e is UnauthorizedException) rethrow;
      debugPrint('❌ 取得邀請好友異常: $e');
      return null;
    }
  }

  /// 取得使用者邀請碼
  Future<String?> getInviteCode({bool isRetry = false}) async {
    try {
      final response = await _send('GET', '/api/user/invite-code');
      debugPrint('📥 Response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final data = (json['data'] as Map<String, dynamic>?) ?? json;
        return data['code'] as String?;
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

  // ============================================================
  // 使用者個人資料
  // ============================================================

  /// 取得目前登入使用者資訊
  ///
  /// 回傳格式：`{ "id", "username", "email", "displayName", "googleLinked": bool }`
  Future<Map<String, dynamic>?> getMe({bool isRetry = false}) async {
    try {
      final response = await _send('GET', '/api/user/me',
          timeout: const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return (json['data'] as Map<String, dynamic>?) ?? json;
      }
      return null;
    } catch (e) {
      if (e is UnauthorizedException) rethrow;
      debugPrint('❌ getMe 異常: $e');
      return null;
    }
  }

  /// 更新顯示名稱（伺服器端同步）
  ///
  /// 端點：PATCH /api/user/me  body: `{ "displayName": "..." }`
  Future<bool> updateProfileName(String displayName, {bool isRetry = false}) async {
    try {
      final response = await _send('PATCH', '/api/user/me',
          body: {'displayName': displayName.trim()});
      if (response.statusCode == 200) return true;
      debugPrint('❌ updateProfileName: ${response.statusCode}');
      return false;
    } catch (e) {
      if (e is UnauthorizedException) rethrow;
      debugPrint('❌ updateProfileName 異常: $e');
      return false;
    }
  }

  /// 修改密碼（需要目前密碼驗證）
  ///
  /// 端點：POST /api/auth/change-password
  /// body: `{ "currentPassword": "...", "newPassword": "..." }`
  Future<Map<String, dynamic>> changePassword({
    required String currentPassword,
    required String newPassword,
    bool isRetry = false,
  }) async {
    try {
      final response = await _send(
        'POST',
        '/api/auth/change-password',
        body: {
          'currentPassword': currentPassword,
          'newPassword': newPassword,
        },
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      final err = jsonDecode(response.body) as Map<String, dynamic>;
      return {'success': false, 'message': err['message'] ?? '修改失敗 (${response.statusCode})'};
    } catch (e) {
      if (e is UnauthorizedException) rethrow;
      return {'success': false, 'message': '網路錯誤: $e'};
    }
  }

  /// 永久刪除目前登入的帳號及其資料（App Store / Google Play 強制要求）。
  ///
  /// 端點：DELETE /api/user/me
  /// 回傳格式：`{ "success": true }`，刪除成功回傳 true。
  Future<bool> deleteAccount({bool isRetry = false}) async {
    try {
      final response = await _send('DELETE', '/api/user/me');
      if (response.statusCode == 200 || response.statusCode == 204) {
        return true;
      }
      debugPrint('❌ deleteAccount: ${response.statusCode}');
      return false;
    } catch (e) {
      if (e is UnauthorizedException) rethrow;
      debugPrint('❌ deleteAccount 異常: $e');
      return false;
    }
  }

  /// 綁定 Google 帳號（idToken from google_sign_in）
  ///
  /// 端點：POST /api/auth/google/link  body: `{ "idToken": "..." }`
  Future<Map<String, dynamic>> linkGoogleAccount(String idToken, {bool isRetry = false}) async {
    try {
      final response = await _send('POST', '/api/auth/google/link',
          body: {'idToken': idToken});
      if (response.statusCode == 200) return jsonDecode(response.body);
      final err = jsonDecode(response.body) as Map<String, dynamic>;
      return {'success': false, 'message': err['message'] ?? '綁定失敗 (${response.statusCode})'};
    } catch (e) {
      if (e is UnauthorizedException) rethrow;
      return {'success': false, 'message': '網路錯誤: $e'};
    }
  }

  /// 套用邀請碼（每帳號限一次）
  ///
  /// 回傳格式：`{ "success": true, "message": "...", "ballsEarned": 5 }`
  Future<Map<String, dynamic>?> applyInviteCode(
    String inviteCode, {
    bool isRetry = false,
  }) async {
    try {
      debugPrint('🎟️ 套用邀請碼 → code=$inviteCode');
      final response = await _send('POST', '/api/user/invite/apply',
          body: {'inviteCode': inviteCode.toUpperCase()});
      debugPrint('📥 Response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return (json['data'] as Map<String, dynamic>?) ?? json;
      } else if (response.statusCode == 400) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return {'success': false, 'message': json['message'] ?? '邀請碼無效'};
      } else {
        debugPrint('❌ 套用邀請碼失敗: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      if (e is UnauthorizedException) rethrow;
      debugPrint('❌ 套用邀請碼異常: $e');
      return null;
    }
  }

  /// 取得回饋圖片上傳的 pre-signed PUT URL
  ///
  /// 回傳格式：`{ "uploadUrl": "...", "imageId": "..." }`
  Future<Map<String, dynamic>?> getFeedbackImageUploadUrl() async {
    try {
      final response = await _send(
          'GET', '/api/user/rewards/feedback/image-upload-url');
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return json['data'] as Map<String, dynamic>?;
      }
      return null;
    } catch (e) {
      debugPrint('❌ 取得回饋圖片上傳 URL 異常: $e');
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
    String? videoId,
    String? imageB2Key,
    bool isRetry = false,
  }) async {
    try {
      debugPrint('💬 提交回饋');
      final response = await _send(
        'POST',
        '/api/user/rewards/feedback',
        body: {
          'type': type,
          'text': text,
          if (videoId != null) 'videoId': videoId,
          if (imageB2Key != null) 'imageB2Key': imageB2Key,
        },
      );
      debugPrint('📥 Response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return (json['data'] as Map<String, dynamic>?) ?? json;
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
      debugPrint('☁️ 上傳資料獎勵 (${sessions.length} 筆)');
      final response = await _send('POST', '/api/user/rewards/upload',
          body: {'sessions': sessions});
      debugPrint('📥 Response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return (json['data'] as Map<String, dynamic>?) ?? json;
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
