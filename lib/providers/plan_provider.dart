import 'package:flutter/foundation.dart';
import '../services/ad_service.dart';
import '../services/analytics_service.dart';
import '../services/plan_service.dart';

/// 全域方案狀態 Provider
///
/// 付款成功後呼叫 [refresh()] 即可讓所有訂閱此 Provider 的頁面即時更新。
class PlanProvider with ChangeNotifier {
  PlanStatus _status = const PlanStatus(
    plan: UserPlan.free,
    todayUsed: 0,
    dailyLimit: 10,
  );

  bool _loading = false;

  PlanStatus   get status              => _status;
  UserPlan     get plan                => _status.plan;
  bool         get loading             => _loading;
  DateTime?    get subscriptionExpiry  => _status.subscriptionExpiry;
  String       get subscriptionStatus  => _status.subscriptionStatus;
  bool         get isSubscribed        => _status.isSubscriptionActive;

  /// 從後端重新拉取方案狀態並通知所有 listener
  Future<void> refresh() async {
    _loading = true;
    notifyListeners();
    try {
      _status = await PlanService.getPlanStatus();
      // Pro / Elite 免廣告；Free 顯示廣告
      AdService.adsEnabled = _status.plan == UserPlan.free;

      // Analytics 使用者屬性：方案與球數分桶（供事件分群）
      AnalyticsService.instance.setUserProperty('user_plan', _status.plan.key);
      final balls = _status.bonusBalls;
      final bucket = balls <= 10
          ? '0-10'
          : balls <= 50
              ? '11-50'
              : balls <= 100
                  ? '51-100'
                  : '100+';
      AnalyticsService.instance.setUserProperty('ball_balance_bucket', bucket);
    } catch (e) {
      debugPrint('[PlanProvider] refresh 失敗: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}
