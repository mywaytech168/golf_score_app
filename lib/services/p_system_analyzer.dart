import '../models/p_system_metrics.dart';
import '../recording/pose_csv_loader.dart';
import '../recording/pose_result.dart';
import 'biomechanics_service.dart';
import 'skeleton_csv_locator.dart';

/// P1-P10 動作分析器（裝置端，純幾何）。
///
/// 吃 clip session 的 `pose_landmarks.csv`（透過 [PoseTrack]）+ 四個強錨點
/// （P1=address / P4=top / P7=impact / P10=finish，由 SwingImpactDetector 8 階段
/// 提供，已是 clip 相對秒數），偵測中間六個代理位置 P2/P3/P5/P6/P8/P9，並在每個
/// P 取樣計算 [BiomechanicsService] 角度指標 + 分級，輸出 [PSystemMetrics]。
///
/// **誠實性**：MediaPipe 無桿身 landmark，P2/P6/P8（club parallel）以「主導前臂」
/// 代理、P3/P5/P9（lead arm parallel）以「主導手臂」代理；旋轉/X-factor 為 2D 投影
/// 代理且僅 face-on 視角採計（[BiomechanicsService.viewpointOf] gate）。皆標 beta。
class PSystemAnalyzer {
  PSystemAnalyzer._();

  /// 取樣掃描步數（區間內均勻取樣找「最接近水平」事件）。
  static const int _scanSteps = 40;

  // ── 評分門檻常數（說明頁顯示與 _metricsFor 共用，單一來源避免分歧）──
  /// 脊椎前傾相對 address 的良好邊際(±deg) + 額外警示邊際。
  static const double spineTiltGoodMargin = 8;
  static const double spineTiltWarnMargin = 6;
  /// 頭部位移（歸一化）良好上限 + 額外警示邊際。
  static const double headMoveGoodMax = 0.06;
  static const double headMoveWarnMargin = 0.04;
  /// X-factor（度）良好區間 + 額外警示邊際（beta，僅 face-on）。
  static const double xFactorGoodLow = 25, xFactorGoodHigh = 55, xFactorWarnMargin = 10;
  /// 擊球重心轉移（比例）良好區間 + 額外警示邊際。
  static const double weightShiftGoodLow = 0.1, weightShiftGoodHigh = 1.0, weightShiftWarnMargin = 0.2;

  /// 某 P 位置適用的指標 key（與 [_metricsFor] 完全一致，供說明頁列門檻）。
  static List<String> metricsForPosition(String p) {
    final out = <String>['spine_tilt'];
    if (p != 'p1') out.add('head_move');
    if (p == 'p3' || p == 'p4' || p == 'p5') out.add('x_factor');
    if (p == 'p7') out.add('weight_shift');
    return out;
  }

  /// 分析 clip。回傳 null 表無骨架 CSV / 無有效骨架。
  /// [leadIsLeft]：右手球員主導臂為左臂（預設 true）。
  static Future<PSystemMetrics?> analyze({
    required String sessionDir,
    required double p1Sec,
    required double p4Sec,
    required double p7Sec,
    required double p10Sec,
    bool leadIsLeft = true,
  }) async {
    final csv = resolveSkeletonCsv(sessionDir);
    if (csv == null) return null;
    final track = await PoseTrack.load(csv);
    if (track.isEmpty) return null;

    double? arm(NativePoseResult f) =>
        BiomechanicsService.leadArmFromHorizontalDeg(f, leadIsLeft: leadIsLeft);
    double? forearm(NativePoseResult f) =>
        BiomechanicsService.leadForearmFromHorizontalDeg(f, leadIsLeft: leadIsLeft);

    // 中間位置：以「最接近水平」事件偵測；失敗退回分數內插（保證不為 null）。
    final p3 = _scanMin(track, p1Sec, p4Sec, arm) ?? _lerp(p1Sec, p4Sec, 0.66);
    final p2 = _scanMin(track, p1Sec, p3, forearm) ?? _lerp(p1Sec, p3, 0.5);
    final p5 = _scanMin(track, p4Sec, p7Sec, arm) ?? _lerp(p4Sec, p7Sec, 0.5);
    final p6 = _scanMin(track, p5, p7Sec, forearm) ?? _lerp(p5, p7Sec, 0.6);
    final p9 = _scanMin(track, p7Sec, p10Sec, arm) ?? _lerp(p7Sec, p10Sec, 0.5);
    final p8 = _scanMin(track, p7Sec, p9, forearm) ?? _lerp(p7Sec, p9, 0.5);

    final pSec = <String, double>{
      'p1': p1Sec, 'p2': p2, 'p3': p3, 'p4': p4Sec, 'p5': p5,
      'p6': p6, 'p7': p7Sec, 'p8': p8, 'p9': p9, 'p10': p10Sec,
    };
    _enforceMonotonic(pSec);

    // 視角 + address 基準（脊椎角、頭位）取自 P1。
    final addrFrame = track.sampleAt(p1Sec);
    final viewpoint = addrFrame != null
        ? BiomechanicsService.viewpointOf(addrFrame)
        : SwingViewpoint.unknown;
    final addrSpine = addrFrame != null
        ? (BiomechanicsService.spineTiltDeg(addrFrame) ?? 0.0)
        : 0.0;

    final perP = <String, List<BiomechMetric>>{};
    final scores = <double>[];
    for (final key in PSystemMetrics.order) {
      final f = track.sampleAt(pSec[key]!);
      final metrics = (f == null || addrFrame == null)
          ? <BiomechMetric>[]
          : _metricsFor(key, f, addrFrame, viewpoint, addrSpine);
      perP[key] = metrics;
      final s = _scoreOf(metrics);
      if (s != null) scores.add(s);
    }

    final overall = scores.isEmpty
        ? null
        : scores.reduce((a, b) => a + b) / scores.length;

    return PSystemMetrics(
      pSec: pSec,
      perP: perP,
      viewpoint: viewpoint,
      overallScore: overall,
    );
  }

