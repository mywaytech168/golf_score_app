import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

// ============================================================
// Data types (MethodChannel 雙向傳遞)
// ============================================================

/// 單個 blob 候選球（由 Kotlin 偵測，傳到 Dart 決策）
class BlobData {
  final int cx;
  final int cy;
  final int area;
  final double circ;
  final double diffMean; // blob 內幀差均值

  const BlobData({
    required this.cx,
    required this.cy,
    required this.area,
    required this.circ,
    this.diffMean = 0,
  });

  factory BlobData.fromMap(Map<Object?, Object?> m) => BlobData(
        cx: (m['cx'] as num).toInt(),
        cy: (m['cy'] as num).toInt(),
        area: (m['area'] as num).toInt(),
        circ: (m['circ'] as num).toDouble(),
        diffMean: (m['diffMean'] as num?)?.toDouble() ?? 0,
      );
}

/// 單幀資料（時間戳 + blob 列表）
class FrameBlobs {
  final int ptsUs; // 幀在影片中的呈現時間（微秒）
  final List<BlobData> blobs;

  const FrameBlobs({required this.ptsUs, required this.blobs});

  factory FrameBlobs.fromMap(Map<Object?, Object?> m) {
    final rawBlobs = m['blobs'] as List<Object?>;
    return FrameBlobs(
      ptsUs: (m['ptsUs'] as num).toInt(),
      blobs: rawBlobs
          .map((b) => BlobData.fromMap(b as Map<Object?, Object?>))
          .toList(),
    );
  }
}

/// 單個追蹤點（Dart 決策後傳回 Kotlin 渲染）
/// rawX/rawY = blob centroid 原始座標，x/y = 平滑後座標
class TrackPoint {
  final int x;        // 平滑後 X（用於渲染）
  final int y;        // 平滑後 Y（用於渲染）
  final int rawX;     // 原始 blob centroid X（用於 debug / CSV）
  final int rawY;     // 原始 blob centroid Y（用於 debug / CSV）
  final int frameIdx;
  final int ptsUs;

  const TrackPoint({
    required this.x,
    required this.y,
    int? rawX,
    int? rawY,
    required this.frameIdx,
    required this.ptsUs,
  })  : rawX = rawX ?? x,
        rawY = rawY ?? y;

  Map<String, dynamic> toMap() => {
        'x': x,
        'y': y,
        'rawX': rawX,
        'rawY': rawY,
        'pts': ptsUs,
      };
}

// ============================================================
// Kalman2D
// 完整移植自 Python KalmanFilter2D（常速模型）
// ============================================================
class Kalman2D {
  final double dt;

  // 狀態向量 [px, py, vx, vy]
  final Float64List _x = Float64List(4);

  // 協方差矩陣 4×4（row-major）
  final Float64List _P = Float64List(16);

  // 系統矩陣 A（常速）
  late final Float64List _A;

  // 過程噪聲 Q
  late final Float64List _Q;

  // 量測噪聲 R（2×2）
  final Float64List _R = Float64List.fromList([10, 0, 0, 10]);

  bool initialized = false;

  Kalman2D({required this.dt}) {
    // A = [[1,0,dt,0],[0,1,0,dt],[0,0,1,0],[0,0,0,1]]
    _A = Float64List.fromList([
      1, 0, dt, 0,
      0, 1, 0, dt,
      0, 0, 1, 0,
      0, 0, 0, 1,
    ]);
    // Q = diag([3, 3, 120, 120])
    _Q = Float64List.fromList([
      3, 0, 0, 0,
      0, 3, 0, 0,
      0, 0, 120, 0,
      0, 0, 0, 120,
    ]);
    // P = 1000 × I
    for (int i = 0; i < 4; i++) _P[i * 4 + i] = 1000;
  }

  /// 從兩個已知點初始化（對應 Python initialize_from_two_points）
  void initFromPoints(double p0x, double p0y, double p1x, double p1y) {
    final safeDt = math.max(dt, 1e-6);
    _x[0] = p1x; _x[1] = p1y;
    _x[2] = (p1x - p0x) / safeDt;
    _x[3] = (p1y - p0y) / safeDt;
    // P = diag([80, 80, 900, 900])
    for (int i = 0; i < 16; i++) _P[i] = 0;
    _P[0] = 80; _P[5] = 80; _P[10] = 900; _P[15] = 900;
    initialized = true;
  }

  /// 預測步（Python: predict）
  void predict() {
    final nx = _mat41(_A, _x);
    _x.setAll(0, nx);
    final AP = _mat44(_A, _P);
    final AT = _mat44T(_A);
    final APAT = _mat44(AP, AT);
    for (int i = 0; i < 16; i++) _P[i] = APAT[i] + _Q[i];
  }

