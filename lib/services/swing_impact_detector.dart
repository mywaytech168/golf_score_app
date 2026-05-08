import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart';

import '../models/swing_hit.dart';

// ──────────────────────────────────────────────────────────────────────────────
// 高爾夫揮桿撞擊偵測
// Dart port of golf_impact_detection_v3_fast.py
//
// 演算法：
//   1. 從 CSV 提取右手腕像素速度（逐幀）
//   2. 從 PCM 提取每幀 RMS 音量
//   3. 各自去噪（中值濾波 → 移動平均 → 基線扣除）
//   4. 各自找峰值（高度門檻 + 最小間距 + 顯著性）
//   5. 交集配對（速度峰 ± 0.33s 內找最近音頻峰 → hit = 平均幀）
//   6. 回傳 List<SwingHit>（含 startSec / hitSec / endSec）
// ──────────────────────────────────────────────────────────────────────────────

class SwingImpactDetector {
  // ── 片段截取範圍 ──────────────────────────────────────────────────────────
  static const double clipPreSec = 2.5;
  static const double clipPostSec = 2.5;

  // ── 峰值偵測共用參數 ──────────────────────────────────────────────────────
  static const double peakDistanceSec = 0.45;
  static const double intersectToleranceSec = 0.50;

  // ── 速度訊號參數 ──────────────────────────────────────────────────────────
  static const int _speedMedianK = 7;
  static const int _speedSmoothW = 7;
  static const int _speedBaselineK = 121;
  static const double _speedHeightPct = 92.0;
  static const double _speedMinHeight = 0.8;
  static const double _speedPromScale = 2.5;

  // ── 音頻訊號參數 ──────────────────────────────────────────────────────────
  static const int _audioMedianK = 9;
  static const int _audioSmoothW = 9;
  static const int _audioBaselineK = 71;
  static const double _audioHeightPct = 90.0;
  static const double _audioMinHeight = 0.04;
  static const double _audioPromScale = 2.0;

  /// 主入口：在 isolate 中執行，不阻塞 UI
  static Future<List<SwingHit>> detect({
    required String csvPath,
    required List<double> audioPcm,
    required int audioSampleRate,
  }) async {
    final args = _DetectArgs(
      csvPath: csvPath,
      audioPcm: audioPcm,
      audioSampleRate: audioSampleRate,
    );
    try {
      return await Isolate.run(() => _detectIsolate(args));
    } catch (e) {
      debugPrint('[SwingImpact] detect error: $e');
      return [];
    }
  }
}

// ── Isolate 入口（頂層函數） ─────────────────────────────────────────────────

List<SwingHit> _detectIsolate(_DetectArgs args) {
  // 1. 解析 CSV → 右手腕速度
  final csvResult = _parseWristSpeed(args.csvPath);
  if (csvResult == null) return [];
  final speedRaw = csvResult.speed;
  final fps = csvResult.fps;
  final n = speedRaw.length;
  if (n < 10) return [];

  // 2. PCM → 每幀 RMS 振幅
  final audioRaw = _pcmToFrameAmplitude(args.audioPcm, args.audioSampleRate, fps, n);

  // 3. 去噪
  final speedDn = _denoiseSignal(speedRaw,
      SwingImpactDetector._speedMedianK,
      SwingImpactDetector._speedSmoothW,
      SwingImpactDetector._speedBaselineK);
  final audioDn = _denoiseSignal(audioRaw,
      SwingImpactDetector._audioMedianK,
      SwingImpactDetector._audioSmoothW,
      SwingImpactDetector._audioBaselineK);

  // 4. 找峰值
  final speedPeaks = _findPeaks(speedDn, fps,
      distanceSec: SwingImpactDetector.peakDistanceSec,
      heightPct: SwingImpactDetector._speedHeightPct,
      minHeight: SwingImpactDetector._speedMinHeight,
      promScale: SwingImpactDetector._speedPromScale);
  final audioPeaks = _findPeaks(audioDn, fps,
      distanceSec: SwingImpactDetector.peakDistanceSec,
      heightPct: SwingImpactDetector._audioHeightPct,
      minHeight: SwingImpactDetector._audioMinHeight,
      promScale: SwingImpactDetector._audioPromScale);

  // 5. 配對：有音頻峰值就交集，否則直接用速度峰值
  if (audioPeaks.isEmpty) {
    return _speedOnlyHits(speedPeaks, speedDn, fps, n);
  }
  return _intersectPeaks(
      speedPeaks, audioPeaks, speedDn, audioDn, fps, n);
}

