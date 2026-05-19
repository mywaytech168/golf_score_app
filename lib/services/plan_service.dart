import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'recording_history_storage.dart';

// ────────────────────────────────────────────────────────────────
// 方案定義
// ────────────────────────────────────────────────────────────────

enum UserPlan { free, pro, elite }

extension UserPlanX on UserPlan {
  String get label {
    switch (this) {
      case UserPlan.free:  return 'Free';
      case UserPlan.pro:   return 'Pro';
      case UserPlan.elite: return 'Elite';
    }
  }

  /// 每日球數上限；-1 代表無限制
  int get dailyLimit {
    switch (this) {
      case UserPlan.free:  return 10;
      case UserPlan.pro:   return 90;
      case UserPlan.elite: return -1;
    }
  }

  bool get isUnlimited => dailyLimit == -1;

  /// 用於 SharedPreferences 的儲存字串
  String get key {
    switch (this) {
      case UserPlan.free:  return 'free';
      case UserPlan.pro:   return 'pro';
      case UserPlan.elite: return 'elite';
    }
  }

  /// 顯示顏色（十六進制整數）
  int get colorValue {
    switch (this) {
      case UserPlan.free:  return 0xFF78909C;
      case UserPlan.pro:   return 0xFF1E8E5A;
      case UserPlan.elite: return 0xFFB8860B;
    }
  }
}

// ────────────────────────────────────────────────────────────────
// PlanService
// ────────────────────────────────────────────────────────────────

class PlanService {
  PlanService._();

  static const _prefKey = 'user_plan';

  // ── 方案讀寫 ──────────────────────────────────────────────────

  /// 取得目前方案（預設 Free）
  static Future<UserPlan> getCurrentPlan() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefKey) ?? 'free';
      return UserPlan.values.firstWhere(
        (p) => p.key == raw,
        orElse: () => UserPlan.free,
      );
    } catch (e) {
      debugPrint('[PlanService] 讀取方案失敗: $e');
      return UserPlan.free;
    }
  }

  /// 儲存方案
  static Future<void> setPlan(UserPlan plan) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, plan.key);
      debugPrint('[PlanService] 方案已更新: ${plan.label}');
    } catch (e) {
      debugPrint('[PlanService] 儲存方案失敗: $e');
    }
  }

  // ── 今日用量 ──────────────────────────────────────────────────

  /// 今日已使用球數（= 今天的錄影片段數）
  static Future<int> getTodayUsedBalls() async {
    try {
      final all = await RecordingHistoryStorage.instance.loadHistory();
      final now = DateTime.now();
      return all
          .where((e) =>
              e.recordedAt.year  == now.year &&
              e.recordedAt.month == now.month &&
              e.recordedAt.day   == now.day)
          .length;
    } catch (e) {
      debugPrint('[PlanService] 取得今日用量失敗: $e');
      return 0;
    }
  }

  // ── 綜合查詢 ──────────────────────────────────────────────────

  /// 同時取得方案與今日用量
  static Future<({UserPlan plan, int used})> getPlanStatus() async {
    final plan = await getCurrentPlan();
    final used = await getTodayUsedBalls();
    return (plan: plan, used: used);
  }
}
