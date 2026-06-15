import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../services/camera_permission_service.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as vt;

import '../services/audio_analysis_service.dart';
import '../services/audio_extraction_service.dart';
import '../models/recording_history_entry.dart';
import '../services/realtime_audio_service.dart';
import '../services/swing_auto_clip_service.dart';
import '../services/swing_detect_prefs.dart';
import 'device_capability.dart';
import 'live_swing_detector.dart';
import 'widgets/anchor_marker.dart';
import 'widgets/wrist_telemetry_hud.dart';
import 'native_camera_service.dart';
import 'pose_csv_writer.dart';
import 'prewarm_cleanup.dart';
import 'pose_frame_model.dart';
import 'pose_result.dart';
import 'recording_config.dart';
import 'recording_widgets.dart';
import 'widgets/recording_indicator.dart';
import 'widgets/impact_glow_overlay.dart';
import '../theme/app_theme.dart';
import 'package:golf_score_app/l10n/app_localizations.dart';
import '../services/analytics_service.dart';

typedef RecordCompleteCallback = void Function({
  required String videoPath,
  required String csvPath,
  required String audioPath,
  required int durationSeconds,
  required String? thumbnailPath,
  required String? audioLabel,
  required String aspectRatioMode,
  List<String>? audioTags,
});

class RecordScreen extends StatefulWidget {
  final RecordCompleteCallback? onComplete;
  const RecordScreen({super.key, this.onComplete});

  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen> {
  final _camera      = NativeCameraService();
  final _audioService = RealtimeAudioService();

  bool _cameraReady = false;
  StreamSubscription<NativePoseResult>? _poseSub;

  String _sessionId = '';
  String _videoPath = '';
  String _csvPath   = '';
  String _audioPath = '';
  PoseCsvWriter? _csvWriter;

  // 即時揮桿偵測：錄影中記錄擊球時刻（影片時鐘），錄後與音訊峰值聯集做自動切片
  late final LiveSwingDetector _liveDetector =
      LiveSwingDetector(onImpact: _onLiveImpact);
  final List<double> _liveImpacts = [];
  bool _bothHands = false; // 雙手判斷（設定可切換）
  int _glowDelayMs = SwingDetectPrefs.defaultGlowDelayMs; // 擊球光暈延遲（設定可調）
  double? _anchorX, _anchorY; // 擊球錨點（點選預覽設定的球位，歸一化）
  bool _useAnchor = false; // 擊球時刻 V4（錨點）；預設關閉＝V1 弧底（載入 prefs 後同步）
  bool _anchorGate = false; // 錨點偵測閘門：揮桿須經過錨點才算
  double _anchorRadius = SwingDetectPrefs.defaultAnchorRadius; // 錨點命中半徑
  double _swingFloor = SwingDetectPrefs.defaultSwingSpeedFloor; // 揮桿速度門檻
  bool _showTelemetry = false; // 除錯 HUD：顯示左右腕 Y + 速度

  /// 套用偵測器錨點：座標永遠帶入（供閘門用），V4 時刻 / 閘門各自獨立開關。
  void _applyAnchorToDetector() {
    final hasCoord = _anchorX != null && _anchorY != null;
    _liveDetector.anchorX = hasCoord ? _anchorX : null;
    _liveDetector.anchorY = hasCoord ? _anchorY : null;
    _liveDetector.useAnchorHit = _useAnchor && hasCoord;
    _liveDetector.anchorGate = _anchorGate && hasCoord;
  }

  /// 即時偵測到擊球：記錄時刻並立即 rebuild，讓光圈/徽章在擊球當下觸發
  /// （不依賴計時器 tick，避免最多 ~1s 的視覺延遲）。
  void _onLiveImpact(double impactTimeSec) {
    _liveImpacts.add(impactTimeSec);
    if (mounted) setState(() {});
  }

  bool _recording  = false;
  bool get _isRecording => _recording;
  bool _saving     = false;   // 停止錄影後的儲存階段：鎖定整個畫面
  int  _frameCount = 0;
  DateTime? _recordingStart;
  Duration  _elapsed = Duration.zero;
  Timer? _elapsedTimer;

  bool _showOverlay  = true;
  bool _isFront      = false;
  bool _pauseAnalysis = false;  // 低端裝置錄影期間暫停

  RecordingConfig _config = RecordingConfig();
  double _currentZoom = 0.0;
  double _baseZoom    = 0.0;

  // 畫面分析尺寸（歸一化座標，不需要再記錄幀尺寸）
  bool _supportsVideoAndAnalysis = true;

  @override
  void initState() {
    super.initState();
    AnalyticsService.instance.logScreen('record'); // 一般錄影畫面
    _resetSession();
    _checkDeviceCapability();
    _initCamera();
    unawaited(cleanupStalePrewarmDirs());
    SwingDetectPrefs.getBothHands().then((v) {
      if (!mounted) return;
      setState(() => _bothHands = v);
      _liveDetector.bothHands = v;
    });
    SwingDetectPrefs.getGlowDelayMs().then((v) {
      if (mounted) setState(() => _glowDelayMs = v);
    });
    SwingDetectPrefs.getUseAnchor().then((v) {
      if (!mounted) return;
      setState(() => _useAnchor = v);
      _applyAnchorToDetector();
    });
    SwingDetectPrefs.getAnchorGate().then((v) {
      if (!mounted) return;
      setState(() => _anchorGate = v);
      _applyAnchorToDetector();
    });
    SwingDetectPrefs.getAnchorRadius().then((v) {
      if (!mounted) return;
      setState(() => _anchorRadius = v);
      _liveDetector.anchorHitRadius = v;
    });
    SwingDetectPrefs.getSwingSpeedFloor().then((v) {
      if (!mounted) return;
      setState(() => _swingFloor = v);
      _liveDetector.swingSpeedFloor = v;
    });
    SwingDetectPrefs.getShowTelemetry().then((v) {
      if (mounted) setState(() => _showTelemetry = v);
    });
    SwingDetectPrefs.getAnchor().then((a) {
      if (!mounted || a == null) return;
      setState(() { _anchorX = a.$1; _anchorY = a.$2; });
      _applyAnchorToDetector();
    });
  }

  Future<void> _checkDeviceCapability() async {
    final ok = await DeviceCapability.supportsVideoAndAnalysis();
    if (mounted) setState(() => _supportsVideoAndAnalysis = ok);
  }

  Future<void> _initCamera() async {
    if (mounted) setState(() => _cameraReady = false);
    if (!await CameraPermissionService.ensure(context)) return;
    _poseSub?.cancel();
    try {
      final quality = switch (_config.quality) {
        VideoQuality.fhd => 'fhd',
        _                => 'hd',
      };
      await _camera.openCamera(facing: _isFront ? 1 : 0, quality: quality, fps: _config.fps.value);
    } catch (e) {
      debugPrint('[RecordScreen] _initCamera failed: $e');
      return;
    }
    if (!mounted) return;
    _poseSub = _camera.poseStream.listen(_onPose);
    setState(() => _cameraReady = true);

    // ★ 相機一就緒就立即預熱 Session（含 MediaRecorder surface），
    //   讓使用者按下錄製鍵時 Session 已就緒，完全無閃爍。
    _preWarmRecordingSession();
  }

  /// 預先準備路徑並預熱錄製 Session，於背景靜默執行。
  /// ★ 使用 _prewarmVideoPath 暫存，等使用者真正按下錄製才確認為 _videoPath。
  ///
  /// 注意：
  /// 1. 只有 prepareForRecording 成功後，才把 _prewarmReady 設為 true。
  /// 2. startRecording 前不可再啟動下一次 pre-warm，否則 native preparedRecPath 會被覆蓋。
  /// 3. 使用 _prewarmFuture 避免重複 prepareForRecording 造成 camera_busy。
  String _prewarmVideoPath = '';
  bool _prewarmReady = false;
  Future<void>? _prewarmFuture;
  bool _startingRecording = false;

  Future<void> _preWarmRecordingSession() {
    if (_recording || !_cameraReady) return Future.value();
    if (_prewarmFuture != null) return _prewarmFuture!;

    _prewarmFuture = _doPreWarmRecordingSession().whenComplete(() {
      _prewarmFuture = null;
    });
    return _prewarmFuture!;
  }

  Future<void> _doPreWarmRecordingSession() async {
    try {
      _prewarmReady = false;

      final appDir     = await getApplicationDocumentsDirectory();
      final sessionId  = 'pw_${DateTime.now().millisecondsSinceEpoch}';
      final sessionDir = p.join(appDir.path, 'golf_recordings', sessionId);
      await Directory(sessionDir).create(recursive: true);

      final path = p.join(sessionDir, 'swing.mp4');
      debugPrint('[RecordFlow] PREWARM 01 call prepareForRecording path=$path');

      await _camera.prepareForRecording(path: path);

      if (!mounted || _recording) return;

      _prewarmVideoPath = path;
      _prewarmReady = true;
      debugPrint('[RecordFlow] PREWARM 02 ready path=$_prewarmVideoPath');
    } catch (e) {
      _prewarmVideoPath = '';
      _prewarmReady = false;
      debugPrint('[RecordScreen] pre-warm failed (non-fatal): $e');
    }
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    _poseSub?.cancel();
    _audioService.dispose();
    _camera.dispose();
    super.dispose();
  }

  void _resetSession() {
    _sessionId    = DateTime.now().millisecondsSinceEpoch.toString();
    _videoPath    = '';
    _csvPath      = '';
    _csvWriter    = null;
    _frameCount   = 0;
    _recording    = false;
    _startingRecording = false;
    _recordingStart = null;
    _elapsed      = Duration.zero;
    _liveImpacts.clear();
    _liveDetector.reset();
  }

  Future<void> _preparePaths() async {
    _sessionId = DateTime.now().millisecondsSinceEpoch.toString();
    final appDir     = await getApplicationDocumentsDirectory();
    final sessionDir = p.join(appDir.path, 'golf_recordings', _sessionId);
    await Directory(sessionDir).create(recursive: true);
    _videoPath = p.join(sessionDir, 'swing.mp4');
    _csvPath   = p.join(sessionDir, 'pose_landmarks.live.csv');
    _audioPath = p.join(sessionDir, 'audio.wav');
    _csvWriter = PoseCsvWriter(_csvPath);
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // 儲存影片期間禁止返回，避免中斷音訊抽取/縮圖/入庫
      canPop: !_saving,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black87,
          foregroundColor: Colors.white,
          elevation: 0,
          title: Text(AppLocalizations.of(context).recordTitle),
          actions: [
            IconButton(
              tooltip: AppLocalizations.of(context).recordOverlayToggle,
              icon: Icon(Icons.person_outline_rounded,
                  color: _showOverlay ? Colors.greenAccent : Colors.white38),
              onPressed:
                  _saving ? null : () => setState(() => _showOverlay = !_showOverlay),
            ),
            // Skeleton visibility controlled natively (always shown when pose detected)
            IconButton(
              tooltip: AppLocalizations.of(context).recordSettings,
              icon: const Icon(Icons.settings_rounded),
              onPressed: (_isRecording || _saving) ? null : _showSettingsSheet,
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: _cameraReady
            ? Stack(fit: StackFit.expand, children: [
                _camera.buildPreviewWidget(),
                _buildOverlay(),
                if (_saving) const SavingScreenLock(),
              ])
            : Container(
                color: Colors.black,
                child: const Center(
                    child: CircularProgressIndicator(color: Colors.white54)),
              ),
      ),
    );
  }

  // ─── Camera Overlay ────────────────────────────────────────────────────────

  /// 點選預覽設定擊球錨點（球位）。錄製中不可改（避免誤觸）。
  void _setAnchorAt(Offset local, Size size) {
    if (_isRecording || size.width <= 0 || size.height <= 0) return;
    final ax = (local.dx / size.width).clamp(0.0, 1.0);
    final ay = (local.dy / size.height).clamp(0.0, 1.0);
    setState(() { _anchorX = ax; _anchorY = ay; });
    _applyAnchorToDetector();
    unawaited(SwingDetectPrefs.setAnchor(ax, ay));
  }

  void _clearAnchor() {
    setState(() { _anchorX = null; _anchorY = null; });
    _applyAnchorToDetector();
    unawaited(SwingDetectPrefs.clearAnchor());
  }

  Widget _buildOverlay() {
    return LayoutBuilder(builder: (context, constraints) {
      final pw = constraints.maxWidth, ph = constraints.maxHeight;
      return GestureDetector(
      onScaleStart: (_) => _baseZoom = _currentZoom,
      onScaleUpdate: (d) {
        if (d.pointerCount < 2) return;
        final z = (_baseZoom + (d.scale - 1.0) * 0.6).clamp(0.0, 1.0);
        _setZoom(z);
      },
      onTapUp: _isRecording
          ? null
          : (d) => _setAnchorAt(d.localPosition, Size(pw, ph)),
      child: Stack(fit: StackFit.expand, children: [
        // Skeleton is drawn natively on the camera Texture (SkeletonRenderer.kt / CoreGraphics)
        // No Dart-side SkeletonPainter needed.
        if (_showOverlay)
          Center(
            child: Transform.scale(
              scaleX: _isFront ? -1.0 : 1.0,
              child: Image.asset(_config.overlayAsset, fit: BoxFit.contain),
            ),
          ),
        // 戶外強光下的高可見度錄製指示：全螢幕脈動紅框
        if (_isRecording) const Positioned.fill(child: RecordingBorderOverlay()),
        // 即時擊球視覺回饋：中性光圈 + 「第 N 桿」彈出
        if (_isRecording)
          Positioned.fill(
            child: ImpactGlowOverlay(
              impactCount: _liveImpacts.length,
              // 錨點 V4：光暈畫在錨點(球位)、延遲歸零（開火時刻已是手到錨點）；
              // 否則固定偏下中央 + 弧底延遲補償。
              center: (_useAnchor && _anchorX != null && _anchorY != null)
                  ? Alignment(_anchorX! * 2 - 1, _anchorY! * 2 - 1)
                  : const Alignment(0.0, 0.35),
              triggerDelay: (_useAnchor && _anchorX != null)
                  ? Duration.zero
                  : Duration(milliseconds: _glowDelayMs),
              labelBuilder: (n) =>
                  AppLocalizations.of(context).recImpactShot(n),
            ),
          ),
        if (_isRecording)
          Positioned(
            top: 16, right: 16,
            child: RecordingIndicator(
              elapsed: _elapsed,
              frameCount: _frameCount,
              impactCount: _liveImpacts.length,
            ),
          ),
        if (!_isRecording)
          Positioned(
            top: 16, right: 16,
            child: GestureDetector(
              onTap: () async {
                _isFront = !_isFront;
                setState(() => _currentZoom = 0.0);
                _prewarmVideoPath = '';
                _prewarmReady = false;
                await _initCamera();
              },
              child: CircleButton(child: const Icon(Icons.flip_camera_ios_rounded,
                  color: Colors.white, size: 26)),
            ),
          ),
        Positioned(
          bottom: 120, left: 16,
          child: _ConfigBadge(config: _config),
        ),
        Positioned(
          bottom: 40, left: 0, right: 0,
          child: Center(child: _RecordButton(
            isRecording: _isRecording,
            onTap: _onRecordButtonTap,
          )),
        ),
        ZoomSlider(zoom: _currentZoom, onChanged: _setZoom),

        // 除錯 HUD：即時左右腕 Y + 速度
        if (_showTelemetry)
          Positioned(
            top: 16, left: 16,
            child: WristTelemetryHud(detector: _liveDetector),
          ),

        // 擊球錨點標記（點選預覽設定的球位）+ 清除鈕
        if (_anchorX != null && _anchorY != null) ...[
          Positioned(
            left: _anchorX! * pw - 16,
            top:  _anchorY! * ph - 16,
            child: const AnchorMarker(),
          ),
          if (!_isRecording)
            Positioned(
              left: _anchorX! * pw + 14,
              top:  _anchorY! * ph - 14,
              child: GestureDetector(
                onTap: _clearAnchor,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: Colors.black54, shape: BoxShape.circle),
                  child: const Icon(Icons.close, color: Colors.white, size: 14),
                ),
              ),
            ),
        ],
        // 提示：尚未設錨點且未錄製
        if (_anchorX == null && !_isRecording)
          Positioned(
            bottom: 120, right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black54, borderRadius: BorderRadius.circular(8)),
              child: Text(AppLocalizations.of(context).recTapSetImpactPoint,
                  style: const TextStyle(color: Colors.white70, fontSize: 11)),
            ),
          ),
      ]),
    );
    });
  }

  void _setZoom(double v) {
    setState(() => _currentZoom = v);
    _camera.setZoom(v);
  }

  // ─── Recording ─────────────────────────────────────────────────────────────

  void _onRecordButtonTap() {
    debugPrint('[RecordFlow] BUTTON TAP recording=$_recording starting=$_startingRecording ready=$_prewarmReady path=$_videoPath');
    _isRecording ? _stopRecording() : _startRecording();
  }

  Future<void> _startRecording() async {
    if (_startingRecording || _recording) return;
    _startingRecording = true;

    debugPrint('[RecordFlow] 01 user tap start');

    try {
      // 如果背景 pre-warm 還在跑，先等它完成，避免 startRecording 撞到 camera_busy。
      if (_prewarmFuture != null) {
        debugPrint('[RecordFlow] 02 wait current pre-warm');
        await _prewarmFuture;
      }

      _resetSession();
      _startingRecording = true;

      // ★ 優先重用已成功 prepared 的 pre-warm path。
      //   注意：只有 _prewarmReady == true 才能拿來 startRecording。
      if (_prewarmReady && _prewarmVideoPath.isNotEmpty) {
        _videoPath = _prewarmVideoPath;

        final dir = p.dirname(_videoPath);
        _sessionId = p.basename(dir);
        _csvPath   = p.join(dir, 'pose_landmarks.live.csv');
        _audioPath = p.join(dir, 'audio.wav');
        _csvWriter = PoseCsvWriter(_csvPath);

        _prewarmVideoPath = '';
        _prewarmReady = false;
        debugPrint('[RecordFlow] 03 using pre-warm path=$_videoPath');
      } else {
        await _preparePaths();
        debugPrint('[RecordFlow] 03 no ready pre-warm, call prepareForRecording path=$_videoPath');
        await _camera
            .prepareForRecording(path: _videoPath)
            .timeout(const Duration(seconds: 8), onTimeout: () {
              throw TimeoutException('prepareForRecording took >8s');
            });
        debugPrint('[RecordFlow] 04 prepareForRecording done');
      }

      // ★ 絕對不要在 startRecording 前啟動下一次 pre-warm。
      //   會覆蓋 native preparedRecPath，導致 startRecording 收不到正確 prepared session。
      debugPrint('[RecordFlow] 05 call startRecording');
      await _camera
          .startRecording(path: _videoPath)
          .timeout(const Duration(seconds: 6), onTimeout: () {
            throw TimeoutException('startRecording took >6s');
          });
      debugPrint('[RecordFlow] 06 startRecording done');
    } catch (e) {
      debugPrint('[RecordScreen] startRecording failed: $e');
      _startingRecording = false;
      return;
    }
    if (!mounted) {
      _startingRecording = false;
      return;
    }

    // ★ 不再啟動 flutter_audio_capture 即時收音：避免與原生錄影管線（mp4 音軌）
    //   同時搶麥克風造成衝突。音訊改由錄製結束後從 mp4 音軌抽出 audio.wav 分析。
    _recording      = true;
    _startingRecording = false;
    AnalyticsService.instance.logEvent('record_start', {'mode': 'record'});
    // 戶外看不清螢幕時，靠震動確認錄製已開始
    HapticFeedback.heavyImpact();
    _recordingStart = DateTime.now();
    _elapsedTimer   = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _recordingStart != null) {
        setState(() => _elapsed = DateTime.now().difference(_recordingStart!));
      }
    });

    if (!_supportsVideoAndAnalysis) {
      setState(() => _pauseAnalysis = true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppLocalizations.of(context).recordLowEndDeviceWarning),
          duration: const Duration(seconds: 3),
          backgroundColor: Colors.orange,
        ));
      }
    }
    setState(() {});
  }

  Future<void> _stopRecording() async {
    debugPrint('[RecordFlow] 06 user tap stop, call stopRecording');
    HapticFeedback.mediumImpact();   // 震動確認停止
    // ★ 最短錄製時長保護：start→stop 過快時 MediaRecorder 還沒編出任何影格，
    //   stop() 會丟 -1007 並使相機 HAL 進入 drain timeout → 後續可能 crash。
    //   先補足到最短時長再停止。
    const minRecordMs = 900;
    if (_recordingStart != null) {
      final elapsedMs = DateTime.now().difference(_recordingStart!).inMilliseconds;
      if (elapsedMs < minRecordMs) {
        await Future<void>.delayed(Duration(milliseconds: minRecordMs - elapsedMs));
      }
    }
    _elapsedTimer?.cancel();
    _recording = false;
    if (mounted) setState(() => _saving = true);   // 停止→儲存完成前鎖定畫面
    var recordOk = true;
    try {
      recordOk = await _camera
          .stopRecording()
          .timeout(const Duration(seconds: 6), onTimeout: () {
            throw TimeoutException('stopRecording took >6s');
          });
      debugPrint('[RecordFlow] 07 stopRecording done ok=$recordOk');
    } catch (e) {
      // record_failed / timeout：native 已刪除壞檔，不可繼續存檔/播放
      debugPrint('[RecordScreen] stopRecording failed: $e');
      recordOk = false;
    }
    if (_pauseAnalysis && mounted) setState(() => _pauseAnalysis = false);

    AnalyticsService.instance.logEvent('record_stop', {
      'mode': 'record',
      'ok': recordOk ? 1 : 0,
    });

    if (!recordOk) {
      // 丟棄 CSV/audio，提示重錄，並重新 pre-warm 下一次
      try { await _audioService.stop(); } catch (_) {}
      if (mounted) setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppLocalizations.of(context).recordFailed),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ));
      }
      if (mounted && !_recording) unawaited(_preWarmRecordingSession());
      return;
    }

    await _finishRecording();
  }

  Future<void> _finishRecording() async {
    final duration = _elapsed.inSeconds.clamp(1, 86400);

    // CSV 時鐘 → 影片時鐘（影片 t=0 = 第一個編碼幀，晚於 rec.start() ~0.2s）
    final csvOffsetSec = _camera.lastRecordCsvOffsetMs / 1000.0;
    _csvWriter?.timeOffsetSec = csvOffsetSec;
    try { await _csvWriter?.flush(); } catch (e) {
      debugPrint('[RecordScreen] CSV flush error: $e');
    }
    if (csvOffsetSec != 0.0 && _liveImpacts.isNotEmpty) {
      // 即時擊球時間同屬 CSV 時鐘，需一併平移
      final shifted = _liveImpacts
          .map((t) => t - csvOffsetSec)
          .where((t) => t >= 0)
          .toList();
      _liveImpacts
        ..clear()
        ..addAll(shifted);
    }

    List<String>? audioTags;
    try {
      // 從 mp4 音軌抽出 audio.wav（單一麥克風來源 = 原生錄影，無收音衝突），
      // 供 server V3 上傳與歷史重分析使用；clip_pipeline 也優先讀此檔。
      final samples = await AudioExtractionService.extractAudioFromVideo(
        videoPath: _videoPath,
        outputWavPath: _audioPath,
      );
      // tags 只有 no_audio 一種消費端（UI 無聲音 badge），對已提取的 wav
      // 做靜音檢測即可；命中評分由切片流程的 5 特徵分析負責。
      if (samples > 0) {
        audioTags =
            await AudioAnalysisService.isWavSilent(_audioPath) ? ['no_audio'] : null;
      } else {
        audioTags = ['no_audio'];   // mp4 無音軌
      }
    } catch (e) {
      debugPrint('[RecordScreen] audio processing error: $e');
    }

    // ★ 擊球事件驅動自動切片（背景）：live impacts ∪ 音訊峰值 → 切 5 秒 clip
    //   → 只對每個 clip 跑逐幀分析（~150 幀）。全片逐幀分析完全跳過，
    //   分析成本 = O(揮桿數)，與影片長度無關。
    await SwingAutoClipService.saveLiveImpacts(
        p.dirname(_videoPath), List.of(_liveImpacts));
    // 存錄製時使用的錨點（離線 V4 偵測用）——僅在啟用且已設座標時
    if (_useAnchor && _anchorX != null && _anchorY != null) {
      await SwingAutoClipService.saveAnchor(
          p.dirname(_videoPath), _anchorX, _anchorY);
    }
    final autoClipSource = RecordingHistoryEntry(
      filePath:            _videoPath,
      roundIndex:          1,
      recordedAt:          _recordingStart ?? DateTime.now(),
      durationSeconds:     duration,
      videoType:           VideoType.original,
      recordedAspectRatio: _config.aspectRatioMode,
      isFrontCamera:       _isFront,
      recordedPlatform:
          defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
    );
    unawaited(SwingAutoClipService.run(
      videoPath: _videoPath,
      sourceEntry: autoClipSource,
      liveImpacts: List.of(_liveImpacts),
    ).then((clips) =>
        debugPrint('[RecordScreen] 背景自動切片完成: ${clips.length} 桿')));

    try {
      debugPrint('[RecordFlow] 08 generateThumbnail path=$_videoPath');
      final thumbnailPath = await _generateThumbnail(_videoPath);
      debugPrint('[RecordFlow] 09 call onComplete duration=${duration}s');
      widget.onComplete?.call(
        videoPath:       _videoPath,
        csvPath:         _csvPath,
        audioPath:       _audioPath,
        durationSeconds: duration,
        thumbnailPath:   thumbnailPath,
        audioLabel:      null,
        aspectRatioMode: _config.aspectRatioMode,
        audioTags:       audioTags,
      );
      debugPrint('[RecordFlow] 10 onComplete returned');
    } catch (e) {
      debugPrint('[RecordScreen] finishRecording error: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
      // 錄製完全結束後，才準備下一次 pre-warm。
      // 不能在 startRecording 前做，否則會覆蓋 native preparedRecPath。
      if (mounted && !_recording) {
        unawaited(_preWarmRecordingSession());
      }
    }
  }

  Future<String?> _generateThumbnail(String videoPath) async {
    final file = File(videoPath);
    if (!await file.exists()) return null;
    if (await file.length() < 100 * 1024) return null;
    final outPath = p.join(file.parent.path, 'thumbnail.jpg');
    for (final timeMs in [0, 1000, 3000]) {
      try {
        final path = await vt.VideoThumbnail.thumbnailFile(
          video: videoPath, thumbnailPath: outPath,
          imageFormat: vt.ImageFormat.JPEG, maxHeight: 256,
          timeMs: timeMs, quality: 75,
        );
        if (path != null && path.isNotEmpty) return path;
      } catch (_) {}
    }
    return null;
  }

  // ─── Pose handling ─────────────────────────────────────────────────────────

  void _onPose(NativePoseResult pose) {
    if (_pauseAnalysis) return;
    if (!mounted) return;

    setState(() {});

    if (_isRecording) {
      // ★ 優先用「幀擷取時間戳 − 原生錄影起點」（同 BOOTTIME 時鐘），
      //   消除推論延遲（2 幀 in-flight + 推論 22-39ms）造成的骨架慢半拍
      double timeSec = 0.0;
      if (_recordingStart != null) {
        final wallSec =
            DateTime.now().difference(_recordingStart!).inMilliseconds / 1000.0;
        final startTs = _camera.lastRecordStartTsMs;
        if (startTs > 0 && pose.timestampMs > 0) {
          final capSec = (pose.timestampMs - startTs) / 1000.0;
          timeSec = ((capSec - wallSec).abs() < 2.0 && capSec >= 0)
              ? capSec
              : wallSec;
        } else {
          timeSec = wallSec;
        }
      }
      // 即時揮桿偵測（影片時鐘；前 3 秒為偵測器校準期，漏掉的桿由音訊峰值補）
      _liveDetector.feed(pose, timeSec);
      if (pose.isEmpty) return;
      // 座標已歸一化，PoseFrameModel 需要像素座標 → 用固定分析幀尺寸 640×360 反算
      const imgW = 640.0;
      const imgH = 360.0;
      final frameModel = PoseFrameModel.fromNative(
        frame:   _frameCount,
        timeSec: timeSec,
        poseUpdateId: _frameCount,
        pose:    pose,
        imgWidth:  imgW,
        imgHeight: imgH,
        isFrontCamera: _isFront,
      );
      _csvWriter?.addFrame(frameModel);
      _frameCount++;
    }
  }

  // ─── Settings ──────────────────────────────────────────────────────────────

  void _showSettingsSheet() {
    VideoQuality         pendingQuality = _config.quality;
    FrameRate            pendingFps     = _config.fps;
    RecordingAspectRatio pendingRatio   = _config.aspectRatio;
    bool                 pendingAudio   = _config.enableAudio;
    bool                 pendingBoth    = _bothHands;
    double               pendingFloor   = _swingFloor;
    int                  pendingGlow    = _glowDelayMs;
    bool                 pendingUseAnchor = _useAnchor;
    bool                 pendingGate      = _anchorGate;
    double               pendingRadius    = _anchorRadius;
    bool                 pendingTelemetry = _showTelemetry;
    final l10n = AppLocalizations.of(context);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setSheet) {
          return SafeArea(
            child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.videocam_rounded, color: kBrandPrimary, size: 20),
                    const SizedBox(width: 8),
                    Text(l10n.recordSettings,
                        style: const TextStyle(color: Colors.white, fontSize: 16,
                            fontWeight: FontWeight.w700)),
                    const Spacer(),
                    IconButton(icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                        onPressed: () => Navigator.pop(ctx)),
                  ]),
                  const Divider(color: Colors.white12, height: 20),

                  Text(l10n.recordVideoQuality, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                  const SizedBox(height: 10),
                  Row(children: VideoQuality.values.map((q) {
                    return Expanded(child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: SettingChip(
                        label: '${q.label}\n${q.resolution}',
                        selected: pendingQuality == q,
                        onTap: () => setSheet(() => pendingQuality = q),
                      ),
                    ));
                  }).toList()),
                  const SizedBox(height: 20),

                  Text(l10n.recordFrameRate, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                  const SizedBox(height: 10),
                  Row(children: FrameRate.values.map((f) {
                    return Expanded(child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: SettingChip(
                        label: f.label,
                        selected: pendingFps == f,
                        onTap: () => setSheet(() => pendingFps = f),
                      ),
                    ));
                  }).toList()),
                  const SizedBox(height: 20),

                  Row(children: [
                    const Icon(Icons.mic_rounded, color: Colors.white54, size: 16),
                    const SizedBox(width: 6),
                    Text(l10n.recordAudio, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                    const Spacer(),
                    Switch(
                      value: pendingAudio,
                      onChanged: (v) => setSheet(() => pendingAudio = v),
                      activeThumbColor: kBrandPrimary,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ]),
                  const SizedBox(height: 12),

                  // 雙手判斷
                  Row(children: [
                    const Icon(Icons.back_hand_outlined, color: Colors.white54, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(l10n.swingBothHands,
                            style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
                        Text(l10n.swingBothHandsDesc,
                            style: const TextStyle(color: Colors.white38, fontSize: 10.5)),
                      ]),
                    ),
                    Switch(
                      value: pendingBoth,
                      onChanged: (v) => setSheet(() => pendingBoth = v),
                      activeThumbColor: kBrandPrimary,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ]),
                  const SizedBox(height: 12),

                  // 揮桿速度門檻：峰值（嚴格雙手下兩手）需達此速度才算揮桿
                  Row(children: [
                    const Icon(Icons.speed_rounded, color: Colors.white54, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(l10n.recSwingSpeed,
                          style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                    Text(pendingFloor.toStringAsFixed(2),
                        style: const TextStyle(color: Colors.white, fontSize: 12)),
                  ]),
                  Slider(
                    value: pendingFloor.clamp(0.05, 0.30),
                    min: 0.05, max: 0.30, divisions: 25,
                    activeColor: kBrandPrimary,
                    label: pendingFloor.toStringAsFixed(2),
                    onChanged: (v) => setSheet(() => pendingFloor = v),
                  ),
                  const SizedBox(height: 12),

                  // 錨點擊球（V4）：用點選的球位當擊球點；關閉退回手腕弧底
                  Row(children: [
                    const Icon(Icons.center_focus_strong_outlined, color: Colors.white54, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(l10n.recUseAnchor,
                            style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
                        Text(l10n.recUseAnchorDesc,
                            style: const TextStyle(color: Colors.white38, fontSize: 10.5)),
                      ]),
                    ),
                    Switch(
                      value: pendingUseAnchor,
                      onChanged: (v) => setSheet(() => pendingUseAnchor = v),
                      activeThumbColor: kBrandPrimary,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ]),
                  // 錨點偵測閘門：揮桿須經過錨點半徑內才算一桿（亂揮/未經過 → 不算）
                  Row(children: [
                    const Icon(Icons.gps_fixed_rounded, color: Colors.white54, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(l10n.recAnchorGate,
                            style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
                        Text(l10n.recAnchorGateDesc,
                            style: const TextStyle(color: Colors.white38, fontSize: 10.5)),
                      ]),
                    ),
                    Switch(
                      value: pendingGate,
                      onChanged: (v) => setSheet(() => pendingGate = v),
                      activeThumbColor: kBrandPrimary,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ]),
                  // 錨點命中半徑：V4 時刻 或 閘門 任一啟用時可調
                  if (pendingUseAnchor || pendingGate) ...[
                    Row(children: [
                      const SizedBox(width: 22),
                      Expanded(
                        child: Text(l10n.recAnchorRadius,
                            style: const TextStyle(color: Colors.white54, fontSize: 11.5)),
                      ),
                      Text(pendingRadius.toStringAsFixed(2),
                          style: const TextStyle(color: Colors.white, fontSize: 12)),
                    ]),
                    Slider(
                      value: pendingRadius.clamp(0.05, 0.80),
                      min: 0.05, max: 0.80, divisions: 30,
                      activeColor: kBrandPrimary,
                      label: pendingRadius.toStringAsFixed(2),
                      onChanged: (v) => setSheet(() => pendingRadius = v),
                    ),
                  ],
                  const SizedBox(height: 12),

                  // 顯示腕點數值（除錯 HUD）
                  Row(children: [
                    const Icon(Icons.show_chart_rounded, color: Colors.white54, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(l10n.recShowTelemetry,
                          style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                    Switch(
                      value: pendingTelemetry,
                      onChanged: (v) => setSheet(() => pendingTelemetry = v),
                      activeThumbColor: kBrandPrimary,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ]),
                  const SizedBox(height: 12),

                  // 擊球光暈延遲（對齊桿頭觸球；偏早調大、偏晚調小）
                  Row(children: [
                    const Icon(Icons.blur_on_rounded, color: Colors.white54, size: 16),
                    const SizedBox(width: 6),
                    Text(l10n.recGlowDelay,
                        style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    Text('${pendingGlow}ms',
                        style: const TextStyle(color: Colors.white, fontSize: 12)),
                  ]),
                  Slider(
                    value: pendingGlow.toDouble().clamp(0, 2000),
                    min: 0, max: 2000, divisions: 40,
                    activeColor: kBrandPrimary,
                    label: '${pendingGlow}ms',
                    onChanged: (v) => setSheet(() => pendingGlow = v.round()),
                  ),
                  const SizedBox(height: 8),

                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: kBrandPrimary,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () async {
                        Navigator.pop(ctx);
                        if (pendingBoth != _bothHands) {
                          setState(() => _bothHands = pendingBoth);
                          _liveDetector.bothHands = pendingBoth;
                          unawaited(SwingDetectPrefs.setBothHands(pendingBoth));
                        }
                        if (pendingFloor != _swingFloor) {
                          setState(() => _swingFloor = pendingFloor);
                          _liveDetector.swingSpeedFloor = pendingFloor;
                          unawaited(SwingDetectPrefs.setSwingSpeedFloor(pendingFloor));
                        }
                        if (pendingGlow != _glowDelayMs) {
                          setState(() => _glowDelayMs = pendingGlow);
                          unawaited(SwingDetectPrefs.setGlowDelayMs(pendingGlow));
                        }
                        if (pendingUseAnchor != _useAnchor) {
                          setState(() => _useAnchor = pendingUseAnchor);
                          _applyAnchorToDetector();
                          unawaited(SwingDetectPrefs.setUseAnchor(pendingUseAnchor));
                        }
                        if (pendingGate != _anchorGate) {
                          setState(() => _anchorGate = pendingGate);
                          _applyAnchorToDetector();
                          unawaited(SwingDetectPrefs.setAnchorGate(pendingGate));
                        }
                        if (pendingRadius != _anchorRadius) {
                          setState(() => _anchorRadius = pendingRadius);
                          _liveDetector.anchorHitRadius = pendingRadius;
                          unawaited(SwingDetectPrefs.setAnchorRadius(pendingRadius));
                        }
                        if (pendingTelemetry != _showTelemetry) {
                          setState(() => _showTelemetry = pendingTelemetry);
                          unawaited(SwingDetectPrefs.setShowTelemetry(pendingTelemetry));
                        }
                        if (pendingQuality != _config.quality ||
                            pendingFps     != _config.fps     ||
                            pendingRatio   != _config.aspectRatio ||
                            pendingAudio   != _config.enableAudio) {
                          setState(() => _config = RecordingConfig(
                            quality:     pendingQuality,
                            fps:         pendingFps,
                            aspectRatio: pendingRatio,
                            enableAudio: pendingAudio,
                          ));
                          _prewarmVideoPath = '';
                          _prewarmReady = false;
                          await _initCamera();
                        }
                      },
                      child: Text(l10n.recordApply,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
            ),
          );
        });
      },
    );
  }
}

// ─── Sub-widgets ──────────────────────────────────────────────────────────────

class _ConfigBadge extends StatelessWidget {
  final RecordingConfig config;
  const _ConfigBadge({required this.config});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
    child: Text('${config.quality.label}  ${config.fps.label}',
        style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500)),
  );
}

