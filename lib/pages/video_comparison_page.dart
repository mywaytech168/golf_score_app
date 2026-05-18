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

  // 相對進度（0 = 兩支影片的 hit 時刻對齊點）
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  // 對軸對齊：各影片的播放起始點（絕對）
  Duration _startA = Duration.zero;
  Duration _startB = Duration.zero;

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

    // hitSecond → Duration
    final hitA = _secToDur(widget.entryA.hitSecond ?? 0.0);
    final hitB = _secToDur(widget.entryB.hitSecond ?? 0.0);

    // 對軸公式
    // minT = -min(hitA, hitB)  → 最早的相對時刻
    // maxT =  min(durA-hitA, durB-hitB) → 最晚的相對時刻
    // startA = hitA + minT（可能 = 0 或 > 0）
    // startB = hitB + minT
    final minT  = hitA < hitB ? -hitA : -hitB;
    final endT  = (durA - hitA) < (durB - hitB) ? (durA - hitA) : (durB - hitB);
    _startA   = hitA + minT;
    _startB   = hitB + minT;
    _duration = endT - minT;

    await _ctrlA.seekTo(_startA);
    await _ctrlB.seekTo(_startB);

    _ctrlA.setLooping(false);
    _ctrlB.setLooping(false);
    _ctrlA.addListener(_onCtrlUpdate);

    if (mounted) setState(() => _initialized = true);
  }

  Duration _secToDur(double sec) =>
      Duration(microseconds: (sec * 1e6).round());

  // ── 同步邏輯 ─────────────────────────────────────────────────

  void _onCtrlUpdate() {
    if (!mounted || _seeking) return;
    final rel = _ctrlA.value.position - _startA;
    final clampedRel = rel < Duration.zero ? Duration.zero : rel;
    if ((clampedRel - _position).abs() > const Duration(milliseconds: 33)) {
      setState(() => _position = clampedRel);
    }
    if (_playing && !_ctrlA.value.isPlaying) {
      _stopSync();
      setState(() => _playing = false);
    }
  }

  void _startSync() {
    _syncTimer?.cancel();
    // 每 150ms 比對一次，誤差超過 1 幀就把 B 拉回對齊
    _syncTimer = Timer.periodic(const Duration(milliseconds: 150), (_) async {
      if (!_playing || _seeking) return;
      final absA     = _ctrlA.value.position;
      final absB     = _ctrlB.value.position;
      final targetB  = absA - _startA + _startB;
      final drift    = (absB - targetB).abs();
      if (drift > const Duration(milliseconds: 80)) {
        await _ctrlB.seekTo(targetB);
      }
    });
  }

  void _stopSync() => _syncTimer?.cancel();

  // ── 控制 ────────────────────────────────────────────────────

  Future<void> _togglePlay() async {
    if (_playing) {
      await _ctrlA.pause();
      await _ctrlB.pause();
      _stopSync();
    } else {
      // 先讓 B 對齊當前 A 的相對位置，再同時播放
      final targetB = _ctrlA.value.position - _startA + _startB;
      await _ctrlB.seekTo(targetB);
      await _ctrlA.play();
      await _ctrlB.play();
      _startSync();
    }
    setState(() => _playing = !_playing);
  }

  Future<void> _seekTo(Duration relPos) async {
    _seeking = true;
    await _ctrlA.seekTo(_startA + relPos);
    await _ctrlB.seekTo(_startB + relPos);
    _seeking = false;
    if (mounted) setState(() => _position = relPos);
  }

  Future<void> _step(Duration delta) async {
    if (_playing) {
      await _ctrlA.pause();
      await _ctrlB.pause();
      _stopSync();
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
    _stopSync();
    _ctrlA.removeListener(_onCtrlUpdate);
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
              onChangeStart: (_) => _seeking = true,
              onChanged: (v) => setState(
                  () => _position = Duration(milliseconds: v.round())),
              onChangeEnd: (v) async =>
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
