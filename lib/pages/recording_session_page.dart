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
import '../services/keep_screen_on_service.dart';
import '../services/video_overlay_processor.dart';

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
  final String? userAvatarPath; // 首頁帶入的個人頭像路徑，供分享影片時疊加

  const RecordingSessionPage({
    super.key,
    required this.cameras,
    required this.isImuConnected,
    required this.totalRounds,
    required this.durationSeconds,
    required this.autoStartOnReady,
    required this.imuButtonStream,
    this.userAvatarPath,
  });

  @override
  State<RecordingSessionPage> createState() => _RecordingSessionPageState();
}

class _RecordingSessionPageState extends State<RecordingSessionPage> {
  // ---------- 狀態變數區 ----------
  CameraController? controller; // 控制鏡頭操作
  CameraDescription? _activeCamera; // 紀錄當前使用的鏡頭，確保預覽與錄影一致
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
  final _SessionProgress _sessionProgress = _SessionProgress(); // 集中管理倒數秒數與剩餘輪次
  Future<void> _cameraOperationQueue = Future.value(); // 鏡頭操作排程，確保同一時間僅執行一個任務
  bool _isRunningCameraTask = false; // 標記是否正在執行鏡頭任務，提供再入檢查
  bool _isDisposing = false; // 錄影頁是否進入釋放狀態，避免離場後仍排程新任務

