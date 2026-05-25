import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camerawesome/camerawesome_plugin.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as vt;

import '../services/audio_analysis_service.dart';
import '../services/realtime_audio_service.dart';
import 'mlkit_utils.dart';
import 'pose_csv_writer.dart';
import 'pose_detector_service.dart';
import 'pose_frame_model.dart';
import 'recording_config.dart';
import 'skeleton_painter.dart';

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
  final _poseService = PoseDetectorService();
  final _audioService = RealtimeAudioService();

  // 錄影路徑與 CSV
  String _sessionId = '';
  String _videoPath = '';
  String _csvPath = '';
  String _audioPath = '';
  PoseCsvWriter? _csvWriter;

  // 錄影狀態
  bool _isRecording = false;
  bool _isPoseProcessing = false;
  int _frameCount = 0;
  DateTime? _recordingStartTime;
  Duration _elapsed = Duration.zero;
  Timer? _elapsedTimer;

  // 骨架覆蓋
  List<Pose> _poses = [];
  Size _analysisImageSize = Size.zero;
  bool _showSkeleton = true;

  // 鏡頭方向
  bool _isFrontCamera = false;

  // 輪廓疊加
  bool _showOverlay = true;

  // 錄製設定
  RecordingConfig _config = RecordingConfig();

  @override
  void initState() {
    super.initState();
    _resetSession();
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    _poseService.dispose();
    _audioService.dispose();
    super.dispose();
  }

  void _resetSession() {
    _sessionId = DateTime.now().millisecondsSinceEpoch.toString();
    _videoPath = '';
    _csvPath = '';
    _csvWriter = null;
    _frameCount = 0;
    _recordingStartTime = null;
    _elapsed = Duration.zero;
    _poses = [];
  }

  /// CameraAwesome 在開始錄影時呼叫，用於確定輸出路徑
  Future<SingleCaptureRequest> _buildCaptureRequest(List<Sensor> sensors) async {
    final appDir = await getApplicationDocumentsDirectory();
    final sessionDir = p.join(appDir.path, 'golf_recordings', _sessionId);
    await Directory(sessionDir).create(recursive: true);
    _videoPath = p.join(sessionDir, 'swing.mp4');
    _csvPath = p.join(sessionDir, 'pose_landmarks.csv');
    _audioPath = p.join(sessionDir, 'audio.pcm');
    _csvWriter = PoseCsvWriter(_csvPath);
    return SingleCaptureRequest(_videoPath, sensors.first);
  }

  // ─── Build ───────────────────────────────────────────────────────────────

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
            icon: Icon(
              Icons.person_outline_rounded,
              color: _showOverlay ? Colors.greenAccent : Colors.white38,
            ),
            onPressed: () => setState(() => _showOverlay = !_showOverlay),
          ),
          IconButton(
            tooltip: '骨架顯示切換',
            icon: Icon(
              Icons.accessibility_new,
              color: _showSkeleton ? Colors.greenAccent : Colors.white38,
            ),
            onPressed: () => setState(() => _showSkeleton = !_showSkeleton),
          ),
          IconButton(
            tooltip: '錄製設定',
            icon: const Icon(Icons.settings_rounded),
            onPressed: _isRecording ? null : _showSettingsSheet,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _buildCameraUI(),
    );
  }

  // ─── 相機 UI ─────────────────────────────────────────────────────────────

  /// 依目前設定建立 SensorConfig，傳給 CameraAwesome 的原生相機 API
  /// aspectRatio 決定實際錄製的 mp4 尺寸（非 UI 裁切）
  SensorConfig _buildSensorConfig() => SensorConfig.single(
    sensor: Sensor.position(
      _isFrontCamera ? SensorPosition.front : SensorPosition.back,
    ),
    aspectRatio: _config.aspectRatio.cameraRatio,
  );

  Widget _buildCameraUI() {
    final cameraWidget = KeyedSubtree(
      key: ValueKey(_config.cameraKey),
      child: CameraAwesomeBuilder.custom(
        sensorConfig: _buildSensorConfig(),
        saveConfig: SaveConfig.video(
          pathBuilder: _buildCaptureRequest,
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
        builder: (state, preview) {
          return Stack(
            fit: StackFit.expand,
            children: [
              if (_showSkeleton && _poses.isNotEmpty && _analysisImageSize != Size.zero)
                CustomPaint(
                  painter: SkeletonPainter(
                    poses: _poses,
                    imageSize: _analysisImageSize,
                  ),
                ),
              if (_showOverlay)
                Center(
                  child: Image.asset(
                    'assets/overlays/person_ball_outline_transparent.png',
                    fit: BoxFit.contain,
                  ),
                ),
              if (_isRecording)
                Positioned(
                  top: 16,
                  right: 16,
                  child: _RecordingBadge(elapsed: _elapsed, frameCount: _frameCount),
                ),
              if (!_isRecording)
                Positioned(
                  top: 16,
                  right: 16,
                  child: GestureDetector(
                    onTap: () async {
                      await state.switchCameraSensor();
                      if (mounted) setState(() => _isFrontCamera = !_isFrontCamera);
                    },
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white24),
                      ),
                      child: const Icon(
                        Icons.flip_camera_ios_rounded,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                  ),
                ),
              Positioned(
                bottom: 120,
                left: 16,
                child: _ConfigBadge(config: _config),
              ),
              Positioned(
                bottom: 40,
                left: 0,
                right: 0,
                child: Center(
                  child: _RecordButton(
                    isRecording: _isRecording,
                    onTap: () => _onRecordButtonTap(state),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );

    // 全螢幕：相機錄製 16:9，預覽填滿整個螢幕
    // 其他比例：用 AspectRatio 框住預覽，讓預覽區域與錄製尺寸一致
    final ratio = _config.aspectRatio.ratio;
    if (ratio == null) {
      return cameraWidget;
    }
    return Container(
      color: Colors.black,
      child: Center(
        child: AspectRatio(
          aspectRatio: ratio,
          child: cameraWidget,
        ),
      ),
    );
  }

  // ─── 錄影控制 ─────────────────────────────────────────────────────────────

  void _onRecordButtonTap(CameraState state) {
    state.when(
      onVideoMode: (videoState) => _startRecording(videoState),
      onVideoRecordingMode: (recordingState) => _stopRecording(recordingState),
    );
  }

  Future<void> _startRecording(VideoCameraState videoState) async {
    _resetSession();

    try {
      await _audioService.start();
    } catch (e) {
      debugPrint('[RecordScreen] ❌ 音频启动失败: $e');
    }

    await videoState.startRecording();
    if (!mounted) return;
    _recordingStartTime = DateTime.now();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _recordingStartTime != null) {
        setState(() => _elapsed = DateTime.now().difference(_recordingStartTime!));
      }
    });
    setState(() => _isRecording = true);
  }

  Future<void> _stopRecording(VideoRecordingCameraState recordingState) async {
    _elapsedTimer?.cancel();
    await recordingState.stopRecording();
    await _finishRecording();
  }

  Future<void> _finishRecording() async {
    final duration = _elapsed.inSeconds.clamp(1, 86400);
    if (mounted) {
      setState(() {
        _isRecording = false;
        _poses = [];
      });
    }

    try {
      await _csvWriter?.flush();
    } catch (e) {
      debugPrint('[RecordScreen] CSV flush error: $e');
    }

    List<String>? audioTags;
    try {
      await _audioService.stop();
      final rawSamples = _audioService.rawSamples;
      if (rawSamples.isNotEmpty) {
        final audioFile = File(_audioPath);
        final byteData = ByteData(rawSamples.length * 4);
        for (int i = 0; i < rawSamples.length; i++) {
          byteData.setFloat32(i * 4, rawSamples[i].toDouble(), Endian.little);
        }
        await audioFile.writeAsBytes(byteData.buffer.asUint8List());
        audioTags = await _extractAudioTags(_audioPath);
      } else {
        audioTags = ['no_audio'];
      }
    } catch (e) {
      debugPrint('[RecordScreen] 音频处理错误: $e');
    }

    try {
      final thumbnailPath = await _generateThumbnail(_videoPath);
      widget.onComplete?.call(
        videoPath: _videoPath,
        csvPath: _csvPath,
        audioPath: _audioPath,
        durationSeconds: duration,
        thumbnailPath: thumbnailPath,
        audioLabel: null,
        aspectRatioMode: _config.aspectRatio.name,
        audioTags: audioTags,
      );
    } catch (e) {
      debugPrint('[RecordScreen] finishRecording error: $e');
    }
  }

  Future<List<String>?> _extractAudioTags(String audioPath) async {
    try {
      if (!File(audioPath).existsSync()) return ['no_audio'];
      final result = await AudioAnalysisService.analyzeVideo(audioPath);
      final summary = result['summary'] as Map<String, dynamic>?;
      if (summary != null) {
        final tags = summary['tags'] as List<dynamic>?;
        if (tags != null && tags.isNotEmpty) {
          return tags.whereType<String>().toList();
        }
      }
      return null;
    } catch (e) {
      debugPrint('[RecordScreen] 音訊標籤提取失敗: $e');
      return null;
    }
  }

  Future<String?> _generateThumbnail(String videoPath) async {
    try {
      final sessionDir = File(videoPath).parent.path;
      return await vt.VideoThumbnail.thumbnailFile(
        video: videoPath,
        thumbnailPath: sessionDir,
        imageFormat: vt.ImageFormat.JPEG,
        quality: 75,
      );
    } catch (e) {
      debugPrint('[RecordScreen] thumbnail error: $e');
      return null;
    }
  }

  // ─── 姿勢偵測 ─────────────────────────────────────────────────────────────

  Future<void> _onImageAnalysis(AnalysisImage image) async {
    if (_isPoseProcessing) return;
    _isPoseProcessing = true;
    try {
      final inputImage = image.toInputImage();
      if (inputImage == null) return;
      final poses = await _poseService.detect(inputImage);
      if (!mounted) return;

      final timeSec = _recordingStartTime != null
          ? DateTime.now().difference(_recordingStartTime!).inMilliseconds / 1000.0
          : 0.0;

      // Android NV21: raw buffer dimensions are in sensor (landscape) space.
      // ML Kit applies the rotation metadata and returns landmarks in visual space.
      // If rotation is 90° or 270°, swap width/height to get the visual dimensions.
      final isRotated = image.rotation == InputAnalysisImageRotation.rotation90deg ||
          image.rotation == InputAnalysisImageRotation.rotation270deg;
      final visualSize = isRotated
          ? Size(image.height.toDouble(), image.width.toDouble())
          : Size(image.width.toDouble(), image.height.toDouble());

      setState(() {
        _poses = poses;
        _analysisImageSize = visualSize;
      });

      if (_isRecording) {
        final frameModel = poses.isNotEmpty
            ? PoseFrameModel.fromPose(
                frame: _frameCount,
                timeSec: timeSec,
                poseUpdateId: _frameCount,
                pose: poses.first,
                imgWidth: visualSize.width,
                imgHeight: visualSize.height,
              )
            : PoseFrameModel.empty(
                frame: _frameCount,
                timeSec: timeSec,
                poseUpdateId: _frameCount,
              );
        _csvWriter?.addFrame(frameModel);
        if (mounted) { setState(() => _frameCount++); }
      }
    } catch (e) {
      debugPrint('[Pose] $e');
    } finally {
      _isPoseProcessing = false;
    }
  }

  // ─── 設定面板 ─────────────────────────────────────────────────────────────

  void _showSettingsSheet() {
    // 暫存設定，確認後才套用
    VideoQuality pendingQuality = _config.quality;
    FrameRate pendingFps = _config.fps;
    AspectRatioMode pendingRatio = _config.aspectRatio;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 標題列
                    Row(
                      children: [
                        const Icon(Icons.videocam_rounded, color: Color(0xFF1E8E5A), size: 20),
                        const SizedBox(width: 8),
                        const Text('錄製設定',
                            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const Divider(color: Colors.white12, height: 20),

                    // ── 畫質 ─────────────────────────────────────────
                    const Text('影片畫質', style: TextStyle(color: Colors.white54, fontSize: 12)),
                    const SizedBox(height: 10),
                    Row(
                      children: VideoQuality.values.map((q) {
                        final selected = pendingQuality == q;
                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: _SettingChip(
                              label: q.label,
                              selected: selected,
                              onTap: () => setSheet(() => pendingQuality = q),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),

                    // ── 影片尺寸 ──────────────────────────────────────
                    const Text('影片尺寸', style: TextStyle(color: Colors.white54, fontSize: 12)),
                    const SizedBox(height: 10),
                    Row(
                      children: AspectRatioMode.values.map((r) {
                        final selected = pendingRatio == r;
                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: _SettingChip(
                              label: r.label,
                              selected: selected,
                              onTap: () => setSheet(() => pendingRatio = r),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),

                    // ── 幀率 ─────────────────────────────────────────
                    const Text('幀率', style: TextStyle(color: Colors.white54, fontSize: 12)),
                    const SizedBox(height: 10),
                    Row(
                      children: FrameRate.values.map((f) {
                        final selected = pendingFps == f;
                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: _SettingChip(
                              label: f.label,
                              selected: selected,
                              onTap: () => setSheet(() => pendingFps = f),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    // 60fps 提示
                    if (pendingFps == FrameRate.fps60)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(
                          children: const [
                            Icon(Icons.info_outline_rounded, color: Colors.amber, size: 14),
                            SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '60fps 需要設備支援，若不支援將自動降回 30fps',
                                style: TextStyle(color: Colors.amber, fontSize: 11),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 24),

                    // 確認按鈕
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF1E8E5A),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: () {
                          Navigator.pop(ctx);
                          final changed = pendingQuality != _config.quality ||
                              pendingFps != _config.fps ||
                              pendingRatio != _config.aspectRatio;
                          if (changed) {
                            setState(() {
                              _config = RecordingConfig(
                                quality: pendingQuality,
                                fps: pendingFps,
                                aspectRatio: pendingRatio,
                              );
                            });
                          }
                        },
                        child: const Text('套用', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ─── 小元件 ───────────────────────────────────────────────────────────────────

class _SettingChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SettingChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
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
}

/// 左下角的目前設定標籤
class _ConfigBadge extends StatelessWidget {
  final RecordingConfig config;
  const _ConfigBadge({required this.config});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '${config.quality.label}  ${config.fps.label}  ${config.aspectRatio.label}',
        style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500),
      ),
    );
  }
}

class _RecordButton extends StatelessWidget {
  final bool isRecording;
  final VoidCallback onTap;

  const _RecordButton({required this.isRecording, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: isRecording ? Colors.red : Colors.white,
          shape: BoxShape.circle,
          boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 10, offset: Offset(0, 4))],
        ),
        child: Icon(
          isRecording ? Icons.stop_rounded : Icons.fiber_manual_record,
          color: isRecording ? Colors.white : Colors.red,
          size: 34,
        ),
      ),
    );
  }
}

class _RecordingBadge extends StatelessWidget {
  final Duration elapsed;
  final int frameCount;

  const _RecordingBadge({required this.elapsed, required this.frameCount});

  String get _timeStr {
    final m = elapsed.inMinutes.toString().padLeft(2, '0');
    final s = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
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
            width: 8,
            height: 8,
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            '$_timeStr  $frameCount 幀',
            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
