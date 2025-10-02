import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_audio_capture/flutter_audio_capture.dart';
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

  // ---------- 生命週期 ----------
  @override
  void initState() {
    super.initState();
    init(); // 啟動鏡頭權限與初始化
    initVolumeKeyListener(); // 設定音量鍵快速啟動
  }

  @override
  void dispose() {
    controller?.dispose();
    _audioCapture.stop();
    _receivePort?.close();
    _isolate.kill(priority: Isolate.immediate);
    _audioPlayer.dispose();
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
  @override
  Widget build(BuildContext context) {
    if (controller == null || !controller!.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Golf Recorder')),
      body: Stack(
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
              onPressed: isRecording ? null : playCountdownAndStart,
              child: Text(isRecording ? '錄製中...' : '開始錄製'),
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
