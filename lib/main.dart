import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
<<<<<<< HEAD
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:io';
=======
import 'dart:developer' as developer;
>>>>>>> 00fbbe244e2f3778851c4634334111c8e914a987

import 'services/auth_token_storage.dart';
import 'pages/login_page.dart';
import 'pages/home_page.dart';

Future<void> main() async {
  // 屏蔽系统噪音日志
  _filterSystemLogs();
  
  // 先初始化 Flutter 綁定，避免在呼叫可用鏡頭前發生錯誤
  WidgetsFlutterBinding.ensureInitialized();

  List<CameraDescription> cameras = const <CameraDescription>[];
  String? cameraError;

  try {
    cameras = await availableCameras();
  } catch (error) {
    cameraError = '無法初始化相機：$error';
  }

  // iOS 藍牙初始化
  if (Platform.isIOS) {
    try {
      // 監聽藍牙狀態，確保藍牙服務已啟動
      FlutterBluePlus.setLogLevel(LogLevel.info, color: true);
    } catch (e) {
      debugPrint('藍牙初始化錯誤: $e');
    }
  }

  runApp(MyApp(
    initialCameras: cameras,
    initialCameraError: cameraError,
  ));
}

/// 應用程式入口：維持 StatefulWidget 以便在相機初始化失敗時允許重新嘗試
class MyApp extends StatefulWidget {
  final List<CameraDescription> initialCameras; // 啟動階段取得的鏡頭清單
  final String? initialCameraError; // 啟動時的錯誤訊息

  const MyApp({
    super.key,
    required this.initialCameras,
    this.initialCameraError,
  });

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  // ---------- 狀態管理區 ----------
  late List<CameraDescription> _cameras; // 最新的鏡頭清單
  String? _cameraError; // 最近一次的錯誤資訊
  bool _isLoading = false; // 控制是否顯示載入指示

  @override
  void initState() {
    super.initState();
    _cameras = widget.initialCameras;
    _cameraError = widget.initialCameraError;
  }

  // ---------- 方法區 ----------
  /// 重新嘗試載入鏡頭，於使用者按下重新整理時呼叫
  Future<void> _reloadCameras() async {
    setState(() {
      _isLoading = true;
      _cameraError = null;
    });

    try {
      final cameras = await availableCameras();
      if (!mounted) return;
      setState(() {
        _cameras = cameras;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _cameraError = '無法初始化相機：$error';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Golf Score App',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1E8E5A)),
        scaffoldBackgroundColor: const Color(0xFFF5F7FB),
        useMaterial3: true,
      ),
      home: _buildHome(),
      routes: {
        '/home': (context) => HomePage(cameras: _cameras),
        '/login': (context) => LoginPage(cameras: _cameras),
      },
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

        if (_isLoading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (_cameraError != null) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _cameraError!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 16, color: Colors.redAccent),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _reloadCameras,
                      child: const Text('重新嘗試'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        // 如果有登入token，進入首頁；否則進入登錄頁
        if (snapshot.data == true) {
          return HomePage(cameras: _cameras);
        }

        return LoginPage(cameras: _cameras);
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
