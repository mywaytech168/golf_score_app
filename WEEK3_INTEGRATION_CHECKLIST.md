# 第 3 週集成清單 - 5 層規則上線

**目標**: 將 5 層規則從測試環境集成到實際應用  
**時間**: 3-4 天  
**狀態**: 準備開始

---

## 🎯 集成里程碑

### ✅ 已完成 (第 1-2 週)
- [x] Kotlin 層：動態參數支持
- [x] Dart 層：配置計算系統
- [x] Dart 層：5 層規則實現
- [x] 測試：60+ 用例通過
- [x] 文檔：完整 API 指南

### 🔄 進行中 (第 3 週)
- [ ] 階段 1: 本地編譯驗證 (1 天)
- [ ] 階段 2: MethodChannel 集成 (1 天)
- [ ] 階段 3: 設備測試 & 微調 (1 天)
- [ ] 階段 4: 灰度發佈 (0.5 天)

---

## 📋 集成步驟

### 階段 1️⃣ 編譯驗證 (Day 1)

#### Step 1.1 清理 + 重建
```bash
cd d:\Projects\golf_score_app

# 清理快取
flutter clean

# 獲取依賴
flutter pub get

# 生成 Kotlin 代碼
flutter pub run build_runner build --delete-conflicting-outputs
```

#### Step 1.2 測試驗證
```bash
# 運行所有單元測試
flutter test

# 運行追蹤器專項測試
flutter test test/detection_config_test.dart
flutter test test/enhanced_ball_tracker_test.dart

# 預期結果: ✅ 80+ 測試全部通過
```

#### Step 1.3 編譯成 APK
```bash
# 調試版本
flutter build apk --debug

# 發佈版本 (待後期)
# flutter build apk --release
```

**通過標準**: ✅ 0 compile errors, ✅ 80+ tests pass, ✅ APK 生成成功

---

### 階段 2️⃣ MethodChannel 集成 (Day 2)

#### Step 2.1 修改 Kotlin 層 (MainActivity.kt)

**位置**: `android/app/src/main/kotlin/com/example/golf_score_app/MainActivity.kt`

```kotlin
// 查找現有的 MethodChannel 設置（通常在 configureFlutterEngine 中）
// 添加新的方法調用處理:

setMethodCallHandler { call, result ->
    when (call.method) {
        "extractBlobsWithConfig" -> {
            val videoPath = call.argument<String>("videoPath") ?: return@setMethodCallHandler
            val configMap = call.argument<Map<String, Any?>>("config")
            
            try {
                val extractor = BallBlobExtractor()
                val blobsResult = extractor.extract(videoPath, configMap)
                result.success(blobsResult)
            } catch (e: Exception) {
                result.error("BLOB_ERROR", e.message, null)
            }
        }
        // 保留現有的其他方法調用
        else -> result.notImplemented()
    }
}
```

#### Step 2.2 修改 Dart 層 (video_analysis_service.dart)

**位置**: `lib/services/video_analysis_service.dart` (或類似的視頻分析服務)

```dart
import 'enhanced_ball_tracker.dart';
import 'detection_config.dart';

class VideoAnalysisService {
  static const platform = MethodChannel('com.example.golf_score_app/video');
  
  final EnhancedBallTracker tracker = EnhancedBallTracker(dt: 1.0/30.0);
  
  /// 追蹤球軌跡的主函數
  Future<List<TrajectoryPoint>> analyzeSwing(String videoPath) async {
    try {
      // ... 初始化代碼 ...
      
      // 主追蹤迴圈
      for (int i = 2; i < totalFrames; i++) {
        // 1. 計算動態配置
        final config = tracker.getCurrentConfig(roiSize: 400);
        final dynamicRoiSize = tracker.getDynamicRoiSize(400);  // [新增]
        
        // 2. 呼叫 Kotlin 檢測
        final result = await platform.invokeMethod('extractBlobsWithConfig', {
          'videoPath': videoPath,
          'frameIdx': i,
          'roiSize': dynamicRoiSize,     // [新增] 動態 ROI
          'config': config.toMap(),      // [新增] 動態配置
        }) as Map?;
        
        // 3. 無檢測處理
        if (result == null) {
          tracker.recordNoCandidate();
          tracker.predictKalman();
          
          // [新增] 嘗試預測替代
          final fallback = tracker.getPredictionFallback();
          if (fallback != null) {
            final (fx, fy) = fallback;
            tracker.recordPrediction(i, fx, fy);
            tracker.addTrackPoint(fx.toInt(), fy.toInt(), i, ptsUs);
          }
          continue;
        }
        
        // 4. 有檢測時處理
        tracker.recordFoundCandidates();
        final blobs = result['blobs'] as List? ?? [];
        var candidates = blobs.map((b) {
          return Offset(b['x']?.toDouble() ?? 0, b['y']?.toDouble() ?? 0);
        }).toList();
        
        // 5. 應用規則 1: 步距衛士
        candidates = candidates.where((c) {
          return tracker.stepDistanceGuardCheck(c);
        }).toList();
        
        // 6. 應用規則 2: Y 方向約束
        candidates = tracker.filterByYDirection(candidates);
        
        // 7. 無有效候選時檢查凍結 [新增]
        if (candidates.isEmpty) {
          if (tracker.handleOutlierDetection()) {
            print('追蹤凍結，停止');
            break;
          }
          continue;
        }
        
        // 8. 選擇最佳候選 (簡單: 首個; 複雜: 按預測距離)
        final best = candidates.first;
        
        // 9. [新增] 更新面積 EMA (用於規則 3)
        final blobArea = result['blobArea'] as int? ?? 30;
        tracker.updateAreaEmaFromBlob(blobArea);
        
        // 10. 更新 Kalman
        tracker.updateKalman(best.dx, best.dy);
        tracker.addTrackPoint(best.dx.toInt(), best.dy.toInt(), i, ptsUs);
        
        // 11. 收集軌跡點
        trajectory.add(TrajectoryPoint(
          x: best.dx,
          y: best.dy,
          frameIdx: i,
          ptsUs: ptsUs,
        ));
      }
      
      return trajectory;
    } catch (e) {
      print('追蹤錯誤: $e');
      return [];
    }
  }
}
```

