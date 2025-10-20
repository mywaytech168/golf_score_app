import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

/// 使用者個資儲存資料結構，統一傳遞暱稱與頭像路徑
class UserProfileData {
  final String displayName; // 顯示名稱（暱稱）
  final String? avatarPath; // 頭像檔案路徑，若為空代表使用預設圖示

  const UserProfileData({
    required this.displayName,
    required this.avatarPath,
  });
}

/// 本地偏好儲存工具，專責維護使用者暱稱與頭像資訊
class UserProfileStorage {
  static const String _displayNameKey = 'user_profile_display_name'; // 偏好儲存用 key：暱稱
  static const String _avatarPathKey = 'user_profile_avatar_path'; // 偏好儲存用 key：頭像路徑

  UserProfileStorage._();

  static final UserProfileStorage instance = UserProfileStorage._(); // 單例實體，避免重複建立

  /// 載入使用者個資，若尚未設定則回傳傳入的預設暱稱
  Future<UserProfileData> loadProfile({required String defaultDisplayName}) async {
    final prefs = await SharedPreferences.getInstance();

    // ---------- 暱稱還原 ----------
    final storedName = prefs.getString(_displayNameKey)?.trim();
    final resolvedName = (storedName != null && storedName.isNotEmpty)
        ? storedName
        : defaultDisplayName; // 未儲存時沿用預設值

    // ---------- 頭像路徑檢查 ----------
    final storedAvatar = prefs.getString(_avatarPathKey);
    String? resolvedAvatar;
    if (storedAvatar != null && storedAvatar.isNotEmpty) {
      final avatarFile = File(storedAvatar);
      if (await avatarFile.exists()) {
        resolvedAvatar = storedAvatar; // 確認檔案存在才回傳路徑
      } else {
        await prefs.remove(_avatarPathKey); // 若檔案已遺失則清除紀錄避免指向無效路徑
      }
    }

    return UserProfileData(displayName: resolvedName, avatarPath: resolvedAvatar);
  }

  /// 儲存最新的暱稱與頭像設定，若頭像為空則移除偏好值
  Future<void> saveProfile({required String displayName, String? avatarPath}) async {
    final prefs = await SharedPreferences.getInstance();

    // ---------- 暱稱保存 ----------
    await prefs.setString(_displayNameKey, displayName.trim());

    // ---------- 頭像保存 ----------
    if (avatarPath == null || avatarPath.isEmpty) {
      await prefs.remove(_avatarPathKey); // 無頭像時直接移除設定
    } else {
      await prefs.setString(_avatarPathKey, avatarPath);
    }
  }
}
