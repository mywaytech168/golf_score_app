# 骨架疊加 Pipeline 差異分析

> 比較對象：`golf_pose_skeleton_pipeline.py` vs Flutter `SkeletonOverlayRenderer.kt`

---

## 1. 架構總覽

| 層級 | Python | Flutter / Kotlin |
|------|--------|-----------------|
| **Pose 偵測** | MediaPipe（Python 端，CPU） | ML Kit PoseDetector（Kotlin 端，GPU/CPU） |
| **骨架座標儲存** | CSV（x_norm, y_norm, z, visibility, x_px, y_px） | CSV（相同欄位格式） |
| **渲染方式** | `cv2.VideoWriter` 直接疊圖寫入 | `MediaCodec` 解碼 → Canvas 疊圖 → `MediaCodec` 編碼 |
| **輸入** | 原始影片（全程） | 已裁切片段（clip，by `startSec` 對齊 CSV） |
| **骨架顏色** | 全部 Cyan `(0,255,255)` + 紅色 lm16 右腕 | 分區彩色：左臂綠、右臂藍、右腕紅、軀幹黃 |
| **骨骼連線數** | 18 條（SKELETON_EDGES） | 31 條（含臉部 + 完整手部） |
| **時域平滑** | 無 | **雙向 EMA（α=0.35）+ 線性插值補幀** |
| **即時預覽** | 無（純離線） | 錄影中 `SkeletonPainter` Widget 實時顯示 |

---

## 2. 影片寫出流程

### Python
```
原始影片
  └─ cv2.VideoCapture → _rotate_frame (cv2.rotate)
       └─ MediaPipe Pose (縮圖 max_long_side=720，偵測用)
           └─ _draw_skeleton → cv2.line / cv2.circle（全解析度）
               └─ cv2.VideoWriter (avc1 / fallback mp4v)
```

### Flutter / Kotlin
```
裁切後片段 (clip)
  └─ MediaExtractor → MediaCodec 解碼 → YUV Image
       └─ yuvToNv12WithRotation
           │  ① YUV420 → NV12（含旋轉座標映射 + nearest-neighbor downscale to encW×encH）
           └─ Canvas.drawSkeleton (overlay Bitmap，分區彩色)
               └─ compositeSkeleton (NV12 composite)
                   └─ MediaCodec 編碼 → MediaMuxer → mp4
```

---

## 3. 解析度處理

| 步驟 | Python | Flutter / Kotlin |
|------|--------|-----------------|
| **Pose 偵測解析度** | `max_long_side=720`（縮圖偵測，輸出還原至原始） | `maxWidth=720`（傳給 Kotlin analyzePoseVideo） |
| **輸出影片解析度** | 旋轉後原始解析度（不縮放） | `displayW × displayH`（旋轉校正後）**對齊 16px 邊界** |
| **旋轉校正方式** | `cv2.rotate()` 像素重新排列 | `yuvToNv12WithRotation` 座標映射，零 RGB 中間層 |
| **16px 對齊** | 無（原始尺寸直出） | `encW = (displayW+15) and -16` |

---

## 4. 編碼參數（檔案大小主因）

### Python（cv2.VideoWriter）

```python
cv2.VideoWriter(str(out_video_path), cv2.VideoWriter_fourcc(*"avc1"), fps, (width, height))
# fallback:
cv2.VideoWriter(str(out_video_path), cv2.VideoWriter_fourcc(*"mp4v"), fps, (width, height))
```

| 參數 | 值 |
|------|----|
| **Codec** | `avc1`（H.264）/ fallback `mp4v`（MPEG-4 Part 2） |
| **Bitrate 控制** | **無** — OpenCV Python 層不暴露 bitrate API |
| **預設行為** | Windows 系統 H.264 codec，使用預設 CQP/VBR，常見 30–100+ Mbps |
| **I-frame 間隔** | 系統決定（Windows 常設為全 I-frame 或極短 GOP） |
| **Color format** | BGR（OpenCV 內部，encode 前轉換） |

### Flutter / Kotlin（MediaCodec）

```kotlin
val bitRateCoeff = when {
    displayW >= 1440 -> 1.0   // 2K+
    displayW >= 1080 -> 0.8   // 1080p
    else              -> 0.6   // 720p 以下
}
val bitRate = (displayW.toLong() * displayH * fps * bitRateCoeff)
    .toLong().coerceIn(8_000_000L, 25_000_000L).toInt()

MediaFormat.createVideoFormat("video/avc", encW, encH).apply {
    setInteger(KEY_COLOR_FORMAT, COLOR_FormatYUV420SemiPlanar) // NV12
    setInteger(KEY_BIT_RATE, bitRate)
    setInteger(KEY_FRAME_RATE, fps.roundToInt())
    setInteger(KEY_I_FRAME_INTERVAL, 1)   // 每 1 秒一個 I-frame
}
```

