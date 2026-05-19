import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';



/// Lightweight player for reviewing a recorded swing video.
class VideoPlayerPage extends StatefulWidget {
  const VideoPlayerPage({
    super.key,
    required this.videoPath,
    this.avatarPath,
    this.startPosition,
  });

  final String videoPath;
  final String? avatarPath;
  final Duration? startPosition;

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage>
    with SingleTickerProviderStateMixin {
  VideoPlayerController? _controller;
  late final TabController _tabController;
  bool _initialized = false;

  static const _tabs = [
    (icon: Icons.videocam,  label: '原始',  type: 'original'),
    (icon: Icons.person,    label: '骨架',  type: 'skeleton'),
    (icon: Icons.analytics, label: '分析',  type: 'analyzed'),
  ];

  String get _sessionDir =>
      widget.videoPath.replaceAll(RegExp(r'[^/\\]*$'), '');

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this)
      ..addListener(() {
        if (!_tabController.indexIsChanging) return;
        switch (_tabController.index) {
          case 0: _viewOriginal();
          case 1: _viewSkeleton();
          case 2: _viewAnalyzed();
        }
      });
    _initController(widget.videoPath, isOriginal: true);
  }

  Future<void> _initController(String path, {bool isOriginal = false}) async {
    final file = File(path);
    if (!file.existsSync()) {
      _showSnack('找不到影片檔案');
      return;
    }

    final old = _controller;
    old?.removeListener(_onUpdate);

    final ctrl = VideoPlayerController.file(file);
    _controller = ctrl;
    if (mounted) setState(() => _initialized = false);

    await ctrl.initialize();
    ctrl.addListener(_onUpdate);
    ctrl.setLooping(true);

    if (isOriginal && widget.startPosition != null) {
      await ctrl.seekTo(widget.startPosition!);
    }
    ctrl.play();

    if (mounted) setState(() => _initialized = true);
    await old?.dispose();
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  void _switchTo(String path) {
    _initController(path);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _controller?.removeListener(_onUpdate);
    _controller?.dispose();
    super.dispose();
  }

  void _showSnack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // ── 切換按鈕 ────────────────────────────────────────────────

  void _viewOriginal() {
    final path = File('${_sessionDir}swing.mp4').existsSync()
        ? '${_sessionDir}swing.mp4'
        : '${_sessionDir}clip.mp4';
    if (!File(path).existsSync()) { _showSnack('原始影片不存在'); return; }
    _switchTo(path);
  }

  void _viewSkeleton() {
    final path = '${_sessionDir}skeleton.mp4';
    if (!File(path).existsSync()) { _showSnack('骨架影片不存在'); return; }
    _switchTo(path);
  }

  void _viewAnalyzed() {
    if (!File(widget.videoPath).existsSync()) { _showSnack('分析影片不存在'); return; }
    _switchTo(widget.videoPath);
  }

  // ── UI ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(context),
            Expanded(child: _buildVideo()),
            if (_initialized) _buildControls(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Container(
      color: Colors.black87,
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            onPressed: () => Navigator.pop(context),
          ),
          Expanded(
            child: TabBar(
              controller: _tabController,
              indicatorColor: const Color(0xFF1E8E5A),
              indicatorWeight: 2,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white54,
              labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              unselectedLabelStyle: const TextStyle(fontSize: 13),
              tabs: _tabs.map((t) => Tab(
                height: 40,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(t.icon, size: 14),
                    const SizedBox(width: 4),
                    Text(t.label),
                  ],
                ),
              )).toList(),
            ),
          ),
          if (widget.avatarPath != null) ...[
            CircleAvatar(
              radius: 14,
              backgroundImage: FileImage(File(widget.avatarPath!)),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Widget _buildVideo() {
    final ctrl = _controller;
    if (ctrl == null || !_initialized) {
      return const Center(child: CircularProgressIndicator(color: Colors.white54));
    }
    return Center(
      child: AspectRatio(
        aspectRatio: ctrl.value.aspectRatio,
        child: VideoPlayer(ctrl),
      ),
    );
  }

  Widget _buildControls() {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return const SizedBox.shrink();

    final position = ctrl.value.position;
    final duration = ctrl.value.duration;
    final progress = duration.inMilliseconds > 0
        ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      color: Colors.black87,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              activeTrackColor: const Color(0xFF1E8E5A),
              thumbColor: Colors.white,
              inactiveTrackColor: Colors.white24,
              overlayColor: Colors.white24,
            ),
            child: Slider(
              value: progress,
              onChanged: (v) => ctrl.seekTo(duration * v),
            ),
          ),
          Row(
            children: [
              Text(_fmt(position),
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
              const Spacer(),
              _btn(Icons.skip_previous,
                  () => ctrl.seekTo(position - const Duration(milliseconds: 33))),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: () => ctrl.value.isPlaying ? ctrl.pause() : ctrl.play(),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    color: Color(0xFF1E8E5A),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    ctrl.value.isPlaying ? Icons.pause : Icons.play_arrow,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              _btn(Icons.skip_next,
                  () => ctrl.seekTo(position + const Duration(milliseconds: 33))),
              const Spacer(),
              Text(_fmt(duration),
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _btn(IconData icon, VoidCallback onTap) =>
      GestureDetector(onTap: onTap, child: Icon(icon, color: Colors.white70, size: 26));
}

/// Simple preview page for a generated highlight clip.
class HighlightPreviewPage extends StatefulWidget {
  const HighlightPreviewPage({super.key, required this.videoPath});
  final String videoPath;

  @override
  State<HighlightPreviewPage> createState() => _HighlightPreviewPageState();
}

class _HighlightPreviewPageState extends State<HighlightPreviewPage> {
  VideoPlayerController? _ctrl;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _ctrl = VideoPlayerController.file(File(widget.videoPath))
      ..initialize().then((_) {
        _ctrl?.addListener(_onUpdate);
        _ctrl?.setLooping(true);
        _ctrl?.play();
        if (mounted) setState(() => _initialized = true);
      });
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _ctrl?.removeListener(_onUpdate);
    _ctrl?.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _ctrl;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              height: 48,
              color: Colors.black87,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
                    padding: EdgeInsets.zero,
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 8),
                  const Text('精彩片段預覽',
                      style: TextStyle(color: Colors.white70, fontSize: 14)),
                ],
              ),
            ),
            Expanded(
              child: ctrl == null || !_initialized
                  ? const Center(child: CircularProgressIndicator(color: Colors.white54))
                  : Center(
                      child: AspectRatio(
                        aspectRatio: ctrl.value.aspectRatio,
                        child: VideoPlayer(ctrl),
                      ),
                    ),
            ),
            if (_initialized && ctrl != null)
              _buildControls(ctrl),
          ],
        ),
      ),
    );
  }

  Widget _buildControls(VideoPlayerController ctrl) {
    final position = ctrl.value.position;
    final duration = ctrl.value.duration;
    final progress = duration.inMilliseconds > 0
        ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      color: Colors.black87,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              activeTrackColor: const Color(0xFF1E8E5A),
              thumbColor: Colors.white,
              inactiveTrackColor: Colors.white24,
              overlayColor: Colors.white24,
            ),
            child: Slider(
              value: progress,
              onChanged: (v) => ctrl.seekTo(duration * v),
            ),
          ),
          Row(
            children: [
              Text(_fmt(position),
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
              const Spacer(),
              GestureDetector(
                onTap: () => ctrl.value.isPlaying ? ctrl.pause() : ctrl.play(),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    color: Color(0xFF1E8E5A),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    ctrl.value.isPlaying ? Icons.pause : Icons.play_arrow,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
              ),
              const Spacer(),
              Text(_fmt(duration),
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }
}
