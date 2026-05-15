import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camerawesome/camerawesome_plugin.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as vt;

import '../models/recording_history_entry.dart';
import '../services/realtime_audio_service.dart';
import '../services/video_analysis_service.dart';
import 'mlkit_utils.dart';
import 'pose_csv_writer.dart';
import 'pose_detector_service.dart';
import 'pose_frame_model.dart';
import 'skeleton_painter.dart';
import 'test_video_selector_dialog.dart';

typedef RecordCompleteCallback = void Function({
  required String videoPath,
  required String csvPath,
  required String audioPath,
  required int durationSeconds,
  required String? thumbnailPath,
  required String? audioLabel,
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

  // 測試模式
  bool _isTestMode = false;
  RecordingHistoryEntry? _selectedTestVideo;

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
        title: Text(_isTestMode ? '高爾夫揮桿錄製 (測試模式)' : '高爾夫揮桿錄製'),
        actions: [
          if (!_isTestMode)
            IconButton(
              tooltip: '骨架顯示切換',
              icon: Icon(
                Icons.accessibility_new,
                color: _showSkeleton ? Colors.greenAccent : Colors.white38,
              ),
              onPressed: () => setState(() => _showSkeleton = !_showSkeleton),
            ),
          _TestModeChip(
            isTestMode: _isTestMode,
            disabled: _isRecording,
            onTap: _toggleTestMode,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isTestMode ? _buildTestModeUI() : _buildCameraUI(),
    );
  }

  // ─── 即時錄製 UI ──────────────────────────────────────────────────────────

  Widget _buildCameraUI() {
    return CameraAwesomeBuilder.custom(
      saveConfig: SaveConfig.video(
        pathBuilder: _buildCaptureRequest,
      ),
      onImageForAnalysis: _onImageAnalysis,
      imageAnalysisConfig: AnalysisConfig(
        androidOptions: const AndroidAnalysisOptions.nv21(width: 480),
        maxFramesPerSecond: 10,
        autoStart: true,
      ),
      builder: (state, preview) {
        // preview 是 AnalysisPreview（座標元數據），相機畫面由 camerawesome 自動顯示在後方
        return Stack(
          fit: StackFit.expand,
          children: [
            // 骨架覆蓋層
            if (_showSkeleton && _poses.isNotEmpty && _analysisImageSize != Size.zero)
              CustomPaint(
                painter: SkeletonPainter(
                  poses: _poses,
                  imageSize: _analysisImageSize,
                ),
              ),
            // 錄影中指示器
            if (_isRecording)
              Positioned(
                top: 16,
                right: 16,
                child: _RecordingBadge(elapsed: _elapsed, frameCount: _frameCount),
              ),
            // 錄影按鈕
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
    
    // 启动音频捕获
    try {
      await _audioService.start();
      debugPrint('[RecordScreen] ✅ 音频服务已启动');
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
    if (mounted) setState(() {
      _isRecording = false;
      _poses = [];
    });
    
    // 保存 CSV 数据
    try {
      await _csvWriter?.flush();
    } catch (e) {
      debugPrint('[RecordScreen] CSV flush error: $e');
    }

    // 停止音频录制
    try {
      await _audioService.stop();
      debugPrint('[RecordScreen] ✅ 音频录制已停止');

      // 保存 PCM 数据
      final rawSamples = _audioService.rawSamples;
      if (rawSamples.isNotEmpty) {
        final audioFile = File(_audioPath);
        final byteData = ByteData(rawSamples.length * 4);
        for (int i = 0; i < rawSamples.length; i++) {
          byteData.setFloat32(i * 4, rawSamples[i].toDouble(), Endian.little);
        }
        await audioFile.writeAsBytes(byteData.buffer.asUint8List());
        debugPrint('[RecordScreen] ✅ 音频文件已保存: $_audioPath (${rawSamples.length} samples)');
      } else {
        debugPrint('[RecordScreen] ⚠️ 没有音频样本');
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
      );
    } catch (e) {
      debugPrint('[RecordScreen] finishRecording error: $e');
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

      // 始終更新骨架以顯示預覽
      setState(() {
        _poses = poses;
        _analysisImageSize = Size(image.width.toDouble(), image.height.toDouble());
      });

      // 只在錄影中才寫入 CSV 和累加幀數
      if (_isRecording) {
        final frameModel = poses.isNotEmpty
            ? PoseFrameModel.fromPose(
                frame: _frameCount,
                timeSec: timeSec,
                poseUpdateId: _frameCount,  // ✅ 實時錄影：每幀都是新推論
                pose: poses.first,
                imgWidth: image.width.toDouble(),
                imgHeight: image.height.toDouble(),
              )
            : PoseFrameModel.empty(
                frame: _frameCount,
                timeSec: timeSec,
                poseUpdateId: _frameCount,  // ✅ 即使檢測失敗也遞增
              );

        _csvWriter?.addFrame(frameModel);

        if (mounted) {
          setState(() {
            _frameCount++;
          });
        }
      }
    } catch (e) {
      debugPrint('[Pose] $e');
    } finally {
      _isPoseProcessing = false;
    }
  }

  // ─── 測試模式 ─────────────────────────────────────────────────────────────

  void _toggleTestMode() {
    if (_isRecording) return;
    setState(() {
      _isTestMode = !_isTestMode;
      _selectedTestVideo = null;
    });
  }

  Future<void> _showTestVideoSelector() async {
    final selected = await showDialog<RecordingHistoryEntry>(
      context: context,
      builder: (_) => const TestVideoSelectorDialog(),
    );
    if (selected != null && mounted) {
      setState(() => _selectedTestVideo = selected);
    }
  }

  Future<void> _completeTestMode() async {
    if (_selectedTestVideo == null) return;

    final progressNotifier = ValueNotifier<(double, String)>((0.0, '準備中...'));

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: Colors.grey[900],
          title: const Text('影片分析中', style: TextStyle(color: Colors.white)),
          content: ValueListenableBuilder<(double, String)>(
            valueListenable: progressNotifier,
            builder: (_, val, __) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(
                  value: val.$1,
                  backgroundColor: Colors.grey[700],
                  color: Colors.green,
                ),
                const SizedBox(height: 12),
                Text(
                  val.$2,
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final dir = await getApplicationDocumentsDirectory();
      final testId = 'test_${DateTime.now().millisecondsSinceEpoch}';
      final testDir = Directory(p.join(dir.path, 'golf_recordings', testId));
      await testDir.create(recursive: true);

      final testVideoPath = p.join(testDir.path, 'swing.mp4');
      await File(_selectedTestVideo!.filePath).copy(testVideoPath);

      final result = await VideoAnalysisService().analyze(
        videoPath: testVideoPath,
        sessionDir: testDir.path,
        durationSeconds: _selectedTestVideo!.durationSeconds.clamp(1, 86400),
        onProgress: (prog, label) => progressNotifier.value = (prog, label),
      );

      if (!mounted) return;
      Navigator.pop(context);

      final thumbnailPath = await _generateThumbnail(testVideoPath);
      widget.onComplete?.call(
        videoPath: testVideoPath,
        csvPath: result.csvPath,
        audioPath: result.audioPath,
        durationSeconds: _selectedTestVideo!.durationSeconds.clamp(1, 86400),
        thumbnailPath: thumbnailPath,
        audioLabel: null,
      );

      if (mounted) Navigator.pop(context);
    } catch (e) {
      debugPrint('[TestMode] $e');
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('分析失敗: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      progressNotifier.dispose();
    }
  }

  Widget _buildTestModeUI() {
    if (_selectedTestVideo == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.video_library_outlined, color: Colors.orange, size: 40),
            ),
            const SizedBox(height: 24),
            const Text('測試模式', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            const Text(
              '從已導入的影片中選擇一支\n作為測試錄製',
              style: TextStyle(color: Colors.white54, fontSize: 16, height: 1.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),
            FilledButton.icon(
              onPressed: _showTestVideoSelector,
              icon: const Icon(Icons.video_library_outlined),
              label: const Text('選擇影片'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.orange,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
            ),
          ],
        ),
      );
    }

    final dur = Duration(seconds: _selectedTestVideo!.durationSeconds);
    final durStr = '${dur.inMinutes}:${(dur.inSeconds % 60).toString().padLeft(2, '0')}';

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(color: Colors.grey[800], borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.videocam, color: Colors.white54, size: 60),
          ),
          const SizedBox(height: 24),
          Text(
            _selectedTestVideo!.displayTitle,
            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(color: Colors.grey[800], borderRadius: BorderRadius.circular(20)),
            child: Text(
              '⏱️ $durStr • Round ${_selectedTestVideo!.roundIndex}',
              style: const TextStyle(color: Colors.white54, fontSize: 14),
            ),
          ),
          const SizedBox(height: 40),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: () => setState(() => _selectedTestVideo = null),
                icon: const Icon(Icons.clear),
                label: const Text('取消'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: const BorderSide(color: Colors.white24),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
              const SizedBox(width: 16),
              FilledButton.icon(
                onPressed: _completeTestMode,
                icon: const Icon(Icons.check),
                label: const Text('完成'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── 小元件 ───────────────────────────────────────────────────────────────────

class _TestModeChip extends StatelessWidget {
  final bool isTestMode;
  final bool disabled;
  final VoidCallback onTap;

  const _TestModeChip({required this.isTestMode, required this.disabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = isTestMode ? Colors.orange : Colors.grey;
    return GestureDetector(
      onTap: disabled ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: disabled ? 0.1 : 0.25),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: disabled ? Colors.grey.withValues(alpha: 0.3) : color),
        ),
        child: Text(
          isTestMode ? '🧪 測試' : '🎥 即時',
          style: TextStyle(
            color: disabled ? Colors.white24 : (isTestMode ? Colors.orange : Colors.white70),
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
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
