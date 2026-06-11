import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:video_player/video_player.dart';

import '../recording/trajectory_painter.dart';
import '../services/ball_tracker.dart';
import '../services/ball_trajectory_service.dart';
import '../services/detection_config.dart';
import '../services/golfer_mask.dart';

/// 球軌跡調參頁（排查用）。
///
/// 流程：對 clip 抽一次 blob 快取 → 滑桿改 [TrackerConfig] / 球員 margin 即時重跑
/// `BallTracker.track()` → 重建 [TrajectoryTrack] 疊在影片上（重用 [TrajectoryPainter]，
/// 不烙進影片）。diffThresh / area 改變屬「重抽」需按按鈕重跑原生偵測。
class BallTuningPage extends StatefulWidget {
  final String clipPath;
  final double? hitSec;
  const BallTuningPage({super.key, required this.clipPath, this.hitSec});

  @override
  State<BallTuningPage> createState() => _BallTuningPageState();
}

class _BallTuningPageState extends State<BallTuningPage> {
  VideoPlayerController? _ctrl;
  FrameExtractionResult? _ext;          // Phase A 快取
  ({int cx, int cy, int frame})? _seed; // p0-SAHI 種子
  List<int>? _golferBox;
  TrajectoryTrack? _track;

  // 可調參數（即時）
  TrackerConfig _cfg = const TrackerConfig(roiHalfBasePx: 200);
  double _margin = 0.15;
  // 可調參數（重抽）
  int _diffThresh = 18;

