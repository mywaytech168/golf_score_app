# 🔴 重大發現：坐標系統邏輯錯誤分析

## 問題症狀

在 SkeletonOverlayRenderer.kt 的 drawSkeleton 函數中：

```kotlin
private fun drawSkeleton(
    canvas: Canvas,
    landmarks: Array<LandmarkPoint?>,
    poseW: Float, poseH: Float,           // ← inferPoseImageSize 推算的值
    displayW: Int, displayH: Int,          // ← 輸出視頻尺寸
) {
    val scaleX  = displayW.toFloat() / poseW   // ← 縮放係數
    val scaleY  = displayH.toFloat() / poseH
    
    // ... 繪製時應用縮放
    canvas.drawLine(la.xPx * scaleX, la.yPx * scaleY, ...)
}
```

**問題：** 這個縮放邏輯是**基於假設** poseW/poseH 是小於 displayW/displayH 的，但實際上：

```
inferPoseImageSize 計算：
  imgW = lm.xPx / lm.xNorm
  imgH = lm.yPx / lm.yNorm
  
例如：
  lm.xPx = 960 (Python CSV 中的像素座標)
  lm.xNorm = 0.5 (標準化座標)
  → imgW = 960 / 0.5 = 1920 (原始視頻寬度！)
  
  displayW = 1920 (輸出視頻寬度)
  → scaleX = 1920 / 1920 = 1.0 ✓ 正確
```

---

## 詳細根因分析

### Python 端

```python
def _row_from_landmarks(frame_idx: int, time_sec: float, lms, w: int, h: int):
    # lms 來自 MediaPipe (標準化座標 [0, 1])
    # w, h 是 _iter_frames 返回的 **旋轉後** 的尺寸
    
    for i in range(LANDMARK_COUNT):
        lm = lms[i]
        x_px = float(lm.x * w)  # ← 例：lm.x=0.5, w=1920 → x_px=960
        y_px = float(lm.y * h)  # ← 例：lm.y=0.4, h=1080 → y_px=432
        
        row[f"lm{i}_x_norm"] = float(lm.x)        # 0.5
        row[f"lm{i}_y_norm"] = float(lm.y)        # 0.4
        row[f"lm{i}_x_px"] = x_px                 # 960
        row[f"lm{i}_y_px"] = y_px                 # 432
```

**CSV 輸出的資料：**
```
frame,time_sec,...,lm0_x_norm,lm0_y_norm,...,lm0_x_px,lm0_y_px,...
0,0.0,...,0.5,0.4,...,960,432,...
```

### Kotlin 端

```kotlin
private fun parseCsv(csvPath: String): Map<Int, Array<LandmarkPoint?>> {
    // ... 讀取 CSV ...
    val xNorm = cols[base + 0].trim().toFloatOrNull()  // 0.5
    val yNorm = cols[base + 1].trim().toFloatOrNull()  // 0.4
    val xPx = cols[base + 4].trim().toFloatOrNull()    // 960
    val yPx = cols[base + 5].trim().toFloatOrNull()    // 432
    
    landmarks[i] = LandmarkPoint(xPx, yPx, xNorm, yNorm, vis)
    // LandmarkPoint(xPx=960f, yPx=432f, xNorm=0.5f, yNorm=0.4f, ...)
}

private fun inferPoseImageSize(...): Pair<Float, Float>? {
    for (lm in landmarks) {
        if (lm != null && lm.xNorm > 0.05f && lm.yNorm > 0.05f) {
            val imgW = lm.xPx / lm.xNorm      // 960 / 0.5 = 1920
            val imgH = lm.yPx / lm.yNorm      // 432 / 0.4 = 1080
            return imgW to imgH               // (1920f, 1080f)
        }
    }
}

private fun drawSkeleton(..., poseW: Float, poseH: Float, displayW: Int, displayH: Int) {
    val scaleX = displayW.toFloat() / poseW  // 1920 / 1920 = 1.0
    val scaleY = displayH.toFloat() / poseH  // 1080 / 1080 = 1.0
    
    canvas.drawLine(la.xPx * scaleX, la.yPx * scaleY, ...)
    //              960 * 1.0,      432 * 1.0        (正確的像素座標！)
}
```

---

## ✅ 實際上是CORRECT的！

經過詳細分析，**坐標轉換邏輯是正確的**，原因如下：

### 座標流向驗證

```
Python:
  MediaPipe 座標 [0,1] × [0,1]
    ↓
  乘以視頻尺寸 → 像素座標 [0, W] × [0, H]
    ↓
  CSV: (xNorm=0.5, yNorm=0.4, xPx=960, yPx=432)

Kotlin:
  CSV 讀取 → (xPx=960, xNorm=0.5)
    ↓
  推算原始姿態檢測圖像尺寸
    imgW = 960 / 0.5 = 1920 = 原始視頻寬度 ✓
    ↓
  計算縮放因子
    scaleX = displayW / imgW = 1920 / 1920 = 1.0
    ↓
  應用縮放繪製
    drawX = 960 * 1.0 = 960 ✓ 正確的像素座標
```

### 🎯 結論：座標系統 **邏輯上正確**

**即使有以下情況，邏輯也是正確的：**

#### 情況 1：視頻被旋轉（90°）

```
Python 端：
  原始編碼尺寸：1920×1080
  旋轉 90°：1080×1920
  CSV 座標在旋轉後空間

Kotlin 端：
  InputFormat: 1920×1080 (原始編碼)
  Rotation metadata: 90°
  DisplayW/H: 1080×1920 (旋轉後)
  
  inferPoseImageSize 計算：
    xPx 在旋轉後空間中的像素座標
    imgW = xPx / xNorm = (旋轉後寬度) 1080
    
  scaleX = displayW / imgW = 1080 / 1080 = 1.0 ✓
```

