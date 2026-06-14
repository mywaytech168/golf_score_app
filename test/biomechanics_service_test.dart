// BiomechanicsService 幾何測試（純數學，合成骨架幀）
//
// 執行: flutter test test/biomechanics_service_test.dart

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:golf_score_app/recording/pose_result.dart';
import 'package:golf_score_app/services/biomechanics_service.dart';

/// 由 {index: (x, y)} 建立 33 點骨架幀；未列出的點為無效（vis=0）。
NativePoseResult frame(Map<int, (double, double)> pts) {
  final lms = List<NativePoseLandmark>.generate(33, (i) {
    final p = pts[i];
    return NativePoseLandmark(
      x: p?.$1 ?? 0,
      y: p?.$2 ?? 0,
      z: 0,
      visibility: p == null ? 0.0 : 1.0,
    );
  });
  return NativePoseResult(landmarks: lms, timestampMs: 0);
}

void main() {
  group('spineTiltDeg', () {
    test('完全直立 → 0°', () {
      final f = frame({
        BiomechanicsService.kLShoulder: (0.45, 0.40), BiomechanicsService.kRShoulder: (0.55, 0.40),
        BiomechanicsService.kLHip: (0.45, 0.60), BiomechanicsService.kRHip: (0.55, 0.60),
      });
      expect(BiomechanicsService.spineTiltDeg(f), closeTo(0.0, 0.01));
    });

    test('肩中點右移 → 正向傾角', () {
      final f = frame({
        BiomechanicsService.kLShoulder: (0.50, 0.40), BiomechanicsService.kRShoulder: (0.60, 0.40), // 肩中點 x=0.55
        BiomechanicsService.kLHip: (0.45, 0.60), BiomechanicsService.kRHip: (0.55, 0.60),           // 髖中點 x=0.50
      });
      // dx=0.05, dy=-0.2 → atan2(0.05,0.2)=14.04°
      expect(BiomechanicsService.spineTiltDeg(f),
          closeTo(math.atan2(0.05, 0.2) * 180 / math.pi, 0.01));
    });

    test('landmark 缺 → null', () {
      expect(BiomechanicsService.spineTiltDeg(frame({})), isNull);
    });
  });

  group('shoulderLineDeg', () {
    test('水平肩線 → 0°', () {
      final f = frame({BiomechanicsService.kLShoulder: (0.40, 0.40), BiomechanicsService.kRShoulder: (0.60, 0.40)});
      expect(BiomechanicsService.shoulderLineDeg(f), closeTo(0.0, 0.01));
    });
    test('右肩下沉 → 正角', () {
      final f = frame({BiomechanicsService.kLShoulder: (0.40, 0.40), BiomechanicsService.kRShoulder: (0.60, 0.45)});
      expect(BiomechanicsService.shoulderLineDeg(f),
          closeTo(math.atan2(0.05, 0.2) * 180 / math.pi, 0.01));
    });
  });

  group('viewpointOf', () {
    test('肩寬遠大於軀幹高 → faceOn', () {
      final f = frame({
        BiomechanicsService.kLShoulder: (0.35, 0.40), BiomechanicsService.kRShoulder: (0.65, 0.40), // 寬 0.30
        BiomechanicsService.kLHip: (0.40, 0.60), BiomechanicsService.kRHip: (0.60, 0.60),           // 軀幹高 0.20
      });
      expect(BiomechanicsService.viewpointOf(f), SwingViewpoint.faceOn);
    });
    test('雙肩幾乎重疊 → downTheLine', () {
      final f = frame({
        BiomechanicsService.kLShoulder: (0.50, 0.40), BiomechanicsService.kRShoulder: (0.53, 0.40), // 寬 0.03
        BiomechanicsService.kLHip: (0.50, 0.60), BiomechanicsService.kRHip: (0.53, 0.60),
      });
      expect(BiomechanicsService.viewpointOf(f), SwingViewpoint.downTheLine);
    });
  });

  group('weightShiftRatio', () {
    test('髖在雙踝正中 → 0', () {
      final f = frame({
        BiomechanicsService.kLHip: (0.45, 0.60), BiomechanicsService.kRHip: (0.55, 0.60),  // 髖中 0.50
        BiomechanicsService.kLAnkle: (0.40, 0.95), BiomechanicsService.kRAnkle: (0.60, 0.95), // 踝中 0.50, 站寬 0.20
      });
      expect(BiomechanicsService.weightShiftRatio(f), closeTo(0.0, 1e-9));
    });
    test('髖移向前腳半個站寬半徑 → 0.5', () {
      final f = frame({
        BiomechanicsService.kLHip: (0.50, 0.60), BiomechanicsService.kRHip: (0.60, 0.60),  // 髖中 0.55
        BiomechanicsService.kLAnkle: (0.40, 0.95), BiomechanicsService.kRAnkle: (0.60, 0.95), // 踝中 0.50, 半徑 0.10
      });
      expect(BiomechanicsService.weightShiftRatio(f), closeTo(0.5, 1e-9));
    });
  });

  group('leadElbowAngleDeg', () {
    test('手臂完全伸直 → 180°', () {
      final f = frame({
        BiomechanicsService.kLShoulder: (0.50, 0.30), BiomechanicsService.kLElbow: (0.50, 0.50), BiomechanicsService.kLWrist: (0.50, 0.70),
      });
      expect(BiomechanicsService.leadElbowAngleDeg(f, leadIsLeft: true),
          closeTo(180.0, 0.01));
    });
    test('直角彎肘 → 90°', () {
      final f = frame({
        BiomechanicsService.kLShoulder: (0.50, 0.50), BiomechanicsService.kLElbow: (0.50, 0.70), BiomechanicsService.kLWrist: (0.70, 0.70),
      });
      expect(BiomechanicsService.leadElbowAngleDeg(f, leadIsLeft: true),
          closeTo(90.0, 0.01));
    });
  });

  group('headDisplacement', () {
    test('鼻位移 0.1 → 0.1', () {
      final addr = frame({BiomechanicsService.kNose: (0.50, 0.30)});
      final cur = frame({BiomechanicsService.kNose: (0.50, 0.40)});
      expect(BiomechanicsService.headDisplacement(cur, addr), closeTo(0.1, 1e-9));
    });
  });

  group('grade', () {
    test('區間內 → good', () {
      expect(BiomechanicsService.grade(45, 35, 55), BiomechGrade.good);
    });
    test('超出但在 warn 內 → warn', () {
      expect(BiomechanicsService.grade(58, 35, 55, warn: 5), BiomechGrade.warn);
    });
    test('遠超 → bad', () {
      expect(BiomechanicsService.grade(70, 35, 55, warn: 5), BiomechGrade.bad);
    });
    test('null → unknown', () {
      expect(BiomechanicsService.grade(null, 35, 55), BiomechGrade.unknown);
    });
  });
}
