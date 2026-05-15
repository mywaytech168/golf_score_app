# Python → Android/Dart 軌跡追蹤規則遷移 - 完整需求分析

**文檔日期**: 2026-05-15  
**目的**: 分析將 Python 版本的追蹤規則遷移到 Android/Dart 需要的技術、資源、測試和時間

---

## 📋 當前架構狀態分析

### Android/Dart 現有構成

```
┌─────────────────────────────────────────────────────────────────┐
│                     當前系統層次結構                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  Dart 層 (lib/services/)                                         │
│  ├─ ball_tracker.dart              ← 追蹤邏輯主文件              │
│  │  └─ Kalman2D 類                 ✅ 已有                      │
│  ├─ video_analysis_service.dart    ← 流程編排                   │
│  └─ [其他輔助服務]                                               │
│                                                                   │
│  Kotlin 層 (android/app/src/main/kotlin/)                       │
│  ├─ BallBlobExtractor.kt           ← 球檢測 (幀差法)            │
│  │  └─ detectBlobs()               ✅ 已有                      │
│  ├─ TrajectoryOverlayRenderer.kt   ← 軌跡渲染                   │
│  ├─ SkeletonOverlayRenderer.kt     ← 骨架渲染                   │
│  └─ [其他渲染器]                                                 │
│                                                                   │
│  MethodChannel 通信                                               │
│  └─ 傳遞: FrameBlobs → Dart → TrackPoint → Kotlin               │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
```

### Python 版本缺失的 5 層規則

```
┌─────────────────────────────────────────┐
│   Python 版本有但 Dart 版本缺少         │
├─────────────────────────────────────────┤
│                                          │
│ ❌ 步距衛士 (Step Distance Guard)       │
│    - EMA 步距追蹤                       │
│    - 動態限制                           │
│    - 硬上限 (130px)                    │
│                                          │
│ ❌ Y 方向約束 (Y Direction Constraint)  │
│    - 方向推斷 (前 3 點)                │
│    - 方向過濾                           │
│    - 距離限制                           │
│                                          │
│ ❌ 遠球自適應 (Far-ball Adaptive)      │
│    - 無檢測計數器                       │
│    - 門檻寬鬆化                         │
│    - ROI 動態擴大                      │
│    - 面積 EMA                          │
│                                          │
│ ❌ 多假設預測替代 (Blue History)       │
│    - Kalman 預測歷史                    │
│    - 無檢測時替代                       │
│                                          │
│ ❌ 異常值檢測 (Outlier Detection)      │
│    - 連續異常計數                       │
│    - 凍結追蹤                           │
│                                          │
└─────────────────────────────────────────┘
```

---

## 🔧 遷移需求詳細分析

### 需求 1: 步距衛士 (Step Distance Guard)

#### 技術需求

**Dart 層** (lib/services/):
```dart
// 新建文件: lib/services/step_distance_guard.dart

需要的核心功能:
  ✅ EMA 計算 (指數移動平均)
  ✅ 動態限制計算
  ✅ 向量距離計算
  ✅ 參數存儲

需要的數據結構:
  ✅ 步距 EMA 狀態
  ✅ 無候選計數
  ✅ 配置參數
  
需要的外部依賴:
  ✅ dart:math (max, min, sqrt)
  ✅ Offset 類 (已有 from dart:ui)
  ✅ Kalman 預測值 (from ball_tracker.dart)
```

#### 集成點

| 文件 | 修改類型 | 行數 | 優先級 |
|------|---------|------|-------|
| `lib/services/ball_tracker.dart` | import + 調用 | 10 | 🔴 |
| `lib/services/enhanced_ball_tracker.dart` | 新文件 | 50 | 🔴 |
| `test/ball_tracker_test.dart` | 新測試 | 80 | 🟡 |

#### 數據流向

```
Frame N:
  └─> Kalman 預測
  └─> 候選球關聯
      └─> 步距檢查 (新增)
          ├─ 計算: step = ||candidate - lastPoint||
          ├─ 限制: hard_lim = min(130, base_lim * factor)
          └─ 決策: accept if step < hard_lim
      └─> 更新 EMA
      └─> Kalman 更新
```

#### 所需參數

