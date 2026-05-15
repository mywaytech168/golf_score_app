# 球軌跡優化 - 實施清單 & 快速參考

## 🚀 快速導航

### 📌 我需要...
- **立即改善軌跡平滑度** → 見「第一階段：Kalman 改進」
- **提高球檢測精度** → 見「第二階段：OpenCV 集成」
- **完整優化方案比較** → 見 [TRAJECTORY_OPTIMIZATION_ANALYSIS.md](TRAJECTORY_OPTIMIZATION_ANALYSIS.md)
- **性能指標基準** → 見「性能監控工具」

---

## ✅ 第一階段清單（1-2 週）

### 任務 1.1: 改進 Kalman 濾波器

#### 文件修改
- [ ] 建立 `lib/services/enhanced_ball_tracker.dart`
  ```dart
  class EnhancedBallTracker {
    // 實現適應性過程噪聲 + MHT 追蹤
  }
  ```

#### 修改現有檔案
- [ ] `lib/main.dart` 或 `lib/services/video_analysis_service.dart`
  - 替換 `BallTracker` 為 `EnhancedBallTracker`
  - 保留切換邏輯供 A/B 測試

#### 測試清單
- [ ] 單位測試: `test/enhanced_ball_tracker_test.dart`
- [ ] 對比測試: 同一視頻用舊/新追蹤器
  ```
  原 Kalman: 軌跡點數=45, 平滑度分數=0.72
  改進版:    軌跡點數=48, 平滑度分數=0.85 ✅
  ```

#### 預期成果
- ✅ 軌跡平滑度 ↑30-50%
- ✅ 追蹤失敗率 ↓50%
- ✅ 零額外延遲

---

### 任務 1.2: 強化 FPS 監控

#### 文件新建
- [ ] `lib/services/fps_diagnostics.dart`
  ```dart
  class FPSDiagnostics {
    void logFPS(String stage, double fps, double? metadata) {
      // 記錄每個階段的 FPS，便於追蹤問題
    }
  }
  ```

#### 日誌檢查清單
在 Logcat 中搜索關鍵詞並驗證:
- [ ] `[BallBlobExtractor] 🎬 fps 檢測: metadata=30 → 使用=30.0`
- [ ] `[TrajectoryOverlay] 🎬 fps 檢測: metadata=30 → 使用=30.0`
- [ ] 超過 10 分鐘視頻時 FPS 無漂移

#### 測試場景
- [ ] 短視頻 (<30 秒) → 應為 30fps
- [ ] 長視頻 (5-10 分鐘) → 應保持 30fps
- [ ] 裁切後短片 → 應為 30fps

---

## 📋 第二階段清單（2-4 週）

### 任務 2.1: C++ OpenCV 球檢測集成

#### 環境準備
- [ ] 安裝 NDK (版本: r21+)
  ```powershell
  # Windows 上
  flutter doctor -v  # 確認 NDK 路徑
  ```

- [ ] 在 `android/CMakeLists.txt` 中配置 OpenCV
  ```cmake
  find_package(OpenCV REQUIRED)
  target_link_libraries(ball_detector ${OpenCV_LIBS})
  ```

#### C++ 實現
- [ ] 建立 `android/app/src/main/cpp/ball_detector.cpp`
  ```cpp
  // 實現 detectBallWithAdaptiveThreshold()
  // - 適應性幀差
  // - Hough Circle Detection
  // - 圓度篩選
  ```

- [ ] JNI 包裹: `android/app/src/main/kotlin/com/example/golf_score_app/BallDetectorNative.kt`
  ```kotlin
  external fun detectBallsNative(
    yPlane: ByteArray, 
    prevY: ByteArray, 
    width: Int, 
    height: Int
  ): Array<BlobData>
  ```

#### Kotlin 修改
- [ ] 修改 `BallBlobExtractor.kt`
  ```kotlin
  // 在 detectBlobs() 中呼叫 native 方法
  val blobs = if (useNative) {
    detectBallsNative(yRaw, prevY, videoW, videoH)
  } else {
    detectBlobsKotlin(yRaw, prevY, videoW, videoH)  // 後備
  }
  ```

