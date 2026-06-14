import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart';

import '../models/swing_hit.dart';

// ──────────────────────────────────────────────────────────────────────────────
// 高爾夫揮桿撞擊偵測 — speed_y_low 算法
//
// 算法升級（對應 golf_impact_detection_release_v1 long_cli.py）：
//
// ┌─────────────────────────────────────────────────────────────────────────┐
// │  舊算法 (v3_fast)            →  新算法 (speed_y_low)                   │
// ├─────────────────────────────────────────────────────────────────────────┤
// │  findPeaks(speed)             →  speedPassageCenters（通道取最大值）    │
// │  findPeaks(audio) + 交集      →  音頻不參與偵測（已移除）               │
// │  片段中心 = avg(speed,audio)  →  片段中心 = Y-LOW（手腕最低點）         │
// │  無去重                       →  5 秒窗口保留 TOP 最高的桿              │
// │  threshold = max(92%,0.8)     →  max(minH, 92%, mean+0.6σ, 0.55×p90)  │
// └─────────────────────────────────────────────────────────────────────────┘
//
// 流程：
//   1. CSV 解析右手腕速度 + 平滑 Y 座標（含實際 FPS）
//   2. 速度去噪（中值 → 移動平均 → 基線扣除）
//   3. 自適應門檻：max(minH, 92nd%, mean+0.6σ, 0.55×p90)
//   4. 速度通道偵測 → FAST 幀（速度持續超門檻的區段中心）
//   5. 每個 FAST → 搜尋最近 Y-LOW（手腕最低點 ≈ 撞球）
//   6. 每個 Y-LOW → 搜尋 TOP（後擺頂點，Y 最小）
//   7. 近距離去重（5 秒窗口保留 TOP 最高的桿）
//   8. 以 Y-LOW 為中心截取 5 秒片段
// ──────────────────────────────────────────────────────────────────────────────

class SwingImpactDetector {
  // ── 片段截取範圍 ──────────────────────────────────────────────────────────
  static const double clipTotalDuration = 5.0;
  @Deprecated('改用 clipTotalDuration + 動態計算')
  static const double clipPreSec = 2.5;
  @Deprecated('改用 clipTotalDuration + 動態計算')
  static const double clipPostSec = 2.5;

  // ── 速度訊號去噪參數（秒，FPS 無關）────────────────────────────────────
  static const double _speedMedianSec   = 0.23;
  static const double _speedSmoothSec   = 0.23;
  static const double _speedBaselineSec = 4.0;
  static const double _speedHeightPct   = 92.0;
  static const double _speedMinHeight   = 0.8;

  // ── speed_y_low 算法參數 ─────────────────────────────────────────────────
  static const double _nearHitWindowSec    = 5.0;   // 近距離去重窗口
  static const double _yLowWindowSec       = 0.45;  // Y-LOW 搜索範圍（±秒）
  static const double _topSearchSec        = 1.2;   // TOP 向前搜索秒數
  static const double _passageMergeGapSec  = 0.18;  // 速度通道合併間距

  // ── legacy 參數（向後兼容，不用於主流程）──────────────────────────────
  static const double peakDistanceSec       = 0.45;
  static const double intersectToleranceSec = 0.40;

  /// 動態計算 clip 邊界，以擊球點為中心
  static (double, double) calculateClipBoundaries({
    required double hitSec,
    required double totalDurationSec,
  }) {
    final halfDuration = clipTotalDuration / 2;
    var startSec = hitSec - halfDuration;
    var endSec   = hitSec + halfDuration;
    if (startSec < 0.0) {
      startSec = 0.0;
      endSec   = math.min(totalDurationSec, clipTotalDuration);
    } else if (endSec > totalDurationSec) {
      endSec   = totalDurationSec;
      startSec = math.max(0.0, totalDurationSec - clipTotalDuration);
    }
    return (startSec, endSec);
  }

  /// 主入口：在 isolate 中執行，不阻塞 UI
  ///
  /// [bothHands] 雙手判斷：速度訊號改為「兩手都在動」才計入，其中一手遮擋時退回
  /// 另一手（見 [SwingDetectPrefs]）。
  /// [anchorX]/[anchorY]：離線 V4 錨點（歸一化 0-1）。提供時，擊球幀改取「揮桿窗內
  /// 主導腕距錨點最近」那一幀（鏡像即時 V4），而非手腕弧底 Y-LOW。
  static Future<List<SwingHit>> detect({
    required String csvPath,
    bool bothHands = false,
    double? anchorX,
    double? anchorY,
  }) async {
    final args = _DetectArgs(
      csvPath: csvPath,
      bothHands: bothHands,
      anchorX: anchorX,
      anchorY: anchorY,
    );
    try {
      return await Isolate.run(() => _detectIsolate(args));
    } catch (e) {
      debugPrint('[SwingImpact] detect error: $e');
      return [];
    }
  }
}

