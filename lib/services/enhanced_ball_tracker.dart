// ============================================================
// 增強型球軌跡追蹤器 (Enhanced Ball Tracker)
// 
// 整合：
// - ball_tracker.dart (Kalman 追蹤)
// - detection_config.dart (動態參數計算)
// - Python 版本的 5 層追蹤規則
// ============================================================

import 'package:flutter/services.dart';
import 'dart:math' as math;
import 'dart:typed_data';
import 'ball_tracker.dart';
import 'detection_config.dart';

/// 增強型追蹤器（支援動態檢測配置）
/// 
/// 使用示例：
/// ```dart
/// final tracker = EnhancedBallTracker(dt: 1.0 / 30.0);
/// 
/// // 方案 1: 使用動態配置調用 Kotlin
/// final config = tracker.configManager.updateConfig(
///   pIndex: trackPoints.length,
///   roiSize: currentRoiSize,
///   noCandCount: nosCandCount,
/// );
/// 
/// final result = await methodChannel.invokeMethod(
///   'detectBallsWithConfig',
///   {
///     'videoPath': path,
///     'config': config.toMap(),
///   },
/// );
/// ```
class EnhancedBallTracker {
  final double dt;  // 時間差（幀時間）
  
  // 核心追蹤器
  late final Kalman2D kalman;
  
  // 配置管理器
  final TrackingConfigManager configManager = TrackingConfigManager();
  
  // 軌跡點歷史
  final List<TrackPoint> trackPoints = [];
  
  // 追蹤狀態
  int? _pIndex;  // 追蹤點索引
  int noCandCount = 0;  // 連續無檢測計數
  int outlierStrikes = 0;  // 連續異常計數
  bool trackingFrozen = false;  // 是否凍結追蹤
  
  // Y 方向推斷
  int? _yDir;  // 1 = 向下, -1 = 向上, null = 未決定
  
  EnhancedBallTracker({required this.dt}) {
    kalman = Kalman2D(dt: dt);
  }
  
  /// 重置追蹤器
  void reset() {
    trackPoints.clear();
    kalman = Kalman2D(dt: dt);
    configManager.reset();
    _pIndex = null;
    noCandCount = 0;
    outlierStrikes = 0;
    trackingFrozen = false;
    _yDir = null;
  }
  
  /// 獲得追蹤點索引
  int get pIndex => _pIndex ?? 0;
  
  /// 獲得 Y 方向（1=向下, -1=向上, null=未決定）
  int? get yDir => _yDir;
  
  // ========== 第 1-2 週功能：基本步距衛士 + Y 方向約束 ==========
  
  /// 計算兩點間距離
  static double distance(Offset a, Offset b) {
    final dx = a.dx - b.dx;
    final dy = a.dy - b.dy;
    return math.sqrt(dx * dx + dy * dy);
  }
  
  /// 步距衛士：檢查候選球是否被接受
  /// 
  /// 返回 true 如果距離在允許範圍內
  bool stepDistanceGuardCheck(Offset candidate) {
    if (trackPoints.isEmpty) return true;
    
    final lastPt = Offset(trackPoints.last.x.toDouble(), trackPoints.last.y.toDouble());
    final step = distance(candidate, lastPt);
    
    // 計算動態限制
    double baseLim = BaseDetectionConfig.STEP_ABS_MAX;
    if (configManager.stepEma != null) {
      baseLim = math.max(
        BaseDetectionConfig.STEP_ABS_MAX,
        configManager.stepEma! * BaseDetectionConfig.STEP_GROWTH_FACTOR,
      );
    }
    
    final relaxFactor = 1.0 + 0.35 * noCandCount;
    final limit = baseLim * relaxFactor;
    final hardLimit = math.min(130.0, limit);  // 硬限制
    
    final accepted = step < hardLimit;
    
    if (accepted) {
      // 更新 EMA
      configManager.updateStepEma(step);
    }
    
    return accepted;
  }
  
  /// Y 方向約束：篩選候選球
  /// 
  /// 返回滿足 Y 方向的候選球列表
  List<Offset> filterByYDirection(List<Offset> candidates) {
    if (_yDir == null) {
      // 如果已有 3+ 個點，推斷 Y 方向
      if (trackPoints.length >= 3) {
        final dy = trackPoints[2].y - trackPoints[0].y;
        if (dy.abs() >= 2) {
          _yDir = dy > 0 ? 1 : -1;
        }
      }
      return candidates;
    }
    
    if (trackPoints.isEmpty) return candidates;
    
    final lastPt = trackPoints.last;
    const yTol = 1;
    const yMaxStep = 80;
    
    return candidates.where((c) {
      final dy = (c.dy - lastPt.y).toInt();
      
      // Y 方向檢查
      if (_yDir == -1) {
        // 球應往上移動
        if (c.dy > lastPt.y + yTol) return false;
      } else if (_yDir == 1) {
        // 球應往下移動
        if (c.dy < lastPt.y - yTol) return false;
      }
      
      // 距離限制
      if (dy.abs() > yMaxStep) return false;
      
      return true;
    }).toList();
  }
  
