import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'pages/login_page.dart';

Future<void> main() async {
  // 先初始化 Flutter 綁定，確保後續相機與路徑等原生功能可正常呼叫
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

/// 應用程式入口：改為 StatefulWidget 以確保相機初始化錯誤時可回報訊息
class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  // ---------- 狀態管理區 ----------
  List<CameraDescription>? _cameras; // 成功初始化後的相機清單
  String? _cameraError; // 初始化失敗時的錯誤訊息

  @override
  void initState() {
    super.initState();
    _loadCameras();
  }

  // ---------- 方法區 ----------
  /// 非同步載入相機清單，並妥善處理可能的例外狀況
  Future<void> _loadCameras() async {
    try {
      final cameras = await availableCameras();
      if (!mounted) return; // 避免 Widget 已卸載時仍嘗試更新 UI
      setState(() {
        _cameras = cameras;
        _cameraError = null;
      });
    } catch (error) {
      // 記錄錯誤訊息以便顯示於畫面，避免直接崩潰
      if (!mounted) return;
      setState(() {
        _cameraError = '無法初始化相機：$error';
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

  /// 依據目前狀態決定要顯示登入頁、載入指示或錯誤提示
  Widget _buildHome() {
    if (_cameraError != null) {
      // 顯示錯誤畫面並提供重新嘗試按鈕，讓使用者可手動重試
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
                  onPressed: _loadCameras,
                  child: const Text('重新嘗試'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final cameras = _cameras;
    if (cameras == null) {
      // 相機仍在初始化時顯示簡單的載入指示，避免黑畫面
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return LoginPage(cameras: cameras);
  }
}
