import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter/services.dart';

import '../services/highlight_service.dart';
import '../services/auth_token_storage.dart';

const double _portraitAspect = 16/ 9; // force a portrait container regardless of source video

Widget _buildVideoBox(VideoPlayerController controller) {
  final Size s = controller.value.size;
  final double vw = s.width == 0 ? 1 : s.width;
  final double vh = s.height == 0 ? 1 : s.height;
  return AspectRatio(
    aspectRatio: _portraitAspect,
    child: Center(
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: vw,
          height:vh ,
          child: VideoPlayer(controller),
        ),
      ),
    ),
  );
}

/// Lightweight player for reviewing a recorded swing video.
class VideoPlayerPage extends StatefulWidget {
  const VideoPlayerPage({
    super.key,
    required this.videoPath,
    this.avatarPath,
    this.cloudVideoId,
  });

  final String videoPath;
  final String? avatarPath;
  final String? cloudVideoId; // 云端视频 ID（如果有的话）

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  VideoPlayerController? _controller;
  Future<void>? _initializeFuture;
  bool _isAnalyzing = false;
  bool _isTrajectoryRunning = false;
  String? _errorMessage;
  Map<String, dynamic>? _trajectoryResult;

  @override
  void initState() {
    super.initState();
    _initController();
  }

  void _initController() {
    // 如果有云端视频 ID，优先使用云端版本
    if (widget.cloudVideoId != null && widget.cloudVideoId!.isNotEmpty) {
      debugPrint('[播放器] 检测到云端视频 ID，优先使用云端版本');
      _initCloudController();
    } else {
      debugPrint('[播放器] 使用本地视频文件');
      _initLocalController();
    }
  }

  /// 初始化本地视频播放器
  void _initLocalController() {
    final file = File(widget.videoPath);
    if (!file.existsSync()) {
      setState(() => _errorMessage = 'Video file not found.');
      return;
    }
    final controller = VideoPlayerController.file(file);
    _controller = controller;
    _initializeFuture = controller.initialize().then((_) {
      controller.setLooping(true);
      controller.play();
      setState(() {});
    }).catchError((e) {
      setState(() => _errorMessage = 'Unable to play: $e');
    });
  }

  /// 初始化云端视频播放器
  void _initCloudController() async {
    try {
      // 获取访问令牌
      final token = await AuthTokenStorage.instance.getAccessToken();
      if (token == null) {
        setState(() => _errorMessage = 'Please login to play cloud videos');
        return;
      }

      // 构建云端视频流 URL
      const String baseUrl = 'https://tekswing.api.atk.tw';
      final streamUrl = '$baseUrl/api/videos/${widget.cloudVideoId}/stream';
      
      debugPrint('[播放器] 云端视频流 URL: $streamUrl');

      final controller = VideoPlayerController.networkUrl(
        Uri.parse(streamUrl),
        httpHeaders: {
          'Authorization': 'Bearer $token',
        },
      );
      
      _controller = controller;
      _initializeFuture = controller.initialize().then((_) {
        debugPrint('[播放器] 云端视频初始化成功');
        controller.setLooping(true);
        controller.play();
        setState(() {});
      }).catchError((e) {
        debugPrint('[播放器] 云端视频初始化失败: $e');
        // 如果云端加载失败，回退到本地版本
        setState(() => _errorMessage = 'Failed to load cloud video: $e. Falling back to local version.');
        _initLocalController();
      });
    } catch (e) {
      debugPrint('[播放器] 云端视频初始化异常: $e');
      setState(() => _errorMessage = 'Error loading cloud video: $e');
      _initLocalController();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _generateHighlight() async {
    if (_isAnalyzing) return;
    setState(() => _isAnalyzing = true);
    try {
      final out = await HighlightService.generateHighlight(widget.videoPath,
          beforeMs: 3000, afterMs: 3000, titleData: {'Name': 'Player', 'Course': 'Unknown'});
      if (!mounted) return;
      if (out != null && out.isNotEmpty) {
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => HighlightPreviewPage(videoPath: out)));
      } else {
        _showSnack('Highlight failed.');
      }
    } finally {
      if (mounted) setState(() => _isAnalyzing = false);
    }
  }

