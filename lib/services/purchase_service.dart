import 'package:shared_preferences/shared_preferences.dart';

/// 購買服務 - 檢查用戶是否購買了無廣告版本
class PurchaseService {
  static const String _premiumKey = 'user_premium_purchase';
  
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
  Future<void> setPremiumUser(bool isPremium) async {
    await _prefs.setBool(_premiumKey, isPremium);
  }
  
  /// 獲取無廣告版本的價格
  static const String premiumPrice = '¥9.99'; // 根據您的定價調整
  
  /// 購買無廣告版本（集成支付網關）
  Future<bool> purchasePremium() async {
    try {
      // 這裡應該集成真實的支付系統（Google Play Billing, App Store, 等）
      // 示例：
      // await _paymentGateway.purchase('premium_no_ads');
      
      // 支付成功后，設置為高級用戶
      await setPremiumUser(true);
      return true;
    } catch (e) {
      print('購買失敗: $e');
      return false;
    }
  }
}