/// 錄製按鈕：放大至 92dp（單手 / 戶外好觸發），外圈白環提升任何背景下的可見度，
/// 錄製中外圈脈動 halo 強化「正在錄影」回饋。
class _RecordButton extends StatefulWidget {
  final bool isRecording;
  final VoidCallback onTap;
  const _RecordButton({required this.isRecording, required this.onTap});

  @override
  State<_RecordButton> createState() => _RecordButtonState();
}

class _RecordButtonState extends State<_RecordButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  );

  @override
  void didUpdateWidget(_RecordButton old) {
    super.didUpdateWidget(old);
    if (widget.isRecording && !_c.isAnimating) {
      _c.repeat(reverse: true);
    } else if (!widget.isRecording) {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rec = widget.isRecording;
    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 104, height: 104, // 觸控熱區放大，腳架/單手好按
        child: Center(
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, __) => Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                // 白色外環，戶外深色/亮色背景皆清楚
                border: Border.all(color: Colors.white, width: 5),
                boxShadow: [
                  const BoxShadow(color: Colors.black54, blurRadius: 12, offset: Offset(0, 4)),
                  if (rec)
                    BoxShadow(
                      color: Colors.red.withValues(alpha: 0.6 * (1 - _c.value)),
                      blurRadius: 8 + 18 * _c.value,
                      spreadRadius: 2 + 8 * _c.value,
                    ),
                ],
              ),
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: rec ? 34 : 70,
                  height: rec ? 34 : 70,
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(rec ? 8 : 40),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

