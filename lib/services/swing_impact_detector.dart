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
//   1. 從 CSV 提取右手腕像素速度（逐幀），並計算實際 FPS
//   2. 從 PCM 提取每幀 RMS 音量
//   3. 各自去噪（中值濾波 → 移動平均 → 基線扣除）
//   4. 各自找峰值（高度門檻 + 最小間距 + 顯著性）
//   5. 有音頻峰值時交集配對；無音頻時純速度後備
//   6. 回傳 List<SwingHit>（含 startSec / hitSec / endSec）
//
// ── FPS 自適應 ────────────────────────────────────────────────────────────────
// Python 原版逐幀處理（~30fps），Dart 有兩條路：
//   即時錄影  ~10fps（CameraAwesome maxFramesPerSecond:10）
//   影片匯入  ~15fps（67ms 取幀）
// 所有 kernel 參數改以「秒」表示，runtime 根據 CSV 實際 FPS 換算成幀數，
// 確保三種路徑的時間窗口一致。
// ──────────────────────────────────────────────────────────────────────────────

class SwingImpactDetector {
  // ── 片段截取範圍 ──────────────────────────────────────────────────────────
  // 改為動態：clip 總長固定 5 秒，以擊球點為中心
  static const double clipTotalDuration = 5.0;  // 總長 5 秒
  // clipPreSec 和 clipPostSec 廢棄（保留向後兼容但不使用）
  @Deprecated('改用 clipTotalDuration + 動態計算')
  static const double clipPreSec = 2.5;
  @Deprecated('改用 clipTotalDuration + 動態計算')
  static const double clipPostSec = 2.5;

  // ── 峰值偵測共用參數（秒為單位，FPS 無關）────────────────────────────────
  static const double peakDistanceSec = 0.45;
  static const double intersectToleranceSec = 0.40;

  // ── 速度訊號參數（時間秒，對應 Python 原版 ~30fps 下的 kernel 尺寸）──────
  // speedMedianSec  = 7/30 ≈ 0.23s
  // speedSmoothSec  = 7/30 ≈ 0.23s
  // speedBaselineSec= 121/30 ≈ 4.0s
  static const double _speedMedianSec = 0.23;
  static const double _speedSmoothSec = 0.23;
  static const double _speedBaselineSec = 4.0;
  static const double _speedHeightPct = 92.0;
  static const double _speedMinHeight = 0.8;
  static const double _speedPromScale = 2.5;

  // ── 音頻訊號參數（時間秒，對應 Python 原版 ~30fps 下的 kernel 尺寸）──────
  // audioMedianSec  = 9/30  = 0.30s
  // audioSmoothSec  = 9/30  = 0.30s
  // audioBaselineSec= 151/30 ≈ 5.0s
  static const double _audioMedianSec = 0.30;
  static const double _audioSmoothSec = 0.30;
  static const double _audioBaselineSec = 5.0;
  static const double _audioHeightPct = 90.0;
  static const double _audioMinHeight = 0.04;
  static const double _audioPromScale = 2.0;

  /// 動態計算 clip 的起點和終點，使擊球點成為 clip 中間
  /// 
  /// @param hitSec 擊球時間（秒）
  /// @param totalDurationSec 總視頻長度（秒）
  /// @return (startSec, endSec) 元組
  static (double, double) calculateClipBoundaries({
    required double hitSec,
    required double totalDurationSec,
  }) {
    final halfDuration = clipTotalDuration / 2;  // 2.5 秒
    
    // 理想情況：以擊球點為中心，前後各 2.5 秒
    var startSec = hitSec - halfDuration;
    var endSec = hitSec + halfDuration;
    
    // 邊界調整：如果觸及影片邊界，反向調整
    if (startSec < 0.0) {
      // 觸及開始邊界 → 向後延伸
      startSec = 0.0;
      endSec = math.min(totalDurationSec, clipTotalDuration);
    } else if (endSec > totalDurationSec) {
      // 觸及結束邊界 → 向前退縮
      endSec = totalDurationSec;
      startSec = math.max(0.0, totalDurationSec - clipTotalDuration);
    }
    
    return (startSec, endSec);
  }

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
  debugPrint('[SwingDetect] 🔍 開始隔離檢測...');
  
