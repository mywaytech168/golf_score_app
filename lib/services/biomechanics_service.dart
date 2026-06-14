import 'dart:math' as math;

import '../recording/pose_result.dart';

/// 生物力學幾何引擎（W2 最大槓桿）：從 MediaPipe 33 點正規化座標算出可解釋的
/// 揮桿角度/比值指標，供 P1-P10、骨架量化卡、AI 教練 prompt、修正追蹤共用。
///
/// 設計原則：
///  - **純幾何、純裝置端、無 ML、無 IO**——只吃單幀 [NativePoseResult]（正規化 0-1）。
///  - **2D 影像平面**：單機位無可靠深度（MediaPipe z 單目不準），故旋轉類指標
///    （肩/髖旋轉、X-factor）只能用投影代理，一律標 [BiomechMetric.beta]，並以
///    [viewpointOf] 視角閘門過濾——face-on 才顯示旋轉角，否則回報 null。
///  - **座標系**：x 右為正、y **下**為正（影像空間）。角度單位一律「度」。
///
/// MediaPipe 索引：0 鼻 · 11/12 左右肩 · 13/14 左右肘 · 15/16 左右腕 ·
///                 23/24 左右髖 · 27/28 左右踝。
class BiomechanicsService {
  BiomechanicsService._();

  // ── landmark 索引 ──────────────────────────────────────────────────────────
  static const int kNose = 0;
  static const int kLShoulder = 11, kRShoulder = 12;
  static const int kLElbow = 13, kRElbow = 14;
  static const int kLWrist = 15, kRWrist = 16;
  static const int kLHip = 23, kRHip = 24;
  static const int kLAnkle = 27, kRAnkle = 28;

  static const double _minVis = 0.1;

  // ── landmark 取值（無效回 null）────────────────────────────────────────────

  /// 取得有效 landmark 的 (x, y)；vis 過低或座標退化為 (0,0)（PoseTrack 無效標記）→ null。
  static _P? _pt(NativePoseResult f, int idx) {
    final lm = f.landmark(idx);
    if (lm == null) return null;
    if (lm.visibility < _minVis) return null;
    if (lm.x == 0 && lm.y == 0) return null;
    return _P(lm.x, lm.y);
  }

  static _P? _mid(NativePoseResult f, int a, int b) {
    final pa = _pt(f, a), pb = _pt(f, b);
    if (pa == null || pb == null) return null;
    return _P((pa.x + pb.x) / 2, (pa.y + pb.y) / 2);
  }

  // ── 視角分類（決定旋轉類指標是否可信）──────────────────────────────────────

  /// 以「肩寬 / 軀幹高」比例粗判拍攝視角：
  ///  - face-on（正面）：雙肩投影寬、比例大；旋轉/X-factor 投影代理較有意義。
  ///  - down-the-line（側面）：雙肩近乎重疊、比例小；旋轉投影代理不可信。
  static SwingViewpoint viewpointOf(NativePoseResult f) {
    final ls = _pt(f, kLShoulder), rs = _pt(f, kRShoulder);
    final sc = _mid(f, kLShoulder, kRShoulder);
    final hc = _mid(f, kLHip, kRHip);
    if (ls == null || rs == null || sc == null || hc == null) {
      return SwingViewpoint.unknown;
    }
    final shoulderWidth = (ls.x - rs.x).abs();
    final torsoHeight = (sc.y - hc.y).abs();
    if (torsoHeight < 1e-4) return SwingViewpoint.unknown;
    final ratio = shoulderWidth / torsoHeight;
    if (ratio >= 0.45) return SwingViewpoint.faceOn;
    if (ratio <= 0.20) return SwingViewpoint.downTheLine;
    return SwingViewpoint.unknown;
  }

  // ── 角度/比值原始計算 ──────────────────────────────────────────────────────

