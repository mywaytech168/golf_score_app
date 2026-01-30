import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'auth_token_storage.dart';

/// 伺服器 API 客戶端
class VideoServerClient {
  static const String _baseUrl = 'https://tekswing.api.atk.tw';

  static final VideoServerClient _instance = VideoServerClient._internal();

  factory VideoServerClient() {
    return _instance;
  }

  VideoServerClient._internal();

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
  Future<Map<String, dynamic>> uploadVideoFile({
    required String videoId,
    required String videoFilePath,
    required String fileType,
    String? sourceLocalFilePath,
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

  /// 取得所有視頻列表
  ///
  /// [userId]: 用戶 ID
  /// [status]: 篩選狀態（可選），多個用逗號分隔
  /// [page]: 分頁號（預設 1）
  /// [limit]: 每頁數量（預設 10）
  Future<Map<String, dynamic>> getVideos({
    required int userId,
    String? status,
    int page = 1,
    int limit = 10,
  }) async {
    try {
      var url = Uri.parse('$_baseUrl/api/videos').replace(queryParameters: {
        'user_id': userId.toString(),
        'page': page.toString(),
        'limit': limit.toString(),
        if (status != null) 'status': status,
      });

      final response = await http.get(url);

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

  /// 建立新視頻紀錄
  ///
  /// [name]: 視頻名稱
  /// [type]: 視頻類型 (original 或 clip)
  /// [parentVideoId]: 父視頻 ID（若為切片時使用）
  Future<Map<String, dynamic>> createVideo({
    required String name,
    required String type,
    String? parentVideoId,
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
}
