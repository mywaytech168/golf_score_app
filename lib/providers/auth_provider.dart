import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
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

  /// 使用 Google 登入
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
      final accessToken = googleAuth.accessToken;

      if (accessToken == null) {
        throw Exception('無法獲取 Google 令牌');
      }

      // 保存令牌
      await _tokenStorage.saveTokens(
        accessToken: accessToken,
        refreshToken: googleAuth.idToken,
        userId: googleUser.id,
        userEmail: googleUser.email,
      );

      // 更新狀態
      _accessToken = accessToken;
      _userId = googleUser.id;
      _userEmail = googleUser.email;
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
      final refreshToken = await _tokenStorage.getRefreshToken();
      if (refreshToken == null) {
        await signOut();
        return false;
      }

      // 在實際應用中，這裡應該調用後端 API 刷新令牌
      // 此處簡化處理，假設刷新成功
      return true;
    } catch (e) {
      _errorMessage = '令牌刷新失敗: $e';
      debugPrint(_errorMessage);
      return false;
    }
  }

  @override
  void dispose() {
    super.dispose();
  }
}