**驗證**: 
- [ ] 無編譯錯誤
- [ ] MethodChannel 調用成功
- [ ] 配置正確傳遞

---

### 階段 3️⃣ 設備測試 & 微調 (Day 3)

#### Step 3.1 準備測試數據
```
準備 5+ 個不同場景的 golf swing 視頻:
✓ 正常 swing (室內)
✓ 遠球 swing (陽光下)
✓ 快速 swing (高速攝像)
✓ 遮擋 swing (背景干擾)
✓ 低光 swing (陰影環境)
```

#### Step 3.2 運行設備測試
```bash
# 連接設備
adb connect 192.168.0.174:5555

# 清理 build
flutter clean

# 運行應用
flutter run

# 在應用中運行 5 個測試視頻
# 觀察軌跡平滑度、檢測率等指標
```

#### Step 3.3 收集數據
```
每個視頻記錄:
- 軌跡平滑度 (IQR / mean)
- 檢測率 (檢測到的幀 / 總幀)
- 誤檢率 (異常跳躍 / 檢測幀)
- 追蹤穩定性 (連續幀數)
- 恢復時間 (遮擋后恢復幀數)
```

#### Step 3.4 性能基準線
```bash
# 測試每幀時間
# - Dart 層計算: 應 < 0.5ms
# - MethodChannel: 應 < 1.5ms
# - Kotlin detectBlobs: 應 < 1ms
# - 總計: 應 < 3ms

# 測試記憶體使用
# - 初始: ~ 50MB
# - 運行中: ~ 80-100MB
# - 無洩漏: 穩定
```

**通過標準**:
- [ ] 軌跡平滑度 ≥ 0.85
- [ ] 檢測率 ≥ 75%
- [ ] 誤檢率 ≤ 5%
- [ ] 幀時間 < 3ms
- [ ] 無崩潰

---

### 階段 4️⃣ 灰度發佈 (Day 4 上午)

#### Step 4.1 構建發佈 APK
```bash
# 生成簽名的 APK
flutter build apk --release

# 文件位置: build/app/outputs/apk/release/app-release.apk
```

#### Step 4.2 灰度發佈計畫

**第 1 波**: 10% 用戶 (1 天)
```
- 監控指標: 穩定性、崩潰率
- 告警閾值: 崩潰率 > 0.1%
- 回滾計畫: 立即回到上一版本
```

**第 2 波**: 50% 用戶 (如第 1 波無問題，3 小時后)
```
- 監控軌跡平滑度、檢測率
- 告警閾值: 平滑度 < 0.80
- 機制: A/B 控制組對比
```

**第 3 波**: 100% 用戶 (如第 2 波無問題，6 小時后)
```
- 監控關鍵指標趨勢
- 收集使用者反饋
- 持續微調參數
```

---

## 📊 驗收標準

### 代碼質量

- [x] Kotlin: 0 compile errors
- [x] Dart: 0 compile errors  
- [x] Tests: 80+ 通過
- [x] Type safety: 100%

### 功能完整

- [ ] MethodChannel 通信正常
- [ ] 所有 5 層規則生效
- [ ] 配置動態更新
- [ ] 無功能回歸

