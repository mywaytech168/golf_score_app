import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:assets_audio_player/assets_audio_player.dart';
import 'package:camera/camera.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_audio_capture/flutter_audio_capture.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../models/recording_history_entry.dart';
import '../services/audio_analysis_service.dart';
import '../services/highlight_service.dart';
import '../services/imu_data_logger.dart';
import '../services/keep_screen_on_service.dart';
import '../services/video_overlay_processor.dart';
import '../widgets/recording_history_sheet.dart';
import 'highlight_preview_page.dart';

// ---------- 分享頻道設定 ----------
const MethodChannel _shareChannel = MethodChannel('share_intent_channel');

// ---------- 分享目標列舉 ----------
enum _ShareTarget { instagram, facebook, line }

/// 錄影專用頁面：專注鏡頭預覽、倒數與音訊波形，與 IMU 配對頁面分離
class RecordingSessionPage extends StatefulWidget {
  final List<CameraDescription> cameras; // 傳入所有可用鏡頭
  final bool isImuConnected; // 是否已配對 IMU，決定提示訊息
  final int totalRounds; // 本次預計錄影的輪數
  // final int durationSeconds; // 每輪錄影秒數 - REMOVED for unlimited recording
  final bool autoStartOnReady; // 由 IMU 按鈕開啟時自動啟動錄影
  final Stream<void> imuButtonStream; // 右手腕 IMU 按鈕事件來源
  final String? userAvatarPath; // 首頁帶入的個人頭像路徑，供分享影片時疊加

  const RecordingSessionPage({
    super.key,
    required this.cameras,
    required this.isImuConnected,
    required this.totalRounds,
    // required this.durationSeconds, // REMOVED
    required this.autoStartOnReady,
    required this.imuButtonStream,
    this.userAvatarPath,
  });

  @override
  State<RecordingSessionPage> createState() => _RecordingSessionPageState();
}

// Top-level label mapping helper (used by multiple pages)
String _mapPredToLabel(String? pred) {
  if (pred == null) return 'Unknown';
  final p = pred.toLowerCase().trim();
  if (p == 'pro') return 'Pro';
  if (p == 'good' || p == 'sweet') return 'Sweet';
  if (p == 'bad') return 'Try again';
  return p.isNotEmpty ? p : 'Unknown';
}

class _RecordingSessionPageState extends State<RecordingSessionPage> {
  // ---------- 狀態變數區 ----------
  CameraController? controller; // 控制鏡頭操作
  bool isRecording = false; // 標記是否正在錄影
  List<double> waveform = []; // 即時波形資料
  List<double> waveformAccumulated = []; // 累積波形資料供繪圖使用
  final ValueNotifier<int> repaintNotifier = ValueNotifier(0); // 用於觸發波形重繪

  final FlutterAudioCapture _audioCapture = FlutterAudioCapture(); // Use a single, final instance.
  ReceivePort? _receivePort; // 與 Isolate 溝通的管道
  Isolate? _isolate; // 處理音訊的背景執行緒，可能尚未建立

  final AssetsAudioPlayer _audioPlayer = AssetsAudioPlayer(); // 播放倒數音效
  final MethodChannel _volumeChannel = const MethodChannel('volume_button_channel'); // 監聽音量鍵
  Completer<void>? _cancelCompleter; // 將取消訊號傳遞給等待中的 Future
  final List<RecordingHistoryEntry> _recordedRuns = []; // 累積此次錄影產生的檔案
  String? _lastAnalysisLabel; // persist latest in-app analysis label
  Map<String, double?> _lastAnalysisFeatures = {}; // persist latest in-app features
  bool _hasTriggeredRecording = false; // 記錄使用者是否啟動過錄影，控制按鈕提示
  StreamSubscription<void>? _imuButtonSubscription; // 監聽 IMU 按鈕觸發錄影
  bool _pendingAutoStart = false; // 記錄 IMU 事件是否需等待鏡頭初始化後再啟動
  final _SessionProgress _sessionProgress = _SessionProgress(); // 集中管理倒數秒數與剩餘輪次
  Future<void> _cameraOperationQueue = Future.value(); // 鏡頭操作排程，確保同一時間僅執行一個任務
  bool _isRunningCameraTask = false; // 標記是否正在執行鏡頭任務，提供再入檢查
  bool _isDisposing = false; // 錄影頁是否進入釋放狀態，避免離場後仍排程新任務

  // Add a future to track the saving process
  Future<void>? _savingFuture;
  DateTime? _recordingStartTime; // To calculate actual duration
  String? _currentRecordingBaseName; // To hold the base name for the current session
  Timer? _recordingElapsedTimer; // periodic ticker for elapsed UI

  @override
  void initState() {
    super.initState();
    _sessionProgress.totalRounds = widget.totalRounds;
    _sessionProgress.remainingRounds = widget.totalRounds;
    _pendingAutoStart = widget.autoStartOnReady;

    // 訂閱 IMU 按鈕事件
    _imuButtonSubscription = widget.imuButtonStream.listen((_) => _handleImuTrigger());

    // 註冊音量鍵監聽
    _volumeChannel.setMethodCallHandler(_handleVolumeButton);

    // 保持螢幕開啟
    KeepScreenOnService.enable();

    // 初始化鏡頭
    _enqueueCameraTask(() => _initializeCamera(widget.cameras.first));
  }

  /// 釋放所有資源
  @override
  void dispose() {
    _isDisposing = true;
    _imuButtonSubscription?.cancel();
    _volumeChannel.setMethodCallHandler(null);
    _stopRecordingTimer();
    _enqueueCameraTask(() async {
      await controller?.dispose();
      await _stopAudioCapture();
    });
    KeepScreenOnService.disable();
    super.dispose();
  }

  /// 處理 IMU 按鈕觸發
  void _handleImuTrigger() {
    if (isRecording) {
      _triggerCancel();
    } else {
      _triggerRecording();
    }
  }

