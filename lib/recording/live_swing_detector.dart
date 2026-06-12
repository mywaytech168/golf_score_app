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

  /// 雙手判斷：雙手腕都有效時，需「兩手一起移動」才接受揮桿；其中一手被遮擋
  /// （數值無法取得）時，自動退回以另一手判斷。關閉時維持單手主導（取速度較大者）。
  /// 可即時切換（設定變更不需重建偵測器）。
  bool bothHands;

  /// 雙手判斷時，第二隻手相對動態門檻的最低速度比例（釋放時一手會略先減速，故放寬）。
  /// 0.35 由 ADB 實錄 76 切片驗證：窗內判定下 recall 96%、相對單手模式 0 漏失。
  static const double _secondHandFactor = 0.35;

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

  // 弧線底部（觸球）偵測：鎖定峰值當下的主導腕，追蹤其垂直速度由下(+)轉上(-)。
  bool    _peakDomLeft = false; // 峰值時主導腕是否為左腕
  bool    _sawDownward = false; // 本次揮桿是否已觀察到向下運動（避免起手即誤判）
  double? _prevDomDy;           // 主導腕上一禎的垂直速度（影像 y 向下為正）

  // 雙手確認（嚴格模式）：本次揮桿過程中是否存在「一禎雙手都可見且一起快」。
  // 不採遮擋免除——ADB 實錄擊球禎雙手可見率 98.7%，嚴格收緊僅損 ~1.3% 真揮桿，
  // 卻能堵掉「另一手不可見/別處飄動」造成的單手誤判（使用者可關閉雙手判斷退回單手）。
  bool _bothFastTogether = false;

  LiveSwingDetector({
    this.calibrationSec      = 3.0,
    this.cooldownSec         = 5.0,
    this.postImpactBufferSec = 2.5,
    this.bothHands           = false,
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
    _resetArc();
  }

  /// 清除弧線底部偵測狀態（每次開火 / 回到 listening 時呼叫）。
  void _resetArc() {
    _sawDownward = false;
    _prevDomDy   = null;
    _bothFastTogether = false;
  }

  /// 喂入一禎姿勢資料（MediaPipe NativePoseResult）。
  ///
  /// [pose]    MediaPipe 結果（歸一化座標 0-1）
  /// [timeSec] 相對錄製開始的秒數
  void feed(NativePoseResult pose, double timeSec) {
    // 雙腕都追蹤、取速度較大者：左打者主導腕為左腕，只看右腕會鈍化偵測
    double rSpeed = 0.0, lSpeed = 0.0;
    double? rDy, lDy; // 帶正負號的垂直速度（影像 y 向下為正），null = 該禎腕點無效
    bool rValid = false, lValid = false; // 本禎腕點是否有效（可見且有上一禎可算速度）
    final rw = pose.rightWrist;
    if (rw != null && rw.visibility >= 0.1) {
      if (_prevRx != null) {
        final dx = rw.x - _prevRx!;
        final dy = rw.y - _prevRy!;
        rSpeed = math.sqrt(dx * dx + dy * dy);
        rDy = dy;
        rValid = true;
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
        lDy = dy;
        lValid = true;
      }
      _prevLx = lw.x;
      _prevLy = lw.y;
    }
    final speed   = math.max(rSpeed, lSpeed);
    final domLeft = lSpeed > rSpeed;        // 本禎主導腕
    final domDy   = domLeft ? lDy : rDy;    // 主導腕垂直速度（可能 null）

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
        _peakDomLeft = domLeft;
        // 起手禎即初始化弧線偵測狀態
        _sawDownward = domDy != null && domDy > 0;
        _prevDomDy   = domDy;
        // 雙手確認：起手禎即開始累計
        _trackBothHands(rValid, lValid, rSpeed, lSpeed, thr);
      }
    } else {
      // 雙手確認：累計本次揮桿期間各手是否曾出現 / 曾達門檻
      _trackBothHands(rValid, lValid, rSpeed, lSpeed, thr);

      // --- 峰值追蹤（含 fallback 回落計數）---
      if (speed >= _peakSpeed) {
        _peakSpeed   = speed;
        _peakTimeSec = timeSec;
        _fallFrames  = 0;
        _peakDomLeft = domLeft;
      } else if (speed < _peakSpeed * 0.80) {
        _fallFrames++;
      } else if (speed < thr * 0.35) {
        _state     = SwingDetectState.listening;
        _peakSpeed = 0;
        _fallFrames = 0;
        _resetArc();
        return;
      }

      // --- 弧線底部偵測（主導腕垂直速度 下(+)→上(-) 過零）= 觸球瞬間 ---
      // 物理：手腕弧線最低點 ≈ 桿頭觸球，晚於腕速峰值（下桿途中），故較貼近真正擊球。
      final dy = _peakDomLeft ? lDy : rDy;
      if (dy != null) {
        if (dy > 0) _sawDownward = true;
        final crossedDownUp =
            _sawDownward && _prevDomDy != null && _prevDomDy! > 0 && dy <= 0;
        _prevDomDy = dy;
        // 已是強揮桿（peak ≥ thr×1.5）且抵達弧線底部 → 即時對齊觸球開火
        // 雙手判斷未確認（單手動作）則略過此次開火，繼續觀察
        if (crossedDownUp && _peakSpeed >= thr * 1.5 && _bothConfirmed()) {
          _state          = SwingDetectState.fired;
          _cooldownEndTime = timeSec + cooldownSec;
          debugPrint('[LiveSwing] ✅ 撞擊（弧底）t=${timeSec.toStringAsFixed(2)}s '
              'peak=${_peakSpeed.toStringAsFixed(4)} thr=${thr.toStringAsFixed(4)}');
          _resetArc();
          onImpact?.call(timeSec);
          return;
        }
      }

      // --- fallback：回落已確認但未抓到垂直反轉（純水平揮桿）→ 退回峰值時刻 ---
      if (_fallFrames >= _minFallFrames) {
        // 邊際峰值（< 門檻 1.5 倍）或雙手判斷未確認（單手動作）→ 視為誤觸，不開火
        if (_peakSpeed < thr * 1.5 || !_bothConfirmed()) {
          debugPrint('[LiveSwing] 忽略（邊際峰值或單手）peak=${_peakSpeed.toStringAsFixed(4)} '
              'thr=${thr.toStringAsFixed(4)} bothOK=${_bothConfirmed()}');
          _state      = SwingDetectState.listening;
          _peakSpeed  = 0;
          _fallFrames = 0;
          _resetArc();
          return;
        }
        _state          = SwingDetectState.fired;
        _cooldownEndTime = timeSec + cooldownSec;
        debugPrint('[LiveSwing] ✅ 撞擊（峰值 fallback）t=${_peakTimeSec.toStringAsFixed(2)}s '
            'peak=${_peakSpeed.toStringAsFixed(4)} thr=${thr.toStringAsFixed(4)}');
        _resetArc();
        onImpact?.call(_peakTimeSec);
      }
    }
  }

  /// 累計：本次揮桿是否出現過「一禎雙手都可見且一起快」（嚴格雙手確認）。
  void _trackBothHands(
      bool rValid, bool lValid, double rSpeed, double lSpeed, double thr) {
    if (!bothHands || _bothFastTogether) return;
    final fastThr = thr * _secondHandFactor;
    if (rValid && lValid && rSpeed >= fastThr && lSpeed >= fastThr) {
      _bothFastTogether = true;
    }
  }

  /// 雙手判斷裁定（開火前呼叫，嚴格模式）：
  ///   ・關閉 → 永遠通過（單手主導，維持舊行為）
  ///   ・開啟 → 本次揮桿須曾出現「一禎雙手都可見且一起快」
  /// 不採遮擋免除：另一手不可見/別處飄動（非同禎）皆不算，杜絕單手誤判。
  bool _bothConfirmed() => !bothHands || _bothFastTogether;

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
