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

/// 伺服器 API 客戶端
class VideoServerClient {
  static const String _baseUrl = 'https://tekswing.api.atk.tw';

  static final VideoServerClient _instance = VideoServerClient._internal();

  factory VideoServerClient() {
    return _instance;
  }

  /// 靜態實例訪問器
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

  /// 獲取多部分表單認證請求頭
  Future<Map<String, String>> _getAuthMultipartHeaders() async {
    final token = await AuthTokenStorage.instance.getAccessToken();
    return {
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// 嘗試自動刷新 Token
  /// 返回 true 表示刷新成功，false 表示失敗（需要重新登入）
  Future<bool> _tryRefreshToken() async {
    // 如果已經在刷新中，等待刷新完成
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
        body: jsonEncode({
          'refreshToken': refreshTokenValue,
        }),
      );

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        
        // 檢查是否有新的 token
        if (result['data'] != null && result['data']['accessToken'] != null) {
          await AuthTokenStorage.instance.saveTokens(
            accessToken: result['data']['accessToken'],
            refreshToken: result['data']['refreshToken'],
            userId: result['data']['userId'] ?? await AuthTokenStorage.instance.getUserId() ?? '',
            userEmail: result['data']['email'],
          );
          debugPrint('✅ Token 刷新成功');
          
          // 通知所有等待者刷新成功
          for (final waiter in _refreshWaiters) {
            waiter.complete(true);
          }
          _refreshWaiters.clear();
          return true;
        }
      }
      
      debugPrint('❌ Token 刷新失敗: ${response.statusCode}');
      // 通知所有等待者刷新失敗
      for (final waiter in _refreshWaiters) {
        waiter.complete(false);
      }
      _refreshWaiters.clear();
      return false;
    } catch (e) {
      debugPrint('❌ Token 刷新異常: $e');
      // 通知所有等待者刷新失敗
      for (final waiter in _refreshWaiters) {
        waiter.complete(false);
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
      debugPrint('════════════════════════════════════════');
      debugPrint('🔑 本地登入');
      debugPrint('════════════════════════════════════════');
      debugPrint('📍 URL: $url');
      debugPrint('👤 Username: $username');

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          'password': password,
        }),
      );

      debugPrint('📥 Response Status: ${response.statusCode}');
      debugPrint('📝 Response: ${response.body}');

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        debugPrint('✅ 登入成功');
        debugPrint('💬 Message: ${result['message'] ?? "無"}');

        // 保存令牌
        if (result['data'] != null) {
          await AuthTokenStorage.instance.saveTokens(
            accessToken: result['data']['accessToken'] ?? '',
            refreshToken: result['data']['refreshToken'],
            userId: result['data']['userId'] ?? '',
            userEmail: result['data']['email'],
          );
        }

        return result;
      } else {
        final errorJson = jsonDecode(response.body);
        debugPrint('❌ 登入失敗: ${response.statusCode}');
        debugPrint('💬 Error: ${errorJson['message'] ?? "未知錯誤"}');
        return {
          'success': false,
          'message':
              '${errorJson['message'] ?? "登入失敗: ${response.statusCode}"}',
        };
      }
    } catch (e) {
      debugPrint('❌ 登入異常: $e');
      return {
        'success': false,
        'message': '登入錯誤: $e',
      };
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
      debugPrint('════════════════════════════════════════');
      debugPrint('📝 本地註冊');
      debugPrint('════════════════════════════════════════');
      debugPrint('📍 URL: $url');
      debugPrint('👤 Username: $username');
      debugPrint('📧 Email: $email');
      debugPrint('👤 Display Name: $displayName');

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

      debugPrint('📥 Response Status: ${response.statusCode}');
      debugPrint('📝 Response: ${response.body}');

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        debugPrint('✅ 註冊成功');
        debugPrint('💬 Message: ${result['message'] ?? "無"}');
        return result;
      } else {
        final errorJson = jsonDecode(response.body);
        debugPrint('❌ 註冊失敗: ${response.statusCode}');
        debugPrint('💬 Error: ${errorJson['message'] ?? "未知錯誤"}');
        return {
          'success': false,
          'message':
              '${errorJson['message'] ?? "註冊失敗: ${response.statusCode}"}',
        };
      }
    } catch (e) {
      debugPrint('❌ 註冊異常: $e');
      return {
        'success': false,
        'message': '註冊錯誤: $e',
      };
    }
  }

  /// Google OAuth 登入
  /// 使用 Google ID Token 和相關資訊向後端進行驗證
  Future<Map<String, dynamic>> loginWithGoogle({
    required String idToken,
    required String email,
    required String? displayName,
    required String? avatarUrl,
  }) async {
    try {
      final url = Uri.parse('$_baseUrl/api/auth/google-login');
      final body = {
        'idToken': idToken,
        'email': email,
        'displayName': displayName ?? email,
        'avatarUrl': avatarUrl ?? '',
      };

      debugPrint('════════════════════════════════════════');
      debugPrint('🔍 Google 登入請求');
      debugPrint('════════════════════════════════════════');
      debugPrint('📍 URL: $url');
      debugPrint('📧 Email: $email');
      debugPrint('👤 Display Name: ${displayName ?? email}');
      debugPrint('🔑 ID Token Length: ${idToken.length} characters');
      debugPrint('════════════════════════════════════════');

      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 10));

      debugPrint('📥 Response Status: ${response.statusCode}');
      debugPrint('📝 Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        debugPrint('✅ Google 登入成功');
        debugPrint('🎯 Success: ${result['success']}');
        debugPrint('💬 Message: ${result['message'] ?? "無"}');
        debugPrint('👤 User ID: ${result['user']?['id'] ?? "未知"}');

        // 保存令牌和用戶信息
        if (result['token'] != null) {
          final userId = result['user']?['id'] ?? '';
          final userEmail = result['user']?['email'];

          await AuthTokenStorage.instance.saveTokens(
            accessToken: result['token'],
            refreshToken: result['refreshToken'],
            userId: userId,
            userEmail: userEmail,
          );

          debugPrint('✅ 令牌已保存');
          debugPrint('👤 User ID: $userId');
          debugPrint('📧 Email: $userEmail');
        }

        return result;
      } else {
        final errorBody = response.body;
        try {
          final errorJson = jsonDecode(errorBody);
          debugPrint('❌ Google 登入失敗: ${response.statusCode}');
          debugPrint('💬 Error Message: ${errorJson['message'] ?? "未知錯誤"}');
          debugPrint('📋 Full Error: $errorJson');
          return {
            'success': false,
            'message':
                '${errorJson['message'] ?? "Google 登入失敗: ${response.statusCode}"}',
          };
        } catch (e) {
          debugPrint('❌ Google 登入失敗: ${response.statusCode}');
          debugPrint('💬 Raw Response: $errorBody');
          return {
            'success': false,
            'message': 'Google 登入失敗: ${response.statusCode}',
          };
        }
      }
    } on TimeoutException catch (e) {
      debugPrint('⏱️ Google 登入超時 - ${e.toString()}');
      return {
        'success': false,
        'message': 'Google 登入超時，請檢查網絡連接',
      };
    } catch (e) {
      debugPrint('❌ Google 登入異常: $e');
      debugPrint('📚 Stack Trace: $e');
      return {
        'success': false,
        'message': 'Google 登入錯誤: $e',
      };
    }
  }

  /// 刷新 Token
  Future<Map<String, dynamic>> refreshToken(String refreshToken) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/auth/refresh-token'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'refreshToken': refreshToken,
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        return {
          'success': false,
          'message': '刷新 Token 失敗',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': '刷新 Token 錯誤: $e',
      };
    }
  }

  // ============================================================
  // 影片上傳方法
  // ============================================================

  /// 上傳原始視頻文件到指定的影片紀錄
  ///
  /// [videoId]: 伺服器上的視頻 ID (UUID)
  /// [videoFilePath]: 本地視頻檔案路徑
  /// [fileType]: 檔案類型，通常為 'original' 或 'clip'
  /// [peakValue]: 軌跡的峰值（對應 CSV 檔案）
  Future<Map<String, dynamic>> uploadVideoFile({
    required String videoId,
    required String videoFilePath,
    required String fileType,
    String? sourceLocalFilePath,
    double? peakValue,
  }) async {
    try {
      debugPrint(
          '════════════════════════════════════════════════════════════');
      debugPrint('📤 開始上傳視頻文件');
      debugPrint(
          '════════════════════════════════════════════════════════════');
      debugPrint('🎯 目標視頻 ID: $videoId');
      debugPrint('📂 本地檔案路徑: $videoFilePath');
      debugPrint('🏷️ 檔案類型: $fileType');
      if (sourceLocalFilePath != null && sourceLocalFilePath.isNotEmpty) {
        debugPrint('💾 來源本地檔案路徑: $sourceLocalFilePath');
      }
      if (peakValue != null) {
        debugPrint('📊 軌跡峰值: $peakValue');
      }

      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$_baseUrl/api/videos/$videoId/files'),
      );

      // ❗❗ 關鍵：印真正 request 會送出的 URL
      debugPrint('🚨 REAL REQUEST URL: ${request.url}');
      debugPrint('🚨 REAL REQUEST METHOD: ${request.method}');

      // 你原本的（可以留著對照）
      debugPrint('🧪 STRING URL: $_baseUrl/api/videos/$videoId/files');

      request.fields['fileType'] = fileType;
      
      // 添加 sourceLocalFilePath（如果提供）
      if (sourceLocalFilePath != null && sourceLocalFilePath.isNotEmpty) {
        request.fields['sourceLocalFilePath'] = sourceLocalFilePath;
      }

      // 添加峰值（如果提供）
      if (peakValue != null) {
        request.fields['peakValue'] = peakValue.toString();
      }

      // 添加認證頭
      final authHeaders = await _getAuthMultipartHeaders();
      final token = await AuthTokenStorage.instance.getAccessToken();
      debugPrint('🔑 認證令牌存在: ${token != null && token.isNotEmpty}');
      request.headers.addAll(authHeaders);

      // 添加視頻檔案
      debugPrint('📎 添加檔案到請求...');
      request.files.add(
        await http.MultipartFile.fromPath(
          'file',
          videoFilePath,
        ),
      );

      debugPrint('⬆️ 發送請求...');
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      debugPrint('📥 上傳回應狀態: ${response.statusCode}');
      debugPrint('📝 回應長度: ${response.body.length} 字符');
      if (response.body.length <= 500) {
        debugPrint('📋 回應內容: ${response.body}');
      } else {
        debugPrint('📋 回應內容（前500字符）: ${response.body.substring(0, 500)}...');
      }

      if (response.statusCode == 201 || response.statusCode == 200) {
        debugPrint('✅ 上傳成功');
        
        // 嘗試解析 JSON，如果失敗則返回原始文本
        try {
          final jsonData = jsonDecode(response.body);
          return {
            'success': true,
            'data': jsonData,
          };
        } catch (parseError) {
          debugPrint('⚠️ JSON 解析失敗，返回原始響應');
          debugPrint('📝 Parse Error: $parseError');
          
          // 只要狀態碼是成功的，就認為上傳成功
          // 即使無法解析 JSON
          return {
            'success': true,
            'data': {
              'raw': response.body,
            },
          };
        }
      } else {
        debugPrint('❌ 上傳失敗: ${response.statusCode}');
        return {
          'success': false,
          'error': 'Upload failed: ${response.statusCode}',
          'body': response.body,
        };
      }
    } catch (e) {
      debugPrint(
          '════════════════════════════════════════════════════════════');
      debugPrint('❌ 上傳異常: $e');
      debugPrint(
          '════════════════════════════════════════════════════════════');
      return {
        'success': false,
        'error': 'Upload error: $e',
      };
    }
  }

  /// 上傳單個切片
  ///
  /// [videoId]: 伺服器上的視頻 ID
  /// [sliceIndex]: 切片索引
  /// [videoFile]: 切片視頻檔案
  /// [trajectoryCSV]: 軌跡 CSV 檔案
  Future<Map<String, dynamic>> uploadSlice({
    required int videoId,
    required int sliceIndex,
    required String videoFilePath,
    required String csvFilePath,
  }) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$_baseUrl/api/slices/upload'),
      );

      request.fields['video_id'] = videoId.toString();
      request.fields['slice_index'] = sliceIndex.toString();

      // 添加視頻檔案
      request.files.add(
        await http.MultipartFile.fromPath(
          'video_file',
          videoFilePath,
        ),
      );

      // 添加 CSV 軌跡檔案
      request.files.add(
        await http.MultipartFile.fromPath(
          'trajectory_csv',
          csvFilePath,
        ),
      );

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        return {
          'success': true,
          'data': jsonDecode(response.body),
        };
      } else {
        return {
          'success': false,
          'error': 'Upload failed: ${response.statusCode}',
          'body': response.body,
        };
      }
    } catch (e) {
      return {
        'success': false,
        'error': 'Upload error: $e',
      };
    }
  }

  /// 批量上傳多個切片
  Future<List<Map<String, dynamic>>> uploadMultipleSlices({
    required int videoId,
    required List<Map<String, String>> slices, // 每個包含 videoPath 和 csvPath
  }) async {
    final results = <Map<String, dynamic>>[];

    for (int i = 0; i < slices.length; i++) {
      final slice = slices[i];
      final result = await uploadSlice(
        videoId: videoId,
        sliceIndex: i,
        videoFilePath: slice['videoPath']!,
        csvFilePath: slice['csvPath']!,
      );
      results.add(result);
    }

    return results;
  }

  /// 上傳摆球摘要 CSV 到原始視頻
  ///
  /// [videoId]: 原始視頻 ID（字符串形式）
  /// [hitsSummaryCsvPath]: hits_summary.csv 的文件路徑
  Future<Map<String, dynamic>> uploadHitsSummary({
    required String videoId,
    required String hitsSummaryCsvPath,
  }) async {
    try {
      debugPrint(
          '════════════════════════════════════════════════════════════');
      debugPrint('📤 上傳摆球摘要');
      debugPrint(
          '════════════════════════════════════════════════════════════');
      debugPrint('🎯 視頻 ID: $videoId');
      debugPrint('📂 摆球摘要路徑: $hitsSummaryCsvPath');

      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$_baseUrl/api/videos/$videoId/hits-summary'),
      );

      // 添加認證頭
      final authHeaders = await _getAuthMultipartHeaders();
      request.headers.addAll(authHeaders);

      // 添加 CSV 檔案
      debugPrint('📎 添加摆球摘要 CSV 到請求...');
      request.files.add(
        await http.MultipartFile.fromPath(
          'file',
          hitsSummaryCsvPath,
        ),
      );

      debugPrint('⬆️ 發送摆球摘要上傳請求...');
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      debugPrint('📥 上傳回應狀態: ${response.statusCode}');
      debugPrint('📝 回應長度: ${response.body.length} 字符');
      if (response.body.length <= 500) {
        debugPrint('📋 回應內容: ${response.body}');
      } else {
        debugPrint('📋 回應內容（前500字符）: ${response.body.substring(0, 500)}...');
      }

      if (response.statusCode == 201 || response.statusCode == 200) {
        debugPrint('✅ 摆球摘要上傳成功');
        try {
          final jsonData = jsonDecode(response.body);
          return {
            'success': true,
            'data': jsonData,
          };
        } catch (parseError) {
          debugPrint('⚠️ JSON 解析失敗，返回原始響應');
          return {
            'success': true,
            'data': {
              'raw': response.body,
            },
          };
        }
      } else {
        debugPrint('❌ 摆球摘要上傳失敗: ${response.statusCode}');
        return {
          'success': false,
          'error': 'Upload failed: ${response.statusCode}',
          'body': response.body,
        };
      }
    } catch (e) {
      debugPrint(
          '════════════════════════════════════════════════════════════');
      debugPrint('❌ 摆球摘要上傳異常: $e');
      debugPrint(
          '════════════════════════════════════════════════════════════');
      return {
        'success': false,
        'error': 'Upload error: $e',
      };
    }
  }

  /// 取得所有視頻列表
  ///
  /// [userId]: 用戶 ID
  /// [status]: 篩選狀態（可選），多個用逗號分隔
  /// [page]: 分頁號（預設 1）
  /// [limit]: 每頁數量（預設 10）
  Future<Map<String, dynamic>> getVideos({
    String? status,
    int page = 1,
    int limit = 10,
  }) async {
    try {
      var url = Uri.parse('$_baseUrl/api/videos').replace(queryParameters: {
        'page': page.toString(),
        'limit': limit.toString(),
        if (status != null) 'status': status,
      });

      final headers = await _getAuthHeaders();
      final response = await http.get(url, headers: headers);

      if (response.statusCode == 200) {
        return {
          'success': true,
          'data': jsonDecode(response.body),
        };
      } else {
        return {
          'success': false,
          'error': 'Failed to fetch videos: ${response.statusCode}',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'error': 'Network error: $e',
      };
    }
  }

  /// 取得單個視頻的詳細狀態
  ///
  /// [videoId]: 視頻 ID
  Future<Map<String, dynamic>> getVideoStatus(int videoId) async {
    try {
      final url = Uri.parse('$_baseUrl/api/videos/$videoId/status');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        return {
          'success': true,
          'data': jsonDecode(response.body),
        };
      } else {
        return {
          'success': false,
          'error': 'Failed to fetch video status: ${response.statusCode}',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'error': 'Network error: $e',
      };
    }
  }

  /// 取得單個視頻的詳細信息（包括隊列狀態）
  /// 用於視頻細項頁面顯示云端視頻的詳細信息
  ///
  /// [videoId]: 視頻 ID（云端視頻 ID）
  Future<Map<String, dynamic>> getVideoDetail(String videoId) async {
    try {
      final url = Uri.parse('$_baseUrl/api/videos/$videoId');
      final headers = await _getAuthHeaders();

      debugPrint('📋 取得視頻詳情: $videoId');

      final response = await http.get(
        url,
        headers: headers,
      );

      debugPrint('📥 Response Status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        debugPrint('✅ 視頻詳情取得成功');
        return {
          'success': true,
          'data': result,
        };
      } else {
        debugPrint('❌ 取得視頻詳情失敗: ${response.statusCode}');
        return {
          'success': false,
          'error': 'Failed to fetch video detail: ${response.statusCode}',
          'body': response.body,
        };
      }
    } catch (e) {
      debugPrint('❌ 取得視頻詳情異常: $e');
      return {
        'success': false,
        'error': 'Network error: $e',
      };
    }
  }

  /// 建立新視頻紀錄
  ///
  /// [name]: 視頻名稱
  /// [type]: 視頻類型 (original 或 clip)
  /// [parentVideoId]: 父視頻 ID（若為切片時使用）
  /// [hitSecond]: 擊球時刻（秒數）
  /// [startSecond]: 切片開始秒數
  /// [endSecond]: 切片結束秒數
  Future<Map<String, dynamic>> createVideo({
    required String name,
    required String type,
    String? parentVideoId,
    double? hitSecond,
    double? startSecond,
    double? endSecond,
    double? peakValue,
    bool? goodShot,
    double? audioCrispness,
    Map<String, double>? rawPeakValues,
  }) async {
    try {
      final url = Uri.parse('$_baseUrl/api/videos');
      final headers = await _getAuthHeaders();

      debugPrint('📝 建立視頻紀錄: $name (type: $type)');

      final response = await http.post(
        url,
        headers: headers,
        body: jsonEncode({
          'name': name,
          'type': type,
          if (parentVideoId != null) 'parentVideoId': parentVideoId,
          if (hitSecond != null) 'hitSecond': hitSecond,
          if (startSecond != null) 'startSecond': startSecond,
          if (endSecond != null) 'endSecond': endSecond,
          if (peakValue != null) 'peakValue': peakValue,
          if (goodShot != null) 'goodShot': goodShot,
          if (audioCrispness != null) 'audioCrispness': audioCrispness,
        }),
      );

      debugPrint('📥 建立回應狀態: ${response.statusCode}');
      debugPrint('📝 回應: ${response.body}');

      if (response.statusCode == 201 || response.statusCode == 200) {
        return {
          'success': true,
          'data': jsonDecode(response.body),
        };
      } else {
        return {
          'success': false,
          'error': 'Failed to create video: ${response.statusCode}',
          'body': response.body,
        };
      }
    } catch (e) {
      debugPrint('❌ 建立視頻失敗: $e');
      return {
        'success': false,
        'error': 'Network error: $e',
      };
    }
  }

  /// 標記影片上傳完成
  /// 當所有檔案上傳完成後調用此方法
  ///
  /// [videoId]: 伺服器上的視頻 ID (UUID)
  Future<Map<String, dynamic>> markVideoUploadComplete({
    required String videoId,
  }) async {
    try {
      final url = Uri.parse('$_baseUrl/api/videos/$videoId/complete');
      final headers = await _getAuthHeaders();

      debugPrint('════════════════════════════════════════════════════════════');
      debugPrint('✅ 標記影片上傳完成');
      debugPrint('════════════════════════════════════════════════════════════');
      debugPrint('🎯 目標視頻 ID: $videoId');
      debugPrint('🔗 API 端點: $_baseUrl/api/videos/$videoId/complete');

      final response = await http.post(
        url,
        headers: headers,
      );

      debugPrint('📥 回應狀態: ${response.statusCode}');
      debugPrint('📝 回應: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        return {
          'success': true,
          'data': jsonDecode(response.body),
        };
      } else {
        return {
          'success': false,
          'error': 'Failed to mark video as complete: ${response.statusCode}',
          'body': response.body,
        };
      }
    } catch (e) {
      debugPrint('❌ 標記完成失敗: $e');
      return {
        'success': false,
        'error': 'Network error: $e',
      };
    }
  }

  /// 重試失敗的切片
  ///
  /// [sliceId]: 伺服器上的切片 ID
  Future<Map<String, dynamic>> retrySlice(int sliceId) async {
    try {
      final url = Uri.parse('$_baseUrl/api/slices/$sliceId/retry');
      final response = await http.post(url);

      if (response.statusCode == 200) {
        return {
          'success': true,
          'data': jsonDecode(response.body),
        };
      } else {
        return {
          'success': false,
          'error': 'Failed to retry slice: ${response.statusCode}',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'error': 'Network error: $e',
      };
    }
  }

  /// 下載切片處理結果
  ///
  /// [sliceId]: 伺服器上的切片 ID
  /// [outputFileName]: 輸出檔案名稱
  Future<String> downloadSliceResult(int sliceId, String outputFileName) async {
    try {
      final url = Uri.parse(
        '$_baseUrl/api/slices/$sliceId/download/$outputFileName',
      );
      // 返回下載 URL，由前端決定如何處理（下載或預覽）
      return url.toString();
    } catch (e) {
      throw Exception('Error generating download URL: $e');
    }
  }

  /// 重新分析影片 (Re-run Analysis)
  ///
  /// [videoId]: 影片 ID
  /// 邏輯：
  ///   1. 檢查該影片是否已經在隊列中 + status = "ready"
  ///   2. 如果有 → 重用現有隊列項目（改為 "queued"）
  ///   3. 如果沒有 → 創建新的隊列項目
  Future<Map<String, dynamic>> rerunAnalysis(String videoId) async {
    try {
      final url = Uri.parse('$_baseUrl/api/videos/$videoId/rerun-analysis');
      final headers = await _getAuthHeaders();

      debugPrint('════════════════════════════════════════');
      debugPrint('🔄 重新分析影片 (Re-run Analysis)');
      debugPrint('════════════════════════════════════════');
      debugPrint('📍 URL: $url');
      debugPrint('🎯 VideoId: $videoId');

      final response = await http.post(
        url,
        headers: headers,
      );

      debugPrint('📥 Response Status: ${response.statusCode}');
      debugPrint('📝 Response: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final result = jsonDecode(response.body);
        debugPrint('✅ 重新分析已排隊');
        return {
          'success': true,
          'data': result,
        };
      } else {
        final errorJson = jsonDecode(response.body);
        debugPrint('❌ 重新分析失敗: ${response.statusCode}');
        return {
          'success': false,
          'error': errorJson['error'] ?? 'Failed to rerun analysis: ${response.statusCode}',
          'body': response.body,
        };
      }
    } catch (e) {
      debugPrint('❌ 重新分析異常: $e');
      return {
        'success': false,
        'error': 'Network error: $e',
      };
    }
  }

  /// 解除雲端綁定
  ///
  /// [videoId]: 影片 ID
  /// 返回是否成功解除綁定
  Future<bool> unbindVideo(String videoId) async {
    try {
      final headers = await _getAuthHeaders();
      final url = Uri.parse('$_baseUrl/api/videos/$videoId/unbind');
      
      debugPrint('════════════════════════════════════════');
      debugPrint('🔓 解除雲端綁定');
      debugPrint('════════════════════════════════════════');
      debugPrint('📍 URL: $url');
      debugPrint('🎯 VideoId: $videoId');

      final response = await http.post(
        url,
        headers: headers,
      );

      debugPrint('📥 Response Status: ${response.statusCode}');
      debugPrint('📝 Response: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final result = jsonDecode(response.body);
        debugPrint('✅ 影片已解除雲端綁定');
        return result['success'] ?? true;
      } else {
        debugPrint('❌ 解除綁定失敗: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      debugPrint('❌ 解除綁定異常: $e');
      return false;
    }
  }

  /// 標記雲端影片為刪除（切片視頻刪除時使用）
  ///
  /// [videoId]: 影片 ID
  /// 返回是否成功標記為刪除
  Future<bool> markVideoAsDeleted(String videoId) async {
    try {
      final headers = await _getAuthHeaders();
      final url = Uri.parse('$_baseUrl/api/videos/$videoId/delete');
      
      debugPrint('════════════════════════════════════════');
      debugPrint('🗑️ 標記影片為刪除');
      debugPrint('════════════════════════════════════════');
      debugPrint('📍 URL: $url');
      debugPrint('🎯 VideoId: $videoId');

      final response = await http.post(
        url,
        headers: headers,
      );

      debugPrint('📥 Response Status: ${response.statusCode}');
      debugPrint('📝 Response: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final result = jsonDecode(response.body);
        debugPrint('✅ 影片已標記為刪除');
        return result['success'] ?? true;
      } else {
        debugPrint('❌ 標記刪除失敗: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      debugPrint('❌ 標記刪除異常: $e');
      return false;
    }
  }

  /// 獲取影片的流式傳輸 URL（用於在線播放）
  ///
  /// [videoId]: 影片 ID
  /// 返回可以直接用於視頻播放的 URL
  /// 如果提供了 token，會將其作為查詢參數添加
  Future<String> getVideoStreamUrl(String videoId, {String? token}) async {
    // 如果沒有提供 token，則嘗試從儲存中獲取
    token ??= await AuthTokenStorage.instance.getAccessToken();
    
    if (token != null && token.isNotEmpty) {
      return '$_baseUrl/api/videos/$videoId/stream?token=$token';
    }
    
    // 如果沒有 token，返回不帶 token 的 URL（會導致 401）
    return '$_baseUrl/api/videos/$videoId/stream';
  }

  /// 更新雲端影片的名稱
  ///
  /// [videoId]: 影片 ID
  /// [newName]: 新的影片名稱
  /// 返回是否成功更新
  Future<bool> updateVideoName(String videoId, String newName) async {
    try {
      final headers = await _getAuthHeaders();
      final url = Uri.parse('$_baseUrl/api/videos/$videoId');
      
      debugPrint('════════════════════════════════════════');
      debugPrint('📝 更新影片名稱');
      debugPrint('════════════════════════════════════════');
      debugPrint('📍 URL: $url');
      debugPrint('🎯 VideoId: $videoId');
      debugPrint('📛 新名稱: $newName');

      final body = jsonEncode({
        'name': newName,
      });

      final response = await http.put(
        url,
        headers: {...headers, 'Content-Type': 'application/json'},
        body: body,
      );

      debugPrint('📥 Response Status: ${response.statusCode}');
      debugPrint('📝 Response: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final result = jsonDecode(response.body);
        debugPrint('✅ 影片名稱已更新');
        return result['success'] ?? true;
      } else {
        debugPrint('❌ 更新名稱失敗: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      debugPrint('❌ 更新名稱異常: $e');
      return false;
    }
  }

  // ============================================================
  // 統計數據方法
  // ============================================================

  /// 獲取統計數據
  /// period: all（全部）、today（今天）、yesterday（昨天）、tomorrow（明天）、date（指定日期）
  /// date: 當 period 為 date 時，指定日期（格式：2026-02-06）
  /// 
  /// 如果遇到 401 錯誤，會自動嘗試刷新 Token 並重試一次
  Future<StatisticsResponse?> getStatistics({
    required String period,
    String? date,
    bool isRetry = false,
  }) async {
    try {
      final headers = await _getAuthHeaders();
      
      var url = Uri.parse('$_baseUrl/api/statistics').replace(
        queryParameters: {
          'period': period,
          if (date != null) 'date': date,
        },
      );

      debugPrint('════════════════════════════════════════');
      debugPrint('📊 獲取統計數據');
      debugPrint('════════════════════════════════════════');
      debugPrint('📍 URL: $url');
      debugPrint('Period: $period' + (date != null ? ', Date: $date' : ''));

      final response = await http.get(url, headers: headers);

      debugPrint('📥 Response Status: ${response.statusCode}');
      debugPrint('📝 Response: ${response.body}');

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final statistics = StatisticsResponse.fromJson(json);
        debugPrint('✅ 統計數據獲取成功');
        debugPrint('📊 數據: $statistics');
        return statistics;
      } else if (response.statusCode == 401) {
        debugPrint('⚠️ 統計數據獲取失敗: ${response.statusCode} - 未授權');
        
        // 如果不是重試，嘗試刷新 Token 並重試
        if (!isRetry) {
          debugPrint('🔄 嘗試刷新 Token 並重試...');
          final refreshSuccess = await _tryRefreshToken();
          if (refreshSuccess) {
            debugPrint('✅ Token 刷新成功，重新獲取統計數據...');
            return getStatistics(period: period, date: date, isRetry: true);
          }
        }
        
        debugPrint('❌ Token 刷新失敗或重試後仍失敗，拋出未授權異常');
        throw UnauthorizedException('統計數據獲取失敗: ${response.statusCode}');
      } else {
        debugPrint('❌ 統計數據獲取失敗: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      if (e is UnauthorizedException) {
        rethrow; // 重新拋出授權異常
      }
      debugPrint('❌ 統計數據異常: $e');
      return null;
    }
  }
}