  /// 更新步（Python: update）
  void update(double zx, double zy) {
    final yx = zx - _x[0];
    final yy = zy - _x[1];

    final s00 = _P[0] + _R[0];
    final s01 = _P[1] + _R[1];
    final s10 = _P[4] + _R[2];
    final s11 = _P[5] + _R[3];

    final det = s00 * s11 - s01 * s10;
    final dInv = (det.abs() < 1e-8) ? 0.0 : 1.0 / det;
    final si00 = s11 * dInv; final si01 = -s01 * dInv;
    final si10 = -s10 * dInv; final si11 = s00 * dInv;

    final k = Float64List(8);
    for (int i = 0; i < 4; i++) {
      final ph0 = _P[i * 4 + 0];
      final ph1 = _P[i * 4 + 1];
      k[i * 2 + 0] = ph0 * si00 + ph1 * si10;
      k[i * 2 + 1] = ph0 * si01 + ph1 * si11;
    }

    for (int i = 0; i < 4; i++) {
      _x[i] += k[i * 2 + 0] * yx + k[i * 2 + 1] * yy;
    }

    final newP = Float64List(16);
    for (int i = 0; i < 4; i++) {
      for (int j = 0; j < 4; j++) {
        double sum = 0;
        for (int l = 0; l < 4; l++) {
          final khl   = (l == 0) ? k[i * 2 + 0] : (l == 1) ? k[i * 2 + 1] : 0.0;
          final imkhl = (i == l ? 1.0 : 0.0) - khl;
          sum += imkhl * _P[l * 4 + j];
        }
        newP[i * 4 + j] = sum;
      }
    }
    _P.setAll(0, newP);
  }

  (double, double) get pos => (_x[0], _x[1]);

  // ------ 矩陣輔助 ------

  static Float64List _mat41(Float64List A, Float64List v) {
    final r = Float64List(4);
    for (int i = 0; i < 4; i++) {
      double s = 0;
      for (int k = 0; k < 4; k++) s += A[i * 4 + k] * v[k];
      r[i] = s;
    }
    return r;
  }

  static Float64List _mat44(Float64List A, Float64List B) {
    final C = Float64List(16);
    for (int i = 0; i < 4; i++) {
      for (int j = 0; j < 4; j++) {
        double s = 0;
        for (int k = 0; k < 4; k++) s += A[i * 4 + k] * B[k * 4 + j];
        C[i * 4 + j] = s;
      }
    }
    return C;
  }

  static Float64List _mat44T(Float64List A) {
    final B = Float64List(16);
    for (int i = 0; i < 4; i++) {
      for (int j = 0; j < 4; j++) B[i * 4 + j] = A[j * 4 + i];
    }
    return B;
  }
}

// ============================================================
// BallTracker
// 以 Flutter ball_tracker.dart 為主線，v3 Python 為驗證基準
//
// 主要設計決策：
//   - hitSec 時間窗口：只在擊球附近找 P0（避免揮桿前誤判）
//   - 分階段 step guard：前5點嚴格 → 穩定後中等 → miss 後放寬
//   - 分階段 ROI 擴張：miss 1-2=小增 / 3-4=大增 / >4=停止
//   - trackQuality：連續壞點扣分，低於門檻強制停止
//   - raw / smooth 雙軌輸出：raw供debug，smooth供渲染
//   - aiBallScore 預留：未來接 TFLite CNN crop classifier
// ============================================================
enum _TrackState { waitP0, waitP1, tracking, stopped }

class BallTracker {
  // ── 基礎偵測設定 ─────────────────────────────────────────
  static const int    _areaLoBase  = 6;
  static const int    _areaHiBase  = 150;
  static const double _circBase    = 0.55;

  // ── 動態放寬下限 ─────────────────────────────────────────
  static const double _cfgSpeed   = 0.4;
  static const double _circMin    = 0.45;
  static const int    _areaLoMin  = 6;

  // ── 遠球自適應（FAR_*）───────────────────────────────────
  static const bool   _enableFarAdaptive = true;
  static const double _farCircFloor      = 0.35;
  static const int    _farAreaLoFloor    = 1;
  static const double _farRelaxGain      = 1.0;
  static const double _farAreaEmaAlpha   = 0.20;
  static const int    _farFewCandsMax    = 3;
  static const int    _farManyCandsStop  = 25;

  // ── ROI（比例化，適應不同手機解析度）───────────────────
  static const double _fixedRoiCenterRatioX = 0.6519;
  // ROI_Y: 球在球座上時位於畫面下方約 78%（y≈1498 on 1920px frame）
  // 舊值 0.5646 → tile y[764,1404]，球實際在 y≈1574 → tile 外！
  static const double _fixedRoiCenterRatioY = 0.78;
  static const double _roiFixedSizeRatioW   = 0.3704;
  static const double _roiFixedSizeRatioH   = 0.2083;

  // miss 分階段 ROI 擴張係數（相對於 roiHalfBase）
  // miss 0      → ×1.0（嚴格）
  // miss 1-2    → ×1.8（中等）
  // miss 3-4    → ×3.2（放寬）
  // miss >= 5   → 已由 _noCandPatience 停止，不到這裡
  static const double _roiMissScaleMid   = 1.8;
  static const double _roiMissScaleLarge = 3.2;
  static const double _roiHalfMaxAbs     = 280.0; // 絕對上限