  // 1. 解析 CSV → 右手腕速度（同時取得實際 FPS）
  final csvResult = _parseWristSpeed(args.csvPath);
  if (csvResult == null) {
    debugPrint('[SwingDetect] ❌ CSV 解析失敗');
    return [];
  }
  final speedRaw = csvResult.speed;
  final fps = csvResult.fps;
  final n = speedRaw.length;
  final xRaw = csvResult.x;
  final yRaw = csvResult.y;
  final vis = csvResult.vis;
  
  debugPrint('[SwingDetect] 📊 CSV 統計: $n 幀, FPS=$fps, 速度範圍=[${speedRaw.reduce((a, b) => a < b ? a : b).toStringAsFixed(2)}, ${speedRaw.reduce((a, b) => a > b ? a : b).toStringAsFixed(2)}]');
  
  if (n < 10) {
    debugPrint('[SwingDetect] ❌ 幀數過少: $n < 10');
    return [];
  }

  // 根據實際 FPS 換算 kernel 幀數（確保奇數且 >= 3）
  final speedMk  = _toOddFrames(SwingImpactDetector._speedMedianSec,   fps);
  final speedSw  = _toOddFrames(SwingImpactDetector._speedSmoothSec,   fps);
  final speedBk  = _toOddFrames(SwingImpactDetector._speedBaselineSec, fps);
  final audioMk  = _toOddFrames(SwingImpactDetector._audioMedianSec,   fps);
  final audioSw  = _toOddFrames(SwingImpactDetector._audioSmoothSec,   fps);
  final audioBk  = _toOddFrames(SwingImpactDetector._audioBaselineSec, fps);

  // 2. PCM → 每幀 RMS 振幅
  final audioRaw = _pcmToFrameAmplitude(args.audioPcm, args.audioSampleRate, fps, n);
  final audioRawValid = audioRaw.where((v) => !v.isNaN).toList();
  debugPrint('[SwingDetect] 🔊 音訊統計: ${args.audioPcm.length} 樣本 @ ${args.audioSampleRate}Hz → $n 幀');
  if (audioRawValid.isNotEmpty) {
    debugPrint('[SwingDetect] 🔊 音訊幅度範圍: [${audioRawValid.reduce((a, b) => a < b ? a : b).toStringAsFixed(4)}, ${audioRawValid.reduce((a, b) => a > b ? a : b).toStringAsFixed(4)}]');
  } else {
    debugPrint('[SwingDetect] 🔊 音訊幅度範圍: [無效數據]');
  }

  // 3. 去噪
  final speedDn = _denoiseSignal(speedRaw, speedMk, speedSw, speedBk);
  final audioDn = _denoiseSignal(audioRaw, audioMk, audioSw, audioBk);
  
  // 安全的 min/max（過濾 NaN）
  final speedValid = speedDn.where((v) => !v.isNaN).toList();
  final audioValid = audioDn.where((v) => !v.isNaN).toList();
  
  if (speedValid.isEmpty) {
    debugPrint('[SwingDetect] ❌ 去噪後速度全是 NaN，無法繼續');
    return [];
  }
  
  final speedMinMax = speedValid.isEmpty 
      ? [0.0, 0.0]
      : [speedValid.reduce((a, b) => a < b ? a : b), speedValid.reduce((a, b) => a > b ? a : b)];
  final audioMinMax = audioValid.isEmpty
      ? [0.0, 0.0]
      : [audioValid.reduce((a, b) => a < b ? a : b), audioValid.reduce((a, b) => a > b ? a : b)];
  
  debugPrint('[SwingDetect] 📉 去噪後 - 速度: [${speedMinMax[0].toStringAsFixed(2)}, ${speedMinMax[1].toStringAsFixed(2)}], 有效值 ${speedValid.length}/${speedDn.length}');
  debugPrint('[SwingDetect] 📉 去噪後 - 音訊: [${audioMinMax[0].toStringAsFixed(4)}, ${audioMinMax[1].toStringAsFixed(4)}], 有效值 ${audioValid.length}/${audioDn.length}]');

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