  /// 脊椎前傾角（度）：髖中點→肩中點向量與垂直線的夾角。
  /// 0 = 完全直立（肩在髖正上方），正值 = 向 +x 方向傾。可靠（2D，視角無關於存在性）。
  static double? spineTiltDeg(NativePoseResult f) {
    final sc = _mid(f, kLShoulder, kRShoulder);
    final hc = _mid(f, kLHip, kRHip);
    if (sc == null || hc == null) return null;
    final dx = sc.x - hc.x;
    final dy = sc.y - hc.y; // 直立時肩在髖上方 → dy < 0
    return _deg(math.atan2(dx, -dy));
  }

  /// 肩線相對水平的傾角（度）：11→12 連線。0 = 水平。
  static double? shoulderLineDeg(NativePoseResult f) {
    final ls = _pt(f, kLShoulder), rs = _pt(f, kRShoulder);
    if (ls == null || rs == null) return null;
    return _deg(math.atan2(rs.y - ls.y, rs.x - ls.x));
  }

  /// 髖線相對水平的傾角（度）：23→24 連線。0 = 水平。
  static double? hipLineDeg(NativePoseResult f) {
    final lh = _pt(f, kLHip), rh = _pt(f, kRHip);
    if (lh == null || rh == null) return null;
    return _deg(math.atan2(rh.y - lh.y, rh.x - lh.x));
  }

  /// X-factor 投影代理（度）：肩線傾角 − 髖線傾角。**beta**——2D 投影非真實
  /// 3D 肩髖分離角，僅 face-on 視角下有參考意義。用 [viewpointOf] 閘門。
  static double? xFactorProxyDeg(NativePoseResult f) {
    final s = shoulderLineDeg(f);
    final h = hipLineDeg(f);
    if (s == null || h == null) return null;
    return s - h;
  }

  /// 頭部位移（正規化距離）：當前鼻位相對 [address] 幀鼻位的位移量。
  /// 量化 sway/lift；回 null 表任一幀鼻點無效。
  static double? headDisplacement(NativePoseResult f, NativePoseResult address) {
    final cur = _pt(f, kNose), addr = _pt(address, kNose);
    if (cur == null || addr == null) return null;
    final dx = cur.x - addr.x, dy = cur.y - addr.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  /// 重心轉移比例：髖中點 x 相對雙踝中點，以站寬半徑正規化。
  /// 約 −1（後腳側）..+1（前腳側）；站寬過小或 landmark 缺 → null。
  static double? weightShiftRatio(NativePoseResult f) {
    final hc = _mid(f, kLHip, kRHip);
    final la = _pt(f, kLAnkle), ra = _pt(f, kRAnkle);
    if (hc == null || la == null || ra == null) return null;
    final ankleMid = (la.x + ra.x) / 2;
    final stance = (la.x - ra.x).abs();
    if (stance < 1e-4) return null;
    return ((hc.x - ankleMid) / (stance / 2)).clamp(-2.0, 2.0);
  }

  /// 主導手肘夾角（度）：肩-肘-腕三點夾角。180 = 手臂完全伸直。
  /// [leadIsLeft] 決定用左臂（左打者主導臂為左）或右臂。
  static double? leadElbowAngleDeg(NativePoseResult f, {required bool leadIsLeft}) {
    final sh = _pt(f, leadIsLeft ? kLShoulder : kRShoulder);
    final el = _pt(f, leadIsLeft ? kLElbow : kRElbow);
    final wr = _pt(f, leadIsLeft ? kLWrist : kRWrist);
    if (sh == null || el == null || wr == null) return null;
    return _angleAt(el, sh, wr);
  }

  /// 主導前臂相對水平的傾角絕對值（度）：肘→腕向量。0 = 水平、90 = 垂直。
  /// 供 P-System 偵測「club parallel（桿身水平，前臂代理）」事件用。
  static double? leadForearmFromHorizontalDeg(NativePoseResult f,
      {required bool leadIsLeft}) {
    final el = _pt(f, leadIsLeft ? kLElbow : kRElbow);
    final wr = _pt(f, leadIsLeft ? kLWrist : kRWrist);
    if (el == null || wr == null) return null;
    return _deg(math.atan2((wr.y - el.y).abs(), (wr.x - el.x).abs()));
  }

  /// 主導手臂（肩→腕）相對水平的傾角絕對值（度）：0 = 水平、90 = 垂直。
  /// 供 P-System 偵測「lead arm parallel（手臂水平）」事件用（P3/P5/P9）。
  static double? leadArmFromHorizontalDeg(NativePoseResult f,
      {required bool leadIsLeft}) {
    final sh = _pt(f, leadIsLeft ? kLShoulder : kRShoulder);
    final wr = _pt(f, leadIsLeft ? kLWrist : kRWrist);
    if (sh == null || wr == null) return null;
    return _deg(math.atan2((wr.y - sh.y).abs(), (wr.x - sh.x).abs()));
  }

  // ── 分級 ──────────────────────────────────────────────────────────────────

  /// 把數值對理想區間 [lo, hi] 分級；超出但在 ±[warn] 內 → warn，更遠 → bad。
  static BiomechGrade grade(double? value, double lo, double hi,
      {double warn = 0}) {
    if (value == null) return BiomechGrade.unknown;
    if (value >= lo && value <= hi) return BiomechGrade.good;
    final dist = value < lo ? lo - value : value - hi;
    return dist <= warn ? BiomechGrade.warn : BiomechGrade.bad;
  }

  // ── 工具 ───────────────────────────────────────────────────────────────────

  static double _deg(double rad) => rad * 180.0 / math.pi;

  /// 在頂點 [v] 的夾角（度）：向量 v→a 與 v→b 之間。
  static double _angleAt(_P v, _P a, _P b) {
    final ax = a.x - v.x, ay = a.y - v.y;
    final bx = b.x - v.x, by = b.y - v.y;
    final dot = ax * bx + ay * by;
    final na = math.sqrt(ax * ax + ay * ay);
    final nb = math.sqrt(bx * bx + by * by);
    if (na < 1e-9 || nb < 1e-9) return 0;
    final c = (dot / (na * nb)).clamp(-1.0, 1.0);
    return _deg(math.acos(c));
  }
}

/// 拍攝視角（決定旋轉類指標是否可信）。
enum SwingViewpoint { faceOn, downTheLine, unknown }

/// 指標分級。
enum BiomechGrade { good, warn, bad, unknown }

/// 單一生物力學指標：數值 + 理想區間 + 分級 + beta 標記。
class BiomechMetric {
  /// 指標 key（如 'x_factor' / 'spine_tilt'）。
  final String key;

