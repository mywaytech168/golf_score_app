import 'dart:io';

import 'package:csv/csv.dart';

import 'one_euro_filter.dart';
import 'pose_result.dart';

/// 載入 `pose_landmarks.csv`，提供「依播放秒數取樣骨架」的能力，
/// 供前端 [SkeletonPainter] 疊圖使用（取代燒錄版 skeleton.mp4）。
///
/// 視覺一致性對齊 Android 原生 `SkeletonOverlayRenderer`：
///   ・雙向 EMA（alpha=0.35）平滑，消除 ML Kit 偵測抖動、等效零延遲。
///   ・缺幀時對相鄰兩幀線性插值，避免骨架閃爍消失。
///   ・座標採 x_norm / y_norm（歸一化、解析度無關），直接餵 CustomPainter。
class PoseTrack {
  /// 依 timeSec 升冪排序、已平滑的幀。
  final List<_SampledFrame> _frames;

  const PoseTrack._(this._frames);

  bool get isEmpty => _frames.isEmpty;
  int get frameCount => _frames.length;

  /// 依「原始整片時間軸」秒數取樣骨架。
  ///
  /// [timeSec] 應為 `clipStartSec + controller.position`，與原生燒錄的
  /// `origTimeSec = startSec + clipTimeSec` 對齊邏輯一致。
  ///
  /// 找不到完全相符的幀時，對相鄰兩幀做線性插值；超出範圍回傳 null。
  NativePoseResult? sampleAt(double timeSec) {
    if (_frames.isEmpty) return null;

    // 二分搜尋第一個 timeSec >= 目標的幀
    int lo = 0, hi = _frames.length - 1;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_frames[mid].timeSec < timeSec) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }

    final nextIdx = lo;
    final next = _frames[nextIdx];
    if (next.timeSec == timeSec || nextIdx == 0) {
      return next.toPose();
    }
    final prev = _frames[nextIdx - 1];
    final span = next.timeSec - prev.timeSec;
    if (span <= 0) return next.toPose();
    final t = ((timeSec - prev.timeSec) / span).clamp(0.0, 1.0);
    return _lerp(prev, next, t);
  }

  NativePoseResult _lerp(_SampledFrame a, _SampledFrame b, double t) {
    final lms = List<NativePoseLandmark>.generate(a.x.length, (i) {
      final ax = a.x[i], ay = a.y[i], av = a.vis[i];
      final bx = b.x[i], by = b.y[i], bv = b.vis[i];
      final aValid = !ax.isNaN, bValid = !bx.isNaN;
      if (aValid && bValid) {
        return NativePoseLandmark(
          x: ax + (bx - ax) * t,
          y: ay + (by - ay) * t,
          z: 0,
          visibility: av + (bv - av) * t,
        );
      }
      final src = aValid ? a : (bValid ? b : a);
      return NativePoseLandmark(
        x: src.x[i], y: src.y[i], z: 0, visibility: src.vis[i],
      );
    });
    return NativePoseResult(landmarks: lms, timestampMs: 0);
  }

  /// 從 `pose_landmarks.csv` 載入並平滑。檔案不存在或無有效資料回傳空 track。
  static Future<PoseTrack> load(String csvPath) async {
    final file = File(csvPath);
    if (!await file.exists()) return const PoseTrack._([]);

    final raw = await file.readAsString();
    final rows = const CsvToListConverter(eol: '\n', shouldParseNumbers: true)
        .convert(raw);
    if (rows.length < 2) return const PoseTrack._([]);

    // 欄位：frame, time_sec, pose_update_id, 然後每點 6 欄
    //   base = 3 + i*6 → [x_norm, y_norm, z, visibility, x_px, y_px]
    final frames = <_SampledFrame>[];
    for (var r = 1; r < rows.length; r++) {
      final cols = rows[r];
      if (cols.length < 201) continue;
      final timeSec = _toD(cols[1]);
      if (timeSec == null) continue;

      final x = List<double>.filled(33, double.nan);
      final y = List<double>.filled(33, double.nan);
      final vis = List<double>.filled(33, 0.0);
      for (var i = 0; i < 33; i++) {
        final base = 3 + i * 6;
        final xn = _toD(cols[base + 0]);
        final yn = _toD(cols[base + 1]);
        final v = _toD(cols[base + 3]) ?? 0.0;
        // 與原生一致：x_norm/y_norm 須 > 0 才視為有效偵測
        if (xn != null && yn != null && !xn.isNaN && !yn.isNaN &&
            xn > 0 && yn > 0) {
          x[i] = xn; y[i] = yn; vis[i] = v;
        }
      }
      frames.add(_SampledFrame(timeSec: timeSec, x: x, y: y, vis: vis));
    }

    if (frames.isEmpty) return const PoseTrack._([]);
    frames.sort((a, b) => a.timeSec.compareTo(b.timeSec));
    _smooth(frames);
    return PoseTrack._(frames);
  }

  /// 雙向 One-Euro：前向（自適應低通：慢速重平滑去抖、快速放寬避免拖尾）+ 後向 pass，
  /// 等效零延遲。取代固定 alpha EMA——靜止 address 與高速 downswing 雙態下表現更佳，
  /// 直接提升 P-System / BiomechanicsService 角度量化的穩定度。缺幀（NaN）跳過不更新。
  static void _smooth(List<_SampledFrame> frames) {
    if (frames.length < 3) return;
    for (var lm = 0; lm < 33; lm++) {
      final fx = OneEuroFilter(), fy = OneEuroFilter();
      for (final f in frames) {
        if (f.x[lm].isNaN) continue;
        f.x[lm] = fx.filter(f.x[lm], f.timeSec);
        f.y[lm] = fy.filter(f.y[lm], f.timeSec);
      }
      // 後向 pass（時間軸取負使 dt 為正）→ 抵銷前向相位延遲。
      final bx = OneEuroFilter(), by = OneEuroFilter();
      for (var i = frames.length - 1; i >= 0; i--) {
        final f = frames[i];
        if (f.x[lm].isNaN) continue;
        f.x[lm] = bx.filter(f.x[lm], -f.timeSec);
        f.y[lm] = by.filter(f.y[lm], -f.timeSec);
      }
    }
  }

  static double? _toD(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim());
    return null;
  }
}

class _SampledFrame {
  final double timeSec;
  final List<double> x;   // x_norm，NaN = 該點無效
  final List<double> y;
  final List<double> vis;

  _SampledFrame({required this.timeSec, required this.x, required this.y, required this.vis});

  NativePoseResult toPose() {
    final lms = List<NativePoseLandmark>.generate(x.length, (i) {
      final xi = x[i];
      return NativePoseLandmark(
        x: xi.isNaN ? 0 : xi,
        y: y[i].isNaN ? 0 : y[i],
        z: 0,
        visibility: xi.isNaN ? 0 : vis[i],
      );
    });
    return NativePoseResult(landmarks: lms, timestampMs: 0);
  }
}
