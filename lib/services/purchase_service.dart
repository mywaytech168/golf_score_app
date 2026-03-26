import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'in_app_purchase_service.dart';

/// 購買服務 - 檢查用戶是否購買了無廣告版本（使用 Google Play 和 Apple App Store）
class PurchaseService {
  static const String _premiumKey = 'user_premium_purchase';
  static const String _paymentMethodKey = 'user_payment_method';
  
  // 無廣告版本定價
  static const String premiumPrice = 'NT\$999';
  
  late SharedPreferences _prefs;
  
  /// 初始化服務
  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
  }
  
  /// 檢查用戶是否是高級用戶（已購買無廣告版本）
  Future<bool> isPremiumUser() async {
    return _prefs.getBool(_premiumKey) ?? false;
  }
  
  /// 設置用戶為高級用戶（在實際支付后調用）
  Future<void> setPremiumUser(bool isPremium, {String? paymentMethod}) async {
    await _prefs.setBool(_premiumKey, isPremium);
    if (paymentMethod != null) {
      await _prefs.setString(_paymentMethodKey, paymentMethod);
    }
    debugPrint('👤 [購買] 用戶高級狀態已設置為: $isPremium (支付方式: $paymentMethod)');
  }
  
  /// 獲取支付方式
  Future<String?> getPaymentMethod() async {
    return _prefs.getString(_paymentMethodKey);
  }
  
  /// 購買無廣告版本（綠界 ECPay 支付）
  Future<bool> purchasePremium({required String userId}) async {
    try {
      debugPrint('� [購買] 開始綠界 ECPay 支付流程...');
      
      final success = await InAppPurchaseService().purchasePremium();

      if (success) {
        debugPrint('✅ [購買] 購買流程已啟動');
        return true;
      } else {
        debugPrint('❌ [購買] 購買流程啟動失敗');
        return false;
      }
    } catch (e) {
      debugPrint('❌ [購買] 購買流程異常: $e');
      return false;
    }
  }
  
  /// 恢復之前的購買（用戶已購買但需要重新激活權益）
  Future<bool> restorePurchases({required String userId}) async {
    try {
      debugPrint('🛒 [購買] 恢復之前的購買...');
      
      final success = await InAppPurchaseService().restorePurchases();

      if (success) {
        debugPrint('✅ [購買] 購買已恢復');
        return true;
      } else {
        debugPrint('❌ [購買] 恢復購買失敗');
        return false;
      }
    } catch (e) {
      debugPrint('❌ [購買] 恢復購買異常: $e');
      return false;
    }
  }
  
  /// 【開發/測試用】清除高級用戶狀態
  Future<void> debugClearPremiumStatus() async {
    await _prefs.remove(_premiumKey);
    await _prefs.remove(_paymentMethodKey);
    debugPrint('🔧 [調試] 已清除高級用戶狀態，用戶現在是普通用戶');
  }
}