```dart
class StepDistanceGuardConfig {
  static const double STEP_EMA_ALPHA = 0.25;        // EMA 平滑因子
  static const double STEP_GROWTH_FACTOR = 1.9;    // 基礎限制增長因子
  static const double STEP_ABS_MAX = 140.0;        // 基礎限制
  static const double STEP_ABS_HARD_MAX = 130.0;  // 硬限制
  static const double PRED_DIST_HARD_MAX = 170.0; // 預測距離限制
  static const double NO_CAND_FACTOR = 0.35;      // 無候選時的寬鬆因子
}
```

#### 測試用例

```dart
test('Step Guard rejects large jumps', () {
  // 正常步距: 應接受
  // 過大跳躍: 應拒絕
  // EMA 更新: 應正確計算
  // 無候選時: 應寬鬆
});
```

---

### 需求 2: Y 方向約束

#### 技術需求

**Dart 層**:
```dart
// 新建文件: lib/services/y_direction_constraint.dart

需要的核心功能:
  ✅ 方向推斷 (前 3 點計算)
  ✅ 方向過濾
  ✅ 距離限制

需要的數據結構:
  ✅ Y 方向狀態 (1/-1/null)
  ✅ 軌跡點歷史
  
需要的外部依賴:
  ✅ Offset 類
  ✅ List<BlobData>
```

#### 集成點

| 文件 | 修改類型 | 行數 |
|------|---------|------|
| `lib/services/ball_tracker.dart` | import + 調用 | 15 |
| `lib/services/y_direction_constraint.dart` | 新文件 | 60 |
| `test/y_constraint_test.dart` | 新測試 | 70 |

#### 数据流向

```
Frame 1-2:
  └─> 累積軌跡點 < 3

Frame 3+:
  ├─> if trackPoints.length >= 3 且 y_dir == null:
  │   ├─ dy = trackPoints[2].y - trackPoints[0].y
  │   └─ y_dir = dy > 0 ? 1 : -1
  │
  └─> 過濾候選球:
      ├─ if y_dir == -1 (向上): pt.y <= lastPt.y + TOL
      ├─ if y_dir == 1 (向下): pt.y >= lastPt.y - TOL
      └─ 距離限制: |pt.y - lastPt.y| <= MAX_STEP
```

#### 所需參數

```dart
class YDirectionConstraintConfig {
  static const int Y_TOLERANCE = 1;       // Y 方向容差
  static const int Y_MAX_STEP = 80;       // 最大 Y 距離
  static const int MIN_POINTS_TO_INFER = 3;  // 推斷所需最小點數
}
```

---

### 需求 3: 遠球自適應檢測

#### 技術需求

**Dart 層**:
```dart
需要的核心功能:
  ✅ 無檢測計數管理
  ✅ 門檻寬鬆化計算
  ✅ 面積 EMA 追蹤
```

**Kotlin 層** (BallBlobExtractor.kt):
```kotlin
需要的修改:
  ✅ 檢測配置結構體 (可選化)
  ✅ 動態參數調整函數
  ✅ 門檻應用邏輯
```

#### 集成點

| 文件 | 修改類型 | 行數 |
|------|---------|------|
| `lib/services/ball_tracker.dart` | 邏輯修改 | 30 |
| `lib/services/far_ball_adaptive.dart` | 新文件 | 70 |
| `android/app/src/main/kotlin/.../BallBlobExtractor.kt` | 修改 | 50 |
| `test/far_adaptive_test.dart` | 新測試 | 60 |

#### 所需參數

```dart
class FarBallAdaptiveConfig {
  static const int FAR_DIFF_FLOOR = 3;
  static const double FAR_CIRC_FLOOR = 0.35;
  static const int FAR_AREA_LO_FLOOR = 1;
  static const double FAR_RELAX_GAIN = 1.0;
  static const int RECOVERY_ROI_GROW_PER_MISS = 35;
  static const int RECOVERY_ROI_MAX = 420;
  static const int NO_CAND_PATIENCE = 4;
  static const double FAR_AREA_EMA_ALPHA = 0.20;
}
```

---

### 需求 4: 多假設預測替代 (Blue History)

#### 技術需求

**Dart 層**:
```dart
需要的核心功能:
  ✅ 圓形緩衝區 (Queue with maxSize)
  ✅ 預測點存儲
  ✅ 歷史訪問邏輯
```

#### 集成點

| 文件 | 修改類型 | 行數 |
|------|---------|------|
| `lib/services/ball_tracker.dart` | 邏輯修改 | 25 |
| `lib/services/kalman_prediction_history.dart` | 新文件 | 40 |

