import 'dart:math' as math;

/// One-Euro filter（Casiez et al. 2012）：低延遲自適應低通。
///
/// 自適應截止頻率隨訊號速度調整——慢速（靜止 address）時重平滑去抖、
/// 高速（downswing）時放寬避免拖尾，比固定 α EMA 更適合「靜止＋高速」雙態。
///
/// 跨子系統共用平滑元件（骨架平滑、未來球軌跡/即時偵測可重用）。純函式狀態機，
/// 無 IO。缺值請於呼叫端跳過（不要餵 NaN）。
class OneEuroFilter {
  /// 最小截止頻率（Hz）：越小越平滑（靜止時的去抖強度）。
  final double minCutoff;

  /// 速度項係數：越大則高速時越快放寬截止（減少拖尾）。
  final double beta;

  /// 速度估計的截止頻率（Hz）。
  final double dCutoff;

  double? _x;   // 上一個平滑值
  double _dx = 0; // 上一個平滑速度
  double? _t;   // 上一個時間（秒）

  OneEuroFilter({
    this.minCutoff = 1.0,
    this.beta = 0.007,
    this.dCutoff = 1.0,
  });

  static double _alpha(double cutoff, double dt) {
    final tau = 1.0 / (2 * math.pi * cutoff);
    return 1.0 / (1.0 + tau / dt);
  }

  /// 餵入 (value, timeSec)，回傳平滑值。時間非遞增（dt<=0）時重置為原值。
  double filter(double value, double t) {
    final tp = _t;
    if (tp == null || t <= tp) {
      _t = t;
      _x = value;
      _dx = 0;
      return value;
    }
    final dt = t - tp;
    final dxRaw = (value - _x!) / dt;
    final aD = _alpha(dCutoff, dt);
    final dxHat = aD * dxRaw + (1 - aD) * _dx;
    final cutoff = minCutoff + beta * dxHat.abs();
    final aX = _alpha(cutoff, dt);
    final xHat = aX * value + (1 - aX) * _x!;
    _x = xHat;
    _dx = dxHat;
    _t = t;
    return xHat;
  }

  void reset() {
    _x = null;
    _dx = 0;
    _t = null;
  }
}
