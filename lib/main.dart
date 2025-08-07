import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_audio_capture/flutter_audio_capture.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:developer';
import 'dart:math' as math;
import 'package:file_picker/file_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:assets_audio_player/assets_audio_player.dart';
import 'package:flutter/services.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  runApp(MyApp(cameras: cameras));
}

class MyApp extends StatelessWidget {
  final List<CameraDescription> cameras;
  const MyApp({super.key, required this.cameras});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Golf App',
      home: RecorderPage(cameras: cameras),
    );
  }
}

class RecorderPage extends StatefulWidget {
  final List<CameraDescription> cameras;
  const RecorderPage({super.key, required this.cameras});

  @override
  State<RecorderPage> createState() => _RecorderPageState();
}

class _RecorderPageState extends State<RecorderPage> {
  CameraController? controller;
  bool isRecording = false;
  double maxDb = -160;
  List<double> waveform = [];
  List<double> waveformAccumulated = [];
  double score = 0;
  final ValueNotifier<int> repaintNotifier = ValueNotifier(0);

  final FlutterAudioCapture _audioCapture = FlutterAudioCapture();
  late Isolate _isolate;
  ReceivePort? _receivePort;

  //StreamSubscription? volumeButtonListener;
  final AssetsAudioPlayer _audioPlayer = AssetsAudioPlayer();
  final MethodChannel _volumeChannel = MethodChannel('volume_button_channel');
  bool _isCountingDown = false;

  @override
  void initState() {
    super.initState();
    init();
    initVolumeKeyListener();
  }


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


  /// 播放倒數音檔並等待播放完成
  Future<void> _playCountdown() async {
    await _audioPlayer.open(
      Audio('assets/sounds/1.mp3'),
      autoStart: true,
      showNotification: false,
    );
    // 監聽播放完成事件，確保倒數音檔播放完畢
    await _audioPlayer.playlistFinished.first;
  }

  /// 進行單次錄影流程
  Future<void> _recordOnce(int index) async {
    try {
      waveformAccumulated.clear();
      await initAudioCapture();
      await controller!.startVideoRecording();

      // 預設錄影 6 秒
      await Future.delayed(Duration(seconds: 6));

      final XFile videoFile = await controller!.stopVideoRecording();
      await _audioCapture.stop();
      _receivePort?.close();
      _isolate.kill(priority: Isolate.immediate);

      // 以 run 序號與時間戳作為檔名
      final directory = Directory('/storage/emulated/0/Download');
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final newPath = '${directory.path}/run_${index + 1}_$timestamp.mp4';
      await File(videoFile.path).copy(newPath);
      print('✅ 儲存為 run_${index + 1}_$timestamp.mp4');
    } catch (e) {
      print('❌ 錄影時出錯：$e');
    }
  }

  /// 按一次後自動執行五次倒數與錄影
  Future<void> playCountdownAndStart() async {
    setState(() => isRecording = true);
    for (int i = 0; i < 5; i++) {
      // 倒數音檔播放完畢後才開始錄影
      await _playCountdown();
      await _recordOnce(i);
    }
    setState(() => isRecording = false);
  }

  Future<void> pickAndPlayVideo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      initialDirectory: '/storage/emulated/0/Download',
    );

    if (result != null && result.files.single.path != null) {
      final filePath = result.files.single.path!;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => VideoPlayerPage(videoPath: filePath),
        ),
      );
    }
  }






  Future<void> init() async {
    await Permission.camera.request();
    await Permission.microphone.request();
    await Permission.storage.request();

    controller = CameraController(widget.cameras.first, ResolutionPreset.medium);
    await controller!.initialize();
    setState(() {});
  }

  Future<void> initAudioCapture() async {
    try {
      _receivePort = ReceivePort();
      _receivePort!.listen((data) {
        if (data is List<double>) {
          waveform = data;
          waveformAccumulated.addAll(data);

          final double avg = waveform.fold(0.0, (prev, el) => prev + el.abs()) / waveform.length;
          final double stdev = math.sqrt(waveform.map((e) => math.pow(e.abs() - avg, 2)).reduce((a, b) => a + b) / waveform.length);
          final double focus = avg / (stdev + 1e-6);
          score = (focus / (focus + 1)).clamp(0.0, 1.0);

          repaintNotifier.value++;
        }
      });
      _isolate = await Isolate.spawn(_audioProcessingIsolate, _receivePort!.sendPort);
      await _audioCapture.init();
      await _audioCapture.start(
        (data) => _receivePort?.sendPort.send(List<double>.from((data as List).map((e) => e as double))),
        onError,
        sampleRate: 22050,
        bufferSize: 512,
      );
    } catch (e) {
      log('🎙️ 初始化失敗: $e');
      rethrow;
    }
  }
Map<String, dynamic> analyzeCrispness(List<double> data, int sampleRate) {
    final frameSize = (0.1 * sampleRate).toInt(); // 每100ms
    final hopSize = frameSize;

    double maxScore = 0;
    int maxIndex = 0;

    for (int i = 0; i + frameSize <= data.length; i += hopSize) {
      final frame = data.sublist(i, i + frameSize);

      // 計算 Zero Crossing Rate
      int zeroCross = 0;
      for (int j = 1; j < frame.length; j++) {
        if ((frame[j - 1] >= 0 && frame[j] < 0) ||
            (frame[j - 1] < 0 && frame[j] >= 0)) {
          zeroCross++;
        }
      }

      final zcr = zeroCross / frameSize;
      if (zcr > maxScore) {
        maxScore = zcr;
        maxIndex = i;
      }
    }
  
  double bestTime = maxIndex / sampleRate;

  return {
    'score': (maxScore * 10).clamp(0.0, 10.0),
    'timestamp': bestTime
  };
}


  static void _audioProcessingIsolate(SendPort sendPort) {}

  void onError(Object e) {
    log("❌ Audio Capture Error: $e");
  }
  // 原本的 start/stop 流程已整合至 _recordOnce

  @override
  void dispose() {
    controller?.dispose();
    _audioCapture.stop();
    _receivePort?.close();
    _isolate.kill(priority: Isolate.immediate);
    super.dispose();
    _audioPlayer.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (controller == null || !controller!.value.isInitialized) {
      return Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: Text('Golf Recorder')),
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
                // 移除結束評分顯示
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
              child: Text('播放影片'),
            ),
          ),
        ],
      ),
    );
  }
}

class WaveformWidget extends StatelessWidget {
  final List<double> waveformAccumulated;
  final ValueNotifier<int> repaintNotifier;
  const WaveformWidget({super.key, required this.waveformAccumulated, required this.repaintNotifier});

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

class VideoPlayerPage extends StatefulWidget {
  final String videoPath;
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
      appBar: AppBar(title: Text('影片播放')),
      body: Center(
        child: _videoController.value.isInitialized
            ? AspectRatio(
                aspectRatio: _videoController.value.aspectRatio,
                child: VideoPlayer(_videoController),
              )
            : CircularProgressIndicator(),
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