  // ---------- 生命週期 ----------
  @override
  void initState() {
    super.initState();
    // 進入錄影頁後立即鎖定螢幕常亮，避免長時間錄製時裝置自動休眠
    unawaited(KeepScreenOnService.enable());
    initVolumeKeyListener(); // 建立音量鍵快捷鍵
    // 鎖定裝置方向為直向，以維持預覽與錄影皆為直式畫面
    SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
      DeviceOrientation.portraitUp,
    ]);
    _sessionProgress.resetForNewSession(widget.totalRounds); // 初始化狀態列顯示預設剩餘次數
    _prepareSession(); // 非同步初始化鏡頭，等待使用者手動啟動
    _pendingAutoStart = widget.autoStartOnReady; // 若由 IMU 開啟則在鏡頭就緒後自動啟動
    // 監聽 IMU 按鈕事件，隨時可從硬體直接觸發錄影
    _imuButtonSubscription = widget.imuButtonStream.listen((_) {
      unawaited(_handleImuButtonTrigger());
    });
  }

  @override
  void dispose() {
    _isDisposing = true; // 標記進入釋放流程，後續若仍有任務會優先收斂
    _triggerCancel(); // 優先發出取消訊號，停止所有倒數與錄影
    // 透過排程方式串接停止錄影與控制器釋放，避免和其他鏡頭任務互搶資源。
    final Future<void> stopFuture = _stopActiveRecording(updateUi: false);
    final CameraController? controllerToDispose = controller;
    controller = null; // 提前解除引用，減少後續誤用機率
    _cameraOperationQueue = _cameraOperationQueue.then((_) async {
      await stopFuture; // 確保已停止錄影後再釋放控制器
      await controllerToDispose?.dispose();
    });
    unawaited(_cameraOperationQueue); // 無須等待完成即可繼續進行其餘釋放流程
    _volumeChannel.setMethodCallHandler(null); // 解除音量鍵監聽，避免重複綁定
    _audioPlayer.dispose();
    _imuButtonSubscription?.cancel(); // 解除 IMU 按鈕監聽，避免資源洩漏
    _sessionProgress.dispose(); // 停止狀態列的計時器，避免離開頁面後仍持續觸發 setState
    // 還原應用允許的方向，避免離開錄影頁後仍被鎖定
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    // 離開頁面時恢復系統預設的螢幕休眠行為
    unawaited(KeepScreenOnService.disable());
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

    // 依照優先順序逐一測試可用鏡頭，若後鏡頭配置失敗會自動退回其他鏡頭。
    _CameraSelectionResult? selection;
    CameraDescription? selectedCamera;
    for (final CameraDescription candidate in _orderedCameras(widget.cameras)) {
      selection = await _createBestCameraController(candidate);
      if (selection != null) {
        selectedCamera = candidate;
        break; // 找到可成功初始化的鏡頭立即停止搜尋
      }
    }

    if (selection == null || selectedCamera == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('無法初始化鏡頭，請稍後再試。')),
      );
      return;
    }

    await _applyCameraSelection(selection, selectedCamera);

    if (_pendingAutoStart) {
      // 鏡頭就緒後若先前已有硬體按鈕請求，立即啟動倒數錄影
      _pendingAutoStart = false;
      unawaited(_handleImuButtonTrigger());
    }
  }

  /// 套用鏡頭初始化結果，統一計算預覽比例與方向設定。
  Future<void> _applyCameraSelection(
    _CameraSelectionResult selection,
    CameraDescription camera,
  ) async {
    controller = selection.controller;
    _activeCamera = camera;

    // 針對大多數手機相機，感光元件以橫向為主，因此在直向預覽時需要將寬高互換。
    // 透過感測器角度判斷是否應交換寬高，再計算適用於直式畫面的長寬比。
    final bool shouldSwapSide =
        controller!.description.sensorOrientation % 180 != 0;
    if (selection.previewSize != null) {
      _previewAspectRatio = shouldSwapSide
          ? selection.previewSize!.height / selection.previewSize!.width
          : selection.previewSize!.width / selection.previewSize!.height;
    } else {
      final double rawAspect = controller!.value.aspectRatio;
      _previewAspectRatio = shouldSwapSide ? (1 / rawAspect) : rawAspect;
    }

    // 鎖定鏡頭拍攝方向為直向，確保錄影檔案不會自動旋轉。
    try {
      await controller!.lockCaptureOrientation(DeviceOrientation.portraitUp);
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('lockCaptureOrientation 失敗：$error\n$stackTrace');
      }
    }

    if (kDebugMode) {
      // 藉由除錯訊息確認實際採用的解析度（部分平台無法回報幀率）。
      debugPrint(
        'Camera initialized with preset ${selection.preset}, size=${selection.previewSize ?? '未知'}, description=${controller!.description.name}',
      );
    }

    if (mounted) {
      setState(() {}); // 更新畫面顯示預覽
    }
  }

  /// 針對指定鏡頭，嘗試使用最佳解析度與幀率進行初始化
  Future<_CameraSelectionResult?> _createBestCameraController(
      CameraDescription description) async {
    // 解析度優先順序：依照畫質由高至低逐一嘗試。
    // 依照需求改為優先採用最高畫質（max → ultraHigh → veryHigh），確保能取得最清晰的錄影畫面。
    // 若裝置在高規格模式初始化失敗，仍會退回較低解析度，兼顧穩定性與畫質需求。
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
        // 透過手動套用逾時計時，若設備長時間卡在 Camera2 配置階段則直接切換下一種解析度。
        await testController
            .initialize()
            .timeout(const Duration(seconds: 6), onTimeout: () {
          // 6 秒內仍未完成初始化代表裝置可能無法支援該解析度，直接丟出逾時讓外層重試下一個設定。
          throw TimeoutException('initialize timeout');
        });

        // 在初始化後立即準備錄影管線，避免真正開始錄影時觸發重新配置導致鏡頭切換
        try {
          await testController.prepareForVideoRecording();
        } catch (error, stackTrace) {
          // 部分平台可能尚未實作此 API，失敗時僅輸出除錯資訊不阻斷流程
          if (kDebugMode) {
            debugPrint('prepareForVideoRecording 失敗：$error\n$stackTrace');
          }
        }

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
      } on TimeoutException catch (_) {
        // 針對逾時個案輸出除錯訊息，讓開發者能追蹤實際退回的解析度。
        if (kDebugMode) {
          debugPrint('Camera initialize timeout on preset $preset，改用下一個設定');
        }
        await testController.dispose();
      } catch (_) {
        await testController.dispose();
      }
    }

    return null;
  }

  /// 根據鏡頭清單建立優先順序，遇到後鏡頭初始化失敗時可退回其他鏡頭
  List<CameraDescription> _orderedCameras(List<CameraDescription> cameras) {
    final List<CameraDescription> backCameras = <CameraDescription>[]; // 主要使用後鏡頭
    final List<CameraDescription> frontCameras = <CameraDescription>[]; // 次要使用前鏡頭
    final List<CameraDescription> externalCameras = <CameraDescription>[]; // 可能存在的外接鏡頭
    final List<CameraDescription> others = <CameraDescription>[]; // 其餘未知型別鏡頭

    for (final CameraDescription camera in cameras) {
      switch (camera.lensDirection) {
        case CameraLensDirection.back:
          backCameras.add(camera);
          break;
        case CameraLensDirection.front:
          frontCameras.add(camera);
          break;
        case CameraLensDirection.external:
          externalCameras.add(camera);
          break;
        default:
          others.add(camera);
          break;
      }
    }

    // ---------- 佈局說明 ----------
    // 1. 後鏡頭 → 外接鏡頭 → 前鏡頭 → 其他：滿足大多數錄影需求並保留替代方案。
    // 2. 若裝置僅有單一鏡頭則順序即為原清單，保持兼容性。
    return <CameraDescription>[
      ...backCameras,
      ...externalCameras,
      ...frontCameras,
      ...others,
    ];
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
          child: CameraPreview(
            controller!,
            child: const SizedBox.shrink(), // 仍可於未來覆寫疊層
          ),
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
    _sessionProgress.resetToIdle(setStateCallback: mounted ? setState : null); // 取消時立即重置倒數資訊
  }

  /// 主動停止鏡頭錄影與音訊擷取，確保返回上一頁後不再持續錄製
  Future<void> _stopActiveRecording({
    bool updateUi = true,
    bool refreshCamera = false,
  }) async {
    if (!isRecording && !_isCountingDown && controller != null && !(controller!.value.isRecordingVideo)) {
      return; // 若沒有任何錄影流程在進行，可直接返回
    }

    try {
      await _audioPlayer.stop();
    } catch (_) {
      // 音檔可能尚未播放完成，忽略停止時的錯誤
    }

    await _runCameraSerial<void>(() async {
      if (controller == null || !controller!.value.isRecordingVideo) {
        return; // 鏡頭已停止或尚未啟動錄影，無需額外處理
      }
      try {
        await controller!.stopVideoRecording();
      } catch (_) {
        // 若已停止或尚未開始錄影，忽略錯誤
      }
    }, debugLabel: 'stopActiveRecording');

    await _closeAudioPipeline();

    if (ImuDataLogger.instance.hasActiveRound) {
      await ImuDataLogger.instance.abortActiveRound();
    }

    if (mounted && updateUi) {
      setState(() => isRecording = false);
    } else {
      isRecording = false;
    }

    if (refreshCamera && controller != null && controller!.value.isInitialized) {
      try {
        // 取消或結束錄影時強制刷新鏡頭，避免返回首頁後鏡頭仍處於卡住狀態。
        await _refreshCameraAfterRound(hasMoreRounds: true);
      } catch (error, stackTrace) {
        if (kDebugMode) {
          debugPrint('強制停止錄影後刷新鏡頭失敗：$error\n$stackTrace');
        }
      }
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

  /// 重新準備錄影管線，避免多輪錄影時因為缺少關鍵影格而產生空檔案。
  Future<void> _prepareRecorderSurface() async {
    await _runCameraSerial<void>(() async {
      if (_isDisposing) {
        return; // 頁面已進入釋放狀態時，不再進行暖機避免排程殘留
      }
      if (controller == null || !controller!.value.isInitialized) {
        return; // 控制器尚未就緒時不進行預熱，避免觸發例外
      }
      if (controller!.value.isRecordingVideo) {
        return; // 避免錄影進行中重複呼叫導致例外
      }
      try {
        // CameraX 需在每次錄影前重新 warm up，否則有機率等不到第一個 I-Frame。
        await controller!.prepareForVideoRecording();
        await _performWarmupRecording();
      } catch (error, stackTrace) {
        if (kDebugMode) {
          debugPrint('prepareForVideoRecording 重新預熱失敗：$error\n$stackTrace');
        }
      }
    }, debugLabel: 'prepareRecorderSurface');
  }

  /// 進行短暫暖機錄影，確保下一輪正式錄影能立即產生關鍵影格。
  Future<void> _performWarmupRecording() async {
    if (controller == null || !controller!.value.isInitialized) {
      return;
    }
    if (controller!.value.isRecordingVideo) {
      return; // 外層已啟動錄影時不可重複進行暖機。
    }

    // 若預覽仍處於暫停狀態，先嘗試恢復以免暖機錄影缺少畫面來源。
    if (controller!.value.isPreviewPaused) {
      try {
        await controller!.resumePreview();
      } catch (error) {
        if (kDebugMode) {
          debugPrint('暖機前恢復預覽失敗：$error');
        }
      }
    }

    try {
      await controller!.startVideoRecording();
      await Future.delayed(const Duration(milliseconds: 600));
      final XFile warmupFile = await controller!.stopVideoRecording();
      await _deleteWarmupFile(warmupFile.path);
      try {
        await controller!.prepareForVideoRecording();
      } catch (error, stackTrace) {
        if (kDebugMode) {
          debugPrint('暖機後重新 prepare 失敗：$error\n$stackTrace');
        }
      }
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('暖機錄影失敗：$error\n$stackTrace');
      }

      // 若暖機過程中仍有錄影未停止，強制停止並清理暫存檔。
      if (controller != null && controller!.value.isRecordingVideo) {
        try {
          final XFile leftover = await controller!.stopVideoRecording();
          await _deleteWarmupFile(leftover.path);
        } catch (_) {}
      }
    }
  }

  /// 刪除暖機產生的臨時檔案，避免佔用儲存空間與誤判為正式影片。
  Future<void> _deleteWarmupFile(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      return;
    }
    try {
      await file.delete();
    } catch (error) {
      if (kDebugMode) {
        debugPrint('刪除暖機影片失敗：$error');
      }
    }
  }

  /// 錄製結束後重建鏡頭控制器，確保下一輪能在乾淨狀態下重新配置。
  Future<void> _resetCameraForNextRound() async {
    await _runCameraSerial<void>(() async {
      final CameraDescription? targetCamera = _activeCamera;
      if (targetCamera == null) {
        return; // 尚未記錄當前鏡頭時不需重置。
      }

      final CameraController? oldController = controller;
      controller = null;
      if (mounted && !_isDisposing) {
        setState(() {}); // 先重設狀態避免 UI 仍引用舊控制器。
      }

      try {
        await oldController?.dispose();
      } catch (error) {
        if (kDebugMode) {
          debugPrint('釋放舊鏡頭控制器失敗：$error');
        }
      }

      if (_isDisposing) {
        return; // 頁面離場時不再重新初始化鏡頭，直接結束任務
      }

      final _CameraSelectionResult? selection =
          await _createBestCameraController(targetCamera);
      if (selection == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('鏡頭重新初始化失敗，請稍後再試。')),
          );
        }
        return;
      }

      await _applyCameraSelection(selection, targetCamera);
    }, debugLabel: 'resetCameraForNextRound');
  }

  /// 依剩餘輪次調整鏡頭狀態：每輪都先完整重建控制器，最後一輪額外暖機，確保預覽不卡住。
  Future<void> _refreshCameraAfterRound({required bool hasMoreRounds}) async {
    try {
      // 無論是否仍有下一輪，都先完整釋放並重建鏡頭，確保預覽畫面回到乾淨狀態。
      await _resetCameraForNextRound();

      if (!hasMoreRounds && controller != null && controller!.value.isInitialized) {
        // 最後一輪結束後仍預先暖機一次，方便使用者再次啟動錄影時不必等待。
        await _prepareRecorderSurface();
      }
    } catch (error) {
      if (kDebugMode) {
        debugPrint('錄影結束後重新整理鏡頭失敗：$error');
      }
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
    const int countdownSeconds = 3; // 倒數音效長度（秒）
    const int bufferSeconds = 3; // 倒數後的緩衝時間
    final int totalSeconds = countdownSeconds + bufferSeconds;

    _sessionProgress.startCountdown(
      seconds: totalSeconds,
      setStateCallback: mounted ? setState : null,
    );

    await _audioPlayer.open(
      Audio('assets/sounds/1.mp3'),
      autoStart: true,
      showNotification: false,
    );

    final Future<void> countdownFuture = _waitForDuration(totalSeconds);
    final Future<void> audioFuture = _audioPlayer.playlistFinished.first;

    await Future.any([
      Future.wait([countdownFuture, audioFuture]),
      if (_cancelCompleter != null) _cancelCompleter!.future,
    ]);

    _sessionProgress.finishCountdown(setStateCallback: mounted ? setState : null);
  }

  /// 進行一次錄影流程（倒數 -> 錄影 -> 儲存）
  Future<bool> _recordOnce(int index) async {
    if (_shouldCancelRecording) {
      return false; // 若已收到取消訊號則直接跳出，避免繼續操作鏡頭
    }

    bool recordedSuccessfully = false; // 標記本輪是否完整完成，供外層計算剩餘次數
    try {
      waveformAccumulated.clear();
      await _prepareRecorderSurface();

      await initAudioCapture();
      if (_shouldCancelRecording) {
        await _closeAudioPipeline();
        if (ImuDataLogger.instance.hasActiveRound) {
          await ImuDataLogger.instance.abortActiveRound();
        }
        return false;
      }

      final baseName = ImuDataLogger.instance.buildBaseFileName(
        roundIndex: index + 1,
      );
      await ImuDataLogger.instance.startRoundLogging(baseName);

      await _runCameraSerial<void>(() async {
        if (controller == null || controller!.value.isRecordingVideo) {
          return; // 已在錄影中時不重複啟動
        }
        await controller!.startVideoRecording();
      }, debugLabel: 'startVideoRecording');

      _sessionProgress.startRecording(
        seconds: widget.durationSeconds,
        setStateCallback: mounted ? setState : null,
      );

      await _waitForDuration(widget.durationSeconds);

      if (_shouldCancelRecording) {
        await _runCameraSerial<void>(() async {
          if (controller == null || !controller!.value.isRecordingVideo) {
            return; // 錄影已停止或尚未啟動，無需額外處理
          }
          try {
            await controller!.stopVideoRecording();
          } catch (_) {}
        }, debugLabel: 'cancelStopVideo');
        await _closeAudioPipeline();
        if (ImuDataLogger.instance.hasActiveRound) {
          await ImuDataLogger.instance.abortActiveRound();
        }
        return false;
      }

      // 停止錄影後仍需等待 CameraX 完成封裝，避免直接複製造成無法播放的檔案。
      final XFile videoFile = await _runCameraSerial<XFile>(() async {
        if (controller == null || !controller!.value.isRecordingVideo) {
          throw StateError('錄影尚未啟動，無法取得影片檔案');
        }
        return controller!.stopVideoRecording();
      }, debugLabel: 'stopVideoRecording');
      await Future.delayed(const Duration(milliseconds: 200));
      await _closeAudioPipeline();

      final savedVideoPath = await ImuDataLogger.instance.persistVideoFile(
        sourcePath: videoFile.path,
        baseName: baseName,
      );

      String? savedThumbnailPath;
      try {
        savedThumbnailPath = await _captureThumbnail(baseName);
      } catch (error) {
        debugPrint('⚠️ 錄影後拍攝縮圖失敗：$error');
        // 若拍照失敗，嘗試確保預覽恢復以免畫面停住。
        if (controller != null && controller!.value.isPreviewPaused) {
          try {
            await controller!.resumePreview();
          } catch (resumeError) {
            debugPrint('⚠️ 拍照失敗後恢復預覽再度失敗：$resumeError');
          }
        }
      } finally {
        await _refreshCameraAfterRound(
          hasMoreRounds: index < widget.totalRounds - 1,
        );
      }
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
        thumbnailPath: savedThumbnailPath,
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
      recordedSuccessfully = true;
    } catch (e) {
      await ImuDataLogger.instance.abortActiveRound();
      debugPrint('❌ 錄影時出錯：$e');
    }

    return recordedSuccessfully;
  }

  /// 排程鏡頭任務，確保相機資源一次只被一個流程操作。
  Future<T> _runCameraSerial<T>(
    Future<T> Function() task, {
    String? debugLabel,
  }) {
    if (_isRunningCameraTask) {
      // 若已在鎖內部執行，直接執行傳入任務以避免死鎖。
      return task();
    }

    final Completer<T> completer = Completer<T>();

    Future<void> runner() async {
      _isRunningCameraTask = true;
      try {
        if (debugLabel != null && kDebugMode) {
          debugPrint('🎥 [$debugLabel] 任務開始');
        }
        final T result = await task();
        if (debugLabel != null && kDebugMode) {
          debugPrint('🎥 [$debugLabel] 任務結束');
        }
        if (!completer.isCompleted) {
          completer.complete(result);
        }
      } catch (error, stackTrace) {
        if (debugLabel != null && kDebugMode) {
          debugPrint('🎥 [$debugLabel] 任務失敗：$error');
        }
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      } finally {
        _isRunningCameraTask = false;
      }
    }

    _cameraOperationQueue = _cameraOperationQueue.then((_) => runner());
    return completer.future;
  }

  /// 捕捉當前畫面作為縮圖，並在序列鎖下執行避免 ImageReader 緩衝耗盡。
  Future<String?> _captureThumbnail(String baseName) async {
    return _runCameraSerial<String?>(() async {
      if (_isDisposing) {
        return null; // 頁面即將離場，略過縮圖產生以縮短釋放時間
      }
      if (controller == null || !controller!.value.isInitialized) {
        return null; // 控制器已被釋放或尚未完成初始化，直接略過縮圖
      }

      // ---------- 拍攝縮圖 ----------
      // 先暫停預覽以釋放預覽緩衝區，避免持續出現 ImageReader 無法取得緩衝的警告。
      bool needResume = false;
      if (!controller!.value.isPreviewPaused) {
        try {
          await controller!.pausePreview();
          needResume = true;
        } catch (pauseError) {
          debugPrint('⚠️ 暫停預覽時發生錯誤：$pauseError');
        }
      }

      try {
        final stillImage = await controller!.takePicture();
        return await ImuDataLogger.instance.persistThumbnailFromPicture(
          sourcePath: stillImage.path,
          baseName: baseName,
        );
      } finally {
        // 拍照結束後恢復預覽，確保畫面持續更新。
        if (needResume && controller != null && controller!.value.isPreviewPaused) {
          try {
            await controller!.resumePreview();
          } catch (resumeError) {
            debugPrint('⚠️ 恢復預覽時發生錯誤：$resumeError');
          }
        }
      }
    }, debugLabel: 'captureThumbnail');
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
        _sessionProgress.resetForNewSession(widget.totalRounds); // 新一輪錄影重新計算剩餘次數
      });
    } else {
      isRecording = true;
      _hasTriggeredRecording = true;
      _sessionProgress.resetForNewSession(widget.totalRounds);
    }

    _shouldCancelRecording = false;
    _cancelCompleter = Completer<void>();

    try {
      for (int i = 0; i < widget.totalRounds; i++) {
        if (_shouldCancelRecording) break;

        _sessionProgress.markCurrentRound(i + 1, setStateCallback: mounted ? setState : null);
        await _playCountdown();
        if (_shouldCancelRecording) break;

        final bool recorded = await _recordOnce(i);
        if (recorded) {
          _sessionProgress.completeCurrentRound(setStateCallback: mounted ? setState : null);
        }
        if (_shouldCancelRecording) break;

        if (recorded && i < widget.totalRounds - 1) {
          _sessionProgress.startRest(
            seconds: _restSecondsBetweenRounds,
            setStateCallback: mounted ? setState : null,
          );
          await _waitForDuration(_restSecondsBetweenRounds);
        }
      }
    } finally {
      _cancelCompleter = null;
      _shouldCancelRecording = false;
      _sessionProgress.resetToIdle(setStateCallback: mounted ? setState : null);
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
      MaterialPageRoute(
        builder: (_) => VideoPlayerPage(
          videoPath: filePath,
          avatarPath: widget.userAvatarPath,
        ),
      ),
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
    await _stopActiveRecording(refreshCamera: true);

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
            _SessionStatusBar(
              totalRounds: widget.totalRounds,
              remainingRounds: _sessionProgress.calculateRemainingRounds(),
              activePhase: _sessionProgress.activePhase,
              secondsLeft: _sessionProgress.secondsLeft,
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

/// 錄影流程的各種階段，以便統一更新狀態列與倒數資訊
enum _SessionPhase { idle, countdown, recording, rest }

/// 專責管理倒數秒數、剩餘輪次與計時器的協助類別
class _SessionProgress {
  int _totalRounds = 0; // 本次預計錄影的總輪數
  int _completedRounds = 0; // 已成功完成的輪數
  int _currentRound = 0; // 目前正在處理的輪數（含倒數或錄影中）

  _SessionPhase activePhase = _SessionPhase.idle; // 當前階段
  int secondsLeft = 0; // 當前階段剩餘秒數

  Timer? _timer; // 控制倒數的計時器

  /// 初始化新的錄影任務，重置剩餘輪數與倒數資訊
  void resetForNewSession(int totalRounds) {
    _cancelTimer();
    _totalRounds = totalRounds;
    _completedRounds = 0;
    _currentRound = 0;
    activePhase = _SessionPhase.idle;
    secondsLeft = 0;
  }

  /// 紀錄目前準備進行的輪次，讓剩餘次數即刻反映
  void markCurrentRound(int roundIndex, {void Function(VoidCallback fn)? setStateCallback}) {
    void update(VoidCallback fn) {
      if (setStateCallback != null) {
        setStateCallback!(fn);
      } else {
        fn();
      }
    }

    update(() {
      _currentRound = roundIndex;
      if (activePhase == _SessionPhase.idle) {
        activePhase = _SessionPhase.countdown;
        secondsLeft = 0;
      }
    });
  }

  /// 啟動倒數計時（含倒數音效與緩衝時間）
  void startCountdown({required int seconds, void Function(VoidCallback fn)? setStateCallback}) {
    _startPhaseTimer(
      phase: _SessionPhase.countdown,
      seconds: seconds,
      setStateCallback: setStateCallback,
    );
  }

  /// 完成倒數後重置資訊，避免停留在倒數狀態
  void finishCountdown({void Function(VoidCallback fn)? setStateCallback}) {
    if (activePhase != _SessionPhase.countdown) {
      return;
    }
    _cancelTimer();

    void update(VoidCallback fn) {
      if (setStateCallback != null) {
        setStateCallback!(fn);
      } else {
        fn();
      }
    }

    update(() {
      secondsLeft = 0;
      activePhase = _SessionPhase.idle;
    });
  }

  /// 開始正式錄影時計算剩餘秒數
  void startRecording({required int seconds, void Function(VoidCallback fn)? setStateCallback}) {
    _startPhaseTimer(
      phase: _SessionPhase.recording,
      seconds: seconds,
      setStateCallback: setStateCallback,
    );
  }

  /// 輪次完成後更新已完成數量
  void completeCurrentRound({void Function(VoidCallback fn)? setStateCallback}) {
    void update(VoidCallback fn) {
      if (setStateCallback != null) {
        setStateCallback!(fn);
      } else {
        fn();
      }
    }

    update(() {
      if (_currentRound > _completedRounds) {
        _completedRounds = _currentRound;
      }
      activePhase = _SessionPhase.idle;
      secondsLeft = 0;
    });
  }

  /// 啟動兩輪錄影間的休息倒數
  void startRest({required int seconds, void Function(VoidCallback fn)? setStateCallback}) {
    _startPhaseTimer(
      phase: _SessionPhase.rest,
      seconds: seconds,
      setStateCallback: setStateCallback,
    );
  }

  /// 手動重置狀態列，常用於取消錄影或流程結束
  void resetToIdle({void Function(VoidCallback fn)? setStateCallback}) {
    _cancelTimer();

    void update(VoidCallback fn) {
      if (setStateCallback != null) {
        setStateCallback!(fn);
      } else {
        fn();
      }
    }

    update(() {
      activePhase = _SessionPhase.idle;
      secondsLeft = 0;
      _currentRound = 0;
    });
  }

  /// 釋放計時器資源，避免離開頁面後仍持續觸發
  void dispose() {
    _cancelTimer();
  }

  /// 計算剩餘尚未完成的錄影次數
  int calculateRemainingRounds() {
    final bool roundInProgress =
        activePhase == _SessionPhase.countdown || activePhase == _SessionPhase.recording;
    final int consumed = _completedRounds + (roundInProgress ? 1 : 0);
    final int remaining = _totalRounds - consumed;
    return remaining < 0 ? 0 : remaining;
  }

  void _startPhaseTimer({
    required _SessionPhase phase,
    required int seconds,
    void Function(VoidCallback fn)? setStateCallback,
  }) {
    _cancelTimer();

    void update(VoidCallback fn) {
      if (setStateCallback != null) {
        setStateCallback!(fn);
      } else {
        fn();
      }
    }

    update(() {
      activePhase = phase;
      secondsLeft = seconds;
    });

    if (seconds <= 0) {
      if (phase != _SessionPhase.recording) {
        update(() {
          activePhase = _SessionPhase.idle;
        });
      }
      return;
    }

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final int remaining = seconds - timer.tick;
      update(() {
        secondsLeft = remaining > 0 ? remaining : 0;
        if (secondsLeft == 0 && phase != _SessionPhase.recording) {
          activePhase = _SessionPhase.idle;
        }
      });

      if (remaining <= 0) {
        timer.cancel();
        _timer = null;
      }
    });
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }
}

