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
class TrackPoint {
  final int x;
  final int y;
  final int frameIdx;
  final int ptsUs;

  const TrackPoint({
    required this.x,
    required this.y,
    required this.frameIdx,
    required this.ptsUs,
  });

  Map<String, dynamic> toMap() => {'x': x, 'y': y, 'pts': ptsUs};
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
    // x = A × x
    final nx = _mat41(_A, _x);
    _x.setAll(0, nx);
    // P = A × P × A^T + Q
    final AP = _mat44(_A, _P);
    final AT = _mat44T(_A);
    final APAT = _mat44(AP, AT);
    for (int i = 0; i < 16; i++) _P[i] = APAT[i] + _Q[i];
  }

  /// 更新步（Python: update）
  void update(double zx, double zy) {
    // y = z - H×x  （H 取 x 的前兩維）
    final yx = zx - _x[0];
    final yy = zy - _x[1];

    // S = H×P×H^T + R  → S 的各元素就是 P 的左上 2×2 子塊 + R
    // H = [[1,0,0,0],[0,1,0,0]] → H×P = rows 0,1 of P
    // HP × H^T = cols 0,1 of HP
    final s00 = _P[0] + _R[0];
    final s01 = _P[1] + _R[1];
    final s10 = _P[4] + _R[2];
    final s11 = _P[5] + _R[3];

    // S^-1（2×2 逆矩陣）
    final det = s00 * s11 - s01 * s10;
    final dInv = (det.abs() < 1e-8) ? 0.0 : 1.0 / det;
    final si00 = s11 * dInv; final si01 = -s01 * dInv;
    final si10 = -s10 * dInv; final si11 = s00 * dInv;

    // K = P × H^T × S^-1  （4×2 × 2×2 → 4×2）
    // P × H^T = cols 0,1 of P  (4×2 matrix: PHt[i][j] = P[i][j])
    // K[i][j] = sum_k PHt[i][k] × Si[k][j]
    final k = Float64List(8);
    for (int i = 0; i < 4; i++) {
      final ph0 = _P[i * 4 + 0]; // PHt[i][0] = P[i][0]
      final ph1 = _P[i * 4 + 1]; // PHt[i][1] = P[i][1]
      k[i * 2 + 0] = ph0 * si00 + ph1 * si10;
      k[i * 2 + 1] = ph0 * si01 + ph1 * si11;
    }

    // x = x + K × y
    for (int i = 0; i < 4; i++) {
      _x[i] += k[i * 2 + 0] * yx + k[i * 2 + 1] * yy;
    }

    // P = (I - K×H) × P
    // (I-KH)[i][l] = (i==l ? 1 : 0) - KH[i][l]
    // KH[i][l] = K[i][0] if l==0, K[i][1] if l==1, 0 otherwise
    final newP = Float64List(16);
    for (int i = 0; i < 4; i++) {
      for (int j = 0; j < 4; j++) {
        double sum = 0;
        for (int l = 0; l < 4; l++) {
          final khl    = (l == 0) ? k[i * 2 + 0] : (l == 1) ? k[i * 2 + 1] : 0.0;
          final imkhl  = (i == l ? 1.0 : 0.0) - khl;
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
// 完整移植 Python trajectory_tracker_v3_stable.py 的狀態機與決策邏輯
// ============================================================
enum _TrackState { waitP0, waitP1, tracking, stopped }

class BallTracker {
  // ── 基礎偵測設定（對應 Python DETECT_CFG_BASE）────────────
  static const int _areaLoBase = 6;
  static const int _areaHiBase = 150;
  static const double _circBase = 0.55;

  // ── 動態放寬下限（Python 各 XXX_MIN 常數）────────────────
  static const double _cfgSpeed = 0.4;
  static const double _circMin = 0.45;
  static const int _areaLoMin = 6;

  // ── 遠球自適應（FAR_*）────────────────────────────────────
  static const bool _enableFarAdaptive = true;
  static const double _farCircFloor = 0.35;
  static const int _farAreaLoFloor = 1;
  static const double _farRelaxGain = 1.0;
  static const double _farAreaEmaAlpha = 0.20;
  static const int _farFewCandsMax = 3;
  static const int _farManyCandsStop = 25;

  // ── ROI 篩選（Python FIXED_ROI_MODE + ROI_CENTER_LOCK_TO_LAST）──────────
  // ROI 中心位置（歸一化坐標）
  static const double _fixedRoiCenterRatioX = 0.6519;
  static const double _fixedRoiCenterRatioY = 0.5646;
  // ROI 尺寸（相對於視頻解析度的比例）
  static const double _roiFixedSizeRatioW = 0.3704;
  static const double _roiFixedSizeRatioH = 0.2083;
  // 追蹤中 ROI 動態增長（每 miss 增加該比例）
  static const double _roiGrowPerMiss = 35.0;
  static const double _roiHalfMax     = 200.0;

  // ── P0 / P1 ──────────────────────────────────────────────
  static const int _p1DeadlineFrames = 3;
  static const int _waitMaxFrames = 180;

  // ── Tracking ─────────────────────────────────────────────
  static const bool _stopWhenNoCand = true;
  static const int _noCandPatience = 4;
  static const int _tooManyCandsThreshold = 4;
  static const bool _tooManyUseBlue = true;
  static const int _bluePOffset = -2;
  static const double _blueToLastPMaxDist = 150.0;

  // ── Y 方向過濾（USE_Y_DIRECTION）─────────────────────────
  static const bool _useYDirection = true;
  static const bool _strictYDirection = false;
  static const int _yTol = 1;
  static const int _yMaxStep = 80;

  // ── 步長守衛（USE_STEP_DIST_GUARD）───────────────────────
  static const bool _useStepDistGuard = true;
  static const double _stepEmaAlpha = 0.25;
  static const double _stepGrowthFactor = 1.9;
  static const double _stepAbsMax = 140.0;
  static const double _stepAbsHardMax = 200.0;
  static const double _predDistHardMax = 250.0;
  static const int _outlierStrikesToFreeze = 8;

  // ── 執行狀態（每次 track() 重置）─────────────────────────
  _TrackState _state = _TrackState.waitP0;
  final List<TrackPoint> _trackPts = [];
  int _p0FrameIdx = -1;
  int _noCandCount = 0;
  int _waitFrames = 0;
  double? _stepEma;
  double? _areaEma;
  int? _yDir;
  final List<(double, double)> _blueHist = [];
  int _outlierStrikes = 0;
  late Kalman2D _kf;

  // ── 擊球時間視窗（由 hitSec 計算，避免在揮桿前偵測到球桿頭）──────────
  int _hitWindowStart = 0;
  int _hitWindowEnd   = -1;

  /// 對整段影片的逐幀 blob 資料執行追蹤，回傳軌跡點列表。
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
    _p0FrameIdx = -1;
    _noCandCount = 0;
    _waitFrames = 0;
    _stepEma = null;
    _areaEma = null;
    _yDir = null;
    _blueHist.clear();
    _outlierStrikes = 0;
    _kf = Kalman2D(dt: 1.0 / math.max(fps, 1.0));

    // 🔍 ROI 調試：打印初始化資訊
    final roiHalfW = videoW * _roiFixedSizeRatioW / 2;
    final roiHalfH = videoH * _roiFixedSizeRatioH / 2;
    final roiHalfBase = math.min(roiHalfW, roiHalfH);
    final roiCenterX = (videoW * _fixedRoiCenterRatioX).round();
    final roiCenterY = (videoH * _fixedRoiCenterRatioY).round();
    debugPrint('''[BallTracker.track] 🎬 追蹤初始化
  • 視頻解析度: ${videoW}×${videoH}
  • ROI 中心: ($roiCenterX, $roiCenterY) [比例: ${_fixedRoiCenterRatioX.toStringAsFixed(4)}, ${_fixedRoiCenterRatioY.toStringAsFixed(4)}]
  • ROI 尺寸: W=$roiHalfW, H=$roiHalfH
  • ROI 半徑: $roiHalfBase px
  • 總幀數: ${frames.length}
''');

    // 計算擊球時間視窗（waitP0 只在此範圍內搜尋，避免揮桿前的白色衣物誤判）
    // leadSec=1.0: 擊球前 1 秒開始（預留 hitSec 偵測誤差）
    // trailSec=2.0: 擊球後 2 秒（球飛行期間）
    if (hitSec != null) {
      const double leadSec  = 1.0;
      const double trailSec = 2.0;
      _hitWindowStart = math.max(0, ((hitSec - leadSec) * fps).round());
      _hitWindowEnd   = ((hitSec + trailSec) * fps).round();
    } else {
      _hitWindowStart = 0;
      _hitWindowEnd   = -1;
    }

    for (int fi = 0; fi < frames.length; fi++) {
      final frame = frames[fi];

      // ── Kalman 預測（在 ROI 篩選前執行，提供 tracking 狀態的 ROI 中心）──
      (double, double)? bluePred;
      if (_state == _TrackState.tracking && _kf.initialized) {
        _kf.predict();
        bluePred = _kf.pos;
        _blueHist.add(bluePred);
        if (_blueHist.length > 10) _blueHist.removeAt(0);
      }

      // ── ROI 空間篩選（模擬 Python 400×400 視窗，大幅降低假陽性）──
      final roiFiltered = _applyRoiFilter(frame.blobs, videoW, videoH, bluePred);

      // ── 動態門檻篩選（Dart 層複製 Python 動態 circ/area 門檻）──
      final pIndex = math.max(_trackPts.length - 1, 0);
      final filtered = _applyDynamicFilter(
        roiFiltered, pIndex, _noCandCount, _areaEma,
      );

      _processFrame(fi, frame.ptsUs, filtered, videoW, videoH, bluePred);
    }

    return List.unmodifiable(_trackPts);
  }

  /// 根據追蹤進度計算本幀的動態門檻，回傳 (areaLo, areaHi, circThresh)
  ({int areaLo, int areaHi, double circThresh}) _getDynamicCfg(
    int pIndex, {
    int missCount = 0,
    double? areaEma,
  }) {
    final t = math.max(pIndex - 1, 0).toDouble();
    final tt = _cfgSpeed * t;
    final relax = 1.0 / (1.0 + 0.45 * tt);

    var lo = (_areaLoBase * relax).round().clamp(_areaLoMin, _areaLoBase);
    var hi = (_areaHiBase * (0.80 + 0.20 * relax))
        .round()
        .clamp(lo + 2, _areaHiBase);
    var circ = (_circBase * (0.90 * relax + 0.10)).clamp(_circMin, _circBase);

    if (_enableFarAdaptive && missCount > 0) {
      final k = missCount * _farRelaxGain;
      lo = math.max(_farAreaLoFloor, (lo - 0.8 * k).round());
      hi = (hi + 1.2 * k).round();
      if (areaEma != null && areaEma > 0) {
        lo = math.min(lo, math.max(_farAreaLoFloor, (areaEma * 0.35).round()));
        hi = math.max(hi, (areaEma * 2.8).round());
      }
      hi = math.max(lo + 2, hi);
      circ = math.max(_farCircFloor, circ - 0.03 * k);
    }

    return (areaLo: lo, areaHi: hi, circThresh: circ);
  }

  /// 對 Kotlin 傳來的寬鬆 blob 列表套用動態門檻（Dart 層過濾）
  List<BlobData> _applyDynamicFilter(
    List<BlobData> raw, int pIndex, int missCount, double? areaEma,
  ) {
    if (_state == _TrackState.waitP0 || _state == _TrackState.waitP1) {
      return raw
          .where((b) =>
              b.area >= _areaLoBase &&
              b.area <= _areaHiBase &&
              b.circ >= _circBase)
          .toList();
    }

    final cfg = _getDynamicCfg(pIndex, missCount: missCount, areaEma: areaEma);
    return raw
        .where((b) =>
            b.area >= cfg.areaLo &&
            b.area <= cfg.areaHi &&
            b.circ >= cfg.circThresh)
        .toList();
  }

  /// 根據追蹤狀態，只保留在 ROI 視窗內的 blob。
  List<BlobData> _applyRoiFilter(
    List<BlobData> blobs,
    int w, int h,
    (double, double)? bluePred,
  ) {
    if (blobs.isEmpty) return blobs;

    // 計算基礎 ROI 尺寸（以較小的維度為準，確保ROI為正方形）
    final roiHalfW = w * _roiFixedSizeRatioW / 2;
    final roiHalfH = h * _roiFixedSizeRatioH / 2;
    final roiHalfBase = math.min(roiHalfW, roiHalfH);

    switch (_state) {
      case _TrackState.waitP0:
        final cx = (w * _fixedRoiCenterRatioX).round();
        final cy = (h * _fixedRoiCenterRatioY).round();
        final filtered = blobs
            .where((b) => _dist(b.cx, b.cy, cx, cy) <= roiHalfBase)
            .toList();
        // 🔍 偶爾打印 P0 搜尋信息
        if (blobs.length > 0 && blobs.length <= 15) {
          debugPrint('[ROI.waitP0] 中心($cx, $cy) 半徑=$roiHalfBase | blob: ${blobs.length} → ${filtered.length}');
        }
        return filtered;

      case _TrackState.waitP1:
        if (_trackPts.isEmpty) return blobs;
        final p0 = _trackPts.first;
        final filtered = blobs
            .where((b) => _dist(b.cx, b.cy, p0.x, p0.y) <= roiHalfBase)
            .toList();
        if (blobs.length > 0 && blobs.length <= 15) {
          debugPrint('[ROI.waitP1] P0(${ p0.x}, ${p0.y}) 半徑=$roiHalfBase | blob: ${blobs.length} → ${filtered.length}');
        }
        return filtered;

      case _TrackState.tracking:
        final radius = math.min(
          _roiHalfMax,
          roiHalfBase + _noCandCount * _roiGrowPerMiss,
        );
        double cx, cy;
        String centerSource = '';
        if (_noCandCount > 0 && bluePred != null) {
          cx = bluePred.$1;
          cy = bluePred.$2;
          centerSource = '[Kalman]';
        } else if (_trackPts.isNotEmpty) {
          cx = _trackPts.last.x.toDouble();
          cy = _trackPts.last.y.toDouble();
          centerSource = '[Last]';
        } else {
          return blobs;
        }
        final filtered = blobs
            .where((b) => _dist(b.cx, b.cy, cx.round(), cy.round()) <= radius)
            .toList();
        // 只打印候選較少或有過濾時
        if ((blobs.length > 0 && blobs.length <= 10) || filtered.isEmpty) {
          debugPrint('[ROI.tracking] center${centerSource}(${cx.round()}, ${cy.round()}) r=$radius miss=$_noCandCount | blob: ${blobs.length} → ${filtered.length}');
        }
        return filtered;

      case _TrackState.stopped:
        return blobs;
    }
  }

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

    final roiX = (w * _fixedRoiCenterRatioX).round();
    final roiY = (h * _fixedRoiCenterRatioY).round();
    final best = blobs.reduce((a, b) =>
        _dist2(a.cx, a.cy, roiX, roiY) <= _dist2(b.cx, b.cy, roiX, roiY)
            ? a
            : b);

    _trackPts.add(TrackPoint(
      x: best.cx, y: best.cy, frameIdx: frameIdx, ptsUs: ptsUs,
    ));
    _state = _TrackState.waitP1;
    _p0FrameIdx = frameIdx;
    _waitFrames = 0;
  }

  void _handleWaitP1(int frameIdx, int ptsUs, List<BlobData> blobs) {
    _waitFrames++;

    if (frameIdx - _p0FrameIdx > _p1DeadlineFrames) {
      _trackPts.clear();
      _state = _TrackState.waitP0;
      _waitFrames = 0;
      _p0FrameIdx = -1;
      return;
    }

    if (blobs.isEmpty) return;

    final p0 = _trackPts.first;
    final valid = blobs.where((b) => _dist(b.cx, b.cy, p0.x, p0.y) > 3).toList();
    if (valid.isEmpty) return;

    final best = valid.reduce((a, b) =>
        _dist2(a.cx, a.cy, p0.x, p0.y) <= _dist2(b.cx, b.cy, p0.x, p0.y)
            ? a
            : b);

    _trackPts.add(TrackPoint(
      x: best.cx, y: best.cy, frameIdx: frameIdx, ptsUs: ptsUs,
    ));
    _kf.initFromPoints(
        p0.x.toDouble(), p0.y.toDouble(),
        best.cx.toDouble(), best.cy.toDouble());
    _state = _TrackState.tracking;
    _noCandCount = 0;
    _blueHist.clear();
    _outlierStrikes = 0;
    _stepEma = null;
    _waitFrames = 0;
  }

  void _handleTracking(
    int frameIdx, int ptsUs, List<BlobData> blobs,
    (double, double) bluePred,
  ) {
    if (blobs.isEmpty) {
      _noCandCount++;
      if (_stopWhenNoCand && _noCandCount > _noCandPatience) {
        _state = _TrackState.stopped;
      }
      return;
    }

    if (blobs.length >= _farManyCandsStop) {
      _state = _TrackState.stopped;
      return;
    }

    _noCandCount = 0;
    final tooMany = blobs.length >= _tooManyCandsThreshold;
    bool appended = false;

    if (tooMany && _tooManyUseBlue) {
      final chosen = _pickBlueFromHistory(_bluePOffset);
      if (chosen != null) {
        bool ok = true;
        if (_trackPts.isNotEmpty) {
          final last = _trackPts.last;
          final d = _dist(chosen.$1.round(), chosen.$2.round(), last.x, last.y);
          if (d > _blueToLastPMaxDist) ok = false;
        }
        if (ok) {
          _trackPts.add(TrackPoint(
            x: chosen.$1.round(), y: chosen.$2.round(),
            frameIdx: frameIdx, ptsUs: ptsUs,
          ));
          appended = true;
        }
      }
    }

    if (!appended && blobs.isNotEmpty) {
      var pool = List<BlobData>.from(blobs);

      if (_useYDirection && _yDir != null && _noCandCount == 0 && _trackPts.isNotEmpty) {
        final lastY = _trackPts.last.y;
        List<BlobData> poolY;
        if (_yDir! < 0) {
          poolY = pool.where((b) => b.cy <= lastY + _yTol).toList();
        } else {
          poolY = pool.where((b) => b.cy >= lastY - _yTol).toList();
        }
        poolY = poolY
            .where((b) => (b.cy - lastY).abs() <= _yMaxStep)
            .toList();
        if (poolY.isNotEmpty) {
          pool = poolY;
        } else if (_strictYDirection) {
          pool = [];
        }
      }

      if (pool.isNotEmpty) {
        final (px, py) = bluePred;
        BlobData best;

        if (pool.length <= _farFewCandsMax) {
          best = pool.reduce((a, b) =>
              _dist2(a.cx, a.cy, px.round(), py.round()) <=
                      _dist2(b.cx, b.cy, px.round(), py.round())
                  ? a
                  : b);
        } else {
          best = pool.reduce((a, b) {
            final scoreA = _dist(a.cx, a.cy, px.round(), py.round()) -
                0.15 * a.diffMean;
            final scoreB = _dist(b.cx, b.cy, px.round(), py.round()) -
                0.15 * b.diffMean;
            return scoreA <= scoreB ? a : b;
          });
        }

        bool accept = true;
        if (_useStepDistGuard && _trackPts.isNotEmpty) {
          final last = _trackPts.last;
          final step = _dist(best.cx, best.cy, last.x, last.y);
          final baseLim = _stepEma == null
              ? _stepAbsMax
              : math.max(_stepAbsMax, _stepEma! * _stepGrowthFactor);
          final lim = baseLim * (1.0 + 0.35 * _noCandCount);
          final predDist = _dist(best.cx, best.cy, px.round(), py.round());
          final hardLim = math.min(_stepAbsHardMax, lim);

          if (step > hardLim || predDist > _predDistHardMax) {
            accept = false;
          } else {
            _stepEma = _stepEma == null
                ? step
                : (1.0 - _stepEmaAlpha) * _stepEma! + _stepEmaAlpha * step;
          }
        }

        if (accept) {
          _outlierStrikes = 0;
          _kf.update(best.cx.toDouble(), best.cy.toDouble());
          _trackPts.add(TrackPoint(
            x: best.cx, y: best.cy, frameIdx: frameIdx, ptsUs: ptsUs,
          ));

          final areaF = best.area.toDouble();
          _areaEma = _areaEma == null
              ? areaF
              : (1.0 - _farAreaEmaAlpha) * _areaEma! +
                  _farAreaEmaAlpha * areaF;

          if (_useYDirection && _yDir == null && _trackPts.length >= 3) {
            final dy = _trackPts.last.y - _trackPts.first.y;
            if (dy.abs() >= 2) _yDir = dy > 0 ? 1 : -1;
          }
        } else {
          _outlierStrikes++;
          if (_outlierStrikes >= _outlierStrikesToFreeze &&
              _trackPts.length >= 8) {
            _state = _TrackState.stopped;
          }
        }
      }
    }
  }

  (double, double)? _pickBlueFromHistory(int offset) {
    if (_blueHist.isEmpty) return null;
    var idx = _blueHist.length - 1 + offset;
    if (idx < 0) idx = 0;
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