| 參數 | 值 |
|------|----|
| **Codec** | `video/avc`（H.264） |
| **Bitrate** | 明確設定，最高 **25 Mbps** |
| **Bitrate 計算（1080p@30fps）** | `1920×1080×30×0.8 = 49.8M → clamped → 25 Mbps` |
| **Bitrate 計算（720p@30fps）** | `1280×720×30×0.6 = 16.6M → 16.6 Mbps` |
| **I-frame 間隔** | **1 秒**（GOP=30f，高壓縮效率） |
| **Color format** | NV12（YUV420 semi-planar）— H.264 原生格式 |

---

## 5. 檔案大小明顯縮小的原因分析

```
Flutter 影片較小 = 以下 4 個因素疊加
```

### ① Bitrate 硬上限（最主要）

| 情境 | Python 典型輸出 | Kotlin 輸出 |
|------|----------------|-------------|
| 1080p @ 30fps | 40–100 Mbps（Windows avc1 預設） | **≤ 25 Mbps** |
| 720p @ 30fps | 20–60 Mbps | **≤ 16.6 Mbps** |
| 1 分鐘影片 | 300–750 MB | **≤ 188 MB** |

Python `cv2.VideoWriter` 在 Windows 上使用系統 H.264 codec，預設 CQP 偏低（畫質優先），對高動態高爾夫揮桿影片會產生極高 bitrate。

### ② I-frame 間隔不同

| | Python | Kotlin |
|-|--------|--------|
| GOP 長度 | 系統預設（Windows 常為全 I-frame） | 30 幀（1 秒） |
| I-frame 比例 | 高 → 檔案大 | P/B frame 主導 → 檔案小 |

全 I-frame 模式（`mp4v` 常見）等同無幀間壓縮，檔案大 2–10 倍。

### ③ Color pipeline 效率

| | Python | Kotlin |
|-|--------|--------|
| 解碼路徑 | cv2 讀取 → BGR pixel | MediaCodec → YUV Image |
| 壓縮前格式 | BGR → H.264 內部轉換 | NV12（H.264 原生）直接喂入 |
| 量化損失 | BGR 多一次轉換，熵略高 | 零轉換，壓縮效率略優 |

### ④ fallback mp4v（無此問題則不計）

若 `avc1` 在 Windows 不可用，Python 退回 `mp4v`（MPEG-4 Part 2），壓縮效率遠低於 H.264，同解析度檔案可大 3–5 倍。

---

## 6. 骨架品質差異

| 項目 | Python | Flutter / Kotlin |
|------|--------|-----------------|
| **連線數** | 18 條（只有身體，無臉） | 31 條（臉部 + 手指環 + 完整身體） |
| **顏色分區** | 無分區（全 Cyan） | 左/右/軀幹分色 |
| **時域平滑** | 無（每幀獨立偵測） | 雙向 EMA 平滑（前向 + 後向，零延遲） |
| **缺幀補值** | 輸出空骨架（`NaN` 不畫） | **線性插值**補齊相鄰幀 |
| **min_visibility** | 0.2 | 0.3（略嚴格） |
| **右腕標記** | lm16 紅點（radius=6） | 右腕（lm16）紅色線 + 紅色點（radius × coeff） |

---

## 7. 骨架座標空間

| 步驟 | Python | Flutter / Kotlin |
|------|--------|-----------------|
| **偵測空間** | `max_long_side=720` 縮圖 | `maxWidth=720` 縮圖 |
| **CSV 儲存** | `x_px, y_px` = 全解析度像素（縮圖座標 × scale 還原） | `x_px, y_px` = 720-wide 縮圖座標 |
| **渲染還原** | 直接畫（已是全解析度） | `scaleX = displayW / poseW`，`scaleY = displayH / poseH` |
| **推算影像大小** | 已知（傳入 w, h） | `inferPoseImageSize()` 從 CSV `xPx/xNorm` 反推 |

> ⚠️ Flutter CSV 的 `x_px/y_px` 是 **720 縮圖空間**，渲染時需乘 scale，Python CSV 則是**全解析度**。

---

## 8. 改善建議（針對 Flutter 影片縮小問題）

若需要讓 Flutter 輸出影片接近 Python 畫質：

```kotlin
// SkeletonOverlayRenderer.kt — 調整 bitrate 上限
val bitRate = (displayW.toLong() * displayH * fps * bitRateCoeff)
    .toLong()
    .coerceIn(8_000_000L, 40_000_000L)  // ← 從 25M 提高到 40M
    .toInt()
```

若需要縮小 Python 輸出檔案以接近 Flutter：

```python
# golf_pose_skeleton_pipeline.py — 可改用 ffmpeg 後處理
# 或改用以下方式控制品質（OpenCV 不直接支援 bitrate，但可透過 fourcc 參數 workaround）
# 最佳方案：寫完後再用 subprocess 呼叫 ffmpeg 轉碼
subprocess.run([
    "ffmpeg", "-i", str(out_video_path),
    "-c:v", "libx264", "-b:v", "16M",
    "-y", str(out_video_path_final)
])
```
