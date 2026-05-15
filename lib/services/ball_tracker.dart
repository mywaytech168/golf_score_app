import 'dart:math' as math;
import 'dart:typed_data';

// ============================================================
// Data types (MethodChannel 雙向傳遞)
// ============================================================

/// 單個 blob 候選球（由 Kotlin 偵測，傳到 Dart 決策）
class BlobData {
  final int cx;
  final int cy;
  final int area;
  final double circ;
  final double diffMean; // blob 內幀差均值

  const BlobData({
    required this.cx,
    required this.cy,
    required this.area,
    required this.circ,
    this.diffMean = 0,
  });

  factory BlobData.fromMap(Map<Object?, Object?> m) => BlobData(
        cx: (m['cx'] as num).toInt(),
        cy: (m['cy'] as num).toInt(),
        area: (m['area'] as num).toInt(),
        circ: (m['circ'] as num).toDouble(),
        diffMean: (m['diffMean'] as num?)?.toDouble() ?? 0,
      );
}

/// 單幀資料（時間戳 + blob 列表）
class FrameBlobs {
  final int ptsUs; // 幀在影片中的呈現時間（微秒）
  final List<BlobData> blobs;

  const FrameBlobs({required this.ptsUs, required this.blobs});

  factory FrameBlobs.fromMap(Map<Object?, Object?> m) {
    final rawBlobs = m['blobs'] as List<Object?>;
    return FrameBlobs(
      ptsUs: (m['ptsUs'] as num).toInt(),
      blobs: rawBlobs
          .map((b) => BlobData.fromMap(b as Map<Object?, Object?>))
          .toList(),
    );
  }
}

/// 單個追蹤點（Dart 決策後傳回 Kotlin 渲染）
class TrackPoint {
  final int x;
  final int y;
  final int frameIdx;
  final int ptsUs;

  const TrackPoint({
    required this.x,
    required this.y,
    required this.frameIdx,
    required this.ptsUs,
  });

  Map<String, dynamic> toMap() => {'x': x, 'y': y, 'pts': ptsUs};
}

// ============================================================
// Kalman2D
// 完整移植自 Python KalmanFilter2D（常速模型）
// ============================================================
class Kalman2D {
  final double dt;

  // 狀態向量 [px, py, vx, vy]
  final Float64List _x = Float64List(4);

  // 協方差矩陣 4×4（row-major）
  final Float64List _P = Float64List(16);

  // 系統矩陣 A（常速）
  late final Float64List _A;

  // 過程噪聲 Q
  late final Float64List _Q;

  // 量測噪聲 R（2×2）
  final Float64List _R = Float64List.fromList([10, 0, 0, 10]);

  bool initialized = false;

  Kalman2D({required this.dt}) {
    // A = [[1,0,dt,0],[0,1,0,dt],[0,0,1,0],[0,0,0,1]]
    _A = Float64List.fromList([
      1, 0, dt, 0,
      0, 1, 0, dt,
      0, 0, 1, 0,
      0, 0, 0, 1,
    ]);
    // Q = diag([3, 3, 120, 120])
    _Q = Float64List.fromList([
      3, 0, 0, 0,
      0, 3, 0, 0,
      0, 0, 120, 0,
      0, 0, 0, 120,
    ]);
    // P = 1000 × I
    for (int i = 0; i < 4; i++) _P[i * 4 + i] = 1000;
  }

  /// 從兩個已知點初始化（對應 Python initialize_from_two_points）
  void initFromPoints(double p0x, double p0y, double p1x, double p1y) {
    final safeDt = math.max(dt, 1e-6);
    _x[0] = p1x; _x[1] = p1y;
    _x[2] = (p1x - p0x) / safeDt;
    _x[3] = (p1y - p0y) / safeDt;
    // P = diag([80, 80, 900, 900])
    for (int i = 0; i < 16; i++) _P[i] = 0;
    _P[0] = 80; _P[5] = 80; _P[10] = 900; _P[15] = 900;
    initialized = true;
  }

