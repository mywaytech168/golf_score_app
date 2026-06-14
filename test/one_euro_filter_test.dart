// OneEuroFilter 單元測試
//
// 執行: flutter test test/one_euro_filter_test.dart

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:golf_score_app/recording/one_euro_filter.dart';

void main() {
  test('第一個樣本原值輸出', () {
    final f = OneEuroFilter();
    expect(f.filter(0.42, 0.0), 0.42);
  });

  test('常數輸入 → 輸出收斂回常數', () {
    final f = OneEuroFilter();
    double out = 0;
    for (var i = 0; i < 30; i++) {
      out = f.filter(0.5, i / 30);
    }
    expect(out, closeTo(0.5, 1e-6));
  });

  test('抖動輸入 → 變異顯著下降（去抖）', () {
    final f = OneEuroFilter(minCutoff: 0.6);
    final rnd = math.Random(42);
    final raw = <double>[];
    final filt = <double>[];
    for (var i = 0; i < 120; i++) {
      final v = 0.5 + (rnd.nextDouble() - 0.5) * 0.1; // ±0.05 抖動
      raw.add(v);
      filt.add(f.filter(v, i / 30));
    }
    double variance(List<double> xs) {
      final m = xs.reduce((a, b) => a + b) / xs.length;
      return xs.map((x) => (x - m) * (x - m)).reduce((a, b) => a + b) / xs.length;
    }
    // 跳過暖機前 10 幀
    expect(variance(filt.sublist(10)) < variance(raw.sublist(10)) * 0.5, isTrue);
  });

  test('dt<=0（時間非遞增）→ 重置為原值', () {
    final f = OneEuroFilter();
    f.filter(0.3, 1.0);
    expect(f.filter(0.8, 0.5), 0.8); // 時間倒退 → 回原值
  });

  test('reset 後第一個樣本原值輸出', () {
    final f = OneEuroFilter();
    f.filter(0.3, 0.0);
    f.filter(0.31, 0.033);
    f.reset();
    expect(f.filter(0.9, 0.0), 0.9);
  });
}
