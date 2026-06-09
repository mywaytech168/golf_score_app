import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 一筆等待後端驗證的已付款交易。
///
/// 使用者已被商店扣款，但後端驗證（升級方案 / 加值球數）尚未成功，
/// 必須持久化保存，待網路恢復或 App 回前景時重試，避免「付了錢卻沒拿到東西」。
class PendingPurchase {
  final String productId;
  final String store; // 'app_store' | 'google_play'
  final String token; // serverVerificationData
  final bool isBallPack;
  final int attempts;
  final int firstSeenMs;

  const PendingPurchase({
    required this.productId,
    required this.store,
    required this.token,
    required this.isBallPack,
    this.attempts = 0,
    required this.firstSeenMs,
  });

  /// 以 token 作為唯一鍵（同一筆交易的 verificationData 固定）。
  String get key => token;

  PendingPurchase withAttempt() => PendingPurchase(
        productId: productId,
        store: store,
        token: token,
        isBallPack: isBallPack,
        attempts: attempts + 1,
        firstSeenMs: firstSeenMs,
      );

  Map<String, dynamic> toJson() => {
        'productId': productId,
        'store': store,
        'token': token,
        'isBallPack': isBallPack,
        'attempts': attempts,
        'firstSeenMs': firstSeenMs,
      };

  factory PendingPurchase.fromJson(Map<String, dynamic> j) => PendingPurchase(
        productId: j['productId'] as String,
        store: j['store'] as String,
        token: j['token'] as String,
        isBallPack: j['isBallPack'] as bool? ?? false,
        attempts: j['attempts'] as int? ?? 0,
        firstSeenMs: j['firstSeenMs'] as int? ?? 0,
      );
}

/// 已付款但尚未完成後端驗證的交易佇列（持久化於 shared_preferences）。
class PurchaseRetryQueue {
  PurchaseRetryQueue._();
  static final PurchaseRetryQueue instance = PurchaseRetryQueue._();

  static const _kPrefsKey = 'pending_purchase_queue_v1';
  static const _kAbandonedKey = 'pending_purchase_abandoned_v1';

  /// 超過此次數仍無法通過後端驗證，視為無法挽回，交由呼叫端核銷並提示客服，
  /// 以免同一筆無效交易在每次啟動時無限重試。
  static const int maxAttempts = 8;

  Future<List<PendingPurchase>> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kPrefsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => PendingPurchase.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[PurchaseQueue] 解析失敗，清空: $e');
      await prefs.remove(_kPrefsKey);
      return [];
    }
  }

  Future<void> _save(List<PendingPurchase> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _kPrefsKey, jsonEncode(items.map((e) => e.toJson()).toList()));
  }

  /// 加入（或更新）一筆待驗證交易；以 token 去重。
  Future<void> enqueue(PendingPurchase item) async {
    final items = await _load();
    final idx = items.indexWhere((e) => e.key == item.key);
    if (idx >= 0) {
      items[idx] = item;
    } else {
      items.add(item);
    }
    await _save(items);
    debugPrint('[PurchaseQueue] 已保存待驗證交易 ${item.productId} (共 ${items.length} 筆)');
  }

  /// 移除一筆（驗證成功或已放棄）。
  Future<void> remove(String token) async {
    final items = await _load();
    items.removeWhere((e) => e.key == token);
    await _save(items);
  }

  Future<List<PendingPurchase>> all() => _load();

  Future<bool> get isEmpty async => (await _load()).isEmpty;

  // ── 放棄清單 ────────────────────────────────────────────────
  // 達重試上限、確定無法挽回的 token。商店仍可能於每次啟動重新派發，
  // 此清單讓事件處理端直接核銷並略過，避免無限迴圈。

  Future<Set<String>> _loadAbandoned() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_kAbandonedKey) ?? const <String>[]).toSet();
  }

  Future<void> abandon(String token) async {
    final prefs = await SharedPreferences.getInstance();
    final set = await _loadAbandoned();
    if (set.add(token)) {
      // 上限保護，避免清單無限增長。
      final list = set.toList();
      if (list.length > 100) list.removeRange(0, list.length - 100);
      await prefs.setStringList(_kAbandonedKey, list);
    }
    await remove(token);
  }

  Future<bool> isAbandoned(String token) async =>
      (await _loadAbandoned()).contains(token);
}