// ── Isolate 入口 ─────────────────────────────────────────────────────────────

List<SwingHit> _detectIsolate(_DetectArgs args) {
  debugPrint('[SwingDetect] 🔍 speed_y_low 模式開始偵測...');

  // 1. 解析 CSV → 速度 + 平滑 Y + FPS
  final csvResult = _parseWristSpeed(args.csvPath, bothHands: args.bothHands);
  if (csvResult == null) {
    debugPrint('[SwingDetect] ❌ CSV 解析失敗');
    return [];
  }
  final speedRaw = csvResult.speed;
  final fps      = csvResult.fps;
  final n        = speedRaw.length;
  final ySmooth  = csvResult.ySmooth;

  debugPrint('[SwingDetect] 📊 $n 幀, FPS=$fps');
  if (n < 10) {
    debugPrint('[SwingDetect] ❌ 幀數不足: $n');
    return [];
  }

  // 2. FPS 自適應 kernel 大小
  final speedMk = _toOddFrames(SwingImpactDetector._speedMedianSec,   fps);
  final speedSw = _toOddFrames(SwingImpactDetector._speedSmoothSec,   fps);
  final speedBk = _toOddFrames(SwingImpactDetector._speedBaselineSec, fps);

  // 3. 速度去噪
  final speedDn = _denoiseSignal(speedRaw, speedMk, speedSw, speedBk);
  final speedValid = speedDn
      .where((v) => !v.isNaN && v.isFinite)
      .toList()
    ..sort();
  if (speedValid.isEmpty) {
    debugPrint('[SwingDetect] ❌ 去噪後速度全部無效');
    return [];
  }

  // 4. 自適應門檻：max(minH, 92nd%, mean+0.6σ, 0.55×p90)
  final p90  = _percentile(speedValid, 90.0);
  final mean = speedValid.fold(0.0, (a, b) => a + b) / speedValid.length;
  final std  = math.sqrt(
    speedValid.fold(0.0, (a, b) => a + (b - mean) * (b - mean)) / speedValid.length,
  );
  final thr = [
    SwingImpactDetector._speedMinHeight,
    _percentile(speedValid, SwingImpactDetector._speedHeightPct),
    mean + 0.6 * std,
    0.55 * p90,
  ].reduce(math.max);
  debugPrint('[SwingDetect] ⚡ 速度門檻=${thr.toStringAsFixed(3)}'
      ' (p90=${p90.toStringAsFixed(3)}, mean=${mean.toStringAsFixed(3)}, std=${std.toStringAsFixed(3)})');

  // 5. 速度通道偵測 → FAST 幀（超門檻區段的速度最大幀）
  final mergeGap    = math.max(1, (SwingImpactDetector._passageMergeGapSec * fps).round());
  final minFastFrame = math.max(0, (0.3 * fps).round()); // 忽略前 0.3 秒
  final fastCenters = _speedPassageCenters(speedDn, thr, minFastFrame, mergeGap);
  debugPrint('[SwingDetect] 📍 速度通道: ${fastCenters.length} 個 FAST 幀');

  // 6. 每個 FAST → 擊球幀（錨點模式＝距錨點最近；否則 Y-LOW）→ TOP
  final hasAnchor = args.anchorX != null && args.anchorY != null &&
      csvResult.xNorm.length == n && csvResult.yNorm.length == n;
  if (hasAnchor) {
    debugPrint('[SwingDetect] 🎯 錨點模式 V4: anchor=(${args.anchorX!.toStringAsFixed(3)}, ${args.anchorY!.toStringAsFixed(3)})');
  }
  final candidates = <_HitCandidate>[];
  for (final fast in fastCenters) {
    final yLow = hasAnchor
        ? _nearestAnchorFrame(csvResult.xNorm, csvResult.yNorm,
            args.anchorX!, args.anchorY!, fast, fps)
        : _nearestYLowFrame(ySmooth, fast, fps);
    final top  = _topFrame(ySmooth, yLow, fast, fps);
    candidates.add(_HitCandidate(
      fastFrame:  fast,
      yLowFrame:  yLow,
      topFrame:   top,
      speedValue: speedDn[fast].isNaN ? 0.0 : speedDn[fast],
    ));
    debugPrint('[SwingDetect]   FAST=$fast → Y-LOW=$yLow, TOP=$top');
  }

  // 7. 近距離去重：5 秒窗口內保留 TOP 最高（Y 最小）的桿
  final deduped = _filterNearbyHitsKeepHighestTop(candidates, ySmooth, fps);
  debugPrint('[SwingDetect] ✅ 去重後: ${deduped.length} 個擊球');

  // 8. 建立 SwingHit（以 Y-LOW 為中心截取片段）
  final totalDurationSec = n / fps;
  final hits = <SwingHit>[];
  for (int i = 0; i < deduped.length; i++) {
    final c      = deduped[i];
    final hitSec = c.yLowFrame / fps;
    final (startSec, endSec) = SwingImpactDetector.calculateClipBoundaries(
      hitSec: hitSec,
      totalDurationSec: totalDurationSec,
    );

    // 8 階段關鍵禎偵測
    final addrFrame  = _addressFrame(speedDn, c.topFrame, fps);
    final tkwFrame   = _takeawayFrame(speedDn, addrFrame, c.topFrame, p90);
    final bswFrame   = _backswingFrame(ySmooth, tkwFrame, c.topFrame);
    final downFrame  = _downswingFrame(ySmooth, c.topFrame, c.yLowFrame);
    final ftFrame    = _followThroughFrame(ySmooth, c.yLowFrame, fps, n);
    final finFrame   = _finishFrame(speedDn, ftFrame, fps, n, p90);

    hits.add(SwingHit(
      hitIndex:   i + 1,
      hitFrame:   c.yLowFrame,
      hitSec:     hitSec,
      startSec:   startSec,
      endSec:     endSec,
      speedValue: c.speedValue,
      audioValue: 0.0,
      fastFrame:  c.fastFrame,
      topFrame:   c.topFrame,
      addressSec:        addrFrame / fps,
      takeawaySec:       tkwFrame  / fps,
      backswingSec:      bswFrame  / fps,
      backswingTopSec:   c.topFrame / fps,
      downswingSec:      downFrame / fps,
      followThroughSec:  ftFrame / fps,
      finishSec:         finFrame / fps,
    ));
    debugPrint('[SwingDetect] 🏌️ Hit ${i+1}: '
        'yLow=${c.yLowFrame} (${hitSec.toStringAsFixed(2)}s), '
        'fast=${c.fastFrame}, top=${c.topFrame}, '
        'clip=[${startSec.toStringAsFixed(2)}, ${endSec.toStringAsFixed(2)}]');
  }
  return hits;
}