/// 錄影狀態列：呈現剩餘次數、倒數秒數與休息時間
class _SessionStatusBar extends StatelessWidget {
  final int totalRounds;
  final int remainingRounds;
  final _SessionPhase activePhase;
  final int secondsLeft;

  const _SessionStatusBar({
    required this.totalRounds,
    required this.remainingRounds,
    required this.activePhase,
    required this.secondsLeft,
  });

  @override
  Widget build(BuildContext context) {
    final TextStyle labelStyle = TextStyle(
      color: const Color(0xFF123B70).withOpacity(0.7),
      fontSize: 12,
      fontWeight: FontWeight.w500,
    );

    final bool showingCountdown =
        activePhase == _SessionPhase.countdown || activePhase == _SessionPhase.recording;
    final bool showingRest = activePhase == _SessionPhase.rest;

    final String countdownText = showingCountdown ? '${secondsLeft.toString()} 秒' : '--';
    final String restText = showingRest ? '${secondsLeft.toString()} 秒' : '--';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      color: const Color(0xFFE1EBF7),
      child: Row(
        children: [
          _SessionStatusTile(
            label: '剩餘錄影',
            value: '$remainingRounds / $totalRounds 次',
            labelStyle: labelStyle,
          ),
          const SizedBox(width: 12),
          _SessionStatusTile(
            label: '倒數時間',
            value: countdownText,
            labelStyle: labelStyle,
          ),
          const SizedBox(width: 12),
          _SessionStatusTile(
            label: '休息時間',
            value: restText,
            labelStyle: labelStyle,
          ),
        ],
      ),
    );
  }
}

