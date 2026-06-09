import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'plan_service.dart';
import 'purchase_retry_queue.dart';
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

    // 啟動時重試先前扣款成功但驗證失敗的交易（網路恢復後補發方案/球數）。
    unawaited(retryPendingVerifications());
  }

  /// 重試所有「已扣款但後端驗證未成功」的交易。
  ///
  /// 建議時機：App 啟動（[init]）、回到前景、token 重新登入後。
  Future<void> retryPendingVerifications() async {
    final pending = await PurchaseRetryQueue.instance.all();
    if (pending.isEmpty) return;
    debugPrint('[IAP] 重試 ${pending.length} 筆待驗證交易');

    for (final item in pending) {
      try {
        final ok = item.isBallPack
            ? (await PlanService.purchaseBalls(item.productId,
                    store: item.store, purchaseToken: item.token)) !=
                null
            : await PlanService.purchasePlan(
                _planFromProductId(item.productId),
                store: item.store,
                purchaseToken: item.token,
                productId: item.productId,
              );

        if (ok) {
          await PurchaseRetryQueue.instance.remove(item.token);
          final plan = _planFromProductId(item.productId);
          _resultController.add(item.isBallPack
              ? const IapResult(IapEvent.success, message: 'balls:refresh')
              : IapResult(IapEvent.success, plan: plan));
          debugPrint('[IAP] 待驗證交易補發成功 ${item.productId}');
        } else {
          await _bumpOrGiveUp(item);
        }
      } on UnauthorizedException {
        // Token 失效：保留佇列，待重新登入後再試。
        debugPrint('[IAP] 重試遇未授權，保留待驗證交易 ${item.productId}');
      } catch (e) {
        // 網路錯誤：保留佇列，下次再試。
        debugPrint('[IAP] 重試網路錯誤，保留 ${item.productId}: $e');
      }
    }
  }

  /// 累加重試次數；超過上限視為無法挽回，移除並提示聯絡客服。
  Future<void> _bumpOrGiveUp(PendingPurchase item) async {
    final next = item.withAttempt();
    if (next.attempts >= PurchaseRetryQueue.maxAttempts) {
      await PurchaseRetryQueue.instance.abandon(item.token);
      _resultController.add(const IapResult(
          IapEvent.error, message: '購買已扣款但驗證持續失敗，請聯絡客服並提供購買憑證'));
      debugPrint('[IAP] 待驗證交易放棄 ${item.productId}（達重試上限）');
    } else {
      await PurchaseRetryQueue.instance.enqueue(next);
    }
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

    // 先前已放棄（達重試上限）的交易：直接核銷以中止商店無限重派。
    if (await PurchaseRetryQueue.instance.isAbandoned(token)) {
      debugPrint('[IAP] 略過已放棄交易 $product');
      await _safeComplete(purchase);
      return;
    }

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
      if (newBalance != null) {
        // 僅在後端確認加值成功後才核銷交易。
        await _safeComplete(purchase);
        await PurchaseRetryQueue.instance.remove(token);
        _resultController.add(IapResult(IapEvent.success, message: 'balls:$newBalance'));
        debugPrint('[IAP] 球包購買成功，新餘額 $newBalance');
      } else {
        // 後端可達但驗證未過：保留交易（不核銷）並排入重試佇列。
        await _enqueuePending(product, store, token, isBallPack: true);
        _resultController.add(const IapResult(
            IapEvent.error, message: '球包驗證未完成，將自動於稍後重試'));
      }
    } on UnauthorizedException {
      debugPrint('[IAP] 未授權，Token 已過期，保留待驗證交易');
      await _enqueuePending(product, store, token, isBallPack: true);
    } catch (e) {
      // 網路錯誤：保留交易（不核銷），讓商店於下次啟動重派並進入重試佇列。
      debugPrint('[IAP] 球包驗證異常: $e');
      await _enqueuePending(product, store, token, isBallPack: true);
      _resultController.add(IapResult(IapEvent.error, message: '網路錯誤，已扣款將自動補發'));
    }
  }

  Future<void> _enqueuePending(String product, String store, String token,
      {required bool isBallPack}) async {
    await PurchaseRetryQueue.instance.enqueue(PendingPurchase(
      productId: product,
      store: store,
      token: token,
      isBallPack: isBallPack,
      firstSeenMs: DateTime.now().millisecondsSinceEpoch,
    ));
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
        await PurchaseRetryQueue.instance.remove(token);
        _resultController.add(IapResult(IapEvent.success, plan: plan));
        debugPrint('[IAP] 後端驗證成功，方案已升級至 ${plan.label}');
      } else {
        // 後端可達但驗證未過：保留交易（不核銷）並排入重試佇列。
        await _enqueuePending(product, store, token, isBallPack: false);
        _resultController.add(const IapResult(
            IapEvent.error, message: '訂閱驗證未完成，將自動於稍後重試'));
      }
    } on UnauthorizedException {
      debugPrint('[IAP] 未授權，Token 已過期，保留待驗證交易');
      await _enqueuePending(product, store, token, isBallPack: false);
    } catch (e) {
      debugPrint('[IAP] 後端驗證異常: $e');
      await _enqueuePending(product, store, token, isBallPack: false);
      _resultController.add(IapResult(IapEvent.error, message: '網路錯誤，已扣款將自動補發'));
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
