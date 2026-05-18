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

  // 進度用 0.0~1.0 的相對百分比，不用絕對時間
  double _progress = 0.0;
  Duration _durationA = Duration.zero;
  Duration _durationB = Duration.zero;

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

    // 取得各自真實時長（若 open 後仍為 0 則等 stream）
    Duration durA = _playerA.state.duration;
    Duration durB = _playerB.state.duration;
    if (durA == Duration.zero) {
      durA = await _playerA.stream.duration.firstWhere((d) => d > Duration.zero);
    }
    if (durB == Duration.zero) {
      durB = await _playerB.stream.duration.firstWhere((d) => d > Duration.zero);
    }
    _durationA = durA;
    _durationB = durB;

    // 監聽 A 的播放位置 → 換算成相對進度
    _posSub = _playerA.stream.position.listen((pos) {
      if (!mounted || _seeking || _durationA == Duration.zero) return;
      final p = (pos.inMilliseconds / _durationA.inMilliseconds).clamp(0.0, 1.0);
      if ((p - _progress).abs() > 0.005) {
        setState(() => _progress = p);
      }
      if (_playing && p >= 0.999) {
        _handleEnd();
      }
    });

    if (mounted) setState(() => _initialized = true);
  }

  void _handleEnd() {
    _playerA.pause();
    _playerB.pause();
    _stopSync();
    if (mounted) setState(() { _playing = false; _progress = 1.0; });
  }

  // ── 同步：比較相對進度，速度補償 ────────────────────────────

  void _startSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(milliseconds: 200), (_) async {
      if (!_playing || _seeking || !mounted) return;
      if (_durationA == Duration.zero || _durationB == Duration.zero) return;

      final progA = _playerA.state.position.inMilliseconds / _durationA.inMilliseconds;
      final progB = _playerB.state.position.inMilliseconds / _durationB.inMilliseconds;
      final drift = progB - progA; // 正 = B 超前

      if (drift.abs() > 0.02) {
        // 超過 2% 差距 → hard seek 對齊
        await _playerB.seek(_durationB * progA.clamp(0.0, 1.0));
        await _playerB.setRate(1.0);
      } else if (drift > 0.003) {
        await _playerB.setRate(0.92);
      } else if (drift < -0.003) {
        await _playerB.setRate(1.08);
      } else {
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
      // 播放前對齊 B 到 A 的當前進度對應位置
      final posA = _playerA.state.position;
      final progA = _durationA == Duration.zero
          ? 0.0
          : (posA.inMilliseconds / _durationA.inMilliseconds).clamp(0.0, 1.0);
      await _playerB.seek(_durationB * progA);
      await Future.wait([_playerA.play(), _playerB.play()]);
      _startSync();
      if (mounted) setState(() => _playing = true);
    }
  }

  Future<void> _seekToProgress(double progress) async {
    _seeking = true;
    final p = progress.clamp(0.0, 1.0);
    if (mounted) setState(() => _progress = p);
    await Future.wait([
      _playerA.seek(_durationA * p),
      _playerB.seek(_durationB * p),
    ]);
    _seeking = false;
  }

  Future<void> _step(double delta) async {
    if (_playing) {
      _stopSync();
      await Future.wait([_playerA.pause(), _playerB.pause()]);
      setState(() => _playing = false);
    }
    await _seekToProgress(_progress + delta);
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
        Expanded(child: _buildPanel(_ctrlA, 'A', _durationA, isLeft: true)),
        Container(width: 1, color: Colors.white24),
        Expanded(child: _buildPanel(_ctrlB, 'B', _durationB, isLeft: false)),
      ],
    );
  }

  Widget _buildPanel(VideoController ctrl, String label, Duration duration, {required bool isLeft}) {
    // 各影片根據自身時長計算當前時間，顯示在角落
    final currentMs = (_progress * duration.inMilliseconds).round();
    final current = Duration(milliseconds: currentMs);

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
              '$label  ${_fmt(current)}/${_fmt(duration)}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildControls() {
    final pct = (_progress * 100).round();

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
              value: _progress,
              min: 0.0,
              max: 1.0,
              onChangeStart: (_) {
                _seeking = true;
                if (_playing) {
                  _stopSync();
                  _playerA.pause();
                  _playerB.pause();
                  setState(() => _playing = false);
                }
              },
              onChanged: (v) => setState(() => _progress = v),
              onChangeEnd: (v) => _seekToProgress(v),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _btn(Icons.replay_5,      () => _step(-0.05)),
              const SizedBox(width: 16),
              _btn(Icons.skip_previous, () => _step(-0.01)),
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
              _btn(Icons.skip_next,  () => _step(0.01)),
              const SizedBox(width: 16),
              _btn(Icons.forward_5,  () => _step(0.05)),
              const SizedBox(width: 24),
              Text(
                '$pct%',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
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