#### 所需參數

```dart
class BlueHistoryConfig {
  static const int HISTORY_SIZE = 30;  // 最多保留 30 幀預測
  static const int BLUE_P_OFFSET = -2;  // 往前 2 幀
  static const double BLUE_TO_LASTP_MAX_DIST = 150.0;  // 距離驗證
}
```

---

### 需求 5: 異常值檢測

#### 技術需求

**Dart 層**:
```dart
需要的核心功能:
  ✅ 異常值計數
  ✅ 追蹤凍結邏輯
  ✅ 狀態轉移
```

#### 所需參數

```dart
class OutlierDetectionConfig {
  static const int OUTLIER_STRIKES_TO_FREEZE = 8;  // 8 次異常後凍結
}
```

---

## 📁 檔案清單與修改詳情

### 需要建立的新文件 (Dart 層)

```
lib/services/
├─ step_distance_guard.dart           (新建, 60 行)
├─ y_direction_constraint.dart        (新建, 70 行)
├─ far_ball_adaptive.dart             (新建, 80 行)
├─ kalman_prediction_history.dart     (新建, 50 行)
├─ outlier_detector.dart              (新建, 40 行)
└─ enhanced_ball_tracker.dart         (新建, 150 行, 整合 5 個模塊)

test/
├─ step_guard_test.dart               (新建, 80 行)
├─ y_constraint_test.dart             (新建, 70 行)
├─ far_adaptive_test.dart             (新建, 60 行)
├─ blue_history_test.dart             (新建, 50 行)
└─ ab_test_python_features.dart       (新建, 120 行)
```

### 需要修改的現有文件

#### Dart 層

| 文件 | 修改內容 | 行數 | 複雜度 |
|------|---------|------|--------|
| `lib/services/ball_tracker.dart` | import 5 個新模塊 | +10 | 低 |
| `lib/services/video_analysis_service.dart` | 調用新追蹤器 | +5 | 低 |
| `lib/main.dart` | 配置開關 | +2 | 低 |

#### Kotlin 層

| 文件 | 修改內容 | 行數 | 複雜度 |
|------|---------|------|--------|
| `BallBlobExtractor.kt` | 動態參數調整函數 | +50 | 中 |
| `TrajectoryOverlayRenderer.kt` | ROI 恢復邏輯 | +20 | 低 |

### 檔案依賴關係

```
┌──────────────────────────────────────────────────────────┐
│           遷移檔案依賴關係圖                               │
├──────────────────────────────────────────────────────────┤
│                                                            │
│  BlobData (既有)                                           │
│  │                                                         │
│  ├─> StepDistanceGuard (新)                              │
│  │    └─> EnhancedBallTracker (新)                        │
│  │                                                         │
│  ├─> YDirectionConstraint (新)                            │
│  │    └─> EnhancedBallTracker                             │
│  │                                                         │
│  ├─> FarBallAdaptive (新)                                │
│  │    ├─> BallBlobExtractor (修改)                        │
│  │    └─> EnhancedBallTracker                             │
│  │                                                         │
│  ├─> KalmanPredictionHistory (新)                         │
│  │    └─> EnhancedBallTracker                             │
│  │                                                         │
│  └─> OutlierDetector (新)                                │
│       └─> EnhancedBallTracker                             │
│                                                            │
│  EnhancedBallTracker 整合所有模塊                         │
│    └─> VideoAnalysisService (修改)                       │
│                                                            │
└──────────────────────────────────────────────────────────┘
```

---

## ⚙️ 技術細節需求

### 1. 向量計算工具函數

```dart
// lib/services/vector_utils.dart (新建)
class VectorUtils {
  // 已有的基礎計算
  static double distance(Offset a, Offset b) => (a - b).distance;
  
  // 新增的計算
  static double emaUpdate(double? current, double newValue, double alpha) {
    return current == null 
        ? newValue 
        : (1 - alpha) * current + alpha * newValue;
  }
  
  static double clamp(double value, double min, double max) {
    return value < min ? min : (value > max ? max : value);
  }
}
```

### 2. 狀態管理

