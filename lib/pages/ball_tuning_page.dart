import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:video_player/video_player.dart';

import '../recording/trajectory_painter.dart';
import '../services/ball_tracker.dart';
import '../services/ball_trajectory_service.dart';
import '../services/detection_config.dart';
import '../services/golfer_mask.dart';
import '../theme/app_theme.dart';
import 'package:golf_score_app/l10n/app_localizations.dart';

enum _HudState { init, detecting, blobFailed, track }

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
  _HudState _hudState = _HudState.init;
  // Track result data for the track HUD line (technical debug values, not localized)
  String _hudTrackRaw = '';

  // ── ROI 視覺化 + 手勢 ──────────────────────────────────────
  bool _showRoiOverlay = true;
  double? _previewRoiHalf;        // 拖曳中暫存（只重畫疊圖，放手才重跑 track）
  double _gestureStartRoi = 200;  // pinch 基準
  bool _roiEdgeDrag = false;      // 單指拖曳邊緣模式
  Size _previewSize = Size.zero;  // 預覽 widget 尺寸（LayoutBuilder 回填）

  /// 目前生效的 ROI 半徑（拖曳中以暫存值優先）
  double get _roiHalf => _previewRoiHalf ?? _cfg.roiHalfBasePx ?? 200;

  /// ROI 圓心（coded 空間）：有 YOLO seed 用 seed，否則用 BallTracker
  /// 的固定比例中心（FIXED_ROI_CENTER=(1149,406) in 1920×1080）。
  Offset? _roiCenterCoded() {
    final ext = _ext;
    if (ext == null) return null;
    final seed = _seed;
    if (seed != null) return Offset(seed.cx.toDouble(), seed.cy.toDouble());
    return Offset(ext.width * 1149.0 / 1920, ext.height * 406.0 / 1080);
  }

  @override
  void initState() {
    super.initState();
    // _hud is set to a localized string in build; placeholder until first frame
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
    setState(() { _busy = true; _hudState = _HudState.detecting; });
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
    if (ext == null) { setState(() => _hudState = _HudState.blobFailed); return; }
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
      _hudState = _HudState.track;
      // Technical debug values intentionally kept as-is (not localized)
      _hudTrackRaw = '軌跡點 ${pts.length}　seed=${_seed == null ? "無(幀差)" : "(${_seed!.cx},${_seed!.cy})"}'
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
    final l10n = AppLocalizations.of(context);
    final ctrl = _ctrl;
    final posSec = (ctrl != null && ctrl.value.isInitialized)
        ? ctrl.value.position.inMilliseconds / 1000.0 : 0.0;
    final hudText = switch (_hudState) {
      _HudState.init      => l10n.ballTuneHudInit,
      _HudState.detecting => l10n.ballTuneHudDetecting,
      _HudState.blobFailed => l10n.ballTuneHudBlobFailed,
      _HudState.track     => _hudTrackRaw,
    };
    return Scaffold(
      backgroundColor: const Color(0xFF101418),
      appBar: AppBar(title: Text(l10n.ballTuneTitle), backgroundColor: const Color(0xFF101418)),
      body: SafeArea(top: false, child: Column(children: [
        // ── 影片 + 軌跡疊圖 + ROI 指示 ──
        AspectRatio(
          aspectRatio: 9 / 16,
          child: LayoutBuilder(builder: (context, constraints) {
            _previewSize = constraints.biggest;
            final ext = _ext;
            final roiCenter = _roiCenterCoded();
            return GestureDetector(
              onScaleStart: _onRoiScaleStart,
              onScaleUpdate: _onRoiScaleUpdate,
              onScaleEnd: _onRoiScaleEnd,
              child: Stack(fit: StackFit.expand, children: [
                if (ctrl != null && ctrl.value.isInitialized) VideoPlayer(ctrl)
                else const Center(child: CircularProgressIndicator()),
                if (_track != null)
                  CustomPaint(painter: TrajectoryPainter(track: _track!, positionSec: posSec)),
                if (_showRoiOverlay && ext != null && roiCenter != null)
                  CustomPaint(
                    painter: _RoiOverlayPainter(
                      codedW: ext.width,
                      codedH: ext.height,
                      rotation: ext.rotation,
                      roiCenter: roiCenter,
                      roiHalfPx: _roiHalf,
                      golferBox: _golferBox,
                      roiColor: kOrviaMint,
                      maskColor: kBadColor,
                      dragging: _previewRoiHalf != null,
                    ),
                  ),
                // ROI 數值徽章 + 顯示開關
                Positioned(
                  left: 8, top: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(kRadiusSM),
                    ),
                    child: Text(
                      l10n.ballTuneRoiBadge(_roiHalf.toStringAsFixed(0), _margin.toStringAsFixed(2)),
                      style: const TextStyle(color: kOrviaMint, fontSize: 12),
                    ),
                  ),
                ),
                Positioned(
                  right: 4, top: 4,
                  child: IconButton(
                    icon: Icon(
                      _showRoiOverlay ? Icons.visibility : Icons.visibility_off,
                      color: Colors.white70, size: 20,
                    ),
                    tooltip: l10n.ballTuneRoiToggleTooltip,
                    onPressed: () => setState(() => _showRoiOverlay = !_showRoiOverlay),
                  ),
                ),
              ]),
            );
          }),
        ),
        // ── HUD ──
        Container(
          width: double.infinity,
          color: const Color(0xFF1A2026),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(_busy ? '⏳ $hudText' : hudText,
              style: const TextStyle(color: Color(0xFF8FE3A0), fontSize: 13)),
        ),
        // ── 滑桿 ──
        Expanded(
          child: ListView(padding: const EdgeInsets.all(12), children: [
            _section(l10n.ballTuneSectionRealtime),
            _slider(l10n.ballTuneSliderResidual, _cfg.trackMaxResidualPx, 0, 200,
                (v) => _setCfg(trackMaxResidualPx: v)),
            _slider(l10n.ballTuneSliderP1MaxDist, _cfg.p1MaxDistPx, 100, 600,
                (v) => _setCfg(p1MaxDistPx: v)),
            // ROI 半徑 / 遮罩 margin：主要操作改在預覽畫面上拖拉，
            // 滑桿收進進階區（雙向同步：手勢放手後滑桿跟著更新）。
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                iconColor: Colors.white70,
                collapsedIconColor: Colors.white70,
                title: Text(l10n.ballTuneRoiMaskSection,
                    style: const TextStyle(color: Colors.white, fontSize: 12)),
                children: [
                  _slider(l10n.ballTuneSliderRoiRadius, _roiHalf, _roiMin, _roiMax,
                      (v) => _setCfg(roiHalfBasePx: v)),
                  _slider(l10n.ballTuneSliderGolferMargin, _margin, 0, 0.5,
                      (v) => setState(() => _margin = v),
                      onEnd: (v) async { _margin = v; await _recomputeGolfer(); _rerun(); }),
                ],
              ),
            ),
            _slider(l10n.ballTuneSliderRoiMissScale, _cfg.roiMissScaleLarge, 1, 5,
                (v) => _setCfg(roiMissScaleLarge: v)),
            _slider(l10n.ballTuneSliderRoiRadiusMax, _cfg.roiHalfMaxAbs, 150, 500,
                (v) => _setCfg(roiHalfMaxAbs: v)),
            _slider(l10n.ballTuneSliderStepMaxPost, _cfg.stepAbsHardMaxPostImpact, 150, 600,
                (v) => _setCfg(stepAbsHardMaxPostImpact: v)),
            _slider(l10n.ballTuneSliderPredMaxPost, _cfg.predDistHardMaxPostImpact, 200, 700,
                (v) => _setCfg(predDistHardMaxPostImpact: v)),
            _slider(l10n.ballTuneSliderMissPatiencePost, _cfg.noCandPatiencePostImpact.toDouble(), 3, 40,
                (v) => _setCfg(noCandPatiencePostImpact: v.round())),
            const Divider(color: Colors.white24, height: 28),
            _section(l10n.ballTuneSectionReextract),
            _slider(l10n.ballTuneSliderDiffThresh, _diffThresh.toDouble(), 5, 40, null,
                onEnd: (v) => setState(() => _diffThresh = v.round())),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy ? null : _reextract,
              icon: const Icon(Icons.refresh),
              label: Text(l10n.ballTuneRedetectButton),
            ),
            const SizedBox(height: 24),
          ]),
        ),
      ])),
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

  // ══════════════════════════════════════════════════════════
  // ROI 手勢：拖曳邊緣 / 雙指縮放（拖曳中只更新疊圖，放手才重跑 track）
  // ══════════════════════════════════════════════════════════

  static const double _roiMin = 80;
  static const double _roiMax = 400;

  void _onRoiScaleStart(ScaleStartDetails d) {
    final ext = _ext;
    final c = _roiCenterCoded();
    if (!_showRoiOverlay || ext == null || c == null || _previewSize == Size.zero) return;
    _gestureStartRoi = _roiHalf;
    _roiEdgeDrag = false;
    if (d.pointerCount <= 1) {
      // 單指：起點落在 ROI 邊緣附近（橢圓正規化距離 0.6~1.6）才進入拖曳模式
      final cw = _codedToWidget(c.dx, c.dy, ext.width, ext.height, ext.rotation, _previewSize);
      final dispW = (ext.rotation == 90 || ext.rotation == 270) ? ext.height : ext.width;
      final dispH = (ext.rotation == 90 || ext.rotation == 270) ? ext.width : ext.height;
      final rx = _roiHalf * _previewSize.width / dispW;
      final ry = _roiHalf * _previewSize.height / dispH;
      if (rx <= 0 || ry <= 0) return;
      final dx = (d.localFocalPoint.dx - cw.dx) / rx;
      final dy = (d.localFocalPoint.dy - cw.dy) / ry;
      final e = math.sqrt(dx * dx + dy * dy);
      _roiEdgeDrag = e > 0.6 && e < 1.6;
    }
  }

  void _onRoiScaleUpdate(ScaleUpdateDetails d) {
    final ext = _ext;
    final c = _roiCenterCoded();
    if (!_showRoiOverlay || ext == null || c == null || _previewSize == Size.zero) return;
    double? next;
    if (d.pointerCount >= 2) {
      next = _gestureStartRoi * d.scale; // 雙指縮放
    } else if (_roiEdgeDrag) {
      // 單指拖曳邊緣：指尖到圓心的 coded 距離 = 新半徑
      final cw = _codedToWidget(c.dx, c.dy, ext.width, ext.height, ext.rotation, _previewSize);
      final dispW = (ext.rotation == 90 || ext.rotation == 270) ? ext.height : ext.width;
      final dispH = (ext.rotation == 90 || ext.rotation == 270) ? ext.width : ext.height;
      final dxCoded = (d.localFocalPoint.dx - cw.dx) * dispW / _previewSize.width;
      final dyCoded = (d.localFocalPoint.dy - cw.dy) * dispH / _previewSize.height;
      next = math.sqrt(dxCoded * dxCoded + dyCoded * dyCoded);
    }
    if (next != null) {
      setState(() => _previewRoiHalf = next!.clamp(_roiMin, _roiMax));
    }
  }

  void _onRoiScaleEnd(ScaleEndDetails d) {
    final committed = _previewRoiHalf;
    _roiEdgeDrag = false;
    if (committed == null) return;
    _previewRoiHalf = null;
    _setCfg(roiHalfBasePx: committed); // 放手才重跑 track（滑桿值同步顯示新值）
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

/// coded 空間座標 → 預覽 widget 座標。
/// rotation 對映同 [TrajectoryTrack.normalizedDisplay]（影片填滿預覽容器）。
Offset _codedToWidget(double x, double y, int codedW, int codedH, int rotation, Size size) {
  double nx, ny;
  switch (rotation) {
    case 90: // display = coded 順時針轉 90°
      nx = (codedH - y) / codedH; ny = x / codedW;
    case 180:
      nx = (codedW - x) / codedW; ny = (codedH - y) / codedH;
    case 270:
      nx = y / codedH; ny = (codedW - x) / codedW;
    default:
      nx = x / codedW; ny = y / codedH;
  }
  return Offset(nx * size.width, ny * size.height);
}

/// ROI 覆蓋範圍指示：
/// - ROI 圓（waitP0 搜尋範圍，圓心 = seed P0 或固定比例中心）半透明填色 +
///   主題色描邊 + 邊緣把手點（拖把手或雙指縮放調 roiHalfBasePx）
/// - 球員遮罩框（含 margin 擴張後的 coded bbox）紅色半透明
class _RoiOverlayPainter extends CustomPainter {
  final int codedW;
  final int codedH;
  final int rotation;
  final Offset roiCenter;   // coded 空間
  final double roiHalfPx;   // coded 空間半徑
  final List<int>? golferBox; // coded [x1,y1,x2,y2]
  final Color roiColor;
  final Color maskColor;
  final bool dragging;

  const _RoiOverlayPainter({
    required this.codedW,
    required this.codedH,
    required this.rotation,
    required this.roiCenter,
    required this.roiHalfPx,
    required this.golferBox,
    required this.roiColor,
    required this.maskColor,
    required this.dragging,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final dispW = (rotation == 90 || rotation == 270) ? codedH : codedW;
    final dispH = (rotation == 90 || rotation == 270) ? codedW : codedH;

    // ── 球員遮罩框 ──
    final box = golferBox;
    if (box != null && box.length == 4) {
      final p1 = _codedToWidget(box[0].toDouble(), box[1].toDouble(), codedW, codedH, rotation, size);
      final p2 = _codedToWidget(box[2].toDouble(), box[3].toDouble(), codedW, codedH, rotation, size);
      final rect = Rect.fromPoints(p1, p2);
      canvas.drawRect(rect, Paint()..color = maskColor.withValues(alpha: 0.12));
      canvas.drawRect(
        rect,
        Paint()
          ..color = maskColor.withValues(alpha: 0.7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }

    // ── ROI 圓（coded 圓 → widget 橢圓，影片非等比填滿時兩軸縮放不同）──
    final c = _codedToWidget(roiCenter.dx, roiCenter.dy, codedW, codedH, rotation, size);
    final rx = roiHalfPx * size.width / dispW;
    final ry = roiHalfPx * size.height / dispH;
    final oval = Rect.fromCenter(center: c, width: rx * 2, height: ry * 2);
    canvas.drawOval(oval, Paint()..color = roiColor.withValues(alpha: dragging ? 0.20 : 0.10));
    canvas.drawOval(
      oval,
      Paint()
        ..color = roiColor.withValues(alpha: dragging ? 1.0 : 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = dragging ? 2.5 : 1.8,
    );

    // 圓心十字
    final centerPaint = Paint()
      ..color = roiColor
      ..strokeWidth = 1.5;
    canvas.drawLine(c - const Offset(6, 0), c + const Offset(6, 0), centerPaint);
    canvas.drawLine(c - const Offset(0, 6), c + const Offset(0, 6), centerPaint);

    // 邊緣把手點（四向）：白底 + 主題色描邊
    for (final h in [
      Offset(c.dx + rx, c.dy), Offset(c.dx - rx, c.dy),
      Offset(c.dx, c.dy + ry), Offset(c.dx, c.dy - ry),
    ]) {
      canvas.drawCircle(h, 5, Paint()..color = Colors.white);
      canvas.drawCircle(
        h, 5,
        Paint()
          ..color = roiColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_RoiOverlayPainter old) =>
      old.roiHalfPx != roiHalfPx ||
      old.roiCenter != roiCenter ||
      old.golferBox != golferBox ||
      old.dragging != dragging ||
      old.rotation != rotation ||
      old.codedW != codedW ||
      old.codedH != codedH;
}
