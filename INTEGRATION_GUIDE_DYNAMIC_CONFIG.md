// ============================================================
// 集成指南: 動態檢測配置使用
// ============================================================
//
// 文件位置: INTEGRATION_GUIDE_DYNAMIC_CONFIG.md
//
// ============================================================

# 動態檢測配置 - 集成實施指南

## 📍 概述

本指南說明如何在現有的 golf_score_app 中整合動態檢測配置系統，使 Kotlin 層的 ball 檢測能根據追蹤狀態（距離、遮擋、速度等）動態調整門檻。

## 🏗️ 架構流程

```
Dart 層 (ball_tracker.dart)
  ↓
  計算: no_cand_count, area_ema, step_ema, pIndex, roiSize
  ↓
Dart 層 (enhanced_ball_tracker.dart + detection_config.dart)
  ↓
  生成 DetectionConfig {diffThresh, areaLo, areaHi, circMin}
  ↓
MethodChannel 傳送配置 Map
  ↓
Kotlin 層 (BallBlobExtractor.kt)
  ↓
  接收 DetectionConfig.fromMap(configMap)
  ↓
  在 detectBlobs() 中使用動態參數
  ↓
  回傳 blob 列表
```

## 🔧 實施步驟

### 第 1 步: Kotlin 層修改 (已完成)

**檔案**: `android/app/src/main/kotlin/com/example/golf_score_app/BallBlobExtractor.kt`

修改內容:
1. ✅ 新增 `DetectionConfig` data class
2. ✅ 修改 `extract()` 接受 `config: Map<String, Any?>?` 參數
3. ✅ 修改 `detectBlobs()` 簽名添加 `config: DetectionConfig` 參數
4. ✅ 在 detectBlobs 內用 `config.diffThresh`, `config.areaLo` 等替代常數

### 第 2 步: Dart 層新增檔案 (已完成)

**新檔案 1**: `lib/services/detection_config.dart`
- `DetectionConfig` 類別（參數容器）
- `DetectionConfigCalculator` 類別（計算邏輯）
- `TrackingConfigManager` 類別（狀態管理）

**新檔案 2**: `lib/services/enhanced_ball_tracker.dart`
- `EnhancedBallTracker` 類別（整合 Kalman + 動態配置）
- 示例使用方式

### 第 3 步: 修改 MethodChannel 調用

在 `lib/services/video_analysis_service.dart` 或適當的調用位置:

```dart
// 原來的呼叫（無配置）
final result = await _channel.invokeMethod('extractBlobs', {
  'videoPath': videoPath,
});

// 新的呼叫（帶動態配置）
final config = tracker.getCurrentConfig(roiSize: 400);
final result = await _channel.invokeMethod('extractBlobsWithConfig', {
  'videoPath': videoPath,
  'config': config.toMap(),  // ← 新增這行
});
```

### 第 4 步: 更新 MainActivity.kt MethodChannel

在 `android/app/src/main/kotlin/.../MainActivity.kt`:

```kotlin
MethodChannel(flutterEngine.dartExecutor.binaryMessenger, 
    "com.example.golf_score_app/ballDetection")
    .setMethodCallHandler { call, result ->
        when (call.method) {
            "extractBlobsWithConfig" -> {
                val videoPath = call.argument<String>("videoPath")
                val configMap = call.argument<Map<String, Any?>>("config")
                
                val extractor = BallBlobExtractor()
                val blobs = extractor.extract(videoPath, configMap)
                
                result.success(blobs)
            }
            else -> result.notImplemented()
        }
    }
```

## 📊 使用示例

### 最小示例

```dart
import 'package:golf_score_app/services/enhanced_ball_tracker.dart';
import 'package:golf_score_app/services/detection_config.dart';

// 初始化
final tracker = EnhancedBallTracker(dt: 1.0 / 30.0);

// 在追蹤迴圈中
for (int frameIdx = 0; frameIdx < totalFrames; frameIdx++) {
  // 1. 計算當前配置
  final config = tracker.getCurrentConfig(roiSize: 400);
  
  // 2. 呼叫 Kotlin（帶配置）
  final result = await platform.invokeMethod(
    'extractBlobsWithConfig',
    {
      'videoPath': videoPath,
      'config': config.toMap(),
    },
  ) as Map?;
  
  if (result == null) {
    tracker.recordNoCandidate();
    tracker.predictKalman();
    continue;
  }
  
  // 3. 處理候選球
  final candidates = result['blobs'] as List;
  
  // 4. 應用步距衛士
  final filtered = candidates.where((c) {
    return tracker.stepDistanceGuardCheck(
      Offset(c['x'].toDouble(), c['y'].toDouble()),
    );
  }).toList();
  
  if (filtered.isNotEmpty) {
    final best = filtered.first;
    tracker.updateKalman(best['x'].toDouble(), best['y'].toDouble());
  }
}
```

### 完整示例（包含所有 5 層規則）

