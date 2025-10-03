import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_audio_capture/flutter_audio_capture.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:assets_audio_player/assets_audio_player.dart';
import 'package:video_player/video_player.dart';

/// 錄影頁面負責串接鏡頭、音訊偵測與檔案儲存
class RecorderPage extends StatefulWidget {
  final List<CameraDescription> cameras; // 傳入所有可用鏡頭

  const RecorderPage({super.key, required this.cameras});

  @override
  State<RecorderPage> createState() => _RecorderPageState();
}

class _RecorderPageState extends State<RecorderPage> {
  // ---------- 狀態變數區 ----------
  CameraController? controller; // 控制鏡頭操作
  bool isRecording = false; // 標記是否正在錄影
  List<double> waveform = []; // 即時波形資料
  List<double> waveformAccumulated = []; // 累積波形資料供繪圖使用
  double score = 0; // 音訊分析結果（目前保留原邏輯）
  final ValueNotifier<int> repaintNotifier = ValueNotifier(0); // 用於觸發波形重繪

  final FlutterAudioCapture _audioCapture = FlutterAudioCapture(); // 音訊擷取工具
  ReceivePort? _receivePort; // 與 Isolate 溝通的管道
  late Isolate _isolate; // 處理音訊的背景執行緒

  final AssetsAudioPlayer _audioPlayer = AssetsAudioPlayer(); // 播放倒數音效
  final MethodChannel _volumeChannel = const MethodChannel('volume_button_channel'); // 監聽音量鍵
  bool _isCountingDown = false; // 避免倒數重複觸發

  final FlutterBluePlus _bluetooth = FlutterBluePlus.instance; // 管理藍牙掃描與連線
  StreamSubscription<List<ScanResult>>? _scanSubscription; // 藍牙掃描訂閱
  StreamSubscription<BluetoothAdapterState>? _adapterStateSubscription; // 藍牙狀態監聽
  StreamSubscription<BluetoothConnectionState>? _deviceConnectionSubscription; // 裝置連線狀態監聽

  BluetoothAdapterState _adapterState = BluetoothAdapterState.unknown; // 目前藍牙狀態
  BluetoothDevice? _foundDevice; // 已搜尋到的目標 IMU 裝置
  BluetoothDevice? _connectedDevice; // 已成功連線的 IMU 裝置
  BluetoothConnectionState _connectionState = BluetoothConnectionState.disconnected; // IMU 連線狀態

  bool _isScanning = false; // 是否正在搜尋裝置
  bool _isConnecting = false; // 是否正處於連線流程
  String _connectionMessage = '尚未搜尋到 IMU 裝置'; // 顯示於 UI 的狀態文字
  int? _lastRssi; // 紀錄訊號強度供顯示
  String? _foundDeviceName; // 掃描到的裝置名稱
  final String _targetNameKeyword = 'TekSwing-IMU'; // 目標裝置名稱關鍵字
  final String _mockBatteryLevel = '82%'; // 假資料電量資訊
  final String _mockFirmwareVersion = '韌體 1.0.3'; // 假資料韌體版本

  // ---------- 生命週期 ----------
  @override
  void initState() {
    super.initState();
    init(); // 啟動鏡頭權限與初始化
    initVolumeKeyListener(); // 設定音量鍵快速啟動
    initBluetooth(); // 準備藍牙配對流程
  }

  @override
  void dispose() {
    controller?.dispose();
    _audioCapture.stop();
    _receivePort?.close();
    _isolate.kill(priority: Isolate.immediate);
    _audioPlayer.dispose();
    _scanSubscription?.cancel();
    _adapterStateSubscription?.cancel();
    _deviceConnectionSubscription?.cancel();
    _bluetooth.stopScan();
    super.dispose();
  }

  // ---------- 初始化流程 ----------
  /// 申請必要權限並初始化相機控制器
  Future<void> init() async {
    await Permission.camera.request();
    await Permission.microphone.request();
    await Permission.storage.request();

    controller = CameraController(
      widget.cameras.first,
      ResolutionPreset.medium,
    );
    await controller!.initialize();
    if (!mounted) return;
    setState(() {}); // 更新畫面顯示預覽
  }

