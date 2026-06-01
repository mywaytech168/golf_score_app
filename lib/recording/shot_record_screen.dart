import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camerawesome/camerawesome_plugin.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/recording_history_entry.dart';
import '../models/swing_hit.dart';
import '../services/audio_analysis_service.dart';
import '../services/clip_pipeline_service.dart';
import '../services/realtime_audio_service.dart';
import '../services/recording_history_storage.dart';
import '../services/swing_impact_detector.dart';
import 'live_swing_detector.dart';
import 'mlkit_utils.dart';
import 'pose_csv_writer.dart';
import 'pose_detector_service.dart';
import 'pose_frame_model.dart';
import 'recording_config.dart';
import 'skeleton_painter.dart';

// ── 狀態機 ────────────────────────────────────────────────────────────────────

enum ShotState {
  idle,       // 等待使用者按下「準備」
  recording,  // 錄製中（含校準期與偵測期）
  postImpact, // 偵測到撞擊，繼續錄 2.5s follow-through
  processing, // 停止錄製，SwingDetector + ClipPipeline 跑中
  result,     // 顯示本桿結果
}

// ── Widget ────────────────────────────────────────────────────────────────────

/// 即時揮桿模式：按下「準備」→ 自動偵測撞擊 → 自動切片 → 顯示結果
class ShotRecordScreen extends StatefulWidget {
  /// 每桿 clip 建立後的回呼（供上層刷新歷史清單）
  final void Function(RecordingHistoryEntry entry)? onEntryAdded;

  const ShotRecordScreen({super.key, this.onEntryAdded});

  @override
  State<ShotRecordScreen> createState() => _ShotRecordScreenState();
}

