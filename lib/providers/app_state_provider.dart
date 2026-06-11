import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:shared_preferences/shared_preferences.dart';

/// 應用全局狀態提供者
/// 
/// 管理應用級別的狀態（主題、語言、通知設置等）
class AppStateProvider with ChangeNotifier {
  static const _kThemeMode = 'theme_mode';

  AppStateProvider() {
    _loadThemeMode();
  }

  // 主題和語言設置
  ThemeMode _themeMode = ThemeMode.system;
  String _languageCode = 'zh'; // 'zh' 或 'en'
  bool _notificationsEnabled = true;
  bool _analyticsEnabled = true;

  // 用戶偏好設置
  bool _highQualityVideo = true;
  int _defaultRecordingDuration = 60; // 秒
  bool _autoUploadEnabled = false;
  bool _showTips = true;

  // 應用狀態
  bool _isOnline = true;
  String? _appVersion;
  bool _updateAvailable = false;

  // Getters
  ThemeMode get themeMode => _themeMode;
  String get languageCode => _languageCode;
  bool get notificationsEnabled => _notificationsEnabled;
  bool get analyticsEnabled => _analyticsEnabled;
  bool get highQualityVideo => _highQualityVideo;
  int get defaultRecordingDuration => _defaultRecordingDuration;
  bool get autoUploadEnabled => _autoUploadEnabled;
  bool get showTips => _showTips;
  bool get isOnline => _isOnline;
  String? get appVersion => _appVersion;
  bool get updateAvailable => _updateAvailable;

  /// 設置主題模式
  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    notifyListeners();
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setString(_kThemeMode, mode.name));
  }

  Future<void> _loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kThemeMode);
    if (saved == null) return;
    _themeMode = ThemeMode.values.firstWhere(
      (m) => m.name == saved,
      orElse: () => ThemeMode.system,
    );
    notifyListeners();
  }

  /// 設置語言
  void setLanguage(String code) {
    if (code != _languageCode) {
      _languageCode = code;
      notifyListeners();
    }
  }

  /// 切換通知設置
  void toggleNotifications(bool enabled) {
    _notificationsEnabled = enabled;
    notifyListeners();
  }

  /// 切換分析設置
  void toggleAnalytics(bool enabled) {
    _analyticsEnabled = enabled;
    notifyListeners();
  }

  /// 設置視頻質量
  void setHighQualityVideo(bool enabled) {
    _highQualityVideo = enabled;
    notifyListeners();
  }

  /// 設置默認錄制時長
  void setDefaultRecordingDuration(int seconds) {
    if (seconds > 0) {
      _defaultRecordingDuration = seconds;
      notifyListeners();
    }
  }

  /// 切換自動上傳
  void toggleAutoUpload(bool enabled) {
    _autoUploadEnabled = enabled;
    notifyListeners();
  }

  /// 切換提示顯示
  void toggleShowTips(bool enabled) {
    _showTips = enabled;
    notifyListeners();
  }

  /// 設置在線狀態
  void setOnlineStatus(bool online) {
    _isOnline = online;
    notifyListeners();
  }

  /// 設置應用版本
  void setAppVersion(String version) {
    _appVersion = version;
    notifyListeners();
  }

  /// 提示有更新可用
  void setUpdateAvailable(bool available) {
    _updateAvailable = available;
    notifyListeners();
  }

  /// 重置為默認設置
  void resetToDefaults() {
    _themeMode = ThemeMode.system;
    _languageCode = 'zh';
    _notificationsEnabled = true;
    _analyticsEnabled = true;
    _highQualityVideo = true;
    _defaultRecordingDuration = 60;
    _autoUploadEnabled = false;
    _showTips = true;
    notifyListeners();
  }

  /// 獲取當前設置摘要
  Map<String, dynamic> getSettingsSummary() {
    return {
      'themeMode': _themeMode.toString(),
      'language': _languageCode,
      'notificationsEnabled': _notificationsEnabled,
      'analyticsEnabled': _analyticsEnabled,
      'highQualityVideo': _highQualityVideo,
      'defaultRecordingDuration': _defaultRecordingDuration,
      'autoUploadEnabled': _autoUploadEnabled,
      'showTips': _showTips,
      'isOnline': _isOnline,
      'appVersion': _appVersion,
      'updateAvailable': _updateAvailable,
    };
  }
}
