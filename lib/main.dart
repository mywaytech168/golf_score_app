import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'services/analysis_progress_service.dart';
import 'services/auth_token_storage.dart';
import 'services/ad_service.dart';
import 'services/purchase_service.dart';
import 'services/in_app_purchase_service.dart';
import 'services/daily_ad_manager.dart';
import 'services/video_frame_extractor_test.dart';
import 'pages/login_page.dart';
import 'pages/main_shell_page.dart';
import 'providers/auth_provider.dart';
import 'providers/user_provider.dart';
import 'providers/statistics_provider.dart';
import 'providers/recording_provider.dart';
import 'providers/video_provider.dart';
import 'providers/app_state_provider.dart';

Future<void> main() async {
  // 屏蔽系统噪音日志
  _filterSystemLogs();
  
  // 先初始化 Flutter 綁定，避免在呼叫可用鏡頭前發生錯誤
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化 media_kit（比較模式雙播放器）
  MediaKit.ensureInitialized();

  // 啟動 Kotlin→Dart 進度回報 EventChannel
  AnalysisProgressService.instance.start();
  
  // 初始化 Google Mobile Ads
  await MobileAds.instance.initialize();
  
  // 初始化應用內購買服務
  await InAppPurchaseService.initialize();
  
  // 初始化購買服務
  final purchaseService = PurchaseService();
  await purchaseService.initialize();
  
  // 初始化每日廣告管理
  final adManager = DailyAdManager();
  await adManager.initialize();
  
  // 預加載廣告
  AdService.loadInterstitialAd();
  AdService.loadRewardedAd();

  // 相機初始化已由 camerawesome 在運行時處理
  // List<CameraDescription> cameras = const <CameraDescription>[];

  runApp(const MyApp());
}

/// 應用程式入口
class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    
    // 🧪 非阻塞地運行 VideoFrameExtractor 測試
    WidgetsBinding.instance.addPostFrameCallback((_) {
      debugPrint('[INIT] ========== 後幀回調開始 ==========');
      _runVideoFrameExtractorTest();
    });
  }

  /// 測試 VideoFrameExtractor 性能
  Future<void> _runVideoFrameExtractorTest() async {
    try {
      // 使用已有的視頻文件進行測試
      const videoPath = '/sdcard/Download/REC202512091023.mp4';
      debugPrint('📲 [DEBUG] 正在嘗試測試 VideoFrameExtractor...');
      debugPrint('📲 [DEBUG] 視頻路徑: $videoPath');
      
      // 簡單的測試：直接調用 MethodChannel
      const frameExtractorChannel =
          MethodChannel('com.example.golf_score_app/frame_extractor');
      
      debugPrint('📲 [DEBUG] 調用 extractFrameRgb at timeMs=0...');
      final result = await frameExtractorChannel.invokeMethod(
        'extractFrameRgb',
        {
          'videoPath': videoPath,
          'timeMs': 0,
          'maxWidth': 720,
        },
      ) as Map<dynamic, dynamic>?;
      
      if (result != null) {
        final width = result['width'] as int;
        final height = result['height'] as int;
        final pixels = result['pixels'];
        debugPrint('✅ [SUCCESS] 幀提取成功: ${width}x$height, ${pixels.toString().length} bytes');
      } else {
        debugPrint('❌ [ERROR] 結果為 null');
      }
    } catch (e) {
      debugPrint('❌ [ERROR] 測試失敗: $e');
    }
  }

  // ---------- 方法區 ----------

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // 全局狀態
        ChangeNotifierProvider(create: (_) => AppStateProvider()),
        
        // 認證
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        
        // 使用者資料
        ChangeNotifierProvider(create: (_) => UserProvider()),
        
        // 統計數據
        ChangeNotifierProvider(create: (_) => StatisticsProvider()),
        
        // 錄制
        ChangeNotifierProvider(create: (_) => RecordingProvider()),
        
        // 視頻播放
        ChangeNotifierProvider(create: (_) => VideoProvider()),
      ],
      child: Consumer<AppStateProvider>(
        builder: (context, appState, _) {
          return MaterialApp(
            title: 'Golf Score App',
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1E8E5A)),
              scaffoldBackgroundColor: const Color(0xFFF5F7FB),
              useMaterial3: true,
            ),
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

  /// 根據 JWT token 判斷是否已登入，返回相應頁面
  Widget _buildHome() {
    return FutureBuilder<bool>(
      future: _isUserLoggedIn(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // 如果有登入token，進入首頁；否則進入登錄頁
        if (snapshot.data == true) {
          return const MainShellPage();
        }

        return const LoginPage();
      },
    );
  }

  /// 檢查是否存在有效的 JWT token
  Future<bool> _isUserLoggedIn() async {
    try {
      return await AuthTokenStorage.instance.isLoggedIn();
    } catch (e) {
      return false;
    }
  }
}

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
