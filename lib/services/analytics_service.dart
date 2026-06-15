import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Firebase Analytics (GA4) 薄封裝。
///
/// 設計原則：**永不丟例外**。Firebase native 設定檔（google-services.json /
/// GoogleService-Info.plist）尚未放入時，[init] 會失敗但被吞掉，之後所有
/// log 方法皆為 no-op，App 功能完全不受影響。
///
/// 用法：
///   - `main()` 於 `runApp` 前 `await AnalyticsService.instance.init();`
///   - `MaterialApp(navigatorObservers: [if (obs != null) obs!])` 自動記錄具名路由
///   - 分頁 / 自訂事件呼叫 [logScreen] / [logEvent]
class AnalyticsService {
  AnalyticsService._();
  static final AnalyticsService instance = AnalyticsService._();

  FirebaseAnalytics? _analytics;
  FirebaseAnalyticsObserver? _observer;

  /// Analytics 是否可用（Firebase 已成功初始化）。
  bool get enabled => _analytics != null;

  /// 供 `MaterialApp.navigatorObservers` 使用，自動記錄具名路由的 screen_view。
  /// Firebase 未初始化時為 null。
  FirebaseAnalyticsObserver? get observer => _observer;

  /// 於 `runApp` 前呼叫。失敗（含未放設定檔）時靜默停用，不影響 App 啟動。
  Future<void> init() async {
    try {
      await Firebase.initializeApp();
      final analytics = FirebaseAnalytics.instance;
      _analytics = analytics;
      _observer = FirebaseAnalyticsObserver(analytics: analytics);
      debugPrint('✅ [Analytics] Firebase Analytics 已啟用');
    } catch (e) {
      // 常見原因：尚未放入 google-services.json / GoogleService-Info.plist
      debugPrint('⚠️ [Analytics] 初始化失敗，停用追蹤: $e');
    }
  }

  /// 記錄使用者目前所在的操作介面（screen_view 事件）。
  Future<void> logScreen(String screenName) async {
    final a = _analytics;
    if (a == null) return;
    try {
      await a.logScreenView(screenName: screenName, screenClass: screenName);
    } catch (e) {
      debugPrint('⚠️ [Analytics] logScreen 失敗: $e');
    }
  }

  /// 記錄自訂事件（如 record_start / purchase_success / analysis_failed）。
  /// 事件名與參數須符合 GA4 規範（小寫底線、參數值為 String/num/bool）。
  Future<void> logEvent(String name, [Map<String, Object>? parameters]) async {
    final a = _analytics;
    if (a == null) return;
    try {
      await a.logEvent(name: name, parameters: parameters);
    } catch (e) {
      debugPrint('⚠️ [Analytics] logEvent($name) 失敗: $e');
    }
  }

  /// App 開啟事件。
  Future<void> logAppOpen() async {
    final a = _analytics;
    if (a == null) return;
    try {
      await a.logAppOpen();
    } catch (e) {
      debugPrint('⚠️ [Analytics] logAppOpen 失敗: $e');
    }
  }

  /// 綁定使用者 ID（可與後端使用者對應；勿傳入個資如 email）。
  Future<void> setUserId(String? userId) async {
    final a = _analytics;
    if (a == null) return;
    try {
      await a.setUserId(id: userId);
    } catch (e) {
      debugPrint('⚠️ [Analytics] setUserId 失敗: $e');
    }
  }

  /// 設定使用者屬性（供事件依使用者類型分群，如 user_plan / app_language）。
  Future<void> setUserProperty(String name, String value) async {
    final a = _analytics;
    if (a == null) return;
    try {
      await a.setUserProperty(name: name, value: value);
    } catch (e) {
      debugPrint('⚠️ [Analytics] setUserProperty($name) 失敗: $e');
    }
  }
}