// ── 速度通道偵測 ─────────────────────────────────────────────────────────────

/// 找出速度訊號中持續超過閾值的區段，合併相近區段後回傳每段的速度最大幀。
/// 對應 Python: _speed_passage_centers()
List<int> _speedPassageCenters(
  List<double> speed,
  double threshold,
  int minFastFrame,
  int mergeGapFrames,
) {
  final n = speed.length;

  // 找連續超閾值區段
  final passages = <(int, int)>[];
  int i = 0;
  while (i < n) {
    if (i < minFastFrame || speed[i] < threshold || speed[i].isNaN) {
      i++;
      continue;
    }
    final start = i;
    while (i + 1 < n && !speed[i + 1].isNaN && speed[i + 1] >= threshold) {
      i++;
    }
    passages.add((start, i));
    i++;
  }
  if (passages.isEmpty) return [];

  // 合併相近區段（間距 ≤ mergeGapFrames）
  final merged = [passages.first];
  for (int j = 1; j < passages.length; j++) {
    final (_, prevEnd) = merged.last;
    final (start, end) = passages[j];
    if (start - prevEnd <= mergeGapFrames) {
      merged[merged.length - 1] = (merged.last.$1, end);
    } else {
      merged.add(passages[j]);
    }
  }

  // 每段取速度最大幀
  return merged.map((p) {
    final (start, end) = p;
    int best = start;
    for (int k = start + 1; k <= end && k < n; k++) {
      if (!speed[k].isNaN && speed[k] > speed[best]) best = k;
    }
    return best;
  }).toList();
}

// ── 錨點最近幀偵測（離線 V4，鏡像即時 LiveSwingDetector）────────────────────────

