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

  // 分開：UI 位置刷新 vs 同步修正
  Timer? _posTimer;
  Timer? _syncTimer;

  // ── 初始化 ──────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _ctrlA = VideoPlayerController.file(File(widget.entryA.filePath));
    _ctrlB = VideoPlayerController.file(File(widget.entryB.filePath));

    await Future.wait([_ctrlA.initialize(), _ctrlB.initialize()]);

    final durA = _ctrlA.value.duration;
    final durB = _ctrlB.value.duration;
    // 以較短的為基準，避免 Slider 超出任一影片範圍
    _duration = durA < durB ? durA : durB;

    _ctrlA.setLooping(false);
    _ctrlB.setLooping(false);

    // 每 100ms 刷新 UI 進度條（不做任何 seek，純讀取）
    _posTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted || _seeking) return;
      final pos = _ctrlA.value.position;
      if ((pos - _position).abs() > const Duration(milliseconds: 33)) {
        setState(() => _position = pos);
      }
      // 播放結束偵測
      if (_playing && pos >= _duration - const Duration(milliseconds: 100)) {
        _handlePlaybackEnd();
      }
    });

    if (mounted) setState(() => _initialized = true);
  }

  void _handlePlaybackEnd() {
    _ctrlA.pause();
    _ctrlB.pause();
    _stopSync();
    if (mounted) setState(() { _playing = false; _position = _duration; });
  }

  // ── 同步：速度補償為主，seekTo 只做緊急修正 ──────────────

  void _startSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(milliseconds: 250), (_) async {
      if (!_playing || _seeking || !mounted) return;

      final posA = _ctrlA.value.position;
      final posB = _ctrlB.value.position;
      final driftMs = (posB - posA).inMilliseconds; // 正 = B 超前

      if (driftMs.abs() > 300) {
        // 嚴重漂移：直接 seekTo 修正（5s 短片不該發生）
        await _ctrlB.seekTo(posA);
        await _ctrlB.setPlaybackSpeed(1.0);
      } else if (driftMs > 50) {
        // B 超前：稍微放慢
        _ctrlB.setPlaybackSpeed(0.92);
      } else if (driftMs < -50) {
        // B 落後：稍微加速
        _ctrlB.setPlaybackSpeed(1.08);
      } else {
        // 已對齊：恢復正常速度
        _ctrlB.setPlaybackSpeed(1.0);
      }
    });
  }

  void _stopSync() {
    _syncTimer?.cancel();
    _ctrlB.setPlaybackSpeed(1.0);
  }

  // ── 控制 ────────────────────────────────────────────────────

  Future<void> _togglePlay() async {
    if (_playing) {
      _stopSync();
      await Future.wait([_ctrlA.pause(), _ctrlB.pause()]);
      if (mounted) setState(() => _playing = false);
    } else {
      // 播放前先讓 B 對齊 A 的當前位置（唯一的 hard seekTo）
      final posA = _ctrlA.value.position;
      await _ctrlB.seekTo(posA);
      await Future.wait([_ctrlA.play(), _ctrlB.play()]);
      _startSync();
      if (mounted) setState(() => _playing = true);
    }
  }

  Future<void> _seekTo(Duration pos) async {
    _seeking = true;
    Duration target = pos;
    if (target < Duration.zero) target = Duration.zero;
    if (target > _duration) target = _duration;

    if (mounted) setState(() => _position = target);
    // 兩個一起 seek，不需要串行
    await Future.wait([
      _ctrlA.seekTo(target),
      _ctrlB.seekTo(target),
    ]);
    _seeking = false;
  }

  Future<void> _step(Duration delta) async {
    if (_playing) {
      _stopSync();
      await Future.wait([_ctrlA.pause(), _ctrlB.pause()]);
      setState(() => _playing = false);
    }
    Duration next = _position + delta;
    if (next < Duration.zero) next = Duration.zero;
    if (next > _duration) next = _duration;
    await _seekTo(next);
  }

  // ── 清理 ────────────────────────────────────────────────────

  @override
  void dispose() {
    _posTimer?.cancel();
    _stopSync();
    _ctrlA.dispose();
    _ctrlB.dispose();
    super.dispose();
  }

  // ── 格式化 ──────────────────────────────────────────────────

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
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
            Expanded(child: _buildVideoRow()),
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
            Text('載入影片中…', style: TextStyle(color: Colors.white54, fontSize: 12)),
          ],
        ),
      );
    }
    return Row(
      children: [
        Expanded(child: _buildPanel(_ctrlA, 'A', isLeft: true)),
        Container(width: 1, color: Colors.white24),
        Expanded(child: _buildPanel(_ctrlB, 'B', isLeft: false)),
      ],
    );
  }

  Widget _buildPanel(VideoPlayerController ctrl, String label, {required bool isLeft}) {
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
              label,
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
    final pos   = _position.inMilliseconds.toDouble().clamp(0.0, total > 0 ? total : 1.0);

    return Container(
      color: Colors.black87,
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
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
              value: total > 0 ? pos : 0,
              max: total > 0 ? total : 1,
              onChangeStart: (_) {
                _seeking = true;
                if (_playing) {
                  _stopSync();
                  _ctrlA.pause();
                  _ctrlB.pause();
                  setState(() => _playing = false);
                }
              },
              onChanged: (v) =>
                  setState(() => _position = Duration(milliseconds: v.round())),
              onChangeEnd: (v) =>
                  _seekTo(Duration(milliseconds: v.round())),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _btn(Icons.replay_5,      () => _step(const Duration(seconds: -5))),
              const SizedBox(width: 16),
              _btn(Icons.skip_previous, () => _step(const Duration(milliseconds: -33))),
              const SizedBox(width: 16),
              GestureDetector(
                onTap: _togglePlay,
                child: Container(
                  width: 48, height: 48,
                  decoration: const BoxDecoration(
                    color: Color(0xFF1E8E5A),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _playing ? Icons.pause : Icons.play_arrow,
                    color: Colors.white, size: 28,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              _btn(Icons.skip_next,  () => _step(const Duration(milliseconds: 33))),
              const SizedBox(width: 16),
              _btn(Icons.forward_5,  () => _step(const Duration(seconds: 5))),
              const SizedBox(width: 24),
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

  Widget _btn(IconData icon, VoidCallback onTap) =>
      GestureDetector(onTap: onTap, child: Icon(icon, color: Colors.white70, size: 26));
}
