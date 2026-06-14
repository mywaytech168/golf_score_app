// PSystemAnalyzer 端到端測試：合成 pose_landmarks.csv → 分析 → 驗證結構。
//
// 執行: flutter test test/p_system_analyzer_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:golf_score_app/models/p_system_metrics.dart';
import 'package:golf_score_app/services/biomechanics_service.dart';
import 'package:golf_score_app/services/p_system_analyzer.dart';

/// 產生 201 欄（frame,time,update_id + 33×6）的 face-on 靜態揮桿 CSV 字串。
String buildCsv({int frames = 60, double durationSec = 5.0}) {
  void set(List<num> cols, int idx, double x, double y) {
    final b = 3 + idx * 6;
    cols[b] = x; cols[b + 1] = y; cols[b + 2] = 0;
    cols[b + 3] = 1.0; cols[b + 4] = x * 1000; cols[b + 5] = y * 1000;
  }

  final sb = StringBuffer();
  sb.writeln(List.generate(201, (i) => 'c$i').join(','));
  for (int fr = 0; fr < frames; fr++) {
    final t = fr * durationSec / (frames - 1);
    final cols = List<num>.filled(201, 0);
    cols[0] = fr; cols[1] = t; cols[2] = fr;
    set(cols, 0, 0.50, 0.20);                       // nose
    set(cols, 11, 0.40, 0.35); set(cols, 12, 0.60, 0.35); // shoulders（寬 0.2 / 軀幹高 0.25 → faceOn）
    set(cols, 13, 0.38, 0.50); set(cols, 14, 0.62, 0.50); // elbows
    set(cols, 15, 0.40, 0.65); set(cols, 16, 0.60, 0.65); // wrists
    set(cols, 23, 0.45, 0.60); set(cols, 24, 0.55, 0.60); // hips
    set(cols, 27, 0.43, 0.95); set(cols, 28, 0.57, 0.95); // ankles
    sb.writeln(cols.join(','));
  }
  return sb.toString();
}

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('psys_test_');
    await File('${dir.path}/pose_landmarks.csv').writeAsString(buildCsv());
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('分析回傳完整 10 個 P 時刻且非遞減', () async {
    final ps = await PSystemAnalyzer.analyze(
      sessionDir: dir.path,
      p1Sec: 0.5, p4Sec: 2.0, p7Sec: 2.5, p10Sec: 4.0,
    );
    expect(ps, isNotNull);
    // 10 個 key 齊全
    for (final k in PSystemMetrics.order) {
      expect(ps!.pSec.containsKey(k), isTrue, reason: '缺 $k');
    }
    // 強錨點對齊輸入
    expect(ps!.pSec['p1'], closeTo(0.5, 1e-9));
    expect(ps.pSec['p4'], closeTo(2.0, 1e-9));
    expect(ps.pSec['p7'], closeTo(2.5, 1e-9));
    expect(ps.pSec['p10'], closeTo(4.0, 1e-9));
    // 非遞減
    for (int i = 1; i < PSystemMetrics.order.length; i++) {
      final prev = ps.pSec[PSystemMetrics.order[i - 1]]!;
      final cur = ps.pSec[PSystemMetrics.order[i]]!;
      expect(cur, greaterThanOrEqualTo(prev - 1e-9), reason: '逆序於 ${PSystemMetrics.order[i]}');
    }
  });

  test('face-on 視角被正確判定', () async {
    final ps = await PSystemAnalyzer.analyze(
      sessionDir: dir.path,
      p1Sec: 0.5, p4Sec: 2.0, p7Sec: 2.5, p10Sec: 4.0,
    );
    expect(ps!.viewpoint, SwingViewpoint.faceOn);
  });

  test('無 CSV → 回 null', () async {
    final empty = await Directory.systemTemp.createTemp('psys_empty_');
    final ps = await PSystemAnalyzer.analyze(
      sessionDir: empty.path,
      p1Sec: 0.5, p4Sec: 2.0, p7Sec: 2.5, p10Sec: 4.0,
    );
    expect(ps, isNull);
    await empty.delete(recursive: true);
  });

  test('angles.json 可存可讀回（round-trip）', () async {
    final ps = await PSystemAnalyzer.analyze(
      sessionDir: dir.path,
      p1Sec: 0.5, p4Sec: 2.0, p7Sec: 2.5, p10Sec: 4.0,
    );
    await ps!.save(dir.path);
    expect(File('${dir.path}/angles.json').existsSync(), isTrue);
    final back = await PSystemMetrics.load(dir.path);
    expect(back, isNotNull);
    expect(back!.pSec.length, 10);
    expect(back.viewpoint, ps.viewpoint);
  });
}
