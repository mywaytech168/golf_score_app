import 'dart:async';

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
import 'services/daily_ad_manager.dart';
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
  await MobileAds.instance.initialize();
  await InAppPurchaseService.initialize();
  final purchaseService = PurchaseService();
  await purchaseService.initialize();
  final adManager = DailyAdManager();
  await adManager.initialize();
  AdService.loadInterstitialAd();
  AdService.loadRewardedAd();

  // Load saved locale before running the app
  final localeProvider = LocaleProvider();
  await localeProvider.loadSavedLocale();

  runApp(MyApp(localeProvider: localeProvider));
}

class MyApp extends StatefulWidget {
  const MyApp({super.key, required this.localeProvider});

  final LocaleProvider localeProvider;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  StreamSubscription<void>? _sessionExpiredSub;

  @override
  void initState() {
    super.initState();
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
  void dispose() {
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
      child: Consumer<LocaleProvider>(
        builder: (context, localeProvider, _) {
          return MaterialApp(
            navigatorKey: _navigatorKey,
            title: 'TekSwing',
            theme: buildAppTheme(),
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
