import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'video_server_client.dart';

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

  /// SharedPreferences / API 使用的字串 key
  String get key {
    switch (this) {
      case UserPlan.free:  return 'free';
      case UserPlan.pro:   return 'pro';
      case UserPlan.elite: return 'elite';
    }
  }

  /// 顯示色值（ARGB int）
  int get colorValue {
    switch (this) {
      case UserPlan.free:  return 0xFF78909C;
      case UserPlan.pro:   return 0xFF1E8E5A;
      case UserPlan.elite: return 0xFFB8860B;
    }
  }

  static UserPlan fromKey(String? key) => UserPlan.values.firstWhere(
    (p) => p.key == key,
    orElse: () => UserPlan.free,
  );
}

// ────────────────────────────────────────────────────────────────
// 方案狀態資料類別
// ────────────────────────────────────────────────────────────────

class PlanStatus {
  final UserPlan plan;
  final int todayUsed;
  final int dailyLimit;   // -1 = 無限制
  final int bonusBalls;   // 額外獎勵球數（看廣告、邀請、回饋、上傳）
  final bool fromCache;   // true = 後端不可用，來自本地 cache

  const PlanStatus({
    required this.plan,
    required this.todayUsed,
    required this.dailyLimit,
    this.bonusBalls = 0,
    this.fromCache = false,
  });

  /// 今日總上限（方案球數 + 獎勵球數）；-1 = 無限制
  int get totalLimit => dailyLimit < 0 ? -1 : dailyLimit + bonusBalls;

  /// 今日剩餘球數；-1 = 無限制
  int get remaining =>
      totalLimit < 0 ? -1 : (totalLimit - todayUsed).clamp(0, totalLimit);
}

// ────────────────────────────────────────────────────────────────
// PlanService
// ────────────────────────────────────────────────────────────────

/// 方案管理服務
///
/// 主要資料來源：後端 API `/api/user/plan`（資料庫）
/// 備援 cache  ：SharedPreferences（離線 / 後端失敗時，球數顯示為 0）
class PlanService {
  PlanService._();

  static const _prefKey = 'user_plan_cache';
  static const _tag = '[PlanService]';

  // ── 取得方案狀態 ──────────────────────────────────────────────

  /// 從後端取得方案與今日用量；後端不可用時回退本地 cache
  static Future<PlanStatus> getPlanStatus() async {
    try {
      final data = await VideoServerClient.instance.getPlanStatus();
      if (data != null) {
        final plan       = UserPlanX.fromKey(data['plan'] as String?);
        final todayUsed  = (data['todayUsed']  as int?) ?? 0;
        final limit      = (data['dailyLimit'] as int?) ?? plan.dailyLimit;
        final bonusBalls = (data['bonusBalls'] as int?) ?? 0;

        // 同步本地 cache
        await _writeCachedPlan(plan);

        debugPrint('$_tag ✅ 後端: ${plan.label} used=$todayUsed limit=$limit bonus=$bonusBalls');
        return PlanStatus(
          plan: plan,
          todayUsed: todayUsed,
          dailyLimit: limit,
          bonusBalls: bonusBalls,
        );
      }
    } on UnauthorizedException {
      rethrow;
    } catch (e) {
      debugPrint('$_tag ⚠️ 後端不可用，使用 cache: $e');
    }

    // 後端失敗 → 讀本地 cache；球數未知，設 0
    final cached = await _readCachedPlan();
    debugPrint('$_tag 📦 cache: ${cached.label}');
    return PlanStatus(
      plan: cached,
      todayUsed: 0,
      dailyLimit: cached.dailyLimit,
      fromCache: true,
    );
  }

  // ── 付款購買 ──────────────────────────────────────────────────

  /// 付款後向後端驗證並升級方案
  ///
  /// [store]         - 'google_pay' | 'google_play' | 'app_store'
  /// [purchaseToken] - 對應 store 的 token / receipt
  static Future<bool> purchasePlan(
    UserPlan plan, {
    required String store,
    required String purchaseToken,
    String? productId,
  }) async {
    try {
      final ok = await VideoServerClient.instance.purchasePlan(
        plan.key, store, purchaseToken, productId: productId,
      );
      if (ok) await _writeCachedPlan(plan);
      debugPrint('$_tag ${ok ? '✅' : '⚠️'} purchasePlan: ${plan.label} via $store → $ok');
      return ok;
    } on UnauthorizedException {
      rethrow;
    } catch (e) {
      debugPrint('$_tag ❌ 購買方案異常: $e');
      return false;
    }
  }

  // ── 本地 cache 輔助 ───────────────────────────────────────────

  static Future<void> _writeCachedPlan(UserPlan plan) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, plan.key);
    } catch (_) {}
  }

  static Future<UserPlan> _readCachedPlan() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return UserPlanX.fromKey(prefs.getString(_prefKey));
    } catch (_) {
      return UserPlan.free;
    }
  }
}