/// 在 FAST 幀附近的較寬窗內，找主導腕（歸一化）距錨點最近的那一幀 = 擊球時刻。
/// 鏡像即時錨點判定（手回到球位/握把最近）。窗口較 Y-LOW 寬，因下桿回歸需更長範圍。
int _nearestAnchorFrame(
    List<double> xn, List<double> yn, double ax, double ay, int center, double fps,
    {double windowSec = 0.8}) {
  final n = xn.length;
  final w = math.max(1, (windowSec * fps).round());
  final l = math.max(0, center - w);
  final r = math.min(n, center + w + 1);
  if (l >= r) return center.clamp(0, n - 1);

  int best = -1;
  double bestDist = double.infinity;
  for (int i = l; i < r; i++) {
    if (xn[i].isNaN || yn[i].isNaN) continue;
    final dx = xn[i] - ax, dy = yn[i] - ay;
    final d = dx * dx + dy * dy;
    if (d < bestDist) { bestDist = d; best = i; }
  }
  return best >= 0 ? best : center.clamp(0, n - 1);
}

// ── Y-LOW 幀偵測 ─────────────────────────────────────────────────────────────

/// 在 FAST 幀附近搜尋最近的 Y 局部最大值（手腕最低點 = 撞球時刻）。
/// 對應 Python: _nearest_y_low_frame()
int _nearestYLowFrame(List<double> y, int center, double fps,
    {double windowSec = SwingImpactDetector._yLowWindowSec}) {
  final n = y.length;
  final w = math.max(1, (windowSec * fps).round());
  final l = math.max(0, center - w);
  final r = math.min(n, center + w + 1);
  if (l >= r) return center.clamp(0, n - 1);

  // 在窗口內找 Y 局部最大值（Y 大 = 螢幕上位置低 = 手腕最低）
  final localMaxima = <int>[];
  for (int i = l + 1; i < r - 1; i++) {
    if (!y[i].isNaN && !y[i - 1].isNaN && !y[i + 1].isNaN &&
        y[i] >= y[i - 1] && y[i] > y[i + 1]) {
      localMaxima.add(i);
    }
  }

  if (localMaxima.isNotEmpty) {
    // 選取最靠近 center 的局部最大值
    return localMaxima
        .reduce((best, c) => (c - center).abs() < (best - center).abs() ? c : best);
  }

  // 後備：窗口內 Y 最大的幀
  int best = l;
  for (int i = l + 1; i < r; i++) {
    if (!y[i].isNaN && (y[best].isNaN || y[i] > y[best])) best = i;
  }
  return best;
}

// ── TOP 幀偵測 ───────────────────────────────────────────────────────────────

/// 在 Y-LOW 前 1.2 秒內找 Y 最小幀（後擺頂點 = 手腕最高點）。
/// 對應 Python speed_y_low: top_r = max(top_l + 1, min(y_low, fast))
int _topFrame(List<double> y, int yLow, int fast, double fps) {
  final n  = y.length;
  final tl = math.max(0, yLow - (SwingImpactDetector._topSearchSec * fps).round());
  final tr = math.max(tl + 1, math.min(yLow, fast));
  if (tl >= tr || tr > n) return math.max(0, yLow - 1);

  int best = tl;
  for (int i = tl + 1; i < tr; i++) {
    if (!y[i].isNaN && (y[best].isNaN || y[i] < y[best])) best = i;
  }
  return best;
}

// ── 近距離去重 ───────────────────────────────────────────────────────────────

/// 5 秒窗口內的相鄰偵測，保留 TOP Y 最小（後擺最高）的桿。
/// 對應 Python: _filter_nearby_hits_keep_highest_top()
List<_HitCandidate> _filterNearbyHitsKeepHighestTop(
  List<_HitCandidate> hits,
  List<double> y,
  double fps, {
  double windowSec = SwingImpactDetector._nearHitWindowSec,
}) {
  if (hits.isEmpty) return hits;
  final windowFrames = math.max(1, (windowSec * fps).round());
  final sorted = [...hits]..sort((a, b) => a.yLowFrame.compareTo(b.yLowFrame));

  // 聚類
  final clusters = <List<_HitCandidate>>[];
  var current = <_HitCandidate>[sorted.first];
  var anchor  = sorted.first.yLowFrame;

  for (int i = 1; i < sorted.length; i++) {
    final ev = sorted[i];
    if (ev.yLowFrame - anchor <= windowFrames) {
      current.add(ev);
    } else {
      clusters.add(current);
      current = [ev];
      anchor  = ev.yLowFrame;
    }
  }
  clusters.add(current);

  // 每群保留 TOP Y 最小者（後擺最高）
  return clusters.map((cluster) {
    return cluster.reduce((best, c) {
      final bestY = (best.topFrame < y.length && !y[best.topFrame].isNaN)
          ? y[best.topFrame]
          : double.infinity;
      final cY = (c.topFrame < y.length && !y[c.topFrame].isNaN)
          ? y[c.topFrame]
          : double.infinity;
      return cY < bestY ? c : best;
    });
  }).toList()
    ..sort((a, b) => a.yLowFrame.compareTo(b.yLowFrame));
}