  bool _busy = true;
  String _hud = '初始化中…';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final ctrl = VideoPlayerController.file(File(widget.clipPath));
    _ctrl = ctrl;
    await ctrl.initialize();
    if (!mounted) return;
    ctrl.setLooping(true);
    ctrl.addListener(_onTick);
    await _reextract();           // 抽 blob + seed + golfer + 首次 track
    if (mounted) {
      setState(() => _busy = false);
      ctrl.play();
    }
  }

  void _onTick() {
    if (mounted) setState(() {}); // 推進疊圖 positionSec
  }

  /// 重抽：原生偵測(diffThresh/area) + p0-SAHI 種子 + 球員框，然後 track。
  Future<void> _reextract() async {
    if (!mounted) return;
    setState(() { _busy = true; _hud = '偵測中…'; });
    _ext = await BallTrajectoryService.extractBlobsWithConfig(
      inputPath: widget.clipPath,
      config: DetectionConfig(diffThresh: _diffThresh, areaLo: 6, areaHi: 150, circMin: 0.45),
      roiSize: 400,
    );
    _seed = await BallTrajectoryService.findBallP0(inputPath: widget.clipPath, hitSec: widget.hitSec);
    await _recomputeGolfer();
    if (!mounted) return;   // 非同步抽取期間頁面可能已關閉
    _rerun();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _recomputeGolfer() async {
    final ext = _ext;
    if (ext == null || widget.hitSec == null) { _golferBox = null; return; }
    _golferBox = await GolferMask.codedBoxFromPoseCsv(
      csvPath:  p.join(p.dirname(widget.clipPath), 'pose_landmarks.csv'),
      hitSec:   widget.hitSec!,
      codedW:   ext.width,
      codedH:   ext.height,
      rotation: ext.rotation,
      margin:   _margin,
    );
  }

  /// 即時重跑 track（純 Dart，讀快取 blob）。
  void _rerun() {
    if (!mounted) return;
    final ext = _ext;
    if (ext == null) { setState(() => _hud = 'blob 抽取失敗'); return; }
    final pts = BallTracker().track(
      frames:   ext.frames,
      fps:      ext.fps,
      videoW:   ext.width,
      videoH:   ext.height,
      rotation: ext.rotation,
      hitSec:   widget.hitSec,
      golferBox: _golferBox,
      seedP0X:     _seed?.cx,
      seedP0Y:     _seed?.cy,
      seedP0Frame: _seed?.frame,
      config:   _cfg,
    );
    final track = TrajectoryTrack(
      codedW: ext.width, codedH: ext.height, rotation: ext.rotation,
      points: [for (final t in pts) TrajectoryPoint(x: t.x.toDouble(), y: t.y.toDouble(), ptsUs: t.ptsUs)],
    );
    setState(() {
      _track = track;
      _hud = '軌跡點 ${pts.length}　seed=${_seed == null ? "無(幀差)" : "(${_seed!.cx},${_seed!.cy})"}'
          '　golfer=${_golferBox == null ? "無" : "有"}';
    });
  }

  @override
  void dispose() {
    _ctrl?.removeListener(_onTick);
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _ctrl;
    final posSec = (ctrl != null && ctrl.value.isInitialized)
        ? ctrl.value.position.inMilliseconds / 1000.0 : 0.0;
    return Scaffold(
      backgroundColor: const Color(0xFF101418),
      appBar: AppBar(title: const Text('球軌跡調參'), backgroundColor: const Color(0xFF101418)),
      body: Column(children: [
        // ── 影片 + 軌跡疊圖 ──
        AspectRatio(
          aspectRatio: 9 / 16,
          child: Stack(fit: StackFit.expand, children: [
            if (ctrl != null && ctrl.value.isInitialized) VideoPlayer(ctrl)
            else const Center(child: CircularProgressIndicator()),
            if (_track != null)
              CustomPaint(painter: TrajectoryPainter(track: _track!, positionSec: posSec)),
          ]),
        ),
        // ── HUD ──
        Container(
          width: double.infinity,
          color: const Color(0xFF1A2026),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(_busy ? '⏳ $_hud' : _hud,
              style: const TextStyle(color: Color(0xFF8FE3A0), fontSize: 13)),
        ),
        // ── 滑桿 ──
        Expanded(
          child: ListView(padding: const EdgeInsets.all(12), children: [
            _section('即時（拉了立刻重畫）'),
            _slider('品質閘門 殘差上限', _cfg.trackMaxResidualPx, 0, 200,
                (v) => _setCfg(trackMaxResidualPx: v)),
            _slider('P1 最遠距離', _cfg.p1MaxDistPx, 100, 600,
                (v) => _setCfg(p1MaxDistPx: v)),
            _slider('ROI 半徑', _cfg.roiHalfBasePx ?? 200, 80, 400,
                (v) => _setCfg(roiHalfBasePx: v)),
            _slider('ROI miss 大擴張×', _cfg.roiMissScaleLarge, 1, 5,
                (v) => _setCfg(roiMissScaleLarge: v)),
            _slider('ROI 半徑上限', _cfg.roiHalfMaxAbs, 150, 500,
                (v) => _setCfg(roiHalfMaxAbs: v)),
            _slider('擊球後 step 上限', _cfg.stepAbsHardMaxPostImpact, 150, 600,
                (v) => _setCfg(stepAbsHardMaxPostImpact: v)),
            _slider('擊球後 pred 上限', _cfg.predDistHardMaxPostImpact, 200, 700,
                (v) => _setCfg(predDistHardMaxPostImpact: v)),
            _slider('擊球後 miss 容忍', _cfg.noCandPatiencePostImpact.toDouble(), 3, 40,
                (v) => _setCfg(noCandPatiencePostImpact: v.round())),
            _slider('球員遮罩 margin', _margin, 0, 0.5, null,
                onEnd: (v) async { _margin = v; await _recomputeGolfer(); _rerun(); }),
            const Divider(color: Colors.white24, height: 28),
            _section('重抽（改完按下方按鈕）'),
            _slider('diffThresh 幀差門檻', _diffThresh.toDouble(), 5, 40, null,
                onEnd: (v) => setState(() => _diffThresh = v.round())),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy ? null : _reextract,
              icon: const Icon(Icons.refresh),
              label: const Text('重新偵測（套用 diffThresh）'),
            ),
            const SizedBox(height: 24),
          ]),
        ),
      ]),
    );
  }

  void _setCfg({
    double? trackMaxResidualPx, double? p1MaxDistPx, double? roiHalfBasePx,
    double? roiMissScaleLarge, double? roiHalfMaxAbs,
    double? stepAbsHardMaxPostImpact, double? predDistHardMaxPostImpact,
    int? noCandPatiencePostImpact,
  }) {
    _cfg = TrackerConfig(
      roiHalfBasePx:           roiHalfBasePx ?? _cfg.roiHalfBasePx,
      roiMissScaleMid:         _cfg.roiMissScaleMid,
      roiMissScaleLarge:       roiMissScaleLarge ?? _cfg.roiMissScaleLarge,
      roiHalfMaxAbs:           roiHalfMaxAbs ?? _cfg.roiHalfMaxAbs,
      p1MaxDistPx:             p1MaxDistPx ?? _cfg.p1MaxDistPx,
      noCandPatiencePostImpact: noCandPatiencePostImpact ?? _cfg.noCandPatiencePostImpact,
      stepAbsHardMaxPostImpact: stepAbsHardMaxPostImpact ?? _cfg.stepAbsHardMaxPostImpact,
      predDistHardMaxPostImpact: predDistHardMaxPostImpact ?? _cfg.predDistHardMaxPostImpact,
      trackMaxResidualPx:      trackMaxResidualPx ?? _cfg.trackMaxResidualPx,
    );
    _rerun();
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(t, style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w700)),
      );

  Widget _slider(String label, double value, double min, double max,
      void Function(double)? onChanged, {void Function(double)? onEnd}) {
    return Row(children: [
      SizedBox(width: 130, child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12))),
      Expanded(
        child: Slider(
          value: value.clamp(min, max),
          min: min, max: max,
          label: value.toStringAsFixed(value < 5 ? 2 : 0),
          divisions: 100,
          onChanged: onChanged ?? (v) => setState(() {}),
          onChangeEnd: onEnd,
        ),
      ),
      SizedBox(width: 44, child: Text(value.toStringAsFixed(value < 5 ? 2 : 0),
          style: const TextStyle(color: Color(0xFF8FE3A0), fontSize: 12), textAlign: TextAlign.right)),
    ]);
  }
}