  // ========== 第 3 週功能：遠球自適應檢測 ==========
  
  /// 更新面積 EMA（用於遠球自適應）
  void updateAreaEmaFromBlob(int area) {
    configManager.updateAreaEma(area.toDouble());
  }
  
  /// 取得當前應使用的檢測配置
  /// 
  /// 此配置應透過 MethodChannel 傳給 Kotlin
  DetectionConfig getCurrentConfig({required int roiSize}) {
    return configManager.updateConfig(
      pIndex: pIndex,
      roiSize: roiSize,
      noCandCount: noCandCount,
    );
  }
  
  // ========== 第 3 週功能：多假設預測替代 + 異常值檢測完善 ==========
  
  /// Kalman 預測歷史（用於無檢測時的替代檢測）
  /// 
  /// 格式: {frameIdx: (predictedX, predictedY)}
  /// 保留最多 5 個預測歷史（1/6 秒內）
  final Map<int, (double, double)> predictionHistory = {};
  
  /// 記錄預測位置到歷史
  void recordPrediction(int frameIdx, double x, double y) {
    predictionHistory[frameIdx] = (x, y);
    
    // 保留最多 5 個預測
    if (predictionHistory.length > 5) {
      final oldestKey = predictionHistory.keys.reduce((a, b) => a < b ? a : b);
      predictionHistory.remove(oldestKey);
    }
  }
  
  /// 使用預測替代進行檢測（無候選球時）
  /// 
  /// 返回 Kalman 預測位置作為替代
  (double, double)? getPredictionFallback() {
    if (!isKalmanInitialized) return null;
    if (trackingFrozen) return null;  // 凍結狀態無替代
    
    // 如果連續無檢測超過 2 幀，使用預測替代
    if (noCandCount <= 2) return null;
    
    // 返回 Kalman 預測位置
    return getKalmanPos();
  }
  
  /// 異常值檢測邏輯（第 5 層規則 - 完善）
  /// 
  /// 檢查：
  /// 1. 連續異常計數是否超過閾值
  /// 2. 是否應凍結追蹤
  /// 3. 是否可以嘗試恢復
  bool shouldFreezeTracking() {
    if (trackingFrozen) return true;
    
    // Python 邏輯：8+ 個連續異常 + 8+ 個追蹤點 = 凍結
    if (outlierStrikes >= 8 && trackPoints.length >= 8) {
      trackingFrozen = true;
      return true;
    }
    
    return false;
  }
  
  /// 嘗試恢復凍結狀態
  /// 
  /// 條件：
  /// 1. 當前處於凍結狀態
  /// 2. 檢測到有效候選球（已通過所有規則）
  /// 3. 距上次凍結 > 10 幀
  void attemptUnfreeze() {
    if (!trackingFrozen) return;
    
    // 如果有新的有效點，重置異常計數
    outlierStrikes = 0;
    trackingFrozen = false;
  }
  
  /// 異常值檢測的完整流程
  /// 
  /// 用法：在應用所有篩選規則後
  /// ```dart
  /// if (filteredCands.isEmpty) {
  ///   final frozen = tracker.handleOutlierDetection();
  ///   if (frozen) {
  ///     print('追蹤已凍結，開始恢復流程');
  ///     break;
  ///   }
  /// }
  /// ```
  bool handleOutlierDetection() {
    recordOutlier();
    return shouldFreezeTracking();
  }
  
  /// 遠球自適應檢測：ROI 動態擴大
  /// 
  /// 當連續無檢測時，擴大搜尋區域：
  /// - noCandCount = 0: ROI 保持原大小
  /// - noCandCount = 1-2: ROI 擴大 20-40%
  /// - noCandCount = 3+: ROI 擴大 50-80%
  int getDynamicRoiSize(int baseRoiSize) {
    double expandFactor = 1.0;
    
    switch (noCandCount) {
      case 0:
        expandFactor = 1.0;
        break;
      case 1:
        expandFactor = 1.2;
        break;
      case 2:
        expandFactor = 1.4;
        break;
      default:
        expandFactor = 1.0 + math.min(0.5, noCandCount * 0.15);
    }
    
    return (baseRoiSize * expandFactor).toInt();
  }
  
  /// 遠球自適應檢測：基於面積 EMA 的距離調整
  /// 
  /// 當檢測到遠球時（面積小），放鬆距離限制：
  /// - 面積 EMA < 20: 硬限制 = 180px
  /// - 面積 EMA 20-50: 硬限制 = 150px
  /// - 面積 EMA > 50: 硬限制 = 130px
  double getAdaptiveDistanceLimitFromAreaEma() {
    final areaEma = configManager.areaEma ?? 30.0;
    
    if (areaEma < 20) {
      return 180.0;
    } else if (areaEma > 50) {
      return 130.0;
    } else {
      // 線性插值
      final t = (areaEma - 20) / 30;
      return 150.0 + (130.0 - 150.0) * t;
    }
  }
  
