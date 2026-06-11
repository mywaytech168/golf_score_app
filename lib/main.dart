import 'dart:async';
import 'dart:io';

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'package:golf_score_app/l10n/app_localizations.dart';

import 'theme/app_theme.dart';
import 'services/analysis_progress_service.dart';
import 'services/auth_token_storage.dart';
import 'services/ad_service.dart';
import 'services/purchase_service.dart';
import 'services/in_app_purchase_service.dart';
import 'pages/login_page.dart';
import 'pages/main_shell_page.dart';
import 'pages/terms_of_service_page.dart';
import 'providers/auth_provider.dart';
import 'providers/user_provider.dart';
import 'providers/statistics_provider.dart';
import 'providers/recording_provider.dart';
import 'providers/video_provider.dart';
import 'providers/app_state_provider.dart';
import 'providers/locale_provider.dart';
import 'providers/plan_provider.dart';

Future<void> main() async {
  _filterSystemLogs();
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  MediaKit.ensureInitialized();
  AnalysisProgressService.instance.start();

  // 只有「載入語系」是進入畫面前的必要步驟，且加上 timeout 避免儲存層卡住白屏。
  final localeProvider = LocaleProvider();
  try {
    await localeProvider.loadSavedLocale().timeout(const Duration(seconds: 3));
  } catch (e) {
    debugPrint('⚠️ [App] 載入語系逾時/失敗，使用預設語系: $e');
  }

  // 廣告 / 內購 / 每日廣告等初始化不該阻塞首屏，改為背景執行。
  // 弱訊號或商店服務無回應時，App 仍能立即進入並正常錄製。
  unawaited(_initServicesInBackground());

  runApp(MyApp(localeProvider: localeProvider));
}

/// 背景初始化非首屏關鍵服務。任何單項失敗都不影響 App 進入。
Future<void> _initServicesInBackground() async {
  Future<void> guard(String name, Future<void> Function() task) async {
    try {
      await task().timeout(const Duration(seconds: 15));
    } catch (e) {
      debugPrint('⚠️ [App] 初始化 $name 失敗: $e');
    }
  }

  // iOS：在初始化廣告前先請求 App Tracking Transparency 授權（Apple 5.1.2 要求）。
  // 使用者未允許時 IDFA 會回傳全零，AdMob 自動改投放非個人化廣告，全功能仍可使用。
  if (Platform.isIOS) {
    await guard('ATT', () async {
      final status =
          await AppTrackingTransparency.trackingAuthorizationStatus;
      if (status == TrackingStatus.notDetermined) {
        await AppTrackingTransparency.requestTrackingAuthorization();
      }
    });
  }

  await guard('MobileAds', () => MobileAds.instance.initialize());
  await guard('InAppPurchase', () => InAppPurchaseService.instance.init());
  await guard('PurchaseService', () => PurchaseService().initialize());

  unawaited(AdService.loadAiCoachInterstitial());
  unawaited(AdService.loadBallDetectionInterstitial());
  unawaited(AdService.loadFullAnalysisInterstitial());
  unawaited(AdService.loadRewardedAiCoach());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key, required this.localeProvider});

  final LocaleProvider localeProvider;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  final _navigatorKey = GlobalKey<NavigatorState>();
  StreamSubscription<void>? _sessionExpiredSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 當 refresh token 也失效時，自動跳轉登入頁
    _sessionExpiredSub = sessionExpiredStream.stream.listen((_) {
      debugPrint('⚠️ [App] Session 過期，跳轉登入頁');
      _navigatorKey.currentState?.pushNamedAndRemoveUntil(
        '/login',
        (route) => false,
      );
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // 回前景時補發先前扣款成功但驗證失敗的交易（網路恢復情境）。
      unawaited(InAppPurchaseService.instance.retryPendingVerifications());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sessionExpiredSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: widget.localeProvider),
        ChangeNotifierProvider(create: (_) => AppStateProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProvider(create: (_) => StatisticsProvider()),
        ChangeNotifierProvider(create: (_) => RecordingProvider()),
        ChangeNotifierProvider(create: (_) => VideoProvider()),
        ChangeNotifierProvider(create: (_) => PlanProvider()),
      ],
      child: Consumer2<LocaleProvider, AppStateProvider>(
        builder: (context, localeProvider, appState, _) {
          return MaterialApp(
            navigatorKey: _navigatorKey,
            title: 'ORVIA',
            theme: buildAppTheme(),
            darkTheme: buildAppDarkTheme(),
            themeMode: appState.themeMode,
            locale: localeProvider.locale,
            supportedLocales: LocaleProvider.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: _buildHome(),
            routes: {
              '/home': (context) => const MainShellPage(),
              '/login': (context) => const LoginPage(),
            },
          );
        },
      ),
    );
  }

  /// 啟動路由：先確認條款，再確認登入狀態
  Widget _buildHome() {
    return FutureBuilder<_StartupState>(
      future: _resolveStartupState(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        switch (snapshot.data ?? _StartupState.showTerms) {
          case _StartupState.showTerms:
            return const TermsOfServicePage();
          case _StartupState.showLogin:
            return const LoginPage();
          case _StartupState.showHome:
            return const MainShellPage();
        }
      },
    );
  }

  Future<_StartupState> _resolveStartupState() async {
    try {
      final accepted = await TermsOfServicePage.isAccepted();
      if (!accepted) return _StartupState.showTerms;

      final loggedIn = await AuthTokenStorage.instance.isLoggedIn();
      return loggedIn ? _StartupState.showHome : _StartupState.showLogin;
    } catch (_) {
      return _StartupState.showTerms;
    }
  }
}

enum _StartupState { showTerms, showLogin, showHome }

/// 屏蔽系统噪音日志
void _filterSystemLogs() {
  // Release 版本完全靜音 debugPrint，避免洩漏 API 結構/狀態碼並減少效能開銷。
  if (kReleaseMode) {
    debugPrint = (String? message, {int? wrapWidth}) {};
    return;
  }

  // 重定向 debugPrint 来过滤日志
  final originalDebugPrint = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message == null) return;

    // 屏蔽的日志关键词
    final blocklist = [
      'hiddenapi',
      'studio.profiler',
      'studio.transport',
      'nativeloader',
      'libc',
      'Transformed class',
      'DexFile',
      'JVMTI',
      'Verification error',
      'Cleared Reference',
      'Invalid ID',
      'avc:',
      'audit(',
      'scontext=',
      'tcontext=',
      'Reaching hidden api',
      'W/qdgralloc',
      'qdgralloc',
    ];
    
    // 如果消息包含屏蔽关键词，则不输出
    for (final keyword in blocklist) {
      if (message.contains(keyword)) {
        return;
      }
    }
    
    // 否则正常输出
    originalDebugPrint(message, wrapWidth: wrapWidth);
  };
}