// ── CSV 解析 ─────────────────────────────────────────────────────────────────

class _CsvResult {
  final List<double> speed;
  final List<double> ySmooth;  // 插值 + 平滑後的 Y（用於 Y-LOW / TOP 偵測）
  final List<double> vis;
  final double fps;
  final List<double> xNorm;    // 主導腕歸一化 X（錨點距離用，與即時錨點同空間）
  final List<double> yNorm;    // 主導腕歸一化 Y
  _CsvResult(this.speed, this.ySmooth, this.vis, this.fps,
      {List<double>? xNorm, List<double>? yNorm})
      : xNorm = xNorm ?? const [],
        yNorm = yNorm ?? const [];
}

// 左手腕 = landmark 15，右手腕 = landmark 16
// CSV 欄位：frame(0), time_sec(1), pose_update_id(2),
//           [lm0_x_norm, lm0_y_norm, lm0_z, lm0_vis, lm0_x_px, lm0_y_px] × 33  (從 col 3 開始)
// lm{i}_vis  = 3 + i*6 + 3；lm{i}_x_px = +4；lm{i}_y_px = +5
const int _colTimeSec = 1;
const int _colLwXn    = 93;   // 3 + 15*6 + 0（歸一化 x）
const int _colLwYn    = 94;
const int _colLwVis   = 96;   // 3 + 15*6 + 3
const int _colLwXpx   = 97;
const int _colLwYpx   = 98;
const int _colRwXn    = 99;   // 3 + 16*6 + 0（歸一化 x）
const int _colRwYn    = 100;
const int _colRwVis   = 102;  // 3 + 16*6 + 3
const int _colRwXpx   = 103;
const int _colRwYpx   = 104;
const double _minVisibility = 0.1;
// 手腕座標/速度平滑窗（秒）：30fps 下 ≈ 5 幀，與舊版固定值等效
const double _smoothWristSec = 0.17;

class _WristTrack {
  final List<double> x = [];
  final List<double> y = [];
  final List<double> xn = []; // 歸一化 x（錨點距離用）
  final List<double> yn = []; // 歸一化 y
  final List<bool> okMask = []; // 該禎腕點是否有效（可見），雙手判斷用
  int valid = 0;
  void add(double vis, double xpx, double ypx, [double xnorm = double.nan, double ynorm = double.nan]) {
    if (vis >= _minVisibility && !xpx.isNaN && !ypx.isNaN) {
      x.add(xpx);
      y.add(ypx);
      xn.add(xnorm);
      yn.add(ynorm);
      okMask.add(true);
      valid++;
    } else {
      x.add(double.nan);
      y.add(double.nan);
      xn.add(double.nan);
      yn.add(double.nan);
      okMask.add(false);
    }
  }
}

/// 合成「雙手一起」速度訊號：
///   ・雙手皆有效 → 兩手都在動才保留訊號；任一手明顯較慢（< 另一手 × factor）
///                   時取較小值（壓低該禎，避免單手動作成峰）
///   ・僅一手有效（遮擋）→ 退回該手速度
///   ・雙手皆無效 → 0
List<double> _combineBothHands(
  List<double> rSpeed, List<double> lSpeed,
  List<bool> rOk, List<bool> lOk,
) {
  final n = rSpeed.length;
  final out = List<double>.filled(n, 0.0);
  for (int i = 0; i < n; i++) {
    final rv = i < rOk.length && rOk[i];
    final lv = i < lOk.length && lOk[i];
    if (rv && lv) {
      // 兩手都在動才算：取較小值代表「一起」的程度
      out[i] = math.min(rSpeed[i], lSpeed[i]);
    } else if (rv) {
      out[i] = rSpeed[i];
    } else if (lv) {
      out[i] = lSpeed[i];
    } else {
      out[i] = 0.0;
    }
  }
  return out;
}

/// 插值 + 平滑 + 計算速度（px/frame）。
(List<double> speed, List<double> ySmooth) _wristSpeed(
    _WristTrack w, int smoothWin) {
  final xs = _movingAverage(_interpNan(w.x), smoothWin);
  final ys = _movingAverage(_interpNan(w.y), smoothWin);
  final speed = List<double>.filled(xs.length, 0.0);
  for (int i = 1; i < xs.length; i++) {
    final dx = xs[i] - xs[i - 1];
    final dy = ys[i] - ys[i - 1];
    speed[i] = math.sqrt(dx * dx + dy * dy);
  }
  return (_movingAverage(speed, smoothWin), ys);
}

