# Python vs Kotlin 視頻處理流程對比分析

## 📋 整體流程架構

### Python 端 (golf_pose_skeleton_pipeline.py)

```
輸入視頻 (原始)
    ↓
_probe_rotation() ← 使用 ffprobe 探測旋轉元數據
    ↓
_rotate_frame() ← 使用 cv2.rotate 旋轉
    ↓
_iter_frames() ← 逐幀迭代，返回旋轉後的幀
    ↓
extract_pose_to_csv_and_video()
    ├─ MediaPipe 姿態檢測 (max_long_side=720 縮小處理)
    ├─ 座標轉換到原始解析度 (x_px, y_px)
    ├─ 輸出 CSV (原始解析度座標)
    └─ 輸出骨架視頻 (單次編碼，cv2.VideoWriter)
```

### Kotlin 端 (Android)

```
輸入視頻 (原始)
    ↓
VideoTrimmer.kt ← 裁切 + 編碼 (第1次編碼)
    ↓
骨架版本 MP4 + 旋轉元數據
    ↓
SkeletonOverlayRenderer.kt
    ├─ 探測旋轉
    ├─ 讀取 CSV 座標
    ├─ 座標轉換 (display-space)
    ├─ 解碼 + 繪製 + 編碼 (第2次編碼)
    └─ 輸出骨架 MP4
    ↓
TrajectoryOverlayRenderer.kt
    ├─ 解碼 + 繪製軌跡 + 編碼 (第3次編碼)
    └─ 輸出最終 MP4
```

---

## 🔍 關鍵差異分析

### 差異 1: 旋轉處理

#### Python 端
```python
def _rotate_frame(frame, rotation: int):
    if rotation == -90:
        return cv2.rotate(frame, cv2.ROTATE_90_CLOCKWISE)
    if rotation == 90:
        return cv2.rotate(frame, cv2.ROTATE_90_COUNTERCLOCKWISE)
    if abs(rotation) == 180:
        return cv2.rotate(frame, cv2.ROTATE_180)
    return frame
```

**特點：**
- ✅ 在讀取時立即旋轉物理像素
- ✅ CSV 中的座標已是旋轉後的空間座標
- ✅ 輸出視頻無旋轉元數據（已物理旋轉）

#### Kotlin 端 (SkeletonOverlayRenderer.kt)
```kotlin
val rotation = android.media.MediaMetadataRetriever().use { mmr ->
    mmr.setDataSource(clipPath)
    mmr.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)
        ?.toIntOrNull() ?: 0
}

val displayW = if (rotation == 90 || rotation == 270) videoH else videoW
val displayH = if (rotation == 90 || rotation == 270) videoW else videoH

// ... 稍後進行座標轉換
private fun codedToDisplay(cx: Int, cy: Int, w: Int, h: Int, rotation: Int): Pair<Int, Int> = when (rotation) {
    90  -> Pair(h - 1 - cy, cx)
    270 -> Pair(cy, w - 1 - cx)
    180 -> Pair(w - 1 - cx, h - 1 - cy)
    else -> Pair(cx, cy)
}
```

**特點：**
- ⚠️ 保留旋轉元數據，在邏輯層進行座標變換
- ⚠️ CSV 座標可能不匹配（取決於 Python 端如何處理）

#### ⚠️ 潛在問題
```
如果 Python CSV 是在 旋轉後 的空間座標
但 Kotlin 端再進行一次旋轉轉換
則座標會被轉換兩次 → 錯誤！
```

---

### 差異 2: 坐標系統

#### Python 端座標

```python
def _row_from_landmarks(frame_idx: int, time_sec: float, lms, w: int, h: int):
    # lms 是 MediaPipe 輸出
    # w, h 是 _iter_frames 返回的 **旋轉後** 的尺寸
    
    for i in range(LANDMARK_COUNT):
        lm = lms[i]
        x_px = float(lm.x * w)  # ← 乘以旋轉後寬度
        y_px = float(lm.y * h)  # ← 乘以旋轉後高度
        row[f"lm{i}_x_px"] = x_px
        row[f"lm{i}_y_px"] = y_px
```

**座標空間：**
- ✅ x_px, y_px 是在 **旋轉後視頻** 的像素座標
- ✅ 範圍：[0, rotatedWidth] × [0, rotatedHeight]

#### Kotlin 端座標處理

在 SkeletonOverlayRenderer.kt 中：

```kotlin
// 從 CSV 讀取座標
val landmarks = arrayOfNulls<LandmarkPoint>(33)
for (i in 0 until 33) {
    val base = 2 + i * 6
    val xPx = cols[base + 4].trim().toFloatOrNull()  // ← 讀取 x_px
    val yPx = cols[base + 5].trim().toFloatOrNull()  // ← 讀取 y_px
    landmarks[i] = LandmarkPoint(xPx, yPx, xNorm, yNorm, vis)
}

// 座標轉換
val blobs: List<Map<String, Any>> = if (rotation == 0) codedBlobs else {
    codedBlobs.map { b ->
        val (dx, dy) = codedToDisplay(
            b["cx"] as Int, b["cy"] as Int, videoW, videoH, rotation
        )
        // ...
    }
}
```