```dart
// 修改 ball_tracker.dart 中的狀態
class TrackingState {
  // 現有狀態
  final Kalman2D kalman;
  final List<TrackPoint> trackPoints;
  
  // 新增狀態
  final StepDistanceGuard stepGuard = StepDistanceGuard();
  final YDirectionConstraint yConstraint = YDirectionConstraint();
  final FarBallAdaptive farAdaptive = FarBallAdaptive();
  final KalmanPredictionHistory predictionHistory = KalmanPredictionHistory();
  final OutlierDetector outlierDetector = OutlierDetector();
  
  int noCandCount = 0;
  int outlierStrikes = 0;
}
```

### 3. 配置管理

```dart
// lib/services/trajectory_config.dart (新建或擴展)
class TrajectoryConfig {
  // 步距衛士
  static const USE_STEP_DIST_GUARD = true;
  static const STEP_EMA_ALPHA = 0.25;
  
  // Y 方向約束
  static const USE_Y_DIRECTION = true;
  static const Y_TOLERANCE = 1;
  
  // 遠球自適應
  static const ENABLE_FAR_ADAPTIVE = true;
  static const NO_CAND_PATIENCE = 4;
  
  // 預測替代
  static const TOO_MANY_CANDS_USE_BLUE_AS_P = true;
  static const TOO_MANY_CANDS_THRESHOLD = 4;
  
  // 異常值檢測
  static const OUTLIER_STRIKES_TO_FREEZE = 8;
}
```

---

## 🧪 測試需求

### 單元測試

```dart
// test/step_guard_test.dart
testWidgets('Step Guard accepts normal motion', ...) { ... }
testWidgets('Step Guard rejects large jumps', ...) { ... }
testWidgets('Step Guard updates EMA correctly', ...) { ... }
testWidgets('Step Guard relaxes when no candidates', ...) { ... }

// test/y_constraint_test.dart
testWidgets('Y constraint infers direction from 3 points', ...) { ... }
testWidgets('Y constraint filters by direction', ...) { ... }
testWidgets('Y constraint respects distance limits', ...) { ... }

// test/far_adaptive_test.dart
testWidgets('Far adaptive relaxes on misses', ...) { ... }
testWidgets('Far adaptive applies area EMA', ...) { ... }
```

### 集成測試

```dart
// test/trajectory_features_integration_test.dart
testWidgets('All features work together', ...) {
  // 模擬視頻，應用所有 5 個特性
  // 驗證最終軌跡質量
});
```

### A/B 測試

```dart
// test/ab_test_python_features.dart
void main() {
  group('Python Features A/B Test', () {
    test('Step Guard + Original', () async {
      final original = await track(video, useEnhanced: false);
      final enhanced = await track(video, useEnhanced: true);
      
      expect(enhanced.smoothness, greaterThan(original.smoothness * 1.25));
    });
    
    test('All Features', () async {
      final baseline = await track(video, useEnhanced: false);
      final fullFeatures = await track(video, useEnhanced: true, 
                                       allFeatures: true);
      
      expect(fullFeatures.detectionRate, greaterThan(baseline.detectionRate * 1.2));
      expect(fullFeatures.falsePositives, lessThan(baseline.falsePositives * 0.5));
    });
  });
}
```

### 性能基準測試

```dart
// test/performance_benchmark.dart
void main() {
  benchmark('Step Guard overhead', () {
    // 應 < 1ms per frame
  });
  
  benchmark('Y Direction filtering overhead', () {
    // 應 < 0.5ms per frame
  });
  
  benchmark('Far Adaptive overhead', () {
    // 應 < 1ms per frame
  });
}
```

---

## 📊 資源需求評估

### 開發工時估算

| 任務 | 工時 (小時) | 複雜度 | 備註 |
|------|-----------|--------|------|
| **第 1 週: 快速勝利** | | | |
| 步距衛士 | 4-6 | ⭐ | 包括測試 |
| Y 方向約束 | 4-5 | ⭐ | 包括測試 |
| 整合 + 測試 | 3-4 | ⭐⭐ | A/B 測試 |
| **小計** | **11-15** | | **1 週** |
| | | | |
| **第 2 週: 中等效果** | | | |
| 遠球自適應 | 5-7 | ⭐⭐ | Kotlin 修改 |
| 預測替代 | 3-4 | ⭐⭐ | Queue 實現 |
| 異常值檢測 | 2-3 | ⭐ | 簡單狀態機 |
| 集成測試 | 4-6 | ⭐⭐ | 完整流程 |
| **小計** | **14-20** | | **1.5 週** |
| | | | |
| **第 3 週: 優化 & 發佈** | | | |
| 性能優化 | 3-5 | ⭐⭐ | 延遲分析 |
| 文檔 & 演練 | 2-3 | ⭐ | 培訓 |
| 灰度測試 | 5-8 | ⭐⭐⭐ | 真實設備 |
| **小計** | **10-16** | | **1 週** |
| | | | |
| **總計** | **35-51 小時** | | **3-3.5 週** |