// ── CSV 解析 ─────────────────────────────────────────────────────────────────

class _CsvResult {
  final List<double> speed;
  final double fps;
  _CsvResult(this.speed, this.fps);
}

// 右手腕 = landmark 16
// CSV 欄位順序：frame, time_sec, [lm0_x_norm, lm0_y_norm, lm0_z, lm0_vis, lm0_x_px, lm0_y_px] × 33
// lm16_x_px 欄位 = 2 + 16*6 + 4 = 102
// lm16_y_px 欄位 = 2 + 16*6 + 5 = 103
// lm16_visibility 欄位 = 2 + 16*6 + 3 = 101
const int _colTimeSec = 1;
const int _colRwVis = 101;
const int _colRwXpx = 102;
const int _colRwYpx = 103;
const double _minVisibility = 0.2;
const int _smoothWrist = 5;

_CsvResult? _parseWristSpeed(String csvPath) {
  try {
    final content = File(csvPath).readAsStringSync();
    final rows = const CsvToListConverter(eol: '\n').convert(content);
    if (rows.length < 3) return null; // header + at least 2 data rows

    final data = rows.sublist(1); // skip header
    final xList = <double>[];
    final yList = <double>[];
    final times = <double>[];

    for (final row in data) {
      if (row.length <= _colRwYpx) {
        xList.add(double.nan);
        yList.add(double.nan);
        if (times.isEmpty && row.length > _colTimeSec) {
          times.add(_toDouble(row[_colTimeSec]));
        }
        continue;
      }
      final vis = _toDouble(row[_colRwVis]);
      final xpx = _toDouble(row[_colRwXpx]);
      final ypx = _toDouble(row[_colRwYpx]);
      final t = _toDouble(row[_colTimeSec]);
      times.add(t);
      if (vis >= _minVisibility && !xpx.isNaN && !ypx.isNaN) {
        xList.add(xpx);
        yList.add(ypx);
      } else {
        xList.add(double.nan);
        yList.add(double.nan);
      }
    }

    if (xList.length < 2) return null;

    // 估計 FPS
    double fps = 30.0;
    if (times.length >= 2) {
      final dur = times.last - times.first;
      if (dur > 0) fps = (times.length - 1) / dur;
    }

    // 插值 NaN
    final x = _interpNan(xList);
    final y = _interpNan(yList);

    // 移動平均平滑
    final xs = _movingAverage(x, _smoothWrist);
    final ys = _movingAverage(y, _smoothWrist);

    // 逐幀速度
    final speed = List<double>.filled(xs.length, 0.0);
    for (int i = 1; i < xs.length; i++) {
      final dx = xs[i] - xs[i - 1];
      final dy = ys[i] - ys[i - 1];
      speed[i] = math.sqrt(dx * dx + dy * dy);
    }
    final speedSmooth = _movingAverage(speed, _smoothWrist);
    return _CsvResult(speedSmooth, fps);
  } catch (e) {
    return null;
  }
}

double _toDouble(dynamic v) {
  if (v == null || v == '') return double.nan;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? double.nan;
}

// ── 音頻振幅 ─────────────────────────────────────────────────────────────────