_CsvResult? _parseWristSpeed(String csvPath, {bool bothHands = false}) {
  try {
    debugPrint('[ParseCSV] 📂 讀取: $csvPath');
    final content = File(csvPath).readAsStringSync();
    final rows    = const CsvToListConverter(eol: '\n').convert(content);
    debugPrint('[ParseCSV] 📄 ${rows.length} 行');
    if (rows.length < 3) return null;

    final data   = rows.sublist(1);
    final right  = _WristTrack();
    final left   = _WristTrack();
    final visList = <double>[];
    final times  = <double>[];

    for (final row in data) {
      if (row.length <= _colRwYpx) {
        right.add(0.0, double.nan, double.nan);
        left.add(0.0, double.nan, double.nan);
        visList.add(0.0);
        if (times.isEmpty && row.length > _colTimeSec) {
          times.add(_toDouble(row[_colTimeSec]));
        }
        continue;
      }
      final rVis = _toDouble(row[_colRwVis]);
      times.add(_toDouble(row[_colTimeSec]));
      visList.add(rVis);
      right.add(rVis, _toDouble(row[_colRwXpx]), _toDouble(row[_colRwYpx]),
          _toDouble(row[_colRwXn]), _toDouble(row[_colRwYn]));
      left.add(_toDouble(row[_colLwVis]),
          _toDouble(row[_colLwXpx]), _toDouble(row[_colLwYpx]),
          _toDouble(row[_colLwXn]), _toDouble(row[_colLwYn]));
    }

    final n = right.x.length;
    debugPrint('[ParseCSV] 有效幀: 右腕 ${right.valid}/$n, 左腕 ${left.valid}/$n');
    if (n < 2) return null;

    // FPS 估計：用總幀數 / 總時長（times 可能因短行而少於幀數）
    double fps = 30.0;
    if (times.length >= 2) {
      final dur = times.last - times.first;
      if (dur > 0) fps = (n - 1) / dur;
    }
    debugPrint('[ParseCSV] FPS: $fps');

    // 平滑窗以秒為單位換算（FPS 自適應；30fps ≈ 5 幀，與舊版等效）
    final smoothWin = _oddKernel(math.max(3, (_smoothWristSec * fps).round()));

    // 左右腕都算速度，選高百分位速度較大者（左打者主導腕為左腕）
    final (rSpeed, rY) = _wristSpeed(right, smoothWin);
    final (lSpeed, lY) = _wristSpeed(left, smoothWin);
    double p95of(List<double> s) {
      final v = s.where((e) => e.isFinite).toList()..sort();
      return v.isEmpty ? 0.0 : _percentile(v, 95.0);
    }
    final useLeft = left.valid > 0 && p95of(lSpeed) > p95of(rSpeed) * 1.15;
    if (useLeft) debugPrint('[ParseCSV] 🫲 改用左腕（速度 p95 較大，疑似左打者）');

    // Y-LOW / TOP 仍用主導手的平滑 Y（雙手判斷僅改速度訊號）
    final domY = useLeft ? lY : rY;
    // 主導腕歸一化座標（錨點距離用）：插值補洞、輕平滑
    final domXn = _movingAverage(_interpNan(useLeft ? left.xn : right.xn), smoothWin);
    final domYn = _movingAverage(_interpNan(useLeft ? left.yn : right.yn), smoothWin);

    if (bothHands) {
      final combined =
          _combineBothHands(rSpeed, lSpeed, right.okMask, left.okMask);
      debugPrint('[ParseCSV] 🤝 雙手判斷：合成兩手一起的速度訊號');
      return _CsvResult(combined, domY, visList, fps, xNorm: domXn, yNorm: domYn);
    }

    return useLeft
        ? _CsvResult(lSpeed, lY, visList, fps, xNorm: domXn, yNorm: domYn)
        : _CsvResult(rSpeed, rY, visList, fps, xNorm: domXn, yNorm: domYn);
  } catch (e) {
    debugPrint('[ParseCSV] ❌ 異常: $e');
    return null;
  }
}

double _toDouble(dynamic v) {
  if (v == null || v == '') return double.nan;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? double.nan;
}

// ── 訊號處理 ─────────────────────────────────────────────────────────────────

List<double> _interpNan(List<double> x) {
  final out = List<double>.from(x);
  final n   = out.length;
  if (n == 0) return out;

  double? first;
  for (int i = 0; i < n; i++) {
    if (!out[i].isNaN) { first = out[i]; break; }
  }
  if (first == null) return List.filled(n, 0.0);

  for (int i = 0; i < n; i++) {
    if (out[i].isNaN) {
      out[i] = first!;
    } else {
      first = out[i];
      break;
    }
  }
  int left = 0;
  for (int i = 1; i < n; i++) {
    if (!out[i].isNaN) {
      if (i - left > 1) {
        final lv = out[left], rv = out[i];
        for (int j = left + 1; j < i; j++) {
          out[j] = lv + (rv - lv) * (j - left) / (i - left);
        }
      }
      left = i;
    }
  }
  double last = out[left];
  for (int i = left + 1; i < n; i++) {
    out[i] = last;
  }
  return out;
}

