// ignore_for_file: constant_identifier_names
// 偵測常數與 Python tracker 同名同步（SCREAMING_CASE 刻意保留）
// ============================================================
// 動態檢測配置計算 (Python → Android/Dart 遷移)
// 
// 此文件實現 Python 版本的動態參數調整邏輯：
// - get_dynamic_detect_cfg() 隨追蹤進度變化
// - get_far_adaptive_cfg() 隨無檢測次數變化
// ============================================================

import 'dart:math' as math;

/// 檢測配置參數（Dart 計算 → 傳給 Kotlin）
class DetectionConfig {
  final int diffThresh;  // 幀差閾值
  final int areaLo;      // 最小面積
  final int areaHi;      // 最大面積
  final double circMin;  // 最小圓度

  const DetectionConfig({
    required this.diffThresh,
    required this.areaLo,
    required this.areaHi,
    required this.circMin,
  });

  /// 轉換為 MethodChannel 序列化格式
  Map<String, dynamic> toMap() => {
    'diffThresh': diffThresh,
    'areaLo': areaLo,
    'areaHi': areaHi,
    'circMin': circMin,
  };

  @override
  String toString() =>
      'DetectionConfig(diff=$diffThresh, area=[$areaLo..$areaHi], circ>=$circMin)';
}

/// Python 版本的基礎檢測配置
class BaseDetectionConfig {
  static const int AREA_RANGE_LO = 6;
  static const int AREA_RANGE_HI = 150;
  static const double CIRC_THRESH = 0.60;
  static const int DIFF_THRESH = 16;

  // ROI 配置
  static const int ROI_SIZE_INIT = 500;
  static const double CFG_SPEED = 0.4;
  static const int DIFF_MIN = 9;
  static const double CIRC_MIN = 0.60;
  static const int AREA_LO_MIN = 6;

  // 遠球自適應
  static const int FAR_DIFF_FLOOR = 3;
  static const double FAR_CIRC_FLOOR = 0.35;
  static const int FAR_AREA_LO_FLOOR = 1;
  static const double FAR_RELAX_GAIN = 1.0;
  static const double FAR_AREA_EMA_ALPHA = 0.20;

  // 步距衛士
  static const double STEP_EMA_ALPHA = 0.25;
  static const double STEP_GROWTH_FACTOR = 1.9;
  static const double STEP_ABS_MAX = 140.0;
}

/// 計算動態檢測配置
/// 
/// 參數:
///   pIndex - 追蹤點索引 (0=P0, 1=P1, 2+=追蹤中)
///   roiSize - 當前 ROI 尺寸 (像素)
///   noCandCount - 連續無檢測計數
///   areaEma - 面積 EMA 估計值
/// 
/// 返回: 動態計算的檢測配置
class DetectionConfigCalculator {
  /// Python 版本的 get_dynamic_detect_cfg() 實現
  static DetectionConfig getDynamicDetectConfig({
    required int pIndex,
    required int roiSize,
    int noCandCount = 0,
    double? areaEma,
  }) {
    // 1. ROI 尺寸歸一化
    double s = roiSize / BaseDetectionConfig.ROI_SIZE_INIT;
    s = math.max(0.20, math.min(1.0, s));  // clamp to [0.20, 1.0]

    // 2. 追蹤進度放鬆因子（越往後追蹤，參數越寬鬆）
    int t = math.max(pIndex - 1, 0);
    double tt = BaseDetectionConfig.CFG_SPEED * t;
    double relax = 1.0 / (1.0 + 0.45 * tt);

    // 3. 面積範圍計算
    int baseLo = BaseDetectionConfig.AREA_RANGE_LO;
    int baseHi = BaseDetectionConfig.AREA_RANGE_HI;

    int lo = ((baseLo * (s * s) * relax).round()).toInt();
    lo = math.max(BaseDetectionConfig.AREA_LO_MIN, 
                  math.min(lo, baseLo));

    int hi = ((baseHi * (s * s) * (0.80 + 0.20 * relax)).round()).toInt();
    hi = math.max(lo + 2, math.min(hi, baseHi));

    // 4. 幀差閾值計算
    double baseThr = BaseDetectionConfig.DIFF_THRESH.toDouble();
    double thr = baseThr * (0.55 * s + 0.45) * relax;
    thr = math.max(BaseDetectionConfig.DIFF_MIN.toDouble(),
                   math.min(thr, baseThr));

    // 5. 圓度計算
    double baseCirc = BaseDetectionConfig.CIRC_THRESH;
    double circ = baseCirc * (0.90 * relax + 0.10);
    circ = math.max(BaseDetectionConfig.CIRC_MIN,
                    math.min(circ, baseCirc));

    return DetectionConfig(
      diffThresh: thr.round(),
      areaLo: lo,
      areaHi: hi,
      circMin: circ,
    );
  }