### 人力需求

```
第 1-3 週:
  ├─ 主要開發者: 1 名 (全職)
  ├─ 代碼審查者: 1 名 (兼職, 每日 1 小時)
  ├─ QA 測試者: 1 名 (第 3 週)
  └─ 設備資源: 2-3 台 Android 設備
```

### 測試環境需求

```
開發環境:
  ✅ Dart SDK 3.0+
  ✅ Android NDK (if C++ OpenCV)
  ✅ 5+ 高爾夫視頻 (多場景)

測試設備:
  ✅ Android 11+ 設備 (至少 2 台不同型號)
  ✅ 高分辨率屏幕 (驗證視覺效果)
  
工具:
  ✅ Android Studio
  ✅ Flutter DevTools
  ✅ Git (版本控制)
  ✅ CI/CD 流程
```

---

## 🚦 依賴關係與優先級

### 關鍵路徑 (Critical Path)

```
1. 步距衛士 (Step Guard)
   └─ 必須優先 (其他特性的基礎)
   
2. Y 方向約束
   └─ 可與步距衛士並行
   
3. 集成測試
   └─ 步距衛士 + Y 方向 完成後
   
4. 遠球自適應
   └─ 需要修改 Kotlin 層 (並行可進行)
   
5. 預測替代 + 異常值檢測
   └─ 非關鍵路徑 (可稍後)
```

### 並行性分析

```
第 1 週 (可並行):
  開發者 A: 步距衛士
  開發者 B: Y 方向約束
  (第 3 天後) 開發者 A+B: 集成

第 2 週 (可並行):
  開發者 A: 遠球自適應 (Dart 層)
  開發者 B: 遠球自適應 (Kotlin 層)
  開發者 C: 預測替代 + 異常值檢測

第 3 週:
  統一集成 + 灰度測試
```

---

## ⚠️ 風險分析與緩解策略

### 風險矩陣

| 風險 | 概率 | 影響 | 緩解策略 |
|------|------|------|---------|
| **Kalman 預測值的質量下降** | 高 | 高 | 需要充分測試預測準確性 |
| **參數調整導致過度平滑** | 中 | 中 | 提供參數調整 UI |
| **Kotlin 層修改引入 bug** | 中 | 高 | 完整單元測試 Kotlin 代碼 |
| **性能回歸 (延遲增加)** | 中 | 中 | 基準測試 + 限制每個模塊 <1ms |
| **不同 Android 版本兼容性** | 低 | 中 | 多設備測試 |
| **梯度式發佈失敗** | 低 | 高 | A/B 測試 + 快速回滾計劃 |

### 回滾計劃

```
如果發現問題:
  1. 立即禁用新特性 (配置開關)
  2. 收集設備日誌 + 用戶反饋
  3. 本地重現 + 調試
  4. 修復後重新測試
  5. 縮小灰度範圍 (1% → 0.5%)

回滾時間: < 1 小時 (遠程禁用)
```

---

## 📈 預期改善指標

### 定量指標

| 指標 | 當前 | 目標 | 獲得方式 |
|------|------|------|---------|
| 軌跡平滑度 | 0.72 | 0.88 | 步距衛士 + Y 方向 |
| 檢測率 | 60% | 75% | 遠球自適應 |
| 誤檢率 | 18% | 5% | 步距衛士 + Y 方向 |
| 無檢測容忍 | 2 幀 | 4 幀 | 預測替代 |
| 追蹤穩定性 | 良好 | 很好 | 異常值檢測 |

### 定性指標

```
用戶體驗改善:
  ✅ 軌跡更連貫 (平滑度提升)
  ✅ 更少誤檢 (減少人工手動)
  ✅ 各場景適應性好 (遠球、遮擋)
  ✅ 球被暫時遮擋時能自動恢復

開發者體驗:
  ✅ 代碼更模塊化 (易於維護)
  ✅ 參數更易調整 (配置驅動)
  ✅ 測試覆蓋更全面
```

