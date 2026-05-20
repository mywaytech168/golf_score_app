import 'dart:io';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../models/recording_history_entry.dart';
import '../services/chart_data_service.dart';
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

  @override
  void initState() {
    super.initState();
    _loadData();
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
                        : _ChartsBody(data: _data!, hitSecond: widget.entry.hitSecond),
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

    final label = entry.audioLabel;
    final crispness = entry.audioCrispness;

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
                  if (label != null) ...[
                    const SizedBox(width: 10),
                    _LabelChip(label: label),
                  ],
                ]),
              ],
            ),
          ),
          if (crispness != null)
            Column(
              children: [
                Text(
                  crispness.toStringAsFixed(0),
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const Text('清脆度', style: TextStyle(color: Colors.white70, fontSize: 11)),
              ],
            ),
        ],
      ),
    );
  }
}

class _LabelChip extends StatelessWidget {
  final String label;
  const _LabelChip({required this.label});

  @override
  Widget build(BuildContext context) {
    Color bg;
    switch (label.toLowerCase()) {
      case 'pro':    bg = const Color(0xFFFFD700); break;
      case 'sweet':  bg = const Color(0xFF4CAF50); break;
      default:       bg = Colors.white24;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white)),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// 圖表主體
// ════════════════════════════════════════════════════════════════

class _ChartsBody extends StatelessWidget {
  final ChartDataSet data;
  final double? hitSecond;

  const _ChartsBody({required this.data, this.hitSecond});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
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
