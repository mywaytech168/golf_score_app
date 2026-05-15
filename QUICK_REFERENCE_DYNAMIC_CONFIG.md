# 快速參考卡 - 動態檢測配置

## 🎯 3 個關鍵文件

### 1️⃣ 檢測配置計算 (Dart)
**文件**: `lib/services/detection_config.dart`

```dart
// 計算動態配置
final config = DetectionConfigCalculator.getDynamicDetectConfig(
  pIndex: 15,          // 追蹤點索引
  roiSize: 400,        // ROI 尺寸
  noCandCount: 2,      // 無檢測計數
  areaEma: 45.0,       // 面積 EMA
);

// 應用遠球自適應
final adaptiveConfig = DetectionConfigCalculator.getFarAdaptiveConfig(
  baseCfg: config,
  noCandCount: 2,
  areaEma: 45.0,
);

// 轉換為 MethodChannel 格式
Map<String, dynamic> configMap = config.toMap();
// → {'diffThresh': 14, 'areaLo': 4, 'areaHi': 200, 'circMin': 0.48}
```

### 2️⃣ 增強型追蹤器 (Dart)
**文件**: `lib/services/enhanced_ball_tracker.dart`

```dart
// 初始化
final tracker = EnhancedBallTracker(dt: 1.0 / 30.0);

// 計算當前配置
final config = tracker.getCurrentConfig(roiSize: 400);

// 步距衛士檢查
if (tracker.stepDistanceGuardCheck(candidate)) {
  // 通過檢查
  tracker.updateKalman(candidate.dx, candidate.dy);
}

// Y 方向篩選
final filtered = tracker.filterByYDirection(candidates);

// 追蹤狀態
tracker.recordNoCandidate();      // 無檢測
tracker.recordFoundCandidates();  // 有檢測
tracker.recordOutlier();          // 異常點
```

### 3️⃣ Kotlin 層接收配置
**文件**: `android/app/.../BallBlobExtractor.kt`

```kotlin
// 接收 MethodChannel 配置
val configMap = call.argument<Map<String, Any?>>("config")
val config = BallBlobExtractor.DetectionConfig.fromMap(configMap)

// extract() 調用
val extractor = BallBlobExtractor()
val result = extractor.extract(videoPath, configMap)  // 傳給 extract()

// 內部使用
val blobs = detectBlobs(cur, prev, w, h, stride, config)
// detectBlobs 內:
// binary[idx] = d >= config.diffThresh  (而不是常數)
// if (area in config.areaLo..config.areaHi)
```

---

## 📋 4 個重要常數

| 常數 | 值 | 用途 |
|------|-----|------|
| `STEP_EMA_ALPHA` | 0.25 | 步距平滑因子 |
| `STEP_ABS_MAX` | 140.0 | 基礎步距限制 |
| `STEP_ABS_HARD_MAX` | 130.0 | 硬限制 |
| `FAR_AREA_EMA_ALPHA` | 0.20 | 面積平滑因子 |

---

## 🔄 完整流程 (5 行代碼)

```dart
// 1. 計算配置
final config = tracker.getCurrentConfig(roiSize: 400);

// 2. 呼叫 Kotlin
final result = await platform.invokeMethod('extractBlobsWithConfig', {
  'videoPath': videoPath,
  'config': config.toMap(),
});

// 3. 處理結果
final candidates = result['blobs'].map((b) {
  return Offset(b['x'].toDouble(), b['y'].toDouble());
}).toList();

// 4. 應用規則
candidates = candidates.where((c) => 
  tracker.stepDistanceGuardCheck(c)).toList();
candidates = tracker.filterByYDirection(candidates);

// 5. 更新追蹤
if (candidates.isNotEmpty) {
  final best = candidates.first;
  tracker.updateKalman(best.dx, best.dy);
}
```

---

## ⚡ 最常用的方法

```dart
// 計算配置
tracker.getCurrentConfig(roiSize: 400)

// 步距衛士
tracker.stepDistanceGuardCheck(candidate)

// Y 方向篩選
tracker.filterByYDirection(candidates)

// 更新 EMA
tracker.updateAreaEmaFromBlob(area)

// Kalman 操作
tracker.predictKalman()
tracker.updateKalman(x, y)
tracker.getKalmanPos()
```

---

## 🧪 測試命令

```bash
# 運行所有配置測試
flutter test test/detection_config_test.dart

# 運行特定測試
flutter test test/detection_config_test.dart -k "getFarAdaptiveConfig"

# 生成覆蓋報告
flutter test test/detection_config_test.dart --coverage
```

---

## 🔍 除錯日誌

### Dart 層
```dart
// 打印當前配置
print('Config: ${tracker.getCurrentConfig(roiSize: 400)}');

// 打印 EMA 狀態
print('Area EMA: ${tracker.configManager.areaEma}');
print('Step EMA: ${tracker.configManager.stepEma}');

// 追蹤狀態
print('No Cand Count: ${tracker.noCandCount}');
print('Outlier Strikes: ${tracker.outlierStrikes}');
```

### Kotlin 層
```kotlin
// BallBlobExtractor.kt
Log.d(TAG, "Config: diff=${config.diffThresh}, area=[${config.areaLo}..${config.areaHi}]")

// 檢測結果
Log.d(TAG, "Found ${blobs.size} blobs with config=$config")
```

---

## 📊 參數範圍速查表

| 場景 | diffThresh | areaLo | areaHi | circMin |
|------|-----------|--------|--------|---------|
| 正常追蹤 | 16 | 6 | 150 | 0.60 |
| 球遠離 | 12 | 3 | 200 | 0.45 |
| 連續無檢測 | 10 | 2 | 250 | 0.35 |
| P0/P1 搜尋 | 16 | 6 | 150 | 0.60 |

---

## ✅ 驗收標準

- [ ] 默認配置 (無動態調整) 行為與原版相同
- [ ] 啟用動態配置後 blob 數量增加 10-30%
- [ ] 步距衛士篩選後誤檢降低 30-50%
- [ ] 軌跡平滑度提升 15-25%
- [ ] 無性能回歸 (每幀 < 2ms 額外延遲)

---

## 🚨 常見錯誤

❌ 錯誤:
```dart
// 忘記呼叫 updateConfig
final config = tracker.configManager.lastConfig;  // 這是上一幀的配置!
```

✅ 正確:
```dart
// 每幀都要重新計算
final config = tracker.getCurrentConfig(roiSize: 400);
```

❌ 錯誤:
```dart
// 配置未傳給 Kotlin
await platform.invokeMethod('extractBlobs', {'videoPath': path});
```

✅ 正確:
```dart
// 必須傳配置
final config = tracker.getCurrentConfig(roiSize: 400);
await platform.invokeMethod('extractBlobsWithConfig', {
  'videoPath': path,
  'config': config.toMap(),
});
```

---

## 📚 相關文檔

| 文檔 | 用途 |
|------|------|
| `INTEGRATION_GUIDE_DYNAMIC_CONFIG.md` | 詳細集成步驟 |
| `MIGRATION_REQUIREMENTS_ANALYSIS.md` | 完整遷移計畫 |
| `IMPLEMENTATION_SUMMARY.md` | 實施總結 |
| `lib/services/detection_config.dart` | 源代碼 |
| `lib/services/enhanced_ball_tracker.dart` | 源代碼 |
| `test/detection_config_test.dart` | 測試文件 |

---

**最後更新**: 2026-05-15
**版本**: 1.0
**狀態**: ✅ 完成