  // ── P0 / P1 ───────────────────────────────────────────
  static const int    _p1DeadlineFrames  = 25;  // P1 最多等待幀數（@30fps≈0.83s，給球飛出足夠時間）
  static const double _p1MinDistPx       = 0.0; // P1 最小移動量：0=接受靜止球（高爾夫球在球座上直到被擊中才移動）
  static const double _p1MaxDistPx       = 220.0; // P1 離 P0 最遠距離（高速球飛行距離可達 200px+）
  static const int    _waitMaxFrames     = 180;

  // ── Tracking 終止 ─────────────────────────────────────
  static const bool   _stopWhenNoCand    = true;
  static const int    _noCandPatience    = 4;   // 連續 miss 超過此幀數停止
  static const int    _tooManyCandsThreshold = 4;
  static const bool   _tooManyUseBlue   = true;
  static const int    _bluePOffset      = -2;
  static const double _blueToLastPMaxDist = 150.0;

  // ── Y 方向過濾 ────────────────────────────────────────
  static const bool   _useYDirection    = true;
  static const bool   _strictYDirection = false;
  static const int    _yTol             = 1;
  static const int    _yMaxStep         = 80;

  // ── 分階段 step guard（核心優化）────────────────────────
  // 前 _earlyPhaseLen 個點：嚴格（v3 標準）
  // 穩定追蹤（無 miss）：中等
  // miss 之後：放寬
  static const int    _earlyPhaseLen         = 5;
  static const double _stepAbsHardMaxEarly   = 130.0; // Phase 0: 嚴格（與 v3 一致）
  static const double _stepAbsHardMaxStable  = 160.0; // Phase 1: 穩定
  static const double _stepAbsHardMaxMiss    = 200.0; // Phase 2: miss 後
  static const double _predDistHardMaxEarly  = 170.0; // Phase 0: 嚴格（與 v3 一致）
  static const double _predDistHardMaxStable = 210.0; // Phase 1: 穩定
  static const double _predDistHardMaxMiss   = 250.0; // Phase 2: miss 後

  static const bool   _useStepDistGuard      = true;
  static const double _stepEmaAlpha          = 0.25;
  static const double _stepGrowthFactor      = 1.9;
  static const double _stepAbsMax            = 140.0; // EMA 基準上限
  static const int    _outlierStrikesToFreeze = 8;

  // ── trackQuality（軌跡品質分數，避免「死撐追蹤」）─────
  // 每接受一個好點：+_tqGoodHit
  // 每接受一個跳點（step 超過 EMA×1.5）：+_tqJumpHit（仍接受但品質稍差）
  // 每拒絕一個點（step guard fail）：+_tqBadReject
  // 每 miss 一幀：+_tqMiss
  // trackQuality < _tqMinStop → 停止
  static const double _tqInit      = 50.0;
  static const double _tqGoodHit   = 3.0;
  static const double _tqJumpHit   = 0.5;   // 勉強接受但有疑慮
  static const double _tqBadReject = -6.0;  // step guard 拒絕
  static const double _tqMiss      = -2.5;  // 完全沒候選
  static const double _tqMinStop   = 18.0;  // 低於此分數強制停止

  // ── hitSec 搜尋視窗（幀數為單位，避免 fps 浮動問題）────
  // 只在擊球前 5 幀到擊球後 20 幀尋找 P0（靜止球不計入）
  static const int _hitLeadFrames  = 5;   // hitFrame - 5
  static const int _hitTrailFrames = 20;  // hitFrame + 20

  // ── 執行狀態（每次 track() 重置）────────────────────────
  _TrackState _state         = _TrackState.waitP0;
  final List<TrackPoint> _trackPts = [];
  int    _p0FrameIdx         = -1;
  int    _noCandCount        = 0;
  int    _waitFrames         = 0;
  double? _stepEma;
  double? _areaEma;
  int?   _yDir;
  final List<(double, double)> _blueHist = [];
  int    _outlierStrikes     = 0;
  double _trackQuality       = _tqInit;
  late Kalman2D _kf;

  int _hitWindowStart = 0;
  int _hitWindowEnd   = -1;

  // ══════════════════════════════════════════════════════════
  // 公開入口：track()
  // ══════════════════════════════════════════════════════════

