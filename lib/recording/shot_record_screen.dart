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
import '../services/shot_sound_service.dart';
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

// 自動下一桿的等待秒數
const int _autoNextShotDelaySec = 3;

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
  final _soundService = ShotSoundService();
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

  // ── 縮放 ─────────────────────────────────────────────────────────
  double _currentZoom = 0.0;
  double _baseZoom    = 0.0;
  CameraState? _cameraState;

  // ── 相機硬體比例（從 AnalysisPreview 取得，確保 preview == 錄製範圍）──
  double _hardwareRatio = 9 / 16; // 預設值，相機就緒後更新

  // ── 設定 ─────────────────────────────────────────────────────────
  RecordingConfig _config = RecordingConfig();
  bool _isFrontCamera = false;

  // ── CameraAwesome 錄製狀態（P0 fix：用 Completer 確保 startRecording 後才能 stop）
  Completer<VideoRecordingCameraState>? _recordingStateCompleter;

  // 進入畫面後自動開始，僅觸發一次
  bool _autoStarted = false;

  // ── 自動偵測高爾夫站姿 ────────────────────────────────────────────
  int _golfPostureFrames = 0;          // 連續偵測到站姿的幀數
  bool _calibrationDone   = false;     // 校準 3s 是否完成
  bool _addressConfirmed  = false;     // 準備站姿是否已確認
  static const double _autoStartDurationSec = 1.5; // 需持續偵測到站姿的秒數
  static const double _calibrationSec = 3.0;
  // 根據實際分析 FPS 動態計算門檻（30fps相機→10fps分析, 60fps相機→15fps分析）
  int get _autoStartFrameThreshold =>
      (_autoStartDurationSec * (_config.fps == FrameRate.fps60 ? 15 : 10)).round();

  // ── 自動下一桿 ────────────────────────────────────────────────────
  Timer? _autoNextTimer;
  int _autoNextCountdown = 0;

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
    _cancelAllTimers();
    _poseService.dispose();
    _audioService.dispose();
    super.dispose();
  }

  // P1 fix：集中取消所有 timer
  void _cancelAllTimers() {
    _elapsedTimer?.cancel();
    _postImpactTimer?.cancel();
    _countdownTick?.cancel();
    _maxDurationTimer?.cancel();
    _autoNextTimer?.cancel();
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
    _latestEntry   = null;
    _recordingStateCompleter = null;
    _golfPostureFrames  = 0;
    _calibrationDone    = false;
    _addressConfirmed   = false;
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
    // P0 fix：建立 Completer，builder 賦值後才能 stop
    _recordingStateCompleter = Completer<VideoRecordingCameraState>();
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

  // P0 fix：安全停止錄製，等待 Completer 確保 state 已就緒
  Future<void> _stopRecordingSafely() async {
    final completer = _recordingStateCompleter;
    if (completer == null) return;
    try {
      final rs = await completer.future.timeout(const Duration(seconds: 3));
      await rs.stopRecording();
    } catch (e) {
      debugPrint('[ShotRecord] stopRecording failed: $e');
    }
  }

  void _handleImpact(double impactTimeSec) {
    if (_state != ShotState.recording || !mounted) return;
    if (!_addressConfirmed) return;
    _maxDurationTimer?.cancel();
    _impactTimeSec = impactTimeSec;
    _soundService.playSwingImpact();
    // 3200ms = 2500ms 目標後段 + 700ms 補償（Y-LOW 比速度峰值最多晚 ~500ms）
    const bufferMs = 3200;
    setState(() {
      _state     = ShotState.postImpact;
      _countdown = 2.5; // UI 顯示 2.5s（使用者感知的等待時間）
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
    _cancelAllTimers();
    if (!mounted) return;
    setState(() => _state = ShotState.processing);
    await _stopRecordingSafely();
    await _finishShotRecording();
  }

  /// 手動停止 + 儲存（使用者按「停止」或超時保底）
  Future<void> _stopAndProcess({bool isTimeout = false}) async {
    if (_state != ShotState.recording && _state != ShotState.postImpact) return;
    _cancelAllTimers();
    if (!mounted) return;
    if (_impactTimeSec == null) {
      final dur = _elapsed.inMilliseconds / 1000.0;
      _impactTimeSec = (dur - 1.0).clamp(0.5, dur);
    }
    setState(() => _state = ShotState.processing);
    await _stopRecordingSafely();
    await _finishShotRecording();
  }

  /// 取消（丟棄，不儲存）
  Future<void> _cancelShot() async {
    _cancelAllTimers();
    await _stopRecordingSafely();
    await _audioService.stop();
    if (mounted) setState(() { _state = ShotState.idle; _poses = []; _autoStarted = false; });
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
      hits = [_fallbackHit(_impactTimeSec!, totalDur, _config.fps.value)];
      debugPrint('[ShotRecord] fallback hit at ${_impactTimeSec}s');
    }

    if (hits.isEmpty) {
      _showError('未偵測到揮桿，請重試');
      if (mounted) setState(() { _state = ShotState.idle; _autoStarted = false; });
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
      if (mounted) setState(() { _state = ShotState.idle; _autoStarted = false; });
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
    _soundService.playRecordingDone();
    setState(() { _latestEntry = clipEntry; _state = ShotState.result; });
    widget.onEntryAdded?.call(clipEntry);
    _startAutoNextCountdown();
  }

  // 自動下一桿：result 頁顯示倒數，時間到自動切回 idle
  void _startAutoNextCountdown() {
    _autoNextCountdown = _autoNextShotDelaySec;
    _autoNextTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      if (_autoNextCountdown <= 1) {
        t.cancel();
        if (_state == ShotState.result) {
          setState(() { _state = ShotState.idle; _autoStarted = false; });
        }
      } else {
        setState(() => _autoNextCountdown--);
      }
    });
  }

  // P1 fix：傳入實際 fps 計算 frame 數
  SwingHit _fallbackHit(double impactSec, double totalDur, int fps) {
    final (s, e) = SwingImpactDetector.calculateClipBoundaries(
      hitSec: impactSec, totalDurationSec: totalDur);
    return SwingHit(
      hitIndex:   1,
      hitFrame:   (impactSec * fps).round(),
      hitSec:     impactSec,
      startSec:   s,
      endSec:     e,
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

  // ── 高爾夫站姿（address position）偵測 ───────────────────────────
  // 條件：
  //   1. 雙手腕可見（confidence > 0.5）
  //   2. 手腕中點 Y > 髖部中點 Y（手腕在髖部以下，image coord Y 向下增大）
  //   3. 雙手腕水平距離 < 肩寬的 45%（雙手並攏）
  bool _isGolfAddressPosture(List<Pose> poses) {
    if (poses.isEmpty) return false;
    final lms = poses.first.landmarks;

    final lw = lms[PoseLandmarkType.leftWrist];
    final rw = lms[PoseLandmarkType.rightWrist];
    final lh = lms[PoseLandmarkType.leftHip];
    final rh = lms[PoseLandmarkType.rightHip];
    final ls = lms[PoseLandmarkType.leftShoulder];
    final rs = lms[PoseLandmarkType.rightShoulder];

    if (lw == null || rw == null || lh == null || rh == null ||
        ls == null || rs == null) return false;
    if (lw.likelihood < 0.5 || rw.likelihood < 0.5) return false;

    final hipMidY    = (lh.y + rh.y) / 2;
    final wristMidY  = (lw.y + rw.y) / 2;
    final shoulderW  = (ls.x - rs.x).abs();
    final wristDistX = (lw.x - rw.x).abs();

    return wristMidY > hipMidY && wristDistX < shoulderW * 0.45;
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
        // P0 fix：_csvWriter 可能因 _buildCaptureRequest 尚未完成而為 null，直接跳過
        final writer = _csvWriter;
        if (writer == null) return;
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
        writer.addFrame(frame);
        setState(() => _frameCount++);

        if (_state == ShotState.recording) {
          // 偵測器全程 feed（校準期收集基線；_handleImpact 內有 _addressConfirmed gate）
          _detector.feed(poses, timeSec);

          // 階段一：校準期（3s）
          if (!_calibrationDone) {
            if (timeSec >= _calibrationSec) {
              setState(() => _calibrationDone = true);
            }
            return;
          }

          // 階段二：偵測準備站姿
          if (!_addressConfirmed) {
            if (_isGolfAddressPosture(poses)) {
              _golfPostureFrames++;
              if (_golfPostureFrames == 1) {
                _soundService.playPostureDetected();
              }
              if (_golfPostureFrames >= _autoStartFrameThreshold) {
                setState(() { _addressConfirmed = true; _golfPostureFrames = 0; });
              }
            } else {
              if (_golfPostureFrames > 0) setState(() => _golfPostureFrames = 0);
            }
          }
          // 階段三（_addressConfirmed == true）：偵測器已在 feed，_handleImpact 自動解鎖
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
            aspectRatio: _hardwareRatio,
            child: ClipRect(
            child: GestureDetector(
              onScaleStart: (_) => _baseZoom = _currentZoom,
              onScaleUpdate: (d) {
                if (d.pointerCount < 2) return;
                final z = (_baseZoom + (d.scale - 1.0) * 0.6).clamp(0.0, 1.0);
                _setZoom(z);
              },
              child: KeyedSubtree(
              key: ValueKey('${_config.cameraKey}_$_isFrontCamera'),
              child: CameraAwesomeBuilder.custom(
                previewFit: CameraPreviewFit.contain,
                sensorConfig: SensorConfig.single(
                  sensor: Sensor.position(
                    _isFrontCamera ? SensorPosition.front : SensorPosition.back,
                  ),
                  aspectRatio: CameraAspectRatios.ratio_16_9,
                  zoom: 0.0,
                ),
                saveConfig: SaveConfig.video(
                  pathBuilder:  _buildCaptureRequest,
                  videoOptions: _config.toVideoOptions(),
                ),
                onImageForAnalysis: _onImageAnalysis,
                imageAnalysisConfig: AnalysisConfig(
                  androidOptions: AndroidAnalysisOptions.nv21(
                    width: _config.quality == VideoQuality.hd ? 640 : 960,
                  ),
                  maxFramesPerSecond: _config.fps == FrameRate.fps60 ? 15 : 10,
                  autoStart: true,
                ),
                builder: (cameraState, preview) {
                  // P0 fix：透過 Completer 傳遞 VideoRecordingCameraState，
                  // 確保 stopRecording 呼叫時 state 已就緒
                  _cameraState = cameraState;
                  // 從硬體 preview 尺寸計算實際比例（確保 preview == 錄製範圍）
                  final pw = preview.nativePreviewSize.width;
                  final ph = preview.nativePreviewSize.height;
                  if (pw > 0 && ph > 0) {
                    final ratio = pw < ph ? pw / ph : ph / pw; // 永遠取直式比例
                    if ((ratio - _hardwareRatio).abs() > 0.001) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) setState(() => _hardwareRatio = ratio);
                      });
                    }
                  }
                  cameraState.when(
                    onVideoRecordingMode: (rs) {
                      final c = _recordingStateCompleter;
                      if (c != null && !c.isCompleted) c.complete(rs);
                    },
                    onVideoMode: (vs) {
                      if (!_autoStarted && _state == ShotState.idle) {
                        _autoStarted = true;
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted && _state == ShotState.idle) _startShot(vs);
                        });
                      }
                    },
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
                      _ZoomSlider(zoom: _currentZoom, onChanged: _setZoom),
                    ],
                  );
                },
              ),              // CameraAwesomeBuilder
            ),                // KeyedSubtree
          ),                  // GestureDetector
        ),                    // ClipRect
      ),                      // AspectRatio
    ),                        // Center
  ),                          // Container
);                            // Scaffold
  }

  void _setZoom(double value) {
    setState(() => _currentZoom = value);
    _cameraState?.sensorConfig.setZoom(value);
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
          _shotCount > 0 ? '再按一次準備下一桿' : '按下開始',
          style: const TextStyle(color: Colors.white54, fontSize: 13),
        ),
      ),
    ),
  ];

  // recording：偵測狀態 + 手動停止儲存 + 取消
  List<Widget> _recordingOverlay() {
    final isListening = _addressConfirmed &&
        (_detector.state == SwingDetectState.listening ||
         _detector.state == SwingDetectState.triggered);
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
      // 階段提示（校準 / 等待站姿 / 偵測中）
      Positioned(
        top: 56, left: 0, right: 0,
        child: Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: !_calibrationDone
                ? _PhaseBadge(key: const ValueKey('cal'), text: '校準中…', color: Colors.white38)
                : !_addressConfirmed
                    ? _PhaseBadge(
                        key: const ValueKey('addr'),
                        text: _golfPostureFrames > 0 ? '偵測到站姿…' : '請站好準備姿勢',
                        color: _golfPostureFrames > 0 ? Colors.greenAccent : Colors.white70,
                      )
                    : _PhaseBadge(key: const ValueKey('swing'), text: '偵測揮桿中', color: Colors.greenAccent),
          ),
        ),
      ),
      if (!_calibrationDone || (!_addressConfirmed && _golfPostureFrames > 0))
        Positioned(
          bottom: 140, left: 0, right: 0,
          child: Center(
            child: SizedBox(
              width: 72, height: 72,
              child: CircularProgressIndicator(
                value: !_calibrationDone
                    ? (_elapsed.inMilliseconds / 1000.0 / _calibrationSec).clamp(0.0, 1.0)
                    : _golfPostureFrames / _autoStartFrameThreshold,
                strokeWidth: 4,
                color: !_calibrationDone ? Colors.white54 : Colors.greenAccent,
                backgroundColor: Colors.white24,
              ),
            ),
          ),
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
                // 自動倒數提示
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.timer_rounded, color: Colors.white38, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        '$_autoNextCountdown 秒後自動準備下一桿',
                        style: const TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                // 按鈕
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          _autoNextTimer?.cancel();
                          setState(() { _state = ShotState.idle; _autoStarted = false; });
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white70,
                          side: const BorderSide(color: Colors.white24),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                        ),
                        child: const Text('立即下一桿'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          _autoNextTimer?.cancel();
                          Navigator.pop(context);
                        },
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
    final text  = isListening ? '揮桿偵測中' : '等待中';
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

class _PhaseBadge extends StatelessWidget {
  final String text;
  final Color color;
  const _PhaseBadge({super.key, required this.text, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(text, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w500)),
  );
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

// ── 縮放滑桿（右側垂直）────────────────────────────────────────────────────────

class _ZoomSlider extends StatelessWidget {
  final double zoom;
  final ValueChanged<double> onChanged;
  const _ZoomSlider({required this.zoom, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final pct = (zoom * 100).round();
    return Positioned(
      left: 8,
      top: 0,
      bottom: 110,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '${pct}%',
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: RotatedBox(
              quarterTurns: 3,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 2,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                ),
                child: Slider(
                  value: zoom,
                  min: 0.0,
                  max: 1.0,
                  onChanged: onChanged,
                  activeColor: Colors.white,
                  inactiveColor: Colors.white24,
                ),
              ),
            ),
          ),
          const Icon(Icons.zoom_in_rounded, color: Colors.white54, size: 18),
        ],
      ),
    );
  }
}
