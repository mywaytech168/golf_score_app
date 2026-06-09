import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'pose_result.dart';

enum SwingDetectState {
  calibrating, // 前幾秒校準基線
  listening,   // 偵測中
  triggered,   // 速度峰值後等待確認
  fired,       // 已觸發，冷卻中
}

/// 即時滾動視窗揮桿偵測器（使用 MediaPipe 歸一化座標）。
///
/// 每禎呼叫 [feed]，偵測到撞擊時呼叫 [onImpact]（傳入 impactTimeSec）。
///
/// 速度以歸一化單位計算（0-1 / frame），threshold 對應像素速度：
///   minThreshold = 0.005 ≈ 2px @ 400px 分析幀寬
class LiveSwingDetector {
  final double calibrationSec;
  final double cooldownSec;
  final double postImpactBufferSec;
  final void Function(double impactTimeSec)? onImpact;

  static const int _bufSize = 60;
  final _speedBuf = Queue<double>();

  SwingDetectState _state = SwingDetectState.calibrating;
  double _calibrationEndTime = 0;
  double _cooldownEndTime    = 0;

  double _peakSpeed    = 0;
  double _peakTimeSec  = 0;
  int    _fallFrames   = 0;
  static const int _minFallFrames = 2;

  double? _prevX, _prevY;

  LiveSwingDetector({
    this.calibrationSec      = 3.0,
    this.cooldownSec         = 5.0,
    this.postImpactBufferSec = 2.5,
    this.onImpact,
  });

  SwingDetectState get state => _state;

  void reset() {
    _speedBuf.clear();
    _state             = SwingDetectState.calibrating;
    _calibrationEndTime = 0;
    _cooldownEndTime   = 0;
    _peakSpeed         = 0;
    _peakTimeSec       = 0;
    _fallFrames        = 0;
    _prevX             = null;
    _prevY             = null;
  }

  /// 喂入一禎姿勢資料（MediaPipe NativePoseResult）。
  ///
  /// [pose]    MediaPipe 結果（歸一化座標 0-1）
  /// [timeSec] 相對錄製開始的秒數
  void feed(NativePoseResult pose, double timeSec) {
    double speed = 0.0;
    final rw = pose.rightWrist;
    if (rw != null && rw.visibility >= 0.1) {
      if (_prevX != null) {
        final dx = rw.x - _prevX!;
        final dy = rw.y - _prevY!;
        speed = math.sqrt(dx * dx + dy * dy);
      }
      _prevX = rw.x;
      _prevY = rw.y;
    }

    _speedBuf.addLast(speed);
    if (_speedBuf.length > _bufSize) _speedBuf.removeFirst();

    // 校準期
    if (_state == SwingDetectState.calibrating) {
      if (_calibrationEndTime == 0) _calibrationEndTime = timeSec + calibrationSec;
      if (timeSec < _calibrationEndTime) return;
      _state = SwingDetectState.listening;
      debugPrint('[LiveSwing] 校準完成 → 開始偵測');
    }

    // 冷卻期
    if (_state == SwingDetectState.fired) {
      if (timeSec < _cooldownEndTime) return;
      _state     = SwingDetectState.listening;
      _peakSpeed = 0;
      _fallFrames = 0;
    }

    if (_state != SwingDetectState.listening &&
        _state != SwingDetectState.triggered) return;

    final thr = _threshold();

    if (_state == SwingDetectState.listening) {
      if (speed > thr) {
        _state       = SwingDetectState.triggered;
        _peakSpeed   = speed;
        _peakTimeSec = timeSec;
        _fallFrames  = 0;
      }
    } else {
      if (speed >= _peakSpeed) {
        _peakSpeed   = speed;
        _peakTimeSec = timeSec;
        _fallFrames  = 0;
      } else if (speed < _peakSpeed * 0.80) {
        _fallFrames++;
        if (_fallFrames >= _minFallFrames) {
          _state          = SwingDetectState.fired;
          _cooldownEndTime = timeSec + cooldownSec;
          debugPrint('[LiveSwing] ✅ 撞擊 t=${_peakTimeSec.toStringAsFixed(2)}s '
              'peak=${_peakSpeed.toStringAsFixed(4)} thr=${thr.toStringAsFixed(4)}');
          onImpact?.call(_peakTimeSec);
        }
      } else if (speed < thr * 0.35) {
        _state     = SwingDetectState.listening;
        _peakSpeed = 0;
        _fallFrames = 0;
      }
    }
  }

  // 動態 threshold（歸一化速度）：80th percentile × 1.8，最低 0.005（≈ 2px/400px）
  double _threshold() {
    if (_speedBuf.length < 5) return 0.005;
    final sorted = _speedBuf.toList()..sort();
    final idx = (0.80 * (sorted.length - 1)).round().clamp(0, sorted.length - 1);
    return math.max(0.005, sorted[idx] * 1.8);
  }
}