/// 狀態列的小卡片樣式，保持排版一致
class _SessionStatusTile extends StatelessWidget {
  final String label;
  final String value;
  final TextStyle labelStyle;

  const _SessionStatusTile({
    required this.label,
    required this.value,
    required this.labelStyle,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: labelStyle),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFF123B70),
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
  bool _isProcessingShare = false; // 控制分享期間按鈕狀態，避免重複觸發
  late final bool _avatarSelectable; // 記錄頭像檔案是否存在，可供開關判斷
  bool _isVideoLoading = true; // 控制是否顯示讀取中轉圈
  String? _videoLoadError; // 若載入失敗記錄錯誤訊息，提供使用者提示與重試

  bool get _canControlVideo {
    // 畫面僅在影片初始化完成後才允許操作播放/暫停，避免觸發例外
    final controller = _videoController;
    return controller != null && controller.value.isInitialized;
  }

  // ---------- 分享相關方法區 ----------
  Future<void> _shareToTarget(_ShareTarget target) async {
    if (_isProcessingShare) {
      return; // 已經在產製分享檔案，避免同時觸發造成流程衝突
    }

    setState(() => _isProcessingShare = true);

    try {
      // 事前確認檔案是否存在，避免分享流程出現例外
      final file = File(widget.videoPath);
      if (!await file.exists()) {
        _showSnack('找不到影片檔案，無法分享。');
        return;
      }

      // 若使用者選擇加入頭像或文字，委派原生端生成覆蓋影片
      final sharePath = await _prepareShareFile();
      if (sharePath == null) {
        return; // 原生處理失敗或條件不足時直接中止
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
        await Share.shareXFiles([
          XFile(sharePath),
        ], text: _shareMessage);
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessingShare = false);
      } else {
        _isProcessingShare = false;
      }
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
        File(widget.avatarPath!).existsSync(); // 預先判斷頭像是否存在，供 UI 判斷
    unawaited(_initializeVideo()); // 進入頁面即嘗試初始化播放器
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _captionController.dispose();
    _cleanupTempFiles();
    super.dispose();
  }

