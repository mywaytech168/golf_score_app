// LiveSwingDetector 狀態機單元測試
//
// 餵入合成的腕部座標序列，驗證：
// 校準期 → listening → 速度峰值 triggered → fired（onImpact 時刻）
// 以及邊際峰值忽略、冷卻期、reset。
//
// 執行: flutter test test/live_swing_detector_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:golf_score_app/recording/live_swing_detector.dart';
import 'package:golf_score_app/recording/pose_result.dart';

/// 建一個只有右腕（index 16）有效的 33 點姿勢。
NativePoseResult poseAtWrist(double x, double y, {int tsMs = 0}) {
  final lms = List.generate(
    33,
    (i) => NativePoseLandmark(
      x: i == 16 ? x : 0.5,
      y: i == 16 ? y : 0.5,
      z: 0,
      visibility: i == 16 ? 0.9 : 0.0,
    ),
  );
  return NativePoseResult(landmarks: lms, timestampMs: tsMs);
}

/// 餵入固定腕位（靜止）直到 [untilSec]，30fps。回傳下一禎時刻。
double feedIdle(LiveSwingDetector det, double fromSec, double untilSec,
    {double x = 0.5, double y = 0.5}) {
  var t = fromSec;
  while (t < untilSec) {
    det.feed(poseAtWrist(x, y), t);
    t += 1 / 30;
  }
  return t;
}

/// 建一個雙腕（15=左、16=右）可分別設定座標/可見度的姿勢。
NativePoseResult poseBothWrists(
  double rx, double ry,
  double lx, double ly, {
  double rVis = 0.9,
  double lVis = 0.9,
  int tsMs = 0,
}) {
  final lms = List.generate(33, (i) {
    if (i == 16) return NativePoseLandmark(x: rx, y: ry, z: 0, visibility: rVis);
    if (i == 15) return NativePoseLandmark(x: lx, y: ly, z: 0, visibility: lVis);
    return const NativePoseLandmark(x: 0.5, y: 0.5, z: 0, visibility: 0.0);
  });
  return NativePoseResult(landmarks: lms, timestampMs: tsMs);
}

/// 雙腕皆可見的靜止餵入（站姿）—— 讓左右腕 prev 座標都被初始化。
double feedIdleBoth(LiveSwingDetector det, double fromSec, double untilSec) {
  var t = fromSec;
  while (t < untilSec) {
    det.feed(poseBothWrists(0.5, 0.5, 0.4, 0.5), t);
    t += 1 / 30;
  }
  return t;
}

