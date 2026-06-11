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

  double? _prevRx, _prevRy;
  double? _prevLx, _prevLy;

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
    _prevRx            = null;
    _prevRy            = null;
    _prevLx            = null;
    _prevLy            = null;
  }

  /// 喂入一禎姿勢資料（MediaPipe NativePoseResult）。
  ///
  /// [pose]    MediaPipe 結果（歸一化座標 0-1）
  /// [timeSec] 相對錄製開始的秒數
  void feed(NativePoseResult pose, double timeSec) {
    // 雙腕都追蹤、取速度較大者：左打者主導腕為左腕，只看右腕會鈍化偵測
    double rSpeed = 0.0, lSpeed = 0.0;
    final rw = pose.rightWrist;
    if (rw != null && rw.visibility >= 0.1) {
      if (_prevRx != null) {
        final dx = rw.x - _prevRx!;
        final dy = rw.y - _prevRy!;
        rSpeed = math.sqrt(dx * dx + dy * dy);
      }
      _prevRx = rw.x;
      _prevRy = rw.y;
    }
    final lw = pose.leftWrist;
    if (lw != null && lw.visibility >= 0.1) {
      if (_prevLx != null) {
        final dx = lw.x - _prevLx!;
        final dy = lw.y - _prevLy!;
        lSpeed = math.sqrt(dx * dx + dy * dy);
      }
      _prevLx = lw.x;
      _prevLy = lw.y;
    }
    final speed = math.max(rSpeed, lSpeed);

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
        _state != SwingDetectState.triggered) {
      return;
    }

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
          // 邊際峰值（< 門檻 1.5 倍）視為小動作誤觸，不開火
          if (_peakSpeed < thr * 1.5) {
            debugPrint('[LiveSwing] 忽略邊際峰值 peak=${_peakSpeed.toStringAsFixed(4)} '
                'thr=${thr.toStringAsFixed(4)}（< thr×1.5）');
            _state      = SwingDetectState.listening;
            _peakSpeed  = 0;
            _fallFrames = 0;
            return;
          }
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

  // 動態 threshold（歸一化速度）：80th percentile × 1.8，最低 0.012
  // （floor 0.005 時安靜期門檻過低，輕微手部移動即觸發 → 錄影 1-4 秒就被停掉）
  static const double _minThreshold = 0.012;

  double _threshold() {
    if (_speedBuf.length < 5) return _minThreshold;
    final sorted = _speedBuf.toList()..sort();
    final idx = (0.80 * (sorted.length - 1)).round().clamp(0, sorted.length - 1);
    return math.max(_minThreshold, sorted[idx] * 1.8);
  }
}