#### 測試清單
- [ ] 編譯測試: `./gradlew assembleDebug`
- [ ] 設備測試: 安裝 APK，執行球檢測
- [ ] 性能測試:
  ```
  原實現: ~5ms/幀
  C++ 版: ~15-20ms/幀 (可接受)
  ```

#### 預期成果
- ✅ 檢測率: 60-70% → 85-90%
- ✅ 誤檢率: 15-20% → 5-8%
- ✅ APK 大小: +500KB

---

### 任務 2.2: 性能基準建立

#### 建立性能監控工具
- [ ] `lib/services/performance_monitor.dart`
  ```dart
  class TrajectoryPerformanceMonitor {
    void recordDetection(Duration time);
    void recordTracking(Duration time);
    void recordRender(Duration time);
    Map<String, double> getReport();
  }
  ```

#### 基準測試
- [ ] 建立 10 個代表性視頻集 (不同光照、背景、球速)
- [ ] 執行各方案，記錄指標:
  ```
  測試視頻: outdoor_fast_swing.mp4
  
  方案 B (Kalman+):
    - 檢測點: 48 (vs 45)
    - 平滑度: 0.85 (vs 0.72)
    - 延遲: 9ms (vs 10ms)
  
  方案 A (OpenCV):
    - 檢測點: 52
    - 平滑度: 0.88
    - 延遲: 22ms
  ```

---

## 🛠️ 第三階段清單（後續考慮）

### 任務 3.1: ML 球檢測集成（可選）

#### 前置條件
- [ ] 基礎檢測精度已達 85%+ (完成方案 A)
- [ ] 有 500+ 標註訓練資料

#### 實施步驟
- [ ] 訓練 YOLO-nano 模型或使用開源模型
- [ ] 轉換為 TFLite 格式
- [ ] 集成 `tflite_flutter` 包
- [ ] 測試推理延遲 (<30ms)

---

## 📊 測試與驗證框架

### 快速驗證清單

```dart
// 在 MainActivity.kt 或測試 app 中
void verifyOptimization() {
  // 1. 軌跡平滑度
  final smoothness = calculateSmoothnessScore(trackPoints);
  assert(smoothness > 0.80, 'Smoothness too low: $smoothness');
  
  // 2. 檢測率
  final detectionRate = totalDetectedFrames / totalFrames;
  assert(detectionRate > 0.85, 'Detection rate too low: $detectionRate');
  
  // 3. 誤檢率
  final falsePositiveRate = falsePositives / totalDetections;
  assert(falsePositiveRate < 0.05, 'False positive rate too high: $falsePositiveRate');
  
  // 4. 延遲
  final totalLatencyMs = detectionMs + trackingMs + renderMs;
  assert(totalLatencyMs < 20, 'Total latency too high: ${totalLatencyMs}ms');
}
```

### A/B 測試腳本

```dart
// lib/tools/ab_test_trajectory.dart
import 'package:test/test.dart';

void main() {
  group('Trajectory Optimization A/B Tests', () {
    
    test('Legacy vs Enhanced Kalman', () async {
      final videoPath = 'test_videos/sample_golf_swing.mp4';
      
      final legacyResult = await analyzeWithLegacy(videoPath);
      final enhancedResult = await analyzeWithEnhanced(videoPath);
      
      print('Legacy smoothness: ${legacyResult.smoothness}');
      print('Enhanced smoothness: ${enhancedResult.smoothness}');
      
      expect(enhancedResult.smoothness, greaterThan(legacyResult.smoothness * 1.25),
        reason: 'Enhanced should be 25%+ smoother');
      
      expect(enhancedResult.trackingFailures, lessThan(legacyResult.trackingFailures),
        reason: 'Enhanced should have fewer tracking failures');
    });
    
    test('Current vs OpenCV Ball Detection', () async {
      final videoPath = 'test_videos/sample_golf_swing.mp4';
      final groundTruth = loadGroundTruth(videoPath);
      
      final currentResult = await analyzeWithCurrent(videoPath);
      final opencvResult = await analyzeWithOpenCV(videoPath);
      
      final currentRecall = calculateRecall(currentResult, groundTruth);
      final opencvRecall = calculateRecall(opencvResult, groundTruth);
      
      print('Current detection recall: ${currentRecall * 100}%');
      print('OpenCV detection recall: ${opencvRecall * 100}%');
      
      expect(opencvRecall, greaterThan(currentRecall * 1.20),
        reason: 'OpenCV should be 20%+ more accurate');
    });
    
  });
}
```

