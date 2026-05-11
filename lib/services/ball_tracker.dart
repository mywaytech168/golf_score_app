import 'dart:math' as math;
import 'dart:typed_data';

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
  static const double _circBase = 0.60;

  // ── 動態放寬下限（Python 各 XXX_MIN 常數）────────────────
  static const double _cfgSpeed = 0.4; // CFG_SPEED
  // _diffMin (=9) applied by Kotlin pixel layer as DIFF_THRESH baseline
  static const double _circMin = 0.60; // CIRC_MIN
  static const int _areaLoMin = 6; // AREA_LO_MIN

  // ── 遠球自適應（FAR_*）────────────────────────────────────
  static const bool _enableFarAdaptive = true;
  // _farDiffFloor (=3) applied by Kotlin pixel layer; Dart uses circ/area floors
  static const double _farCircFloor = 0.35;
  static const int _farAreaLoFloor = 1;
  static const double _farRelaxGain = 1.0;
  static const double _farAreaEmaAlpha = 0.20;
  static const int _farFewCandsMax = 3;
  static const int _farManyCandsStop = 25;

  // ── P0 / P1 ──────────────────────────────────────────────
  static const int _p1DeadlineFrames = 1; // Python P1_MUST_APPEAR_NEXT_FRAME + DEADLINE=1
  static const int _waitMaxFrames = 180; // Python WAIT_MAX_FRAMES

  // ── Tracking ─────────────────────────────────────────────
  static const bool _stopWhenNoCand = true; // STOP_WHEN_NO_CAND_IN_TRACK
  static const int _noCandPatience = 4; // NO_CAND_PATIENCE
  static const int _tooManyCandsThreshold = 4; // TOO_MANY_CANDS_THRESHOLD
  static const bool _tooManyUseBlue = true; // TOO_MANY_CANDS_USE_BLUE_AS_P
  static const int _bluePOffset = -2; // BLUE_P_OFFSET
  static const double _blueToLastPMaxDist = 150.0; // BLUE_TO_LASTP_MAX_DIST

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
  static const double _stepAbsHardMax = 130.0;
  static const double _predDistHardMax = 170.0;
  static const int _outlierStrikesToFreeze = 8;

  // ── 執行狀態（每次 track() 重置）─────────────────────────
  _TrackState _state = _TrackState.waitP0;
  final List<TrackPoint> _trackPts = [];
  int _p0FrameIdx = -1;
  int _noCandCount = 0;
  int _waitFrames = 0;
  double? _stepEma; // 步長 EMA
  double? _areaEma; // blob 面積 EMA（遠球偵測）
  int? _yDir; // 垂直方向：+1=下 -1=上
  final List<(double, double)> _blueHist = []; // Kalman 預測點歷史
  int _outlierStrikes = 0;
  late Kalman2D _kf;

  // ============================================================
  // 公開入口
  // ============================================================

  /// 對整段影片的逐幀 blob 資料執行追蹤，回傳軌跡點列表。
  ///
  /// [frames]  Kotlin 回傳的每幀 blob（已過 pixel-level 初篩）
  /// [fps]     影片幀率（決定 Kalman dt）
  /// [videoW]  影片寬（用於初始 ROI 判斷）
  /// [videoH]  影片高
  List<TrackPoint> track({
    required List<FrameBlobs> frames,
    required double fps,
    required int videoW,
    required int videoH,
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

    for (int fi = 0; fi < frames.length; fi++) {
      final frame = frames[fi];
      final pIndex = math.max(_trackPts.length - 1, 0);

      // 動態過濾：Dart 對 Kotlin 傳來的寬鬆 blob 再套 Python 動態門檻
      final filtered = _applyDynamicFilter(
        frame.blobs, pIndex, _noCandCount, _areaEma,
      );

      _processFrame(fi, frame.ptsUs, filtered, videoW, videoH);
    }

    return List.unmodifiable(_trackPts);
  }

  // ============================================================
  // 動態偵測門檻（Python get_dynamic_detect_cfg + get_far_adaptive_cfg）
  // ============================================================

  /// 根據追蹤進度計算本幀的動態門檻，回傳 (areaLo, areaHi, circThresh)
  ({int areaLo, int areaHi, double circThresh}) _getDynamicCfg(
    int pIndex, {
    int missCount = 0,
    double? areaEma,
  }) {
    // ── 基礎放寬（Python: relax 因子）──
    final t = math.max(pIndex - 1, 0).toDouble();
    final tt = _cfgSpeed * t;
    final relax = 1.0 / (1.0 + 0.45 * tt);

    // area_lo
    var lo = (_areaLoBase * relax).round().clamp(_areaLoMin, _areaLoBase);
    // area_hi：hi 也隨 relax 縮小（遠球視野縮小）
    var hi = (_areaHiBase * (0.80 + 0.20 * relax))
        .round()
        .clamp(lo + 2, _areaHiBase);
    // circ
    var circ = (_circBase * (0.90 * relax + 0.10)).clamp(_circMin, _circBase);

    // ── 遠球自適應（Python: get_far_adaptive_cfg）──
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
    // WAIT_P0 / WAIT_P1 使用基礎設定
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

  // ============================================================
  // 逐幀狀態機
  // ============================================================

  void _processFrame(
    int frameIdx, int ptsUs, List<BlobData> blobs, int w, int h,
  ) {
    (double, double)? bluePred;

    // Tracking 狀態：先 Kalman predict，保存預測點到歷史
    if (_state == _TrackState.tracking && _kf.initialized) {
      _kf.predict();
      bluePred = _kf.pos;
      _blueHist.add(bluePred);
    }

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

  // ── WAIT_P0 ─────────────────────────────────────────────────

  void _handleWaitP0(
    int frameIdx, int ptsUs, List<BlobData> blobs, int w, int h,
  ) {
    _waitFrames++;
    if (blobs.isEmpty) {
      if (_waitFrames >= _waitMaxFrames) {
        _state = _TrackState.stopped;
      }
      return;
    }

    // Python: 取最接近 ROI 中心（我們無固定 ROI，改取中心距最近 + circ 最高）
    // 用評分：circ × area，值越高越像球（避免邊緣雜訊）
    final best = blobs.reduce((a, b) {
      final scoreA = a.circ * a.area.toDouble();
      final scoreB = b.circ * b.area.toDouble();
      return scoreA >= scoreB ? a : b;
    });

    _trackPts.add(TrackPoint(
      x: best.cx, y: best.cy, frameIdx: frameIdx, ptsUs: ptsUs,
    ));
    _state = _TrackState.waitP1;
    _p0FrameIdx = frameIdx;
    _waitFrames = 0;
  }

  // ── WAIT_P1 ─────────────────────────────────────────────────

  void _handleWaitP1(int frameIdx, int ptsUs, List<BlobData> blobs) {
    _waitFrames++;

    // Python P1_MUST_APPEAR_NEXT_FRAME + P1_DEADLINE_FRAMES=1
    if (frameIdx - _p0FrameIdx > _p1DeadlineFrames) {
      // P1 超時 → 重置
      _trackPts.clear();
      _state = _TrackState.waitP0;
      _waitFrames = 0;
      _p0FrameIdx = -1;
      return;
    }

    if (blobs.isEmpty) return;

    final p0 = _trackPts.first;

    // Python USE_LEFT_RULE = false → 所有方向都接受
    // 但排除與 P0 完全重疊的點（dist > 3）
    final valid = blobs.where((b) => _dist(b.cx, b.cy, p0.x, p0.y) > 3).toList();
    if (valid.isEmpty) return;

    // 取距 P0 最近的
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

  // ── TRACKING ────────────────────────────────────────────────

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

    // Python: FAR_MANY_CANDS_STOP
    if (blobs.length >= _farManyCandsStop) {
      _state = _TrackState.stopped;
      return;
    }

    _noCandCount = 0;
    final tooMany = blobs.length >= _tooManyCandsThreshold;
    bool appended = false;

    // ── 候選過多 → 用 Kalman 歷史 blue 點（Python: TOO_MANY_CANDS_USE_BLUE_AS_P）──
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

    // ── 正常候選選擇 ────────────────────────────────────────
    if (!appended && blobs.isNotEmpty) {
      var pool = List<BlobData>.from(blobs);

      // Python USE_LEFT_RULE = false → 不過濾方向

      // Y 方向過濾（Python USE_Y_DIRECTION）
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
          // 少量候選 → 選最接近 Kalman 預測的
          best = pool.reduce((a, b) =>
              _dist2(a.cx, a.cy, px.round(), py.round()) <=
                      _dist2(b.cx, b.cy, px.round(), py.round())
                  ? a
                  : b);
        } else {
          // 中量候選 → 距離 - 0.15×diffMean 評分（Python 原版）
          best = pool.reduce((a, b) {
            final scoreA = _dist(a.cx, a.cy, px.round(), py.round()) -
                0.15 * a.diffMean;
            final scoreB = _dist(b.cx, b.cy, px.round(), py.round()) -
                0.15 * b.diffMean;
            return scoreA <= scoreB ? a : b;
          });
        }

        // ── 步長守衛（USE_STEP_DIST_GUARD）──
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

          // 更新面積 EMA（遠球自適應用）
          final areaF = best.area.toDouble();
          _areaEma = _areaEma == null
              ? areaF
              : (1.0 - _farAreaEmaAlpha) * _areaEma! +
                  _farAreaEmaAlpha * areaF;

          // 更新 Y 方向（Python: 取前3點決定方向）
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

  // ============================================================
  // 輔助工具
  // ============================================================

  /// 從 blue 歷史取指定偏移的 Kalman 預測點（Python: pick_blue_from_history）
  (double, double)? _pickBlueFromHistory(int offset) {
    if (_blueHist.isEmpty) return null;
    var idx = _blueHist.length - 1 + offset; // offset 通常是 -2
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