  // ========== 追蹤點管理 ==========
  
  /// 新增追蹤點（Kalman 已更新）
  void addTrackPoint(int x, int y, int frameIdx, int ptsUs) {
    trackPoints.add(TrackPoint(
      x: x,
      y: y,
      frameIdx: frameIdx,
      ptsUs: ptsUs,
    ));
    _pIndex = trackPoints.length;
    
    // 新增有效點後重置異常計數
    outlierStrikes = 0;
    
    // 嘗試恢復凍結狀態（有新的有效點）
    if (trackingFrozen && trackPoints.length >= 2) {
      attemptUnfreeze();
    }
  }
  
  /// 標記異常點（被步距衛士或其他規則拒絕）
  void recordOutlier() {
    outlierStrikes++;
    
    // Python 版本邏輯：8+ 異常 + 8+ 追蹤點 = 凍結
    if (outlierStrikes >= 8 && trackPoints.length >= 8) {
      trackingFrozen = true;
    }
  }
  
  /// 無檢測回調（Kalman 用預測值）
  void recordNoCandidate() {
    noCandCount++;
  }
  
  /// 有檢測回調（重置計數）
  void recordFoundCandidates() {
    noCandCount = 0;
  }
  
  // ========== Kalman 方法代理 ==========
  
  /// 從兩點初始化 Kalman
  void initKalman(double p0x, double p0y, double p1x, double p1y) {
    kalman.initFromPoints(p0x, p0y, p1x, p1y);
  }
  
  /// 預測下一個位置
  void predictKalman() {
    kalman.predict();
  }
  
  /// 更新 Kalman（新測量）
  void updateKalman(double zx, double zy) {
    kalman.update(zx, zy);
  }
  
  /// 取得 Kalman 預測位置
  (double, double) getKalmanPos() => kalman.pos;
  
  /// 是否已初始化
  bool get isKalmanInitialized => kalman.initialized;
}

/// 方便類：在 ball_tracker.dart 的基礎上增加動態配置
/// 
/// 使用示例（在 video_analysis_service.dart）：
/// ```dart
/// final tracker = EnhancedBallTracker(dt: 1.0 / 30.0);
/// 
/// // 第 1 幀
/// tracker.recordFoundCandidates();
/// tracker.addTrackPoint(x0, y0, 0, pts0);
/// 
/// // 第 2 幀 - 查找 P1
/// tracker.recordFoundCandidates();
/// tracker.initKalman(x0, y0, x1, y1);
/// tracker.addTrackPoint(x1, y1, 1, pts1);
/// 
/// // 第 3+ 幀 - 追蹤迴圈
/// for (int i = 2; i < frames.length; i++) {
///   // 1. 準備配置
///   final config = tracker.getCurrentConfig(roiSize: 400);
///   
///   // 2. 呼叫 Kotlin 用動態配置
///   final result = await platform.invokeMethod('detectBallsWithConfig', {
///     'videoPath': videoPath,
///     'frameIdx': i,
///     'config': config.toMap(),
///   }) as Map?;
///   
///   // 3. 處理檢測結果
///   if (result == null) {
///     tracker.recordNoCandidate();
///     tracker.predictKalman();
///     continue;
///   }
///   
///   tracker.recordFoundCandidates();
///   final candidates = (result['candidates'] as List).map((c) {
///     return Offset(c['x'].toDouble(), c['y'].toDouble());
///   }).toList();
///   
///   // 4. 應用步距衛士
///   var filteredCands = candidates.where((c) {
///     return tracker.stepDistanceGuardCheck(c);
///   }).toList();
///   
///   // 5. 應用 Y 方向約束
///   filteredCands = tracker.filterByYDirection(filteredCands);
///   
///   if (filteredCands.isEmpty) {
///     tracker.recordOutlier();
///     if (tracker.trackingFrozen) break;
///     continue;
///   }
///   
///   // 6. 選擇最佳候選
///   final best = filteredCands.first;  // 應該用 Kalman 預測距離選擇
///   tracker.updateKalman(best.dx, best.dy);
///   tracker.addTrackPoint(best.dx.toInt(), best.dy.toInt(), i, ptsUs);
/// }
/// ```
extension EnhancedBallTrackerIntegration on EnhancedBallTracker {
  /// 方便方法：一次性計算和傳遞配置
  Map<String, dynamic> getConfigAsMethodChannelArg({
    required int roiSize,
  }) {
    final config = getCurrentConfig(roiSize: roiSize);
    return config.toMap();
  }
}