class _ShotRecordScreenState extends State<ShotRecordScreen>
    with SingleTickerProviderStateMixin {
  // ── 服務 ────────────────────────────────────────────────────────
  final _poseService  = PoseDetectorService();
  final _audioService = RealtimeAudioService();
  late final LiveSwingDetector _detector;

  // ── 錄製路徑 ─────────────────────────────────────────────────────
  String _sessionId  = '';
  String _videoPath  = '';
  String _csvPath    = '';
  String _audioPath  = '';
  PoseCsvWriter? _csvWriter;

  // ── 狀態 ─────────────────────────────────────────────────────────
  ShotState _state  = ShotState.idle;
  bool _isPoseProcessing = false;
  int  _frameCount  = 0;
  DateTime? _recordingStart;
  Duration _elapsed = Duration.zero;
  Timer? _elapsedTimer;
  Timer? _postImpactTimer;
  Timer? _countdownTick;
  Timer? _maxDurationTimer;       // 保底：超過最大錄製時間自動停止
  double _countdown = 0.0;        // postImpact 倒數秒數（UI 顯示用）

  static const int _maxRecordingSec = 45; // 最大錄製秒數（保底）

  // ── 撞擊資料 ─────────────────────────────────────────────────────
  double? _impactTimeSec;

  // ── Session 資訊 ──────────────────────────────────────────────────
  int _sessionRoundIndex = 1;
  int _shotCount = 0;  // 本次 session 已完成幾桿

  // ── 結果 ─────────────────────────────────────────────────────────
  RecordingHistoryEntry? _latestEntry;

  // ── 骨架 ─────────────────────────────────────────────────────────
  List<Pose> _poses = [];
  Size _analysisSize = Size.zero;
  bool _showSkeleton = true;

  // ── 設定 ─────────────────────────────────────────────────────────
  RecordingConfig _config = RecordingConfig();
  bool _isFrontCamera = false;

  // ── CameraAwesome 錄製狀態（供 timer 觸發停止用）─────────────────
  VideoRecordingCameraState? _activeRecordingState;

  // ── 動畫 ─────────────────────────────────────────────────────────
  late final AnimationController _pulseCtrl;
  late final Animation<double>   _pulseScale;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _pulseScale = Tween(begin: 1.0, end: 1.09).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    _detector = LiveSwingDetector(onImpact: _handleImpact);
    _loadRoundIndex();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _elapsedTimer?.cancel();
    _postImpactTimer?.cancel();
    _countdownTick?.cancel();
    _maxDurationTimer?.cancel();
    _poseService.dispose();
    _audioService.dispose();
    super.dispose();
  }

  Future<void> _loadRoundIndex() async {
    final existing = await RecordingHistoryStorage.instance.loadHistory();
    if (mounted) setState(() => _sessionRoundIndex = existing.length + 1);
  }

  // ── Session reset ─────────────────────────────────────────────────
  void _resetShot() {
    _sessionId     = DateTime.now().millisecondsSinceEpoch.toString();
    _videoPath     = '';
    _csvPath       = '';
    _audioPath     = '';
    _csvWriter     = null;
    _frameCount    = 0;
    _recordingStart = null;
    _elapsed       = Duration.zero;
    _impactTimeSec = null;
    _poses         = [];
    _detector.reset();
  }

  // ── CameraAwesome 路徑建構（每次 startRecording 前呼叫）──────────
  Future<SingleCaptureRequest> _buildCaptureRequest(List<Sensor> sensors) async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = p.join(appDir.path, 'golf_recordings', _sessionId);
    await Directory(dir).create(recursive: true);
    _videoPath = p.join(dir, 'swing.mp4');
    _csvPath   = p.join(dir, 'pose_landmarks.csv');
    _audioPath = p.join(dir, 'audio.pcm');
    _csvWriter = PoseCsvWriter(_csvPath);
    return SingleCaptureRequest(_videoPath, sensors.first);
  }

  // ── 錄製控制 ─────────────────────────────────────────────────────

  Future<void> _startShot(VideoCameraState videoState) async {
    _resetShot();
    try { await _audioService.start(); } catch (e) {
      debugPrint('[ShotRecord] 音頻啟動失敗: $e');
    }
    await videoState.startRecording();
    if (!mounted) return;
    _recordingStart = DateTime.now();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _recordingStart != null) {
        setState(() => _elapsed = DateTime.now().difference(_recordingStart!));
      }
    });
    // 保底計時器：超時自動停止並儲存
    _maxDurationTimer = Timer(
      Duration(seconds: _maxRecordingSec),
      () => _stopAndProcess(isTimeout: true),
    );
    setState(() => _state = ShotState.recording);
  }

  void _handleImpact(double impactTimeSec) {
    if (_state != ShotState.recording || !mounted) return;
    _maxDurationTimer?.cancel();
    _impactTimeSec = impactTimeSec;
    const bufferMs = 2500;
    setState(() {
      _state     = ShotState.postImpact;
      _countdown = bufferMs / 1000.0;
    });
    _countdownTick = Timer.periodic(const Duration(milliseconds: 100), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() { _countdown = (_countdown - 0.1).clamp(0.0, 9.9); });
    });
    _postImpactTimer = Timer(
      const Duration(milliseconds: bufferMs),
      _onPostImpactComplete,
    );
  }

  Future<void> _onPostImpactComplete() async {
    _countdownTick?.cancel();
    _elapsedTimer?.cancel();
    _maxDurationTimer?.cancel();
    if (!mounted) return;
    setState(() => _state = ShotState.processing);
    final rs = _activeRecordingState;
    if (rs != null) await rs.stopRecording();
    await _finishShotRecording();
  }

  /// 手動停止 + 儲存（使用者按「停止」或超時保底）
  Future<void> _stopAndProcess({bool isTimeout = false}) async {
    if (_state != ShotState.recording && _state != ShotState.postImpact) return;
    _postImpactTimer?.cancel();
    _countdownTick?.cancel();
    _elapsedTimer?.cancel();
    _maxDurationTimer?.cancel();
    if (!mounted) return;
    // 如果沒有 impact 時間，用錄製長度估算
    if (_impactTimeSec == null) {
      final dur = _elapsed.inMilliseconds / 1000.0;
      _impactTimeSec = (dur - 1.0).clamp(0.5, dur);
    }
    setState(() => _state = ShotState.processing);
    final rs = _activeRecordingState;
    if (rs != null) await rs.stopRecording();
    await _finishShotRecording();
  }

  /// 取消（丟棄，不儲存）
  Future<void> _cancelShot() async {
    _postImpactTimer?.cancel();
    _countdownTick?.cancel();
    _elapsedTimer?.cancel();
    _maxDurationTimer?.cancel();
    final rs = _activeRecordingState;
    if (rs != null) await rs.stopRecording();
    await _audioService.stop();
    if (mounted) setState(() { _state = ShotState.idle; _poses = []; });
  }

  // ── 錄製完成後處理 ────────────────────────────────────────────────

  Future<void> _finishShotRecording() async {
    // 1. Flush CSV
    try { await _csvWriter?.flush(); } catch (e) {
      debugPrint('[ShotRecord] CSV flush: $e');
    }

    // 2. 儲存音頻 PCM
    List<String>? audioTags;
    try {
      await _audioService.stop();
      final samples = _audioService.rawSamples;
      if (samples.isNotEmpty) {
        final bytes = ByteData(samples.length * 4);
        for (int i = 0; i < samples.length; i++) {
          bytes.setFloat32(i * 4, samples[i].toDouble(), Endian.little);
        }
        await File(_audioPath).writeAsBytes(bytes.buffer.asUint8List());
        audioTags = await _extractAudioTags(_audioPath);
      } else {
        audioTags = ['no_audio'];
      }
    } catch (e) {
      debugPrint('[ShotRecord] 音頻處理: $e');
      audioTags = ['no_audio'];
    }

    // 3. 離線精確偵測揮桿相位
    List<SwingHit> hits = [];
    try {
      hits = await SwingImpactDetector.detect(csvPath: _csvPath);
    } catch (e) {
      debugPrint('[ShotRecord] SwingImpactDetector: $e');
    }

    // 4. Fallback：用線上偵測器的時間建立最基本的 SwingHit
    if (hits.isEmpty && _impactTimeSec != null) {
      final totalDur = _elapsed.inMilliseconds / 1000.0;
      hits = [_fallbackHit(_impactTimeSec!, totalDur)];
      debugPrint('[ShotRecord] fallback hit at ${_impactTimeSec}s');
    }

    if (hits.isEmpty) {
      _showError('未偵測到揮桿，請重試');
      if (mounted) setState(() => _state = ShotState.idle);
      return;
    }

    // 5. 虛擬 sourceEntry（用於 ClipPipelineService）
    final sourceEntry = RecordingHistoryEntry(
      filePath:            _videoPath,
      roundIndex:          _sessionRoundIndex,
      recordedAt:          _recordingStart!,
      durationSeconds:     _elapsed.inSeconds.clamp(1, 3600),
      videoType:           VideoType.original,
      recordedAspectRatio: 'wide',
    );

    // 6. ClipPipeline：trim + thumbnail + CSV slice + audio slice + phases.json
    List<ClipResult> results = [];
    try {
      results = await ClipPipelineService.run(
        hits:         hits,
        srcVideoPath: _videoPath,
        sourceEntry:  sourceEntry,
      );
    } catch (e) {
      debugPrint('[ShotRecord] ClipPipeline: $e');
    }

    if (results.isEmpty) {
      _showError('切片失敗，請重試');
      if (mounted) setState(() => _state = ShotState.idle);
      return;
    }

    // 7. 存入歷史
    final shotNum  = _shotCount + 1;
    final clipEntry = results.first.entry.copyWith(
      customName: '即時第$shotNum桿',
      audioTags:  audioTags,
      createdAt:  DateTime.now(),
    );
    await RecordingHistoryStorage.instance.upsertEntry(clipEntry);
    _shotCount++;

    // 8. 刪除原始短錄製（clip 已裁切到獨立資料夾）
    try {
      final orig = File(_videoPath);
      if (await orig.exists()) await orig.delete();
    } catch (_) {}

    if (!mounted) return;
    setState(() { _latestEntry = clipEntry; _state = ShotState.result; });
    widget.onEntryAdded?.call(clipEntry);
  }

  SwingHit _fallbackHit(double impactSec, double totalDur) {
    const half = 2.5;
    return SwingHit(
      hitIndex:   1,
      hitFrame:   (impactSec * 10).round(),
      hitSec:     impactSec,
      startSec:   (impactSec - half).clamp(0.0, totalDur),
      endSec:     (impactSec + half).clamp(0.0, totalDur),
      speedValue: 0.0,
      audioValue: 0.0,
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
      debugPrint('[ShotRecord] 音訊標籤: $e');
      return null;
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.orange),
    );
  }

  // ── 姿勢偵測 ─────────────────────────────────────────────────────

  Future<void> _onImageAnalysis(AnalysisImage image) async {
    if (_isPoseProcessing) return;
    _isPoseProcessing = true;
    try {
      final input = image.toInputImage();
      if (input == null) return;
      final poses = await _poseService.detect(input);
      if (!mounted) return;

      final timeSec = _recordingStart != null
          ? DateTime.now().difference(_recordingStart!).inMilliseconds / 1000.0
          : 0.0;

      final isRotated =
          image.rotation == InputAnalysisImageRotation.rotation90deg ||
          image.rotation == InputAnalysisImageRotation.rotation270deg;
      final visual = isRotated
          ? Size(image.height.toDouble(), image.width.toDouble())
          : Size(image.width.toDouble(), image.height.toDouble());

      setState(() { _poses = poses; _analysisSize = visual; });

      final isActive = _state == ShotState.recording || _state == ShotState.postImpact;
      if (isActive) {
        final frame = poses.isNotEmpty
            ? PoseFrameModel.fromPose(
                frame:        _frameCount,
                timeSec:      timeSec,
                poseUpdateId: _frameCount,
                pose:         poses.first,
                imgWidth:     visual.width,
                imgHeight:    visual.height,
                isFrontCamera: _isFrontCamera,
              )
            : PoseFrameModel.empty(frame: _frameCount, timeSec: timeSec);
        _csvWriter?.addFrame(frame);
        setState(() => _frameCount++);

        // 線上偵測只在 recording 狀態啟用（postImpact 不再偵測）
        if (_state == ShotState.recording) {
          _detector.feed(poses, timeSec);
        }
      }
    } catch (e) {
      debugPrint('[ShotRecord] pose: $e');
    } finally {
      _isPoseProcessing = false;
    }
  }

  // ── Build ─────────────────────────────────────────────────────────

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
          if (_state == ShotState.idle || _state == ShotState.result) ...[
            IconButton(
              tooltip: '骨架顯示',
              icon: Icon(
                Icons.accessibility_new,
                color: _showSkeleton ? Colors.greenAccent : Colors.white38,
              ),
              onPressed: () => setState(() => _showSkeleton = !_showSkeleton),
            ),
            IconButton(
              tooltip: '錄製設定',
              icon: const Icon(Icons.settings_rounded),
              onPressed: _showSettingsSheet,
            ),
          ],
          const SizedBox(width: 4),
        ],
      ),
      body: Container(
        color: Colors.black,
        child: Center(
          child: AspectRatio(
            aspectRatio: 9 / 16,
            child: KeyedSubtree(
              key: ValueKey('${_config.cameraKey}_$_isFrontCamera'),
              child: CameraAwesomeBuilder.custom(
                sensorConfig: SensorConfig.single(
                  sensor: Sensor.position(
                    _isFrontCamera ? SensorPosition.front : SensorPosition.back,
                  ),
                  aspectRatio: CameraAspectRatios.ratio_16_9,
                ),
                saveConfig: SaveConfig.video(
                  pathBuilder:  _buildCaptureRequest,
                  videoOptions: _config.toVideoOptions(),
                ),
                onImageForAnalysis: _onImageAnalysis,
                imageAnalysisConfig: AnalysisConfig(
                  androidOptions: AndroidAnalysisOptions.nv21(
                    width: _config.quality == VideoQuality.sd ? 320 : 480,
                  ),
                  maxFramesPerSecond: _config.fps == FrameRate.fps60 ? 15 : 10,
                  autoStart: true,
                ),
                builder: (cameraState, preview) {
                  // 捕獲錄製狀態供 timer 呼叫 stopRecording 用
                  cameraState.when(
                    onVideoRecordingMode: (rs) { _activeRecordingState = rs; },
                    onVideoMode: (_) {},
                  );

                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      // 骨架覆蓋
                      if (_showSkeleton &&
                          _poses.isNotEmpty &&
                          _analysisSize != Size.zero)
                        CustomPaint(
                          painter: SkeletonPainter(
                            poses:        _poses,
                            imageSize:    _analysisSize,
                            isFrontCamera: _isFrontCamera,
                          ),
                        ),
                      // 狀態覆蓋層
                      ..._buildOverlay(cameraState),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── 各狀態的覆蓋層 ────────────────────────────────────────────────

  List<Widget> _buildOverlay(CameraState cameraState) {
    switch (_state) {
      case ShotState.idle:       return _idleOverlay(cameraState);
      case ShotState.recording:  return _recordingOverlay();
      case ShotState.postImpact: return _postImpactOverlay();
      case ShotState.processing: return _processingOverlay();
      case ShotState.result:     return _resultOverlay(cameraState);
    }
  }

  // idle：顯示翻轉按鈕 + 準備按鈕
  List<Widget> _idleOverlay(CameraState cameraState) => [
    Center(
      child: Image.asset(
        _config.quality == VideoQuality.fhd
            ? 'assets/overlays/Group 1080x1920_0.png'
            : 'assets/overlays/Group 720x1280_0.png',
        fit: BoxFit.contain,
      ),
    ),
    Positioned(
      top: 16, right: 16,
      child: _FlipButton(
        onTap: () => setState(() {
          _isFrontCamera = !_isFrontCamera;
          _poses = [];
          _analysisSize = Size.zero;
        }),
      ),
    ),
    if (_shotCount > 0)
      Positioned(
        top: 16, left: 16,
        child: _Chip(text: '已完成 $_shotCount 桿'),
      ),
    Positioned(
      bottom: 52,
      left: 0, right: 0,
      child: Center(
        child: GestureDetector(
          onTap: () => cameraState.when(
            onVideoMode: (vs) => _startShot(vs),
            onVideoRecordingMode: (_) {},
          ),
          child: AnimatedBuilder(
            animation: _pulseCtrl,
            builder: (_, __) => Transform.scale(
              scale: _pulseScale.value,
              child: Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  color: const Color(0xFF1E8E5A),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF1E8E5A).withValues(alpha: 0.45),
                      blurRadius: 22,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.sports_golf_rounded,
                  color: Colors.white,
                  size: 38,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
    Positioned(
      bottom: 22,
      left: 0, right: 0,
      child: Center(
        child: Text(
          _shotCount > 0 ? '再按一次準備下一桿' : '按下開始，揮桿自動切片',
          style: const TextStyle(color: Colors.white54, fontSize: 13),
        ),
      ),
    ),
  ];

  // recording：偵測狀態 + 手動停止儲存 + 取消
  List<Widget> _recordingOverlay() {
    final isListening = _detector.state == SwingDetectState.listening ||
        _detector.state == SwingDetectState.triggered;
    final remainSec = _maxRecordingSec - _elapsed.inSeconds;
    return [
      Positioned(
        top: 16, right: 16,
        child: _RecBadge(elapsed: _elapsed, frames: _frameCount),
      ),
      Positioned(
        top: 16, left: 16,
        child: _DetectBadge(isListening: isListening, elapsed: _elapsed),
      ),
      // 保底倒數提示（剩 10 秒以內才顯示）
      if (remainSec <= 10 && remainSec > 0)
        Positioned(
          top: 56, left: 0, right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${remainSec}s 後自動停止',
                style: const TextStyle(
                    color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
      // 底部操作列
      Positioned(
        bottom: 28,
        left: 24, right: 24,
        child: Row(
          children: [
            // 取消（丟棄）
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _cancelShot,
                icon: const Icon(Icons.close_rounded, size: 18),
                label: const Text('取消'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white54,
                  side: const BorderSide(color: Colors.white24),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // 手動停止並儲存
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: _stopAndProcess,
                icon: const Icon(Icons.stop_circle_rounded, size: 18),
                label: const Text('停止並儲存'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFE05252),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    ];
  }

  // postImpact：顯示閃光動畫 + 倒數
  List<Widget> _postImpactOverlay() => [
    Container(color: Colors.amber.withValues(alpha: 0.06)),
    Positioned(
      top: 16, right: 16,
      child: _RecBadge(elapsed: _elapsed, frames: _frameCount),
    ),
    Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.flash_on_rounded, color: Colors.amber, size: 60),
          const SizedBox(height: 10),
          const Text(
            '偵測到揮桿！',
            style: TextStyle(
              color: Colors.amber,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '記錄中 ${_countdown.toStringAsFixed(1)}s',
            style: const TextStyle(color: Colors.white70, fontSize: 16),
          ),
        ],
      ),
    ),
  ];

  // processing：黑底 + 轉圈
  List<Widget> _processingOverlay() => [
    Container(color: Colors.black.withValues(alpha: 0.78)),
    const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF1E8E5A)),
            strokeWidth: 3,
          ),
          SizedBox(height: 20),
          Text(
            '分析揮桿中...',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: 6),
          Text('請稍候', style: TextStyle(color: Colors.white54, fontSize: 13)),
        ],
      ),
    ),
  ];

  // result：半透明背景 + 結果卡片
  List<Widget> _resultOverlay(CameraState cameraState) {
    final entry = _latestEntry;
    return [
      Container(color: Colors.black.withValues(alpha: 0.68)),
      Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: const Color(0xFF1E8E5A).withValues(alpha: 0.45),
              ),
            ),
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 標題
                Row(
                  children: [
                    const Icon(Icons.check_circle_rounded,
                        color: Color(0xFF1E8E5A), size: 22),
                    const SizedBox(width: 8),
                    Text(
                      '第 $_shotCount 桿完成',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // 縮圖
                if (entry?.thumbnailPath != null &&
                    File(entry!.thumbnailPath!).existsSync())
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(
                      File(entry.thumbnailPath!),
                      height: 130,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                const SizedBox(height: 12),
                // 速度
                if (entry?.bestSpeedValue != null && entry!.bestSpeedValue! > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.speed_rounded,
                            color: Colors.amber, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          '速度峰值  ${entry.bestSpeedValue!.toStringAsFixed(1)}',
                          style: const TextStyle(
                              color: Colors.amber, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                // 按鈕
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => setState(() {
                          _state = ShotState.idle;
                          _poses = [];
                        }),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white70,
                          side: const BorderSide(color: Colors.white24),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                        ),
                        child: const Text('下一桿'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.pop(context),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF1E8E5A),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                        ),
                        child: const Text('完成'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ];
  }

  // ── 設定面板 ──────────────────────────────────────────────────────

  void _showSettingsSheet() {
    VideoQuality pendingQ = _config.quality;
    FrameRate    pendingF = _config.fps;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.videocam_rounded,
                      color: Color(0xFF1E8E5A), size: 20),
                  const SizedBox(width: 8),
                  const Text('錄製設定',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close,
                        color: Colors.white54, size: 20),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ]),
                const Divider(color: Colors.white12, height: 20),
                const Text('影片畫質',
                    style: TextStyle(color: Colors.white54, fontSize: 12)),
                const SizedBox(height: 10),
                Row(
                  children: VideoQuality.values.map((q) => Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: _ShotSettingChip(
                        label: q.label,
                        selected: pendingQ == q,
                        onTap: () => set(() => pendingQ = q),
                      ),
                    ),
                  )).toList(),
                ),
                const SizedBox(height: 20),
                const Text('幀率',
                    style: TextStyle(color: Colors.white54, fontSize: 12)),
                const SizedBox(height: 10),
                Row(
                  children: FrameRate.values.map((f) => Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: _ShotSettingChip(
                        label: f.label,
                        selected: pendingF == f,
                        onTap: () => set(() => pendingF = f),
                      ),
                    ),
                  )).toList(),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF1E8E5A),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      if (pendingQ != _config.quality || pendingF != _config.fps) {
                        setState(() => _config =
                            RecordingConfig(quality: pendingQ, fps: pendingF));
                      }
                    },
                    child: const Text('套用',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── 小元件 ────────────────────────────────────────────────────────────────────

class _FlipButton extends StatelessWidget {
  final VoidCallback onTap;
  const _FlipButton({required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 48, height: 48,
      decoration: BoxDecoration(
        color: Colors.black54,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white24),
      ),
      child: const Icon(Icons.flip_camera_ios_rounded,
          color: Colors.white, size: 26),
    ),
  );
}

class _Chip extends StatelessWidget {
  final String text;
  const _Chip({required this.text});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(text,
        style: const TextStyle(color: Colors.white70, fontSize: 12)),
  );
}

class _RecBadge extends StatelessWidget {
  final Duration elapsed;
  final int frames;
  const _RecBadge({required this.elapsed, required this.frames});

  @override
  Widget build(BuildContext context) {
    final m = elapsed.inMinutes.toString().padLeft(2, '0');
    final s = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8, height: 8,
            decoration: const BoxDecoration(
                color: Colors.white, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text('$m:$s  $frames 幀',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _DetectBadge extends StatelessWidget {
  final bool isListening;
  final Duration elapsed;
  const _DetectBadge({required this.isListening, required this.elapsed});

  @override
  Widget build(BuildContext context) {
    final text  = isListening ? '偵測中' : '校準中 ${elapsed.inSeconds}s';
    final color = isListening ? Colors.greenAccent : Colors.amber;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(text, style: TextStyle(color: color, fontSize: 12)),
        ],
      ),
    );
  }
}

class _ShotSettingChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ShotSettingChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFF1E8E5A) : const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: selected ? const Color(0xFF1E8E5A) : Colors.white12,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          color: selected ? Colors.white : Colors.white54,
          fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
          fontSize: 14,
        ),
      ),
    ),
  );
}
