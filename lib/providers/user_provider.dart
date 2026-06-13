import 'package:flutter/foundation.dart';
import '../services/user_profile_storage.dart';
import '../services/video_server_client.dart';

/// 使用者資料提供者
/// 
/// 管理用戶個人信息（暱稱、頭像等）
class UserProvider with ChangeNotifier {
  final UserProfileStorage _profileStorage = UserProfileStorage.instance;

  // 狀態變數
  bool _isLoading = false;
  String? _displayName;
  String? _avatarPath;
  String? _errorMessage;

  // 預設暱稱
  static const String _defaultDisplayName = 'Golf Player';

  // Getters
  bool get isLoading => _isLoading;
  String get displayName => _displayName ?? _defaultDisplayName;
  String? get avatarPath => _avatarPath;
  String? get errorMessage => _errorMessage;

  /// 載入使用者資料
  Future<void> loadProfile() async {
    _isLoading = true;
    notifyListeners();

    try {
      final profile = await _profileStorage.loadProfile(
        defaultDisplayName: _defaultDisplayName,
      );
      _displayName = profile.displayName;
      _avatarPath = profile.avatarPath;

      // 本機沒有自訂暱稱（仍是預設/空）→ 從伺服器帳號抓真實名稱並持久化
      final stillDefault = _displayName == null ||
          _displayName!.trim().isEmpty ||
          _displayName == _defaultDisplayName;
      if (stillDefault) {
        final serverName = await _fetchServerName();
        if (serverName != null && serverName.isNotEmpty) {
          _displayName = serverName;
          await _profileStorage.saveProfile(
            displayName: serverName,
            avatarPath: _avatarPath,
          );
        }
      }
      _errorMessage = null;
    } catch (e) {
      _errorMessage = '載入使用者資料失敗: $e';
      debugPrint(_errorMessage);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 從伺服器帳號取顯示名稱：displayName → username → email 前綴。
  Future<String?> _fetchServerName() async {
    try {
      final me = await VideoServerClient.instance.getMe();
      if (me == null) return null;
      final dn = (me['displayName'] as String?)?.trim();
      if (dn != null && dn.isNotEmpty) return dn;
      final un = (me['username'] as String?)?.trim();
      if (un != null && un.isNotEmpty) return un;
      final email = (me['email'] as String?)?.trim();
      if (email != null && email.contains('@')) return email.split('@').first;
      return null;
    } catch (e) {
      debugPrint('[UserProvider] 取伺服器名稱失敗: $e');
      return null;
    }
  }

  /// 更新暱稱
  Future<void> updateDisplayName(String newName) async {
    if (newName.trim().isEmpty) {
      _errorMessage = '暱稱不能為空';
      notifyListeners();
      return;
    }

    try {
      await _profileStorage.saveProfile(
        displayName: newName,
        avatarPath: _avatarPath,
      );
      _displayName = newName;
      _errorMessage = null;
      notifyListeners();
    } catch (e) {
      _errorMessage = '更新暱稱失敗: $e';
      debugPrint(_errorMessage);
      notifyListeners();
    }
  }

  /// 更新頭像
  Future<void> updateAvatar(String? newAvatarPath) async {
    try {
      await _profileStorage.saveProfile(
        displayName: _displayName ?? _defaultDisplayName,
        avatarPath: newAvatarPath,
      );
      _avatarPath = newAvatarPath;
      _errorMessage = null;
      notifyListeners();
    } catch (e) {
      _errorMessage = '更新頭像失敗: $e';
      debugPrint(_errorMessage);
      notifyListeners();
    }
  }

  /// 清除錯誤訊息
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}