List<double> _pcmToFrameAmplitude(
    List<double> pcm, int sampleRate, double fps, int numFrames) {
  if (pcm.isEmpty || numFrames <= 0) return List.filled(numFrames, 0.0);
  final samplesPerFrame = sampleRate / fps;
  final result = List<double>.filled(numFrames, 0.0);
  for (int f = 0; f < numFrames; f++) {
    final start = (f * samplesPerFrame).round();
    final end = math.min(((f + 1) * samplesPerFrame).round(), pcm.length);
    if (start >= end || start >= pcm.length) continue;
    double sumSq = 0.0;
    for (int i = start; i < end; i++) {
      sumSq += pcm[i] * pcm[i];
    }
    result[f] = math.sqrt(sumSq / (end - start));
  }
  return result;
}

// ── 訊號處理 ─────────────────────────────────────────────────────────────────

List<double> _interpNan(List<double> x) {
  final out = List<double>.from(x);
  final n = out.length;
  // 前向填充首段 NaN
  double? first;
  for (int i = 0; i < n; i++) {
    if (!out[i].isNaN) { first = out[i]; break; }
  }
  if (first == null) return out;
  for (int i = 0; i < n; i++) {
    if (out[i].isNaN) { out[i] = first!; }
    else { first = out[i]; break; }
  }
  // 線性插值中間段
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
  // 後向填充尾段 NaN
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

int _oddKernel(int k) {
  k = math.max(1, k);
  return (k % 2 == 1) ? k : k + 1;
}

List<double> _medianFilter(List<double> x, int kernelSize) {
  final k = _oddKernel(kernelSize);
  final half = k ~/ 2;
  final n = x.length;
  final out = List<double>.filled(n, 0.0);
  for (int i = 0; i < n; i++) {
    final start = math.max(0, i - half);
    final end = math.min(n - 1, i + half);
    final window = x.sublist(start, end + 1).toList()..sort();
    out[i] = window[window.length ~/ 2];
  }
  return out;
}

List<double> _denoiseSignal(List<double> raw, int medK, int smoothW, int baseK) {
  final med = _medianFilter(raw, medK);
  final smooth = _movingAverage(med, smoothW);
  final baseline = _medianFilter(smooth, baseK);
  return List<double>.generate(
      smooth.length, (i) => math.max(0.0, smooth[i] - baseline[i]));
}

// ── 峰值偵測 ─────────────────────────────────────────────────────────────────

double _percentile(List<double> sorted, double pct) {
  if (sorted.isEmpty) return 0.0;
  final idx = (pct / 100.0 * (sorted.length - 1)).round().clamp(0, sorted.length - 1);
  return sorted[idx];
}

double _median(List<double> sorted) {
  if (sorted.isEmpty) return 0.0;
  return sorted[sorted.length ~/ 2];
}

List<int> _findPeaks(
  List<double> x,
  double fps, {
  required double distanceSec,
  required double heightPct,
  required double minHeight,
  required double promScale,
}) {
  final n = x.length;
  if (n < 3) return [];

  final sorted = [...x]..sort();
  final heightThresh = math.max(_percentile(sorted, heightPct), minHeight);
  final med = _median(sorted);
  final absDevs = x.map((v) => (v - med).abs()).toList()..sort();
  final mad = _median(absDevs) + 1e-6;
  final maxVal = sorted.last;
  final promThresh = math.max(promScale * mad, 0.05 * maxVal);

  final minDist = math.max(1, (distanceSec * fps).round());

  // 找局部極大值（≥ 高度門檻）
  final candidates = <int>[];
  for (int i = 1; i < n - 1; i++) {
    if (x[i] >= heightThresh && x[i] > x[i - 1] && x[i] > x[i + 1]) {
      candidates.add(i);
    }
  }
  if (candidates.isEmpty) return [];

  // 最小距離過濾：依高度降序貪心選取
  final byHeight = [...candidates]..sort((a, b) => x[b].compareTo(x[a]));
  final selected = <int>{};
  for (final c in byHeight) {
    if (selected.any((p) => (p - c).abs() < minDist)) continue;
    selected.add(c);
  }

  // 按位置排序
  final sorted2 = selected.toList()..sort();

  // 顯著性過濾（峰值 - 兩側谷值最大值 ≥ promThresh）
  return sorted2.where((p) {
    final lStart = math.max(0, p - minDist);
    final rEnd = math.min(n - 1, p + minDist);
    final lSlice = x.sublist(lStart, p);
    final rSlice = x.sublist(p + 1, rEnd + 1);
    if (lSlice.isEmpty || rSlice.isEmpty) return false;
    final leftMin = lSlice.reduce(math.min);
    final rightMin = rSlice.reduce(math.min);
    final prom = x[p] - math.max(leftMin, rightMin);
    return prom >= promThresh;
  }).toList();
}

// ── 峰值交集配對 ──────────────────────────────────────────────────────────────

List<SwingHit> _intersectPeaks(
  List<int> speedPeaks,
  List<int> audioPeaks,
  List<double> speedSig,
  List<double> audioSig,
  double fps,
  int totalFrames,
) {
  final tol = math.max(1, (SwingImpactDetector.intersectToleranceSec * fps).round());
  final audioUsed = <int>{};
  final matches = <SwingHit>[];

  for (final s in speedPeaks) {
    final candidates = audioPeaks
        .where((a) => (a - s).abs() <= tol && !audioUsed.contains(a))
        .toList();
    if (candidates.isEmpty) continue;
    final a = candidates.reduce((best, c) =>
        (c - s).abs() < (best - s).abs() ? c : best);
    audioUsed.add(a);

    final hitFrame = ((s + a) / 2).round();
    final hitSec = hitFrame / fps;
    final startSec = math.max(0.0, hitSec - SwingImpactDetector.clipPreSec);
    final endSec = math.min(
        totalFrames / fps, hitSec + SwingImpactDetector.clipPostSec);

    matches.add(SwingHit(
      hitIndex: 0,
      hitFrame: hitFrame,
      hitSec: hitSec,
      startSec: startSec,
      endSec: endSec,
      speedValue: speedSig[s],
      audioValue: audioSig[a],
    ));
  }

  matches.sort((a, b) => a.hitFrame.compareTo(b.hitFrame));
  return List.generate(
      matches.length,
      (i) => SwingHit(
            hitIndex: i + 1,
            hitFrame: matches[i].hitFrame,
            hitSec: matches[i].hitSec,
            startSec: matches[i].startSec,
            endSec: matches[i].endSec,
            speedValue: matches[i].speedValue,
            audioValue: matches[i].audioValue,
          ));
}

// ── 純速度偵測（音頻不可用時的後備模式） ────────────────────────────────────────

List<SwingHit> _speedOnlyHits(
  List<int> speedPeaks,
  List<double> speedSig,
  double fps,
  int totalFrames,
) {
  final matches = <SwingHit>[];
  for (final s in speedPeaks) {
    final hitSec = s / fps;
    final startSec = math.max(0.0, hitSec - SwingImpactDetector.clipPreSec);
    final endSec = math.min(totalFrames / fps, hitSec + SwingImpactDetector.clipPostSec);
    matches.add(SwingHit(
      hitIndex: 0,
      hitFrame: s,
      hitSec: hitSec,
      startSec: startSec,
      endSec: endSec,
      speedValue: speedSig[s],
      audioValue: 0.0,
    ));
  }
  matches.sort((a, b) => a.hitFrame.compareTo(b.hitFrame));
  return List.generate(
      matches.length,
      (i) => SwingHit(
            hitIndex: i + 1,
            hitFrame: matches[i].hitFrame,
            hitSec: matches[i].hitSec,
            startSec: matches[i].startSec,
            endSec: matches[i].endSec,
            speedValue: matches[i].speedValue,
            audioValue: matches[i].audioValue,
          ));
}

// ── Isolate 傳參 ─────────────────────────────────────────────────────────────

class _DetectArgs {
  final String csvPath;
  final List<double> audioPcm;
  final int audioSampleRate;
  const _DetectArgs({
    required this.csvPath,
    required this.audioPcm,
    required this.audioSampleRate,
  });
}
