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
      for (var i = 0; i < 8; i++) {
        det.feed(poseBothWrists(x, 0.5, x - 0.1, 0.5), t);
        t += 1 / 30;
      }
      expect(impacts, 1);
    });

    test('窗內確認：兩手在不同禎達門檻（非同禎）→ 仍觸發', () {
      var impacts = 0;
      final det = LiveSwingDetector(
        calibrationSec: 3.0, bothHands: true, onImpact: (_) => impacts++,
      );
      var t = feedIdleBoth(det, 0, 4.0);
      // 右腕先衝（左腕該禎僅微動 <0.12），下一段換左腕衝（右腕微動）——從不同禎達標，
      // 但兩腕全程都可見且夠近（gap≈0.1）。窗內確認應成立。
      var rx = 0.5, lx = 0.4;
      // 第一段：右腕大步、左腕小步
      for (final dx in [0.06, 0.14, 0.22]) {
        rx += dx; lx += 0.02;
        det.feed(poseBothWrists(rx, 0.5, lx, 0.5), t);
        t += 1 / 30;
      }
      // 第二段：左腕大步、右腕小步
      for (final dx in [0.14, 0.22, 0.16]) {
        lx += dx; rx += 0.02;
        det.feed(poseBothWrists(rx, 0.5, lx, 0.5), t);
        t += 1 / 30;
      }
      for (var i = 0; i < 8; i++) {
        det.feed(poseBothWrists(rx, 0.5, lx, 0.5), t);
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
      for (var i = 0; i < 8; i++) {
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
      for (var i = 0; i < 8; i++) {
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
      for (var i = 0; i < 8; i++) {
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
      for (var i = 0; i < 8; i++) {
        det.feed(poseAtWrist(x, 0.5), t); // 靜止，速度 0
        t += 1 / 30;
      }

      expect(det.state, SwingDetectState.fired);
      expect(impactAt, isNotNull);
      expect(impactAt!, closeTo(peakTime, 1e-9));
    });

    test('垂直揮桿：開火時刻為弧線底部（位置最低 + 窗確認），晚於腕速峰值', () {
      double? impactAt;
      final det = LiveSwingDetector(
        calibrationSec: 3.0,
        onImpact: (t) => impactAt = t,
      );
      var t = feedIdleBoth(det, 0, 4.0);

      // 下桿：y 遞增（向下）且加速，腕速峰值落在最大 dy 那禎、最低點在最後一個下降幀
      double y = 0.30;
      double peakTime = 0, bottomTime = 0;
      final downDys = [0.05, 0.12, 0.20, 0.18];
      for (var i = 0; i < downDys.length; i++) {
        final dy = downDys[i];
        y += dy;
        if (dy == 0.20) peakTime = t;                    // 腕速峰值時刻
        if (i == downDys.length - 1) bottomTime = t;     // 最低點（影像 y 最大）那一幀
        det.feed(poseAtWrist(0.5, y), t);
        t += 1 / 30;
      }
      // 弧底後連續上升 2 幀（窗確認）→ 開火，回報最低點那一幀的時刻
      y -= 0.10; det.feed(poseAtWrist(0.5, y), t); t += 1 / 30;
      y -= 0.10; det.feed(poseAtWrist(0.5, y), t); t += 1 / 30;

      expect(det.state, SwingDetectState.fired);
      expect(impactAt, isNotNull);
      // 開火時刻 = 最低點那一幀（非偵測當下），且嚴格晚於腕速峰值時刻
      expect(impactAt!, closeTo(bottomTime, 1e-9));
      expect(impactAt!, greaterThan(peakTime));
    });

    test('錨點模式：開火於主導腕回到錨點(球位)最近那一幀', () {
      double? impactAt;
      final det = LiveSwingDetector(
        calibrationSec: 3.0,
        onImpact: (t) => impactAt = t,
      )
        ..anchorX = 0.5
        ..anchorY = 0.70 // 點選預覽設定的球位
        ..useAnchorHit = true;
      // 站姿在錨點上方靜止
      var t = feedIdle(det, 0, 4.0, x: 0.5, y: 0.30);
      // 下桿：腕由上往下逼近錨點，最近在 y=0.70，之後越過遠離（連續 2 幀遠離確認）
      final ys = [0.45, 0.60, 0.70, 0.74, 0.78];
      double closestTime = 0;
      for (final y in ys) {
        if (y == 0.70) closestTime = t;
        det.feed(poseAtWrist(0.5, y), t);
        t += 1 / 30;
      }
      expect(det.state, SwingDetectState.fired);
      expect(impactAt, isNotNull);
      // 擊球時刻 = 最接近錨點那一幀（非弧底、非偵測當下）
      expect(impactAt!, closeTo(closestTime, 1e-9));
    });

    test('錨點模式：純水平揮（無向下運動）仍由「回歸錨點」開火，不退回峰值', () {
      double? impactAt;
      final det = LiveSwingDetector(
        calibrationSec: 3.0,
        onImpact: (t) => impactAt = t,
      )
        ..anchorX = 0.30
        ..anchorY = 0.50 // 球位在左側，水平揮過去
        ..useAnchorHit = true;
      // 站姿在錨點上靜止（address＝impact＝同點）
      var t = feedIdle(det, 0, 4.0, x: 0.30, y: 0.50);
      // 上桿：水平向右離開錨點（y 不變→無向下運動，_sawDownward 永遠 false）
      final back = [0.42, 0.55, 0.66];
      for (final x in back) {
        det.feed(poseAtWrist(x, 0.50), t);
        t += 1 / 30;
      }
      // 下桿：水平回到錨點再越過（最近在 x=0.30）
      final fwd = [0.50, 0.38, 0.30, 0.24, 0.18];
      double closestTime = 0;
      for (final x in fwd) {
        if (x == 0.30) closestTime = t;
        det.feed(poseAtWrist(x, 0.50), t);
        t += 1 / 30;
      }
      expect(det.state, SwingDetectState.fired);
      expect(impactAt, isNotNull);
      // 開火於最接近錨點那一幀，而非速度峰值（驗證 _sawDownward 邊際漏洞已修）
      expect(impactAt!, closeTo(closestTime, 1e-9));
    });

    test('錨點模式：回歸最近距離超出命中半徑 → 不採錨點時刻，退回峰值', () {
      double? impactAt;
      final det = LiveSwingDetector(
        calibrationSec: 3.0,
        onImpact: (t) => impactAt = t,
      )
        ..anchorX = 0.20
        ..anchorY = 0.50
        ..useAnchorHit = true
        ..swingSpeedFloor = 0.10 // 本測測半徑非門檻，壓低門檻讓合成揮桿能開火
        ..anchorHitRadius = 0.08; // 收緊：最近須 ≤0.08
      var t = feedIdle(det, 0, 4.0, x: 0.50, y: 0.50);
      // 水平揮：離開錨點後回歸，但最近只到 x=0.40（距錨點 0.20 > 半徑 0.08）
      final xs = [0.62, 0.74, 0.62, 0.48, 0.40, 0.50, 0.62];
      double closestTime = 0;
      for (final x in xs) {
        if (x == 0.40) closestTime = t; // 距錨點最近的那一幀（但仍 >半徑）
        det.feed(poseAtWrist(x, 0.50), t);
        t += 1 / 30;
      }
      // 補幾幀讓 fallback 視窗成立
      for (var i = 0; i < 8; i++) {
        det.feed(poseAtWrist(0.62, 0.50), t);
        t += 1 / 30;
      }
      expect(det.state, SwingDetectState.fired);
      expect(impactAt, isNotNull);
      // 最近距離超出半徑 → 不應停在「錨點最近幀」，而是退回峰值時刻（不同幀）
      expect((impactAt! - closestTime).abs(), greaterThan(1 / 60));
    });

    test('錨點閘門：揮桿未經過錨點半徑內 → 不算一桿（亂揮不誤判）', () {
      var impacts = 0;
      final det = LiveSwingDetector(
        calibrationSec: 3.0,
        onImpact: (_) => impacts++,
      )
        ..anchorX = 0.10
        ..anchorY = 0.10     // 錨點在左上角
        ..anchorGate = true  // 閘門開（時刻方法維持 V1 弧底）
        ..anchorHitRadius = 0.15;
      // 在畫面右下大幅揮桿（離錨點很遠，從未進入半徑）
      var t = feedIdle(det, 0, 4.0, x: 0.80, y: 0.80);
      double y = 0.80;
      for (final dy in [0.05, 0.12, 0.20, 0.18]) {
        y += dy;
        det.feed(poseAtWrist(0.80, y), t);
        t += 1 / 30;
      }
      for (var i = 0; i < 8; i++) {
        det.feed(poseAtWrist(0.80, y), t);
        t += 1 / 30;
      }
      expect(impacts, 0); // 閘門擋下：揮桿未經過錨點
      expect(det.state, SwingDetectState.listening);
    });

    test('錨點閘門：揮桿有經過錨點半徑內 → 正常算一桿', () {
      var impacts = 0;
      final det = LiveSwingDetector(
        calibrationSec: 3.0,
        onImpact: (_) => impacts++,
      )
        ..anchorX = 0.50
        ..anchorY = 0.80     // 錨點在揮桿路徑底部
        ..anchorGate = true
        ..anchorHitRadius = 0.15;
      var t = feedIdle(det, 0, 4.0, x: 0.50, y: 0.50);
      double y = 0.50;
      // 向下揮經過 y≈0.80（進入錨點半徑）
      for (final dy in [0.08, 0.14, 0.20]) {
        y += dy;
        det.feed(poseAtWrist(0.50, y), t);
        t += 1 / 30;
      }
      for (var i = 0; i < 8; i++) {
        det.feed(poseAtWrist(0.50, y), t);
        t += 1 / 30;
      }
      expect(impacts, 1);
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

      for (var i = 0; i < 8; i++) {
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
        for (var i = 0; i < 8; i++) {
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

    test('自校準：校準期雜訊抬高門檻 → 抑制 waggle 級中等揮動', () {
      var impacts = 0;
      final det = LiveSwingDetector(calibrationSec: 3.0, onImpact: (_) => impacts++);
      // 校準期腕點來回晃動，每禎位移 ~0.07（waggle/手抖等級）→ baseline≈0.07、floor≈0.175
      var t = 0.0;
      var fwd = true;
      while (t < 3.5) {
        det.feed(poseAtWrist(fwd ? 0.57 : 0.5, 0.5), t);
        fwd = !fwd;
        t += 1 / 30;
      }
      // 中等揮動 peak ~0.16（> 預設 floor 0.15，靜止校準下會開火，但 < 自校準 floor 0.175）
      var x = 0.5;
      for (final dx in [0.04, 0.09, 0.16]) {
        x += dx;
        det.feed(poseAtWrist(x, 0.5), t);
        t += 1 / 30;
      }
      for (var i = 0; i < 10; i++) {
        det.feed(poseAtWrist(x, 0.5), t);
        t += 1 / 30;
      }
      expect(impacts, 0, reason: '自校準基線抬高門檻應抑制 waggle 級揮動');
    });

    test('自校準對照：靜止校準下同等中等揮動 → 正常開火', () {
      var impacts = 0;
      final det = LiveSwingDetector(calibrationSec: 3.0, onImpact: (_) => impacts++);
      var t = feedIdle(det, 0, 3.5); // 靜止校準 → baseline≈0
      var x = 0.5;
      for (final dx in [0.04, 0.09, 0.16]) {
        x += dx;
        det.feed(poseAtWrist(x, 0.5), t);
        t += 1 / 30;
      }
      for (var i = 0; i < 10; i++) {
        det.feed(poseAtWrist(x, 0.5), t);
        t += 1 / 30;
      }
      expect(impacts, 1);
    });
  });
}