  /// 處理音量鍵事件
  Future<dynamic> _handleVolumeButton(MethodCall call) async {
    if (call.method == 'volumeButtonPressed') {
      // 在 iOS 上，音量鍵會觸發 startVideoRecording，這裡避免重複啟動
      if (Platform.isIOS && isRecording) {
        return;
      }
      _handleImuTrigger(); // 借用 IMU 觸發邏輯
    }
  }

  /// 建立並執行鏡頭任務，避免衝突
  Future<void> _enqueueCameraTask(Future<void> Function() task) async {
    if (_isRunningCameraTask) {
      // 如果已有任務在執行，將新任務排入佇列
      _cameraOperationQueue = _cameraOperationQueue.then((_) async {
        if (!_isDisposing) await task();
      });
    } else {
      // 否則直接執行
      _isRunningCameraTask = true;
      _cameraOperationQueue = task().whenComplete(() {
        _isRunningCameraTask = false;
      });
    }
  }

  /// 初始化鏡頭
  Future<void> _initializeCamera(CameraDescription cameraDescription) async {
    if (controller != null) {
      await controller!.dispose();
    }
    controller = CameraController(
      cameraDescription,
      ResolutionPreset.high,
      enableAudio: true,
    );

    try {
      await controller!.initialize();
      if (!mounted) return;

      // If there is a pending auto start, trigger it now
      if (_pendingAutoStart) {
        _pendingAutoStart = false;
        _triggerRecording();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('無法初始化鏡頭: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {});
      }
    }
  }

  /// 觸發錄影流程
  void _triggerRecording() {
    if (controller == null || !controller!.value.isInitialized) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('鏡頭尚未準備就緒')),
      );
      return;
    }
    if (_sessionProgress.remainingRounds <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已完成所有錄影輪次')),
      );
      return;
    }
    setState(() {
      _hasTriggeredRecording = true;
    });
    _startCountdown();
  }

  /// 處理取消流程
  void _triggerCancel() {
    if (_cancelCompleter != null && !_cancelCompleter!.isCompleted) {
      _cancelCompleter!.complete();
    }
  }

  /// 開始倒數計時
  void _startCountdown() {
    _sessionProgress.isCountingDown = true;
    _sessionProgress.countdownSeconds = 3;
    _cancelCompleter = Completer<void>();

    Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_cancelCompleter!.isCompleted) {
        timer.cancel();
        _resetToIdle();
        return;
      }

      if (_sessionProgress.countdownSeconds > 1) {
        setState(() {
          _sessionProgress.countdownSeconds--;
        });
        _playBeep();
      } else {
        timer.cancel();
        _playBeep(isFinal: true);
        _startRecording();
      }
    });
  }

  /// 開始錄影
  Future<void> _startRecording() async {
    if (controller == null || !controller!.value.isInitialized || controller!.value.isRecordingVideo) {
      return;
    }

    setState(() {
      isRecording = true;
      _sessionProgress.isCountingDown = false;
    });

    try {
      // --- Generate a consistent base name for all files in this session ---
      _recordingStartTime = DateTime.now(); // Record start time
      _startRecordingTimer();
      String two(int v) => v.toString().padLeft(2, '0');
      final baseTimestamp = '${_recordingStartTime!.year}'
          '${two(_recordingStartTime!.month)}'
          '${two(_recordingStartTime!.day)}'
          '${two(_recordingStartTime!.hour)}'
          '${two(_recordingStartTime!.minute)}'
          '${two(_recordingStartTime!.second)}';
      _currentRecordingBaseName = 'REC_$baseTimestamp';
      // --- End base name generation ---

      await controller!.startVideoRecording();
      
      // If audio capture fails, this will throw and be caught, preventing further execution.
      await _startAudioCapture();
      
      // Use the consistent base name for the IMU logger
      await ImuDataLogger.instance.startRoundLogging(_currentRecordingBaseName!);

      // REMOVED Timer for unlimited recording. Now only waits for manual stop.
      // final recordingCompleter = Completer<void>();
      // Timer(Duration(seconds: widget.durationSeconds), () {
      //   if (!recordingCompleter.isCompleted) {
      //     recordingCompleter.complete();
      //   }
      // });

      // 等待手動取消
      await _cancelCompleter!.future;

      // IMPORTANT: Only call stop/save if the recording was successfully started and completed.
      await _stopRecordingAndSave();

    } catch (e, stackTrace) {
      debugPrint('[Recording] Start recording failed: $e');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('錄影失敗: $e')),
        );
      }
      // If starting failed, ensure we clean up immediately.
      // This prevents a call to _stopRecordingAndSave with an uninitialized state.
      if (controller?.value.isRecordingVideo ?? false) {
        try {
          await controller!.stopVideoRecording();
        } catch (stopError) {
          debugPrint('[Recording] Failed to stop video after start error: $stopError');
        }
      }
      _stopRecordingTimer();
      _resetToIdle();
      // NOTE: We do NOT call _stopRecordingAndSave here.
    }
  }

  /// 停止錄影並儲存檔案
  Future<void> _stopRecordingAndSave() async {
    if (!isRecording || controller == null) {
      debugPrint('[Save] Stop called but not recording or controller is null.');
      return;
    }

    debugPrint('[Save] Starting stop/save process...');
    final completer = Completer<void>();
    _savingFuture = completer.future;

    try {
      debugPrint('[Save] Stopping video recording...');
      final XFile videoFile = await controller!.stopVideoRecording();
      debugPrint('[Save] Video recording stopped. File at: ${videoFile.path}');
      
      debugPrint('[Save] Stopping audio capture...');
      await _stopAudioCapture();
      debugPrint('[Save] Audio capture stopped.');

      debugPrint('[Save] Finishing IMU logging...');
      final imuFiles = await ImuDataLogger.instance.finishRoundLogging();
      debugPrint('[Save] IMU logging finished. Files: ${imuFiles.toString()}');

      // Use the base name generated at the start of recording
      final baseName = _currentRecordingBaseName;
      if (baseName == null) {
        throw Exception("Recording base name was not set. Cannot save files.");
      }

      // Determine public Downloads directory (external storage)
      Directory? targetDir;
      if (Platform.isAndroid) {
        // Force saves to the public Downloads directory so files are easy to find
        targetDir = Directory('/storage/emulated/0/Download');
        try {
          if (!await targetDir.exists()) {
            await targetDir.create(recursive: true);
          }
        } catch (e) {
          debugPrint('[Save] Failed to create /storage/emulated/0/Download: $e');
          targetDir = null; // Allow fallback below
        }
      }

      // Fallback to platform-provided locations if the primary target is unavailable
      if (targetDir == null) {
        try {
          final exDirs = await getExternalStorageDirectories(type: StorageDirectory.downloads);
          if (exDirs != null && exDirs.isNotEmpty) {
            targetDir = exDirs.first;
          }
        } catch (e) {
          debugPrint('[Save] getExternalStorageDirectories error: $e');
        }
      }

      if (targetDir == null) {
        final appDocs = await getApplicationDocumentsDirectory();
        targetDir = Directory(p.join(appDocs.path, 'Downloads'));
      }

      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }

      // Ensure WRITE permission on Android for external storage (Android 11+ needs special handling)
      if (Platform.isAndroid) {
        final status = await Permission.manageExternalStorage.status;
        if (!status.isGranted) {
          try {
            await Permission.manageExternalStorage.request();
          } catch (e) {
            debugPrint('[Save] Permission request failed: $e');
          }
        }
      }

      // Move video to targetDir with new name
      final newVideoPath = p.join(targetDir.path, '$baseName.mp4');
      try {
        await videoFile.saveTo(newVideoPath);
      } catch (e) {
        debugPrint('[Save] Failed to move video to $newVideoPath: $e');
        // As last resort, copy bytes
        final bytes = await videoFile.readAsBytes();
        final out = File(newVideoPath);
        await out.writeAsBytes(bytes);
      }

      // Move and rename IMU files to same directory, preserve slot keys
      final Map<String, String> imuDestPaths = {};
      // finishRoundLogging returns Map<String,String>
      final Map<String, String> imuFilesMap = Map<String, String>.from(imuFiles);
      for (final entryKvp in imuFilesMap.entries) {
        final slotKey = entryKvp.key; // e.g., 'RIGHT_WRIST' or 'CHEST'
        final imuPath = entryKvp.value;
        try {
          final imuFile = File(imuPath);
          // The temp IMU file is already named correctly, just move it.
          final newImuName = p.basename(imuPath); // e.g., REC202512021328_RIGHT_WRIST.csv
          final newImuPath = p.join(targetDir.path, newImuName);
          await imuFile.copy(newImuPath);
          imuDestPaths[slotKey] = newImuPath;
        } catch (e) {
          debugPrint('[Save] Failed to move IMU file $imuPath: $e');
        }
      }

      final int recordedDuration;
      if (_recordingStartTime != null) {
        recordedDuration = DateTime.now().difference(_recordingStartTime!).inSeconds;
      } else {
        recordedDuration = 0;
      }
      final recordedAtTime = _recordingStartTime ?? DateTime.now();
      _recordingStartTime = null; // Reset for next recording
      _currentRecordingBaseName = null; // Reset for next recording

      final entry = RecordingHistoryEntry(
        filePath: newVideoPath, // Use the new, permanent path
        roundIndex: _sessionProgress.totalRounds - _sessionProgress.remainingRounds + 1,
        recordedAt: recordedAtTime,
        durationSeconds: recordedDuration, // Use calculated duration
        imuConnected: widget.isImuConnected,
        imuCsvPaths: imuDestPaths,
      );
      _recordedRuns.add(entry);
      debugPrint('[Save] Entry added to history. Total runs: ${_recordedRuns.length}');

      // 在背景執行音訊分析
      unawaited(_runAudioAnalysis(entry));

    } catch (e, stackTrace) {
      debugPrint('[Save] Error during save process: $e');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('存檔失敗: $e')),
        );
      }
    } finally {
      setState(() {
        _sessionProgress.remainingRounds--;
      });
      _resetToIdle();
      completer.complete();
      debugPrint('[Save] Save process finished.');
    }
  }

  /// 重設為閒置狀態
  void _resetToIdle() {
    _stopRecordingTimer();
    setState(() {
      isRecording = false;
      _hasTriggeredRecording = false;
      _sessionProgress.isCountingDown = false;
      waveform.clear();
      waveformAccumulated.clear();
    });
  }

  // ---------- 音訊處理 ----------

  /// 開始擷取音訊
  Future<void> _startAudioCapture() async {
    // Ensure microphone permission is granted before proceeding.
    if (!await Permission.microphone.request().isGranted) {
      debugPrint('[AudioCapture] Microphone permission not granted.');
      throw Exception('Microphone permission not granted.');
    }

    try {
      _receivePort = ReceivePort();
      _isolate = await Isolate.spawn(
        _audioProcessingIsolate,
        _receivePort!.sendPort,
      );
      _receivePort!.listen(_handleAudioData);

      // The core of the fix: wait for the native side to be ready.
      await _audioCapture.start(_audioListener, (error) {
        // Add detailed logging for any errors from the listener.
        debugPrint('[AudioCapture] Listener Error: $error');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Audio listener error: $error')),
          );
        }
      }, sampleRate: 44100, bufferSize: 4096);

    } catch (e, stackTrace) {
      // Catch and log any exceptions during the setup process.
      debugPrint('[AudioCapture] Failed to start audio capture: $e');
      debugPrintStack(stackTrace: stackTrace);
      // Re-throw the exception to be caught by the recording logic.
      rethrow;
    }
  }

  /// 停止擷取音訊並回傳檔案路徑
  Future<String?> _stopAudioCapture() async {
    // Use the single instance to stop.
    await _audioCapture.stop();
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _receivePort?.close();
    // 這部分需要原生端實作來回傳檔案路徑
    return null;
  }

  /// Isolate 入口函式，處理音訊資料
  static void _audioProcessingIsolate(SendPort sendPort) {
    final receivePort = ReceivePort();
    sendPort.send(receivePort.sendPort);

    receivePort.listen((dynamic data) {
      if (data is List<double>) {
        // 簡單的 RMS 計算
        double sum = 0;
        for (var sample in data) {
          sum += sample * sample;
        }
        double rms = sum > 0 ? (sum / data.length) : 0.0;
        sendPort.send(rms);
      }
    });
  }

  /// 處理來自 Isolate 的音訊資料
  void _handleAudioData(dynamic data) {
    if (data is double) {
      setState(() {
        waveform.add(data);
        if (waveform.length > 200) {
          waveform.removeAt(0);
        }
        waveformAccumulated.add(data);
        repaintNotifier.value++;
      });
    }
  }

  /// 音訊監聽回呼
  void _audioListener(dynamic data) {
    _receivePort?.sendPort.send(data as List<double>);
  }

  // ---------- UI 輔助方法 ----------

  /// 建立鏡頭預覽 Widget
  Widget _buildCameraPreview() {
    if (controller == null || !controller!.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    // Get screen and camera aspect ratios
    final mediaSize = MediaQuery.of(context).size;
    final scale = 1 / (controller!.value.aspectRatio * mediaSize.aspectRatio);

    return ClipRect(
      clipper: _MediaSizeClipper(mediaSize),
      child: Transform.scale(
        scale: scale,
        alignment: Alignment.topCenter,
        child: CameraPreview(controller!),
      ),
    );
  }

  /// 播放提示音
  void _playBeep({bool isFinal = false}) {
    final sound = isFinal ? 'assets/sounds/final_beep.mp3' : 'assets/sounds/beep.mp3';
    _audioPlayer.open(Audio(sound), autoStart: true, volume: 0.5);
  }

  /// 顯示錄影紀錄
  void _showRecordingHistory(BuildContext context) {
    showRecordingHistorySheet(
      context: context,
      entries: _recordedRuns,
      onPlayEntry: (entry) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => VideoPlayerPage(
              videoPath: entry.filePath,
              avatarPath: widget.userAvatarPath,
            ),
          ),
        );
      },
    );
  }

  /// 執行 Python 音訊分析 (Desktop only)
  Future<void> _runPythonAnalyzer() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['wav', 'mp3', 'm4a', 'aac'],
    );
    if (result != null && result.files.single.path != null) {
      final filePath = result.files.single.path!;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('正在分析: $filePath')),
        );
      }
      try {
        final analysisResult = await AudioAnalysisService.analyzeVideo(filePath);
        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('分析結果'),
              content: Text(jsonEncode(analysisResult)),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('關閉'),
                ),
              ],
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('分析失敗: $e')),
          );
        }
      }
    }
  }

  /// 執行音訊分析服務
  Future<void> _runAudioAnalysis(RecordingHistoryEntry entry) async {
    try {
      final result = await AudioAnalysisService.analyzeVideo(entry.filePath);
      final summary = result['summary'] as Map<String, dynamic>?;
      if (summary != null) {
        final pred = summary['audio_class']?.toString();
        if (pred != null) {
          setState(() {
            _lastAnalysisLabel = _mapPredToLabel(pred);
            _lastAnalysisFeatures = {
              'rms_dbfs': _toDouble(summary['rms_dbfs']),
              'spectral_centroid': _toDouble(summary['spectral_centroid']),
              'sharpness_hfxloud': _toDouble(summary['sharpness_hfxloud']),
            };
          });
        }
      }
    } catch (e) {
      debugPrint('音訊分析失敗: $e');
    }
  }

  double? _toDouble(dynamic val) {
    if (val is double) return val;
    if (val is int) return val.toDouble();
    if (val is String) return double.tryParse(val);
    return null;
  }

  void _startRecordingTimer() {
    _recordingElapsedTimer?.cancel();
    _recordingElapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !isRecording || _recordingStartTime == null) return;
      setState(() {});
    });
  }

  void _stopRecordingTimer() {
    _recordingElapsedTimer?.cancel();
    _recordingElapsedTimer = null;
  }

  String _formatElapsed() {
    if (_recordingStartTime == null) return '00:00';
    final diff = DateTime.now().difference(_recordingStartTime!);
    final hours = diff.inHours;
    final minutes = diff.inMinutes.remainder(60);
    final seconds = diff.inSeconds.remainder(60);
    String two(int v) => v.toString().padLeft(2, '0');
    if (hours > 0) {
      return '${two(hours)}:${two(minutes)}:${two(seconds)}';
    }
    return '${two(minutes)}:${two(seconds)}';
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (isRecording) {
          _triggerCancel();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('正在儲存影片...')),
            );
          }
          await _savingFuture;
          return true;
        }
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('錄影'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              if (isRecording) {
                _triggerCancel();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('正在儲存影片...')),
                  );
                }
                await _savingFuture;
                if (mounted) Navigator.of(context).pop();
              } else {
                Navigator.of(context).pop();
              }
            },
          ),
          actions: [
            if (kDebugMode)
              IconButton(
                tooltip: 'Run audio analyzer (desktop)',
                onPressed: _runPythonAnalyzer,
                icon: const Icon(Icons.analytics),
              ),
            IconButton(
              icon: const Icon(Icons.history),
              onPressed: () => _showRecordingHistory(context),
              tooltip: '錄影紀錄',
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Container(
                  color: Colors.black,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _buildCameraPreview(),
                      if (isRecording)
                        Positioned(
                          top: 12,
                          left: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.circle, color: Colors.white, size: 14),
                                SizedBox(width: 6),
                                Text('REC', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                              ],
                            ),
                          ),
                        ),
                      if (isRecording && _recordingStartTime != null)
                        Positioned(
                          top: 12,
                          right: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.6),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.timer, color: Colors.white, size: 16),
                                const SizedBox(width: 6),
                                Text(
                                  _formatElapsed(),
                                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (_sessionProgress.isCountingDown)
                        Center(
                          child: Text(
                            '${_sessionProgress.countdownSeconds}',
                            style: const TextStyle(fontSize: 120, color: Colors.white, fontWeight: FontWeight.bold, shadows: [Shadow(blurRadius: 15, color: Colors.black54)]),
                          ),
                        ),
                      const StanceGuideOverlay(
                        isVisible: true,
                        stanceValue: 0.6,
                        swingDirection: 15,
                      ),
                    ],
                  ),
                ),
              ),
              Container(
                color: Colors.white,
                padding: const EdgeInsets.all(16.0),
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      _SessionStatusBar(
                        progress: _sessionProgress,
                        isImuConnected: widget.isImuConnected,
                        isRecording: isRecording,
                      ),
                      const SizedBox(height: 12),
                      if (_lastAnalysisLabel != null)
                        _SessionStatusTile(
                          title: '????',
                          value: _lastAnalysisLabel!,
                          isActive: true,
                        ),
                      if (_lastAnalysisFeatures.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                          child: Wrap(
                            spacing: 12,
                            runSpacing: 4,
                            children: _lastAnalysisFeatures.entries
                                .map((e) => Text('${e.key}: ${e.value?.toStringAsFixed(2) ?? '--'}', style: const TextStyle(fontSize: 10, color: Colors.grey)))
                                .toList(),
                          ),
                        ),
                      Container(
                        height: 100,
                        decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(8)),
                        child: ValueListenableBuilder<int>(
                          valueListenable: repaintNotifier,
                          builder: (context, _, __) {
                            return WaveformWidget(
                              waveform: waveformAccumulated,
                              color: Colors.blueAccent,
                              strokeWidth: 2.0,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.large(
          onPressed: _hasTriggeredRecording ? _triggerCancel : _triggerRecording,
          backgroundColor: _hasTriggeredRecording ? Colors.red : Colors.blue,
          child: Icon(
            _hasTriggeredRecording ? Icons.stop : Icons.camera,
            color: Colors.white,
            size: 42,
          ),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      ),
    );
  }
}

class _MediaSizeClipper extends CustomClipper<Rect> {
  final Size mediaSize;
  const _MediaSizeClipper(this.mediaSize);
  @override
  Rect getClip(Size size) {
    return Rect.fromLTWH(0, 0, mediaSize.width, mediaSize.height);
  }

  @override
  bool shouldReclip(CustomClipper<Rect> oldClipper) {
    return true;
  }
}

class _SessionProgress {
  int remainingRounds = 0; // 剩餘輪次
  int totalRounds = 0; // 總輪次
  int countdownSeconds = 0; // 倒數秒數
  bool isCountingDown = false; // 是否正在倒數中
}

class _SessionStatusBar extends StatelessWidget {
  final _SessionProgress progress;
  final bool isImuConnected;
  final bool isRecording;

  const _SessionStatusBar({
    required this.progress,
    required this.isImuConnected,
    required this.isRecording,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 8)],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // IMU 連線狀態
          Row(
            children: [
              Icon(
                isImuConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                color: isImuConnected ? Colors.green : Colors.red,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                isImuConnected ? 'IMU 已連線' : 'IMU 未連線',
                style: TextStyle(
                  color: isImuConnected ? Colors.green : Colors.red,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          // 錄影狀態
          Row(
            children: [
              Icon(
                isRecording ? Icons.videocam : Icons.videocam_off,
                color: isRecording ? Colors.red : Colors.grey,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                isRecording ? '正在錄影' : '錄影已停止',
                style: TextStyle(
                  color: isRecording ? Colors.red : Colors.grey,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SessionStatusTile extends StatelessWidget {
  final String title;
  final String value;
  final bool isActive;

  const _SessionStatusTile({
    required this.title,
    required this.value,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFFE8F5E9) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 8)],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: TextStyle(
              color: isActive ? const Color(0xFF2E7D32) : Colors.black,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: isActive ? const Color(0xFF2E7D32) : Colors.black54,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class WaveformWidget extends StatelessWidget {
  final List<double> waveform;
  final Color color;
  final double strokeWidth;

  const WaveformWidget({
    super.key,
    required this.waveform,
    this.color = Colors.blue,
    this.strokeWidth = 2.0,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(double.infinity, 100),
      painter: WaveformPainter(waveform, color, strokeWidth),
    );
  }
}

class WaveformPainter extends CustomPainter {
  final List<double> waveform;
  final Color color;
  final double strokeWidth;

  WaveformPainter(this.waveform, this.color, this.strokeWidth);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    final width = size.width;
    final height = size.height;

    // Draw the waveform
    for (int i = 0; i < waveform.length - 1; i++) {
      final x1 = i * (width / (waveform.length - 1));
      final y1 = height / 2 - (waveform[i] * height / 2);
      final x2 = (i + 1) * (width / (waveform.length - 1));
      final y2 = height / 2 - (waveform[i + 1] * height / 2);
      canvas.drawLine(Offset(x1, y1), Offset(x2, y2), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class StanceGuideOverlay extends StatelessWidget {
  final bool isVisible;
  final double stanceValue; // 0.0 to 1.0 range
  final double swingDirection; // In degrees

  const StanceGuideOverlay({
    super.key,
    required this.isVisible,
    required this.stanceValue,
    required this.swingDirection,
  });

  @override
  Widget build(BuildContext context) {
    if (!isVisible) return const SizedBox.shrink();

    // Ensure the painter receives the full available area so the "person" guide is centered
    return SizedBox.expand(
      child: CustomPaint(
        painter: _StanceGuidePainter(stanceValue, swingDirection),
      ),
    );
  }
}

class _StanceGuidePainter extends CustomPainter {
  final double stanceValue; // 0.0 to 1.0 range
  final double swingDirection; // In degrees

  _StanceGuidePainter(this.stanceValue, this.swingDirection);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    final centerX = size.width / 2;
    final centerY = size.height * 0.85; // Move the drawing lower
    final figureScale = size.height * 0.0020; // Scale down the figure slightly

    // Define the path for the left golfer silhouette
    final Path golferPath = Path();
    golferPath.moveTo(-28, -105); // Head top
    golferPath.cubicTo(-45, -100, -55, -80, -53, -65); // Head back
    golferPath.cubicTo(-50, -40, -45, -30, -35, -20); // Neck/Shoulder
    golferPath.cubicTo(-20, 0, -25, 25, -15, 45); // Back
    golferPath.cubicTo(-5, 65, 5, 80, 15, 90); // Buttocks
    golferPath.cubicTo(25, 100, 30, 110, 25, 120); // Back of leg
    golferPath.cubicTo(20, 130, 0, 135, -15, 130); // Foot bottom
    golferPath.cubicTo(-30, 125, -35, 115, -30, 105); // Front of foot/leg
    golferPath.cubicTo(-25, 95, -20, 80, -10, 60); // Front of leg
    golferPath.cubicTo(0, 40, 15, 30, 25, 10); // Belly
    golferPath.cubicTo(35, -10, 30, -40, 20, -55); // Chest/Front shoulder
    golferPath.cubicTo(10, -70, -5, -80, -15, -90); // Front of head
    golferPath.close();

    // --- Draw Left Golfer ---
    final double stanceWidth = size.width * 0.25;
    final Matrix4 leftTransform = Matrix4.identity()
      ..translate(centerX - stanceWidth / 2, centerY)
      ..scale(figureScale);
    final Path transformedLeftPath = golferPath.transform(leftTransform.storage);
    canvas.drawPath(transformedLeftPath, paint);

    // --- Draw Right Golfer (flipped) ---
    final Matrix4 rightTransform = Matrix4.identity()
      ..translate(centerX + stanceWidth / 2, centerY)
      ..scale(-figureScale, figureScale); // Flip horizontally
    final Path transformedRightPath = golferPath.transform(rightTransform.storage);
    canvas.drawPath(transformedRightPath, paint);

    // --- Draw Clubs and Center Circle ---
    final clubPaint = Paint()
      ..color = Colors.white.withOpacity(0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5;

    final circleRadius = size.width * 0.06;
    final circleCenter = Offset(centerX, centerY + size.height * 0.1);

    // Club lines from an approximate hand position to the circle
    final leftHandPos = Offset(centerX - stanceWidth / 2 + (10 * figureScale), centerY + (10 * figureScale));
    final rightHandPos = Offset(centerX + stanceWidth / 2 - (10 * figureScale), centerY + (10 * figureScale));
    canvas.drawLine(leftHandPos, circleCenter, clubPaint);
    canvas.drawLine(rightHandPos, circleCenter, clubPaint);

    // Center circle
    canvas.drawCircle(circleCenter, circleRadius, clubPaint);

    // Arrow inside the circle
    final arrowPaint = Paint()
      ..color = Colors.white.withOpacity(0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;
    final arrowPath = Path();
    arrowPath.moveTo(circleCenter.dx, circleCenter.dy - circleRadius * 0.4);
    arrowPath.lineTo(circleCenter.dx, circleCenter.dy + circleRadius * 0.4);
    arrowPath.moveTo(circleCenter.dx - circleRadius * 0.3, circleCenter.dy);
    arrowPath.lineTo(circleCenter.dx, circleCenter.dy - circleRadius * 0.4);
    arrowPath.lineTo(circleCenter.dx + circleRadius * 0.3, circleCenter.dy);
    canvas.drawPath(arrowPath, arrowPaint);
  }

  @override
  bool shouldRepaint(covariant _StanceGuidePainter oldDelegate) {
    return oldDelegate.stanceValue != stanceValue || oldDelegate.swingDirection != swingDirection;
  }
}


/// 影片播放頁面，提供錄製檔案的立即檢視
class VideoPlayerPage extends StatefulWidget {
  final String videoPath; // 影片檔案路徑
  final String? avatarPath; // 首頁傳遞的個人頭像，用於決定是否可疊加

  const VideoPlayerPage({
    super.key,
    required this.videoPath,
    this.avatarPath,
  });

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  VideoPlayerController? _videoController; // 影片控制器，初始化成功後才會建立
  static const String _shareMessage = '分享我的 TekSwing 揮桿影片'; // 分享時的預設文案
  final TextEditingController _captionController = TextEditingController(); // 影片下方說明輸入
  final List<String> _generatedTempFiles = []; // 記錄原生處理後的暫存影片，頁面結束時統一清理
  bool _attachAvatar = false; // 是否要在分享影片中加入個人頭像
  bool _isProcessingShare = false; // 控制分享期間按鈕狀態，避免重複觢發
  late final bool _avatarSelectable; // 記錄頭像檔案是否存在，可供開關判斷
  bool _isVideoLoading = true; // 控制是否顯示讀取中轉圈
  String? _videoLoadError; // 若載入失敗記錄錯誤訊息，提供使用者提示與重試
  String? _classificationLabel; // 影片的聲音評分標籤
  Map<String, double?> _classificationFeatures = {};
  bool _isGeneratingHighlight = false;

  bool get _canControlVideo => _videoController != null && _videoController!.value.isInitialized;

  Widget _featRow(String label, double? value) {
    return Text('$label: ${value == null ? '--' : value.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontSize: 11));
  }

  double? _toDouble(dynamic val) {
    if (val is double) return val;
    if (val is int) return val.toDouble();
    if (val is String) return double.tryParse(val);
    return null;
  }

  Future<void> _generateHighlight() async {
    if (_isGeneratingHighlight) return;
    setState(() => _isGeneratingHighlight = true);
    try {
      final out = await HighlightService.generateHighlight(widget.videoPath, beforeMs: 3000, afterMs: 3000, titleData: {'Name':'Player','Course':'Unknown'});
      if (out != null && out.isNotEmpty) {
        if (!mounted) return;
        debugPrint('[Highlight] generated at: $out');
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Highlight 生成完成: $out')));
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => HighlightPreviewPage(videoPath: out, avatarPath: widget.avatarPath)));
      } else {
        String? debugText;
        try {
          final cache = await getTemporaryDirectory();
          final String debugName = p.basenameWithoutExtension(widget.videoPath) + '_highlight_debug.txt';
          final f = File('${cache.path}${Platform.pathSeparator}$debugName');
          if (await f.exists()) debugText = await f.readAsString();
        } catch (_) {}
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('生成 Highlight 失敗或此平台不支援。')));
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => HighlightPreviewPage(videoPath: widget.videoPath, avatarPath: widget.avatarPath, debugText: debugText)));
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('生成 Highlight 發生錯誤：$e')));
    } finally {
      if (mounted) setState(() => _isGeneratingHighlight = false);
    }
  }

  /// 根據分享目標，準備檔案並呼叫原生分享
  Future<void> _shareToTarget(_ShareTarget target) async {
    if (_isProcessingShare) {
      return;
    }
    setState(() => _isProcessingShare = true);

    try {
      final String? sharePath = await _prepareShareFile();

      if (!mounted || sharePath == null) {
        return;
      }

      final packageName = switch (target) {
        _ShareTarget.instagram => 'com.instagram.android',
        _ShareTarget.facebook => 'com.facebook.katana',
        _ShareTarget.line => 'jp.naver.line.android',
      };

      bool sharedByPackage = false;
      if (Platform.isAndroid) {
        try {
          final result = await _shareChannel.invokeMethod<bool>('shareToPackage', {
            'packageName': packageName,
            'filePath': sharePath,
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
        await Share.shareXFiles([XFile(sharePath)], text: _shareMessage);
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessingShare = false);
      }
    }
  }

  Widget _buildShareButton({
    required IconData icon,
    required String label,
    required Color color,
    required _ShareTarget target,
  }) {
    return Expanded(
      child: ElevatedButton.icon(
        onPressed: _isProcessingShare ? null : () => _shareToTarget(target),
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
    _avatarSelectable = widget.avatarPath != null &&
        widget.avatarPath!.isNotEmpty &&
        File(widget.avatarPath!).existsSync();
    unawaited(_initializeVideo());
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _captionController.dispose();
    _cleanupTempFiles();
    super.dispose();
  }

  Future<void> _initializeVideo() async {
    setState(() {
      _isVideoLoading = true;
      _videoLoadError = null;
    });

    final file = File(widget.videoPath);
    if (!await file.exists()) {
      setState(() {
        _isVideoLoading = false;
        _videoLoadError = '找不到錄影檔案，請返回上一頁重新錄製。';
      });
      return;
    }

    await _videoController?.dispose();
    final controller = VideoPlayerController.file(file);
    try {
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _videoController = controller;
        _isVideoLoading = false;
      });
      unawaited(_loadClassificationForVideo());
      controller.play();
    } catch (error, stackTrace) {
      debugPrint('[VideoPlayer] 初始化失敗：$error');
      debugPrintStack(stackTrace: stackTrace);
      await controller.dispose();
      if (mounted) {
        setState(() {
          _videoController = null;
          _isVideoLoading = false;
          _videoLoadError = '無法載入影片，請稍後再試。';
        });
      }
    }
  }

  Future<void> _loadClassificationForVideo() async {
    try {
      final file = File(widget.videoPath);
      if (!await file.exists()) return;
      final parent = file.parent;
      final batchFile = File('${parent.path}${Platform.pathSeparator}batch_classify.csv');
      String? pred;
      if (await batchFile.exists()) {
        final lines = await batchFile.readAsLines();
        for (var i = 1; i < lines.length; i++) {
          final cols = lines[i].split(',');
          if (cols.isNotEmpty && cols[0].trim() == file.uri.pathSegments.last) {
            pred = cols.length > 1 ? cols[1].trim() : null;
            break;
          }
        }
      }
      final per = File(widget.videoPath.replaceAll(RegExp(r'\\.mp4$'), '') + '_classify_report.csv');
      if (await per.exists()) {
        final lines = await per.readAsLines();
        final Map<String, double?> feats = {};
        for (var line in lines) {
          final cols = line.trim().split(',');
          if (cols.length > 1) {
            final key = cols[0].trim();
            if (!key.startsWith('__') && !key.toLowerCase().contains('feature') && !key.toLowerCase().contains('title')) {
              feats[key] = double.tryParse(cols[1].trim());
            }
          }
        }
        final wanted = ['rms_dbfs','spectral_centroid','sharpness_hfxloud','highband_amp','peak_dbfs'];
        final picked = { for (var k in wanted) k: feats[k] };
        setState(() => _classificationFeatures = picked);
      }

      if (pred != null && pred.isNotEmpty) {
        setState(() => _classificationLabel = _mapPredToLabel(pred));
      }
    } catch (e) {
      // ignore
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _cleanupTempFiles() {
    for (final path in _generatedTempFiles) {
      try {
        final file = File(path);
        if (file.existsSync()) file.deleteSync();
      } catch (_) {}
    }
    _generatedTempFiles.clear();
  }

  Future<String?> _prepareShareFile() async {
    final bool wantsAvatar = _attachAvatar;
    final String trimmedCaption = _captionController.text.trim();
    final bool wantsCaption = trimmedCaption.isNotEmpty;

    if (wantsAvatar) {
      if (!_avatarSelectable || widget.avatarPath == null || !File(widget.avatarPath!).existsSync()) {
        _showSnack('尚未設定或找不到個人頭像檔案。');
        return null;
      }
    }

    String captionToUse = trimmedCaption;
    bool finalAttachCaption = wantsCaption;
    try {
      final List<String> captionParts = [];
      if (captionToUse.isNotEmpty) captionParts.add(captionToUse);
      if (_classificationLabel != null && _classificationLabel!.isNotEmpty) {
        captionParts.add('評分: ${_classificationLabel!}');
      }
      if (_classificationFeatures.isNotEmpty) {
        final rms = _classificationFeatures['rms_dbfs'];
        final sc = _classificationFeatures['spectral_centroid'];
        final sh = _classificationFeatures['sharpness_hfxloud'];
        final featText = 'rms:${rms?.toStringAsFixed(2) ?? '--'} sc:${sc?.toStringAsFixed(1) ?? '--'} sh:${sh?.toStringAsFixed(2) ?? '--'}';
        captionParts.add(featText);
        finalAttachCaption = true;
      }
      captionToUse = captionParts.join(' \n');
    } catch (_) {
      captionToUse = trimmedCaption;
      finalAttachCaption = wantsCaption;
    }

    final result = await VideoOverlayProcessor.process(
      inputPath: widget.videoPath,
      attachAvatar: wantsAvatar,
      avatarPath: widget.avatarPath,
      attachCaption: finalAttachCaption,
      caption: captionToUse,
    );

    if (result == null) {
      _showSnack('處理影片時發生錯誤，請稍後再試。');
      return null;
    }

    if (result != widget.videoPath) {
      _generatedTempFiles.add(result);
    }
    return result;
  }

  Future<void> _reAnalyzeForVideo() async {
    if (_isProcessingShare) return;
    setState(() => _isProcessingShare = true);
    try {
      final result = await AudioAnalysisService.analyzeVideo(widget.videoPath);
      final summary = result['summary'] as Map<String, dynamic>?;
      if (summary != null) {
        final feats = <String, double?>{
          'rms_dbfs': _toDouble(summary['rms_dbfs']),
          'spectral_centroid': _toDouble(summary['spectral_centroid']),
          'sharpness_hfxloud': _toDouble(summary['sharpness_hfxloud']),
          'highband_amp': _toDouble(summary['highband_amp']),
          'peak_dbfs': _toDouble(summary['peak_dbfs']),
        };
        String? pred = summary['audio_class']?.toString();
        if (mounted) {
          setState(() {
            _classificationFeatures = feats;
            if (pred != null) _classificationLabel = _mapPredToLabel(pred);
          });
        }

        try {
          final file = File(widget.videoPath);
          if (await file.exists()) {
            final csvFile = File(widget.videoPath.replaceAll(RegExp(r'\.mp4$'), '') + '_classify_report.csv');
            final rows = <String>['feature,target,weight'];
            feats.forEach((k, v) => rows.add('$k,${v ?? ''},1.0'));
            if (pred != null) rows.add('label,$pred,1.0');
            await csvFile.writeAsString(rows.join('\n'));
            final debugFile = File(widget.videoPath.replaceAll(RegExp(r'\.mp4$'), '') + '_analysis_debug.json');
            await debugFile.writeAsString(jsonEncode(result));
          }
        } catch (_) {}
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Analysis failed: $e')));
    } finally {
      if (mounted) setState(() => _isProcessingShare = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('影片播放')),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: _isVideoLoading
                  ? const CircularProgressIndicator()
                  : _videoLoadError != null
                      ? Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
                              const SizedBox(height: 12),
                              Text(_videoLoadError!, textAlign: TextAlign.center),
                              const SizedBox(height: 12),
                              ElevatedButton.icon(onPressed: _initializeVideo, icon: const Icon(Icons.refresh), label: const Text('重新嘗試載入')),
                            ],
                          ),
                        )
                      : AspectRatio(
                          aspectRatio: _videoController!.value.aspectRatio,
                          child: Stack(
                            children: [
                              VideoPlayer(_videoController!),
                              if (_classificationLabel != null)
                                Positioned(
                                  top: 12, left: 12,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(20)),
                                    child: Text(_classificationLabel!, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                                  ),
                                ),
                              if (_classificationFeatures.isNotEmpty)
                                Positioned(
                                  top: 56, left: 12,
                                  child: Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        _featRow('rms_dbfs', _classificationFeatures['rms_dbfs']),
                                        _featRow('spectral_centroid', _classificationFeatures['spectral_centroid']),
                                        _featRow('sharpness_hfxloud', _classificationFeatures['sharpness_hfxloud']),
                                        _featRow('highband_amp', _classificationFeatures['highband_amp']),
                                        _featRow('peak_dbfs', _classificationFeatures['peak_dbfs']),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange),
                      onPressed: _isGeneratingHighlight ? null : _generateHighlight,
                      icon: _isGeneratingHighlight ? const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2,color:Colors.white)) : const Icon(Icons.movie),
                      label: const Text('一鍵生成 Highlight'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile.adaptive(
                    value: _attachAvatar,
                    onChanged: !_avatarSelectable ? null : (value) => setState(() => _attachAvatar = value),
                    title: const Text('右上角加入我的個人頭像'),
                    subtitle: Text(!_avatarSelectable ? '尚未設定個人頭像。' : '開啟後會以圓形頭像覆蓋在影片右上角。', style: const TextStyle(fontSize: 12)),
                    activeColor: const Color(0xFF1E8E5A),
                  ),
                  TextField(
                    controller: _captionController,
                    maxLength: 50,
                    decoration: const InputDecoration(labelText: '影片下方文字', hintText: '輸入要顯示在影片底部的描述', counterText: ''),
                  ),
                  if (_isProcessingShare) const LinearProgressIndicator(),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      ElevatedButton.icon(onPressed: _reAnalyzeForVideo, icon: const Icon(Icons.refresh), label: const Text('Re-run analysis')),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _buildShareButton(icon: Icons.photo_camera, label: 'Instagram', color: const Color(0xFFC13584), target: _ShareTarget.instagram),
                      const SizedBox(width: 12),
                      _buildShareButton(icon: Icons.facebook, label: 'Facebook', color: const Color(0xFF1877F2), target: _ShareTarget.facebook),
                      const SizedBox(width: 12),
                      _buildShareButton(icon: Icons.chat, label: 'LINE', color: const Color(0xFF00C300), target: _ShareTarget.line),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _canControlVideo ? () => setState(() { _videoController!.value.isPlaying ? _videoController!.pause() : _videoController!.play(); }) : null,
        child: Icon(_canControlVideo && _videoController!.value.isPlaying ? Icons.pause : Icons.play_arrow),
      ),
    );
  }
}