  /// 初始化影片播放器，補上錯誤處理與重試機制
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

    // 若重新整理需先釋放舊控制器，避免資源外洩
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
      controller.play();
    } catch (error, stackTrace) {
      debugPrint('[VideoPlayer] 初始化失敗：$error');
      debugPrintStack(stackTrace: stackTrace);
      await controller.dispose();
      if (!mounted) {
        return;
      }
      setState(() {
        _videoController = null;
        _isVideoLoading = false;
        _videoLoadError = '無法載入影片，請稍後再試。';
      });
    }
  }

  /// 統一顯示 Snackbar，確保訊息風格一致
  void _showSnack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// 嘗試清除原生產製的暫存檔，避免長時間累積佔用空間
  void _cleanupTempFiles() {
    for (final path in _generatedTempFiles) {
      try {
        final file = File(path);
        if (file.existsSync()) {
          file.deleteSync();
        }
      } catch (_) {
        // 若刪除失敗可忽略，暫存資料夾會由系統定期清理
      }
    }
    _generatedTempFiles.clear();
  }

  /// 若使用者開啟頭像或文字選項，委派原生端生成覆蓋後的分享檔案
  Future<String?> _prepareShareFile() async {
    final bool wantsAvatar = _attachAvatar;
    final String trimmedCaption = _captionController.text.trim();
    final bool wantsCaption = trimmedCaption.isNotEmpty;

    if (wantsAvatar) {
      if (!_avatarSelectable || widget.avatarPath == null) {
        _showSnack('尚未設定個人頭像，請先到個資頁上傳照片。');
        return null;
      }
      final avatarFile = File(widget.avatarPath!);
      if (!avatarFile.existsSync()) {
        _showSnack('找不到個人頭像檔案，請重新選擇。');
        return null;
      }
    }

    final result = await VideoOverlayProcessor.process(
      inputPath: widget.videoPath,
      attachAvatar: wantsAvatar,
      avatarPath: widget.avatarPath,
      attachCaption: wantsCaption,
      caption: trimmedCaption,
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
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
                            const SizedBox(height: 12),
                            Text(
                              _videoLoadError!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 14),
                            ),
                            const SizedBox(height: 12),
                            ElevatedButton.icon(
                              onPressed: _initializeVideo,
                              icon: const Icon(Icons.refresh),
                              label: const Text('重新嘗試載入'),
                            ),
                          ],
                        )
                      : AspectRatio(
                          aspectRatio: _videoController!.value.aspectRatio,
                          child: VideoPlayer(_videoController!),
                        ),
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
                SwitchListTile.adaptive(
                  value: _attachAvatar,
                  onChanged: !_avatarSelectable
                      ? null
                      : (value) {
                          setState(() => _attachAvatar = value);
                        },
                  title: const Text('右上角加入我的個人頭像'),
                  subtitle: Text(
                    !_avatarSelectable
                        ? '尚未設定個人頭像，請先到個人資訊頁上傳照片。'
                        : '開啟後會以圓形頭像覆蓋在影片右上角。',
                    style: const TextStyle(fontSize: 12),
                  ),
                  activeColor: const Color(0xFF1E8E5A),
                ),
                TextField(
                  controller: _captionController,
                  maxLength: 50,
                  decoration: const InputDecoration(
                    labelText: '影片下方文字',
                    hintText: '輸入要顯示在影片底部的描述（可留空）',
                    counterText: '',
                  ),
                ),
                if (_isProcessingShare) ...[
                  const SizedBox(height: 8),
                  const LinearProgressIndicator(),
                ],
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
        onPressed: _canControlVideo
            ? () {
                setState(() {
                  final controller = _videoController!;
                  controller.value.isPlaying ? controller.pause() : controller.play();
                });
              }
            : null,
        child: Icon(
          _canControlVideo && _videoController!.value.isPlaying ? Icons.pause : Icons.play_arrow,
        ),
      ),
    );
  }
}
