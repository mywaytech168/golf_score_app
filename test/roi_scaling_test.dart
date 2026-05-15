// ROI 分辨率縮放測試
// 檢查 Dart 層和 Kotlin 層的 ROI 計算是否正確同步
// 
// 運行: flutter test test/roi_scaling_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'dart:math' as math;
import 'package:golf_score_app/services/enhanced_ball_tracker.dart';

void main() {
  group('ROI 分辨率縮放測試', () {
    late EnhancedBallTracker tracker;
    
    setUp(() {
      tracker = EnhancedBallTracker(dt: 1.0 / 30.0);
    });
    
    // ===== 基準測試：1080×1920 =====
    group('基準分辨率 (1080×1920)', () {
      test('ROI 縮放因子應為 1.0', () {
        final scale = EnhancedBallTracker.getResolutionScaleFactor(1080, 1920);
        expect(scale, closeTo(1.0, 0.001));
      });
      
      test('calculateRoiBounds() 應返回 400×400 ROI', () {
        final (left, top, right, bottom) = tracker.calculateRoiBounds(
          videoW: 1080,
          videoH: 1920,
          roiSize: 0,  // 0 表示自動計算
        );
        
        final width = (right - left).toInt();
        final height = (bottom - top).toInt();
        
        expect(width, 400);
        expect(height, 400);
      });
      
      test('ROI 中心應在 (704.5, 1083.8) 附近', () {
        final (left, top, right, bottom) = tracker.calculateRoiBounds(
          videoW: 1080,
          videoH: 1920,
          roiSize: 0,
        );
        
        final centerX = (left + right) / 2;
        final centerY = (top + bottom) / 2;
        
        // 中心應該在 (0.6519 * 1080, 0.5646 * 1920) = (704.5, 1083.8)
        expect(centerX, closeTo(704.5, 0.5));
        expect(centerY, closeTo(1083.8, 0.5));
      });
      
      test('無檢測計數 0 時 getDynamicRoiSize() 應返回 400', () {
        tracker.noCandCount = 0;
        final size = tracker.getDynamicRoiSize(400, videoW: 1080, videoH: 1920);
        expect(size, 400);
      });
      
      test('無檢測計數 1 時 getDynamicRoiSize() 應返回 480', () {
        tracker.noCandCount = 1;
        final size = tracker.getDynamicRoiSize(400, videoW: 1080, videoH: 1920);
        expect(size, 480);  // 400 * 1.2
      });
      
      test('無檢測計數 2 時 getDynamicRoiSize() 應返回 560', () {
        tracker.noCandCount = 2;
        final size = tracker.getDynamicRoiSize(400, videoW: 1080, videoH: 1920);
        expect(size, 560);  // 400 * 1.4
      });
    });
    
    // ===== 測試分辨率：720×1080 =====
    group('低分辨率 (720×1080) - 縮放因子應為 0.563', () {
      test('ROI 縮放因子計算正確', () {
        final scale = EnhancedBallTracker.getResolutionScaleFactor(720, 1080);
        // min(720/1080, 1080/1920) = min(0.667, 0.563) = 0.563
        expect(scale, closeTo(0.563, 0.001));
      });
      
      test('calculateRoiBounds() 應返回 ~225×225 ROI', () {
        final (left, top, right, bottom) = tracker.calculateRoiBounds(
          videoW: 720,
          videoH: 1080,
          roiSize: 0,
        );
        
        final width = (right - left).toInt();
        final height = (bottom - top).toInt();
        
        // 400 * 0.563 ≈ 225
        expect(width, greaterThanOrEqualTo(223));
        expect(width, lessThanOrEqualTo(227));
        expect(height, greaterThanOrEqualTo(223));
        expect(height, lessThanOrEqualTo(227));
      });
      
      test('ROI 中心位置應按比例調整', () {
        final (left, top, right, bottom) = tracker.calculateRoiBounds(
          videoW: 720,
          videoH: 1080,
          roiSize: 0,
        );
        
        final centerX = (left + right) / 2;
        final centerY = (top + bottom) / 2;
        
        // 中心應該在 (0.6519 * 720, 0.5646 * 1080) = (469.4, 610.2)
        expect(centerX, closeTo(469.4, 0.5));
        expect(centerY, closeTo(610.2, 0.5));
      });
      
      test('getDynamicRoiSize() 應返回分辨率縮放後的尺寸', () {
        tracker.noCandCount = 0;
        
        // 基準 ROI 在 720×1080: 400 * 0.563 ≈ 225
        final size = tracker.getDynamicRoiSize(400, videoW: 720, videoH: 1080);
        
        expect(size, greaterThanOrEqualTo(223));
        expect(size, lessThanOrEqualTo(227));
      });
      
      test('動態擴大應基於分辨率縮放後的尺寸', () {
        tracker.noCandCount = 1;
        
        // 基準: 400 * 0.563 ≈ 225
        // 擴大 1.2×: 225 * 1.2 = 270
        final size = tracker.getDynamicRoiSize(400, videoW: 720, videoH: 1080);
        
        expect(size, greaterThanOrEqualTo(268));
        expect(size, lessThanOrEqualTo(272));
      });
    });
    
    // ===== 測試分辨率：1440×2560（2K）=====
    group('高分辨率 (1440×2560) - 縮放因子應為 1.333', () {
      test('ROI 縮放因子計算正確', () {
        final scale = EnhancedBallTracker.getResolutionScaleFactor(1440, 2560);
        // min(1440/1080, 2560/1920) = min(1.333, 1.333) = 1.333
        expect(scale, closeTo(1.333, 0.001));
      });
      
      test('calculateRoiBounds() 應返回 ~533×533 ROI', () {
        final (left, top, right, bottom) = tracker.calculateRoiBounds(
          videoW: 1440,
          videoH: 2560,
          roiSize: 0,
        );
        
        final width = (right - left).toInt();
        
        // 400 * 1.333 ≈ 533
        expect(width, greaterThanOrEqualTo(531));
        expect(width, lessThanOrEqualTo(535));
      });
    });
    
    // ===== 測試顯式 roiSize 參數 =====
    group('顯式 roiSize 參數應優先使用', () {
      test('roiSize > 0 時應直接使用，不進行分辨率縮放', () {
        final (left, top, right, bottom) = tracker.calculateRoiBounds(
          videoW: 720,
          videoH: 1080,
          roiSize: 300,  // 顯式指定
        );
        
        final width = (right - left).toInt();
        expect(width, 300);  // 應該正好是 300
      });
    });
    
    // ===== ROI 邊界夾緊測試 =====
    group('ROI 邊界夾緊（不超出視頻範圍）', () {
      test('ROI 不應超出視頻左邊界', () {
        final (left, _, _, _) = tracker.calculateRoiBounds(
          videoW: 1080,
          videoH: 1920,
          roiSize: 0,
        );
        
        expect(left, greaterThanOrEqualTo(0.0));
      });
      
      test('ROI 不應超出視頻右邊界', () {
        final (_, _, right, _) = tracker.calculateRoiBounds(
          videoW: 1080,
          videoH: 1920,
          roiSize: 0,
        );
        
        expect(right, lessThanOrEqualTo(1079.0));
      });
      
      test('極端情況：小視頻（480×640）ROI 應被完全包含', () {
        final (left, top, right, bottom) = tracker.calculateRoiBounds(
          videoW: 480,
          videoH: 640,
          roiSize: 0,
        );
        
        expect(left, greaterThanOrEqualTo(0.0));
        expect(top, greaterThanOrEqualTo(0.0));
        expect(right, lessThanOrEqualTo(479.0));
        expect(bottom, lessThanOrEqualTo(639.0));
      });
    });
    
    // ===== 與 Kotlin 層同步檢查 =====
    group('Dart-Kotlin 層同步檢查', () {
      test('使用 getDynamicRoiSize() 的結果計算 calculateRoiBounds()', () {
        // 模擬 Kotlin 層調用過程
        final baseRoiSize = 400;
        
        // Step 1: Dart 計算動態 ROI
        tracker.noCandCount = 1;
        final dynamicRoiSize = tracker.getDynamicRoiSize(
          baseRoiSize,
          videoW: 1080,
          videoH: 1920,
        );
        
        // Step 2: 使用動態 ROI 計算邊界
        final (left, top, right, bottom) = tracker.calculateRoiBounds(
          videoW: 1080,
          videoH: 1920,
          roiSize: dynamicRoiSize,  // 傳入 Dart 計算的值
        );
        
        final width = (right - left).toInt();
        
        // 預期：400 * 1.2 = 480
        expect(dynamicRoiSize, 480);
        expect(width, 480);
      });
      
      test('不同分辨率下的動態 ROI 應保持一致性', () {
        // 1080×1920 視頻：noCandCount=1 → 480px
        tracker.noCandCount = 1;
        final size1 = tracker.getDynamicRoiSize(400, videoW: 1080, videoH: 1920);
        
        // 2160×3840 視頻（2 倍解析度）：noCandCount=1 → 960px (480*2)
        tracker.noCandCount = 1;
        final size2 = tracker.getDynamicRoiSize(400, videoW: 2160, videoH: 3840);
        
        // 驗證比例
        expect(size2, closeTo(size1 * 2, 2.0));
      });
    });
  });
}