#### 情況 2：視頻被裁切（1920×1080 → 960×540）

```
Python 端生成原始 1080 解析度座標
  xPx_orig = 960

Kotlin 端（VideoTrimmer 裁切後）：
  displayW = 960
  inferPoseImageSize：
    imgW = 960 / 0.5 = 1920 ❌ 錯誤！
    
  scaleX = 960 / 1920 = 0.5 ← 這會縮放座標
  drawX = 960 * 0.5 = 480 ← 可能不正確
```

---

## ⚠️ 真正的問題：VideoTrimmer

### 發現新問題

**VideoTrimmer 裁切視頻時，會改變解析度**

```kotlin
class VideoTrimmer {
    fun handle(call: MethodCall, result: MethodChannel.Result) {
        // ... 參數獲取 ...
        
        // 使用 Media3 Transformer 進行裁切
        val transformer = Transformer.Builder(context)
            .addListener(...)
            .build()
        
        transformer.start(composition, dstPath)
    }
}
```

**問題：** 不清楚 VideoTrimmer 是否保留了原始解析度

- ✅ 如果保留原始解析度：邏輯正確
- ❌ 如果改變了解析度：座標會錯誤

### 驗證步驟

需要檢查 VideoTrimmer 的輸出：

```bash
# 使用 ffprobe 檢查
ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 trimmed_video.mp4

# 預期輸出（若保留解析度）：
# 1920x1080

# 若解析度改變：
# 960x540  ← 座標邏輯會錯誤！
```

---

## 📊 完整流程驗證表

| 步驟 | 輸入 | 處理 | 輸出 | 狀態 |
|------|------|------|------|------|
| **Python** | 1920×1080 MP4 | MediaPipe + CSV | (xPx=960, xNorm=0.5) | ✅ |
| **VideoTrimmer** | 1920×1080 MP4 | 裁切 | ??? | ⚠️ 需驗證 |
| **SkeletonOverlay** | CSV + 視頻 | inferPoseImageSize | imgW = 960/0.5 = 1920 | ⚠️ 取決於上一步 |
| **drawSkeleton** | landmarks | scaleX = displayW/1920 | drawX = 960 * scaleX | ⚠️ 取決於上一步 |

---

## 🎯 行動計劃

### Phase 1: 立即驗證（今天）

```bash
# 1. 檢查 VideoTrimmer 輸出解析度
adb shell
dumpsys media.extractor  # 或使用 ffprobe

# 2. 檢查 SkeletonOverlayRenderer 日誌
adb logcat | grep "SkeletonOverlay"
# 應該看到：
# "骨架影像尺寸推算: XXXXX × XXXXX"

# 3. 檢查座標縮放係數
adb logcat | grep -E "scaleX|scaleY"  # 應該看到 scale factor
```

### Phase 2: 條件修復（如需要）

**如果 VideoTrimmer 改變了解析度：**

需要在 SkeletonOverlayRenderer 中添加額外的座標縮放：

```kotlin
// 可能需要的修復
private fun correctLandmarkCoordinates(
    landmarks: Array<LandmarkPoint?>,
    expectedW: Int,  // Python CSV 期望的寬度
    actualW: Int,    // VideoTrimmer 實際輸出寬度
) {
    if (expectedW != actualW) {
        val scale = actualW.toFloat() / expectedW
        for (lm in landmarks) {
            if (lm != null) {
                lm.xPx *= scale
                lm.yPx *= (actualH.toFloat() / expectedH)
            }
        }
    }
}
```

### Phase 3: 長期改進

實施元數據追蹤：
```python
# Python CSV 中添加元數據
csv_header = ["frame", "time_sec", "source_width", "source_height", ...]
```

---

## 📝 當前的不確定性

### 1. VideoTrimmer 是否保留解析度？

**需要檢查：** Compose API 和 Transformer 的行為

```kotlin
val composition = Composition.Builder(listOf(sequence)).build()
transformer.start(composition, dstPath)
```

預設情況下應該保留，但需要驗證。

### 2. Rotation metadata 是否在各層正確傳遞？

**需要檢查：** 每個編碼步驟是否保留了旋轉元數據

```kotlin
// SkeletonOverlayRenderer.kt
val rotation = android.media.MediaMetadataRetriever().use { mmr ->
    mmr.setDataSource(clipPath)
    mmr.extractMetadata(...)
}
// 如果這裡 rotation 讀不到，後續邏輯都會錯誤
```

### 3. CSS 座標的實際含義

**需要确认：** 
- ✓ Python 端 xPx, yPx 确实是像素座标
- ✓ Kotlin 端正确理解了 xNorm 和 xPx 的含义

---

## ✅ 已驗證正確的部分

| 項目 | 驗證方式 | 結果 |
|------|---------|------|
| **CSV 座標含義** | 數學推導 | ✅ 邏輯正確 |
| **inferPoseImageSize** | 代數驗證 | ✅ 推算無誤 |
| **座標縮放因子** | 單位分析 | ✅ 維度一致 |
| **旋轉轉換（BallBlob）** | 代碼檢查 | ✅ 針對球軌跡，邏輯正確 |

---

## 結論

### ✅ 座標系統邏輯上是正確的

只要滿足以下條件：
1. VideoTrimmer 保留了原始解析度
2. Rotation metadata 正確傳遞
3. CSV 座標確實是像素座標

### ⚠️ 但需要實際驗證

建議的驗證步驟：
1. 檢查 VideoTrimmer 輸出的實際解析度
2. 監視日誌中的推算尺寸
3. 測試一個實際視頻，檢查骨架位置是否正確對齐

### 🔍 下一步

查看實際運行時的日誌輸出，以確認假設是否成立。
