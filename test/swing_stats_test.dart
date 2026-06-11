// SwingStats 純計算測試：發射角（含旋轉/左飛）、節奏比、飛行時間
//
// 執行: flutter test test/swing_stats_test.dart

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:golf_score_app/recording/trajectory_painter.dart';
import 'package:golf_score_app/services/swing_stats_service.dart';

TrajectoryTrack trackFrom(List<(double, double, int)> pts,
    {int codedW = 1920, int codedH = 1080, int rotation = 0}) {
  return TrajectoryTrack(
    codedW: codedW,
    codedH: codedH,
    rotation: rotation,
    points: [
      for (final (x, y, us) in pts) TrajectoryPoint(x: x, y: y, ptsUs: us)
    ],
  );
}

void main() {
  group('發射角', () {
    test('向右上飛 45° → +45', () {
      // y 軸向下：每步 x+10, y-10
      final track = trackFrom([
        for (var i = 0; i < 6; i++) (100.0 + i * 10, 500.0 - i * 10, i * 33000)
      ]);
      final stats = SwingStats.compute(track: track);
      expect(stats.launchAngleDeg, closeTo(45.0, 0.5));
    });

    test('向左上飛 30° → +30（左打者方向不影響正負）', () {
      final dy = 10 * math.tan(30 * math.pi / 180);
      final track = trackFrom([
        for (var i = 0; i < 6; i++) (800.0 - i * 10, 500.0 - i * dy, i * 33000)
      ]);
      final stats = SwingStats.compute(track: track);
      expect(stats.launchAngleDeg, closeTo(30.0, 0.5));
    });

    test('rotation 90（直式影片）仍算出正確角度', () {
      // coded 空間 (x,y)，display = (codedH - y, x) / 旋轉後尺寸
      // 構造 display 空間 45° 向右上：display.dx 增、display.dy 減
      // dx_disp = -(dy_coded)、dy_disp = dx_coded → coded: y 減、x 減
      final track = trackFrom(
        [for (var i = 0; i < 6; i++) (500.0 - i * 10, 600.0 - i * 10, i * 33000)],
        rotation: 90,
      );
      final stats = SwingStats.compute(track: track);
      expect(stats.launchAngleDeg, closeTo(45.0, 0.5));
    });

    test('點數不足（<2）→ null', () {
      final track = trackFrom([(100, 500, 0)]);
      final stats = SwingStats.compute(track: track);
      expect(stats.launchAngleDeg, isNull);
      expect(stats.trajectoryPointCount, 1);
    });
  });

  group('飛行時間', () {
    test('首尾 ptsUs 差換算秒', () {
      final track = trackFrom([
        (100, 500, 0),
        (110, 490, 33000),
        (120, 480, 1500000),
      ]);
      final stats = SwingStats.compute(track: track);
      expect(stats.flightTimeSec, closeTo(1.5, 1e-9));
      expect(stats.trajectoryPointCount, 3);
    });
  });

  group('節奏', () {
    test('標準 3:1 揮桿', () {
      final phases = {
        'takeaway': 1.0,
        'top': 1.9, // 上桿 0.9s
        'impact': 2.2, // 下桿 0.3s
      };
      final stats = SwingStats.compute(phases: phases);
      expect(stats.backswingSec, closeTo(0.9, 1e-9));
      expect(stats.downswingSec, closeTo(0.3, 1e-9));
      expect(stats.tempoRatio, closeTo(3.0, 1e-9));
    });

    test('缺 top → 全為 null', () {
      final stats = SwingStats.compute(phases: {'takeaway': 1.0, 'impact': 2.2});
      expect(stats.tempoRatio, isNull);
      expect(stats.backswingSec, isNull);
    });

    test('下桿時間過短（≤0.05s，偵測雜訊）→ tempo null', () {
      final stats = SwingStats.compute(
          phases: {'takeaway': 1.0, 'top': 1.9, 'impact': 1.93});
      expect(stats.tempoRatio, isNull);
      expect(stats.downswingSec, closeTo(0.03, 1e-9));
    });
  });

  test('無軌跡無階段 → isEmpty', () {
    expect(SwingStats.compute().isEmpty, isTrue);
  });
}
