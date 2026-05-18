import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../models/recording_history_entry.dart';
import '../services/analysis_progress_service.dart';
import '../services/video_comparison_service.dart';

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
  // ── 渲染階段 ──────────────────────────────────────────────────
  bool _rendering = true;
  String _renderLabel = '準備中…';
  double _renderProgress = 0.0;
  String? _renderError;
  String? _mergedPath;

  // ── 播放階段 ──────────────────────────────────────────────────
  VideoPlayerController? _ctrl;
  bool _initialized = false;
  bool _playing = false;
  bool _seeking = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _startRender();
  }

  // ── 渲染 ─────────────────────────────────────────────────────

  Future<void> _startRender() async {
    void onProgress() {
      final (prog, label) = AnalysisProgressService.instance.progress.value;
      if (mounted) setState(() { _renderProgress = prog; _renderLabel = label; });
    }
    AnalysisProgressService.instance.progress.addListener(onProgress);

    try {
      final tmp = await getTemporaryDirectory();
      final outPath = '${tmp.path}/cmp_${DateTime.now().millisecondsSinceEpoch}.mp4';

      final ok = await VideoComparisonService().renderComparison(
        pathA: widget.entryA.filePath,
        pathB: widget.entryB.filePath,
        outputPath: outPath,
        hitSecA: widget.entryA.hitSecond ?? 0.0,
        hitSecB: widget.entryB.hitSecond ?? 0.0,
      );

      if (!mounted) return;
      if (!ok || !File(outPath).existsSync()) {
        setState(() { _rendering = false; _renderError = '合成失敗，請稍後再試'; });
        return;
      }

      _mergedPath = outPath;
      if (mounted) setState(() => _rendering = false);
      await _initPlayer(outPath);
    } catch (e) {
      if (mounted) setState(() { _rendering = false; _renderError = '錯誤：$e'; });
    } finally {
      AnalysisProgressService.instance.progress.removeListener(onProgress);
    }
  }

  Future<void> _initPlayer(String path) async {
    final ctrl = VideoPlayerController.file(File(path));
    await ctrl.initialize();
    ctrl.setLooping(false);
    ctrl.addListener(_onCtrlUpdate);
    if (mounted) {
      setState(() {
        _ctrl = ctrl;
        _duration = ctrl.value.duration;
        _initialized = true;
      });
    }
  }

  // ── 播放回調 ─────────────────────────────────────────────────

  void _onCtrlUpdate() {
    if (!mounted || _seeking || _ctrl == null) return;
    final pos = _ctrl!.value.position;
    if ((pos - _position).abs() > const Duration(milliseconds: 33)) {
      setState(() => _position = pos);
    }
    if (_playing && !_ctrl!.value.isPlaying) {
      setState(() => _playing = false);
    }
  }

  Future<void> _togglePlay() async {
    final ctrl = _ctrl;
    if (ctrl == null) return;
    if (_playing) {
      await ctrl.pause();
    } else {
      await ctrl.play();
    }
    setState(() => _playing = !_playing);
  }

  Future<void> _seekTo(Duration pos) async {
    _seeking = true;
    await _ctrl?.seekTo(pos);
    _seeking = false;
    if (mounted) setState(() => _position = pos);
  }

  Future<void> _step(Duration delta) async {
    if (_playing) { await _ctrl?.pause(); setState(() => _playing = false); }
    Duration next = _position + delta;
    if (next < Duration.zero) next = Duration.zero;
    if (next > _duration) next = _duration;
    await _seekTo(next);
  }

  // ── 清理 ─────────────────────────────────────────────────────

  @override
  void dispose() {
    _ctrl?.removeListener(_onCtrlUpdate);
    _ctrl?.dispose();
    if (_mergedPath != null) File(_mergedPath!).delete().ignore();
    super.dispose();
  }

  // ── 格式化 ───────────────────────────────────────────────────

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // ── UI ───────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(context),
            Expanded(child: _buildBody()),
            if (_initialized) _buildControls(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Container(
      height: 44,
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
          const Icon(Icons.compare_arrows, color: Colors.white38, size: 18),
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

  Widget _buildBody() {
    if (_renderError != null) return _buildError();
    if (_rendering) return _buildLoading();
    if (_initialized && _ctrl != null) return _buildPlayer();
    return const Center(child: CircularProgressIndicator(color: Colors.white54));
  }

  Widget _buildLoading() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.movie_creation_outlined, color: Colors.white38, size: 48),
            const SizedBox(height: 20),
            Text(
              _renderLabel,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: _renderProgress > 0 ? _renderProgress : null,
              backgroundColor: Colors.white12,
              valueColor: const AlwaysStoppedAnimation(Color(0xFF1E8E5A)),
            ),
            const SizedBox(height: 8),
            Text(
              '${(_renderProgress * 100).toInt()}%',
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
            const SizedBox(height: 16),
            Text(
              _renderError!,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('返回', style: TextStyle(color: Color(0xFF1E8E5A))),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayer() {
    final ctrl = _ctrl!;
    return FittedBox(
      fit: BoxFit.contain,
      child: SizedBox(
        width: ctrl.value.size.width,
        height: ctrl.value.size.height,
        child: VideoPlayer(ctrl),
      ),
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
              onChanged: (v) => setState(() => _position = Duration(milliseconds: v.round())),
              onChangeEnd: (v) async => _seekTo(Duration(milliseconds: v.round())),
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
