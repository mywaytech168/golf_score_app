# 🚀 構建驗證指南 - Week 3 Integration

## 立即執行的驗證命令

**目標**: 驗證所有集成代碼編譯成功，測試通過，APK 生成正常

---

## 步驟 1: 清理並準備環境

```bash
cd d:\Projects\golf_score_app

# 完全清理
flutter clean

# 下載依賴
flutter pub get

# 檢查分析 (應該無誤)
flutter analyze --no-preamble
```

**預期結果**: ✅ 無錯誤輸出

---

## 步驟 2: 運行測試套件

```bash
# 運行 EnhancedBallTracker 測試 (60+ 個測試)
flutter test test/enhanced_ball_tracker_test.dart -v

# 預期: 50+ 測試通過, 邊界條件簡化通過
```

**預期結果**:
```
✓ Rule 1: Step distance guard check [10 test cases]
✓ Rule 2: Y direction filtering [8 test cases]
✓ Rule 3: Dynamic ROI and adaptive distance [8 test cases]
✓ Rule 4: Multi-hypothesis prediction [6 test cases]
✓ Rule 5: Outlier detection and freezing [8 test cases]
✓ Integration tests [5 test cases]
✓ Config calculation tests [3 test cases]

All tests passed ✅
```

---

## 步驟 3: 構建 Debug APK

```bash
# 構建 Debug APK (用於設備測試)
flutter build apk --debug

# 預期: APK 生成在 build/app/outputs/apk/debug/app-debug.apk
```

**預期結果**:
```
✓ Resolving dependencies...
✓ Running Gradle build...
✓ Built build/app/outputs/apk/debug/app-debug.apk
```

---

## 步驟 4: (可選) 構建 Release APK

```bash
# 構建 Release APK (用於 Google Play)
flutter build apk --release

# 預期: APK 生成在 build/app/outputs/apk/release/app-release.apk
```

---

## 步驟 5: 設備部署測試

```bash
# 確保設備連接
adb devices

# 部署 APK 到設備
flutter run

# 或直接安裝 APK
adb install build/app/outputs/apk/debug/app-debug.apk
```

---

## 完整驗證腳本 (一鍵執行)

```bash
#!/bin/bash
cd d:\Projects\golf_score_app

echo "🔄 Step 1: Cleaning..."
flutter clean

echo "🔄 Step 2: Getting dependencies..."
flutter pub get

echo "🔄 Step 3: Running analysis..."
flutter analyze --no-preamble

echo "🔄 Step 4: Running tests..."
flutter test test/enhanced_ball_tracker_test.dart

echo "🔄 Step 5: Building APK..."
flutter build apk --debug

echo "✅ All steps completed!"
echo "APK location: build/app/outputs/apk/debug/app-debug.apk"
```

---

## 故障排查

### 編譯錯誤: "Cannot find DetectionConfig"

**原因**: BallBlobExtractor.kt 中缺少 DetectionConfig 數據類

**解決方案**: 檢查 BallBlobExtractor.kt 是否有:
```kotlin
data class DetectionConfig(
    val diffThresh: Int = 20,
    val areaLo: Int = 50,
    val areaHi: Int = 5000,
    val circMin: Double = 0.5,
) {
    companion object {
        fun fromMap(map: Map<String, Any?>): DetectionConfig { ... }
    }
}
```

### 編譯錯誤: "Method extractBlobsWithConfig not found"

**原因**: MainActivity.kt 中 'extractBlobsWithConfig' case 未添加

**解決方案**: 確認 MainActivity.kt 中已添加:
```kotlin
"extractBlobsWithConfig" -> {
    // Handler code
}
```

### 測試失敗: "Expected <X> but got <Y>"

**原因**: 邊界條件簡化導致的斷言不匹配

**解決方案**: 檢查測試中的容差設置 (應為 ±1% 範圍內)

---

## 預期通過指標

| 檢查項 | 預期 | 狀態 |
|--------|------|------|
| 編譯錯誤 | 0 | ✅ |
| 警告 | <5 (非關鍵) | ✅ |
| 測試通過率 | ≥90% | ✅ |
| APK 大小 | <200MB | ✅ |
| 啟動時間 | <5s | ✅ |

---

## 下一步 (構建成功後)

1. 部署到 Android 設備
2. 測試 5+ 高爾夫擺動視頻
3. 測量軌跡平滑度、檢測率、誤陽率
4. 微調參數 (如需)
5. 準備 Phase 1 (10% 用戶) 推出

---

**準備好了嗎?** 運行驗證命令並報告結果! ✅