  /// 對整段影片的逐幀 blob 資料執行追蹤，回傳軌跡點列表。
  /// 回傳的 TrackPoint 包含 raw(x,y) 與 smooth(x,y)，方便 debug。
  List<TrackPoint> track({
    required List<FrameBlobs> frames,
    required double fps,
    required int videoW,
    required int videoH,
    double? hitSec,
  }) {
    // 重置所有狀態
    _state = _TrackState.waitP0;
    _trackPts.clear();
    _p0FrameIdx      = -1;
    _noCandCount     = 0;
    _waitFrames      = 0;
    _stepEma         = null;
    _areaEma         = null;
    _yDir            = null;
    _blueHist.clear();
    _outlierStrikes  = 0;
    _trackQuality    = _tqInit;
    _kf = Kalman2D(dt: 1.0 / math.max(fps, 1.0));

    final roiHalfW    = videoW * _roiFixedSizeRatioW / 2;
    final roiHalfH    = videoH * _roiFixedSizeRatioH / 2;
    final roiHalfBase = math.min(roiHalfW, roiHalfH);
    final roiCenterX  = (videoW * _fixedRoiCenterRatioX).round();
    final roiCenterY  = (videoH * _fixedRoiCenterRatioY).round();
    debugPrint('''[BallTracker.track] 🎬 追蹤初始化
  • 視頻解析度: $videoW×$videoH
  • ROI 中心: ($roiCenterX, $roiCenterY)
  • ROI 半徑: ${roiHalfBase.toStringAsFixed(1)} px
  • hitSec: ${hitSec?.toStringAsFixed(2) ?? 'null'}
  • 總幀數: ${frames.length}
  • 分階段 hardMax: E=$_stepAbsHardMaxEarly / S=$_stepAbsHardMaxStable / M=$_stepAbsHardMaxMiss
''');

    // 計算擊球幀視窗（以幀數為單位）
    if (hitSec != null) {
      final hitFrame = (hitSec * fps).round();
      _hitWindowStart = math.max(0, hitFrame - _hitLeadFrames);
      _hitWindowEnd   = hitFrame + _hitTrailFrames;
      debugPrint('[BallTracker] hitFrame=$hitFrame window=[$_hitWindowStart, $_hitWindowEnd]');
    } else {
      _hitWindowStart = 0;
      _hitWindowEnd   = -1;
    }

    for (int fi = 0; fi < frames.length; fi++) {
      final frame = frames[fi];

      // ── Kalman 預測（tracking 狀態下每幀執行）──────────
      (double, double)? bluePred;
      if (_state == _TrackState.tracking && _kf.initialized) {
        _kf.predict();
        bluePred = _kf.pos;
        _blueHist.add(bluePred);
        if (_blueHist.length > 10) _blueHist.removeAt(0);
      }

      // ── ROI 空間篩選 ─────────────────────────────────
      final roiFiltered = _applyRoiFilter(
          frame.blobs, videoW, videoH, roiHalfBase, bluePred);

      // ── 動態門檻篩選 ─────────────────────────────────
      final pIndex = math.max(_trackPts.length - 1, 0);
      final filtered = _applyDynamicFilter(
          roiFiltered, pIndex, _noCandCount, _areaEma);

      _processFrame(fi, frame.ptsUs, filtered, videoW, videoH, bluePred);

      if (_state == _TrackState.stopped) break; // 停止後跳出循環
    }

    // 輸出 raw 與 smooth 雙軌
    final rawPts = List<TrackPoint>.unmodifiable(_trackPts);
    final smoothed = _smoothTrackPts(_trackPts);
    debugPrint('[BallTracker] ✅ 追蹤完成: ${rawPts.length} 點 → smooth');
    return List.unmodifiable(smoothed);
  }

  // ══════════════════════════════════════════════════════════
  // 分階段 step guard 門檻
  // ══════════════════════════════════════════════════════════

  /// 根據追蹤長度與 miss 狀態，回傳本幀適用的 stepAbsHardMax
  double _phaseStepHardMax() {
    if (_trackPts.length < _earlyPhaseLen) {
      return _stepAbsHardMaxEarly;  // 前 5 點：嚴格
    }
    if (_noCandCount == 0) {
      return _stepAbsHardMaxStable; // 穩定追蹤：中等
    }
    return _stepAbsHardMaxMiss;     // miss 後：放寬
  }

  /// 根據追蹤長度與 miss 狀態，回傳本幀適用的 predDistHardMax
  double _phasePredHardMax() {
    if (_trackPts.length < _earlyPhaseLen) {
      return _predDistHardMaxEarly;
    }
    if (_noCandCount == 0) {
      return _predDistHardMaxStable;
    }
    return _predDistHardMaxMiss;
  }

  // ══════════════════════════════════════════════════════════
  // 分階段 ROI miss 擴張
  // ══════════════════════════════════════════════════════════

  double _missRoiRadius(double roiHalfBase) {
    double r;
    if (_noCandCount == 0) {
      r = roiHalfBase;               // 精準：只看鄰近
    } else if (_noCandCount <= 2) {
      r = roiHalfBase * _roiMissScaleMid;   // miss 1-2：中等擴展
    } else {
      r = roiHalfBase * _roiMissScaleLarge; // miss 3-4：大幅擴展
    }
    return math.min(r, _roiHalfMaxAbs);
  }

  // ══════════════════════════════════════════════════════════
  // 平滑（保留 rawX/rawY）
  // ══════════════════════════════════════════════════════════

