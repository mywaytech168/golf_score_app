import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:assets_audio_player/assets_audio_player.dart';
import 'package:camera/camera.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_audio_capture/flutter_audio_capture.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:video_player/video_player.dart';
import 'package:share_plus/share_plus.dart';

import '../models/recording_history_entry.dart';
import '../widgets/recording_history_sheet.dart';
import '../services/imu_data_logger.dart';

// ---------- 分享頻道設定 ----------
const MethodChannel _shareChannel = MethodChannel('share_intent_channel');

// ---------- 分享目標列舉 ----------
enum _ShareTarget { instagram, facebook, line }

/// 錄影專用頁面：專注鏡頭預覽、倒數與音訊波形，與 IMU 配對頁面分離
class RecordingSessionPage extends StatefulWidget {
  final List<CameraDescription> cameras; // 傳入所有可用鏡頭
  final bool isImuConnected; // 是否已配對 IMU，決定提示訊息
  final int totalRounds; // 本次預計錄影的輪數
  final int durationSeconds; // 每輪錄影秒數
  final bool autoStartOnReady; // 由 IMU 按鈕開啟時自動啟動錄影
  final Stream<void> imuButtonStream; // 右手腕 IMU 按鈕事件來源

  const RecordingSessionPage({
    super.key,
    required this.cameras,
    required this.isImuConnected,
    required this.totalRounds,
    required this.durationSeconds,
    required this.autoStartOnReady,
    required this.imuButtonStream,
  });

  @override
  State<RecordingSessionPage> createState() => _RecordingSessionPageState();
}

class _RecordingSessionPageState extends State<RecordingSessionPage> {
  // ---------- 狀態變數區 ----------
  CameraController? controller; // 控制鏡頭操作
  double? _previewAspectRatio; // 記錄初始化時的預覽比例，避免錄影時變動
  bool isRecording = false; // 標記是否正在錄影
  List<double> waveform = []; // 即時波形資料
  List<double> waveformAccumulated = []; // 累積波形資料供繪圖使用
  final ValueNotifier<int> repaintNotifier = ValueNotifier(0); // 用於觸發波形重繪

  final FlutterAudioCapture _audioCapture = FlutterAudioCapture(); // 音訊擷取工具
  ReceivePort? _receivePort; // 與 Isolate 溝通的管道
  Isolate? _isolate; // 處理音訊的背景執行緒，可能尚未建立

  final AssetsAudioPlayer _audioPlayer = AssetsAudioPlayer(); // 播放倒數音效
  final MethodChannel _volumeChannel = const MethodChannel('volume_button_channel'); // 監聽音量鍵
  bool _isCountingDown = false; // 避免倒數重複觸發
  bool _shouldCancelRecording = false; // 控制流程是否應該中斷
  Completer<void>? _cancelCompleter; // 將取消訊號傳遞給等待中的 Future
  static const int _restSecondsBetweenRounds = 10; // 每輪錄影間預設的休息秒數
  final List<RecordingHistoryEntry> _recordedRuns = []; // 累積此次錄影產生的檔案
  bool _hasTriggeredRecording = false; // 記錄使用者是否啟動過錄影，控制按鈕提示
  StreamSubscription<void>? _imuButtonSubscription; // 監聽 IMU 按鈕觸發錄影
  bool _pendingAutoStart = false; // 記錄 IMU 事件是否需等待鏡頭初始化後再啟動

  // ---------- 生命週期 ----------
  @override
  void initState() {
    super.initState();
    initVolumeKeyListener(); // 建立音量鍵快捷鍵
    _prepareSession(); // 非同步初始化鏡頭，等待使用者手動啟動
    _pendingAutoStart = widget.autoStartOnReady; // 若由 IMU 開啟則在鏡頭就緒後自動啟動
    // 監聽 IMU 按鈕事件，隨時可從硬體直接觸發錄影
    _imuButtonSubscription = widget.imuButtonStream.listen((_) {
      unawaited(_handleImuButtonTrigger());
    });
  }

  @override
  void dispose() {
    _triggerCancel(); // 優先發出取消訊號，停止所有倒數與錄影
    _stopActiveRecording(updateUi: false); // 嘗試停止仍在進行的錄影與音訊擷取
    controller?.dispose();
    _volumeChannel.setMethodCallHandler(null); // 解除音量鍵監聽，避免重複綁定
    _audioPlayer.dispose();
    _imuButtonSubscription?.cancel(); // 解除 IMU 按鈕監聽，避免資源洩漏
    super.dispose();
  }