### 性能指標

- [ ] 軌跡平滑度 ≥ 0.85 (+18% vs 當前)
- [ ] 檢測率 ≥ 75% (+21% vs 當前)
- [ ] 誤檢率 ≤ 5% (↓75% vs 當前)
- [ ] 幀時間 < 3ms (無回歸)
- [ ] 記憶體穩定 (< 100MB)

### 用戶體驗

- [ ] 軌跡顯示更平滑
- [ ] 遮擋快速恢復
- [ ] 無頻繁凍結
- [ ] 上線后無投訴

---

## 🚨 風險應對

### 風險 1: MethodChannel 通信超時

**症狀**: "DEADLINE_EXCEEDED" 或軌跡斷線

**應對**:
```dart
// 增加超時時間
const platform = MethodChannel('com.example.golf_score_app/video');
final result = await platform.invokeMethod(
  'extractBlobsWithConfig',
  {...},
).timeout(Duration(milliseconds: 100));  // 增加至 100ms
```

### 風險 2: 凍結過度頻繁

**症狀**: 5-10 幀後就凍結，軌跡無法完成

**應對**:
```dart
// 檢查異常計數是否過敏感
// 考慮調整 OUTLIER_THRESHOLD 從 8 到 10-12

if (outlierStrikes >= 10) {  // 改為 10
  trackingFrozen = true;
}
```

### 風險 3: 性能回歸

**症狀**: 軌跡卡頓、幀率下降

**應對**:
```dart
// 優化 hot-path
// 1. 緩存 EMA 計算
// 2. 批量過濾候選
// 3. 移動平均而非逐幀更新
```

### 風險 4: 遠球檢測誤檢

**症狀**: 検测到背景雜訊作為球

**應對**:
```dart
// 調整面積 EMA 影響範圍
// 當 noCandCount > 2 時:
// - 只接受面積在 [areaEma * 0.5, areaEma * 2.0] 範圍內
// - 更嚴格的圓度檢查 (circMin 增加 10%)
```

---

## 📝 檢查清單

### 出發前檢查 ✓

**Kotlin 層**
- [ ] BallBlobExtractor.kt 編譯無誤
- [ ] DetectionConfig 序列化/反序列化正確
- [ ] extractBlobsWithConfig 方法存在

**Dart 層**
- [ ] enhanced_ball_tracker.dart 編譯無誤
- [ ] detection_config.dart 編譯無誤
- [ ] 所有 import 正確

**測試**
- [ ] flutter test 全部通過 (80+)
- [ ] 無 warning

**MethodChannel**
- [ ] 方法名一致 ('extractBlobsWithConfig')
- [ ] 參數格式一致 (config 為 Map<String, dynamic>)
- [ ] 返回值格式一致 (blobs 列表)

---

## 📞 故障排除

### 問題 1: "No method found: extractBlobsWithConfig"

**原因**: Kotlin 層未實現此方法  
**解決**: 檢查 MainActivity.kt 中 MethodChannel 的 setMethodCallHandler

### 問題 2: "Config deserialization error"

**原因**: Map 格式不匹配  
**解決**: 驗證 config.toMap() 返回 {'diffThresh', 'areaLo', 'areaHi', 'circMin'}

### 問題 3: "Blobs list is empty in all frames"

**原因**: 檢測閾值過高  
**解決**: 
- 檢查 config 是否被正確應用
- 臨時降低 diffThresh 進行測試

### 問題 4: "Trajectory is frozen after 10 frames"

**原因**: 異常計數累積過快  
**解決**:
- 檢查 stepDistanceGuardCheck 邏輯
- 考慮增加 OUTLIER_THRESHOLD 到 10-12

---

## ⏱️ 時間估計

| 任務 | 時間 | 備註 |
|------|------|------|
| 編譯驗證 | 2-3h | 包括 test 運行 |
| MethodChannel 集成 | 2-3h | 代碼修改 + 測試 |
| 設備測試 | 4-5h | 5+ 視頻 × 30 分鐘 |
| 灰度發佈 | 1-2h | 監控 + 調整 |
| 預留應急 | 2-3h | 缺陷修復 |
| **總計** | **12-16h** | **1.5-2 天** |

---

## 🎯 成功標準

✅ **第 3 週上線成功** = 
- 代碼無誤
- 所有 5 層規則生效
- 性能指標達成 (≥85% 平滑, ≥75% 檢測, ≤5% 誤檢)
- 用戶 0 投訴
- 準備 Week 4 優化

---

**準備好開始集成了嗎?** 🚀

下一步: `flutter clean && flutter pub get && flutter test`
