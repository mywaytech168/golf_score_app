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
  static Future<List<SwingHit>> detect({
    required String csvPath,
  }) async {
    final args = _DetectArgs(
      csvPath: csvPath,
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
  final csvResult = _parseWristSpeed(args.csvPath);
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

  // 6. 每個 FAST → Y-LOW → TOP
  final candidates = <_HitCandidate>[];
  for (final fast in fastCenters) {
    final yLow = _nearestYLowFrame(ySmooth, fast, fps);
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
  _CsvResult(this.speed, this.ySmooth, this.vis, this.fps);
}

// 右手腕 = landmark 16
// CSV 欄位：frame(0), time_sec(1), pose_update_id(2),
//           [lm0_x_norm, lm0_y_norm, lm0_z, lm0_vis, lm0_x_px, lm0_y_px] × 33  (從 col 3 開始)
// lm16_vis   = 3 + 16*6 + 3 = 102
// lm16_x_px  = 3 + 16*6 + 4 = 103
// lm16_y_px  = 3 + 16*6 + 5 = 104
const int _colTimeSec = 1;
const int _colRwVis   = 102;
const int _colRwXpx   = 103;
const int _colRwYpx   = 104;
const double _minVisibility = 0.1;
const int    _smoothWrist   = 5;

_CsvResult? _parseWristSpeed(String csvPath) {
  try {
    debugPrint('[ParseCSV] 📂 讀取: $csvPath');
    final content = File(csvPath).readAsStringSync();
    final rows    = const CsvToListConverter(eol: '\n').convert(content);
    debugPrint('[ParseCSV] 📄 ${rows.length} 行');
    if (rows.length < 3) return null;

    final data   = rows.sublist(1);
    final xList  = <double>[];
    final yList  = <double>[];
    final visList = <double>[];
    final times  = <double>[];
    int validCount = 0;

    for (final row in data) {
      if (row.length <= _colRwYpx) {
        xList.add(double.nan);
        yList.add(double.nan);
        visList.add(0.0);
        if (times.isEmpty && row.length > _colTimeSec) {
          times.add(_toDouble(row[_colTimeSec]));
        }
        continue;
      }
      final vis = _toDouble(row[_colRwVis]);
      final xpx = _toDouble(row[_colRwXpx]);
      final ypx = _toDouble(row[_colRwYpx]);
      final t   = _toDouble(row[_colTimeSec]);
      times.add(t);
      visList.add(vis);
      if (vis >= _minVisibility && !xpx.isNaN && !ypx.isNaN) {
        xList.add(xpx);
        yList.add(ypx);
        validCount++;
      } else {
        xList.add(double.nan);
        yList.add(double.nan);
      }
    }

    debugPrint('[ParseCSV] 有效幀: $validCount/${xList.length}');
    if (xList.length < 2) return null;

    // FPS 估計：用總幀數 / 總時長（times 可能因短行而少於 xList.length）
    double fps = 30.0;
    if (times.length >= 2) {
      final dur = times.last - times.first;
      if (dur > 0) fps = (xList.length - 1) / dur;
    }
    debugPrint('[ParseCSV] FPS: $fps');

    // 插值 + 平滑（用於速度計算）
    final x  = _interpNan(xList);
    final y  = _interpNan(yList);
    final xs = _movingAverage(x, _smoothWrist);
    final ys = _movingAverage(y, _smoothWrist);

    // 速度（px/frame）
    final speed = List<double>.filled(xs.length, 0.0);
    for (int i = 1; i < xs.length; i++) {
      final dx = xs[i] - xs[i - 1];
      final dy = ys[i] - ys[i - 1];
      speed[i] = math.sqrt(dx * dx + dy * dy);
    }
    final speedSmooth = _movingAverage(speed, _smoothWrist);

    return _CsvResult(speedSmooth, ys, visList, fps);
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
  const _DetectArgs({
    required this.csvPath,
  });
}