  debugPrint('[SwingDetect] 📍 速度峰值: ${speedPeaks.length} 個');
  debugPrint('[SwingDetect] 📍 音訊峰值: ${audioPeaks.length} 個');
  if (speedPeaks.isNotEmpty) {
    debugPrint('[SwingDetect]   速度峰值幀: $speedPeaks');
  }
  if (audioPeaks.isNotEmpty) {
    debugPrint('[SwingDetect]   音訊峰值幀: $audioPeaks');
    
    // 🔍 診斷：音訊峰值位置的骨架信息
    if (speedPeaks.isEmpty) {
      debugPrint('[SwingDetect] 🔍 診斷：音訊峰值位置的骨架數據');
      for (final audioFrame in audioPeaks) {
        if (audioFrame >= 0 && audioFrame < n) {
          final windowStart = (audioFrame - 2).clamp(0, n - 1);
          final windowEnd = (audioFrame + 3).clamp(0, n);
          
          debugPrint('[SwingDetect] 🎯 音訊峰值 #$audioFrame (時間: ${(audioFrame / fps).toStringAsFixed(2)}s):');
          for (int i = windowStart; i < windowEnd; i++) {
            final marker = i == audioFrame ? '→' : ' ';
            debugPrint('[SwingDetect] $marker 幀 $i: 速度=${speedRaw[i].toStringAsFixed(3)}, 位置=(${xRaw[i].toStringAsFixed(1)}, ${yRaw[i].toStringAsFixed(1)}), 信心=${vis[i].toStringAsFixed(3)}, 幅度=${audioDn[i].toStringAsFixed(4)}');
          }
        }
      }
    }
  }

  // 5. 配對：有音頻峰值就交集，否則純速度後備
  if (audioPeaks.isEmpty) {
    debugPrint('[SwingDetect] ⚠️ 無音訊峰值，使用純速度檢測');
    return _speedOnlyHits(speedPeaks, speedDn, fps, n);
  }
  final result = _intersectPeaks(speedPeaks, audioPeaks, speedDn, audioDn, fps, n);
  debugPrint('[SwingDetect] ✅ 最終檢測結果: ${result.length} 個擊球');
  return result;
}

// ── CSV 解析 ─────────────────────────────────────────────────────────────────