  /// 預測步（Python: predict）
  void predict() {
    // x = A × x
    final nx = _mat41(_A, _x);
    _x.setAll(0, nx);
    // P = A × P × A^T + Q
    final AP = _mat44(_A, _P);
    final AT = _mat44T(_A);
    final APAT = _mat44(AP, AT);
    for (int i = 0; i < 16; i++) _P[i] = APAT[i] + _Q[i];
  }

  /// 更新步（Python: update）
  void update(double zx, double zy) {
    // y = z - H×x  （H 取 x 的前兩維）
    final yx = zx - _x[0];
    final yy = zy - _x[1];

    // S = H×P×H^T + R  → S 的各元素就是 P 的左上 2×2 子塊 + R
    // H = [[1,0,0,0],[0,1,0,0]] → H×P = rows 0,1 of P
    // HP × H^T = cols 0,1 of HP
    final s00 = _P[0] + _R[0];
    final s01 = _P[1] + _R[1];
    final s10 = _P[4] + _R[2];
    final s11 = _P[5] + _R[3];

    // S^-1（2×2 逆矩陣）
    final det = s00 * s11 - s01 * s10;
    final dInv = (det.abs() < 1e-8) ? 0.0 : 1.0 / det;
    final si00 = s11 * dInv; final si01 = -s01 * dInv;
    final si10 = -s10 * dInv; final si11 = s00 * dInv;

    // K = P × H^T × S^-1  （4×2 × 2×2 → 4×2）
    // P × H^T = cols 0,1 of P  (4×2 matrix: PHt[i][j] = P[i][j])
    // K[i][j] = sum_k PHt[i][k] × Si[k][j]
    final k = Float64List(8);
    for (int i = 0; i < 4; i++) {
      final ph0 = _P[i * 4 + 0]; // PHt[i][0] = P[i][0]
      final ph1 = _P[i * 4 + 1]; // PHt[i][1] = P[i][1]
      k[i * 2 + 0] = ph0 * si00 + ph1 * si10;
      k[i * 2 + 1] = ph0 * si01 + ph1 * si11;
    }

    // x = x + K × y
    for (int i = 0; i < 4; i++) {
      _x[i] += k[i * 2 + 0] * yx + k[i * 2 + 1] * yy;
    }

    // P = (I - K×H) × P
    // (I-KH)[i][l] = (i==l ? 1 : 0) - KH[i][l]
    // KH[i][l] = K[i][0] if l==0, K[i][1] if l==1, 0 otherwise
    final newP = Float64List(16);
    for (int i = 0; i < 4; i++) {
      for (int j = 0; j < 4; j++) {
        double sum = 0;
        for (int l = 0; l < 4; l++) {
          final khl    = (l == 0) ? k[i * 2 + 0] : (l == 1) ? k[i * 2 + 1] : 0.0;
          final imkhl  = (i == l ? 1.0 : 0.0) - khl;
          sum += imkhl * _P[l * 4 + j];
        }
        newP[i * 4 + j] = sum;
      }
    }
    _P.setAll(0, newP);
  }

  (double, double) get pos => (_x[0], _x[1]);

  // ------ 矩陣輔助 ------

  static Float64List _mat41(Float64List A, Float64List v) {
    final r = Float64List(4);
    for (int i = 0; i < 4; i++) {
      double s = 0;
      for (int k = 0; k < 4; k++) s += A[i * 4 + k] * v[k];
      r[i] = s;
    }
    return r;
  }

  static Float64List _mat44(Float64List A, Float64List B) {
    final C = Float64List(16);
    for (int i = 0; i < 4; i++) {
      for (int j = 0; j < 4; j++) {
        double s = 0;
        for (int k = 0; k < 4; k++) s += A[i * 4 + k] * B[k * 4 + j];
        C[i * 4 + j] = s;
      }
    }
    return C;
  }

  static Float64List _mat44T(Float64List A) {
    final B = Float64List(16);
    for (int i = 0; i < 4; i++) {
      for (int j = 0; j < 4; j++) B[i * 4 + j] = A[j * 4 + i];
    }
    return B;
  }
}