  /// 建立音量鍵監聽器，讓使用者快速啟動錄影
  void initVolumeKeyListener() {
    _volumeChannel.setMethodCallHandler((call) async {
      if (call.method == 'volume_down') {
        if (!_isCountingDown && !isRecording) {
          _isCountingDown = true;
          await playCountdownAndStart();
          _isCountingDown = false;
        }
      }
    });
  }

  /// 初始化音訊擷取並將資料傳入獨立 Isolate
  Future<void> initAudioCapture() async {
    try {
      _receivePort = ReceivePort();
      _receivePort!.listen((data) {
        if (data is List<double>) {
          waveform = data;
          waveformAccumulated.addAll(data);

          // 計算音訊資訊以更新得分，保留原有邏輯以利後續擴充
          final double avg =
              waveform.fold(0.0, (prev, el) => prev + el.abs()) / waveform.length;
          final double stdev = math.sqrt(
            waveform
                    .map((e) => math.pow(e.abs() - avg, 2))
                    .reduce((a, b) => a + b) /
                waveform.length,
          );
          final double focus = avg / (stdev + 1e-6);
          score = (focus / (focus + 1)).clamp(0.0, 1.0);

          repaintNotifier.value++; // 通知波形重繪
        }
      });
      _isolate = await Isolate.spawn(
        _audioProcessingIsolate,
        _receivePort!.sendPort,
      );
      await _audioCapture.init();
      await _audioCapture.start(
        (data) => _receivePort?.sendPort.send(
          List<double>.from((data as List).map((e) => e as double)),
        ),
        onError,
        sampleRate: 22050,
        bufferSize: 512,
      );
    } catch (e) {
      debugPrint('🎙️ 初始化失敗: $e');
      rethrow;
    }
  }

  /// 初始化藍牙狀態與權限，確保錄影前完成 IMU 配對
  Future<void> initBluetooth() async {
    await _requestBluetoothPermissions();

    _adapterStateSubscription = _bluetooth.state.listen((state) {
      if (!mounted) return;
      setState(() {
        _adapterState = state;
        if (state == BluetoothAdapterState.off) {
          _connectedDevice = null;
          _connectionState = BluetoothConnectionState.disconnected;
          _connectionMessage = '請開啟藍牙以搜尋裝置';
        }
      });

      if (state == BluetoothAdapterState.on && !isImuConnected && !_isScanning && !_isConnecting) {
        scanForImu();
      }
    });

    final initialState = await _bluetooth.state.first;
    if (!mounted) return;
    setState(() => _adapterState = initialState);

    final connectedDevices = await _bluetooth.connectedDevices;
    if (!mounted) return;

    for (final device in connectedDevices) {
      if (_matchTarget(device.platformName)) {
        _connectedDevice = device;
        _listenConnectionState(device);
        setState(() {
          _connectionState = BluetoothConnectionState.connected;
          _connectionMessage = '已連線至 ${_resolveDeviceName(device)}';
        });
        return;
      }
    }

    if (initialState == BluetoothAdapterState.on) {
      await scanForImu();
    } else {
      setState(() {
        _connectionMessage = '請先開啟藍牙功能後再開始搜尋';
      });
    }
  }

  /// 申請藍牙與定位權限，避免掃描過程被拒
  Future<void> _requestBluetoothPermissions() async {
    await Permission.bluetooth.request();
    await Permission.bluetoothScan.request();
    await Permission.bluetoothConnect.request();
    await Permission.locationWhenInUse.request();
  }