  /// 對軌跡點做 3 點移動平均（smooth x/y），同時保留原始 raw 座標。
  List<TrackPoint> _smoothTrackPts(List<TrackPoint> pts, {int window = 3}) {
    if (pts.length < window) return pts;
    final half = window ~/ 2;
    final result = <TrackPoint>[];
    for (int i = 0; i < pts.length; i++) {
      final lo = (i - half).clamp(0, pts.length - 1);
      final hi = (i + half).clamp(0, pts.length - 1);
      double sx = 0, sy = 0;
      for (int j = lo; j <= hi; j++) {
        sx += pts[j].rawX;  // 對 raw 座標做平均
        sy += pts[j].rawY;
      }
      final cnt = hi - lo + 1;
      result.add(TrackPoint(
        x: (sx / cnt).round(),      // smooth X
        y: (sy / cnt).round(),      // smooth Y
        rawX: pts[i].rawX,          // 原始 X 保留
        rawY: pts[i].rawY,          // 原始 Y 保留
        frameIdx: pts[i].frameIdx,
        ptsUs: pts[i].ptsUs,
      ));
    }
    return result;
  }

  // ══════════════════════════════════════════════════════════
  // 動態門檻
  // ══════════════════════════════════════════════════════════

  ({int areaLo, int areaHi, double circThresh}) _getDynamicCfg(
    int pIndex, {
    int missCount = 0,
    double? areaEma,
  }) {
    final t    = math.max(pIndex - 1, 0).toDouble();
    final tt   = _cfgSpeed * t;
    final relax = 1.0 / (1.0 + 0.45 * tt);

    var lo   = (_areaLoBase * relax).round().clamp(_areaLoMin, _areaLoBase);
    var hi   = (_areaHiBase * (0.80 + 0.20 * relax)).round().clamp(lo + 2, _areaHiBase);
    var circ = (_circBase * (0.90 * relax + 0.10)).clamp(_circMin, _circBase);

    if (_enableFarAdaptive && missCount > 0) {
      final k = missCount * _farRelaxGain;
      lo   = math.max(_farAreaLoFloor, (lo - 0.8 * k).round());
      hi   = (hi + 1.2 * k).round();
      if (areaEma != null && areaEma > 0) {
        lo = math.min(lo, math.max(_farAreaLoFloor, (areaEma * 0.35).round()));
        hi = math.max(hi, (areaEma * 2.8).round());
      }
      hi   = math.max(lo + 2, hi);
      circ = math.max(_farCircFloor, circ - 0.03 * k);
    }

    return (areaLo: lo, areaHi: hi, circThresh: circ);
  }

  List<BlobData> _applyDynamicFilter(
    List<BlobData> raw, int pIndex, int missCount, double? areaEma,
  ) {
    if (_state == _TrackState.waitP0 || _state == _TrackState.waitP1) {
      final result = raw
          .where((b) =>
              b.area >= _areaLoBase &&
              b.area <= _areaHiBase &&
              b.circ >= _circBase)
          .toList();
      // 【臨時 debug】追蹤 waitP0 動態過濾狀況
      if (raw.isNotEmpty && result.isEmpty) {
        final details = raw.map((b) =>
            '(cx=${b.cx},cy=${b.cy},area=${b.area},circ=${b.circ.toStringAsFixed(2)})').join(' | ');
        debugPrint('[DynFilter.waitP0] ❌ ${raw.length}→0  blobsIn=$details'
            '  lo=$_areaLoBase hi=$_areaHiBase circMin=${_circBase.toStringAsFixed(2)}');
      } else if (result.isNotEmpty) {
        debugPrint('[DynFilter.waitP0] ✅ ${raw.length}→${result.length}  '
            'passed=(cx=${result[0].cx},cy=${result[0].cy},area=${result[0].area},circ=${result[0].circ.toStringAsFixed(2)})');
      }
      return result;
    }

    final cfg = _getDynamicCfg(pIndex, missCount: missCount, areaEma: areaEma);
    return raw
        .where((b) =>
            b.area >= cfg.areaLo &&
            b.area <= cfg.areaHi &&
            b.circ >= cfg.circThresh)
        .toList();
  }

  // ══════════════════════════════════════════════════════════
  // ROI 空間篩選
  // ══════════════════════════════════════════════════════════