  Future<void> _runTrajectoryAnalysis() async {
    if (_isTrajectoryRunning) return;
    setState(() => _isTrajectoryRunning = true);
    const channel = MethodChannel('com.example.golf_score_app/trajectory');
    try {
      final res = await channel.invokeMethod<Map>('analyzeTrajectory', {
        'videoPath': widget.videoPath,
      });
      if (!mounted) return;
      if (res != null) {
        setState(() => _trajectoryResult = res.cast<String, dynamic>());
        _showSnack('軌跡分析完成');
      } else {
        _showSnack('沒有收到軌跡結果');
      }
    } catch (e) {
      if (mounted) {
        _showSnack('軌跡分析失敗: $e');
      }
    } finally {
      if (mounted) setState(() => _isTrajectoryRunning = false);
    }
  }

  void _showSnack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Video Review'),
        actions: [
          IconButton(
            tooltip: 'Generate Highlight',
            onPressed: _isAnalyzing ? null : _generateHighlight,
            icon: const Icon(Icons.movie_creation_outlined),
          ),
          if (widget.avatarPath != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: CircleAvatar(backgroundImage: FileImage(File(widget.avatarPath!))),
            ),
        ],
      ),
      body: Center(
        child: _errorMessage != null
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_errorMessage!, style: const TextStyle(color: Colors.redAccent)),
              )
            : controller == null
                ? const CircularProgressIndicator()
                : FutureBuilder<void>(
                    future: _initializeFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.done && controller.value.isInitialized) {
                        return Column(
                          children: [
                            _buildVideoBox(controller),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                ElevatedButton.icon(
                                  onPressed: _isAnalyzing ? null : _generateHighlight,
                                  icon: const Icon(Icons.movie),
                                  label: const Text('Generate Highlight'),
                                ),
                                const SizedBox(width: 12),
                                ElevatedButton.icon(
                                  onPressed: () {
                                    if (controller.value.isPlaying) {
                                      controller.pause();
                                    } else {
                                      controller.play();
                                    }
                                    setState(() {});
                                  },
                                  icon: Icon(controller.value.isPlaying ? Icons.pause : Icons.play_arrow),
                                  label: const Text('Play/Pause'),
                                ),
                                const SizedBox(width: 12),
                                ElevatedButton.icon(
                                  onPressed: _isTrajectoryRunning ? null : _runTrajectoryAnalysis,
                                  icon: _isTrajectoryRunning
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        )
                                      : const Icon(Icons.track_changes),
                                  label: const Text('軌跡分析'),
                                ),
                              ],
                            ),
                            if (_trajectoryResult != null) ...[
                              const SizedBox(height: 12),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                child: Text(
                                  '軌跡結果：$_trajectoryResult',
                                  style: const TextStyle(fontSize: 12, color: Colors.black87),
                                ),
                              ),
                            ],
                          ],
                        );
                      }
                      if (snapshot.hasError) {
                        return Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text('Unable to load video: ${snapshot.error}'),
                        );
                      }
                      return const CircularProgressIndicator();
                    },
                  ),
      ),
      floatingActionButton: controller == null
          ? null
          : FloatingActionButton(
              onPressed: () {
                if (!controller.value.isInitialized) return;
                setState(() {
                  if (controller.value.isPlaying) {
                    controller.pause();
                  } else {
                    controller.play();
                  }
                });
              },
              child: Icon(controller.value.isPlaying ? Icons.pause : Icons.play_arrow),
            ),
    );
  }
}

/// Simple preview page for a generated highlight clip
class HighlightPreviewPage extends StatefulWidget {
  const HighlightPreviewPage({super.key, required this.videoPath});
  final String videoPath;

  @override
  State<HighlightPreviewPage> createState() => _HighlightPreviewPageState();
}

class _HighlightPreviewPageState extends State<HighlightPreviewPage> {
  VideoPlayerController? _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = VideoPlayerController.file(File(widget.videoPath))
      ..initialize().then((_) {
        setState(() {});
        _ctrl?.play();
      });
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _ctrl;
    return Scaffold(
      appBar: AppBar(title: const Text('Preview Highlight')),
      body: Center(
        child: controller == null || !controller.value.isInitialized
            ? const CircularProgressIndicator()
            : _buildVideoBox(controller),
      ),
      floatingActionButton: controller == null
          ? null
          : FloatingActionButton(
              onPressed: () {
                if (controller.value.isPlaying) {
                  controller.pause();
                } else {
                  controller.play();
                }
                setState(() {});
              },
              child: Icon(controller.value.isPlaying ? Icons.pause : Icons.play_arrow),
            ),
    );
  }
}
