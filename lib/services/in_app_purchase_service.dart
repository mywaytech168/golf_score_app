import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'plan_service.dart';
import 'video_server_client.dart';

// ── 商品 ID 對照 ────────────────────────────────────────────────

const _kProMonthly   = 'golf_pro_monthly';
const _kEliteMonthly = 'golf_elite_monthly';

// 球數包（consumable）
const _kBalls1   = 'golf_balls_1';
const _kBalls5   = 'golf_balls_5';
const _kBalls10  = 'golf_balls_10';
const _kBalls50  = 'golf_balls_50';
const _kBalls100 = 'golf_balls_100';

const _kBallPackIds = {_kBalls1, _kBalls5, _kBalls10, _kBalls50, _kBalls100};

const _kProductIds = {_kProMonthly, _kEliteMonthly, ..._kBallPackIds};

// ── 事件通知 ────────────────────────────────────────────────────

enum IapEvent { success, error, canceled, pending }

class IapResult {
  final IapEvent event;
  final UserPlan? plan;
  final String? message;
  const IapResult(this.event, {this.plan, this.message});
}

// ════════════════════════════════════════════════════════════════
// InAppPurchaseService
// ════════════════════════════════════════════════════════════════

/// Singleton service 管理訂閱的購買流程。
///
/// 使用方式：
/// 1. main() 呼叫 [InAppPurchaseService.instance.init()]
/// 2. 監聽 [results] stream 取得購買結果
/// 3. 購買完成後呼叫 [PlanProvider.refresh()] 更新 UI
class InAppPurchaseService {
  InAppPurchaseService._();
  static final InAppPurchaseService instance = InAppPurchaseService._();

  final _iap = InAppPurchase.instance;

  StreamSubscription<List<PurchaseDetails>>? _subscription;
  final _resultController = StreamController<IapResult>.broadcast();

  Stream<IapResult> get results => _resultController.stream;

  bool _initialized = false;

  // ── 初始化 ──────────────────────────────────────────────────

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    final available = await _iap.isAvailable();
    if (!available) {
      debugPrint('[IAP] Store 不可用');
      return;
    }

    _subscription = _iap.purchaseStream.listen(
      _handlePurchaseUpdates,
      onError: (e) => debugPrint('[IAP] stream error: $e'),
    );

    debugPrint('[IAP] 初始化完成');
  }

  void dispose() {
    _subscription?.cancel();
    _resultController.close();
  }

  // ── 查詢商品 ────────────────────────────────────────────────

  Future<List<ProductDetails>> queryProducts() async {
    final response = await _iap.queryProductDetails(_kProductIds);
    if (response.notFoundIDs.isNotEmpty) {
      debugPrint('[IAP] 找不到商品: ${response.notFoundIDs}');
    }
    return response.productDetails;
  }

  // ── 發起訂閱 ────────────────────────────────────────────────

  Future<void> subscribe(ProductDetails product) async {
    final param = PurchaseParam(productDetails: product);
    await _iap.buyNonConsumable(purchaseParam: param);
  }

  // ── 購買球包（consumable）──────────────────────────────────

  Future<void> buyBallPack(ProductDetails product) async {
    final param = PurchaseParam(productDetails: product);
    await _iap.buyConsumable(purchaseParam: param);
  }

  // ── 恢復購買 ────────────────────────────────────────────────

  Future<void> restorePurchases() async {
    await _iap.restorePurchases();
  }

  // ── 購買事件處理 ────────────────────────────────────────────

  Future<void> _handlePurchaseUpdates(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      switch (purchase.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _onPurchasedOrRestored(purchase);
        case PurchaseStatus.pending:
          _resultController.add(
            const IapResult(IapEvent.pending, message: '付款處理中，完成後將自動升級'));
        case PurchaseStatus.error:
          debugPrint('[IAP] 錯誤: ${purchase.error}');
          _resultController.add(
            IapResult(IapEvent.error, message: purchase.error?.message));
          await _safeComplete(purchase);
        case PurchaseStatus.canceled:
          _resultController.add(const IapResult(IapEvent.canceled));
      }
    }
  }

  Future<void> _onPurchasedOrRestored(PurchaseDetails purchase) async {
    final store   = Platform.isIOS ? 'app_store' : 'google_play';
    final token   = purchase.verificationData.serverVerificationData;
    final product = purchase.productID;

    debugPrint('[IAP] 購買成功 store=$store product=$product');

    if (_kBallPackIds.contains(product)) {
      await _handleBallPackPurchase(purchase, store, token, product);
    } else {
      await _handleSubscriptionPurchase(purchase, store, token, product);
    }
  }

  Future<void> _handleBallPackPurchase(
      PurchaseDetails purchase, String store, String token, String product) async {
    try {
      final newBalance = await PlanService.purchaseBalls(
        product,
        store: store,
        purchaseToken: token,
      );
      await _safeComplete(purchase);
      if (newBalance != null) {
        _resultController.add(IapResult(IapEvent.success, message: 'balls:$newBalance'));
        debugPrint('[IAP] 球包購買成功，新餘額 $newBalance');
      } else {
        _resultController.add(const IapResult(IapEvent.error, message: '球包驗證失敗，請聯絡客服'));
      }
    } on UnauthorizedException {
      debugPrint('[IAP] 未授權，Token 已過期');
      rethrow;
    } catch (e) {
      debugPrint('[IAP] 球包驗證異常: $e');
      _resultController.add(IapResult(IapEvent.error, message: '網路錯誤，請稍後再試'));
    }
  }

  Future<void> _handleSubscriptionPurchase(
      PurchaseDetails purchase, String store, String token, String product) async {
    final plan = _planFromProductId(product);
    try {
      final ok = await PlanService.purchasePlan(
        plan,
        store: store,
        purchaseToken: token,
        productId: product,
      );
      if (ok) {
        await _safeComplete(purchase);
        _resultController.add(IapResult(IapEvent.success, plan: plan));
        debugPrint('[IAP] 後端驗證成功，方案已升級至 ${plan.label}');
      } else {
        await _safeComplete(purchase);
        _resultController.add(
          const IapResult(IapEvent.error, message: '訂閱驗證失敗，請稍後使用「恢復購買」重試'));
      }
    } on UnauthorizedException {
      debugPrint('[IAP] 未授權，Token 已過期');
      rethrow;
    } catch (e) {
      debugPrint('[IAP] 後端驗證異常: $e');
      _resultController.add(IapResult(IapEvent.error, message: '網路錯誤，請稍後再試'));
    }
  }

  Future<void> _safeComplete(PurchaseDetails purchase) async {
    if (purchase.pendingCompletePurchase) {
      try {
        await _iap.completePurchase(purchase);
      } catch (e) {
        debugPrint('[IAP] completePurchase 失敗: $e');
      }
    }
  }

  UserPlan _planFromProductId(String productId) {
    if (productId == _kEliteMonthly) return UserPlan.elite;
    return UserPlan.pro;
  }
}
