import 'dart:io';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../models/export_spec.dart';
import '../models/recording_history_entry.dart';
import '../models/p_system_metrics.dart';
import '../providers/plan_provider.dart';
import '../services/plan_service.dart';
import '../models/swing_posture.dart';
import '../services/analysis_service.dart';
import '../services/audio_analysis_service.dart';
import '../services/chart_data_service.dart';
import '../services/biomechanics_service.dart';
import '../services/recording_history_storage.dart';
import '../services/overlay_burn_service.dart';
import '../services/skeleton_csv_locator.dart';
import '../services/video_export_service.dart';
import '../theme/app_theme.dart';
import '../widgets/custom_export_sheet.dart';
import 'package:golf_score_app/l10n/app_localizations.dart';

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


  /// 自訂匯出：勾選疊加元素 → 單 pass 合成 → 下載。
  /// 浮水印由方案決定（免費強制，UI 不可關）。
  Future<void> _customExportFlow() async {
    final l10n = AppLocalizations.of(context);
    final sessionDir = p.dirname(widget.entry.filePath);
    if (!OverlayBurnService.canCompose(sessionDir)) {
      _showSnack(l10n.recDetailNoVideoFound, isError: true);
      return;
    }
    final hasSkeleton   = resolveSkeletonCsv(sessionDir) != null;
    final hasTrajectory = File(p.join(sessionDir, 'trajectory.json')).existsSync();
    final isFree        = context.read<PlanProvider>().plan == UserPlan.free;

    final spec = await showModalBottomSheet<ExportSpec>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => CustomExportSheet(
        hasSkeleton: hasSkeleton,
        hasTrajectory: hasTrajectory,
        hasImpact: widget.entry.hitSecond != null,
        hasShotQuality: widget.entry.goodShot != null,
        isFree: isFree,
      ),
    );
    if (spec == null || !mounted) return;

    setState(() => _isDownloading = true);
    try {
      final exportLabel = l10n.exportCustomTitle;
      _showSnack(l10n.recDetailBurning(exportLabel));
      final burned = await OverlayBurnService.composeForExport(
        sessionDir,
        spec,
        impactSec: widget.entry.hitSecond,
        goodShot: widget.entry.goodShot,
        passCount: widget.entry.audioPassCount ?? 0,
      );
      if (burned == null) {
        if (mounted) _showSnack(l10n.recDetailBurnFailed, isError: true);
        return;
      }
      final displayName =
          '${_title.replaceAll(RegExp(r'[^\w一-龥]'), '_')}_export';
      final result = await VideoExportService.download(burned, displayName: displayName);
      if (!mounted) return;
      switch (result.status) {
        case ExportStatus.savedToDownloads:
          _showSnack(l10n.recDetailSavedToDownloads(exportLabel));
        case ExportStatus.savedToPhotos:
          _showSnack(l10n.recDetailSavedToPhotos(exportLabel));
        case ExportStatus.sharedViaSheet:
          _showSnack(l10n.recDetailSharedViaSheet);
        case ExportStatus.failed:
          _showSnack(l10n.recDetailDownloadFailed(result.detail ?? ''), isError: true);
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
      backgroundColor: context.bgPage,
      appBar: AppBar(
        backgroundColor: kBrandPrimary,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(_title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        actions: [
          // ── 匯出（勾選疊加元素 → 合成下載）─────────────────
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
              tooltip: AppLocalizations.of(context).exportCustomTitle,
              onPressed: _customExportFlow,
            ),
        ],
      ),
      body: SafeArea(top: false, child: Column(
        children: [
          _MetaHeader(entry: widget.entry),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: kBrandPrimary))
                : _error != null
                    ? _ErrorView(message: _error!)
                    : _data == null || _data!.isEmpty
                        ? const _NoDataView()
                        : _ChartsBody(data: _data!, hitSecond: widget.entry.hitSecond, entry: widget.entry, postureAnalysisId: _postureAnalysisId, isAutoAnalyzing: _isAutoAnalyzing),
          ),
        ],
      )),
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
      color: kBrandPrimary,
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
    final l10n = AppLocalizations.of(context);
    const pad = EdgeInsets.fromLTRB(16, 16, 16, 32);
    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          TabBar(
            isScrollable: true,
            labelColor: kBrandPrimary,
            unselectedLabelColor: context.textHint,
            indicatorColor: kBrandPrimary,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: l10n.chartTabStage),
              Tab(text: l10n.chartTabCharts),
              Tab(text: l10n.chartTabAudio),
              Tab(text: l10n.chartTabPosture),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                // ① 揮桿階段：P1-P10 各階段量化數值
                ListView(padding: pad, children: [
                  _PSystemValuesCard(entry: entry),
                ]),
                // ② 圖表：聲音峰值 / 手腕 Y / 速度 三線圖
                ListView(padding: pad, children: [
                  if (data.audioRms.isNotEmpty)
                    _ChartCard(
                      title: l10n.recDetailAudioPeak,
                      subtitle: l10n.recDetailAudioPeakSubtitle,
                      icon: Icons.graphic_eq_rounded,
                      color: const Color(0xFFE53935),
                      points: data.audioRms,
                      hitSecond: hitSecond,
                      yLabel: (v) => '${v.toStringAsFixed(0)}dB',
                      invertY: false,
                    )
                  else
                    _MissingDataCard(
                      label: l10n.recDetailAudioPeak,
                      hint: l10n.recDetailAudioPeakMissing,
                    ),
                  const SizedBox(height: 16),
                  if (data.wristY.isNotEmpty)
                    _ChartCard(
                      title: l10n.recDetailWristY,
                      subtitle: l10n.recDetailWristYSubtitle,
                      icon: Icons.sports_golf_rounded,
                      color: const Color(0xFF1565C0),
                      points: data.wristY,
                      hitSecond: hitSecond,
                      yLabel: (v) => '${v.toStringAsFixed(0)}px',
                      invertY: true,
                    )
                  else
                    _MissingDataCard(
                      label: l10n.recDetailWristY,
                      hint: l10n.recDetailPoseMissing,
                    ),
                  const SizedBox(height: 16),
                  if (data.wristSpeed.isNotEmpty)
                    _ChartCard(
                      title: 'Speed',
                      subtitle: l10n.recDetailSpeedSubtitle,
                      icon: Icons.speed_rounded,
                      color: kBrandPrimary,
                      points: data.wristSpeed,
                      hitSecond: hitSecond,
                      yLabel: (v) => v.toStringAsFixed(0),
                      invertY: false,
                    )
                  else
                    _MissingDataCard(
                      label: l10n.recDetailSpeedMissing,
                      hint: l10n.recDetailPoseMissing,
                    ),
                ]),
                // ③ 音頻：音頻特徵 5 項
                ListView(padding: pad, children: [
                  if (entry.audioFeatureValues != null &&
                      entry.audioFeatureValues!.isNotEmpty)
                    _AudioFeaturesCard(entry: entry)
                  else
                    _MissingDataCard(
                      label: l10n.recDetailAudioFeaturesTitle,
                      hint: l10n.recDetailAudioPeakMissing,
                    ),
                ]),
                // ④ 姿勢：ONNX 分析
                ListView(padding: pad, children: [
                  if (postureAnalysisId != null)
                    _OnnxPostureCard(analysisId: postureAnalysisId!)
                  else if (isAutoAnalyzing)
                    _AutoAnalyzingPostureCard()
                  else
                    _MissingDataCard(
                      label: l10n.postureTitle,
                      hint: l10n.postureNoData,
                    ),
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
// 揮桿階段（P1-P10）各階段量化數值卡（讀 angles.json）
// ════════════════════════════════════════════════════════════════

class _PSystemValuesCard extends StatefulWidget {
  final RecordingHistoryEntry entry;
  const _PSystemValuesCard({required this.entry});
  @override
  State<_PSystemValuesCard> createState() => _PSystemValuesCardState();
}

class _PSystemValuesCardState extends State<_PSystemValuesCard> {
  PSystemMetrics? _ps;
  bool _loading = true;

  static const _goodColor = kGoodColor;
  static const _warnColor = Color(0xFFFFB74D);
  static const _badColor = Color(0xFFE05252);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ps = await PSystemMetrics.load(p.dirname(widget.entry.filePath));
    if (mounted) setState(() { _ps = ps; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (_loading) {
      return const Card(
        elevation: 2,
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Center(child: CircularProgressIndicator(color: kBrandPrimary)),
        ),
      );
    }
    final ps = _ps;
    if (ps == null) {
      return Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(children: [
            Icon(Icons.timeline_rounded, color: context.textHint, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Text(l10n.pSystemNoData,
                  style: TextStyle(color: context.textSecondary, fontSize: 13)),
            ),
          ]),
        ),
      );
    }
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.timeline_rounded, color: kBrandPrimary, size: 18),
              const SizedBox(width: 8),
              Text(l10n.pSystemTitle,
                  style: const TextStyle(
                      color: kBrandPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(width: 8),
              if (ps.overallScore != null)
                Text('${ps.overallScore!.round()}',
                    style: TextStyle(
                        color: _scoreColor(ps.overallScore),
                        fontSize: 15,
                        fontWeight: FontWeight.w800)),
              const Spacer(),
              if (ps.viewpoint != SwingViewpoint.faceOn)
                Flexible(
                  child: Text(l10n.pSystemViewpointWarn,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: TextStyle(color: context.textHint, fontSize: 10)),
                ),
            ]),
            const SizedBox(height: 6),
            for (final key in PSystemMetrics.order) _pTile(context, l10n, ps, key),
          ],
        ),
      ),
    );
  }

  Widget _pTile(BuildContext context, AppLocalizations l10n, PSystemMetrics ps,
      String key) {
    final metrics = ps.perP[key] ?? const <BiomechMetric>[];
    final score = _pScore(metrics);
    final color = _scoreColor(score);
    final sec = ps.pSec[key];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            SizedBox(
              width: 34,
              child: Text(key.toUpperCase(),
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w800, color: color)),
            ),
            Text(_pName(l10n, key),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            if (sec != null) ...[
              const SizedBox(width: 6),
              Text('${sec.toStringAsFixed(1)}s',
                  style: TextStyle(fontSize: 10, color: context.textHint)),
            ],
            const Spacer(),
            if (score != null)
              Text('${score.round()}',
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700, color: color)),
          ]),
          if (metrics.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 34, top: 3),
              child: Wrap(spacing: 10, runSpacing: 4, children: [
                for (final m in metrics) _metricChip(l10n, m),
              ]),
            ),
        ],
      ),
    );
  }

  Widget _metricChip(AppLocalizations l10n, BiomechMetric m) {
    return Text(
      '${_metricName(l10n, m.key)} ${_fmtVal(m)}${m.beta ? " ·beta" : ""}',
      style: TextStyle(fontSize: 11, color: _gradeColor(m.grade)),
    );
  }

  double? _pScore(List<BiomechMetric> metrics) {
    final v = <double>[];
    for (final m in metrics) {
      switch (m.grade) {
        case BiomechGrade.good: v.add(100); break;
        case BiomechGrade.warn: v.add(60); break;
        case BiomechGrade.bad: v.add(20); break;
        case BiomechGrade.unknown: break;
      }
    }
    return v.isEmpty ? null : v.reduce((a, b) => a + b) / v.length;
  }

  Color _scoreColor(double? s) {
    if (s == null) return Colors.grey;
    if (s >= 80) return _goodColor;
    if (s >= 50) return _warnColor;
    return _badColor;
  }

  Color _gradeColor(BiomechGrade g) {
    switch (g) {
      case BiomechGrade.good: return _goodColor;
      case BiomechGrade.warn: return _warnColor;
      case BiomechGrade.bad: return _badColor;
      case BiomechGrade.unknown: return Colors.grey;
    }
  }

  String _fmtVal(BiomechMetric m) {
    final v = m.value;
    if (v == null) return '--';
    if (m.unit == 'deg') return '${v.toStringAsFixed(0)}°';
    if (m.unit == 'norm') return v.toStringAsFixed(3);
    return v.toStringAsFixed(2);
  }

  String _pName(AppLocalizations l, String key) {
    switch (key) {
      case 'p1': return l.pLabelP1;
      case 'p2': return l.pLabelP2;
      case 'p3': return l.pLabelP3;
      case 'p4': return l.pLabelP4;
      case 'p5': return l.pLabelP5;
      case 'p6': return l.pLabelP6;
      case 'p7': return l.pLabelP7;
      case 'p8': return l.pLabelP8;
      case 'p9': return l.pLabelP9;
      case 'p10': return l.pLabelP10;
      default: return key;
    }
  }

  String _metricName(AppLocalizations l, String key) {
    switch (key) {
      case 'spine_tilt': return l.metricSpineTilt;
      case 'head_move': return l.metricHeadMove;
      case 'x_factor': return l.metricXFactor;
      case 'weight_shift': return l.metricWeightShift;
      default: return key;
    }
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
              Text(widget.subtitle, style: TextStyle(
                color: context.textHint,
                fontSize: 11,
              )),
              const Spacer(),
              Text(
                AppLocalizations.of(context).recDetailPointCount(widget.points.length),
                style: TextStyle(color: context.textHint, fontSize: 11),
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
                      color: context.borderColor.withValues(alpha: 0.45),
                      strokeWidth: 1,
                    ),
                    getDrawingVerticalLine: (_) => FlLine(
                      color: context.borderColor.withValues(alpha: 0.45),
                      strokeWidth: 1,
                    ),
                  ),
                  borderData: FlBorderData(
                    show: true,
                    border: Border(
                      bottom: BorderSide(color: context.borderColor),
                      left:   BorderSide(color: context.borderColor),
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
                          style: TextStyle(fontSize: 9, color: context.textSecondary),
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
                          style: TextStyle(fontSize: 9, color: context.textSecondary),
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
        Text(label, style: TextStyle(fontSize: 10, color: context.textHint)),
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
            Icon(Icons.bar_chart_outlined, color: context.textHint, size: 36),
            const SizedBox(height: 8),
            Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: context.textSecondary)),
            const SizedBox(height: 4),
            Text(hint, style: TextStyle(fontSize: 12, color: context.textHint)),
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
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bar_chart_outlined, size: 64, color: context.textHint),
          const SizedBox(height: 16),
          Text(AppLocalizations.of(context).recDetailNoChartData, style: TextStyle(fontSize: 16, color: context.textSecondary, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(AppLocalizations.of(context).recDetailNoChartHint, style: TextStyle(fontSize: 13, color: context.textHint)),
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
            Text(AppLocalizations.of(context).recDetailLoadFailed, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(message, style: TextStyle(fontSize: 12, color: context.textSecondary), textAlign: TextAlign.center),
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
    final l10n = AppLocalizations.of(context);
    if (goodShot == true) {
      qualityColor = kBrandPrimary;
      qualityText  = label?.isNotEmpty == true ? label! : l10n.recDetailSweetSpot;
    } else {
      qualityColor = const Color(0xFFE05252);
      qualityText  = label?.isNotEmpty == true ? label! : l10n.recDetailOffCenter;
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
                Text(l10n.recDetailAudioFeaturesTitle,
                    style: const TextStyle(color: Color(0xFF7B1FA2), fontSize: 15, fontWeight: FontWeight.w700)),
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
                                  ? (isGood ? kBrandPrimary : const Color(0xFFE05252))
                                  : context.bgInset,
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
                    color: isGood ? kBrandPrimary : const Color(0xFFE05252),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              l10n.recDetailFeaturePassCount(passCount),
              style: TextStyle(color: context.textSecondary, fontSize: 11),
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
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: context.textPrimary)),
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
                        color: context.bgInset,
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
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF7C3AED))),
            const SizedBox(width: 12),
            Text(AppLocalizations.of(context).recDetailAutoAnalyzing, style: const TextStyle(fontSize: 13, color: Colors.grey)),
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
              Text(AppLocalizations.of(context).recDetailOnnxTitle,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ]),
            const SizedBox(height: 12),
            if (_loading)
              const Center(child: Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: CircularProgressIndicator(),
              ))
            else if (_error != null)
              Center(child: Text(AppLocalizations.of(context).recDetailOnnxLoadFailed(_error!),
                  style: const TextStyle(color: Colors.red, fontSize: 12)))
            else if (_result == null)
              Center(child: Text(AppLocalizations.of(context).recDetailOnnxNoResult,
                  style: const TextStyle(color: Colors.grey)))
            else
              ..._buildBars(_result!, context),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildBars(OnnxResult result, BuildContext context) {
    final scores = result.scores;
    if (scores.isEmpty) return [Text(AppLocalizations.of(context).recDetailOnnxNoScores)];

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
                Expanded(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13)),
                ),
                const SizedBox(width: 8),
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
                backgroundColor: context.bgInset,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ],
        ),
      );
    }).toList();
  }
}