---

## 📋 遷移檢查清單

### 第 0 週 (準備)

- [ ] 環境檢查 (Dart SDK, Android SDK, Git)
- [ ] 代碼審查: 現有 ball_tracker.dart 結構
- [ ] 建立特性分支 (git checkout -b migration/python-features)
- [ ] 創建 CHANGELOG 條目

### 第 1 週 (步距衛士 + Y 方向)

#### 步距衛士
- [ ] 建立 `step_distance_guard.dart`
- [ ] 實現 StepDistanceGuard 類
- [ ] 編寫單元測試 (4+ 個測試用例)
- [ ] 整合到 ball_tracker.dart
- [ ] 代碼審查
- [ ] 本地驗證

#### Y 方向約束
- [ ] 建立 `y_direction_constraint.dart`
- [ ] 實現 YDirectionConstraint 類
- [ ] 編寫單元測試 (4+ 個測試用例)
- [ ] 整合到 ball_tracker.dart
- [ ] 代碼審查
- [ ] 本地驗證

#### 集成 & 測試
- [ ] 建立 `enhanced_ball_tracker.dart`
- [ ] 整合 2 個特性
- [ ] A/B 測試 (對比原版本)
- [ ] 性能測試 (延遲 < 2ms)
- [ ] 文檔更新

### 第 2 週 (遠球自適應 + 預測替代 + 異常值)

#### 遠球自適應
- [ ] 建立 `far_ball_adaptive.dart` (Dart 層)
- [ ] 修改 `BallBlobExtractor.kt` (Kotlin 層)
- [ ] 實現動態參數調整邏輯
- [ ] 編寫測試 (各光照場景)
- [ ] 代碼審查

#### 預測替代
- [ ] 建立 `kalman_prediction_history.dart`
- [ ] 實現 blue_hist 機制
- [ ] 測試無檢測恢復場景

#### 異常值檢測
- [ ] 建立 `outlier_detector.dart`
- [ ] 實現異常值計數 + 凍結邏輯
- [ ] 測試

#### 全集成測試
- [ ] 所有 5 個特性一起運行
- [ ] 完整流程測試 (10+ 視頻)
- [ ] 性能基準 (總延遲 < 5ms)

### 第 3 週 (優化 & 發佈)

#### 優化
- [ ] 識別性能瓶頸
- [ ] 優化 Kotlin 層 (如需)
- [ ] 參數微調
- [ ] 文檔最終化

#### 灰度發佈
- [ ] 內部測試 (5 人, 1 天)
- [ ] 灰度 1% (1 天, 監控)
- [ ] 灰度 10% (2 天, 監控)
- [ ] 灰度 100% (1 天, 監控)
- [ ] 發佈說明

### 上線後

- [ ] 持續監控 (crash rate, 性能)
- [ ] 收集用戶反饋
- [ ] 參數微調 (基於真實數據)
- [ ] 發佈文檔博客

---

## 📚 所需文檔

### 內部文檔

```
docs/
├─ architecture.md              (系統架構 - 需更新)
├─ ball_tracking_design.md      (軌跡追蹤設計文檔 - 新)
├─ python_migration_guide.md    (遷移指南 - 新)
├─ parameters_reference.md      (參數參考 - 新)
└─ troubleshooting.md           (故障排除 - 新)
```

### 用戶文檔

```
docs/user/
├─ changelog.md                 (更新日誌)
├─ performance_tips.md          (性能提示)
└─ known_issues.md              (已知問題)
```

---

## 🔄 遷移流程圖

```
START
  │
  ├─> 環境檢查 (第 0 週)
  │   └─> ✅ 通過 → 繼續
  │
  ├─> 步距衛士 (第 1 週)
  │   ├─> 實現 → 測試 → 審查 → ✅
  │   │
  │   └─> Y 方向約束 (並行)
  │       ├─> 實現 → 測試 → 審查 → ✅
  │       │
  │       └─> 集成測試
  │           └─> 性能驗證 → ✅
  │
  ├─> 遠球自適應 (第 2 週)
  │   ├─> Dart 層 (並行 Kotlin)
  │   │   └─> ✅
  │   │
  │   └─> Kotlin 層
  │       └─> ✅
  │
  ├─> 預測替代 + 異常值檢測
  │   └─> ✅
  │
  ├─> 全集成測試
  │   └─> ✅ 通過 → 繼續
  │       ❌ 失敗 → 修復 → 重新測試
  │
  ├─> 性能優化 (第 3 週)
  │   └─> ✅
  │
  ├─> 灰度發佈
  │   ├─> 1% (監控 24h)
  │   ├─> 10% (監控 48h)
  │   ├─> 100% (監控 7 天)
  │   └─> ✅
  │
  └─> END
```