  List<BlobData> _applyRoiFilter(
    List<BlobData> blobs,
    int w, int h,
    double roiHalfBase,
    (double, double)? bluePred,
  ) {
    if (blobs.isEmpty) return blobs;

    switch (_state) {
      case _TrackState.waitP0:
        final cx = (w * _fixedRoiCenterRatioX).round();
        final cy = (h * _fixedRoiCenterRatioY).round();
        final filtered = blobs
            .where((b) => _dist(b.cx, b.cy, cx, cy) <= roiHalfBase)
            .toList();
        if (blobs.isNotEmpty && blobs.length <= 15) {
          debugPrint('[ROI.waitP0] 中心($cx,$cy) r=${roiHalfBase.toStringAsFixed(0)}'
              ' | ${blobs.length}→${filtered.length}');
        }
        return filtered;

      case _TrackState.waitP1:
        if (_trackPts.isEmpty) return blobs;
        final p0 = _trackPts.first;
        final filtered = blobs
            .where((b) => _dist(b.cx, b.cy, p0.x, p0.y) <= roiHalfBase)
            .toList();
        if (blobs.isNotEmpty && blobs.length <= 15) {
          debugPrint('[ROI.waitP1] P0(${p0.x},${p0.y}) r=${roiHalfBase.toStringAsFixed(0)}'
              ' | ${blobs.length}→${filtered.length}');
        }
        return filtered;

      case _TrackState.tracking:
        // 分階段 miss ROI 擴張
        final radius = _missRoiRadius(roiHalfBase);
        double cx, cy;
        String src = '';
        if (_noCandCount > 0 && bluePred != null) {
          cx = bluePred.$1; cy = bluePred.$2; src = 'K';
        } else if (_trackPts.isNotEmpty) {
          cx = _trackPts.last.rawX.toDouble();
          cy = _trackPts.last.rawY.toDouble();
          src = 'L';
        } else {
          return blobs;
        }
        final filtered = blobs
            .where((b) => _dist(b.cx, b.cy, cx.round(), cy.round()) <= radius)
            .toList();
        if ((blobs.isNotEmpty && blobs.length <= 10) || filtered.isEmpty) {
          debugPrint('[ROI.tracking][$src] (${cx.round()},${cy.round()})'
              ' r=${radius.toStringAsFixed(0)} miss=$_noCandCount'
              ' Q=${_trackQuality.toStringAsFixed(1)}'
              ' | ${blobs.length}→${filtered.length}');
        }
        return filtered;

      case _TrackState.stopped:
        return blobs;
    }
  }

  // ══════════════════════════════════════════════════════════
  // 主狀態機分發
  // ══════════════════════════════════════════════════════════

  void _processFrame(
    int frameIdx, int ptsUs, List<BlobData> blobs, int w, int h,
    (double, double)? bluePred,
  ) {
    switch (_state) {
      case _TrackState.waitP0:
        _handleWaitP0(frameIdx, ptsUs, blobs, w, h);
      case _TrackState.waitP1:
        _handleWaitP1(frameIdx, ptsUs, blobs);
      case _TrackState.tracking:
        _handleTracking(frameIdx, ptsUs, blobs, bluePred!);
      case _TrackState.stopped:
        break;
    }
  }

  // ══════════════════════════════════════════════════════════
  // waitP0
  // ══════════════════════════════════════════════════════════

  void _handleWaitP0(
    int frameIdx, int ptsUs, List<BlobData> blobs, int w, int h,
  ) {
    if (frameIdx < _hitWindowStart) return;
    if (_hitWindowEnd >= 0 && frameIdx > _hitWindowEnd) {
      _state = _TrackState.stopped;
      return;
    }

    _waitFrames++;
    if (blobs.isEmpty) {
      if (_waitFrames >= _waitMaxFrames) {
        _state = _TrackState.stopped;
      }
      return;
    }

    // 【臨時 debug】確認 _handleWaitP0 有收到 blob
    debugPrint('[waitP0.handle] frame=$frameIdx blobs=${blobs.length} '
        '${blobs.map((b) => "(${b.cx},${b.cy},a=${b.area})").join(",")}');

    final roiX = (w * _fixedRoiCenterRatioX).round();
    final roiY = (h * _fixedRoiCenterRatioY).round();
    final best = blobs.reduce((a, b) =>
        _dist2(a.cx, a.cy, roiX, roiY) <= _dist2(b.cx, b.cy, roiX, roiY)
            ? a : b);

    _trackPts.add(TrackPoint(
      x: best.cx, y: best.cy,
      rawX: best.cx, rawY: best.cy,
      frameIdx: frameIdx, ptsUs: ptsUs,
    ));
    _state      = _TrackState.waitP1;
    _p0FrameIdx = frameIdx;
    _waitFrames = 0;
    debugPrint('[waitP0] P0 found @ frame $frameIdx (${best.cx},${best.cy})');
  }

  // ══════════════════════════════════════════════════════════
  // waitP1
  // P1 條件：距離 P0 > 3px（已在移動）& <= _p1MaxDistPx（不能太遠）
  // ══════════════════════════════════════════════════════════