List<double> _movingAverage(List<double> x, int window) {
  final w = math.max(1, window);
  if (w == 1 || x.isEmpty) return List.from(x);
  final pad = w ~/ 2;
  final out = List<double>.filled(x.length, 0.0);
  for (int i = 0; i < x.length; i++) {
    double sum = 0.0;
    int cnt = 0;
    for (int j = i - pad; j <= i + pad; j++) {
      final idx = j.clamp(0, x.length - 1);
      sum += x[idx];
      cnt++;
    }
    out[i] = sum / cnt;
  }
  return out;
}

int _toOddFrames(double sec, double fps) {
  final k = math.max(3, (sec * fps).round());
  return (k % 2 == 1) ? k : k + 1;
}

int _oddKernel(int k) {
  k = math.max(1, k);
  return (k % 2 == 1) ? k : k + 1;
}

List<double> _medianFilter(List<double> x, int kernelSize) {
  final k    = _oddKernel(kernelSize);
  final half = k ~/ 2;
  final n    = x.length;
  final out  = List<double>.filled(n, 0.0);
  for (int i = 0; i < n; i++) {
    final start  = math.max(0, i - half);
    final end    = math.min(n - 1, i + half);
    final window = x.sublist(start, end + 1)..sort();
    out[i] = window[window.length ~/ 2];
  }
  return out;
}

List<double> _denoiseSignal(List<double> raw, int medK, int smoothW, int baseK) {
  final med      = _medianFilter(raw, medK);
  final smooth   = _movingAverage(med, smoothW);
  final baseline = _medianFilter(smooth, baseK);
  return List<double>.generate(
      smooth.length, (i) => math.max(0.0, smooth[i] - baseline[i]));
}

// ── 統計工具 ─────────────────────────────────────────────────────────────────

double _percentile(List<double> sorted, double pct) {
  if (sorted.isEmpty) return 0.0;
  final idx = (pct / 100.0 * (sorted.length - 1)).round().clamp(0, sorted.length - 1);
  return sorted[idx];
}

// ── 4 階段關鍵禎偵測 ─────────────────────────────────────────────────────────

/// 準備動作禎：topFrame 前 0.5–3.0 秒窗口中，速度最小（最靜止）的禎。
int _addressFrame(List<double> speed, int topFrame, double fps) {
  final n    = speed.length;
  final lo   = math.max(0, topFrame - (3.0 * fps).round());
  final hi   = math.max(lo + 1, topFrame - (0.5 * fps).round());
  if (lo >= hi || hi > n) return math.max(0, topFrame - (1.5 * fps).round()).clamp(0, n - 1);

  int best = lo;
  for (int i = lo + 1; i < hi; i++) {
    if (!speed[i].isNaN && (speed[best].isNaN || speed[i] < speed[best])) best = i;
  }
  return best;
}

/// ⑤ 下桿中段禎：top→hit 之間「手腕 Y 行程過半」那一幀（位置中點，非時間中點）。
/// 下桿手腕由高到低（Y 由小變大），取 Y 跨越 (yTop+yHit)/2 的真實幀；
/// 失敗（端點 NaN / 無交越）退回算術中點，保證不退化、向後相容。
int _downswingFrame(List<double> y, int topFrame, int hitFrame) =>
    _yTravelHalfwayFrame(y, topFrame, hitFrame);

/// 送桿禎：hitFrame 後 0.3–2.0 秒窗口中，Y 局部最小值（手腕最高點）。
int _followThroughFrame(List<double> y, int hitFrame, double fps, int n) {
  final lo = math.min(n - 1, hitFrame + (0.3 * fps).round());
  final hi = math.min(n,     hitFrame + (2.0 * fps).round());
  if (lo >= hi) return math.min(n - 1, hitFrame + (fps * 0.7).round());

  // 尋找局部最小值（Y 最小 = 手腕最高 = 送桿頂點）
  for (int i = lo + 1; i < hi - 1; i++) {
    if (!y[i].isNaN && !y[i - 1].isNaN && !y[i + 1].isNaN &&
        y[i] <= y[i - 1] && y[i] < y[i + 1]) {
      return i;
    }
  }
  // 後備：窗口內 Y 最小的禎
  int best = lo;
  for (int i = lo + 1; i < hi; i++) {
    if (!y[i].isNaN && (y[best].isNaN || y[i] < y[best])) best = i;
  }
  return best;
}