  // ---------- 初始化流程 ----------
  /// 初始化鏡頭與權限，僅建立預覽等待使用者手動啟動錄影
  Future<void> _prepareSession() async {
    await Permission.camera.request();
    await Permission.microphone.request();
    await Permission.storage.request();

    if (widget.cameras.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('沒有可用鏡頭，無法啟動錄影。')),
      );
      return;
    }

    // 依序測試從最高到較低的解析度，找到裝置可支援的最佳錄影規格
    final _CameraSelectionResult? selection =
        await _createBestCameraController(widget.cameras.first);

    if (selection == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('無法初始化鏡頭，請稍後再試。')),
      );
      return;
    }

    controller = selection.controller;
    _previewAspectRatio = selection.previewSize != null
        ? selection.previewSize!.width / selection.previewSize!.height
        : controller!.value.aspectRatio;
    if (kDebugMode) {
      // 藉由除錯訊息確認實際採用的解析度（部分平台無法回報幀率）
      debugPrint(
        'Camera initialized with preset ${selection.preset}, size=${selection.previewSize ?? '未知'}',
      );
    }
    if (!mounted) return;
    setState(() {}); // 更新畫面顯示預覽

    if (_pendingAutoStart) {
      // 鏡頭就緒後若先前已有硬體按鈕請求，立即啟動倒數錄影
      _pendingAutoStart = false;
      unawaited(_handleImuButtonTrigger());
    }
  }

  /// 針對指定鏡頭，嘗試使用最高可支援的解析度與幀率進行初始化
  Future<_CameraSelectionResult?> _createBestCameraController(
      CameraDescription description) async {
    // 解析度優先順序：依照套件提供的列舉，由高至低逐一嘗試
    const List<ResolutionPreset> presetPriority = <ResolutionPreset>[
      ResolutionPreset.max,
      ResolutionPreset.ultraHigh,
      ResolutionPreset.veryHigh,
      ResolutionPreset.high,
      ResolutionPreset.medium,
      ResolutionPreset.low,
    ];

    for (final ResolutionPreset preset in presetPriority) {
      final CameraController testController = CameraController(
        description,
        preset,
        enableAudio: true,
      );

      try {
        await testController.initialize();

        // 嘗試讀取預覽資訊，若特定平台未提供則以 null 代表未知
        Size? previewSize;
        try {
          previewSize = testController.value.previewSize;
        } catch (_) {
          previewSize = null;
        }

        return _CameraSelectionResult(
          controller: testController,
          preset: preset,
          previewSize: previewSize,
        );
      } catch (_) {
        await testController.dispose();
      }
    }

    return null;
  }

  /// 建立固定比例的預覽畫面，避免錄影時鏡頭切換解析度導致畫面跳動
  Widget _buildStablePreview() {
    if (controller == null || !controller!.value.isInitialized) {
      return const SizedBox.shrink();
    }

    final double aspectRatio =
        _previewAspectRatio ?? controller!.value.aspectRatio;

    return Center(
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: ClipRect(
          child: controller!.buildPreview(),
        ),
      ),
    );
  }

  /// 建立音量鍵監聽器，讓使用者快速啟動錄影
  void initVolumeKeyListener() {
    _volumeChannel.setMethodCallHandler((call) async {
      if (call.method == 'volume_down') {
        if (!_isCountingDown && !isRecording && controller != null && controller!.value.isInitialized) {
          _isCountingDown = true;
          try {
            await playCountdownAndStart();
          } finally {
            _isCountingDown = false;
          }
        }
      }
    });
  }

  /// 由 IMU 按鈕觸發錄影，統一檢查鏡頭與倒數狀態
  Future<void> _handleImuButtonTrigger() async {
    if (!mounted) {
      return;
    }
    if (controller == null || !controller!.value.isInitialized) {
      // 鏡頭尚未準備完成，保留旗標待完成初始化後再自動啟動
      _pendingAutoStart = true;
      return;
    }
    if (_isCountingDown || isRecording) {
      return; // 已在倒數或錄影中則忽略額外事件
    }

    _isCountingDown = true; // 鎖定狀態避免連續觸發
    try {
      await playCountdownAndStart();
    } finally {
      _isCountingDown = false;
    }
  }

  /// 發送取消錄影訊號，讓倒數與錄影流程可以即時中斷
  void _triggerCancel() {
    _shouldCancelRecording = true;
    if (_cancelCompleter != null && !_cancelCompleter!.isCompleted) {
      _cancelCompleter!.complete();
    }
  }

  /// 主動停止鏡頭錄影與音訊擷取，確保返回上一頁後不再持續錄製
  Future<void> _stopActiveRecording({bool updateUi = true}) async {
    if (!isRecording && !_isCountingDown && controller != null && !(controller!.value.isRecordingVideo)) {
      return; // 若沒有任何錄影流程在進行，可直接返回
    }

    try {
      await _audioPlayer.stop();
    } catch (_) {
      // 音檔可能尚未播放完成，忽略停止時的錯誤
    }

    if (controller != null && controller!.value.isRecordingVideo) {
      try {
        await controller!.stopVideoRecording();
      } catch (_) {
        // 若已停止或尚未開始錄影，忽略錯誤
      }
    }

    await _closeAudioPipeline();

    if (ImuDataLogger.instance.hasActiveRound) {
      await ImuDataLogger.instance.abortActiveRound();
    }

    if (mounted && updateUi) {
      setState(() => isRecording = false);
    } else {
      isRecording = false;
    }
  }

  /// 停止音訊擷取並回收相關資源，確保下次錄影前狀態乾淨
  Future<void> _closeAudioPipeline() async {
    try {
      await _audioCapture.stop();
    } catch (_) {
      // 可能尚未成功啟動音訊擷取，忽略錯誤避免阻斷流程
    }
    _receivePort?.close();
    _receivePort = null;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
  }

  /// 初始化音訊擷取並將資料傳入獨立 Isolate
  Future<void> initAudioCapture() async {
    try {
      _receivePort = ReceivePort();
      _receivePort!.listen((data) {
        if (data is List<double>) {
          waveform = data;
          waveformAccumulated.addAll(data);

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
  /// 依秒數逐步等待，遇到取消訊號時即刻跳出
  Future<void> _waitForDuration(int seconds) async {
    for (int i = 0; i < seconds && !_shouldCancelRecording; i++) {
      await Future.delayed(const Duration(seconds: 1));
      if (_shouldCancelRecording) {
        break;
      }
    }
  }

  /// 播放倒數音效並等待音檔結束或取消
  Future<void> _playCountdown() async {
    await _audioPlayer.open(
      Audio('assets/sounds/1.mp3'),
      autoStart: true,
      showNotification: false,
    );
    await Future.any([
      _audioPlayer.playlistFinished.first,
      if (_cancelCompleter != null) _cancelCompleter!.future,
    ]);
  }

  /// 進行一次錄影流程（倒數 -> 錄影 -> 儲存）
  Future<void> _recordOnce(int index) async {
    if (_shouldCancelRecording) {
      return; // 若已收到取消訊號則直接跳出，避免繼續操作鏡頭
    }

    try {
      waveformAccumulated.clear();
      await initAudioCapture();
      if (_shouldCancelRecording) {
        await _closeAudioPipeline();
        if (ImuDataLogger.instance.hasActiveRound) {
          await ImuDataLogger.instance.abortActiveRound();
        }
        return;
      }

      final baseName = ImuDataLogger.instance.buildBaseFileName(
        roundIndex: index + 1,
      );
      await ImuDataLogger.instance.startRoundLogging(baseName);

      await controller!.startVideoRecording();

      await _waitForDuration(widget.durationSeconds);

      if (_shouldCancelRecording) {
        if (controller!.value.isRecordingVideo) {
          try {
            await controller!.stopVideoRecording();
          } catch (_) {}
        }
        await _closeAudioPipeline();
        if (ImuDataLogger.instance.hasActiveRound) {
          await ImuDataLogger.instance.abortActiveRound();
        }
        return;
      }

      final XFile videoFile = await controller!.stopVideoRecording();
      await _closeAudioPipeline();

      final savedVideoPath = await ImuDataLogger.instance.persistVideoFile(
        sourcePath: videoFile.path,
        baseName: baseName,
      );
      final csvPaths = ImuDataLogger.instance.hasActiveRound
          ? await ImuDataLogger.instance.finishRoundLogging()
          : <String, String>{};

      final entry = RecordingHistoryEntry(
        filePath: savedVideoPath,
        roundIndex: index + 1,
        recordedAt: DateTime.now(),
        durationSeconds: widget.durationSeconds,
        imuConnected: widget.isImuConnected,
        imuCsvPaths: csvPaths,
      );

      if (mounted) {
        setState(() {
          // 新紀錄置頂顯示，方便使用者快速找到最新檔案
          _recordedRuns.insert(0, entry);
        });
      } else {
        _recordedRuns.insert(0, entry);
      }

      debugPrint('✅ 儲存影片與感測資料：${entry.fileName}');
    } catch (e) {
      await ImuDataLogger.instance.abortActiveRound();
      debugPrint('❌ 錄影時出錯：$e');
    }
  }

  /// 依使用者設定自動執行多輪倒數與錄影，中間保留休息時間
  Future<void> playCountdownAndStart() async {
    if (controller == null || !controller!.value.isInitialized) {
      return; // 鏡頭尚未準備完成時不執行
    }

    if (isRecording) {
      return; // 避免重複點擊時重入流程
    }

    if (!widget.isImuConnected && mounted) {
      // 若尚未連線 IMU，仍允許錄影但提示使用者僅能取得畫面
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('尚未連線 IMU，將以純錄影模式進行。')),
      );
    }

    if (mounted) {
      setState(() {
        isRecording = true;
        _hasTriggeredRecording = true; // 使用者已主動啟動錄影
      });
    } else {
      isRecording = true;
      _hasTriggeredRecording = true;
    }

    _shouldCancelRecording = false;
    _cancelCompleter = Completer<void>();

    try {
      for (int i = 0; i < widget.totalRounds; i++) {
        if (_shouldCancelRecording) break;

        await _playCountdown();
        if (_shouldCancelRecording) break;

        await _waitForDuration(3); // 倒數結束後保留緩衝時間
        if (_shouldCancelRecording) break;

        await _recordOnce(i);
        if (_shouldCancelRecording) break;

        if (i < widget.totalRounds - 1) {
          await _waitForDuration(_restSecondsBetweenRounds);
        }
      }
    } finally {
      _cancelCompleter = null;
      _shouldCancelRecording = false;
      if (mounted) {
        setState(() => isRecording = false);
      } else {
        isRecording = false;
      }
    }
  }

  /// 讓使用者自選影片並播放
  Future<void> _pickAndPlayVideo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      initialDirectory: '/storage/emulated/0/Download',
    );

    if (!mounted) return;

    if (result != null && result.files.single.path != null) {
      final filePath = result.files.single.path!;
      _openVideoPlayer(filePath);
    }
  }

  /// 直接開啟影片播放頁面，統一處理導覽流程
  Future<void> _openVideoPlayer(String filePath) async {
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => VideoPlayerPage(videoPath: filePath)),
    );
  }

  /// 彈出歷史列表，提供使用者快速檢視本次錄影成果
  Future<void> _showRecordedRunsSheet() {
    return showRecordingHistorySheet(
      context: context,
      entries: _recordedRuns,
      onPlayEntry: (entry) => _openVideoPlayer(entry.filePath),
      onPickExternal: _pickAndPlayVideo,
    );
  }

  /// 音訊處理的 Isolate 主體（保留為預留擴充）
  static void _audioProcessingIsolate(SendPort sendPort) {}

  /// 音訊擷取錯誤處理
  void onError(Object e) {
    debugPrint('❌ Audio Capture Error: $e');
  }

  /// 處理返回上一頁事件：先停止錄影再允許跳轉
  Future<bool> _handleWillPop() async {
    _triggerCancel();
    await _stopActiveRecording();

    if (mounted) {
      Navigator.of(context).pop(List<RecordingHistoryEntry>.from(_recordedRuns));
    }
    return false;
  }

  // ---------- 畫面建構 ----------
  @override
  Widget build(BuildContext context) {
    if (controller == null || !controller!.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return WillPopScope(
      onWillPop: _handleWillPop,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('錄影進行中'),
          backgroundColor: const Color(0xFF123B70),
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!widget.isImuConnected)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                color: const Color(0xFFFFF4E5),
                child: const Text(
                  '目前為純錄影模式，返回上一頁可再次嘗試配對 IMU。',
                  style: TextStyle(color: Color(0xFF9A6A2F), fontSize: 13),
                ),
              ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              color: const Color(0xFFF4F7FB),
              child: Text(
                '本次預計錄影 ${widget.totalRounds} 次，每次 ${widget.durationSeconds} 秒。',
                style: const TextStyle(fontSize: 14, color: Color(0xFF123B70), fontWeight: FontWeight.w600),
              ),
            ),
            if (!_hasTriggeredRecording)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                color: const Color(0xFFE8F5E9),
                child: const Text(
                  '請確認站位後，點選右下角「開始錄影」才會啟動倒數。',
                  style: TextStyle(color: Color(0xFF1E8E5A), fontSize: 13),
                ),
              ),
            Expanded(
              child: Stack(
                children: [
                  Column(
                    children: [
                      Expanded(
                        child: Stack(
                          children: [
                            _buildStablePreview(),
                            const Positioned.fill(
                              child: StanceGuideOverlay(),
                            ),
                          ],
                        ),
                      ),
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
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E8E5A),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                      ),
                      child: Text(
                        isRecording
                            ? '錄製中...'
                            : (_hasTriggeredRecording ? '再次錄製' : '開始錄影'),
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 20,
                    left: 20,
                    child: ElevatedButton(
                      onPressed: _showRecordedRunsSheet,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF123B70),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                      ),
                      child: const Text(
                        '曾經錄影紀錄',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 封裝鏡頭初始化後的結果，保留可用的解析度資訊
class _CameraSelectionResult {
  const _CameraSelectionResult({
    required this.controller,
    required this.preset,
    required this.previewSize,
  });

  final CameraController controller; // 已初始化可直接使用的鏡頭控制器
  final ResolutionPreset preset; // 成功套用的解析度列舉值
  final Size? previewSize; // 實際解析度尺寸，無法取得時為 null
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

/// 揮桿站位指引覆蓋層，協助使用者對齊姿勢
class StanceGuideOverlay extends StatelessWidget {
  const StanceGuideOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _StanceGuidePainter(),
      ),
    );
  }
}

/// 自訂畫家：繪製左右對稱的揮桿人形與置中的箭頭提示
class _StanceGuidePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // ---------- 畫面設定 ----------
    final Paint guidelinePaint = Paint()
      ..color = const Color(0x99FFFFFF)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    final Paint fillPaint = Paint()
      ..color = const Color(0x4D000000)
      ..style = PaintingStyle.fill;

    final double centerX = size.width / 2;
    // 由於使用者希望人形示意圖更加貼近畫面底部，改以底部對齊的方式計算基準高度
    final double overlayWidth = size.width * 0.7;
    final double overlayHeight = size.height * 0.6;
    final double overlayBottom = size.height * 0.92; // 保留 8% 的底部邊界避免被裁切
    final Rect overlayRect = Rect.fromLTWH(
      centerX - overlayWidth / 2,
      overlayBottom - overlayHeight,
      overlayWidth,
      overlayHeight,
    );
    final double baseY = overlayRect.bottom - size.height * 0.04; // 腳部靠近底部，但仍預留安全距
    final double figureHeight = size.height * 0.35;
    final double headRadius = figureHeight * 0.12;

    // ---------- 畫出半透明底框，淡化鏡頭畫面並突顯指引 ----------
    canvas.drawRRect(
      RRect.fromRectAndRadius(overlayRect, const Radius.circular(24)),
      fillPaint,
    );

    // ---------- 定義左右人形的關鍵點 ----------
    void drawFigure(bool isLeft) {
      final double direction = isLeft ? -1 : 1; // 控制左右翻轉
      final double torsoX = centerX + (size.width * 0.18 * direction);
      final double headCenterY = baseY - figureHeight;
      final Offset headCenter = Offset(torsoX, headCenterY);

      // 頭部
      canvas.drawCircle(headCenter, headRadius, guidelinePaint);

      // 身體與腿部
      final Offset hip = Offset(torsoX, baseY - headRadius);
      final Offset knee = Offset(torsoX + direction * headRadius * 0.6, baseY - headRadius * 0.4);
      final Offset foot = Offset(torsoX + direction * headRadius * 1.4, baseY);
      canvas.drawLine(headCenter.translate(0, headRadius), hip, guidelinePaint);
      canvas.drawLine(hip, knee, guidelinePaint);
      canvas.drawLine(knee, foot, guidelinePaint);

      // 手臂與球桿
      final Offset shoulder = headCenter.translate(0, headRadius * 1.4);
      final Offset hand = Offset(centerX + direction * headRadius * 1.8, baseY - headRadius * 0.8);
      final Offset clubHead = Offset(centerX + direction * headRadius * 3.2, baseY + headRadius * 0.4);
      canvas.drawLine(shoulder, hand, guidelinePaint);
      canvas.drawLine(hand, clubHead, guidelinePaint);
    }

    drawFigure(true);
    drawFigure(false);

    // ---------- 畫出中央球與箭頭指引 ----------
    final double ballRadius = headRadius * 0.9;
    final Offset ballCenter = Offset(centerX, baseY - ballRadius * 0.2);
    canvas.drawCircle(ballCenter, ballRadius, guidelinePaint);

    final Path arrowPath = Path()
      ..moveTo(centerX, ballCenter.dy - ballRadius * 1.4)
      ..lineTo(centerX, ballCenter.dy - ballRadius * 3)
      ..moveTo(centerX - ballRadius * 0.9, ballCenter.dy - ballRadius * 2.2)
      ..lineTo(centerX, ballCenter.dy - ballRadius * 3)
      ..lineTo(centerX + ballRadius * 0.9, ballCenter.dy - ballRadius * 2.2);
    canvas.drawPath(arrowPath, guidelinePaint);

    // ---------- 在頂部顯示指引文字 ----------
    const String tip = '請對齊站位指引，確保雙腳與球心對稱';
    final TextPainter textPainter = TextPainter(
      text: const TextSpan(
        text: tip,
        style: TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w600,
          shadows: [Shadow(blurRadius: 6, color: Colors.black45, offset: Offset(0, 1))],
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width * 0.8);

    textPainter.paint(
      canvas,
      Offset(centerX - textPainter.width / 2, overlayRect.top + 16),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
  static const String _shareMessage = '分享我的 TekSwing 揮桿影片'; // 分享時的預設文案

  // ---------- 分享相關方法區 ----------
  Future<void> _shareToTarget(_ShareTarget target) async {
    // 事前確認檔案是否存在，避免分享流程出現例外
    final file = File(widget.videoPath);
    if (!await file.exists()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('找不到影片檔案，無法分享。')),
        );
      }
      return;
    }

    // 依目標應用程式取得對應的封裝名稱
    final packageName = switch (target) {
      _ShareTarget.instagram => 'com.instagram.android',
      _ShareTarget.facebook => 'com.facebook.katana',
      _ShareTarget.line => 'jp.naver.line.android',
    };

    bool sharedByPackage = false; // 紀錄是否已成功透過指定應用分享
    if (Platform.isAndroid) {
      try {
        final result = await _shareChannel.invokeMethod<bool>('shareToPackage', {
          'packageName': packageName,
          'filePath': widget.videoPath,
          'mimeType': 'video/*',
          'text': _shareMessage,
        });
        sharedByPackage = result ?? false;
      } on PlatformException catch (error) {
        debugPrint('[Share] Android 指定分享失敗：$error');
      }
    }

    if (!sharedByPackage) {
      if (mounted && Platform.isAndroid) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('未找到指定社群 App，已改用系統分享選單。')),
        );
      }
      await Share.shareXFiles([
        XFile(widget.videoPath),
      ], text: _shareMessage);
    }
  }

  Widget _buildShareButton({
    required IconData icon,
    required String label,
    required Color color,
    required _ShareTarget target,
  }) {
    // 建立統一樣式的分享按鈕，維持排版一致
    return Expanded(
      child: ElevatedButton.icon(
        onPressed: () => _shareToTarget(target),
        icon: Icon(icon),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

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
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: _videoController.value.isInitialized
                  ? AspectRatio(
                      aspectRatio: _videoController.value.aspectRatio,
                      child: VideoPlayer(_videoController),
                    )
                  : const CircularProgressIndicator(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '分享影片',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _buildShareButton(
                      icon: Icons.photo_camera,
                      label: 'Instagram',
                      color: const Color(0xFFC13584),
                      target: _ShareTarget.instagram,
                    ),
                    const SizedBox(width: 12),
                    _buildShareButton(
                      icon: Icons.facebook,
                      label: 'Facebook',
                      color: const Color(0xFF1877F2),
                      target: _ShareTarget.facebook,
                    ),
                    const SizedBox(width: 12),
                    _buildShareButton(
                      icon: Icons.chat,
                      label: 'LINE',
                      color: const Color(0xFF00C300),
                      target: _ShareTarget.line,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  '若無對應應用程式，將自動改用系統分享選單。',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          setState(() {
            _videoController.value.isPlaying
                ? _videoController.pause()
                : _videoController.play();
          });
        },
        child: Icon(_videoController.value.isPlaying ? Icons.pause : Icons.play_arrow),
      ),
    );
  }
}
