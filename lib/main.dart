import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'pages/login_page.dart';

Future<void> main() async {
  // 先初始化 Flutter 綁定，避免在呼叫可用鏡頭前發生錯誤
  WidgetsFlutterBinding.ensureInitialized();

  List<CameraDescription> cameras = const <CameraDescription>[];
  String? cameraError;

  try {
    cameras = await availableCameras();
  } catch (error) {
    cameraError = '無法初始化相機：$error';
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
      title: 'Golf App',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1E8E5A)),
        scaffoldBackgroundColor: const Color(0xFFF5F7FB),
        useMaterial3: true,
      ),
      home: _buildHome(),
    );
  }

  /// 依照載入狀態顯示登入頁、錯誤提示或載入指示
  Widget _buildHome() {
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

    return LoginPage(cameras: _cameras);
  }
}
