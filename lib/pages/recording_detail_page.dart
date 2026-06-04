import 'dart:convert';
import 'dart:io';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../models/recording_history_entry.dart';
import '../models/swing_posture.dart';
import '../services/analysis_service.dart';
import '../services/audio_analysis_service.dart';
import '../services/chart_data_service.dart';
import '../services/clip_pipeline_service.dart';
import '../services/recording_history_storage.dart';
import '../services/swing_impact_detector.dart';
import '../services/video_export_service.dart';
import '../theme/app_theme.dart';

/// 錄影詳情頁：顯示聲音峰值、手腕 Y、Speed 三張圖表
class RecordingDetailPage extends StatefulWidget {
  final RecordingHistoryEntry entry;

  const RecordingDetailPage({super.key, required this.entry});

  @override
  State<RecordingDetailPage> createState() => _RecordingDetailPageState();
}

class _RecordingDetailPageState extends State<RecordingDetailPage> {
  ChartDataSet? _data;
  bool _loading = true;
  String? _error;

  String? _postureAnalysisId;
  bool _isAutoAnalyzing = false;
  bool _isDownloading   = false;

  @override
  void initState() {
    super.initState();
    _postureAnalysisId = widget.entry.postureAnalysisId;
    _loadData();
    if (_postureAnalysisId == null && widget.entry.isAnalyzed) {
      _startAutoPostureAnalysis();
    }
  }

