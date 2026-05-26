import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import '../services/auth_token_storage.dart';

/// 認證狀態提供者
/// 
/// 管理用戶登入/登出狀態、令牌和用戶信息
class AuthProvider with ChangeNotifier {
  final AuthTokenStorage _tokenStorage = AuthTokenStorage.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  // 狀態變數
  bool _isLoading = false;
  String? _accessToken;
  String? _userId;
  String? _userEmail;
  String? _errorMessage;
  bool _isLoggedIn = false;

  // Getters
  bool get isLoading => _isLoading;
  String? get accessToken => _accessToken;
  String? get userId => _userId;
  String? get userEmail => _userEmail;
  String? get errorMessage => _errorMessage;
  bool get isLoggedIn => _isLoggedIn;

  /// 初始化認證狀態（在應用啟動時調用）
  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();

    try {
      _isLoggedIn = await _tokenStorage.isLoggedIn();
      if (_isLoggedIn) {
        _accessToken = await _tokenStorage.getAccessToken();
        _userId = await _tokenStorage.getUserId();
        _userEmail = await _tokenStorage.getUserEmail();
      }
      _errorMessage = null;
    } catch (e) {
      _errorMessage = '初始化認證失敗: $e';
      debugPrint(_errorMessage);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 使用 Google 登入（向後端驗證後取得 JWT）
  Future<bool> signInWithGoogle() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        _isLoggedIn = false;
        notifyListeners();
        return false;
      }

      final googleAuth = await googleUser.authentication;
      final idToken = googleAuth.idToken;
      if (idToken == null) {
        throw Exception('無法取得 Google IdToken');
      }

      // 送後端驗證，取得 JWT
      final response = await http.post(
        Uri.parse('https://tekswing.api.atk.tw/api/auth/google-login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'idToken': idToken,
          'email': googleUser.email,
          'displayName': googleUser.displayName,
          'avatarUrl': googleUser.photoUrl,
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        throw Exception(body['message'] ?? 'Google 登入失敗: ${response.statusCode}');
      }

      final result = jsonDecode(response.body) as Map<String, dynamic>;
      final token = result['token'] as String?;
      if (token == null || token.isEmpty) {
        throw Exception('後端未返回認證令牌');
      }

      final user = result['user'] as Map<String, dynamic>?;
      await _tokenStorage.saveTokens(
        accessToken: token,
        refreshToken: result['refreshToken'] as String?,
        userId: user?['id']?.toString() ?? googleUser.id,
        userEmail: user?['email'] as String? ?? googleUser.email,
      );

      _accessToken = token;
      _userId = user?['id']?.toString() ?? googleUser.id;
      _userEmail = user?['email'] as String? ?? googleUser.email;
      _isLoggedIn = true;
      _errorMessage = null;
      return true;
    } catch (e) {
      _errorMessage = 'Google 登入失敗: $e';
      debugPrint(_errorMessage);
      _isLoggedIn = false;
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 登出
  Future<void> signOut() async {
    _isLoading = true;
    notifyListeners();

    try {
      await _tokenStorage.clearTokens();
      await _googleSignIn.signOut();

      _accessToken = null;
      _userId = null;
      _userEmail = null;
      _isLoggedIn = false;
      _errorMessage = null;
    } catch (e) {
      _errorMessage = '登出失敗: $e';
      debugPrint(_errorMessage);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 刷新令牌
  Future<bool> refreshToken() async {
    try {
      final success = await _tokenStorage.tryRefreshToken();
      if (success) {
        _accessToken = await _tokenStorage.getAccessToken();
        notifyListeners();
      } else {
        await signOut();
      }
      return success;
    } catch (e) {
      _errorMessage = '令牌刷新失敗: $e';
      debugPrint(_errorMessage);
      return false;
    }
  }

}
