import 'dart:io';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:video_player/video_player.dart';

import '../models/recording_history_entry.dart';
import '../services/analysis_service.dart';
import '../services/chart_data_service.dart';
import '../theme/app_theme.dart';
import 'ai_coach_page.dart';

/// Lightweight player for reviewing a recorded swing video.
class VideoPlayerPage extends StatefulWidget {
  const VideoPlayerPage({
    super.key,
    required this.videoPath,
    this.avatarPath,
    this.startPosition,
    this.entry,
  });

  final String videoPath;
  final String? avatarPath;
  final Duration? startPosition;
  final RecordingHistoryEntry? entry;

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage>
    with SingleTickerProviderStateMixin {
  VideoPlayerController? _controller;
  late final TabController _tabController;
  bool _initialized = false;

  // Charts panel state
  bool _chartsExpanded = false;
  int _chartTabIndex = 0;
  ChartDataSet? _chartData;
  bool _chartsLoading = false;

  // AI analysis panel state
  bool _aiExpanded = false;
  AnalysisStatus? _aiStatus;
  bool _aiLoading = false;
  bool _aiSubmitting = false;

  static const _tabs = [
    (icon: Icons.videocam,  label: '原始',  type: 'original'),
    (icon: Icons.person,    label: '骨架',  type: 'skeleton'),
    (icon: Icons.analytics, label: '分析',  type: 'analyzed'),
  ];

  static const _chartTabs = [
    (label: '聲音峰值', color: Color(0xFFE53935)),
    (label: '手腕 Y',   color: Color(0xFF1565C0)),
    (label: '速度',      color: Color(0xFF1E8E5A)),
  ];

  String get _sessionDir => '${p.dirname(widget.videoPath)}${p.separator}';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this, initialIndex: 2)
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

    try {
      await ctrl.initialize();
      ctrl.addListener(_onUpdate);
      ctrl.setLooping(true);

      if (isOriginal && widget.startPosition != null) {
        await ctrl.seekTo(widget.startPosition!);
      }
      ctrl.play();

      if (mounted) setState(() => _initialized = true);
    } catch (e) {
      debugPrint('[VideoPlayer] 初始化失敗: $e');
      if (mounted) _showSnack('影片載入失敗');
    } finally {
      await old?.dispose();
    }
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  void _switchTo(String path) => _initController(path);

  void _toggleCharts() {
    setState(() => _chartsExpanded = !_chartsExpanded);
    if (_chartsExpanded && _chartData == null && !_chartsLoading) {
      _loadCharts();
    }
  }

  void _toggleAi() {
    setState(() => _aiExpanded = !_aiExpanded);
    if (_aiExpanded && _aiStatus == null && !_aiLoading) {
      _loadAiStatus();
    }
  }

  Future<void> _loadAiStatus() async {
    if (widget.entry == null) return;
    setState(() => _aiLoading = true);
    try {
      final videoId = p.basename(p.dirname(widget.videoPath));
      final status = await AnalysisService.instance
          .getLatestAnalysisForVideo(videoId);
      if (mounted) setState(() => _aiStatus = status);
    } catch (_) {
      // 未登入或網路失敗 → 靜默，顯示「尚未分析」
    } finally {
      if (mounted) setState(() => _aiLoading = false);
    }
  }