  // ── 每個 P 的指標 + 評分規則 ────────────────────────────────────────────────

  static List<BiomechMetric> _metricsFor(
    String pKey,
    NativePoseResult f,
    NativePoseResult addr,
    SwingViewpoint vp,
    double addrSpine,
  ) {
    final out = <BiomechMetric>[];

    // 脊椎前傾：相對 address 維持（±8° 良好、±14° 警告）。
    final spine = BiomechanicsService.spineTiltDeg(f);
    if (spine != null) {
      out.add(BiomechMetric(
        key: 'spine_tilt',
        value: spine,
        idealLow: addrSpine - spineTiltGoodMargin,
        idealHigh: addrSpine + spineTiltGoodMargin,
        grade: BiomechanicsService.grade(spine,
            addrSpine - spineTiltGoodMargin, addrSpine + spineTiltGoodMargin,
            warn: spineTiltWarnMargin),
        unit: 'deg',
      ));
    }

    // 頭部位移（P1 以外）：相對 address 越小越好。
    if (pKey != 'p1') {
      final hm = BiomechanicsService.headDisplacement(f, addr);
      if (hm != null) {
        out.add(BiomechMetric(
          key: 'head_move',
          value: hm,
          idealLow: 0,
          idealHigh: headMoveGoodMax,
          grade: BiomechanicsService.grade(hm, 0, headMoveGoodMax, warn: headMoveWarnMargin),
          unit: 'norm',
        ));
      }
    }

    // X-factor 投影代理（P3/P4/P5，beta，僅 face-on）。
    if ((pKey == 'p3' || pKey == 'p4' || pKey == 'p5') &&
        vp == SwingViewpoint.faceOn) {
      final xf = BiomechanicsService.xFactorProxyDeg(f);
      if (xf != null) {
        final a = xf.abs();
        out.add(BiomechMetric(
          key: 'x_factor',
          value: a,
          idealLow: xFactorGoodLow,
          idealHigh: xFactorGoodHigh,
          grade: BiomechanicsService.grade(a, xFactorGoodLow, xFactorGoodHigh, warn: xFactorWarnMargin),
          beta: true,
          unit: 'deg',
        ));
      }
    }

    // 擊球重心轉移（P7）：髖往前腳側（正值）為佳。
    if (pKey == 'p7') {
      final ws = BiomechanicsService.weightShiftRatio(f);
      if (ws != null) {
        out.add(BiomechMetric(
          key: 'weight_shift',
          value: ws,
          idealLow: weightShiftGoodLow,
          idealHigh: weightShiftGoodHigh,
          grade: BiomechanicsService.grade(ws, weightShiftGoodLow, weightShiftGoodHigh, warn: weightShiftWarnMargin),
          unit: 'ratio',
        ));
      }
    }

    return out;
  }

  static double? _scoreOf(List<BiomechMetric> metrics) {
    final vals = <double>[];
    for (final m in metrics) {
      switch (m.grade) {
        case BiomechGrade.good:
          vals.add(100);
          break;
        case BiomechGrade.warn:
          vals.add(60);
          break;
        case BiomechGrade.bad:
          vals.add(20);
          break;
        case BiomechGrade.unknown:
          break; // 不計入
      }
    }
    if (vals.isEmpty) return null;
    return vals.reduce((a, b) => a + b) / vals.length;
  }

  // ── 偵測工具 ────────────────────────────────────────────────────────────────

  /// 在 [t0, t1] 均勻取樣，回傳 fn（角度）最小的時刻；無有效取樣 → null。
  static double? _scanMin(
    PoseTrack track,
    double t0,
    double t1,
    double? Function(NativePoseResult) fn,
  ) {
    if (t1 <= t0) return null;
    double? bestT;
    double bestV = double.infinity;
    for (int i = 0; i <= _scanSteps; i++) {
      final t = t0 + (t1 - t0) * i / _scanSteps;
      final f = track.sampleAt(t);
      if (f == null) continue;
      final v = fn(f);
      if (v == null) continue;
      if (v < bestV) {
        bestV = v;
        bestT = t;
      }
    }
    return bestT;
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  /// 強制 P1..P10 時刻非遞減（代理偵測偶有逆序時鉗位到前一個）。
  static void _enforceMonotonic(Map<String, double> pSec) {
    for (int i = 1; i < PSystemMetrics.order.length; i++) {
      final prev = pSec[PSystemMetrics.order[i - 1]]!;
      final cur = pSec[PSystemMetrics.order[i]]!;
      if (cur < prev) pSec[PSystemMetrics.order[i]] = prev;
    }
  }
}