  void _handleWaitP1(int frameIdx, int ptsUs, List<BlobData> blobs) {
    _waitFrames++;

    if (frameIdx - _p0FrameIdx > _p1DeadlineFrames) {
      // P1 deadline 到期，重置回 waitP0
      debugPrint('[waitP1] deadline expired @ frame $frameIdx, reset');
      _trackPts.clear();
      _state      = _TrackState.waitP0;
      _waitFrames = 0;
      _p0FrameIdx = -1;
      return;
    }

    if (blobs.isEmpty) return;

    final p0 = _trackPts.first;
    // P1 條件：移動量 >= _p1MinDistPx（0=接受靜止球，高爾夫球在球座上直到擊球後才飛走）
    //          且不過遠（<_p1MaxDistPx，避免誤接背景亮點）
    final valid = blobs.where((b) {
      final d = _dist(b.cx, b.cy, p0.x, p0.y);
      return d >= _p1MinDistPx && d <= _p1MaxDistPx;
    }).toList();
    if (valid.isEmpty) return;

    // 選距離 P0 最近的（剛剛起飛的球應在 P0 附近）
    final best = valid.reduce((a, b) =>
        _dist2(a.cx, a.cy, p0.x, p0.y) <= _dist2(b.cx, b.cy, p0.x, p0.y)
            ? a : b);

    _trackPts.add(TrackPoint(
      x: best.cx, y: best.cy,
      rawX: best.cx, rawY: best.cy,
      frameIdx: frameIdx, ptsUs: ptsUs,
    ));
    _kf.initFromPoints(
        p0.x.toDouble(), p0.y.toDouble(),
        best.cx.toDouble(), best.cy.toDouble());
    _state          = _TrackState.tracking;
    _trackQuality   = _tqInit;
    _noCandCount    = 0;
    _blueHist.clear();
    _outlierStrikes = 0;
    _stepEma        = null;
    _waitFrames     = 0;
    debugPrint('[waitP1] P1 found @ frame $frameIdx'
        ' (${best.cx},${best.cy}) dist=${_dist(best.cx, best.cy, p0.x, p0.y).toStringAsFixed(1)}');
  }

  // ══════════════════════════════════════════════════════════
  // tracking
  // ══════════════════════════════════════════════════════════

  void _handleTracking(
    int frameIdx, int ptsUs, List<BlobData> blobs,
    (double, double) bluePred,
  ) {
    // ── 完全沒候選 ──────────────────────────────────────
    if (blobs.isEmpty) {
      _noCandCount++;
      _trackQuality += _tqMiss;
      _checkQualityStop(frameIdx);
      if (_state != _TrackState.stopped &&
          _stopWhenNoCand &&
          _noCandCount > _noCandPatience) {
        debugPrint('[tracking] miss patience exceeded @ frame $frameIdx, stop');
        _state = _TrackState.stopped;
      }
      return;
    }

    // ── 候選過多（場景雜亂，可信度低）──────────────────
    if (blobs.length >= _farManyCandsStop) {
      _trackQuality += _tqMiss;
      _checkQualityStop(frameIdx);
      if (_state != _TrackState.stopped) {
        debugPrint('[tracking] too many blobs (${blobs.length}) @ frame $frameIdx, stop');
        _state = _TrackState.stopped;
      }
      return;
    }

    _noCandCount = 0;
    final tooMany = blobs.length >= _tooManyCandsThreshold;
    bool appended = false;

    // ── 候選數 >= _tooManyCandsThreshold：用 Kalman 預測歷史點 ──
    if (tooMany && _tooManyUseBlue) {
      final chosen = _pickBlueFromHistory(_bluePOffset);
      if (chosen != null) {
        bool ok = true;
        if (_trackPts.isNotEmpty) {
          final last = _trackPts.last;
          final d = _dist(chosen.$1.round(), chosen.$2.round(), last.rawX, last.rawY);
          if (d > _blueToLastPMaxDist) { ok = false; }
        }
        if (ok) {
          _trackPts.add(TrackPoint(
            x: chosen.$1.round(), y: chosen.$2.round(),
            rawX: chosen.$1.round(), rawY: chosen.$2.round(),
            frameIdx: frameIdx, ptsUs: ptsUs,
          ));
          _trackQuality += _tqJumpHit; // blue 點品質稍低
          appended = true;
        }
      }
    }

    // ── 正常候選選取 ─────────────────────────────────
    if (!appended && blobs.isNotEmpty) {
      var pool = List<BlobData>.from(blobs);

      // Y 方向軟過濾（不硬限，只移除明顯逆向）
      if (_useYDirection && _yDir != null && _noCandCount == 0 && _trackPts.isNotEmpty) {
        final lastY = _trackPts.last.rawY;
        List<BlobData> poolY;
        if (_yDir! < 0) {
          poolY = pool.where((b) => b.cy <= lastY + _yTol).toList();
        } else {
          poolY = pool.where((b) => b.cy >= lastY - _yTol).toList();
        }
        poolY = poolY.where((b) => (b.cy - lastY).abs() <= _yMaxStep).toList();
        if (poolY.isNotEmpty) { pool = poolY; }
        else if (_strictYDirection) { pool = []; }
      }

      if (pool.isNotEmpty) {
        final (px, py) = bluePred;

        // ── 候選評分 ──────────────────────────────────
        // 公式：kalmanDist - 0.15×diffMean - 0.0×aiBallScore（預留）
        // 未來：aiBallScore 由 TFLite CNN crop classifier 提供（0-1，越高越像球）
        //   final_score ≈
        //     0.35×kalman_dist_score + 0.25×diff_score
        //   + 0.25×aiBallScore      + 0.15×trajectory_score
        BlobData best;
        if (pool.length <= _farFewCandsMax) {
          best = pool.reduce((a, b) =>
              _dist2(a.cx, a.cy, px.round(), py.round()) <=
                      _dist2(b.cx, b.cy, px.round(), py.round())
                  ? a : b);
        } else {
          best = pool.reduce((a, b) {
            const double aiBallScore = 0.0; // TODO: 接 TFLite classifier
            final scoreA = _dist(a.cx, a.cy, px.round(), py.round())
                - 0.15 * a.diffMean
                - 25.0 * aiBallScore; // 25=比例因子，與距離同量級
            final scoreB = _dist(b.cx, b.cy, px.round(), py.round())
                - 0.15 * b.diffMean
                - 25.0 * aiBallScore;
            return scoreA <= scoreB ? a : b;
          });
        }

        // ── 分階段 step guard ─────────────────────────
        bool accept = true;
        bool isJump = false;

        if (_useStepDistGuard && _trackPts.isNotEmpty) {
          final last     = _trackPts.last;
          final step     = _dist(best.cx, best.cy, last.rawX, last.rawY);
          final predDist = _dist(best.cx, best.cy, px.round(), py.round());

          // EMA 基準上限
          final baseLim = _stepEma == null
              ? _stepAbsMax
              : math.max(_stepAbsMax, _stepEma! * _stepGrowthFactor);
          final lim     = baseLim * (1.0 + 0.35 * _noCandCount);

          // 分階段 hard max（核心優化）
          final hardStep = _phaseStepHardMax();
          final hardPred = _phasePredHardMax();
          final stepLim  = math.min(hardStep, lim);

          if (step > stepLim || predDist > hardPred) {
            accept  = false;
            isJump  = true; // 暫稱 jump，後面用於品質扣分
          } else {
            // 判斷是否為「勉強接受的跳點」
            isJump = _stepEma != null && step > _stepEma! * 1.5;
            _stepEma = _stepEma == null
                ? step
                : (1.0 - _stepEmaAlpha) * _stepEma! + _stepEmaAlpha * step;
          }
        }

        if (accept) {
          // trackQuality 加分
          _trackQuality += isJump ? _tqJumpHit : _tqGoodHit;
          _trackQuality  = math.min(_trackQuality, 100.0); // 上限

          _outlierStrikes = 0;
          _kf.update(best.cx.toDouble(), best.cy.toDouble());
          _trackPts.add(TrackPoint(
            x: best.cx, y: best.cy,
            rawX: best.cx, rawY: best.cy,
            frameIdx: frameIdx, ptsUs: ptsUs,
          ));

          final areaF = best.area.toDouble();
          _areaEma = _areaEma == null
              ? areaF
              : (1.0 - _farAreaEmaAlpha) * _areaEma! + _farAreaEmaAlpha * areaF;

          // 確定 Y 方向（3 點以上才固定方向）
          if (_useYDirection && _yDir == null && _trackPts.length >= 3) {
            final dy = _trackPts.last.rawY - _trackPts.first.rawY;
            if (dy.abs() >= 2) { _yDir = dy > 0 ? 1 : -1; }
          }
        } else {
          // step guard 拒絕 → 扣 trackQuality
          _trackQuality += _tqBadReject;
          _outlierStrikes++;
          debugPrint('[tracking] step guard reject @ frame $frameIdx'
              ' step=${isJump ? "jump" : "over"} Q=${_trackQuality.toStringAsFixed(1)}');
          if (_outlierStrikes >= _outlierStrikesToFreeze &&
              _trackPts.length >= 8) {
            debugPrint('[tracking] outlier strikes=$_outlierStrikes, stop');
            _state = _TrackState.stopped;
          }
        }

        // trackQuality 下限檢查（即使接受了點，也可能因累積扣分停止）
        _checkQualityStop(frameIdx);
      }
    }
  }