  Future<void> _openOrSubmitAi({bool forceReanalyze = false}) async {
    if (widget.entry == null) return;
    setState(() => _aiSubmitting = true);
    try {
      final sessionDir = p.dirname(widget.videoPath);
      final videoId    = p.basename(sessionDir);
      final csvPath    = p.join(sessionDir, 'pose_landmarks.csv');
      final hasCsv     = File(csvPath).existsSync();
      await AiCoachPage.submitAndPush(
        context:        context,
        videoId:        videoId,
        clipPath:       widget.videoPath,
        csvPath:        hasCsv ? csvPath : null,
        forceReanalyze: forceReanalyze,
      );
      // 回到此頁後刷新狀態
      if (mounted) {
        setState(() { _aiStatus = null; });
        _loadAiStatus();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('AI 分析失敗: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _aiSubmitting = false);
    }
  }

  Future<void> _loadCharts() async {
    final entry = widget.entry;
    if (entry == null) return;
    setState(() => _chartsLoading = true);
    try {
      final data = await ChartDataService.loadFromEntry(entry);
      if (mounted) setState(() { _chartData = data; _chartsLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _chartsLoading = false);
    }
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
            _buildChartsPanel(),
            _buildAiPanel(),
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
              if (widget.entry != null) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _toggleCharts,
                  child: AnimatedRotation(
                    turns: _chartsExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 250),
                    child: Icon(
                      Icons.bar_chart_rounded,
                      color: _chartsExpanded
                          ? const Color(0xFF1E8E5A)
                          : Colors.white54,
                      size: 24,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _toggleAi,
                  child: Icon(
                    Icons.psychology_rounded,
                    color: _aiExpanded
                        ? const Color(0xFF7C3AED)
                        : Colors.white54,
                    size: 24,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // ── 圖表面板 ─────────────────────────────────────────────────

  Widget _buildChartsPanel() {
    if (widget.entry == null) return const SizedBox.shrink();
    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeInOut,
      height: _chartsExpanded ? 244 : 0,
      color: const Color(0xFF121212),
      child: ClipRect(child: _buildChartContent()),
    );
  }

  Widget _buildChartContent() {
    if (_chartsLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF1E8E5A), strokeWidth: 2),
      );
    }
    final data = _chartData;
    if (data == null || data.isEmpty) {
      return const Center(
        child: Text('尚無圖表資料，請先完成分析',
            style: TextStyle(color: Colors.white38, fontSize: 12)),
      );
    }

    final activePoints = switch (_chartTabIndex) {
      0 => data.audioRms,
      1 => data.wristY,
      _ => data.wristSpeed,
    };
    final tab = _chartTabs[_chartTabIndex];
    final invertY = _chartTabIndex == 1;
    final yLabel = _chartTabIndex == 0
        ? (double v) => '${v.toStringAsFixed(0)}dB'
        : _chartTabIndex == 1
            ? (double v) => '${v.toStringAsFixed(0)}px'
            : (double v) => v.toStringAsFixed(0);

    return Column(
      children: [
        // Tab 列
        Container(
          height: 36,
          color: const Color(0xFF1A1A1A),
          child: Row(
            children: List.generate(_chartTabs.length, (i) {
              final t = _chartTabs[i];
              final selected = i == _chartTabIndex;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _chartTabIndex = i),
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: selected ? t.color : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                    child: Text(
                      t.label,
                      style: TextStyle(
                        color: selected ? t.color : Colors.white38,
                        fontSize: 12,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
        // 圖表
        Expanded(
          child: activePoints.isEmpty
              ? Center(
                  child: Text('${tab.label} 無資料',
                      style: const TextStyle(
                          color: Colors.white24, fontSize: 12)),
                )
              : Padding(
                  padding: const EdgeInsets.fromLTRB(4, 6, 12, 6),
                  child: _PlayerChart(
                    key: ValueKey(_chartTabIndex),
                    points: activePoints,
                    color: tab.color,
                    invertY: invertY,
                    hitSecond: widget.entry!.hitSecond,
                    yLabel: yLabel,
                  ),
                ),
        ),
      ],
    );
  }

  Widget _btn(IconData icon, VoidCallback onTap) =>
      GestureDetector(onTap: onTap, child: Icon(icon, color: Colors.white70, size: 26));

  // ── AI 分析面板 ──────────────────────────────────────────────

  Widget _buildAiPanel() {
    if (widget.entry == null) return const SizedBox.shrink();
    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeInOut,
      height: _aiExpanded ? _aiPanelHeight() : 0,
      color: const Color(0xFF0D0D1A),
      child: ClipRect(child: _buildAiContent()),
    );
  }

  double _aiPanelHeight() {
    if (_aiLoading) return 80;
    if (_aiStatus == null) return 100;
    if (_aiStatus!.isCompleted) return 160;
    return 100;
  }

  Widget _buildAiContent() {
    if (_aiLoading) {
      return const Center(
        child: SizedBox(
          width: 28, height: 28,
          child: CircularProgressIndicator(
              color: Color(0xFF7C3AED), strokeWidth: 2.5),
        ),
      );
    }
    final status = _aiStatus;

    // 尚無分析
    if (status == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            const Icon(Icons.psychology_rounded,
                color: Color(0xFF7C3AED), size: 22),
            const SizedBox(width: 10),
            const Expanded(
              child: Text('尚未進行 AI 教練分析',
                  style: TextStyle(color: Colors.white70, fontSize: 13)),
            ),
            _aiSubmitting
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(
                        color: Color(0xFF7C3AED), strokeWidth: 2))
                : TextButton(
                    onPressed: () => _openOrSubmitAi(),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF7C3AED),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                    ),
                    child: const Text('開始分析',
                        style: TextStyle(fontSize: 13)),
                  ),
          ],
        ),
      );
    }

    // 進行中
    if (status.isActive) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            const SizedBox(
              width: 20, height: 20,
              child: CircularProgressIndicator(
                  color: Color(0xFF7C3AED), strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(_aiStatusLabel(status.status),
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 13)),
            ),
            TextButton(
              onPressed: () => _openOrSubmitAi(),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF7C3AED),
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
              ),
              child: const Text('查看進度',
                  style: TextStyle(fontSize: 13)),
            ),
          ],
        ),
      );
    }

    // 已完成
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.psychology_rounded,
                  color: Color(0xFF7C3AED), size: 18),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('AI 教練分析',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ),
              if (status.severity != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _severityColor(status.severity!)
                        .withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: _severityColor(status.severity!)
                            .withValues(alpha: 0.6)),
                  ),
                  child: Text(
                    _severityLabel(status.severity!),
                    style: TextStyle(
                        fontSize: 11,
                        color: _severityColor(status.severity!),
                        fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
          if (status.summary != null) ...[
            const SizedBox(height: 8),
            Text(
              status.summary!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white60, fontSize: 12, height: 1.5),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => _openOrSubmitAi(forceReanalyze: true),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white38,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  textStyle: const TextStyle(fontSize: 12),
                ),
                child: const Text('重新分析'),
              ),
              const SizedBox(width: 4),
              ElevatedButton(
                onPressed: () => _openOrSubmitAi(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C3AED),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 6),
                  textStyle: const TextStyle(fontSize: 13),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('查看詳細'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _aiStatusLabel(String s) => switch (s) {
    'pending'    => '準備中...',
    'queued'     => '等待分析佇列...',
    'processing' => 'AI 教練分析中...',
    _            => '分析中...',
  };

  Color _severityColor(String s) => switch (s) {
    'high'   => kBadColor,
    'medium' => kCrispColor,
    _        => kGoodColor,
  };

  String _severityLabel(String s) => switch (s) {
    'high'   => '嚴重',
    'medium' => '中等',
    _        => '輕微',
  };
}

// ════════════════════════════════════════════════════════════════
// 播放器內用的深色主題圖表
// ════════════════════════════════════════════════════════════════

class _PlayerChart extends StatefulWidget {
  final List<ChartPoint> points;
  final Color color;
  final bool invertY;
  final double? hitSecond;
  final String Function(double) yLabel;

  const _PlayerChart({
    super.key,
    required this.points,
    required this.color,
    required this.invertY,
    required this.hitSecond,
    required this.yLabel,
  });

  @override
  State<_PlayerChart> createState() => _PlayerChartState();
}

class _PlayerChartState extends State<_PlayerChart> {
  late final double _rawMaxY = widget.invertY
      ? widget.points.map((e) => e.y).reduce((a, b) => a > b ? a : b)
      : 0;

  double _toRaw(double displayY) =>
      widget.invertY ? (_rawMaxY - displayY) : displayY;

  late final List<FlSpot> _spots = widget.invertY
      ? widget.points.map((p) => FlSpot(p.x, _rawMaxY - p.y)).toList()
      : widget.points.map((p) => FlSpot(p.x, p.y)).toList();

  late final double _minX = widget.points.first.x;
  late final double _maxX = widget.points.last.x;
  late final double _minY =
      _spots.map((s) => s.y).reduce((a, b) => a < b ? a : b);
  late final double _maxY =
      _spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
  double get _yPad => (_maxY - _minY) * 0.12 + 1;

  @override
  Widget build(BuildContext context) {
    return LineChart(
      LineChartData(
        minX: _minX,
        maxX: _maxX,
        minY: _minY - _yPad,
        maxY: _maxY + _yPad,
        clipData: const FlClipData.all(),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => Colors.black54,
            getTooltipItems: (spots) => spots
                .map((s) => LineTooltipItem(
                      '${s.x.toStringAsFixed(2)}s\n${widget.yLabel(_toRaw(s.y))}',
                      const TextStyle(color: Colors.white, fontSize: 10),
                    ))
                .toList(),
          ),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: (_maxY - _minY + 1) / 3,
          getDrawingHorizontalLine: (_) => FlLine(
            color: Colors.white.withValues(alpha: 0.07),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(
          show: true,
          border: Border(
            bottom: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
            left: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 38,
              interval: (_maxY - _minY + 1) / 3,
              getTitlesWidget: (val, _) => Text(
                widget.yLabel(_toRaw(val)),
                style: const TextStyle(fontSize: 8, color: Colors.white38),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 16,
              interval: (_maxX - _minX) / 4,
              getTitlesWidget: (val, _) => Text(
                '${val.toStringAsFixed(1)}s',
                style: const TextStyle(fontSize: 8, color: Colors.white38),
              ),
            ),
          ),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        extraLinesData: widget.hitSecond != null
            ? ExtraLinesData(verticalLines: [
                VerticalLine(
                  x: widget.hitSecond!,
                  color: const Color(0xFFFF6F00),
                  strokeWidth: 1.5,
                  dashArray: [5, 4],
                  label: VerticalLineLabel(
                    show: true,
                    alignment: Alignment.topRight,
                    labelResolver: (_) => 'Hit',
                    style: const TextStyle(
                      color: Color(0xFFFF6F00),
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ])
            : null,
        lineBarsData: [
          LineChartBarData(
            spots: _spots,
            isCurved: true,
            curveSmoothness: 0.25,
            color: widget.color,
            barWidth: 1.5,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  widget.color.withValues(alpha: 0.25),
                  widget.color.withValues(alpha: 0.02),
                ],
              ),
            ),
          ),
        ],
      ),
      duration: Duration.zero,
    );
  }

}

// ════════════════════════════════════════════════════════════════
// Simple preview page for a generated highlight clip.
// ════════════════════════════════════════════════════════════════

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
