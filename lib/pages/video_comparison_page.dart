import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models/recording_history_entry.dart';

class VideoComparisonPage extends StatefulWidget {
  final RecordingHistoryEntry entryA;
  final RecordingHistoryEntry entryB;

  const VideoComparisonPage({
    super.key,
    required this.entryA,
    required this.entryB,
  });

  @override
  State<VideoComparisonPage> createState() => _VideoComparisonPageState();
}

class _VideoComparisonPageState extends State<VideoComparisonPage> {
  late VideoPlayerController _ctrlA;
  late VideoPlayerController _ctrlB;

  bool _initialized = false;
  bool _playing = false;
  bool _seeking = false;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  Timer? _syncTimer;

  // ── 初始化 ──────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _ctrlA = VideoPlayerController.file(File(widget.entryA.filePath));
    _ctrlB = VideoPlayerController.file(File(widget.entryB.filePath));

    await Future.wait([
      _ctrlA.initialize(),
      _ctrlB.initialize(),
    ]);

    // 以較短的影片為基準時長
    final durA = _ctrlA.value.duration;
    final durB = _ctrlB.value.duration;
    _duration = durA < durB ? durA : durB;

    _ctrlA.setLooping(false);
    _ctrlB.setLooping(false);

    _ctrlA.addListener(_onControllerUpdate);

    if (mounted) setState(() => _initialized = true);
  }

  // ── 同步邏輯 ─────────────────────────────────────────────

  void _onControllerUpdate() {
    if (!mounted || _seeking) return;
    final pos = _ctrlA.value.position;
    if ((pos - _position).abs() > const Duration(milliseconds: 50)) {
      setState(() => _position = pos);
    }
    // 影片結束 → 暫停同步
    if (_playing && !_ctrlA.value.isPlaying) {
      _stopSync();
      setState(() => _playing = false);
    }
  }

  void _startSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
      if (!_playing || _seeking) return;
      final posA = _ctrlA.value.position;
      final posB = _ctrlB.value.position;
      final diff = (posA - posB).abs();
      if (diff > const Duration(milliseconds: 200)) {
        await _ctrlB.seekTo(posA);
      }
    });
  }

  void _stopSync() => _syncTimer?.cancel();

  // ── 控制 ────────────────────────────────────────────────

  Future<void> _togglePlay() async {
    if (_playing) {
      await _ctrlA.pause();
      await _ctrlB.pause();
      _stopSync();
    } else {
      await _ctrlB.seekTo(_position);
      await _ctrlA.play();
      await _ctrlB.play();
      _startSync();
    }
    setState(() => _playing = !_playing);
  }

  Future<void> _seekTo(Duration pos) async {
    _seeking = true;
    await _ctrlA.seekTo(pos);
    await _ctrlB.seekTo(pos);
    _seeking = false;
    setState(() => _position = pos);
  }

  Future<void> _step(Duration delta) async {
    Duration next = _position + delta;
    if (next < Duration.zero) next = Duration.zero;
    if (next > _duration) next = _duration;
    if (_playing) {
      await _ctrlA.pause();
      await _ctrlB.pause();
      _stopSync();
      setState(() => _playing = false);
    }
    await _seekTo(next);
  }

  // ── 清理 ────────────────────────────────────────────────

  @override
  void dispose() {
    _stopSync();
    _ctrlA.removeListener(_onControllerUpdate);
    _ctrlA.dispose();
    _ctrlB.dispose();
    super.dispose();
  }

  // ── 格式化 ──────────────────────────────────────────────

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // ── UI ──────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // ── 頂部 bar ──
            _buildTopBar(context),
            // ── 雙影片區 ──
            Expanded(child: _buildVideoRow()),
            // ── 底部控制 ──
            if (_initialized) _buildControls(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Container(
      height: 40,
      color: Colors.black87,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
            padding: EdgeInsets.zero,
            onPressed: () => Navigator.pop(context),
          ),
          Expanded(
            child: Text(
              widget.entryA.displayTitle,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
          const Icon(Icons.compare_arrows, color: Colors.white54, size: 18),
          Expanded(
            child: Text(
              widget.entryB.displayTitle,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: 36),
        ],
      ),
    );
  }

  Widget _buildVideoRow() {
    if (!_initialized) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white54),
            SizedBox(height: 12),
            Text('載入影片中...', style: TextStyle(color: Colors.white54, fontSize: 12)),
          ],
        ),
      );
    }
    return Row(
      children: [
        Expanded(child: _buildVideoPanel(_ctrlA, widget.entryA, isLeft: true)),
        Container(width: 1, color: Colors.white24),
        Expanded(child: _buildVideoPanel(_ctrlB, widget.entryB, isLeft: false)),
      ],
    );
  }

  Widget _buildVideoPanel(VideoPlayerController ctrl, RecordingHistoryEntry entry, {required bool isLeft}) {
    return Stack(
      fit: StackFit.expand,
      children: [
        FittedBox(
          fit: BoxFit.contain,
          child: SizedBox(
            width: ctrl.value.size.width,
            height: ctrl.value.size.height,
            child: VideoPlayer(ctrl),
          ),
        ),
        // 角標
        Positioned(
          top: 6,
          left: isLeft ? 8 : null,
          right: isLeft ? null : 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: isLeft
                  ? const Color(0xFF1E8E5A).withAlpha(200)
                  : const Color(0xFF1565C0).withAlpha(200),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              isLeft ? 'A' : 'B',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildControls() {
    final total = _duration.inMilliseconds.toDouble();
    final pos = _position.inMilliseconds.toDouble().clamp(0.0, total > 0 ? total : 1.0);

    return Container(
      color: Colors.black87,
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // seek bar
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
              value: total > 0 ? pos : 0,
              max: total > 0 ? total : 1,
              onChangeStart: (_) => _seeking = true,
              onChanged: (v) => setState(() => _position = Duration(milliseconds: v.round())),
              onChangeEnd: (v) async {
                await _seekTo(Duration(milliseconds: v.round()));
              },
            ),
          ),
          // 按鈕行
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // -5s
              _controlBtn(
                icon: Icons.replay_5,
                onTap: () => _step(const Duration(seconds: -5)),
              ),
              const SizedBox(width: 16),
              // 逐幀後退
              _controlBtn(
                icon: Icons.skip_previous,
                onTap: () => _step(const Duration(milliseconds: -33)),
              ),
              const SizedBox(width: 16),
              // 播放/暫停
              GestureDetector(
                onTap: _togglePlay,
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E8E5A),
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: Colors.black38, blurRadius: 6)],
                  ),
                  child: Icon(
                    _playing ? Icons.pause : Icons.play_arrow,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // 逐幀前進
              _controlBtn(
                icon: Icons.skip_next,
                onTap: () => _step(const Duration(milliseconds: 33)),
              ),
              const SizedBox(width: 16),
              // +5s
              _controlBtn(
                icon: Icons.forward_5,
                onTap: () => _step(const Duration(seconds: 5)),
              ),
              const SizedBox(width: 24),
              // 時間標籤
              Text(
                '${_fmt(_position)} / ${_fmt(_duration)}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _controlBtn({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Icon(icon, color: Colors.white70, size: 26),
    );
  }
}