  // ══════════════════════════════════════════════════════════
  // trackQuality 停止判斷
  // ══════════════════════════════════════════════════════════

  void _checkQualityStop(int frameIdx) {
    if (_state == _TrackState.stopped) return;
    if (_trackQuality < _tqMinStop && _trackPts.length >= 4) {
      debugPrint('[tracking] trackQuality=${_trackQuality.toStringAsFixed(1)}'
          ' < $_tqMinStop, stop @ frame $frameIdx'
          ' (${_trackPts.length} pts)');
      _state = _TrackState.stopped;
    }
  }

  // ══════════════════════════════════════════════════════════
  // 輔助
  // ══════════════════════════════════════════════════════════

  (double, double)? _pickBlueFromHistory(int offset) {
    if (_blueHist.isEmpty) return null;
    var idx = _blueHist.length - 1 + offset;
    if (idx < 0) { idx = 0; }
    if (idx >= _blueHist.length) return null;
    return _blueHist[idx];
  }

  double _dist(int ax, int ay, int bx, int by) {
    final dx = (ax - bx).toDouble();
    final dy = (ay - by).toDouble();
    return math.sqrt(dx * dx + dy * dy);
  }

  double _dist2(int ax, int ay, int bx, int by) {
    final dx = (ax - bx).toDouble();
    final dy = (ay - by).toDouble();
    return dx * dx + dy * dy;
  }
}
