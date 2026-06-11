import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as vt;

import '../services/audio_analysis_service.dart';
import '../services/audio_extraction_service.dart';
import '../models/recording_history_entry.dart';
import '../services/realtime_audio_service.dart';
import '../services/swing_auto_clip_service.dart';
import 'device_capability.dart';
import 'live_swing_detector.dart';
import 'native_camera_service.dart';
import 'pose_csv_writer.dart';
import 'prewarm_cleanup.dart';
import 'pose_frame_model.dart';
import 'pose_result.dart';
import 'recording_config.dart';
import 'recording_widgets.dart';

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
      LiveSwingDetector(onImpact: _liveImpacts.add);
  final List<double> _liveImpacts = [];

  bool _recording  = false;
  bool get _isRecording => _recording;
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
    _resetSession();
    _checkDeviceCapability();
    _initCamera();
    unawaited(cleanupStalePrewarmDirs());
  }

  Future<void> _checkDeviceCapability() async {
    final ok = await DeviceCapability.supportsVideoAndAnalysis();
    if (mounted) setState(() => _supportsVideoAndAnalysis = ok);
  }

  /// 開相機前確保相機 + 麥克風權限；被拒時引導使用者至設定。
  /// 回傳 false 表示權限不足，呼叫端不應繼續開相機。
  Future<bool> _ensureRecordPermissions() async {
    final statuses = await [Permission.camera, Permission.microphone].request();
    final camOk = statuses[Permission.camera]?.isGranted ?? false;
    final micOk = statuses[Permission.microphone]?.isGranted ?? false;
    if (camOk && micOk) return true;

    final permanentlyDenied =
        (statuses[Permission.camera]?.isPermanentlyDenied ?? false) ||
        (statuses[Permission.microphone]?.isPermanentlyDenied ?? false);
    if (mounted) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('需要相機與麥克風權限'),
          content: Text(camOk
              ? '錄影需要麥克風權限以收錄擊球聲，請開啟後再試。'
              : '揮桿錄影需要相機與麥克風權限，請開啟後再試。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () { Navigator.pop(ctx); if (permanentlyDenied) openAppSettings(); },
              child: Text(permanentlyDenied ? '前往設定' : '知道了'),
            ),
          ],
        ),
      );
    }
    return false;
  }

  Future<void> _initCamera() async {
    if (mounted) setState(() => _cameraReady = false);
    if (!await _ensureRecordPermissions()) return;
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
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('高爾夫揮桿錄製'),
        actions: [
          IconButton(
            tooltip: '輪廓疊加切換',
            icon: Icon(Icons.person_outline_rounded,
                color: _showOverlay ? Colors.greenAccent : Colors.white38),
            onPressed: () => setState(() => _showOverlay = !_showOverlay),
          ),
          // Skeleton visibility controlled natively (always shown when pose detected)
          IconButton(
            tooltip: '錄製設定',
            icon: const Icon(Icons.settings_rounded),
            onPressed: _isRecording ? null : _showSettingsSheet,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _cameraReady
          ? Stack(fit: StackFit.expand, children: [
              _camera.buildPreviewWidget(),
              _buildOverlay(),
            ])
          : Container(
              color: Colors.black,
              child: const Center(
                  child: CircularProgressIndicator(color: Colors.white54)),
            ),
    );
  }

  // ─── Camera Overlay ────────────────────────────────────────────────────────

  Widget _buildOverlay() {
    return GestureDetector(
      onScaleStart: (_) => _baseZoom = _currentZoom,
      onScaleUpdate: (d) {
        if (d.pointerCount < 2) return;
        final z = (_baseZoom + (d.scale - 1.0) * 0.6).clamp(0.0, 1.0);
        _setZoom(z);
      },
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
        if (_isRecording)
          Positioned(
            top: 16, right: 16,
            child: RecordingBadge(elapsed: _elapsed, frameCount: _frameCount),
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
      ]),
    );
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('此裝置不支援錄影期間同步骨架偵測，錄影結束後恢復'),
          duration: Duration(seconds: 3),
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

    if (!recordOk) {
      // 丟棄 CSV/audio，提示重錄，並重新 pre-warm 下一次
      try { await _audioService.stop(); } catch (_) {}
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('本次錄製失敗（未取得有效影像），請重新錄製'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
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
      if (samples > 0) {
        audioTags = await _extractAudioTags(_videoPath);  // 直接分析 mp4 音軌
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
    final autoClipSource = RecordingHistoryEntry(
      filePath:            _videoPath,
      roundIndex:          1,
      recordedAt:          _recordingStart ?? DateTime.now(),
      durationSeconds:     duration,
      videoType:           VideoType.original,
      recordedAspectRatio: _config.aspectRatioMode,
      isFrontCamera:       _isFront,
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
      // 錄製完全結束後，才準備下一次 pre-warm。
      // 不能在 startRecording 前做，否則會覆蓋 native preparedRecPath。
      if (mounted && !_recording) {
        unawaited(_preWarmRecordingSession());
      }
    }
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
      debugPrint('[RecordScreen] audio tag error: $e');
      return null;
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.videocam_rounded, color: Color(0xFF1AA87C), size: 20),
                    const SizedBox(width: 8),
                    const Text('錄製設定',
                        style: TextStyle(color: Colors.white, fontSize: 16,
                            fontWeight: FontWeight.w700)),
                    const Spacer(),
                    IconButton(icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                        onPressed: () => Navigator.pop(ctx)),
                  ]),
                  const Divider(color: Colors.white12, height: 20),

                  const Text('影片畫質', style: TextStyle(color: Colors.white54, fontSize: 12)),
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

                  const Text('幀率', style: TextStyle(color: Colors.white54, fontSize: 12)),
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
                    const Text('錄製音訊', style: TextStyle(color: Colors.white54, fontSize: 12)),
                    const Spacer(),
                    Switch(
                      value: pendingAudio,
                      onChanged: (v) => setSheet(() => pendingAudio = v),
                      activeThumbColor: const Color(0xFF1AA87C),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ]),
                  const SizedBox(height: 16),

                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF1AA87C),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () async {
                        Navigator.pop(ctx);
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
                      child: const Text('套用',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
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

