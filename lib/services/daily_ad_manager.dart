import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

/// 每日廣告管理服務 - 記錄用戶今天是否已看過一次廣告
/// 
/// 邏輯：
/// 1. 用戶看完廣告 → 進入錄影 → 記錄"已使用一次廣告"
/// 2. 同一天內，再按錄影按鈕時 → 不彈窗，直接進入錄影
/// 3. 用戶中途離開 (回到首頁) → 保留此次機會（不重置）
/// 4. 隔天 → 重置，又可以看一次廣告
class DailyAdManager {
  static const String _adWatchedDateKey = 'daily_ad_watched_date';
  static const String _adUsedTodayKey = 'daily_ad_used_today';

  late SharedPreferences _prefs;

  /// 初始化
  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    _checkAndResetDaily();
  }

  /// 檢查是否需要重置每日廣告機會（如果是新的一天）
  void _checkAndResetDaily() {
    final lastDate = _prefs.getString(_adWatchedDateKey);
    final today = _getTodayDateString();

    if (lastDate != today) {
      // 是新的一天，重置廣告使用狀態
      _prefs.setString(_adWatchedDateKey, today);
      _prefs.setBool(_adUsedTodayKey, false);
      debugPrint('🗓️ [廣告] 新的一天，已重置廣告使用狀態');
    }
  }

  /// 檢查用戶今天是否已使用過一次廣告機會
  Future<bool> hasUsedAdToday() async {
    _checkAndResetDaily();
    return _prefs.getBool(_adUsedTodayKey) ?? false;
  }

  /// 標記用戶已使用廣告（看完廣告並進入錄影）
  Future<void> markAdAsUsed() async {
    await _prefs.setBool(_adUsedTodayKey, true);
    debugPrint('✅ [廣告] 已標記用戶使用了今天的廣告機會');
  }

  /// 重置廣告使用狀態（用於測試）
  Future<void> resetAdUsage() async {
    await _prefs.setBool(_adUsedTodayKey, false);
    debugPrint('🔄 [廣告] 已重置廣告使用狀態（測試用）');
  }

  /// 取得今天的日期字符串 (YYYY-MM-DD)
  String _getTodayDateString() {
    return DateTime.now().toString().split(' ')[0];
  }

  /// 取得剩餘次數 (0 或 1)
  Future<int> getRemainingAdOpportunities() async {
    final used = await hasUsedAdToday();
    return used ? 0 : 1;
  }
}
