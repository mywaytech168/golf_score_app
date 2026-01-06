import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../services/highlight_service.dart';

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
  const VideoPlayerPage({super.key, required this.videoPath, this.avatarPath});

  final String videoPath;
  final String? avatarPath;

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  VideoPlayerController? _controller;
  Future<void>? _initializeFuture;
  bool _isAnalyzing = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initController();
  }

  void _initController() {
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
                              ],
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