  /// Python 版本的 get_far_adaptive_cfg() 實現
  /// 
  /// 遠球自適應檢測：球距離遠或被遮擋時，放寬檢測門檻
  static DetectionConfig getFarAdaptiveConfig({
    required DetectionConfig baseCfg,
    required int noCandCount,
    double? areaEma,
  }) {
    if (noCandCount <= 0) {
      return baseCfg;
    }

    // 1. 按無檢測次數放鬆門檻
    double k = noCandCount * BaseDetectionConfig.FAR_RELAX_GAIN;

    int lo0 = baseCfg.areaLo;
    int hi0 = baseCfg.areaHi;

    // 2. 面積範圍放寬
    int lo = math.max(
      BaseDetectionConfig.FAR_AREA_LO_FLOOR,
      (lo0 - 0.8 * k).round(),
    );
    int hi = (hi0 + 1.2 * k).round();

    // 3. 如果有面積 EMA 估計，以此為中心調整
    if (areaEma != null && areaEma > 0) {
      lo = math.min(lo, math.max(
        BaseDetectionConfig.FAR_AREA_LO_FLOOR,
        (areaEma * 0.35).round(),
      ));
      hi = math.max(hi, (areaEma * 2.8).round());
    }

    hi = math.max(lo + 2, hi);

    // 4. 幀差和圓度也放寬
    int newDiff = math.max(
      BaseDetectionConfig.FAR_DIFF_FLOOR,
      (baseCfg.diffThresh - 1.2 * k).round(),
    );

    double newCirc = math.max(
      BaseDetectionConfig.FAR_CIRC_FLOOR,
      baseCfg.circMin - 0.03 * k,
    );

    return DetectionConfig(
      diffThresh: newDiff,
      areaLo: lo,
      areaHi: hi,
      circMin: newCirc,
    );
  }
}

/// 追蹤狀態中的檢測配置管理器
/// 
/// 在 ball_tracker.dart 中使用，維護:
/// - 上一幀的配置
/// - 面積 EMA
/// - 步距 EMA
class TrackingConfigManager {
  DetectionConfig _lastConfig = DetectionConfig(
    diffThresh: BaseDetectionConfig.DIFF_THRESH,
    areaLo: BaseDetectionConfig.AREA_RANGE_LO,
    areaHi: BaseDetectionConfig.AREA_RANGE_HI,
    circMin: BaseDetectionConfig.CIRC_THRESH,
  );

  double? _areaEma;
  double? _stepEma;

  /// 取得當前配置（只讀）
  DetectionConfig get lastConfig => _lastConfig;

  /// 取得面積 EMA（只讀）
  double? get areaEma => _areaEma;

  /// 取得步距 EMA（只讀）
  double? get stepEma => _stepEma;

  /// 更新面積 EMA
  void updateAreaEma(double newArea) {
    if (_areaEma == null) {
      _areaEma = newArea;
    } else {
      _areaEma = (1.0 - BaseDetectionConfig.FAR_AREA_EMA_ALPHA) * _areaEma! +
                 BaseDetectionConfig.FAR_AREA_EMA_ALPHA * newArea;
    }
  }

  /// 更新步距 EMA
  void updateStepEma(double newStep) {
    if (_stepEma == null) {
      _stepEma = newStep;
    } else {
      _stepEma = (1.0 - BaseDetectionConfig.STEP_EMA_ALPHA) * _stepEma! +
                 BaseDetectionConfig.STEP_EMA_ALPHA * newStep;
    }
  }

  /// 重置所有狀態（追蹤重新開始）
  void reset() {
    _areaEma = null;
    _stepEma = null;
  }

  /// 計算新的動態配置並更新內部狀態
  DetectionConfig updateConfig({
    required int pIndex,
    required int roiSize,
    required int noCandCount,
  }) {
    // 1. 計算基礎動態配置
    _lastConfig = DetectionConfigCalculator.getDynamicDetectConfig(
      pIndex: pIndex,
      roiSize: roiSize,
      noCandCount: noCandCount,
      areaEma: _areaEma,
    );

    // 2. 應用遠球自適應
    if (noCandCount > 0) {
      _lastConfig = DetectionConfigCalculator.getFarAdaptiveConfig(
        baseCfg: _lastConfig,
        noCandCount: noCandCount,
        areaEma: _areaEma,
      );
    }

    return _lastConfig;
  }
}
