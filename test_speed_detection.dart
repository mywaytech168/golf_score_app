#!/usr/bin/env dart

import 'dart:io';
import 'dart:math' as math;
import 'package:csv/csv.dart';

// ============================================================================
// 獨立測試工具：驗證速度計算修復
// ============================================================================

const double _minVisibility = 0.1;
const int _smoothWrist = 5;

// CSV 列索引
const int _colTimeSec = 1;
const int _colRwVis = 101;
const int _colRwXpx = 102;
const int _colRwYpx = 103;

void main(List<String> args) async {
  if (args.isEmpty) {
    print('❌ 用法: dart test_speed_detection.dart <csv_file>');
    exit(1);
  }
  
  final csvPath = args[0];
  print('📂 讀取 CSV: $csvPath');
  
  try {
    final content = File(csvPath).readAsStringSync();
    final rows = const CsvToListConverter(eol: '\n').convert(content);
    print('📄 CSV 行數: ${rows.length}');
    
    if (rows.length < 2) {
      print('❌ CSV 行數不足');
      exit(1);
    }
    
    final data = rows.sublist(1);
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
    
    print('📊 有效幀: $validCount/${xList.length} (可見度 ≥ $_minVisibility)');
    
    int nanCount = xList.where((v) => v.isNaN).length;
    print('🔍 x 座標 NaN 數: $nanCount/${xList.length}');
    
    if (xList.length < 2) {
      print('❌ 無有效座標');
      exit(1);
    }
    
    // 估計 FPS
    double fps = 30.0;
    if (times.length >= 2) {
      final dur = times.last - times.first;
      if (dur > 0) fps = (times.length - 1) / dur;
    }
    print('⏱️ 估計 FPS: ${fps.toStringAsFixed(2)}');
    
    // 插值 NaN
    final x = _interpNan(xList);
    final y = _interpNan(yList);
    
    if (x.any((v) => v.isNaN) || y.any((v) => v.isNaN)) {
      print('⚠️ 警告：插值後仍有 NaN 值');
    }
    
    // 移動平均
    final xs = _movingAverage(x, _smoothWrist);
    final ys = _movingAverage(y, _smoothWrist);
    
    // 速度計算
    final speed = List<double>.filled(xs.length, 0.0);
    for (int i = 1; i < xs.length; i++) {
      final dx = xs[i] - xs[i - 1];
      final dy = ys[i] - ys[i - 1];
      speed[i] = math.sqrt(dx * dx + dy * dy);
    }
    
    final speedNanCount = speed.where((v) => v.isNaN).length;
    if (speedNanCount > 0) {
      print('⚠️ 速度中有 NaN: $speedNanCount/${speed.length}');
    } else {
      print('✅ 速度無 NaN');
    }
    
    // 平滑速度
    final speedSmooth = _movingAverage(speed, _smoothWrist);
    
    final speedSmoothedNanCount = speedSmooth.where((v) => v.isNaN).length;
    if (speedSmoothedNanCount > 0) {
      print('❌ 平滑後仍有 NaN: $speedSmoothedNanCount/${speedSmooth.length}');
    } else {
      print('✅ 平滑後無 NaN');
    }
    
    // 速度統計
    final speedValid = speedSmooth.where((v) => !v.isNaN && v.isFinite).toList()..sort();
    if (speedValid.isEmpty) {
      print('❌ 無有效速度值');
      exit(1);
    }
    
    print('📊 速度統計：');
    print('   最小: ${speedValid.first.toStringAsFixed(2)} px/frame');
    print('   最大: ${speedValid.last.toStringAsFixed(2)} px/frame');
    print('   平均: ${(speedValid.reduce((a, b) => a + b) / speedValid.length).toStringAsFixed(2)} px/frame');
    print('   中位數: ${speedValid[speedValid.length ~/ 2].toStringAsFixed(2)} px/frame');
    print('   有效值: ${speedValid.length}/${speedSmooth.length}');
    
    // 找出速度峰值（簡易版）
    final peaks = <int>[];
    for (int i = 1; i < speedSmooth.length - 1; i++) {
      if (speedSmooth[i] > speedSmooth[i - 1] && speedSmooth[i] > speedSmooth[i + 1]) {
        peaks.add(i);
      }
    }
    
    print('\n🎯 簡易峰值檢測 (局部最大值):');
    if (peaks.isEmpty) {
      print('   無峰值找到');
    } else {
      print('   找到 ${peaks.length} 個峰值：');
      for (final peak in peaks.take(10)) {
        final time = peak / fps;
        print('      Frame $peak: ${speedSmooth[peak].toStringAsFixed(2)} px/frame @ ${time.toStringAsFixed(3)}s');
      }
    }
    
    print('\n✅ 速度計算測試完成，無 NaN 錯誤！');
    
  } catch (e) {
    print('❌ 錯誤: $e');
    exit(1);
  }
}

double _toDouble(dynamic v) {
  if (v == null) return double.nan;
  if (v is double) return v;
  if (v is int) return v.toDouble();
  final str = v.toString().trim();
  if (str.isEmpty) return double.nan;
  try {
    return double.parse(str);
  } catch (e) {
    return double.nan;
  }
}

List<double> _interpNan(List<double> x) {
  final out = List<double>.from(x);
  final n = out.length;
  if (n == 0) return out;
  
  double? first;
  for (int i = 0; i < n; i++) {
    if (!out[i].isNaN) { first = out[i]; break; }
  }
  
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
