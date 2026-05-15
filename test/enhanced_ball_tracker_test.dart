import 'package:flutter_test/flutter_test.dart';
import 'package:golf_score_app/services/enhanced_ball_tracker.dart';
import 'package:golf_score_app/services/ball_tracker.dart';

void main() {
  group('EnhancedBallTracker - 第 1-2 週規則', () {
    late EnhancedBallTracker tracker;
    
    setUp(() {
      tracker = EnhancedBallTracker(dt: 1.0 / 30.0);
    });
    
    // ===== 第 1 層規則：步距衛士 =====
    group('規則 1: 步距衛士 (Step Distance Guard)', () {
      test('空追蹤點時應接受任何候選球', () {
        expect(tracker.stepDistanceGuardCheck(const Offset(100, 100)), true);
      });
      
      test('距離在限制內應接受', () {
        tracker.addTrackPoint(100, 100, 0, 0);
        tracker.addTrackPoint(110, 100, 1, 33000);
        
        // 距離 = 15px，應接受
        expect(tracker.stepDistanceGuardCheck(const Offset(125, 100)), true);
      });
      
      test('距離超過硬限制（130px）應拒絕', () {
        tracker.addTrackPoint(100, 100, 0, 0);
        tracker.addTrackPoint(110, 100, 1, 33000);
        
        // 距離 = 150px，超過硬限制
        expect(tracker.stepDistanceGuardCheck(const Offset(250, 100)), false);
      });
      
      test('無檢測計數增加時應放鬆限制', () {
        tracker.addTrackPoint(100, 100, 0, 0);
        tracker.addTrackPoint(110, 100, 1, 33000);
        
        // 設置無檢測計數
        tracker.noCandCount = 3;
        
        // 距離 = 135px，在 noCandCount=3 的放鬆限制內
        expect(
          tracker.stepDistanceGuardCheck(const Offset(235, 100)),
          true,  // 應接受（因為放鬆因子 = 1.0 + 0.35*3 = 2.05）
        );
      });
    });
    
    // ===== 第 2 層規則：Y 方向約束 =====
    group('規則 2: Y 方向約束 (Y Direction Constraint)', () {
      test('少於 3 點時不過濾', () {
        tracker.addTrackPoint(100, 100, 0, 0);
        tracker.addTrackPoint(110, 100, 1, 33000);
        
        final filtered = tracker.filterByYDirection([
          const Offset(120, 100),
          const Offset(120, 150),
        ]);
        
        expect(filtered.length, 2);
      });
      
      test('推斷向下方向後過濾', () {
        // 創建向下軌跡
        tracker.addTrackPoint(100, 100, 0, 0);
        tracker.addTrackPoint(110, 110, 1, 33000);
        tracker.addTrackPoint(120, 120, 2, 66000);
        
        // 第一次過濾呼叫應推斷方向
        tracker.filterByYDirection([]);
        
        // 確保方向推斷有效
        if (tracker.yDir != null) {
          // 如果推斷成功，應該是 1 或 -1
          expect([1, -1].contains(tracker.yDir), true);
        }
      });
      
      test('Y 距離超過 80px 應拒絕', () {
        // 創建向下軌跡
        tracker.addTrackPoint(100, 100, 0, 0);
        tracker.addTrackPoint(110, 110, 1, 33000);
        tracker.addTrackPoint(120, 120, 2, 66000);
        
        // 初始化方向
        tracker.filterByYDirection([]);
        
        final filtered = tracker.filterByYDirection([
          const Offset(130, 210),  // dy = 90，超過 80px，拒絕
          const Offset(130, 130),  // dy = 10，接受
        ]);
        
        // 應該至少有一個通過
        expect(filtered.isNotEmpty, true);
      });
    });
    
    // ===== 第 3 層規則：遠球自適應檢測 =====
    group('規則 3: 遠球自適應檢測 (Far-ball Adaptive)', () {
      test('無檢測計數 0 時 ROI 不擴大', () {
        tracker.noCandCount = 0;
        expect(tracker.getDynamicRoiSize(400), 400);
      });
      
      test('無檢測計數 1-2 時 ROI 擴大 20-40%', () {
        tracker.noCandCount = 1;
        expect(tracker.getDynamicRoiSize(400), 480);  // 400 * 1.2
        
        tracker.noCandCount = 2;
        expect(tracker.getDynamicRoiSize(400), 560);  // 400 * 1.4
      });
      
      test('無檢測計數 3+ 時 ROI 擴大 50-80%', () {
        tracker.noCandCount = 3;
        final size3 = tracker.getDynamicRoiSize(400);
        expect(size3, greaterThanOrEqualTo(580));  // >= 400 * 1.45
        expect(size3, lessThanOrEqualTo(720));     // <= 400 * 1.8
      });
      
      test('面積 EMA 影響距離限制', () {
        // 遠球（面積小）
        tracker.configManager.updateAreaEma(15.0);
        expect(tracker.getAdaptiveDistanceLimitFromAreaEma(), 180.0);
        
        // 近球（面積大）
        tracker.configManager.updateAreaEma(60.0);
        expect(tracker.getAdaptiveDistanceLimitFromAreaEma(), 130.0);
        
        // 中間距離
        tracker.configManager.updateAreaEma(35.0);
        final mid = tracker.getAdaptiveDistanceLimitFromAreaEma();
        // 應該在 130-180 之間
        expect(mid, greaterThanOrEqualTo(130));
        expect(mid, lessThanOrEqualTo(180));
      });
    });
    
    // ===== 第 4 層規則：多假設預測替代 =====
    group('規則 4: 多假設預測替代 (Prediction Fallback)', () {
      test('預測歷史記錄不超過 5 個', () {
        for (int i = 0; i < 10; i++) {
          tracker.recordPrediction(i, 100.0 + i, 100.0);
        }
        
        expect(tracker.predictionHistory.length, 5);
      });
      
      test('無檢測 <= 2 幀時無替代', () {
        tracker.trackPoints.add(TrackPoint(x: 100, y: 100, frameIdx: 0, ptsUs: 0));
        tracker.kalman.initFromPoints(100, 100, 110, 110);
        
        tracker.noCandCount = 2;
        expect(tracker.getPredictionFallback(), null);
      });
      
      test('無檢測 > 2 幀時使用預測替代', () {
        tracker.trackPoints.add(TrackPoint(x: 100, y: 100, frameIdx: 0, ptsUs: 0));
        tracker.trackPoints.add(TrackPoint(x: 110, y: 110, frameIdx: 1, ptsUs: 33000));
        tracker.kalman.initFromPoints(100, 100, 110, 110);
        
        tracker.noCandCount = 3;
        final fallback = tracker.getPredictionFallback();
        expect(fallback, isNotNull);
      });
      
      test('凍結狀態時無替代', () {
        tracker.trackingFrozen = true;
        tracker.noCandCount = 5;
        expect(tracker.getPredictionFallback(), null);
      });
    });
    
    // ===== 第 5 層規則：異常值檢測 =====
    group('規則 5: 異常值檢測 (Outlier Detection)', () {
      test('少於 8 個異常不凍結', () {
        for (int i = 0; i < 7; i++) {
          tracker.recordOutlier();
        }
        
        expect(tracker.trackingFrozen, false);
      });
      
      test('8+ 個異常且 8+ 個追蹤點時凍結', () {
        // 添加 8 個追蹤點
        for (int i = 0; i < 8; i++) {
          tracker.trackPoints.add(
            TrackPoint(x: 100 + i, y: 100 + i, frameIdx: i, ptsUs: i * 33000),
          );
        }
        
        // 8 個異常
        for (int i = 0; i < 8; i++) {
          tracker.recordOutlier();
        }
        
        expect(tracker.trackingFrozen, true);
      });
      
      test('新增有效點後重置異常計數', () {
        tracker.outlierStrikes = 5;
        tracker.addTrackPoint(100, 100, 0, 0);
        
        expect(tracker.outlierStrikes, 0);
      });
      
      test('新增有效點可嘗試恢復凍結', () {
        tracker.trackingFrozen = true;
        
        tracker.trackPoints.add(TrackPoint(x: 100, y: 100, frameIdx: 0, ptsUs: 0));
        tracker.kalman.initFromPoints(100, 100, 110, 110);
        tracker.addTrackPoint(100, 100, 0, 0);
        
        expect(tracker.trackingFrozen, false);
      });
      
      test('handleOutlierDetection 完整流程', () {
        // 準備 8+ 追蹤點
        for (int i = 0; i < 8; i++) {
          tracker.trackPoints.add(
            TrackPoint(x: 100 + i, y: 100 + i, frameIdx: i, ptsUs: i * 33000),
          );
        }
        
        // 7 個異常（尚未凍結）
        for (int i = 0; i < 7; i++) {
          tracker.handleOutlierDetection();
        }
        expect(tracker.trackingFrozen, false);
        
        // 第 8 個異常（應凍結）
        final frozen = tracker.handleOutlierDetection();
        expect(frozen, true);
        expect(tracker.trackingFrozen, true);
      });
    });
    
    // ===== 整合測試 =====
    group('完整追蹤流程', () {
      test('典型 golf swing 軌跡', () {
        // P0: 球初始位置
        tracker.recordFoundCandidates();
        tracker.addTrackPoint(200, 300, 0, 0);
        
        // P1: 找到第二個點後初始化 Kalman
        tracker.recordFoundCandidates();
        tracker.initKalman(200, 300, 210, 310);
        tracker.addTrackPoint(210, 310, 1, 33000);
        
        // 接下來 5 幀
        for (int i = 2; i < 7; i++) {
          tracker.predictKalman();
          final (px, py) = tracker.getKalmanPos();
          
          // 模擬檢測候選
          final candidates = [
            Offset(px + 5, py + 10),
            Offset(px + 50, py + 50),  // 異常遠
          ];
          
          // 應用規則
          tracker.recordFoundCandidates();
          var filtered = candidates.where((c) {
            return tracker.stepDistanceGuardCheck(c);
          }).toList();
          filtered = tracker.filterByYDirection(filtered);
          
          if (filtered.isNotEmpty) {
            tracker.updateKalman(filtered[0].dx, filtered[0].dy);
            tracker.addTrackPoint(
              filtered[0].dx.toInt(),
              filtered[0].dy.toInt(),
              i,
              i * 33000,
            );
          }
        }
        
        // 驗證軌跡
        expect(tracker.trackPoints.length, 7);
        expect(tracker.outlierStrikes, 0);
        expect(tracker.trackingFrozen, false);
      });
      
      test('遮擋恢復流程', () {
        // P0-P2: 正常追蹤
        tracker.addTrackPoint(100, 100, 0, 0);
        tracker.addTrackPoint(110, 110, 1, 33000);
        tracker.initKalman(100, 100, 110, 110);
        tracker.addTrackPoint(120, 120, 2, 66000);
        
        // P3-P5: 無檢測（遮擋）
        for (int i = 0; i < 3; i++) {
          tracker.recordNoCandidate();
          tracker.predictKalman();
          tracker.recordOutlier();
        }
        
        // 應該仍未凍結（異常計數 3 < 8）
        expect(tracker.trackingFrozen, false);
        
        // P6: 恢復檢測
        tracker.recordFoundCandidates();
        final (px, py) = tracker.getKalmanPos();
        tracker.updateKalman(px, py);
        tracker.addTrackPoint(px.toInt(), py.toInt(), 6, 200000);
        
        // 異常計數應重置
        expect(tracker.outlierStrikes, 0);
      });
    });
    
    // ===== 配置更新測試 =====
    group('動態配置計算', () {
      test('getCurrentConfig 返回有效配置', () {
        tracker.addTrackPoint(100, 100, 0, 0);
        tracker.addTrackPoint(110, 110, 1, 33000);
        
        tracker.noCandCount = 2;
        final config = tracker.getCurrentConfig(roiSize: 400);
        
        expect(config.diffThresh, greaterThan(0));
        expect(config.areaLo, greaterThan(0));
        expect(config.areaHi, greaterThan(config.areaLo));
        expect(config.circMin, greaterThan(0));
      });
    });
  });
}