  Future<void> _startAutoPostureAnalysis() async {
    final sessionDir = p.dirname(widget.entry.filePath);
    final csvPath    = p.join(sessionDir, 'pose_landmarks.csv');
    if (!File(csvPath).existsSync()) return;

    if (mounted) setState(() => _isAutoAnalyzing = true);
    try {
      final svc     = AnalysisService.instance;
      final videoId = p.basename(sessionDir);

      // 先查後端是否已有分析，避免每次進圖表頁都重複送出
      String analysisId;
      final existing = await svc.getLatestAnalysisForVideo(videoId);
      if (existing != null && !existing.isFailed) {
        analysisId = existing.analysisId;
        // 已完成（idle = posture_only done，completed = full done）→ 直接存入並返回
        if (existing.isIdle || existing.isCompleted) {
          final updated = widget.entry.copyWith(postureAnalysisId: analysisId);
          await RecordingHistoryStorage.instance.upsertEntry(updated);
          if (mounted) {
            setState(() {
              _postureAnalysisId = analysisId;
              _isAutoAnalyzing   = false;
            });
          }
          return;
        }
        // 仍在處理中 → 等它完成即可，不新送
      } else {
        // 完全沒有或上次失敗 → 才送出新的 posture_only
        analysisId = await svc.submitForAnalysis(
          videoId:  videoId,
          clipPath: widget.entry.filePath,
          csvPath:  csvPath,
          mode:     'posture_only',
        );
      }

      // 輪詢直到完成（最多 90 秒）
      for (int i = 0; i < 15; i++) {
        await Future<void>.delayed(const Duration(seconds: 6));
        if (!mounted) return;
        final status = await svc.getStatus(analysisId);
        if (status.isIdle || status.isFailed) {
          if (!mounted) return;
          if (status.isIdle) {
            final updated = widget.entry.copyWith(postureAnalysisId: analysisId);
            await RecordingHistoryStorage.instance.upsertEntry(updated);
          }
          setState(() {
            _postureAnalysisId = status.isIdle ? analysisId : null;
            _isAutoAnalyzing   = false;
          });
          return;
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _isAutoAnalyzing = false);
  }

  Future<void> _loadData() async {
    try {
      final data = await ChartDataService.loadFromEntry(widget.entry);
      if (mounted) {
        setState(() {
          _data = data;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  String get _title {
    if (widget.entry.customName != null && widget.entry.customName!.isNotEmpty) {
      return widget.entry.customName!;
    }
    final name = p.basenameWithoutExtension(widget.entry.filePath);
    return name.length > 24 ? '${name.substring(0, 24)}…' : name;
  }

  // ── 下載影片 ────────────────────────────────────────────────────

  /// 可下載的影片項目定義
  static const _kDownloadOptions = [
    _VideoOption(
      file:  'final.mp4',
      label: '分析完整版',
      desc:  '骨架 + 球軌跡',
      icon:  Icons.sports_golf_rounded,
    ),
    _VideoOption(
      file:  'skeleton.mp4',
      label: '骨架版',
      desc:  '只含骨架 overlay',
      icon:  Icons.accessibility_new_rounded,
    ),
    _VideoOption(
      file:  'swing.mp4',
      label: '原始影片',
      desc:  '無任何 overlay',
      icon:  Icons.videocam_rounded,
    ),
    _VideoOption(
      file:  'swing.mov',
      label: '原始影片 (MOV)',
      desc:  '原始 MOV 檔',
      icon:  Icons.videocam_rounded,
    ),
  ];

  /// 顯示下載選單 → 使用者選擇 → 執行下載
  Future<void> _downloadVideo() async {
    final sessionDir = p.dirname(widget.entry.filePath);

    // 篩選出實際存在的檔案
    final available = _kDownloadOptions
        .where((o) => File(p.join(sessionDir, o.file)).existsSync())
        .toList();

    if (available.isEmpty) {
      _showSnack('找不到可下載的影片', isError: true);
      return;
    }

    // 彈出選單
    final chosen = await showModalBottomSheet<_VideoOption>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _DownloadPicker(options: available),
    );
    if (chosen == null || !mounted) return;

    // 執行下載
    setState(() => _isDownloading = true);
    try {
      final videoPath  = p.join(sessionDir, chosen.file);
      final displayName = '${_title.replaceAll(RegExp(r'[^\w一-龥]'), '_')}_${chosen.label}';
      final result = await VideoExportService.download(videoPath, displayName: displayName);

      if (!mounted) return;
      switch (result.status) {
        case ExportStatus.savedToDownloads:
          _showSnack('「${chosen.label}」已儲存到下載資料夾 ✅');
        case ExportStatus.savedToPhotos:
          _showSnack('「${chosen.label}」已儲存到相機膠卷 ✅');
        case ExportStatus.sharedViaSheet:
          _showSnack('已開啟分享 ✅');
        case ExportStatus.failed:
          _showSnack('下載失敗：${result.detail}', isError: true);
      }
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red[700] : Colors.green[700],
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        backgroundColor: kPrimaryGreen,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(_title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        actions: [
          // ── 下載影片 ───────────────────────────────────────
          if (_isDownloading)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.download_rounded),
              tooltip: '下載影片',
              onPressed: _downloadVideo,
            ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              setState(() => _loading = true);
              _loadData();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          _MetaHeader(entry: widget.entry),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: kPrimaryGreen))
                : _error != null
                    ? _ErrorView(message: _error!)
                    : _data == null || _data!.isEmpty
                        ? const _NoDataView()
                        : _ChartsBody(data: _data!, hitSecond: widget.entry.hitSecond, entry: widget.entry, postureAnalysisId: _postureAnalysisId, isAutoAnalyzing: _isAutoAnalyzing),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// 頂部資訊列
// ════════════════════════════════════════════════════════════════

class _MetaHeader extends StatelessWidget {
  final RecordingHistoryEntry entry;
  const _MetaHeader({required this.entry});

  @override
  Widget build(BuildContext context) {
    final thumb = entry.thumbnailPath;
    final fmt = DateFormat('yyyy/MM/dd HH:mm');
    final timeStr = fmt.format(entry.recordedAt);
    final dur = entry.durationSeconds;
    final durStr = dur >= 60
        ? '${dur ~/ 60}m ${dur % 60}s'
        : '${dur}s';

    return Container(
      color: kPrimaryGreen,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Row(
        children: [
          // 縮圖
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: thumb != null && File(thumb).existsSync()
                ? Image.file(File(thumb), width: 72, height: 52, fit: BoxFit.cover)
                : Container(
                    width: 72, height: 52,
                    color: Colors.white24,
                    child: const Icon(Icons.videocam_rounded, color: Colors.white54, size: 28),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(timeStr, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(Icons.timer_outlined, color: Colors.white70, size: 14),
                  const SizedBox(width: 4),
                  Text(durStr, style: const TextStyle(color: Colors.white, fontSize: 13)),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// 圖表主體
// ════════════════════════════════════════════════════════════════

class _ChartsBody extends StatelessWidget {
  final ChartDataSet data;
  final double? hitSecond;
  final RecordingHistoryEntry entry;
  final String? postureAnalysisId;
  final bool isAutoAnalyzing;

  const _ChartsBody({required this.data, this.hitSecond, required this.entry, this.postureAnalysisId, this.isAutoAnalyzing = false});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        _SwingPhasesCard(entry: entry),
        const SizedBox(height: 16),
        if (postureAnalysisId != null)
          _OnnxPostureCard(analysisId: postureAnalysisId!)
        else if (isAutoAnalyzing)
          _AutoAnalyzingPostureCard(),
        if (postureAnalysisId != null || isAutoAnalyzing) const SizedBox(height: 16),
        if (data.audioRms.isNotEmpty)
          _ChartCard(
            title: '聲音峰值',
            subtitle: 'RMS dBFS',
            icon: Icons.graphic_eq_rounded,
            color: const Color(0xFFE53935),
            points: data.audioRms,
            hitSecond: hitSecond,
            yLabel: (v) => '${v.toStringAsFixed(0)}dB',
            invertY: false,
          )
        else
          const _MissingDataCard(label: '聲音峰值', hint: '需完成音頻分析'),
        const SizedBox(height: 16),
        if (data.wristY.isNotEmpty)
          _ChartCard(
            title: '手腕 Y',
            subtitle: '右手腕 Y 位置（像素）',
            icon: Icons.sports_golf_rounded,
            color: const Color(0xFF1565C0),
            points: data.wristY,
            hitSecond: hitSecond,
            yLabel: (v) => '${v.toStringAsFixed(0)}px',
            invertY: true,  // 螢幕 Y 向下，圖表反轉較直覺
          )
        else
          const _MissingDataCard(label: '手腕 Y', hint: '需完成姿勢分析'),
        const SizedBox(height: 16),
        if (data.wristSpeed.isNotEmpty)
          _ChartCard(
            title: 'Speed',
            subtitle: '手腕移動速度（px/frame）',
            icon: Icons.speed_rounded,
            color: kPrimaryGreen,
            points: data.wristSpeed,
            hitSecond: hitSecond,
            yLabel: (v) => v.toStringAsFixed(0),
            invertY: false,
          )
        else
          const _MissingDataCard(label: '速度', hint: '需完成姿勢分析'),
        // 音頻特徵分析卡片
        if (entry.audioFeatureValues != null && entry.audioFeatureValues!.isNotEmpty) ...[
          const SizedBox(height: 16),
          _AudioFeaturesCard(entry: entry),
        ],
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════
// 單張圖表卡片
// ════════════════════════════════════════════════════════════════

class _ChartCard extends StatefulWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final List<ChartPoint> points;
  final double? hitSecond;
  final String Function(double) yLabel;
  final bool invertY;

  const _ChartCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.points,
    required this.hitSecond,
    required this.yLabel,
    required this.invertY,
  });

  @override
  State<_ChartCard> createState() => _ChartCardState();
}

class _ChartCardState extends State<_ChartCard> {
  int? _touchedIndex;

  // invertY 時的原始最大 Y（用來還原顯示值 → 原始值）
  late final double _rawMaxY = widget.invertY
      ? widget.points.map((e) => e.y).reduce((a, b) => a > b ? a : b)
      : 0;

  // 把圖表座標 y（可能已翻轉）還原成原始值，供 label/tooltip 顯示
  double _toRaw(double displayY) =>
      widget.invertY ? (_rawMaxY - displayY) : displayY;

  late final List<FlSpot> _spots = widget.invertY
      ? widget.points.map((p) => FlSpot(p.x, _rawMaxY - p.y)).toList()
      : widget.points.map((p) => FlSpot(p.x, p.y)).toList();

  double get _minX => widget.points.first.x;
  double get _maxX => widget.points.last.x;
  late final double _minY = _spots.map((s) => s.y).reduce((a, b) => a < b ? a : b);
  late final double _maxY = _spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
  double get _yPad => (_maxY - _minY) * 0.12 + 1;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 標題列
            Row(children: [
              Icon(widget.icon, color: widget.color, size: 18),
              const SizedBox(width: 8),
              Text(widget.title, style: TextStyle(
                color: widget.color,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              )),
              const SizedBox(width: 8),
              Text(widget.subtitle, style: const TextStyle(
                color: Colors.black38,
                fontSize: 11,
              )),
              const Spacer(),
              Text(
                '${widget.points.length} 點',
                style: const TextStyle(color: Colors.black38, fontSize: 11),
              ),
            ]),
            const SizedBox(height: 12),
            // 圖表
            SizedBox(
              height: 180,
              child: LineChart(
                LineChartData(
                  minX: _minX,
                  maxX: _maxX,
                  minY: _minY - _yPad,
                  maxY: _maxY + _yPad,
                  clipData: const FlClipData.all(),
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipColor: (_) => Colors.black87,
                      getTooltipItems: (spots) => spots.map((s) => LineTooltipItem(
                        '${s.x.toStringAsFixed(2)}s\n${widget.yLabel(_toRaw(s.y))}',
                        const TextStyle(color: Colors.white, fontSize: 11),
                      )).toList(),
                    ),
                    touchCallback: (_, response) {
                      setState(() {
                        _touchedIndex = response?.lineBarSpots?.first.spotIndex;
                      });
                    },
                  ),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: true,
                    horizontalInterval: (_maxY - _minY + 1) / 4,
                    getDrawingHorizontalLine: (_) => FlLine(
                      color: Colors.black.withValues(alpha: 0.06),
                      strokeWidth: 1,
                    ),
                    getDrawingVerticalLine: (_) => FlLine(
                      color: Colors.black.withValues(alpha: 0.06),
                      strokeWidth: 1,
                    ),
                  ),
                  borderData: FlBorderData(
                    show: true,
                    border: Border(
                      bottom: BorderSide(color: Colors.black.withValues(alpha: 0.15)),
                      left:   BorderSide(color: Colors.black.withValues(alpha: 0.15)),
                    ),
                  ),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 44,
                        interval: (_maxY - _minY + 1) / 4,
                        getTitlesWidget: (val, meta) => Text(
                          widget.yLabel(_toRaw(val)),
                          style: const TextStyle(fontSize: 9, color: Colors.black45),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 22,
                        interval: (_maxX - _minX) / 4,
                        getTitlesWidget: (val, meta) => Text(
                          '${val.toStringAsFixed(1)}s',
                          style: const TextStyle(fontSize: 9, color: Colors.black45),
                        ),
                      ),
                    ),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  // 擊球時刻標記線
                  extraLinesData: widget.hitSecond != null
                      ? ExtraLinesData(verticalLines: [
                          VerticalLine(
                            x: widget.hitSecond!,
                            color: const Color(0xFFFF6F00),
                            strokeWidth: 2,
                            dashArray: [5, 4],
                            label: VerticalLineLabel(
                              show: true,
                              alignment: Alignment.topRight,
                              labelResolver: (_) => 'Hit',
                              style: const TextStyle(
                                color: Color(0xFFFF6F00),
                                fontSize: 10,
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
                      barWidth: 2,
                      dotData: FlDotData(
                        show: widget.points.length <= 30,
                        getDotPainter: (spot, _, __, i) => FlDotCirclePainter(
                          radius: i == _touchedIndex ? 5 : 3,
                          color: widget.color,
                          strokeWidth: 0,
                        ),
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            widget.color.withValues(alpha: 0.20),
                            widget.color.withValues(alpha: 0.01),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                duration: const Duration(milliseconds: 200),
              ),
            ),
            // 統計列（invertY 時 Min/Max 對調，使語意與圖表視覺一致）
            _StatsRow(points: widget.points, color: widget.color, yLabel: widget.yLabel, invertY: widget.invertY),
          ],
        ),
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  final List<ChartPoint> points;
  final Color color;
  final String Function(double) yLabel;
  final bool invertY;

  const _StatsRow({
    required this.points,
    required this.color,
    required this.yLabel,
    this.invertY = false,
  });

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) return const SizedBox.shrink();
    final ys = points.map((p) => p.y).toList();
    final minV = ys.reduce((a, b) => a < b ? a : b);
    final maxV = ys.reduce((a, b) => a > b ? a : b);
    final avgV = ys.reduce((a, b) => a + b) / ys.length;

    // invertY 時圖表最高點 = 原始最小像素，對調 Min/Max 標籤讓語意與視覺一致
    final topLabel  = invertY ? 'Max(↑)' : 'Max';
    final botLabel  = invertY ? 'Min(↓)' : 'Min';
    final topVal    = invertY ? minV : maxV;
    final botVal    = invertY ? maxV : minV;

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _StatChip(botLabel, yLabel(botVal), color),
          _StatChip(topLabel, yLabel(topVal), color),
          _StatChip('Avg', yLabel(avgV), color),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatChip(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.black38)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════
// 空狀態 / 錯誤狀態
// ════════════════════════════════════════════════════════════════

class _MissingDataCard extends StatelessWidget {
  final String label;
  final String hint;
  const _MissingDataCard({required this.label, required this.hint});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Column(
          children: [
            const Icon(Icons.bar_chart_outlined, color: Colors.black26, size: 36),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.black45)),
            const SizedBox(height: 4),
            Text(hint, style: const TextStyle(fontSize: 12, color: Colors.black26)),
          ],
        ),
      ),
    );
  }
}

class _NoDataView extends StatelessWidget {
  const _NoDataView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bar_chart_outlined, size: 64, color: Colors.black26),
          SizedBox(height: 16),
          Text('尚無圖表資料', style: TextStyle(fontSize: 16, color: Colors.black45, fontWeight: FontWeight.w600)),
          SizedBox(height: 8),
          Text('請先完成音頻分析與姿勢分析', style: TextStyle(fontSize: 13, color: Colors.black38)),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  const _ErrorView({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            const Text('載入失敗', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(message, style: const TextStyle(fontSize: 12, color: Colors.black45), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}


// ════════════════════════════════════════════════════════════════
// 音頻特徵分析卡片（5大特徵水平量規）
// ════════════════════════════════════════════════════════════════

/// 各特徵顯示用的值域範圍 [displayMin, displayMax]
const _kFeatureDisplayRanges = <String, List<double>>{
  'rms_dbfs':          [-45.0, -5.0],
  'spectral_centroid': [1500.0, 7000.0],
  'sharpness_hfxloud': [0.0, 6.0],
  'highband_amp':      [0.0, 60.0],
  'peak_dbfs':         [-30.0, 0.0],
};

const _kFeatureUnits = <String, String>{
  'rms_dbfs':          'dBFS',
  'spectral_centroid': 'Hz',
  'sharpness_hfxloud': '',
  'highband_amp':      '',
  'peak_dbfs':         'dBFS',
};

class _AudioFeaturesCard extends StatelessWidget {
  final RecordingHistoryEntry entry;

  const _AudioFeaturesCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final featureValues = entry.audioFeatureValues!;
    final passes    = entry.audioPasses ?? {};
    final passCount = passes.values.where((v) => v).length;
    final isGood    = passCount >= AudioAnalysisService.goodBadThreshold;
    final goodShot  = entry.goodShot;
    final label     = entry.audioLabel;

    // 品質等級對應色彩
    final Color qualityColor;
    final String qualityText;
    if (goodShot == true) {
      qualityColor = kPrimaryGreen;
      qualityText  = label?.isNotEmpty == true ? label! : '甜蜜點';
    } else {
      qualityColor = const Color(0xFFE05252);
      qualityText  = label?.isNotEmpty == true ? label! : '擊球偏虛';
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 標題列
            Row(
              children: [
                const Icon(Icons.equalizer_rounded, color: Color(0xFF7B1FA2), size: 18),
                const SizedBox(width: 8),
                const Text('音頻特徵分析',
                    style: TextStyle(color: Color(0xFF7B1FA2), fontSize: 15, fontWeight: FontWeight.w700)),
                const Spacer(),
                if (goodShot != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(
                      color: qualityColor.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: qualityColor.withValues(alpha: 0.5)),
                    ),
                    child: Text(
                      qualityText,
                      style: TextStyle(color: qualityColor, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            // 整體通過數進度條
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      for (int i = 0; i < 5; i++) ...[
                        Expanded(
                          child: Container(
                            height: 6,
                            decoration: BoxDecoration(
                              color: i < passCount
                                  ? (isGood ? kPrimaryGreen : const Color(0xFFE05252))
                                  : const Color(0xFFE0E4EA),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                        if (i < 4) const SizedBox(width: 4),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '$passCount/5',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isGood ? kPrimaryGreen : const Color(0xFFE05252),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '$passCount / 5 項特徵符合甜蜜點範圍',
              style: const TextStyle(color: Color(0xFF6F7B86), fontSize: 11),
            ),
            const SizedBox(height: 14),
            // 每個特徵一行
            for (final feat in AudioAnalysisService.featureLabels.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _AudioFeatureGaugeRow(
                  label: feat.value,
                  featureKey: feat.key,
                  value: featureValues[feat.key],
                  passed: passes[feat.key] ?? false,
                  unit: _kFeatureUnits[feat.key] ?? '',
                  displayRange: _kFeatureDisplayRanges[feat.key] ?? [0, 100],
                  threshold: AudioAnalysisService.ruleIntervals[feat.key] ?? [0, 1],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AudioFeatureGaugeRow extends StatelessWidget {
  final String label;
  final String featureKey;
  final double? value;
  final bool passed;
  final String unit;
  final List<double> displayRange;
  final List<double> threshold;

  const _AudioFeatureGaugeRow({
    required this.label,
    required this.featureKey,
    required this.value,
    required this.passed,
    required this.unit,
    required this.displayRange,
    required this.threshold,
  });

  @override
  Widget build(BuildContext context) {
    final dMin = displayRange[0];
    final dMax = displayRange[1];
    final tLow  = threshold[0];
    final tHigh = threshold[1];
    final barColor = passed ? const Color(0xFF4CAF50) : const Color(0xFFF44336);

    // Normalise a value to [0, 1] within the display range
    double norm(double v) => ((v - dMin) / (dMax - dMin)).clamp(0.0, 1.0);

    final tLowN  = norm(tLow);
    final tHighN = norm(tHigh);
    final valN   = value != null ? norm(value!) : null;

    // Format value for display
    String valueText = value != null
        ? '${value!.toStringAsFixed(value!.abs() < 100 ? 1 : 0)}$unit'
        : '—';

    return Row(
      children: [
        SizedBox(
          width: 36,
          child: Text(label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: LayoutBuilder(builder: (context, constraints) {
            final width = constraints.maxWidth;
            return SizedBox(
              height: 16,
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  // 背景軌道
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  // 閾值區間（綠色帶）
                  Positioned(
                    left: tLowN * width,
                    width: (tHighN - tLowN) * width,
                    top: 3,
                    bottom: 3,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xFF4CAF50).withValues(alpha: 0.28),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  // 實際值標記點
                  if (valN != null)
                    Positioned(
                      left: (valN * width - 4).clamp(0.0, width - 8),
                      top: 2,
                      bottom: 2,
                      width: 8,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: barColor,
                          borderRadius: BorderRadius.circular(4),
                          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 2)],
                        ),
                      ),
                    ),
                ],
              ),
            );
          }),
        ),
        const SizedBox(width: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              valueText,
              style: TextStyle(fontSize: 11, color: barColor, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(width: 4),
            Icon(
              passed ? Icons.check_circle_rounded : Icons.cancel_rounded,
              color: barColor,
              size: 14,
            ),
          ],
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════
// 自動提交 posture_only 時的等待卡片
// ════════════════════════════════════════════════════════════════

class _AutoAnalyzingPostureCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: const Padding(
        padding: EdgeInsets.all(20),
        child: Row(
          children: [
            SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF7C3AED))),
            SizedBox(width: 12),
            Text('姿勢分析上傳中，請稍候…', style: TextStyle(fontSize: 13, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// ONNX 錯誤姿勢分析圖表（從後端 posture_only 分析結果讀取）
// ════════════════════════════════════════════════════════════════

class _OnnxPostureCard extends StatefulWidget {
  final String analysisId;
  const _OnnxPostureCard({required this.analysisId});

  @override
  State<_OnnxPostureCard> createState() => _OnnxPostureCardState();
}

class _OnnxPostureCardState extends State<_OnnxPostureCard> {
  OnnxResult? _result;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final status = await AnalysisService.instance.getStatus(widget.analysisId);
      if (mounted) {
        setState(() {
          _result  = status.onnxResult;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error   = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.sports_golf_rounded, color: Color(0xFF7C3AED), size: 20),
              const SizedBox(width: 8),
              const Text('ONNX 姿勢分析',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ]),
            const SizedBox(height: 12),
            if (_loading)
              const Center(child: Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: CircularProgressIndicator(),
              ))
            else if (_error != null)
              Center(child: Text('載入失敗: $_error',
                  style: const TextStyle(color: Colors.red, fontSize: 12)))
            else if (_result == null)
              const Center(child: Text('尚無 ONNX 結果',
                  style: TextStyle(color: Colors.grey)))
            else
              ..._buildBars(_result!),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildBars(OnnxResult result) {
    final scores = result.scores;
    if (scores.isEmpty) return [const Text('無分數資料')];

    final sorted = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return sorted.map((e) {
      final label     = SwingPosture.zhName(e.key);
      final score     = e.value.clamp(0.0, 1.0);
      final isOfficial = result.officialErrors.contains(e.key);
      final isSuspect  = result.suspectErrors.contains(e.key);
      final color = isOfficial
          ? const Color(0xFFEF4444)
          : isSuspect
              ? const Color(0xFFF97316)
              : const Color(0xFF22C55E);

      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(label, style: const TextStyle(fontSize: 13)),
                Text('${(score * 100).toStringAsFixed(0)}%',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: color)),
              ],
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: score,
                minHeight: 8,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ],
        ),
      );
    }).toList();
  }
}

// ════════════════════════════════════════════════════════════════
// 揮桿 8 階段關鍵禎時間軸（文字版，讀取 phases.json）
// ════════════════════════════════════════════════════════════════

class _SwingPhasesCard extends StatefulWidget {
  final RecordingHistoryEntry entry;
  const _SwingPhasesCard({required this.entry});

  @override
  State<_SwingPhasesCard> createState() => _SwingPhasesCardState();
}

class _SwingPhasesCardState extends State<_SwingPhasesCard> {
  static const _phaseOrder = [
    ('address',       '①準備'),
    ('takeaway',      '②起桿'),
    ('backswing',     '③上桿'),
    ('top',           '④頂點'),
    ('downswing',     '⑤下桿'),
    ('impact',        '⑥擊球'),
    ('followthrough', '⑦送桿'),
    ('finish',        '⑧收桿'),
  ];

  Map<String, double>? _phases;
  bool _generating = false;

  String get _sessionDir => p.dirname(widget.entry.filePath);
  bool get _canGenerate  => widget.entry.videoType == VideoType.localClip;

  @override
  void initState() {
    super.initState();
    _loadPhases();
  }

  Future<void> _loadPhases() async {
    final f = File(p.join(_sessionDir, 'phases.json'));
    if (!f.existsSync()) return;
    try {
      final raw = jsonDecode(await f.readAsString());
      if (raw is Map && mounted) {
        setState(() {
          _phases = raw.map((k, v) => MapEntry(k as String, (v as num).toDouble()));
        });
      }
    } catch (e) {
      debugPrint('[SwingPhasesCard] phases.json 讀取失敗: $e');
    }
  }

  Future<void> _generate() async {
    if (_generating) return;
    setState(() => _generating = true);
    try {
      final csvPath = p.join(_sessionDir, 'pose_landmarks.csv');
      if (!File(csvPath).existsSync()) return;

      final hits = await SwingImpactDetector.detect(csvPath: csvPath);
      if (hits.isEmpty) return;

      await ClipPipelineService.savePhasesJson(
        sessionDir: _sessionDir,
        hit: hits.first,
        clipActualStartSec: 0.0,
      );
      await _loadPhases();
    } catch (e) {
      debugPrint('[SwingPhasesCard] 生成失敗: $e');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_phases == null && !_canGenerate) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 6, offset: Offset(0, 2))],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.sports_golf_rounded, color: kPrimaryGreen, size: 18),
              const SizedBox(width: 6),
              const Text('揮桿階段', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              const Spacer(),
              if (_canGenerate)
                _generating
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: kPrimaryGreen),
                      )
                    : GestureDetector(
                        onTap: _generate,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _phases != null ? Icons.refresh_rounded : Icons.auto_awesome_rounded,
                              size: 15,
                              color: kPrimaryGreen,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              _phases != null ? '重新生成' : '生成階段',
                              style: TextStyle(fontSize: 11, color: kPrimaryGreen, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
            ],
          ),
          const SizedBox(height: 10),
          _phases != null ? _buildTimeline() : _buildPlaceholder(),
        ],
      ),
    );
  }

  Widget _buildTimeline() {
    final phases = _phases!;
    // 分兩列 4+4
    Widget row(int start) => Row(
      children: List.generate(4, (i) {
        final (key, label) = _phaseOrder[start + i];
        final sec = phases[key];
        return Expanded(
          child: _PhaseChip(label: label, sec: sec),
        );
      }),
    );

    return Column(
      children: [
        row(0),
        const SizedBox(height: 6),
        row(4),
      ],
    );
  }

  Widget _buildPlaceholder() {
    return Row(
      children: _phaseOrder.take(4).map((e) => Expanded(
        child: _PhaseChip(label: e.$2, sec: null),
      )).toList(),
    );
  }
}

class _PhaseChip extends StatelessWidget {
  final String label;
  final double? sec;
  const _PhaseChip({required this.label, required this.sec});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        children: [
          Container(
            height: 42,
            decoration: BoxDecoration(
              color: sec != null ? const Color(0xFFF0FAF4) : const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: sec != null ? kPrimaryGreen.withValues(alpha: 0.35) : const Color(0xFFDDDDDD),
              ),
            ),
            child: Center(
              child: sec != null
                  ? Text(
                      '${sec!.toStringAsFixed(1)}s',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: kPrimaryGreen,
                      ),
                    )
                  : const Icon(Icons.hourglass_empty_rounded, color: Color(0xFFCCCCCC), size: 16),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: const TextStyle(fontSize: 9, color: Color(0xFF777777), fontWeight: FontWeight.w500),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// 下載影片選項資料類
// ════════════════════════════════════════════════════════════════

class _VideoOption {
  final String file;
  final String label;
  final String desc;
  final IconData icon;

  const _VideoOption({
    required this.file,
    required this.label,
    required this.desc,
    required this.icon,
  });
}

// ════════════════════════════════════════════════════════════════
// 下載選擇 Bottom Sheet
// ════════════════════════════════════════════════════════════════

class _DownloadPicker extends StatelessWidget {
  final List<_VideoOption> options;
  const _DownloadPicker({required this.options});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── 標題列 ──────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 16, 8),
            child: Row(
              children: [
                const Icon(Icons.download_rounded, color: kPrimaryGreen, size: 22),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    '選擇下載版本',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // ── 選項列表 ──────────────────────────────────────────
          ...options.map((opt) => _OptionTile(
            option: opt,
            onTap: () => Navigator.pop(context, opt),
          )),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  final _VideoOption option;
  final VoidCallback onTap;
  const _OptionTile({required this.option, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            // 圖示
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: kPrimaryGreen.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(option.icon, color: kPrimaryGreen, size: 22),
            ),
            const SizedBox(width: 14),
            // 文字
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    option.label,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    option.desc,
                    style: const TextStyle(fontSize: 12, color: Color(0xFF888888)),
                  ),
                ],
              ),
            ),
            // 箭頭
            const Icon(Icons.chevron_right_rounded, color: Color(0xFFCCCCCC)),
          ],
        ),
      ),
    );
  }
}