**問題：** ❌ 這是針對 **解碼後** 的像素座標進行的轉換
- CSV 座標已是旋轉後的空間座標
- 不需要再進行旋轉轉換！

---

### 差異 3: 多層編碼導致的質量損失

#### Python 端
```
原始視頻 8.4MB
    ↓ (單次編碼，cv2.VideoWriter with mp4v)
輸出視頻 3.2MB (質量損失 ~62%)
```

**原因分析：**
- 使用 OpenCV 的 VideoWriter + mp4v codec
- 預設編碼參數（較低比特率）

#### Kotlin 端
```
原始視頻 8.4MB
    ↓ [編碼 1] VideoTrimmer (6 Mbps)
4.5MB (-46%)
    ↓ [編碼 2] SkeletonOverlay (6 Mbps) ← 舊方案
2.4MB (-46%)
    ↓ [編碼 3] TrajectoryOverlay (6 Mbps)
1.8MB (-27%)
最終: 1.8MB ❌ 嚴重損失

改善後 (新方案 25 Mbps):
    ↓ [編碼 2] SkeletonOverlay (25 Mbps)
4.0MB (-23%)
    ↓ [編碼 3] TrajectoryOverlay (25 Mbps)
3.2MB (-19%)
最終: 3.2MB ✅ 改善
```

**差異分析：**
- Python 端：1 次編碼
- Kotlin 端：3 次編碼
- Kotlin 端質量損失更嚴重（多層堆疊）

---

## ⚠️ 發現的具體問題

### 問題 1: 旋轉座標轉換邏輯錯誤

**位置：** SkeletonOverlayRenderer.kt (BallBlobExtractor.kt)

**代碼：**
```kotlin
// 在 BallBlobExtractor.kt 中
val blobs: List<Map<String, Any>> = if (rotation == 0) codedBlobs else {
    codedBlobs.map { b ->
        val (dx, dy) = codedToDisplay(
            b["cx"] as Int, b["cy"] as Int, videoW, videoH, rotation
        )
        // ...
    }
}
```

**問題：**
- ❌ Python CSV 座標已是旋轉後的空間座標
- ❌ 在 Kotlin 端再進行 codedToDisplay 轉換是錯誤的（轉換兩次）
- ❌ 這會導致座標完全錯亂

**應該改為：**
```kotlin
// Python CSV 已經是 display-space，直接使用
val blobs: List<Map<String, Any>> = codedBlobs.map { b ->
    mapOf(
        "cx" to b["cx"]!!,
        "cy" to b["cy"]!!,
        // ...
    )
}
```

### 問題 2: CSV 座標空間不匹配

**Python 端生成的 CSV：**
```
座標空間：旋轉後的視頻空間
示例：如果視頻被旋轉 90° (from 1920x1080 to 1080x1920)
     則 x_px 範圍是 [0, 1080]
     y_px 範圍是 [0, 1920]
```

**Kotlin 端期望的座標：**
```
SkeletonOverlayRenderer 中：
    val poseW, poseH = inferPoseImageSize()  // 推算為 720x1280?
    val scale = clipWidth / poseImgWidth
    
問題：Python 給出的不是 720 空間的座標，而是原始解析度空間的！
```

### 問題 3: 幀率精度一致性

**Python 端：**
```python
fps = float(cap.get(cv2.CAP_PROP_FPS))  # 浮點 FPS
writer = cv2.VideoWriter(..., fps, ...)  # 直接使用浮點
```

**Kotlin 端（舊方案）：**
```kotlin
val fps = inputFormat.getInteger(MediaFormat.KEY_FRAME_RATE).toFloat()
setInteger(MediaFormat.KEY_FRAME_RATE, fps.roundToInt())  // ❌ 四捨五入
```

**Kotlin 端（新方案）：**
```kotlin
// ✅ 已改為使用精確時間戳
val ptsUs = (frameCount.toDouble() * 1_000_000.0 / fps).toLong()
```

---

## ✅ 驗證的正確部分

### ✓ 骨架邊定義一致性

Python 端：
```python
SKELETON_EDGES = [
    (11, 12), (11, 13), (13, 15), (12, 14), (14, 16),  # 上半身
    (11, 23), (12, 24), (23, 24),                        # 軀幹
    (23, 25), (25, 27), (24, 26), (26, 28),              # 腿
    (27, 29), (29, 31), (27, 31), (28, 30), (30, 32),    # 腳
]
```

Kotlin 端 (SkeletonOverlayRenderer.kt)：
```kotlin
val CONNECTIONS = listOf(
    0 to 1, 1 to 2, 2 to 3, 3 to 7,      // 臉部
    // ... 以及完整的骨架定義
)
```

**狀態：** ⚠️ 部分不同（Kotlin 包含臉部，Python 沒有），但都是有效的

### ✓ Landmark 數量一致

Python：`LANDMARK_COUNT = 33`  
Kotlin：使用 33 個 landmarks

**狀態：** ✅ 一致

### ✓ 可見度閾值

Python：`MIN_VISIBILITY = 0.2`  
Kotlin：`CIRC_MIN = 0.30` (不同，但都用於過濾)