class _CsvResult {
  final List<double> speed;
  final List<double> x;
  final List<double> y;
  final List<double> vis;
  final double fps;
  _CsvResult(this.speed, this.x, this.y, this.vis, this.fps);
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
const double _minVisibility = 0.1;  // 降低到 0.1 以捕捉更多幀
const int _smoothWrist = 5;

_CsvResult? _parseWristSpeed(String csvPath) {
  try {
    debugPrint('[ParseCSV] 📂 讀取 CSV: $csvPath');
    final content = File(csvPath).readAsStringSync();
    final rows = const CsvToListConverter(eol: '\n').convert(content);
    debugPrint('[ParseCSV] 📄 CSV 行數: ${rows.length}');
    
    if (rows.length < 3) {
      debugPrint('[ParseCSV] ❌ CSV 行數不足: ${rows.length} < 3');
      return null;
    }

    final data = rows.sublist(1); // skip header
    final xList = <double>[];
    final yList = <double>[];
    final visList = <double>[];
    final times = <double>[];

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
      final t = _toDouble(row[_colTimeSec]);
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

    debugPrint('[ParseCSV] 📊 有效幀: $validCount/${xList.length} (可見度 ≥ $_minVisibility)');
    
    if (xList.length < 2) {
      debugPrint('[ParseCSV] ❌ 無有效座標');
      return null;
    }
    
    // 診斷：檢查 NaN 分佈
    int nanCount = xList.where((v) => v.isNaN).length;
    debugPrint('[ParseCSV] 🔍 x 座標 NaN 數: $nanCount/${xList.length}');

    // 估計 FPS
    double fps = 30.0;
    if (times.length >= 2) {
      final dur = times.last - times.first;
      if (dur > 0) fps = (times.length - 1) / dur;
    }
    debugPrint('[ParseCSV] ⏱️ 估計 FPS: $fps');

    // 插值 NaN
    final x = _interpNan(xList);
    final y = _interpNan(yList);
    
    // 檢查插值後是否還有 NaN（不應該有）
    if (x.any((v) => v.isNaN) || y.any((v) => v.isNaN)) {
      debugPrint('[ParseCSV] ⚠️ 警告：插值後仍有 NaN 值');
    }

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
    
    // 檢查速度是否包含 NaN（診斷用）
    final speedNanCount = speed.where((v) => v.isNaN).length;
    if (speedNanCount > 0) {
      debugPrint('[ParseCSV] ⚠️ 速度中有 NaN: $speedNanCount/${speed.length}');
    }
    
    final speedSmooth = _movingAverage(speed, _smoothWrist);
    
    // 二次 NaN 檢查
    final speedSmoothedNanCount = speedSmooth.where((v) => v.isNaN).length;
    if (speedSmoothedNanCount > 0) {
      debugPrint('[ParseCSV] ❌ 平滑後仍有 NaN: $speedSmoothedNanCount/${speedSmooth.length}');
    }
    
    debugPrint('[ParseCSV] ✅ 速度計算完成: ${speedSmooth.length} 幀');
    
    return _CsvResult(speedSmooth, xList, yList, visList, fps);
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

// ── 音頻振幅 ─────────────────────────────────────────────────────────────────

List<double> _pcmToFrameAmplitude(
    List<double> pcm, int sampleRate, double fps, int numFrames) {
  if (pcm.isEmpty || numFrames <= 0) return List.filled(numFrames, 0.0);

  // 將 PCM 裁剪到 CSV 時長對應的樣本數
  // audio_extractor 提取的音軌有時比影片長（編碼後的音軌長度 ≠ 影片長度）
  // 只取 [0, csvDurationSec] 範圍的 PCM，確保每幀 RMS 與 CSV 幀對齊
  final csvDurationSec = numFrames / fps;
  final expectedSamples = (csvDurationSec * sampleRate).round();
  final effectivePcm = pcm.length > expectedSamples
      ? pcm.sublist(0, expectedSamples)
      : pcm;

  final samplesPerFrame = sampleRate / fps;
  final result = List<double>.filled(numFrames, 0.0);
  for (int f = 0; f < numFrames; f++) {
    final start = (f * samplesPerFrame).round();
    final end = math.min(((f + 1) * samplesPerFrame).round(), effectivePcm.length);
    if (start >= end || start >= effectivePcm.length) continue;
    double sumSq = 0.0;
    for (int i = start; i < end; i++) {
      sumSq += effectivePcm[i] * effectivePcm[i];
    }
    result[f] = math.sqrt(sumSq / (end - start));
  }

  // 全局正規化：對齊 Python 版 amps /= max(amps)
  // Python 將振幅縮放到 [0,1]，AUDIO_MIN_HEIGHT=0.04 才有意義（最大值的 4%）
  // 未正規化時原始 RMS 通常在 0.001~0.05，min_height 會直接等於或超過最大值
  final mx = result.reduce(math.max);
  if (mx > 1e-8) {
    for (int i = 0; i < result.length; i++) {
      result[i] /= mx;
    }
  }
  return result;
}

// ── 訊號處理 ─────────────────────────────────────────────────────────────────

List<double> _interpNan(List<double> x) {
  final out = List<double>.from(x);
  final n = out.length;
  if (n == 0) return out;
  
  // 前向填充首段 NaN
  double? first;
  for (int i = 0; i < n; i++) {
    if (!out[i].isNaN) { first = out[i]; break; }
  }
  
  // 如果沒有找到有效值，使用 0.0 作為備用
  if (first == null) {
    for (int i = 0; i < n; i++) {
      out[i] = 0.0;
    }
    return out;
  }
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

/// 將秒數轉換為幀數，並確保結果為奇數且 >= 3
int _toOddFrames(double sec, double fps) {
  final k = math.max(3, (sec * fps).round());
  return (k % 2 == 1) ? k : k + 1;
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
    final totalDurationSec = totalFrames / fps;
    final (startSec, endSec) = SwingImpactDetector.calculateClipBoundaries(
      hitSec: hitSec,
      totalDurationSec: totalDurationSec,
    );

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
    final totalDurationSec = totalFrames / fps;
    final (startSec, endSec) = SwingImpactDetector.calculateClipBoundaries(
      hitSec: hitSec,
      totalDurationSec: totalDurationSec,
    );
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