```dart
// 假設這在 video_analysis_service.dart

class BallTrackingPipeline {
  final platform = const MethodChannel('com.example.golf_score_app/ballDetection');
  late EnhancedBallTracker tracker;
  
  Future<void> trackBallInVideo(String videoPath) async {
    tracker = EnhancedBallTracker(dt: 1.0 / 30.0);
    
    // 第 0 幀: 搜尋 P0
    final frames = await _decodeAllFrames(videoPath);
    
    for (int idx = 0; idx < frames.length; idx++) {
      final config = tracker.getCurrentConfig(roiSize: 400);
      
      final result = await platform.invokeMethod('extractBlobsWithConfig', {
        'videoPath': videoPath,
        'frameIdx': idx,
        'config': config.toMap(),
      }) as Map?;
      
      if (result == null) {
        tracker.recordNoCandidate();
        if (idx > 0) tracker.predictKalman();
        continue;
      }
      
      tracker.recordFoundCandidates();
      final blobs = result['blobs'] as List;
      
      if (tracker.pIndex == 0) {
        // 搜尋 P0
        if (blobs.isNotEmpty) {
          final p0 = blobs.first;
          tracker.addTrackPoint(
            p0['x'] as int, p0['y'] as int, idx, 0,
          );
        }
      } else if (tracker.pIndex == 1) {
        // 搜尋 P1（下一幀）
        if (blobs.isNotEmpty) {
          final p1 = blobs.first;
          final p0 = tracker.trackPoints[0];
          
          // 初始化 Kalman
          tracker.initKalman(
            p0.x.toDouble(), p0.y.toDouble(),
            p1['x'].toDouble(), p1['y'].toDouble(),
          );
          
          tracker.addTrackPoint(
            p1['x'] as int, p1['y'] as int, idx, 0,
          );
        }
      } else {
        // 追蹤中（第 2+ 幀）
        tracker.predictKalman();
        
        // 應用所有篩選規則
        var candidates = blobs.map((b) {
          return Offset(b['x'].toDouble(), b['y'].toDouble());
        }).toList();
        
        // 規則 1: 步距衛士
        candidates = candidates.where((c) {
          if (!tracker.stepDistanceGuardCheck(c)) {
            tracker.recordOutlier();
            return false;
          }
          return true;
        }).toList();
        
        if (candidates.isEmpty) {
          if (tracker.trackingFrozen) break;  // 規則 5: 異常值凍結
          continue;
        }
        
        // 規則 2: Y 方向約束
        candidates = tracker.filterByYDirection(candidates);
        
        if (candidates.isEmpty) {
          tracker.recordOutlier();
          if (tracker.trackingFrozen) break;
          continue;
        }
        
        // 選擇最佳候選
        final best = candidates.first;  // 應使用 Kalman 預測距離篩選
        
        // 規則 3: 遠球自適應（已在 getCurrentConfig 內實施）
        tracker.updateAreaEmaFromBlob(blobs[0]['area'] as int);
        
        // 更新 Kalman
        tracker.updateKalman(best.dx, best.dy);
        tracker.addTrackPoint(
          best.dx.toInt(), best.dy.toInt(), idx, 0,
        );
      }
    }
  }
}
```

## ✅ 驗證檢查清單

- [ ] Kotlin 代碼編譯無誤
- [ ] 新增 Dart 檔案無 import 錯誤
- [ ] 測試 `detection_config_test.dart` 全部通過
- [ ] MethodChannel 通信正常
- [ ] 默認配置（無動態調整）行為與原來相同
- [ ] 啟用動態配置後，輸出 blob 數量和質量有改善

## 🐛 故障排除

### 問題 1: Kotlin 編譯失敗

**症狀**: `DetectionConfig` 找不到或類型錯誤

**解決**:
1. 確保 `BallBlobExtractor.kt` 已正確修改
2. Rebuild: `flutter clean && flutter pub get && flutter run`

### 問題 2: MethodChannel 傳遞配置失敗

**症狀**: `NoSuchMethodError` 或 `type mismatch in java.lang.Map`

**解決**:
1. 確認 Dart 側 `config.toMap()` 正確
2. 檢查 Kotlin 側 `DetectionConfig.fromMap()` 邏輯
3. 打印日誌: 
   ```kotlin
   Log.d(TAG, "Received config: $configMap")
   ```

### 問題 3: 配置未生效（blob 結果不變）

**症狀**: 修改動態配置但檢測結果相同

**解決**:
1. 確認 `detectBlobs()` 內實際使用 `config.diffThresh` 等
2. 檢查 `extract()` 是否正確傳給 `detectBlobs()`
3. 添加日誌:
   ```kotlin
   Log.d(TAG, "Using diff=${config.diffThresh}, area=[${config.areaLo}..${config.areaHi}]")
   ```

## 📈 效能預期

- **Dart 層計算**：< 0.5ms per frame
- **MethodChannel 通信**：< 1ms per frame
- **Kotlin 層執行**：無額外開銷（只改常數名稱）

**總計**：每幀增加 ~1.5ms（在 30fps = 33ms/frame 的可接受範圍內）

## 🔄 後續步驟 (第 1-3 週)

### 第 1 週
1. ✅ 實施本文檔（動態參數傳遞）
2. ✅ 新增步距衛士（已在 enhanced_ball_tracker.dart）
3. ✅ 新增 Y 方向約束（已在 enhanced_ball_tracker.dart）
4. 測試 A/B

### 第 2 週
5. 完善遠球自適應（已有框架）
6. 新增預測替代（blue_hist）
7. 新增異常值檢測（已有框架）

### 第 3 週
8. 性能優化
9. 灰度發佈

## 📚 參考資源

- [MIGRATION_REQUIREMENTS_ANALYSIS.md](MIGRATION_REQUIREMENTS_ANALYSIS.md) - 完整遷移計畫
- [PYTHON_TRAJECTORY_ALGORITHM_ANALYSIS.md](PYTHON_TRAJECTORY_ALGORITHM_ANALYSIS.md) - Python 算法詳解
- `lib/services/detection_config.dart` - 配置計算源碼
- `lib/services/enhanced_ball_tracker.dart` - 整合追蹤器源碼
- `test/detection_config_test.dart` - 測試用例

---

**最後更新**: 2026-05-15
**狀態**: 🟢 實施完成 (第 1 週核心)
