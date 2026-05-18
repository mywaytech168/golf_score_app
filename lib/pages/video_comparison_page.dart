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
  bool _syncBusy = false;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

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

    // 显示两支影片中较长的那个（确保能看完整）
    _duration = durA > durB ? durA : durB;

    // 两支影片都从 0 开始播放
    await _ctrlA.seekTo(Duration.zero);
    await _ctrlB.seekTo(Duration.zero);

    _ctrlA.setLooping(false);
    _ctrlB.setLooping(false);
    _ctrlA.addListener(_onCtrlUpdate);

    if (mounted) setState(() => _initialized = true);
  }

  // ── 同步邏輯 ─────────────────────────────────────────────────

  void _onCtrlUpdate() {
    if (!mounted || _seeking) return;
    
    // 使用 A 的当前位置作为相对位置（两支影片同时开始）
    final currentPos = _ctrlA.value.position;
    
    // 只在位置改变超过 1 帧时更新（减少 setState 调用）
    if ((currentPos - _position).abs() > const Duration(milliseconds: 33)) {
      setState(() => _position = currentPos);
    }
    
    // 检查是否播放完成
    if (_playing && !_ctrlA.value.isPlaying) {
      _stopSync();
      setState(() => _playing = false);
    }
  }

  void _startSync() {
    _syncTimer?.cancel();
    _syncBusy = false;
    _syncTimer = Timer.periodic(const Duration(milliseconds: 150), (_) async {
      if (!_playing || _seeking || _syncBusy || !mounted) return;
      final posA = _ctrlA.value.position;
      final posB = _ctrlB.value.position;
      if ((posB - posA).abs() > const Duration(milliseconds: 100)) {
        _syncBusy = true;
        await _ctrlB.seekTo(posA);
        _syncBusy = false;
      }
    });
  }

  void _stopSync() => _syncTimer?.cancel();

  // ── 控制 ────────────────────────────────────────────────────

  Future<void> _togglePlay() async {
    if (_playing) {
      // 暂停：立即停止同步定时器
      _stopSync();
      
      // 并行暂停两个影片
      await Future.wait([
        _ctrlA.pause(),
        _ctrlB.pause(),
      ]);
      
      if (mounted) setState(() => _playing = false);
    } else {
      // 播放：同时播放两支影片
      await Future.wait([
        _ctrlA.play(),
        _ctrlB.play(),
      ]);
      _startSync();
      
      if (mounted) setState(() => _playing = true);
    }
  }

  Future<void> _seekTo(Duration pos) async {
    _seeking = true;
    // 立即更新 UI 显示新位置
    if (mounted) setState(() => _position = pos);
    
    // 同时 seek 两支影片到相同位置
    await Future.wait([
      _ctrlA.seekTo(pos),
      _ctrlB.seekTo(pos),
    ]);
    
    _seeking = false;
  }

  Future<void> _step(Duration delta) async {
    // 如果正在播放，先暂停
    if (_playing) {
      _stopSync();
      await Future.wait([
        _ctrlA.pause(),
        _ctrlB.pause(),
      ]);
      setState(() => _playing = false);
    }
    
    // 计算目标位置
    Duration next = _position + delta;
    if (next < Duration.zero) next = Duration.zero;
    if (next > _duration) next = _duration;
    
    // 同时 seek 两支影片
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
              onChangeEnd: (v) {
                // 在后台进行 seek，不阻塞 UI
                unawaited(_seekTo(Duration(milliseconds: v.round())));
              },
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
