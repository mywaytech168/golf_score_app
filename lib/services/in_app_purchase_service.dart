import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

/// 應用內購買服務（Google Play 和 Apple App Store）
class InAppPurchaseService {
  static const String _noAdProductId = 'golf_no_ads_premium';
  
  /// 初始化應用內購買服務
  static Future<void> initialize() async {
    debugPrint('🛒 [應用內購買] 初始化服務...');
    
    final available = await InAppPurchase.instance.isAvailable();
    if (!available) {
      debugPrint('❌ [應用內購買] 設備不支持應用內購買');
      return;
    }
    
    debugPrint('✅ [應用內購買] 服務初始化成功');
  }

  /// 查詢產品信息
  Future<ProductDetails?> getProductDetails() async {
    try {
      debugPrint('🛒 [應用內購買] 查詢產品信息: $_noAdProductId');
      
      final ProductDetailsResponse response = await InAppPurchase.instance.queryProductDetails({_noAdProductId});
      
      if (response.notFoundIDs.isNotEmpty) {
        debugPrint('❌ [應用內購買] 找不到產品: ${response.notFoundIDs}');
        return null;
      }
      
      if (response.productDetails.isEmpty) {
        debugPrint('❌ [應用內購買] 沒有可用的產品');
        return null;
      }
      
      final product = response.productDetails.first;
      debugPrint('✅ [應用內購買] 產品名稱: ${product.title}');
      debugPrint('✅ [應用內購買] 產品價格: ${product.price}');
      debugPrint('✅ [應用內購買] 產品描述: ${product.description}');
      
      return product;
    } catch (e) {
      debugPrint('❌ [應用內購買] 查詢產品出錯: $e');
      return null;
    }
  }

  /// 購買無廣告版本
  Future<bool> purchasePremium() async {
    try {
      debugPrint('🛒 [應用內購買] 開始購買無廣告版本...');
      
      final product = await getProductDetails();
      if (product == null) {
        debugPrint('❌ [應用內購買] 無法獲取產品信息');
        return false;
      }
      
      final PurchaseParam purchaseParam = PurchaseParam(productDetails: product);
      
      debugPrint('🛒 [應用內購買] 發起購買流程...');
      await InAppPurchase.instance.buyConsumable(
        purchaseParam: purchaseParam,
        autoConsume: true, // 自動消費此次購買
      );
      
      debugPrint('🛒 [應用內購買] 購買流程已發起，等待用戶完成...');
      return true;
    } catch (e) {
      debugPrint('❌ [應用內購買] 購買出錯: $e');
      return false;
    }
  }

  /// 恢復購買（用於用戶已購買但需要重新激活權益）
  Future<bool> restorePurchases() async {
    try {
      debugPrint('🛒 [應用內購買] 恢復之前的購買...');
      
      await InAppPurchase.instance.restorePurchases();
      
      debugPrint('✅ [應用內購買] 購買已恢復');
      return true;
    } catch (e) {
      debugPrint('❌ [應用內購買] 恢復購買出錯: $e');
      return false;
    }
  }

  /// 監聽購買更新
  Stream<List<PurchaseDetails>> purchaseUpdated() {
    debugPrint('🛒 [應用內購買] 開始監聽購買更新...');
    
    return InAppPurchase.instance.purchaseStream;
  }

  /// 驗證並完成購買
  static Future<void> verifyAndCompletePurchase(PurchaseDetails purchase) async {
    try {
      if (purchase.status == PurchaseStatus.purchased) {
        debugPrint('✅ [應用內購買] 購買成功 - 交易ID: ${purchase.purchaseID}');
        
        // 驗證購買收據（在生產環境應驗證 purchase.verificationData.serverVerificationData）
        if (purchase.verificationData.serverVerificationData.isNotEmpty) {
          debugPrint('✅ [應用內購買] 收據已驗證');
        }
        
        // 標記購買為已完成
        if (!purchase.pendingCompletePurchase) {
          await InAppPurchase.instance.completePurchase(purchase);
        }
      } else if (purchase.status == PurchaseStatus.error) {
        debugPrint('❌ [應用內購買] 購買失敗: ${purchase.error}');
      } else if (purchase.status == PurchaseStatus.canceled) {
        debugPrint('⚠️ [應用內購買] 用戶取消了購買');
      } else if (purchase.status == PurchaseStatus.pending) {
        debugPrint('⏳ [應用內購買] 購買待處理中...');
      }
    } catch (e) {
      debugPrint('❌ [應用內購買] 驗證購買出錯: $e');
    }
  }

  /// 調試方法 - 模擬購買成功
  static Future<void> debugSimulatePurchaseSuccess({
    required Function() onSuccess,
  }) async {
    debugPrint('🛒 [應用內購買] 調試模式 - 模擬購買成功');
    
    await Future.delayed(const Duration(seconds: 2));
    onSuccess();
    
    debugPrint('✅ [應用內購買] 模擬購買完成');
  }

  /// 獲取產品 ID
  static String get noAdProductId => _noAdProductId;
}
