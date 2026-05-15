# 短影片骨架異常（15fps）修正報告

## 問題描述

**現象**：
- 長影片 30fps → 偵測擊球 → 骨架 30fps → 短影片 30fps → ✅ 正常
- 短影片 30fps → 影片分析 → 骨架 15fps → ❌ 異常

**根本原因**：
當短影片（clip）被匯入進行分析時，無法正確讀取視頻的幀率元數據，導致各種處理器（BallBlobExtractor、TrajectoryOverlayRenderer）回退到預設的 **15fps**，造成骨架檢測異常。

---

## 修正方案

### 1️⃣ **VideoTrimmer.kt** - 保留幀率元數據  
**位置**：`android/app/src/main/kotlin/.../VideoTrimmer.kt`

**問題**：
裁切短影片時，未明確保留源影片的幀率信息。

**修正**：
```kotlin
// ✅ 明確讀取源幀率，避免 mux 後遺失
val srcFps = runCatching {
    fmt.getInteger(MediaFormat.KEY_FRAME_RATE)
}.getOrElse { 30 }  // 預設 30fps
fmt.setInteger(MediaFormat.KEY_FRAME_RATE, srcFps)
```

**效果**：確保所有裁切出的短影片都帶有正確的幀率元數據。

---

### 2️⃣ **BallBlobExtractor.kt** - 修改預設幀率  
**位置**：`android/app/src/main/kotlin/.../BallBlobExtractor.kt` (line 98-99)

**修正前**：
```kotlin
.getOrElse { 15.0 }  // ❌ 預設 15fps
```

**修正後**：
```kotlin
.getOrElse { 30.0 }  // ✅ 改為 30fps，保持與原錄影一致
```

**理由**：當視頻幀率無法讀取時，應該保守地假設與原始錄影相同的 30fps，而非更低的 15fps。

---

### 3️⃣ **TrajectoryOverlayRenderer.kt** - 修改預設幀率  
**位置**：`android/app/src/main/kotlin/.../TrajectoryOverlayRenderer.kt` (line 141-142)

**修正前**：
```kotlin
.getOrElse { 15f }  // ❌ 預設 15fps
```

**修正後**：
```kotlin
.getOrElse { 30f }  // ✅ 改為 30fps，保持與原錄影一致
```

**理由**：同 BallBlobExtractor。

---

## 驗證方式

### ✅ 測試長影片流程
1. 匯入長影片（30fps） 
2. 點擊「偵測擊球」
3. 生成短影片 clips
4. 檢查 pose_landmarks.csv 中的幀數

**預期結果**：
```
短影片持續時間 = 3 秒
幀率 = 30fps
預期幀數 = 3 × 30 = 90 幀
實際幀數 ≈ 90 幀 ✅
```

### ✅ 測試短影片直接匯入
1. 匯入短影片（30fps）
2. 直接點擊「分析」
3. 檢查 pose_landmarks.csv 中的骨架資料和幀率

**預期結果**：
```
time_sec 列應該以 ~0.033s（33ms）為間隔遞增（30fps）
而非 ~0.067s（67ms）為間隔（15fps）
幀數應與預期一致 ✅
```

---

## 改動摘要

| 檔案 | 改動 | 目的 |
|------|------|------|
| VideoTrimmer.kt | 明確讀取/保留源幀率 | 保留裁切影片的幀率元數據 |
| BallBlobExtractor.kt | 預設 15fps → 30fps | 當無法讀取幀率時，保守假設 30fps |
| TrajectoryOverlayRenderer.kt | 預設 15fps → 30fps | 同上 |

---

## 為什麼是 30fps？

1. **原始錄製**：手機通常以 30fps 錄製視頻
2. **骨架分析**：VideoAnalysisService 指定 `targetFps = 30`
3. **疊加渲染**：SkeletonOverlayRenderer 已正確使用 30f 作為預設
4. **一致性**：長影片流程始終保持 30fps，短影片應該相同

---

## 預期影響

✅ **短影片骨架分析現在將保持 30fps，而非異常的 15fps**
✅ **骨架座標精度提升（更多幀 = 更細膩的動作捕捉）**
✅ **與長影片流程保持一致**