  /// 掃描 TekSwing IMU 裝置並更新顯示資訊
  Future<void> scanForImu() async {
    await _scanSubscription?.cancel();
    await _bluetooth.stopScan();

    if (!mounted) return;
    setState(() {
      _isScanning = true;
      _foundDevice = null;
      _foundDeviceName = null;
      _lastRssi = null;
      _connectionMessage = '搜尋 $_targetNameKeyword 裝置中...';
    });

    _scanSubscription = _bluetooth.scanResults.listen((results) {
      if (!mounted || _foundDevice != null) {
        return;
      }

      for (final result in results) {
        final advertisementName = result.advertisementData.advName;
        final deviceName = result.device.platformName;
        final displayName = deviceName.isNotEmpty
            ? deviceName
            : (advertisementName.isNotEmpty ? advertisementName : _targetNameKeyword);

        if (_matchTarget(displayName)) {
          setState(() {
            _foundDevice = result.device;
            _foundDeviceName = displayName;
            _lastRssi = result.rssi;
            _connectionMessage = '找到 $displayName，可進行配對';
          });
          _bluetooth.stopScan();
          break;
        }
      }
    }, onError: (error) {
      if (!mounted) return;
      setState(() {
        _connectionMessage = '搜尋失敗，請確認藍牙權限狀態';
      });
    });

    try {
      await _bluetooth.startScan(timeout: const Duration(seconds: 8));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _connectionMessage = '無法開始掃描：$e';
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _isScanning = false;
      });
    }
  }

  /// 嘗試連線到掃描到的 IMU 裝置
  Future<void> connectToImu() async {
    final target = _foundDevice ?? _connectedDevice;
    if (target == null) {
      await scanForImu();
      return;
    }

    await _bluetooth.stopScan();

    setState(() {
      _isConnecting = true;
      _connectionMessage = '正在連線 ${_foundDeviceName ?? _resolveDeviceName(target)}...';
    });

    try {
      await target.connect(timeout: const Duration(seconds: 10));
      _connectedDevice = target;
      _listenConnectionState(target);
      if (!mounted) return;
      setState(() {
        _connectionMessage = '已連線至 ${_resolveDeviceName(target)}';
      });
    } catch (e) {
      if (!mounted) return;
      if (e.toString().toLowerCase().contains('already')) {
        _connectedDevice = target;
        _listenConnectionState(target);
        setState(() {
          _connectionMessage = '裝置已連線，可開始錄影';
        });
      } else {
        setState(() {
          _connectionMessage = '連線失敗，請重新嘗試';
        });
      }
    } finally {
      if (!mounted) return;
      setState(() {
        _isConnecting = false;
      });
    }
  }

  /// 監聽裝置連線狀態，若中斷則重新搜尋
  void _listenConnectionState(BluetoothDevice device) {
    _deviceConnectionSubscription?.cancel();
    _deviceConnectionSubscription = device.connectionState.listen((state) {
      if (!mounted) return;
      setState(() {
        _connectionState = state;
        if (state == BluetoothConnectionState.connected) {
          _connectedDevice = device;
          _connectionMessage = '已連線至 ${_resolveDeviceName(device)}';
        } else if (state == BluetoothConnectionState.disconnected) {
          _connectedDevice = null;
          _connectionMessage = '裝置已斷線，正在重新搜尋';
        }
      });

      if (state == BluetoothConnectionState.disconnected) {
        scanForImu();
      }
    });
  }

  /// 判斷目前是否已建立 IMU 連線
  bool get isImuConnected =>
      _connectedDevice != null && _connectionState == BluetoothConnectionState.connected;

  /// 根據裝置資訊推算顯示名稱
  String _resolveDeviceName(BluetoothDevice device) {
    if (device.platformName.isNotEmpty) {
      return device.platformName;
    }
    return device.remoteId.str;
  }

  /// 比對字串是否符合目標關鍵字
  bool _matchTarget(String name) => name.contains(_targetNameKeyword);

  // ---------- 方法區 ----------
  /// 播放倒數音效並等待音檔結束
  Future<void> _playCountdown() async {
    await _audioPlayer.open(
      Audio('assets/sounds/1.mp3'),
      autoStart: true,
      showNotification: false,
    );
    await _audioPlayer.playlistFinished.first;
  }

  /// 進行一次錄影流程（倒數 -> 錄影 -> 儲存）
  Future<void> _recordOnce(int index) async {
    try {
      waveformAccumulated.clear();
      await initAudioCapture();
      await controller!.startVideoRecording();

      await Future.delayed(const Duration(seconds: 15));

      final XFile videoFile = await controller!.stopVideoRecording();
      await _audioCapture.stop();
      _receivePort?.close();
      _isolate.kill(priority: Isolate.immediate);

      final directory = Directory('/storage/emulated/0/Download');
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final newPath = '${directory.path}/run_${index + 1}_$timestamp.mp4';
      await File(videoFile.path).copy(newPath);
      debugPrint('✅ 儲存為 run_${index + 1}_$timestamp.mp4');
    } catch (e) {
      debugPrint('❌ 錄影時出錯：$e');
    }
  }

  /// 按一次後自動執行五次倒數與錄影，中間保留休息時間
  Future<void> playCountdownAndStart() async {
    if (!isImuConnected) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請先連線 TekSwing IMU 裝置後再開始錄影')),
      );
      return;
    }

    setState(() => isRecording = true);
    for (int i = 0; i < 5; i++) {
      if (i == 1) {
        await Future.delayed(const Duration(seconds: 8));
      }
      await _playCountdown();
      await Future.delayed(const Duration(seconds: 3));
      await _recordOnce(i);
      if (i < 4) {
        await Future.delayed(const Duration(seconds: 10));
      }
    }
    setState(() => isRecording = false);
  }

  /// 讓使用者自選影片並播放
  Future<void> pickAndPlayVideo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      initialDirectory: '/storage/emulated/0/Download',
    );

    if (!mounted) return;

    if (result != null && result.files.single.path != null) {
      final filePath = result.files.single.path!;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => VideoPlayerPage(videoPath: filePath)),
      );
    }
  }

  /// 音訊處理的 Isolate 主體（保留為預留擴充）
  static void _audioProcessingIsolate(SendPort sendPort) {}

  /// 音訊擷取錯誤處理
  void onError(Object e) {
    debugPrint('❌ Audio Capture Error: $e');
  }

  // ---------- UI 建構區 ----------
  /// 建構 IMU 連線卡片，提示使用者完成藍牙配對
  Widget _buildImuConnectionCard() {
    final bool connected = isImuConnected;
    final String displayName = connected
        ? _resolveDeviceName(_connectedDevice!)
        : (_foundDeviceName ?? 'TekSwing-IMU-A12');
    final String signalText = _lastRssi != null ? '訊號 ${_lastRssi} dBm' : '訊號偵測中';

    final Color statusColor = connected
        ? const Color(0xFF1E8E5A)
        : (_adapterState == BluetoothAdapterState.on
            ? const Color(0xFF7D8B9A)
            : const Color(0xFFD9534F));

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 14, offset: Offset(0, 6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '連線裝置（自動對設備配對）',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF123B70),
                ),
              ),
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF1E8E5A), width: 2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF123B70), Color(0xFF1E8E5A)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: const Icon(Icons.sports_golf, color: Colors.white, size: 34),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E1E1E),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '電量 $_mockBatteryLevel · $_mockFirmwareVersion',
                      style: const TextStyle(fontSize: 13, color: Color(0xFF7D8B9A)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _connectionMessage,
                      style: TextStyle(fontSize: 13, color: statusColor, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      signalText,
                      style: const TextStyle(fontSize: 12, color: Color(0xFF9AA8B6)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: connected || _isConnecting ? null : connectToImu,
                style: FilledButton.styleFrom(
                  backgroundColor: connected ? const Color(0xFF1E8E5A) : const Color(0xFF123B70),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                ),
                child: _isConnecting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                      )
                    : Text(
                        connected ? '已連線' : (_foundDevice != null ? '配對裝置' : '搜尋中'),
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _isScanning ? null : scanForImu,
                icon: Icon(
                  _isScanning ? Icons.hourglass_empty : Icons.sync,
                  color: const Color(0xFF123B70),
                ),
                label: Text(
                  _isScanning ? '掃描中' : '重新搜尋',
                  style: const TextStyle(color: Color(0xFF123B70)),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF123B70)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
              const SizedBox(width: 12),
              if (!connected)
                Expanded(
                  child: Text(
                    '裝置需先完成配對，錄影按鈕才會解鎖。',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF7D8B9A)),
                    textAlign: TextAlign.right,
                  ),
                )
              else
                const Expanded(
                  child: Text(
                    '裝置已就緒，可以開始錄影流程。',
                    style: TextStyle(fontSize: 12, color: Color(0xFF1E8E5A)),
                    textAlign: TextAlign.right,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (controller == null || !controller!.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Golf Recorder')),
      body: Column(
        children: [
          _buildImuConnectionCard(),
          Expanded(
            child: Stack(
              children: [
                Column(
                  children: [
                    Expanded(child: CameraPreview(controller!)),
                    SizedBox(
                      height: 200,
                      width: double.infinity,
                      child: WaveformWidget(
                        waveformAccumulated: List.from(waveformAccumulated),
                        repaintNotifier: repaintNotifier,
                      ),
                    ),
                  ],
                ),
                Positioned(
                  bottom: 20,
                  right: 20,
                  child: ElevatedButton(
                    onPressed: isRecording || !isImuConnected ? null : playCountdownAndStart,
                    child: Text(
                      isRecording
                          ? '錄製中...'
                          : (isImuConnected ? '開始錄製' : '請先配對 IMU'),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 20,
                  left: 20,
                  child: ElevatedButton(
                    onPressed: pickAndPlayVideo,
                    child: const Text('播放影片'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 用於顯示波形的 Widget，接收累積資料並觸發重繪
class WaveformWidget extends StatelessWidget {
  final List<double> waveformAccumulated; // 波形資料來源
  final ValueNotifier<int> repaintNotifier; // 外部通知刷新

  const WaveformWidget({
    super.key,
    required this.waveformAccumulated,
    required this.repaintNotifier,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: repaintNotifier,
      builder: (context, value, child) {
        return CustomPaint(
          size: Size.infinite,
          painter: WaveformPainter(List.from(waveformAccumulated)),
        );
      },
    );
  }
}

/// 自訂波形畫家，將音訊振幅轉成畫面線條
class WaveformPainter extends CustomPainter {
  final List<double> waveform;
  WaveformPainter(this.waveform);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.blue
      ..strokeWidth = 1.0;

    if (waveform.isEmpty) return;

    final double middle = size.height / 2;
    final int maxSamples = size.width.toInt();
    final int skip = waveform.length ~/ maxSamples;
    if (skip == 0) return;

    for (int i = 0; i < maxSamples; i++) {
      final int idx = i * skip;
      if (idx >= waveform.length) break;
      final double x = i.toDouble();
      final double y = middle - waveform[idx] * 500;
      canvas.drawLine(Offset(x, middle), Offset(x, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

/// 影片播放頁面，提供錄製檔案的立即檢視
class VideoPlayerPage extends StatefulWidget {
  final String videoPath; // 影片檔案路徑
  const VideoPlayerPage({super.key, required this.videoPath});

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  late VideoPlayerController _videoController;

  @override
  void initState() {
    super.initState();
    _videoController = VideoPlayerController.file(File(widget.videoPath))
      ..initialize().then((_) {
        setState(() {});
        _videoController.play();
      });
  }

  @override
  void dispose() {
    _videoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('影片播放')),
      body: Center(
        child: _videoController.value.isInitialized
            ? AspectRatio(
                aspectRatio: _videoController.value.aspectRatio,
                child: VideoPlayer(_videoController),
              )
            : const CircularProgressIndicator(),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          setState(() {
            _videoController.value.isPlaying
                ? _videoController.pause()
                : _videoController.play();
          });
        },
        child: Icon(
          _videoController.value.isPlaying ? Icons.pause : Icons.play_arrow,
        ),
      ),
    );
  }
}