**狀態：** ⚠️ 不同但都合理

---

## 🔧 建議的修復

### 修復 1: 移除雙重旋轉轉換（最優先）

**位置：** SkeletonOverlayRenderer.kt 中的坐標處理

```kotlin
// 修改前：
val blobs: List<Map<String, Any>> = if (rotation == 0) codedBlobs else {
    codedBlobs.map { b ->
        val (dx, dy) = codedToDisplay(...)  // ❌ 錯誤：轉換兩次
        // ...
    }
}

// 修改後：
// Python CSV 已是 display-space，直接使用
val blobs: List<Map<String, Any>> = codedBlobs
```

### 修復 2: 統一比特率配置

**Python 端優化：**
```python
# golf_pose_skeleton_pipeline.py 中添加
CV2_FOURCC = cv2.VideoWriter_fourcc(*"mp4v")
CV2_BITRATE = 25_000_000  # 25 Mbps
# 需要通過 FFmpeg 包裝以支持自定義比特率
```

**或者使用 FFmpeg 直接編碼：**
```python
import subprocess

subprocess.run([
    "ffmpeg", "-i", input_video, 
    "-c:v", "libx264",
    "-b:v", "25M",
    output_video
])
```

### 修復 3: 座標空間文檔化

在 CSV 標頭中添加元數據：
```python
# 在 _csv_header() 中
header = [
    "frame", "time_sec",
    "# Coordinate space: rotated video dimensions",
    "# Rotation: " + str(rotation) + "°",
]
```

---

## 📊 整合驗證矩陣

| 項目 | Python | Kotlin | 狀態 | 優先級 |
|------|--------|--------|------|--------|
| **旋轉處理** | 物理旋轉 | 邏輯轉換 | ⚠️ 不一致 | 🔴 高 |
| **座標系** | 旋轉後空間 | 未正確理解 | ❌ 錯誤 | 🔴 高 |
| **多層編碼** | 1 層 | 3 層 | ⚠️ 質量損失 | 🟡 中 |
| **比特率** | ~6 Mbps | 6→25 Mbps | ✅ 已改善 | 🟢 低 |
| **幀率精度** | 浮點 | 整數→浮點 | ✅ 已改善 | 🟢 低 |
| **Landmarks** | 33 | 33 | ✅ 一致 | 🟢 低 |

---

## 🎯 行動計劃

### Phase 1: 緊急修復（立即）
1. [ ] 驗證 BallBlobExtractor 中的旋轉轉換是否實際執行
2. [ ] 如果是，移除 codedToDisplay 調用
3. [ ] 測試座標是否正確對應

### Phase 2: 驗證測試（今日）
1. [ ] 錄製一個 90° 旋轉的視頻進行測試
2. [ ] 檢查最終輸出中骨架位置是否正確
3. [ ] 對比 Python 輸出和 Kotlin 輸出

### Phase 3: 長期優化（本週）
1. [ ] 統一 Python 端的比特率配置
2. [ ] 添加座標空間元數據到 CSV
3. [ ] 實施單次編碼流程

---

## 📝 技術備註

### 為什麼 Python 座標需要乘以 w, h?

```python
def _row_from_landmarks(frame_idx: int, time_sec: float, lms, w: int, h: int):
    for i in range(LANDMARK_COUNT):
        lm = lms[i]
        # lm.x, lm.y 是 MediaPipe 返回的 **標準化座標** [0, 1]
        x_px = float(lm.x * w)  # ← 轉換到像素座標
        y_px = float(lm.y * h)
```

MediaPipe 返回的是 [0, 1] 之間的標準化座標，需要乘以圖像尺寸才能得到像素座標。

### 為什麼 Kotlin 端需要進行座標轉換?

```kotlin
private fun codedToDisplay(cx: Int, cy: Int, w: Int, h: Int, rotation: Int): Pair<Int, Int>
```

這個函數用於將 **原始編碼空間** (coded-space) 的座標轉換到 **顯示空間** (display-space)。

但是 Python CSV 已經是顯示空間了，所以不需要再轉換！

---

## ❓ 待驗證的問題

1. **BallBlobExtractor 是否真的執行了旋轉轉換？**
   - 需要檢查 blobs 輸出的座標是否與 CSV 座標對應

2. **inferPoseImageSize() 返回的尺寸是什麼？**
   - Python 輸入是 max_long_side=720 用於檢測
   - 但輸出座標是原始解析度
   - Kotlin 端的 poseW/poseH 是否正確推算？

3. **VideoTrimmer 是否改變了解析度？**
   - 如果裁切改變了尺寸，後續的 SkeletonOverlay 座標會錯誤

---

## 結論

### ✅ 做對的事
- 比特率改善（0.25 → 0.8-1.0 bpp）
- 幀率精度改善
- EOS 處理改善

### ❌ 需要修正的事
- **座標轉換邏輯** - 可能存在雙重旋轉
- **座標空間文檔** - 需要明確化
- **多層編碼** - 仍需進一步優化

### ⚠️ 需要驗證的事
- 實際運行時座標是否正確
- 旋轉視頻的輸出是否對齐