// ── 新增：起桿 / 上桿中段 / 收桿 ──────────────────────────────────────────────

/// ② 起桿禎：addressFrame 之後到 topFrame 之前，速度首次超過低門檻。
/// 低門檻改尺度無關：max(0.4 px/frame 保底, p90×0.08)，消除解析度/拍攝距離相依
/// （px/frame 在 360p 與 1080p 差數倍 → 原寫死 0.4 在高解析度過低、誤抓起桿）。
int _takeawayFrame(List<double> speed, int addressFrame, int topFrame, double speedP90) {
  if (topFrame <= addressFrame + 2) return addressFrame;
  // 低速門檻：手開始移動。保底 0.4，並隨揮桿速度尺度等比放大。
  final lowThr = math.max(0.4, speedP90 * 0.08);
  for (int i = addressFrame + 1; i < topFrame; i++) {
    if (!speed[i].isNaN && speed[i] >= lowThr) return i;
  }
  // 後備：address 到 top 之間 1/4 處
  return addressFrame + (topFrame - addressFrame) ~/ 4;
}

/// ③ 上桿中段禎：takeaway→top 之間「手腕 Y 行程過半」那一幀（位置中點，非時間中點）。
/// 上桿手腕由低到高（Y 由大變小），取 Y 跨越中點值的真實幀；失敗退回算術中點。
int _backswingFrame(List<double> y, int takeawayFrame, int topFrame) =>
    _yTravelHalfwayFrame(y, takeawayFrame, topFrame);

/// 在 [fromFrame, toFrame] 區間找「手腕 Y 位置行程過半」那一幀：
/// target = (y[from]+y[to])/2，回傳 Y 首次跨越 target 的幀（位置中點，方向無關）。
/// 任一端點 NaN 或無交越 → 退回算術時間中點（不退化、向後相容）。
int _yTravelHalfwayFrame(List<double> y, int fromFrame, int toFrame) {
  final mid = (fromFrame + toFrame) ~/ 2;
  if (toFrame <= fromFrame + 1) return math.max(fromFrame, mid);
  final n = y.length;
  if (fromFrame < 0 || toFrame >= n) return mid;
  final yFrom = y[fromFrame], yTo = y[toFrame];
  if (yFrom.isNaN || yTo.isNaN) return mid;
  final target = (yFrom + yTo) / 2;
  for (int i = fromFrame + 1; i <= toFrame; i++) {
    final prev = y[i - 1], cur = y[i];
    if (prev.isNaN || cur.isNaN) continue;
    if ((prev - target) * (cur - target) <= 0) return i; // 跨越（含等於）
  }
  return mid;
}

/// ⑧ 收桿禎：followThroughFrame 之後，速度持續低於門檻（身體靜止）。
int _finishFrame(List<double> speed, int followThroughFrame, double fps, int n, double speedP90) {
  final lo = math.min(n - 1, followThroughFrame + (0.2 * fps).round());
  final hi = math.min(n,     followThroughFrame + (2.5 * fps).round());
  if (lo >= hi) return math.min(n - 1, lo);

  // 尋找速度持續低於門檻的起點（連續至少 3 幀）；門檻尺度無關：max(0.5 保底, p90×0.06)
  final lowThr = math.max(0.5, speedP90 * 0.06);
  const minStableFrames = 3;
  for (int i = lo; i < hi - minStableFrames; i++) {
    if (speed[i].isNaN || speed[i] >= lowThr) continue;
    bool stable = true;
    for (int j = i + 1; j < i + minStableFrames && j < hi; j++) {
      if (!speed[j].isNaN && speed[j] >= lowThr) { stable = false; break; }
    }
    if (stable) return i;
  }
  // 後備：窗口結尾
  return math.min(n - 1, hi - 1);
}

// ── 內部候選結構 ─────────────────────────────────────────────────────────────

class _HitCandidate {
  final int fastFrame;
  final int yLowFrame;
  final int topFrame;
  final double speedValue;
  const _HitCandidate({
    required this.fastFrame,
    required this.yLowFrame,
    required this.topFrame,
    required this.speedValue,
  });
}

// ── Isolate 傳參 ─────────────────────────────────────────────────────────────

class _DetectArgs {
  final String csvPath;
  final bool bothHands;
  final double? anchorX;
  final double? anchorY;
  const _DetectArgs({
    required this.csvPath,
    this.bothHands = false,
    this.anchorX,
    this.anchorY,
  });
}
