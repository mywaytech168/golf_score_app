# FPS 調試日誌 (Video Frame Rate Detection)

## 概述
所有解析影片的地方都已新增 **fps 檢測日誌**，幫助診斷骨架檢測異常問題（15fps vs 30fps）。

---

## 📍 日誌記錄點

### 1️⃣ **VideoTrimmer.kt** - 裁切短影片時
```kotlin
Log.d(TAG, "[VideoTrimmer] 🎬 fps 檢測: metadata=$fpsFromMetadata → 使用=$srcFps")
```
**位置**：當裁切影片時，在複製 video track 到 muxer 的地方。

**作用**：顯示源影片的 fps 元數據，以及最終保存到新 MP4 的 fps。

**預期輸出**：
```
[VideoTrimmer] 🎬 fps 檢測: metadata=30 → 使用=30
```

---

### 2️⃣ **BallBlobExtractor.kt** - 球 Blob 提取時
```kotlin
Log.d(TAG, "[BallBlobExtractor] 🎬 fps 檢測: metadata=${fpsFromMetadata} → 使用=$fps")
Log.d(TAG, "[BallBlobExtractor] 影片: coded=${videoW}x${videoH} display=${displayW}x${displayH} fps=$fps mime=$videoMime rotation=$rotation°")
```
**位置**：開始解碼球軌跡時。

**作用**：記錄是否能從 MP4 元數據讀取 fps，如果不能則使用預設的 30fps。

**預期輸出**：
```
[BallBlobExtractor] 🎬 fps 檢測: metadata=30 → 使用=30.0
[BallBlobExtractor] 影片: coded=1080x1920 display=1920x1080 fps=30.0 mime=video/avc rotation=90°
```

或（無法讀取時）：
```
[BallBlobExtractor] 🎬 fps 檢測: metadata=null → 使用=30.0
```

---

### 3️⃣ **TrajectoryOverlayRenderer.kt** - 軌跡疊加時
```kotlin
Log.d(TAG, "[TrajectoryOverlay] 🎬 fps 檢測: metadata=${fpsFromMetadata} → 使用=$fps")
```
**位置**：開始渲染球軌跡疊加影片時。

**作用**：確保軌跡渲染器使用正確的 fps。

**預期輸出**：
```
[TrajectoryOverlay] 🎬 fps 檢測: metadata=30 → 使用=30.0
```

---

### 4️⃣ **SkeletonOverlayRenderer.kt** - 骨架疊加時
```kotlin
Log.d(TAG, "[SkeletonOverlay] 🎬 fps 檢測: metadata=${fpsFromMetadata} → 使用=$fps")
```
**位置**：開始渲染骨架疊加影片時。

**作用**：確保骨架渲染器使用正確的 fps。

**預期輸出**：
```
[SkeletonOverlay] 🎬 fps 檢測: metadata=30 → 使用=30.0
```

---

### 5️⃣ **MainActivity.kt (PoseAnalyzer)** - 骨架分析開始時
```kotlin
Log.i(logTag, "[PoseAnalyzer] 🎬 開始分析: targetFps=$targetFps maxWidth=$maxWidth videoPath=$videoPath")
Log.i(logTag, "[PoseAnalyzer] coded=${codedW}x${codedH} display=${displayW}x${displayH} rotation=$rotation duration=${durationMs}ms targetFps=$targetFps expected≈$expectedFrames")
```
**位置**：analyzeVideoNatively 函數開始處。

**作用**：記錄骨架分析的目標 fps 以及讀取到的視頻信息。

**預期輸出**：
```
[PoseAnalyzer] 🎬 開始分析: targetFps=30 maxWidth=720 videoPath=/path/to/video.mp4
[PoseAnalyzer] coded=1080x1920 display=1920x1080 rotation=90 duration=3000ms targetFps=30 expected≈90
```

---

## 🔍 調試流程

### 情況A：長影片 → 短影片 → 分析（應該 30fps）

```
1. 匯入長影片（30fps）
   → [VideoTrimmer] 🎬 fps 檢測: metadata=30 → 使用=30
   
2. 點擊「偵測擊球」
   → [BallBlobExtractor] 🎬 fps 檢測: metadata=30 → 使用=30.0
   
3. 系統自動裁切短影片
   → [VideoTrimmer] 🎬 fps 檢測: metadata=30 → 使用=30
   
4. 分析短影片
   → [PoseAnalyzer] 🎬 開始分析: targetFps=30 maxWidth=720
   → [SkeletonOverlay] 🎬 fps 檢測: metadata=30 → 使用=30.0 ✅
```

### 情況B：短影片直接匯入 → 分析（應該 30fps）

```
1. 匯入短影片（30fps，但可能遺失 fps 元數據）
   
2. 點擊「分析」
   → [PoseAnalyzer] 🎬 開始分析: targetFps=30 maxWidth=720
   → [SkeletonOverlay] 🎬 fps 檢測: metadata=null → 使用=30.0 ✅（回退到 30fps）
```

### ❌ 異常情況（15fps）

如果日誌顯示：
```
[SkeletonOverlay] 🎬 fps 檢測: metadata=15 → 使用=15.0 ❌
```

表示：
- 短影片的 MP4 元數據中 fps 被設置為 15（錯誤）
- 需要檢查 VideoTrimmer 或裁切前的源影片

---

## 📊 預期日誌摘要

### ✅ 正常流程（30fps）

```
[VideoTrimmer] 🎬 fps 檢測: metadata=30 → 使用=30
[BallBlobExtractor] 🎬 fps 檢測: metadata=30 → 使用=30.0
[PoseAnalyzer] 🎬 開始分析: targetFps=30 maxWidth=720
[SkeletonOverlay] 🎬 fps 檢測: metadata=30 → 使用=30.0
[TrajectoryOverlay] 🎬 fps 檢測: metadata=30 → 使用=30.0
```

### ❌ 異常流程（15fps）

```
[VideoTrimmer] 🎬 fps 檢測: metadata=15 → 使用=15 ❌
[BallBlobExtractor] 🎬 fps 檢測: metadata=15 → 使用=15.0 ❌
[PoseAnalyzer] 🎬 開始分析: targetFps=30 maxWidth=720 (但影片是 15fps)
```

---

## 🛠️ 調試步驟

1. **打開 Android Studio / Logcat**
2. **匯入影片或執行分析**
3. **過濾日誌**：搜尋 `🎬` 或 `fps` 關鍵字
4. **檢查每一步的 fps 值**：
   - VideoTrimmer：fps 是否正確保留？
   - BallBlobExtractor：fps 是否成功讀取或正確回退？
   - PoseAnalyzer：targetFps 是否設置為 30？
   - SkeletonOverlay：fps 是否為 30？
5. **如果發現異常**：找到回退到 15 的那一步，檢查上游為什麼沒有正確保留 fps 元數據

---

## 📝 改動清單

| 檔案 | 新增日誌 |
|------|---------|
| VideoTrimmer.kt | fps 檢測：metadata vs 使用 |
| BallBlobExtractor.kt | fps 檢測：metadata vs 使用 |
| TrajectoryOverlayRenderer.kt | fps 檢測：metadata vs 使用 |
| SkeletonOverlayRenderer.kt | fps 檢測：metadata vs 使用 |
| MainActivity.kt | targetFps 開始分析 |