void main() {
  group('LiveSwingDetector 雙手判斷', () {
    // 加速揮動序列：每禎位移遞增，遠超 floor 0.012 × 1.5
    const steps = [0.02, 0.06, 0.12, 0.20];

    test('雙手一起快速移動 → 觸發', () {
      var impacts = 0;
      final det = LiveSwingDetector(
        calibrationSec: 3.0, bothHands: true, onImpact: (_) => impacts++,
      );
      var t = feedIdleBoth(det, 0, 4.0);
      var x = 0.5;
      for (final dx in steps) {
        x += dx;
        det.feed(poseBothWrists(x, 0.5, x - 0.1, 0.5), t); // 雙腕同步前進
        t += 1 / 30;
      }
      for (var i = 0; i < 3; i++) {
        det.feed(poseBothWrists(x, 0.5, x - 0.1, 0.5), t);
        t += 1 / 30;
      }
      expect(impacts, 1);
    });

    test('僅單手快速移動、另一手有效但靜止 → 不觸發', () {
      var impacts = 0;
      final det = LiveSwingDetector(
        calibrationSec: 3.0, bothHands: true, onImpact: (_) => impacts++,
      );
      var t = feedIdleBoth(det, 0, 4.0);
      var x = 0.5;
      for (final dx in steps) {
        x += dx;
        det.feed(poseBothWrists(x, 0.5, 0.4, 0.5), t); // 左腕固定不動（同站姿位）
        t += 1 / 30;
      }
      for (var i = 0; i < 3; i++) {
        det.feed(poseBothWrists(x, 0.5, 0.4, 0.5), t);
        t += 1 / 30;
      }
      expect(impacts, 0);
      expect(det.state, SwingDetectState.listening);
    });

    test('一手被遮擋（不可見）→ 嚴格模式不觸發（無同禎雙手快）', () {
      var impacts = 0;
      final det = LiveSwingDetector(
        calibrationSec: 3.0, bothHands: true, onImpact: (_) => impacts++,
      );
      var t = feedIdleBoth(det, 0, 4.0);
      var x = 0.5;
      for (final dx in steps) {
        x += dx;
        // 左腕 vis=0（遮擋）→ 嚴格模式不免除，無「同禎雙手快」→ 不觸發
        det.feed(poseBothWrists(x, 0.5, 0.2, 0.5, lVis: 0.0), t);
        t += 1 / 30;
      }
      for (var i = 0; i < 3; i++) {
        det.feed(poseBothWrists(x, 0.5, 0.2, 0.5, lVis: 0.0), t);
        t += 1 / 30;
      }
      expect(impacts, 0);
      expect(det.state, SwingDetectState.listening);
    });

    test('關閉雙手判斷（預設）：單手快速移動即觸發', () {
      var impacts = 0;
      final det = LiveSwingDetector(
        calibrationSec: 3.0, onImpact: (_) => impacts++, // bothHands 預設 false
      );
      var t = feedIdleBoth(det, 0, 4.0);
      var x = 0.5;
      for (final dx in steps) {
        x += dx;
        det.feed(poseBothWrists(x, 0.5, 0.2, 0.5), t); // 左腕靜止亦觸發
        t += 1 / 30;
      }
      for (var i = 0; i < 3; i++) {
        det.feed(poseBothWrists(x, 0.5, 0.2, 0.5), t);
        t += 1 / 30;
      }
      expect(impacts, 1);
    });
  });

  group('LiveSwingDetector 狀態機', () {
    test('校準期內不偵測，期滿轉 listening', () {
      final det = LiveSwingDetector(calibrationSec: 3.0);
      var t = feedIdle(det, 0, 2.9);
      expect(det.state, SwingDetectState.calibrating);

      t = feedIdle(det, t, 3.2);
      expect(det.state, SwingDetectState.listening);
    });

    test('大幅揮動觸發 onImpact，impactTime 為峰值時刻', () {
      double? impactAt;
      final det = LiveSwingDetector(
        calibrationSec: 3.0,
        onImpact: (t) => impactAt = t,
      );
      var t = feedIdleBoth(det, 0, 4.0);

      // 加速揮動：每禎位移遞增至 0.20（遠超 floor 0.012 × 1.5）
      final steps = [0.02, 0.06, 0.12, 0.20];
      var x = 0.5;
      double peakTime = 0;
      for (final dx in steps) {
        x += dx;
        if (dx == 0.20) peakTime = t;
        det.feed(poseAtWrist(x, 0.5), t);
        t += 1 / 30;
      }
      // 峰值後回落（< peak × 0.80）連續 2 禎 → fired
      for (var i = 0; i < 3; i++) {
        det.feed(poseAtWrist(x, 0.5), t); // 靜止，速度 0
        t += 1 / 30;
      }

      expect(det.state, SwingDetectState.fired);
      expect(impactAt, isNotNull);
      expect(impactAt!, closeTo(peakTime, 1e-9));
    });

    test('垂直揮桿：開火時刻為弧線底部（下→上 過零），晚於腕速峰值', () {
      double? impactAt;
      final det = LiveSwingDetector(
        calibrationSec: 3.0,
        onImpact: (t) => impactAt = t,
      );
      var t = feedIdleBoth(det, 0, 4.0);

      // 下桿：y 遞增（向下）且加速，腕速峰值落在最大 dy 那禎
      double y = 0.30;
      double peakTime = 0;
      final downDys = [0.05, 0.12, 0.20, 0.18];
      for (final dy in downDys) {
        y += dy;
        if (dy == 0.20) peakTime = t; // 峰值時刻（最大位移）
        det.feed(poseAtWrist(0.5, y), t);
        t += 1 / 30;
      }
      // 弧線底部後上揚：y 遞減（向上）→ 垂直速度由 + 轉 −，應於此禎開火
      final crossTime = t;
      y -= 0.10;
      det.feed(poseAtWrist(0.5, y), t);
      t += 1 / 30;

      expect(det.state, SwingDetectState.fired);
      expect(impactAt, isNotNull);
      // 開火時刻 = 過零禎（弧底），且嚴格晚於腕速峰值時刻
      expect(impactAt!, closeTo(crossTime, 1e-9));
      expect(impactAt!, greaterThan(peakTime));
    });

    test('邊際峰值（< 門檻 1.5 倍）視為誤觸，不開火', () {
      double? impactAt;
      final det = LiveSwingDetector(
        calibrationSec: 3.0,
        onImpact: (t) => impactAt = t,
      );
      var t = feedIdleBoth(det, 0, 4.0);

      // 微小移動：剛過 floor 0.012 但 < 0.018（= thr × 1.5）
      det.feed(poseAtWrist(0.5 + 0.014, 0.5), t);
      t += 1 / 30;
      expect(det.state, SwingDetectState.triggered);

      for (var i = 0; i < 3; i++) {
        det.feed(poseAtWrist(0.5 + 0.014, 0.5), t);
        t += 1 / 30;
      }

      expect(impactAt, isNull);
      expect(det.state, SwingDetectState.listening);
    });

    test('冷卻期內不重複觸發，期滿恢復 listening', () {
      var impacts = 0;
      final det = LiveSwingDetector(
        calibrationSec: 3.0,
        cooldownSec: 5.0,
        onImpact: (_) => impacts++,
      );
      var t = feedIdleBoth(det, 0, 4.0);

      void swing() {
        var x = 0.5;
        for (final dx in [0.02, 0.06, 0.12, 0.20]) {
          x += dx;
          det.feed(poseAtWrist(x, 0.5), t);
          t += 1 / 30;
        }
        for (var i = 0; i < 3; i++) {
          det.feed(poseAtWrist(x, 0.5), t);
          t += 1 / 30;
        }
      }

      swing();
      expect(impacts, 1);
      expect(det.state, SwingDetectState.fired);

      // 冷卻期內再揮一次：不觸發
      swing();
      expect(impacts, 1);

      // 過冷卻期（fired 的 cooldownEnd 自第一次觸發起 5 秒）
      t = feedIdle(det, t, t + 6.0);
      expect(det.state, SwingDetectState.listening);
    });

    test('低可見度腕點不產生速度（不觸發）', () {
      var impacts = 0;
      final det = LiveSwingDetector(
        calibrationSec: 3.0,
        onImpact: (_) => impacts++,
      );
      var t = feedIdleBoth(det, 0, 4.0);

      // 大位移但 visibility 0 → 應被忽略
      final lms = List.generate(
        33,
        (i) => const NativePoseLandmark(x: 0.9, y: 0.9, z: 0, visibility: 0.0),
      );
      for (var i = 0; i < 5; i++) {
        det.feed(NativePoseResult(landmarks: lms, timestampMs: 0), t);
        t += 1 / 30;
      }

      expect(impacts, 0);
      expect(det.state, SwingDetectState.listening);
    });

    test('reset 後回到校準期', () {
      final det = LiveSwingDetector(calibrationSec: 3.0);
      feedIdle(det, 0, 4.0);
      expect(det.state, SwingDetectState.listening);

      det.reset();
      expect(det.state, SwingDetectState.calibrating);

      // reset 後校準時間重新起算
      det.feed(poseAtWrist(0.5, 0.5), 10.0);
      expect(det.state, SwingDetectState.calibrating);
      feedIdle(det, 10.0, 13.5);
      expect(det.state, SwingDetectState.listening);
    });
  });
}
