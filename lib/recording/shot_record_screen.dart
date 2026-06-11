import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../models/recording_history_entry.dart';
import '../models/swing_hit.dart';
import '../pages/video_player_page.dart';
import '../services/audio_analysis_service.dart';
import '../services/audio_extraction_service.dart';
import '../services/clip_pipeline_service.dart';
import '../services/shot_sound_service.dart';
import '../services/realtime_audio_service.dart';
import '../services/recording_history_storage.dart';
import '../services/swing_impact_detector.dart';
import 'device_capability.dart';
import 'live_swing_detector.dart';
import 'native_camera_service.dart';
import 'pose_csv_writer.dart';
import 'prewarm_cleanup.dart';
import 'pose_frame_model.dart';
import 'pose_result.dart';
import 'recording_config.dart';
import 'recording_widgets.dart';

const int _autoNextShotDelaySec = 3;

enum ShotState { idle, addressing, recording, postImpact, processing, result }

class ShotRecordScreen extends StatefulWidget {
  final void Function(RecordingHistoryEntry entry)? onEntryAdded;
  const ShotRecordScreen({super.key, this.onEntryAdded});

  @override
  State<ShotRecordScreen> createState() => _ShotRecordScreenState();
}

class _ShotRecordScreenState extends State<ShotRecordScreen>
    with SingleTickerProviderStateMixin {

  // ── Services ──────────────────────────────────────────────────────────────
  final _camera       = NativeCameraService();
  final _audioService = RealtimeAudioService();
  final _soundService = ShotSoundService();
  late final LiveSwingDetector _detector;

  // ── Recording paths ───────────────────────────────────────────────────────
  String _sessionId = '';
  String _videoPath = '';
  String _csvPath   = '';
  String _audioPath = '';
  PoseCsvWriter? _csvWriter;

  // ── State machine ─────────────────────────────────────────────────────────
  ShotState _state    = ShotState.idle;
  int       _frameCount = 0;
  // 偵測器/校準時鐘起點（按下「準備」即開始，早於實際錄製）。
  // 揮桿偵測器需連續餵入跨越校準期，故用此連續時鐘；錄製/CSV 另用 _recordingStart。
  DateTime? _addressingStart;
  DateTime? _recordingStart;
  Duration  _elapsed    = Duration.zero;
  Timer? _elapsedTimer;
  Timer? _postImpactTimer;
  Timer? _countdownTick;
  Timer? _maxDurationTimer;
  Timer? _addressTimeoutTimer;   // addressing 階段未在時限內站定 → 自動取消，避免無限等待
  double _countdown = 0.0;
  static const int _maxRecordingSec = 45;
  static const int _addressTimeoutSec = 60;

  double? _impactTimeSec;
  String _processingLabel = '分析中…';
  int _sessionRoundIndex = 1;
  int _shotCount = 0;
  RecordingHistoryEntry? _latestEntry;

  // ── Pose ──────────────────────────────────────────────────────────────────
  StreamSubscription<NativePoseResult>? _poseSub;

  // ── Camera ────────────────────────────────────────────────────────────────
  bool _cameraReady  = false;
  bool _isFront      = false;
  bool _pauseAnalysis = false;
  bool _supportsVideoAndAnalysis = true;
  RecordingConfig _config = RecordingConfig();
  double _currentZoom = 0.0;
  double _baseZoom    = 0.0;

  // ── Pre-warmed recording session ──────────────────────────────────────────
  String _prewarmVideoPath = '';
  bool _prewarmReady = false;
  Future<void>? _prewarmFuture;

  // ── Address posture detection ─────────────────────────────────────────────
  int  _addressFrames = 0;
  bool _calibrationDone  = false;
  bool _addressConfirmed = false;
  Timer? _calibrationTimer;
  static const double _calibrationSec  = 3.0;
  static const double _autoStartDurSec = 1.5;
  int get _addressThreshold =>
      (_autoStartDurSec * (_config.fps == FrameRate.fps60 ? 15 : 10)).round();

  // ── Auto-next countdown ───────────────────────────────────────────────────
  Timer? _autoNextTimer;
  int _autoNextCountdown = 0;

  // ── Animation ─────────────────────────────────────────────────────────────
  late final AnimationController _pulseCtrl;
  late final Animation<double>   _pulseScale;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _pulseScale = Tween(begin: 1.0, end: 1.09).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    _detector = LiveSwingDetector(onImpact: _handleImpact);
    _loadRoundIndex();
    unawaited(cleanupStalePrewarmDirs());
    DeviceCapability.supportsVideoAndAnalysis().then((ok) {
      if (mounted) setState(() => _supportsVideoAndAnalysis = ok);
    });
    _initCamera();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _cancelAllTimers();
    _poseSub?.cancel();
    _audioService.dispose();
    _camera.dispose();
    super.dispose();
  }

  Future<void> _initCamera() async {
    if (mounted) setState(() => _cameraReady = false);
    _poseSub?.cancel();
    try {
      final quality = switch (_config.quality) {
        VideoQuality.fhd => 'fhd',
        _                => 'hd',
      };
      await _camera.openCamera(facing: _isFront ? 1 : 0, quality: quality, fps: _config.fps.value);
    } catch (e) {
      debugPrint('[ShotRecord] _initCamera failed: $e');
      return;
    }
    if (!mounted) return;
    _poseSub = _camera.poseStream.listen(_onPose);
    setState(() => _cameraReady = true);
    unawaited(_preWarmRecordingSession());
  }

  void _cancelAllTimers() {
    _elapsedTimer?.cancel();
    _postImpactTimer?.cancel();
    _countdownTick?.cancel();
    _maxDurationTimer?.cancel();
    _addressTimeoutTimer?.cancel();
    _autoNextTimer?.cancel();
    _calibrationTimer?.cancel();
  }

  Future<void> _loadRoundIndex() async {
    final existing = await RecordingHistoryStorage.instance.loadHistory();
    if (mounted) setState(() => _sessionRoundIndex = existing.length + 1);
  }

  // ── Shot reset ────────────────────────────────────────────────────────────

  void _resetShot() {
    _sessionId      = DateTime.now().millisecondsSinceEpoch.toString();
    _videoPath      = ''; _csvPath = ''; _audioPath = '';
    _csvWriter      = null;
    _frameCount     = 0;
    _addressingStart = null;
    _recordingStart = null;
    _elapsed        = Duration.zero;
    _impactTimeSec  = null;
    _latestEntry    = null;
    _addressFrames  = 0;
    _calibrationDone   = false;
    _addressConfirmed  = false;
    _detector.reset();
  }

  Future<void> _preparePaths() async {
    _sessionId = DateTime.now().millisecondsSinceEpoch.toString();
    final appDir = await getApplicationDocumentsDirectory();
    final dir    = p.join(appDir.path, 'golf_recordings', _sessionId);
    await Directory(dir).create(recursive: true);
    _videoPath = p.join(dir, 'swing.mp4');
    _csvPath   = p.join(dir, 'pose_landmarks.live.csv');
    _audioPath = p.join(dir, 'audio.wav');
    _csvWriter = PoseCsvWriter(_csvPath);
  }

  Future<void> _preparePathsFromVideoPath(String videoPath) async {
    _videoPath = videoPath;
    final dir = p.dirname(_videoPath);
    _sessionId = p.basename(dir);
    _csvPath   = p.join(dir, 'pose_landmarks.live.csv');
    _audioPath = p.join(dir, 'audio.wav');
    _csvWriter = PoseCsvWriter(_csvPath);
  }

  Future<void> _preWarmRecordingSession() {
    if (!_cameraReady || _state != ShotState.idle) return Future.value();
    if (_prewarmFuture != null) return _prewarmFuture!;

    _prewarmFuture = _doPreWarmRecordingSession().whenComplete(() {
      _prewarmFuture = null;
    });
    return _prewarmFuture!;
  }

  Future<void> _doPreWarmRecordingSession() async {
    try {
      _prewarmReady = false;

      final appDir = await getApplicationDocumentsDirectory();
      final sessionId = 'shot_pw_${DateTime.now().millisecondsSinceEpoch}';
      final dir = p.join(appDir.path, 'golf_recordings', sessionId);
      await Directory(dir).create(recursive: true);

      final path = p.join(dir, 'swing.mp4');
      debugPrint('[RecordFlow][Shot] PREWARM 01 call prepareForRecording path=$path');

      await _camera
          .prepareForRecording(path: path)
          .timeout(const Duration(seconds: 8), onTimeout: () {
            throw TimeoutException('prepareForRecording took >8s');
          });

      if (!mounted || _state != ShotState.idle) return;

      _prewarmVideoPath = path;
      _prewarmReady = true;
      debugPrint('[RecordFlow][Shot] PREWARM 02 ready path=$_prewarmVideoPath');
    } catch (e) {
      _prewarmVideoPath = '';
      _prewarmReady = false;
      debugPrint('[ShotRecord] pre-warm failed (non-fatal): $e');
    }
  }

  // ── Recording flow ────────────────────────────────────────────────────────

  Future<void> _startShot() async {
    debugPrint('[RecordFlow][Shot] 01 _startShot enter');

    if (!_cameraReady) {
      debugPrint('[RecordFlow][Shot] camera not ready, abort');
      return;
    }
    if (_state != ShotState.idle && _state != ShotState.result) {
      return;
    }

    try {
      if (_prewarmFuture != null) {
        debugPrint('[RecordFlow][Shot] 02 wait current pre-warm');
        await _prewarmFuture;
      }

      _resetShot();

      // ★ 只「預備」錄製 Session，先不 startRecording。
      //   進入 addressing 階段做校準 + 站姿偵測；待站姿確認後才真正開始錄影，
      //   使站姿提示音播放在錄製開始之前，不會被收進 mp4 音軌。
      if (_prewarmReady && _prewarmVideoPath.isNotEmpty) {
        await _preparePathsFromVideoPath(_prewarmVideoPath);
        _prewarmVideoPath = '';
        _prewarmReady = false;
        debugPrint('[RecordFlow][Shot] 03 using pre-warm path=$_videoPath');
      } else {
        await _preparePaths();
        debugPrint('[RecordFlow][Shot] 03 no ready pre-warm, call prepareForRecording path=$_videoPath');
        await _camera
            .prepareForRecording(path: _videoPath)
            .timeout(const Duration(seconds: 8), onTimeout: () {
              throw TimeoutException('prepareForRecording took >8s');
            });
        debugPrint('[RecordFlow][Shot] 04 prepareForRecording done');
      }
    } catch (e) {
      debugPrint('[ShotRecord] prepareForRecording failed: $e');
      if (mounted) setState(() => _state = ShotState.idle);
      return;
    }
    if (!mounted) return;

    // 進入 addressing：啟動偵測器/校準時鐘，等待站姿確認。
    _addressingStart = DateTime.now();
    _detector.reset();
    // ★ 校準完成以 Timer 驅動，不依賴 pose 回呼：MediaPipe 偵測不到人時
    //   原生端不會發事件，若靠 _onPose 判斷 detSec 會永遠卡在「校準中」。
    _calibrationTimer = Timer(
      Duration(milliseconds: (_calibrationSec * 1000).round()),
      () {
        if (mounted && _state == ShotState.addressing && !_calibrationDone) {
          setState(() => _calibrationDone = true);
        }
      },
    );
    _addressTimeoutTimer = Timer(
      Duration(seconds: _addressTimeoutSec),
      () {
        if (_state == ShotState.addressing) {
          _showError('未偵測到準備姿勢，已取消');
          _cancelShot();
        }
      },
    );
    HapticFeedback.selectionClick();   // 輕震動確認已進入準備
    debugPrint('[RecordFlow][Shot] 05 enter addressing (waiting for address)');
    setState(() => _state = ShotState.addressing);
  }

  /// 站姿確認後才真正開始錄影（站姿提示音此時已播完，不會入檔）。
  Future<void> _beginRecording() async {
    if (_state != ShotState.addressing || !mounted) return;
    _addressTimeoutTimer?.cancel();
    debugPrint('[RecordFlow][Shot] 06 address confirmed → startRecording path=$_videoPath');
    try {
      await _camera
          .startRecording(path: _videoPath)
          .timeout(const Duration(seconds: 6), onTimeout: () {
            throw TimeoutException('startRecording took >6s');
          });
      debugPrint('[RecordFlow][Shot] 07 startRecording done');
      // ★ 不啟動 flutter_audio_capture：原生錄影管線（mp4 音軌）為唯一麥克風來源。
    } catch (e) {
      debugPrint('[ShotRecord] startRecording failed: $e');
      _onShotRecordFailed();
      return;
    }
    if (!mounted) return;

    if (!_supportsVideoAndAnalysis) {
      setState(() => _pauseAnalysis = true);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('此裝置不支援錄影期間同步骨架偵測，仍會自動偵測揮桿'),
        duration: Duration(seconds: 3), backgroundColor: Colors.orange,
      ));
    }

    _recordingStart = DateTime.now();
    _elapsedTimer   = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _recordingStart != null) {
        setState(() => _elapsed = DateTime.now().difference(_recordingStart!));
      }
    });
    _maxDurationTimer = Timer(
      Duration(seconds: _maxRecordingSec),
      () => _stopAndProcess(isTimeout: true),
    );
    HapticFeedback.heavyImpact();   // 震動確認開始錄影
    setState(() => _state = ShotState.recording);
  }

  /// 回傳 true 表示影片成功封口；false 表示本次錄製無有效影像（壞檔已被 native 刪除）。
  Future<bool> _stopRecordingSafely() async {
    debugPrint('[RecordFlow][Shot] 07 call stopRecording');
    // ★ 最短錄製時長保護：避免 start→stop 過快導致 MediaRecorder stop() -1007 + 相機 HAL crash。
    const minRecordMs = 900;
    if (_recordingStart != null) {
      final elapsedMs = DateTime.now().difference(_recordingStart!).inMilliseconds;
      if (elapsedMs < minRecordMs) {
        await Future<void>.delayed(Duration(milliseconds: minRecordMs - elapsedMs));
      }
    }
    var recordOk = true;
    try {
      recordOk = await _camera
          .stopRecording()
          .timeout(const Duration(seconds: 6), onTimeout: () {
            throw TimeoutException('stopRecording took >6s');
          });
      debugPrint('[RecordFlow][Shot] 08 stopRecording done ok=$recordOk');
    } catch (e) {
      debugPrint('[ShotRecord] stopRecording failed: $e');
      recordOk = false;
    }
    if (_pauseAnalysis && mounted) setState(() => _pauseAnalysis = false);
    return recordOk;
  }

  void _handleImpact(double impactTimeSec) {
    if (_state != ShotState.recording || !mounted) return;
    if (!_addressConfirmed) return;
    _maxDurationTimer?.cancel();
    // impactTimeSec 是偵測器時鐘（addressing 起算）；換算為影片時鐘（錄製起算）。
    final offsetSec = (_recordingStart != null && _addressingStart != null)
        ? _recordingStart!.difference(_addressingStart!).inMilliseconds / 1000.0
        : 0.0;
    _impactTimeSec = (impactTimeSec - offsetSec).clamp(0.0, double.infinity);
    // ★ 不在錄製中播放擊球快門聲：它正落在音訊分析的 ±0.25s 擊球窗口、且是最響的人造音，
    //   會被麥克風錄進 mp4 音軌 → 誤判為擊球峰值，破壞擊球聲分類。
    //   改以震動回饋；錄製停止後的 playRecordingDone() 仍會給使用者聽覺確認。
    HapticFeedback.heavyImpact();   // 偵測到揮桿：震動回饋（戶外不必看螢幕）
    // 倒數需與實際 postImpact 收尾時長一致（3.2s = 2.5s buffer + 封口餘裕）
    setState(() { _state = ShotState.postImpact; _countdown = 3.2; });
    _countdownTick = Timer.periodic(const Duration(milliseconds: 100), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() { _countdown = (_countdown - 0.1).clamp(0.0, 9.9); });
    });
    _postImpactTimer = Timer(
      const Duration(milliseconds: 3200),
      _onPostImpactComplete,
    );
  }

  Future<void> _onPostImpactComplete() async {
    _cancelAllTimers();
    if (!mounted) return;
    setState(() => _state = ShotState.processing);
    if (await _stopRecordingSafely()) {
      await _finishShotRecording();
    } else {
      _onShotRecordFailed();
    }
  }

  Future<void> _stopAndProcess({bool isTimeout = false}) async {
    if (_state != ShotState.recording && _state != ShotState.postImpact) return;
    _cancelAllTimers();
    if (!mounted) return;
    if (_impactTimeSec == null) {
      final dur = _elapsed.inMilliseconds / 1000.0;
      _impactTimeSec = (dur - 1.0).clamp(0.5, dur);
    }
    setState(() => _state = ShotState.processing);
    if (await _stopRecordingSafely()) {
      await _finishShotRecording();
    } else {
      _onShotRecordFailed();
    }
  }

  Future<void> _cancelShot() async {
    final wasAddressing = _state == ShotState.addressing;
    _cancelAllTimers();
    if (wasAddressing) {
      // addressing 階段尚未開始錄影：只需丟棄已預備的 session，回到 idle。
      // 預備的暫存檔由 native 在下次 prepare/dispose 時清理。
      _prewarmVideoPath = '';
      _prewarmReady = false;
    } else {
      await _stopRecordingSafely();
    }
    await _audioService.stop();
    if (mounted) setState(() => _state = ShotState.idle);
    // 回到 idle 後重新預備下一次（_startShot 已消耗掉先前的 prewarm）。
    unawaited(_preWarmRecordingSession());
  }

  /// 錄製失敗（無有效影像，壞檔已被 native 刪除）：丟棄本次、提示重錄、回到 idle。
  void _onShotRecordFailed() {
    debugPrint('[ShotRecord] record failed → discard, back to idle');
    _audioService.stop();
    _prewarmVideoPath = '';
    _prewarmReady = false;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('本次揮桿錄製失敗（未取得有效影像），請重試'),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 3),
      ));
      setState(() => _state = ShotState.idle);
    }
    unawaited(_preWarmRecordingSession());
  }

  // ── Post-recording processing ─────────────────────────────────────────────

  Future<void> _logVideoSize(String path) async {
    try {
      final vp = VideoPlayerController.file(File(path));
      await vp.initialize();
      final s = vp.value.size;
      debugPrint('[ShotRecord] swing.mp4 顯示尺寸: ${s.width.toInt()}×${s.height.toInt()}');
      await vp.dispose();
    } catch (e) {
      debugPrint('[ShotRecord] 無法讀取影片尺寸: $e');
    }
  }

  Future<void> _finishShotRecording() async {
    _logVideoSize(_videoPath);

    try { await _csvWriter?.flush(); } catch (e) {
      debugPrint('[ShotRecord] CSV flush: $e');
    }

    if (mounted) setState(() => _processingLabel = '提取音訊…');
    List<String>? audioTags;
    try {
      // 從 mp4 音軌抽出 audio.wav（單一麥克風來源 = 原生錄影，無收音衝突）
      final samples = await AudioExtractionService.extractAudioFromVideo(
        videoPath: _videoPath,
        outputWavPath: _audioPath,
      );
      if (samples > 0) {
        audioTags = await _extractAudioTags(_videoPath);  // 直接分析 mp4 音軌
      } else {
        audioTags = ['no_audio'];   // mp4 無音軌
      }
    } catch (e) {
      debugPrint('[ShotRecord] audio processing: $e');
      audioTags = ['no_audio'];
    }

    // 直接用錄影即時推論的 live CSV 偵測（~15fps 取樣，零分析等待）。
    // 取樣較疏、擊球幀可能落在兩幀之間 — 已知 trade-off；
    // LiveSwingDetector 的即時擊球時間仍為兜底。
    if (mounted) setState(() => _processingLabel = '偵測擊球…');
    List<SwingHit> hits = [];
    try {
      hits = await SwingImpactDetector.detect(csvPath: _csvPath);
    } catch (e) {
      debugPrint('[ShotRecord] SwingImpactDetector: $e');
    }

    if (hits.isEmpty && _impactTimeSec != null) {
      final totalDur = _elapsed.inMilliseconds / 1000.0;
      hits = [_fallbackHit(_impactTimeSec!, totalDur, _config.fps.value)];
      debugPrint('[ShotRecord] fallback hit at ${_impactTimeSec}s');
    }

    if (hits.isEmpty) {
      _showError('未偵測到揮桿，請重試');
      if (mounted) setState(() => _state = ShotState.idle);
      return;
    }

    final sourceEntry = RecordingHistoryEntry(
      filePath:            _videoPath,
      roundIndex:          _sessionRoundIndex,
      recordedAt:          _recordingStart!,
      durationSeconds:     _elapsed.inSeconds.clamp(1, 3600),
      videoType:           VideoType.original,
      recordedAspectRatio: _config.aspectRatioMode,
      isFrontCamera:       _isFront,
    );

    if (mounted) setState(() => _processingLabel = '切片中…');
    List<ClipResult> results = [];
    try {
      results = await ClipPipelineService.run(
        hits: hits, srcVideoPath: _videoPath, sourceEntry: sourceEntry,
      );
    } catch (e) {
      debugPrint('[ShotRecord] ClipPipeline: $e');
    }

    if (results.isEmpty) {
      _showError('切片失敗，請重試');
      if (mounted) setState(() => _state = ShotState.idle);
      return;
    }

    final shotNum  = _shotCount + 1;
    final clipEntry = results.first.entry.copyWith(
      customName: '即時第$shotNum桿',
      audioTags:  audioTags,
      createdAt:  DateTime.now(),
    );
    await RecordingHistoryStorage.instance.upsertEntry(clipEntry);
    _shotCount++;

    // 切片已各自帶走影片/CSV/音訊，整個原始 session 目錄不再需要；
    // 只刪 swing.mp4 會留下 audio.wav / csv 等孤兒檔（磁碟洩漏）。
    try {
      final srcDir = Directory(p.dirname(_videoPath));
      if (await srcDir.exists()) await srcDir.delete(recursive: true);
    } catch (_) {}

    if (!mounted) return;
    _soundService.playRecordingDone();
    setState(() { _latestEntry = clipEntry; _state = ShotState.result; });
    widget.onEntryAdded?.call(clipEntry);
    _startAutoNextCountdown();

    // 處理完成後才準備下一次錄影，避免錄影開始前覆蓋 native preparedRecPath。
    unawaited(_preWarmRecordingSession());
  }

  void _startAutoNextCountdown() {
    _autoNextCountdown = _autoNextShotDelaySec;
    _autoNextTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      if (_autoNextCountdown <= 1) {
        t.cancel();
        // ★ 自動下一輪：倒數結束直接進入下一桿 addressing（不需再按「準備」），
        //   連續打位練習零操作。_startShot 接受 result 狀態並會等 prewarm。
        if (_state == ShotState.result) _startShot();
      } else {
        setState(() => _autoNextCountdown--);
      }
    });
  }

  SwingHit _fallbackHit(double impactSec, double totalDur, int fps) {
    final (s, e) = SwingImpactDetector.calculateClipBoundaries(
      hitSec: impactSec, totalDurationSec: totalDur);
    return SwingHit(
      hitIndex: 1, hitFrame: (impactSec * fps).round(),
      hitSec: impactSec, startSec: s, endSec: e,
      speedValue: 0.0, audioValue: 0.0,
    );
  }

  Future<List<String>?> _extractAudioTags(String audioPath) async {
    try {
      if (!File(audioPath).existsSync()) return ['no_audio'];
      final result  = await AudioAnalysisService.analyzeVideo(audioPath);
      final summary = result['summary'] as Map<String, dynamic>?;
      final tags    = summary?['tags'] as List<dynamic>?;
      if (tags != null && tags.isNotEmpty) return tags.whereType<String>().toList();
      return null;
    } catch (e) {
      debugPrint('[ShotRecord] audio tags: $e');
      return null;
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.orange),
    );
  }

  // ── Golf address posture detection (MediaPipe normalized coords) ───────────
  //
  // Conditions (same logic as before, adapted to normalized 0-1 coords):
  //   1. Both wrists visible (confidence > 0.5)
  //   2. Wrist mid-Y > hip mid-Y (wrists below hips in screen space)
  //   3. Wrist horizontal separation < 45% of shoulder width
  //
  // With MediaPipe LIVE_STREAM + rotation applied, coords are already in
  // display space: y increases downward, x increases rightward.
  int _postureDbgFrame = 0;

  bool _isGolfAddressPosture(NativePoseResult pose) {
    final dbg = (_postureDbgFrame++ % 20 == 0);   // ~每秒輸出一次診斷
    if (pose.isEmpty || pose.landmarks.length < 25) {
      if (dbg) debugPrint('[AddressDbg] ✗ 無骨架/點數不足 (${pose.landmarks.length})');
      return false;
    }
    final lw = pose.leftWrist;
    final rw = pose.rightWrist;
    final lh = pose.leftHip;
    final rh = pose.rightHip;
    final ls = pose.leftShoulder;
    final rs = pose.rightShoulder;
    if (lw == null || rw == null || lh == null || rh == null ||
        ls == null || rs == null) {
      if (dbg) debugPrint('[AddressDbg] ✗ 關鍵點缺失 (lw=$lw rw=$rw lh=$lh rh=$rh)');
      return false;
    }
    // ★ 雙手交疊握桿時「後面那隻手」必然被前手遮擋（vis 常 0.2-0.4），
    //   要求雙腕都 ≥0.5 等於與「雙手合攏」條件互相矛盾。
    //   放寬：主手（較清楚者）≥0.5、副手 ≥0.2 即可。
    final visHi = lw.visibility > rw.visibility ? lw.visibility : rw.visibility;
    final visLo = lw.visibility < rw.visibility ? lw.visibility : rw.visibility;
    if (visHi < 0.5 || visLo < 0.2) {
      if (dbg) {
        debugPrint('[AddressDbg] ✗ 腕可見度不足 '
            '(lw=${lw.visibility.toStringAsFixed(2)} '
            'rw=${rw.visibility.toStringAsFixed(2)})');
      }
      return false;
    }

    final hipMidY    = (lh.y + rh.y) / 2;
    final wristMidY  = (lw.y + rw.y) / 2;
    final shoulderW  = (ls.x - rs.x).abs();
    final wristDistX = (lw.x - rw.x).abs();

    // ★ 容差 8% 畫面高：站直握桿時手腕約在髖線附近，真正前傾瞄球才明顯低於髖；
    //   嚴格 > hipMidY 會把「站直握桿」拒之門外。
    final handsLow   = wristMidY > hipMidY - 0.08;
    final handsClose = wristDistX < shoulderW * 0.45;
    if (dbg) {
      debugPrint('[AddressDbg] '
          '${handsLow ? "✓" : "✗"}手低於髖 (wristY=${wristMidY.toStringAsFixed(2)} '
          'hipY=${hipMidY.toStringAsFixed(2)}) | '
          '${handsClose ? "✓" : "✗"}雙手合攏 (dist=${wristDistX.toStringAsFixed(2)} '
          '需<${(shoulderW * 0.45).toStringAsFixed(2)}) | '
          'vis L=${lw.visibility.toStringAsFixed(2)} R=${rw.visibility.toStringAsFixed(2)}');
    }
    return handsLow && handsClose;
  }

  // ── Pose callback ─────────────────────────────────────────────────────────

  void _onPose(NativePoseResult pose) {
    if (_pauseAnalysis || !mounted) return;

    // 偵測器/校準時鐘（addressing 起算，連續跨越校準期）。
    final detSec = _addressingStart != null
        ? DateTime.now().difference(_addressingStart!).inMilliseconds / 1000.0
        : 0.0;
    // 影片時鐘（錄製起算）—— CSV 與擊球時間都以此為準，與 mp4 同步。
    final videoSec = _recordingStart != null
        ? DateTime.now().difference(_recordingStart!).inMilliseconds / 1000.0
        : 0.0;

    // ── addressing：尚未錄影，做校準 + 站姿偵測（提示音不會入檔）──────────────
    if (_state == ShotState.addressing) {
      // 持續餵偵測器，使其在進入錄製前完成自身校準，避免揮桿時還在校準而漏判。
      _detector.feed(pose, detSec);

      if (!_calibrationDone) return;   // 校準完成由 _calibrationTimer 驅動
      if (!_addressConfirmed) {
        if (_isGolfAddressPosture(pose)) {
          setState(() => _addressFrames++);   // UI 顯示站姿進度
          if (_addressFrames == 1) _soundService.playPostureDetected();
          if (_addressFrames >= _addressThreshold) {
            setState(() { _addressConfirmed = true; _addressFrames = 0; });
            _beginRecording();   // ★ 站姿確認 → 此刻才真正開始錄影
          }
        } else {
          if (_addressFrames > 0) setState(() => _addressFrames = 0);
        }
      }
      return;
    }

    // ── recording / postImpact：寫 CSV（影片時鐘）、持續餵偵測器偵測揮桿 ────────
    final isActive = _state == ShotState.recording || _state == ShotState.postImpact;
    if (isActive) {
      const imgW = 640.0;
      const imgH = 360.0;
      final frameModel = pose.isEmpty
          ? PoseFrameModel.empty(frame: _frameCount, timeSec: videoSec)
          : PoseFrameModel.fromNative(
              frame:        _frameCount,
              timeSec:      videoSec,
              poseUpdateId: _frameCount,
              pose:         pose,
              imgWidth:     imgW,
              imgHeight:    imgH,
              isFrontCamera: _isFront,
            );
      _csvWriter?.addFrame(frameModel);
      // 每幀 setState 會以 ~10-30Hz 重建整個 UI 樹（耗電/掉幀）；
      // RecordingBadge 的幀數顯示每 10 幀刷新一次即可（elapsed 已有每秒 timer）。
      _frameCount++;
      if (_frameCount % 10 == 0) setState(() {});

      if (_state == ShotState.recording) {
        _detector.feed(pose, detSec);   // 偵測器仍用連續時鐘
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('即時揮桿模式'),
        actions: [
          IconButton(
            tooltip: '錄製設定',
            icon: const Icon(Icons.settings_rounded),
            onPressed: (_state == ShotState.addressing ||
                        _state == ShotState.recording ||
                        _state == ShotState.postImpact ||
                        _state == ShotState.processing)
                ? null
                : _showSettingsSheet,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _cameraReady
          ? Stack(fit: StackFit.expand, children: [
              _camera.buildPreviewWidget(),
              GestureDetector(
                onScaleStart: (_) => _baseZoom = _currentZoom,
                onScaleUpdate: (d) {
                  if (d.pointerCount < 2) return;
                  final z = (_baseZoom + (d.scale - 1.0) * 0.6).clamp(0.0, 1.0);
                  _setZoom(z);
                },
                child: Stack(fit: StackFit.expand, children: [
                  if (_state == ShotState.idle      ||
                      _state == ShotState.addressing ||
                      _state == ShotState.recording  ||
                      _state == ShotState.postImpact)
                    Center(
                      child: Transform.scale(
                        scaleX: _isFront ? -1.0 : 1.0,
                        child: Image.asset(_config.overlayAsset, fit: BoxFit.contain),
                      ),
                    ),
                  // Skeleton rendered natively on Texture (no Dart CustomPainter needed)
                  // 戶外強光下的高可見度錄製指示：偵測/錄製中全螢幕脈動紅框
                  if (_state == ShotState.recording ||
                      _state == ShotState.postImpact)
                    const Positioned.fill(child: RecordingBorderOverlay()),
                  ..._buildStateOverlay(),
                  ZoomSlider(zoom: _currentZoom, onChanged: _setZoom),
                ]),
              ),
            ])
          : Container(
              color: Colors.black,
              child: const Center(child: CircularProgressIndicator(color: Colors.white54)),
            ),
    );
  }

  void _setZoom(double v) {
    setState(() => _currentZoom = v);
    _camera.setZoom(v);
  }

  List<Widget> _buildStateOverlay() => switch (_state) {
    ShotState.idle       => _idleOverlay(),
    ShotState.addressing => _addressingOverlay(),
    ShotState.recording  => _recordingOverlay(),
    ShotState.postImpact => _postImpactOverlay(),
    ShotState.processing => _processingOverlay(),
    ShotState.result     => _resultOverlay(),
  };

  // ── idle ──────────────────────────────────────────────────────────────────
  List<Widget> _idleOverlay() => [
    Positioned(
      top: 16, right: 16,
      child: GestureDetector(
        onTap: () async {
          _isFront = !_isFront;
          _prewarmVideoPath = '';
          _prewarmReady = false;
          setState(() => _currentZoom = 0.0);
          await _initCamera();
        },
        child: CircleButton(child: const Icon(Icons.flip_camera_ios_rounded,
            color: Colors.white, size: 26)),
      ),
    ),
    if (_shotCount > 0)
      Positioned(top: 16, left: 16,
          child: _Chip(text: '已完成 $_shotCount 桿')),
    Positioned(
      bottom: 52, left: 0, right: 0,
      child: Center(child: ScaleTransition(
        scale: _pulseScale,
        child: _ShotButton(label: '準備', color: Colors.white, onTap: _startShot),
      )),
    ),
  ];

  // ── addressing（尚未錄影：校準 + 等待站姿；提示音在此播放，不入檔）──────────
  /// 大型提示膠囊：深色底 + 粗體大字，戶外強光下清楚可讀。
  Widget _promptChip(String text, {IconData? icon, Color color = Colors.white,
      String? subText}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.65),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, color: color, size: 40),
          const SizedBox(height: 8),
        ],
        Text(text,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: color, fontSize: 22, fontWeight: FontWeight.bold)),
        if (subText != null) ...[
          const SizedBox(height: 6),
          Text(subText,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 15)),
        ],
      ]),
    );
  }

  List<Widget> _addressingOverlay() => [
    if (!_calibrationDone)
      Positioned(
        bottom: 130, left: 0, right: 0,
        child: Center(child: _promptChip('校準中…請保持靜止',
            icon: Icons.hourglass_top_rounded)),
      )
    else
      Positioned(
        bottom: 130, left: 0, right: 0,
        child: Center(child: _promptChip(
          '請站到準備姿勢 ($_addressFrames/$_addressThreshold)',
          icon: Icons.sports_golf_rounded,
          subText: '站定後將自動開始錄影',
        )),
      ),
    // 等待站姿階段：只提供取消（尚未開始錄影，無停止鈕、無紅框/徽章）
    Positioned(
      bottom: 52, left: 0, right: 0,
      child: Center(child: TextButton(
        onPressed: _cancelShot,
        child: const Text('取消', style: TextStyle(color: Colors.white54, fontSize: 16)),
      )),
    ),
  ];

  // ── recording（站姿已確認、實際錄影中）──────────────────────────────────────
  List<Widget> _recordingOverlay() => [
    Positioned(top: 16, right: 16,
        child: RecordingBadge(elapsed: _elapsed, frameCount: _frameCount)),
    Positioned(
      bottom: 130, left: 0, right: 0,
      child: Center(child: _promptChip('⚡ 偵測中…請揮桿',
          color: Colors.greenAccent)),
    ),
    Positioned(
      bottom: 52, left: 0, right: 0,
      child: Center(child: _ShotButton(
        label: '停止', color: Colors.red,
        onTap: () => _stopAndProcess(),
      )),
    ),
    Positioned(
      bottom: 52, right: 24,
      child: TextButton(
        onPressed: _cancelShot,
        child: const Text('取消', style: TextStyle(color: Colors.white38)),
      ),
    ),
  ];

  // ── postImpact ────────────────────────────────────────────────────────────
  List<Widget> _postImpactOverlay() => [
    Positioned(top: 16, right: 16,
        child: RecordingBadge(elapsed: _elapsed, frameCount: _frameCount)),
    Positioned(
      bottom: 130, left: 0, right: 0,
      child: Center(child: _promptChip(
        '偵測到揮桿 ✓\n倒數 ${_countdown.toStringAsFixed(1)}s',
        color: Colors.greenAccent,
      )),
    ),
  ];

  // ── processing ────────────────────────────────────────────────────────────
  List<Widget> _processingOverlay() => [
    Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const CircularProgressIndicator(color: Colors.white70),
      const SizedBox(height: 16),
      Text(_processingLabel,
          style: const TextStyle(color: Colors.white70, fontSize: 16)),
    ])),
  ];

  // ── result ────────────────────────────────────────────────────────────────
  List<Widget> _resultOverlay() {
    final entry = _latestEntry;
    return [
      Positioned.fill(child: Container(color: Colors.black54)),
      Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 72),
        const SizedBox(height: 16),
        const Text('完成！', style: TextStyle(color: Colors.white,
            fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (entry != null)
          Text(entry.customName ?? '',
              style: const TextStyle(color: Colors.white70, fontSize: 16)),
        const SizedBox(height: 32),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (entry != null)
            OutlinedButton.icon(
              onPressed: () {
                // 跳去觀看 → 停掉自動下一輪（避免人在別頁時背景開錄）
                _autoNextTimer?.cancel();
                Navigator.push(context, MaterialPageRoute(
                  builder: (_) => VideoPlayerPage(
                    videoPath: entry.filePath,
                    entry:     entry,
                  ),
                ));
              },
              icon: const Icon(Icons.play_arrow_rounded, color: Colors.white),
              label: const Text('觀看', style: TextStyle(color: Colors.white)),
              style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white38)),
            ),
          const SizedBox(width: 16),
          FilledButton.icon(
            onPressed: () {
              _autoNextTimer?.cancel();
              _startShot();   // 立刻開始下一桿（不等倒數）
            },
            icon: const Icon(Icons.sports_golf_rounded),
            label: Text('下一桿 ($_autoNextCountdown)'),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1E8E5A)),
          ),
        ]),
      ])),
    ];
  }

  // ── Settings ──────────────────────────────────────────────────────────────

  void _showSettingsSheet() {
    VideoQuality pendingQ = _config.quality;
    FrameRate    pendingF = _config.fps;
    bool         pendingA = _config.enableAudio;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setSheet) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Column(mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.settings_rounded, color: Color(0xFF1E8E5A), size: 20),
                  const SizedBox(width: 8),
                  const Text('錄製設定', style: TextStyle(color: Colors.white,
                      fontSize: 16, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  IconButton(icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                      onPressed: () => Navigator.pop(ctx)),
                ]),
                const Divider(color: Colors.white12, height: 20),

                const Text('影片畫質', style: TextStyle(color: Colors.white54, fontSize: 12)),
                const SizedBox(height: 10),
                Row(children: VideoQuality.values.map((q) => Expanded(child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: SettingChip(
                    label: '${q.label}\n${q.resolution}',
                    selected: pendingQ == q,
                    onTap: () => setSheet(() => pendingQ = q),
                  ),
                ))).toList()),
                const SizedBox(height: 20),

                const Text('幀率', style: TextStyle(color: Colors.white54, fontSize: 12)),
                const SizedBox(height: 10),
                Row(children: FrameRate.values.map((f) => Expanded(child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: SettingChip(
                    label: f.label,
                    selected: pendingF == f,
                    onTap: () => setSheet(() => pendingF = f),
                  ),
                ))).toList()),
                const SizedBox(height: 16),

                Row(children: [
                  const Icon(Icons.mic_rounded, color: Colors.white54, size: 16),
                  const SizedBox(width: 6),
                  const Text('錄製音訊', style: TextStyle(color: Colors.white54, fontSize: 12)),
                  const Spacer(),
                  Switch(value: pendingA, onChanged: (v) => setSheet(() => pendingA = v),
                    activeThumbColor: const Color(0xFF1E8E5A),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
                ]),
                const SizedBox(height: 16),

                SizedBox(width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF1E8E5A),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () async {
                      Navigator.pop(ctx);
                      if (pendingQ != _config.quality || pendingF != _config.fps ||
                          pendingA != _config.enableAudio) {
                        setState(() => _config = RecordingConfig(
                          quality:     pendingQ,
                          fps:         pendingF,
                          aspectRatio: _config.aspectRatio,
                          enableAudio: pendingA,
                        ));
                        _prewarmVideoPath = '';
                        _prewarmReady = false;
                        await _initCamera();
                      }
                    },
                    child: const Text('套用',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(height: 8),
              ]),
            ),
          );
        });
      },
    );
  }
}

// ─── Sub-widgets ──────────────────────────────────────────────────────────────

class _Chip extends StatelessWidget {
  final String text;
  const _Chip({required this.text});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
    child: Text(text, style: const TextStyle(color: Colors.white70, fontSize: 12)),
  );
}

class _ShotButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ShotButton({required this.label, required this.color, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    behavior: HitTestBehavior.opaque,
    child: SizedBox(
      width: 104, height: 104,   // 放大觸控熱區，單手/腳架好按
      child: Center(
        child: Container(
          width: 92, height: 92,
          decoration: BoxDecoration(
            color: color, shape: BoxShape.circle,
            // 白色外環：戶外深淺背景皆清楚
            border: Border.all(color: Colors.white, width: 4),
            boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 12, offset: Offset(0, 4))],
          ),
          child: Center(child: Text(label,
              style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 17))),
        ),
      ),
    ),
  );
}

