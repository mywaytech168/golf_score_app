// ============================================================
// 動態配置計算測試
// ============================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:golf_score_app/services/detection_config.dart';

void main() {
  group('DetectionConfigCalculator', () {
    test('getDynamicDetectConfig respects ROI size scaling', () {
      // P0 狀態，ROI 尺寸 500（100% 初始化）
      final cfg0 = DetectionConfigCalculator.getDynamicDetectConfig(
        pIndex: 0,
        roiSize: 500,
      );
      
      expect(cfg0.areaLo, lessThanOrEqualTo(6));
      expect(cfg0.areaHi, greaterThanOrEqualTo(100));
      expect(cfg0.circMin, greaterThan(0.5));
    });

    test('getDynamicDetectConfig relaxes with tracking progress', () {
      // 早期追蹤（p_index=5）
      final cfgEarly = DetectionConfigCalculator.getDynamicDetectConfig(
        pIndex: 5,
        roiSize: 500,
      );
      
      // 後期追蹤（p_index=50）
      final cfgLate = DetectionConfigCalculator.getDynamicDetectConfig(
        pIndex: 50,
        roiSize: 500,
      );
      
      // 後期應該更寬鬆（圓度下限更低）
      expect(cfgLate.circMin, lessThanOrEqualTo(cfgEarly.circMin));
    });

    test('getFarAdaptiveConfig relaxes on misses', () {
      final baseCfg = DetectionConfig(
        diffThresh: 16,
        areaLo: 6,
        areaHi: 150,
        circMin: 0.60,
      );
      
      // 0 次無檢測
      final cfg0 = DetectionConfigCalculator.getFarAdaptiveConfig(
        baseCfg: baseCfg,
        noCandCount: 0,
      );
      expect(cfg0.diffThresh, equals(baseCfg.diffThresh));
      
      // 3 次無檢測
      final cfg3 = DetectionConfigCalculator.getFarAdaptiveConfig(
        baseCfg: baseCfg,
        noCandCount: 3,
      );
      expect(cfg3.diffThresh, lessThan(baseCfg.diffThresh));
      expect(cfg3.circMin, lessThan(baseCfg.circMin));
    });

    test('getFarAdaptiveConfig uses areaEma when available', () {
      final baseCfg = DetectionConfig(
        diffThresh: 16,
        areaLo: 6,
        areaHi: 150,
        circMin: 0.60,
      );
      
      // 無 EMA
      final cfgNoEma = DetectionConfigCalculator.getFarAdaptiveConfig(
        baseCfg: baseCfg,
        noCandCount: 2,
        areaEma: null,
      );
      
      // 有 EMA
      final cfgWithEma = DetectionConfigCalculator.getFarAdaptiveConfig(
        baseCfg: baseCfg,
        noCandCount: 2,
        areaEma: 50.0,  // 球的估計面積
      );
      
      // 有 EMA 時面積範圍應更精確
      expect(cfgWithEma.areaLo, lessThanOrEqualTo(cfgNoEma.areaLo));
      expect(cfgWithEma.areaHi, greaterThanOrEqualTo(cfgNoEma.areaHi));
    });
  });

  group('TrackingConfigManager', () {
    test('updateConfig maintains consistency', () {
      final mgr = TrackingConfigManager();
      
      final cfg1 = mgr.updateConfig(
        pIndex: 5,
        roiSize: 400,
        noCandCount: 0,
      );
      
      expect(mgr.lastConfig, equals(cfg1));
    });

    test('areaEma updates incrementally', () {
      final mgr = TrackingConfigManager();
      
      mgr.updateAreaEma(50.0);
      expect(mgr.areaEma, equals(50.0));
      
      mgr.updateAreaEma(60.0);
      expect(mgr.areaEma, greaterThan(50.0));
      expect(mgr.areaEma, lessThan(60.0));  // EMA 平滑
    });

    test('reset clears state', () {
      final mgr = TrackingConfigManager();
      
      mgr.updateAreaEma(50.0);
      mgr.updateStepEma(30.0);
      
      expect(mgr.areaEma, isNotNull);
      expect(mgr.stepEma, isNotNull);
      
      mgr.reset();
      
      expect(mgr.areaEma, isNull);
      expect(mgr.stepEma, isNull);
    });
  });

  group('DetectionConfig serialization', () {
    test('toMap creates valid MethodChannel arguments', () {
      final cfg = DetectionConfig(
        diffThresh: 12,
        areaLo: 5,
        areaHi: 200,
        circMin: 0.50,
      );
      
      final map = cfg.toMap();
      
      expect(map['diffThresh'], equals(12));
      expect(map['areaLo'], equals(5));
      expect(map['areaHi'], equals(200));
      expect(map['circMin'], equals(0.50));
    });

    test('fromMap round-trip preserves values', () {
      final original = DetectionConfig(
        diffThresh: 14,
        areaLo: 4,
        areaHi: 180,
        circMin: 0.55,
      );
      
      final map = original.toMap();
      final restored = DetectionConfig(
        diffThresh: map['diffThresh'] as int,
        areaLo: map['areaLo'] as int,
        areaHi: map['areaHi'] as int,
        circMin: map['circMin'] as double,
      );
      
      expect(restored.diffThresh, equals(original.diffThresh));
      expect(restored.areaLo, equals(original.areaLo));
      expect(restored.areaHi, equals(original.areaHi));
      expect(restored.circMin, equals(original.circMin));
    });
  });

  group('Real-world scenarios', () {
    test('Scenario 1: Ball far away (small, low contrast)', () {
      // 球遠離（ROI 縮小到 300）
      final cfg = DetectionConfigCalculator.getDynamicDetectConfig(
        pIndex: 20,
        roiSize: 300,
      );
      
      // 門檻應該更寬鬆以捕捉小球
      expect(cfg.areaLo, lessThan(6));
      expect(cfg.circMin, lessThan(0.60));
    });

    test('Scenario 2: Ball occluded (multiple misses)', () {
      final baseCfg = DetectionConfig(
        diffThresh: 16,
        areaLo: 6,
        areaHi: 150,
        circMin: 0.60,
      );
      
      // 連續 5 次無檢測 + 面積 EMA 估計
      final cfg = DetectionConfigCalculator.getFarAdaptiveConfig(
        baseCfg: baseCfg,
        noCandCount: 5,
        areaEma: 40.0,
      );
      
      // 門檻應大幅放寬
      expect(cfg.diffThresh, lessThan(10));
      expect(cfg.areaLo, lessThan(5));
      expect(cfg.circMin, lessThan(0.40));
    });

    test('Scenario 3: Recovery after occlusion', () {
      final mgr = TrackingConfigManager();
      
      // 追蹤中
      mgr.updateAreaEma(45.0);
      mgr.updateStepEma(25.0);
      
      // 連續 2 次無檢測
      var cfg = mgr.updateConfig(
        pIndex: 15,
        roiSize: 420,  // ROI 擴大
        noCandCount: 2,
      );
      
      expect(cfg.diffThresh, lessThan(16));  // 門檻下降
      
      // 恢復檢測
      mgr.updateAreaEma(48.0);
      cfg = mgr.updateConfig(
        pIndex: 16,
        roiSize: 400,
        noCandCount: 0,  // 重置
      );
      
      // 門檻應恢復
      expect(cfg.diffThresh, greaterThan(10));
    });
  });
}