---

## 📞 溝通計劃

### 每週同步

**第 1 週**:
- Monday 10:00: 專案啟動會議 (30 min)
  - 確認目標、資源、風險
  - 分配任務
- Thursday 15:00: 進度更新 (15 min)
  - 分享完成情況
  - 發現的問題

**第 2 週**:
- Monday 10:00: 進度審查 (30 min)
  - 第 1 週成果演示
  - 第 2 週計劃調整
- Thursday 15:00: 技術討論 (30 min)
  - 代碼審查反饋
  - 問題解決

**第 3 週**:
- Monday 10:00: 集成審查 (30 min)
  - 全功能演示
  - 發佈準備
- Thursday 15:00: 灰度計劃 (30 min)
  - 監控指標確認
  - 應急計劃

### 異步溝通

- **GitHub Issues**: 跟蹤任務和 bug
- **PR Reviews**: 代碼質量把控
- **Slack**: 日常快速溝通

---

## 🎯 成功標誌

✅ **第 1 週**:
- 步距衛士 + Y 方向完成
- A/B 測試顯示平滑度 +25%
- 零 crash 在本地測試

✅ **第 2 週**:
- 所有 5 個特性完成
- 檢測率 +15%, 誤檢率 ↓50%
- 內部測試通過

✅ **第 3 週**:
- 灰度 100% 無異常
- 用戶反饋正面
- 性能指標達成

✅ **上線**:
- 軌跡平滑度 0.72 → 0.88
- 檢測率 60% → 75%
- 用戶滿意度 +0.5 分

---

## 📊 監控指標

### 實時監控 (灰度期間)

```
Dashboard:
  ├─ Crash Rate (目標: < 0.1%)
  ├─ ANR Rate (目標: 0%)
  ├─ 平均軌跡長度 (目標: ↑10%)
  ├─ 追蹤失敗率 (目標: ↓30%)
  └─ 用戶滿意度 (目標: ↑)

告警:
  ⚠️  Crash Rate > 0.5% → 立即停止灰度
  ⚠️  ANR > 5 起 → 調查性能問題
  ⚠️  軌跡精度下降 > 5% → 回滾
```

---

## 總結

### 所需東西清單

| 類別 | 項目 | 需求 |
|------|------|------|
| **人力資源** | 開發者 | 1 名全職 + 1 名兼職審查 |
| | QA | 1 名 (第 3 週) |
| **時間** | 開發 | 35-51 小時 |
| | 測試 | 20-30 小時 |
| | 總計 | 3-3.5 週 |
| **基礎設施** | 開發環境 | Dart + Android SDK |
| | 測試設備 | 2-3 台 Android 設備 |
| | CI/CD | GitHub Actions (可選) |
| **文檔** | 設計文檔 | 5 份新文檔 |
| | 代碼註釋 | 詳細的內聯註釋 |
| **技術棧** | Dart 庫 | dart:math, dart:typed_data |
| | Kotlin 庫 | Android MediaCodec API |

### 核心里程碑

1. ✅ **第 1 週**: 步距衛士 + Y 方向完成
2. ✅ **第 2 週**: 所有 5 特性完成
3. ✅ **第 3 週**: 灰度發佈完成
4. ✅ **目標**: 平滑度 +22%, 檢測率 +25%

---

## 🔗 參考資源

- [PYTHON_TRAJECTORY_ALGORITHM_ANALYSIS.md](PYTHON_TRAJECTORY_ALGORITHM_ANALYSIS.md) - Python 算法詳解
- [PYTHON_TO_ANDROID_MIGRATION_GUIDE.md](PYTHON_TO_ANDROID_MIGRATION_GUIDE.md) - 遷移技術指南
- [TRAJECTORY_OPTIMIZATION_ANALYSIS.md](TRAJECTORY_OPTIMIZATION_ANALYSIS.md) - 完整優化分析
- [trajectory_tracker_v3_stable.py](python/trajectory_tracker_v3_stable.py) - Python 參考實現