---

## 📈 進度追蹤

### 里程碑 (Milestones)

| 里程碑 | 目標完成日期 | 狀態 | 關鍵指標 |
|--------|------------|------|---------|
| 第 1 週 - Kalman 改進 | Week 1 | ⏳ | 平滑度 ↑30% |
| 第 2 週 - FPS 監控完善 | Week 1-2 | ⏳ | 0 FPS 漂移 |
| 第 3 週 - NDK 環境建立 | Week 2 | ⏳ | 編譯成功 |
| 第 4 週 - OpenCV 集成 | Week 2-3 | ⏳ | 檢測率 ↑85% |
| 第 5 週 - 全系統測試 | Week 3-4 | ⏳ | 延遲 <20ms |
| 第 6 週 - 灰度發佈 | Week 4+ | ⏳ | 用戶反饋 +90 分 |

---

## 🐛 常見問題排查

### Q1: Kalman 改進後軌跡反而抖動

**原因**: MHT 的多個假設分歧  
**解決**:
```dart
// 減少假設數量或加強假設選擇
const int numHypotheses = 2;  // 從 3 改為 2
// 或提高平滑度權重
double minAccelVar = double.infinity;
for (final hyp in hypotheses) {
  final smoothness = 1.0 / calculateAccelerationVariance(hyp);
  // ...
}
```

### Q2: OpenCV JNI 編譯失敗

**原因**: NDK 版本不匹配或 OpenCV 路徑錯誤  
**解決**:
```cmake
# 在 CMakeLists.txt 中明確指定
set(OPENCV_DIR "/path/to/opencv/android")
find_package(OpenCV REQUIRED PATHS ${OPENCV_DIR})
```

### Q3: 設備上檢測率比預期低

**原因**: 設備解析度或編碼格式差異  
**解決**:
```kotlin
Log.d(TAG, "設備特性: ${Build.DEVICE}, Android=${Build.VERSION.SDK_INT}")
Log.d(TAG, "視頻格式: ${videoMime}, 解析度=${videoW}x${videoH}")
// 根據設備特性動態調整門檻
```

---

## 🔐 品質保證清單

### 上線前檢查
- [ ] 在 5+ 種設備上測試
- [ ] 無 crash 或 ANR
- [ ] 檢測率 ≥ 85%
- [ ] 平滑度分數 ≥ 0.80
- [ ] 總延遲 < 25ms
- [ ] 電池消耗無異常增加 (<5%)
- [ ] 內存無洩漏 (Profiler 驗證)

### 灰度發佈計畫
1. **內測 (1 天)**: 5 人團隊
   - 各方案對比
   - 邊界情況測試
   
2. **灰度 (3 天)**: 10% 用戶
   - 監控 crash rate
   - 收集性能數據
   - 用戶反饋
   
3. **全量 (1 天)**: 100% 用戶
   - 監控關鍵指標
   - 快速回滾方案

---

## 📚 參考文件

- [完整優化分析](TRAJECTORY_OPTIMIZATION_ANALYSIS.md)
- [骨架軌跡 Pipeline 診斷](SKELETON_TRAJECTORY_PIPELINE_DEBUG.md)
- [FPS 調試日誌](FPS_DEBUG_LOGGING.md)
- [性能優化機會](OPTIMIZATION_OPPORTUNITIES.md)

---

## 🎯 成功標誌

當以下條件全部達成時，優化完成:

✅ 檢測率: **85%+** (vs 60-70%)  
✅ 誤檢率: **<5%** (vs 15-20%)  
✅ 軌跡平滑度: **0.85+** (vs 0.72)  
✅ 總延遲: **<20ms** (vs 8-12ms with lower quality)  
✅ 用戶滿意度: **>4.5/5** (球軌跡清晰度)  
✅ 穩定性: **0 crash rate** 在灰度測試中
