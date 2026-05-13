import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models/recording_history_entry.dart';
import '../services/recording_history_storage.dart';

const double _portraitAspect = 16 / 9; // force a portrait container regardless of source video

/// 自定义视频播放器 - 带进度条和控制按钮覆盖层
class VideoPlayerWithControls extends StatefulWidget {
  final VideoPlayerController controller;
  final VoidCallback onPlayPauseToggle;

  const VideoPlayerWithControls({
    Key? key,
    required this.controller,
    required this.onPlayPauseToggle,
  }) : super(key: key);

  @override
  State<VideoPlayerWithControls> createState() => _VideoPlayerWithControlsState();
}

class _VideoPlayerWithControlsState extends State<VideoPlayerWithControls> {
  bool _showControls = true;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        setState(() => _showControls = !_showControls);
      },
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 视频播放器 - 填满容器
          Container(
            color: Colors.black,
            child: Center(
              child: FittedBox(
                fit: BoxFit.contain,
                child: SizedBox(
                  width: widget.controller.value.size.width == 0
                      ? 1
                      : widget.controller.value.size.width,
                  height: widget.controller.value.size.height == 0
                      ? 1
                      : widget.controller.value.size.height,
                  child: VideoPlayer(widget.controller),
                ),
              ),
            ),
          ),
          // 控制层 (仅当 _showControls 为 true 时显示)
          if (_showControls)
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Play/Pause 按钮 - 带阴影效果
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.5),
                        blurRadius: 8,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: FloatingActionButton(
                    backgroundColor: Colors.white,
                    onPressed: widget.onPlayPauseToggle,
                    child: Icon(
                      widget.controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
                      color: Colors.black,
                      size: 32,
                    ),
                  ),
                ),
              ],
            ),
          // 底部进度条 (始终显示)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: VideoProgressIndicator(
              widget.controller,
              allowScrubbing: true,
              colors: VideoProgressColors(
                playedColor: Colors.deepOrange,
                bufferedColor: Colors.grey[400] ?? Colors.grey,
                backgroundColor: Colors.grey[300] ?? Colors.grey,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Lightweight player for reviewing a recorded swing video.
class VideoPlayerPage extends StatefulWidget {
  const VideoPlayerPage({
    super.key,
    required this.videoPath,
    this.avatarPath,
    this.startPosition,
  });

  final String videoPath; // swing.mp4 or clip.mp4
  final String? avatarPath;
  final Duration? startPosition; // 初始播放位置（用於擊球跳轉）

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  VideoPlayerController? _controller;
  Future<void>? _initializeFuture;
  String? _errorMessage;
  String? _currentVideoPath; // 当前播放的影片路径
  String _currentVideoType = 'original'; // 当前影片类型: original/skeleton/analyzed

  /// 获取会话目录路径
  String get _sessionDir {
    return widget.videoPath.replaceAll(RegExp(r'[^/\\]*$'), '');
  }

  @override
  void initState() {
    super.initState();
    _currentVideoPath = widget.videoPath;
    _initController();
  }

  void _initController() {
    _initLocalController();
  }

  /// 初始化本地视频播放器
  void _initLocalController() {
    final file = File(_currentVideoPath!);
    if (!file.existsSync()) {
      setState(() => _errorMessage = 'Video file not found.');
      return;
    }
    
    // 释放旧的控制器
    _controller?.dispose();
    
    final controller = VideoPlayerController.file(file);
    _controller = controller;
    _initializeFuture = controller.initialize().then((_) async {
      controller.setLooping(true);
      if (widget.startPosition != null && _currentVideoType == 'original') {
        await controller.seekTo(widget.startPosition!);
      }
      controller.play();
      setState(() {});
    }).catchError((e) {
      setState(() => _errorMessage = 'Unable to play: $e');
    });
  }

  /// 切换影片
  void _switchVideo(String videoPath, String videoType) {
    if (videoPath.isEmpty || !File(videoPath).existsSync()) {
      _showSnack('影片文件不存在');
      return;
    }
    
    setState(() {
      _currentVideoPath = videoPath;
      _currentVideoType = videoType;
      _errorMessage = null;
    });
    
    _initLocalController();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
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
                      if (snapshot.connectionState == ConnectionState.done &&
                          controller.value.isInitialized) {
                        return Column(
                          children: [
                            // 视频播放器 + 进度条 + 控制按钮 (占大部分空间)
                            Expanded(
                              flex: 9,
                              child: VideoPlayerWithControls(
                                controller: controller,
                                onPlayPauseToggle: () {
                                  setState(() {
                                    if (controller.value.isPlaying) {
                                      controller.pause();
                                    } else {
                                      controller.play();
                                    }
                                  });
                                },
                              ),
                            ),
                            // 底部操作按钮区 (占小部分空间)
                            Expanded(
                              flex: 1,
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                  children: [
                                    // 原始影片按钮
                                    ElevatedButton.icon(
                                      onPressed: _viewOriginalVideo,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green,
                                      ),
                                      icon: const Icon(Icons.videocam),
                                      label: const Text('原始影片'),
                                    ),
                                    // 骨架影片按钮
                                    ElevatedButton.icon(
                                      onPressed: _viewSkeletonVideo,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.blue,
                                      ),
                                      icon: const Icon(Icons.person),
                                      label: const Text('骨架影片'),
                                    ),
                                    // 分析影片按钮
                                    ElevatedButton.icon(
                                      onPressed: _viewAnalyzedVideo,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.orange,
                                      ),
                                      icon: const Icon(Icons.analytics),
                                      label: const Text('分析影片'),
                                    ),
                                  ],
                                ),
                              ),
                            ),
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
    );
  }

  /// 查看原始影片 (swing.mp4 or clip.mp4)
  Future<void> _viewOriginalVideo() async {
    final swingPath = _sessionDir + 'swing.mp4';
    final clipPath = _sessionDir + 'clip.mp4';
    
    final originalPath = File(swingPath).existsSync() ? swingPath : clipPath;
    
    if (!File(originalPath).existsSync()) {
      _showSnack('原始影片不存在');
      return;
    }
    
    _switchVideo(originalPath, 'original');
  }

  /// 查看骨架影片 (skeleton.mp4)
  Future<void> _viewSkeletonVideo() async {
    final skeletonPath = _sessionDir + 'skeleton.mp4';
    
    if (!File(skeletonPath).existsSync()) {
      _showSnack('骨架影片不存在');
      return;
    }
    
    _switchVideo(skeletonPath, 'skeleton');
  }

  /// 查看分析影片 (final.mp4)
  Future<void> _viewAnalyzedVideo() async {
    if (!File(widget.videoPath).existsSync()) {
      _showSnack('分析影片不存在');
      return;
    }
    
    _switchVideo(widget.videoPath, 'analyzed');
  }

  /// 显示骨架覆盖层
  Future<void> _showSkeletonOverlay() async {
    if (!mounted) return;
    
    final csvPath = _sessionDir + 'pose_landmarks.csv';
    
    // 检查骨架数据是否存在
    if (!await File(csvPath).exists()) {
      _showSnack('骨架数据不存在，请先进行影片分析');
      return;
    }

    if (!mounted) return;
    // 骨架数据已加载，待实现可视化功能
  }
}

/// Simple preview page for a generated highlight clip
class HighlightPreviewPage extends StatefulWidget {
  const HighlightPreviewPage({
    super.key,
    required this.videoPath,
  });
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
      appBar: AppBar(
        title: const Text('Preview Highlight'),
      ),
      body: Center(
        child: controller == null || !controller.value.isInitialized
            ? const CircularProgressIndicator()
            : VideoPlayerWithControls(
                controller: controller,
                onPlayPauseToggle: () {
                  setState(() {
                    if (controller.value.isPlaying) {
                      controller.pause();
                    } else {
                      controller.play();
                    }
                  });
                },
              ),
      ),
    );
  }
}
