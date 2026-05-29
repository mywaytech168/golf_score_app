import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

enum SwingDetectState {
  calibrating, // 前幾秒校準基線
  listening,   // 偵測中
  triggered,   // 速度峰值後等待確認
  fired,       // 已觸發，冷卻中
}

/// 即時滾動視窗揮桿偵測器。
///
/// 每禎呼叫 [feed]，偵測到撞擊時呼叫 [onImpact]（傳入 impactTimeSec）。
///
/// 算法：
///   1. 校準期（前 calibrationSec 秒）只收集速度，不觸發
///   2. 動態 threshold = max(2.0, rolling_80th_percentile × 1.8)
///   3. 速度超過 threshold → 進入 triggered，追蹤峰值
///   4. 速度從峰值下降 ≥ 20% 且連續 2 禎 → 確認撞擊，呼叫 onImpact
///   5. 觸發後進入冷卻期（cooldownSec），防止同一桿重複觸發
class LiveSwingDetector {
  final double calibrationSec;
  final double cooldownSec;
  final double postImpactBufferSec;
  final void Function(double impactTimeSec)? onImpact;

  // 滾動速度緩衝：最多 60 禎（約 6 秒 @ 10fps）
  static const int _bufSize = 60;
  final _speedBuf = Queue<double>();

  SwingDetectState _state = SwingDetectState.calibrating;
  double _calibrationEndTime = 0;
  double _cooldownEndTime = 0;

  // 峰值追蹤
  double _peakSpeed = 0;
  double _peakTimeSec = 0;
  int _fallFrames = 0;
  static const int _minFallFrames = 2;

  // 前一禎右手腕座標
  double? _prevX, _prevY;

  LiveSwingDetector({
    this.calibrationSec = 3.0,
    this.cooldownSec = 5.0,
    this.postImpactBufferSec = 2.5,
    this.onImpact,
  });

  SwingDetectState get state => _state;

  /// 重置至初始狀態（新一桿開始前呼叫）
  void reset() {
    _speedBuf.clear();
    _state = SwingDetectState.calibrating;
    _calibrationEndTime = 0;
    _cooldownEndTime = 0;
    _peakSpeed = 0;
    _peakTimeSec = 0;
    _fallFrames = 0;
    _prevX = null;
    _prevY = null;
  }

  /// 喂入一禎姿勢資料。
  ///
  /// [poses] ML Kit 偵測結果
  /// [timeSec] 此禎相對於錄製開始的秒數
  void feed(List<Pose> poses, double timeSec) {
    // 計算右手腕速度（px/frame）
    double speed = 0.0;
    if (poses.isNotEmpty) {
      final lm = poses.first.landmarks[PoseLandmarkType.rightWrist];
      if (lm != null && lm.likelihood >= 0.1) {
        if (_prevX != null) {
          final dx = lm.x - _prevX!;
          final dy = lm.y - _prevY!;
          speed = math.sqrt(dx * dx + dy * dy);
        }
        _prevX = lm.x;
        _prevY = lm.y;
      }
    }

    _speedBuf.addLast(speed);
    if (_speedBuf.length > _bufSize) { _speedBuf.removeFirst(); }

    // 校準期：收集基線，不觸發
    if (_state == SwingDetectState.calibrating) {
      if (_calibrationEndTime == 0) _calibrationEndTime = timeSec + calibrationSec;
      if (timeSec < _calibrationEndTime) return;
      _state = SwingDetectState.listening;
      debugPrint('[LiveSwing] 校準完成 → 開始偵測');
    }

    // 冷卻期
    if (_state == SwingDetectState.fired) {
      if (timeSec < _cooldownEndTime) return;
      _state = SwingDetectState.listening;
      _peakSpeed = 0;
      _fallFrames = 0;
    }

    if (_state != SwingDetectState.listening &&
        _state != SwingDetectState.triggered) {
      return;
    }

    final thr = _threshold();

    if (_state == SwingDetectState.listening) {
      if (speed > thr) {
        _state = SwingDetectState.triggered;
        _peakSpeed = speed;
        _peakTimeSec = timeSec;
        _fallFrames = 0;
      }
    } else {
      // triggered
      if (speed >= _peakSpeed) {
        // 峰值更新
        _peakSpeed = speed;
        _peakTimeSec = timeSec;
        _fallFrames = 0;
      } else if (speed < _peakSpeed * 0.80) {
        _fallFrames++;
        if (_fallFrames >= _minFallFrames) {
          // 確認撞擊
          _state = SwingDetectState.fired;
          _cooldownEndTime = timeSec + cooldownSec;
          debugPrint('[LiveSwing] ✅ 撞擊 t=${_peakTimeSec.toStringAsFixed(2)}s '
              'peak=${_peakSpeed.toStringAsFixed(1)} thr=${thr.toStringAsFixed(1)}');
          onImpact?.call(_peakTimeSec);
        }
      } else if (speed < thr * 0.35) {
        // 速度跌太低，放棄此次 trigger
        _state = SwingDetectState.listening;
        _peakSpeed = 0;
        _fallFrames = 0;
      }
    }
  }

  // 動態 threshold：80th percentile × 1.8，最低 2.0 px/frame
  double _threshold() {
    if (_speedBuf.length < 5) return 2.0;
    final sorted = _speedBuf.toList()..sort();
    final idx = (0.80 * (sorted.length - 1)).round().clamp(0, sorted.length - 1);
    return math.max(2.0, sorted[idx] * 1.8);
  }
}