  /// 量測值；null = 無法量測（landmark 缺 / 視角不可信）。
  final double? value;

  /// 理想區間（單位同 value）。
  final double idealLow, idealHigh;

  final BiomechGrade grade;

  /// true = 受 2D 投影/視角限制，僅供參考（旋轉/X-factor 類）。
  final bool beta;

  /// 'deg' | 'norm' | 'ratio'
  final String unit;

  const BiomechMetric({
    required this.key,
    required this.value,
    required this.idealLow,
    required this.idealHigh,
    required this.grade,
    this.beta = false,
    this.unit = 'deg',
  });

  /// 距理想區間的偏差（區間內為 0）；value 為 null → null。
  double? get deviation {
    final v = value;
    if (v == null) return null;
    if (v < idealLow) return idealLow - v;
    if (v > idealHigh) return v - idealHigh;
    return 0;
  }

  Map<String, dynamic> toJson() => {
        'key': key,
        if (value != null) 'value': value,
        'idealLow': idealLow,
        'idealHigh': idealHigh,
        'grade': grade.name,
        'beta': beta,
        'unit': unit,
      };

  factory BiomechMetric.fromJson(Map<String, dynamic> j) => BiomechMetric(
        key: j['key'] as String,
        value: (j['value'] as num?)?.toDouble(),
        idealLow: (j['idealLow'] as num?)?.toDouble() ?? 0,
        idealHigh: (j['idealHigh'] as num?)?.toDouble() ?? 0,
        grade: BiomechGrade.values.firstWhere(
          (g) => g.name == j['grade'],
          orElse: () => BiomechGrade.unknown,
        ),
        beta: j['beta'] as bool? ?? false,
        unit: j['unit'] as String? ?? 'deg',
      );
}

/// 內部座標點。
class _P {
  final double x, y;
  const _P(this.x, this.y);
}
