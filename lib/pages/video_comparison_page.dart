import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

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
  // ── media_kit ────────────────────────────────────────────────
  late final Player _playerA;
  late final Player _playerB;
  late final VideoController _ctrlA;
  late final VideoController _ctrlB;

  bool _initialized = false;
  bool _playing = false;
  bool _seeking = false;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  StreamSubscription<Duration>? _posSub;
  Timer? _syncTimer;

  // ── 初始化 ──────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _playerA = Player();
    _playerB = Player();
    _ctrlA = VideoController(_playerA);
    _ctrlB = VideoController(_playerB);
    _init();
  }

  Future<void> _init() async {
    await Future.wait([
      _playerA.open(Media(widget.entryA.filePath), play: false),
      _playerB.open(Media(widget.entryB.filePath), play: false),
    ]);

    // state.duration may be zero immediately after open(); wait for real value
    Duration durA = _playerA.state.duration;
    Duration durB = _playerB.state.duration;
    if (durA == Duration.zero) {
      durA = await _playerA.stream.duration.firstWhere((d) => d > Duration.zero);
    }
    if (durB == Duration.zero) {
      durB = await _playerB.stream.duration.firstWhere((d) => d > Duration.zero);
    }
    _duration = durA < durB ? durA : durB;

    // 用 A 的 position stream 更新進度條
    _posSub = _playerA.stream.position.listen((pos) {
      if (!mounted || _seeking) return;
      final clamped = pos > _duration ? _duration : pos;
      if ((clamped - _position).abs() > const Duration(milliseconds: 33)) {
        setState(() => _position = clamped);
      }
      // 結束偵測
      if (_playing && pos >= _duration - const Duration(milliseconds: 100)) {
        _handleEnd();
      }
    });

    if (mounted) setState(() => _initialized = true);
  }

  void _handleEnd() {
    _playerA.pause();
    _playerB.pause();
    _stopSync();
    if (mounted) setState(() { _playing = false; _position = _duration; });
  }

  // ── 同步：速度補償為主 ────────────────────────────────────

  void _startSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(milliseconds: 200), (_) async {
      if (!_playing || _seeking || !mounted) return;

      final posA = _playerA.state.position;
      final posB = _playerB.state.position;
      final driftMs = (posB - posA).inMilliseconds; // 正 = B 超前

      if (driftMs.abs() > 300) {
        // 嚴重漂移：hard seek
        await _playerB.seek(posA);
        await _playerB.setRate(1.0);
      } else if (driftMs > 50) {
        // B 超前：放慢
        await _playerB.setRate(0.92);
      } else if (driftMs < -50) {
        // B 落後：加速
        await _playerB.setRate(1.08);
      } else {
        // 已對齊
        await _playerB.setRate(1.0);
      }
    });
  }

  void _stopSync() {
    _syncTimer?.cancel();
    _playerB.setRate(1.0);
  }

  // ── 控制 ────────────────────────────────────────────────────

  Future<void> _togglePlay() async {
    if (_playing) {
      _stopSync();
      await Future.wait([_playerA.pause(), _playerB.pause()]);
      if (mounted) setState(() => _playing = false);
    } else {
      // 播放前對齊 B 到 A 的當前位置
      final posA = _playerA.state.position;
      await _playerB.seek(posA);
      await Future.wait([_playerA.play(), _playerB.play()]);
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
    await Future.wait([_playerA.seek(target), _playerB.seek(target)]);
    _seeking = false;
  }

  Future<void> _step(Duration delta) async {
    if (_playing) {
      _stopSync();
      await Future.wait([_playerA.pause(), _playerB.pause()]);
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
    _posSub?.cancel();
    _stopSync();
    _playerA.dispose();
    _playerB.dispose();
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

  Widget _buildPanel(VideoController ctrl, String label, {required bool isLeft}) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Video(
          controller: ctrl,
          fit: BoxFit.contain,
          controls: NoVideoControls,
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
                  _playerA.pause();
                  _playerB.pause();
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
