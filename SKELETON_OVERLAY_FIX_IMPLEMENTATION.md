# SkeletonOverlay 編碼器修復 - 實施完成總結

## 修復日期
2026-05-11

## 修復對象
[SkeletonOverlayRenderer.kt](android/app/src/main/kotlin/com/example/golf_score_app/SkeletonOverlayRenderer.kt)

---

## 四大核心修復

### 1️⃣ 添加編碼幀計數變量 ✅
**位置**：`render()` 方法，第 147-153 行

```kotlin
var encodedFrames = 0      // 記錄實際寫入 Muxer 的幀數
var drainedOutputs = 0     // 記錄 drainEncoder 遇到的輸出次數
var samplesWritten = 0     // 記錄 writeSampleData 成功的次數
```

**目的**：區分「渲染幀數」vs「編碼幀數」，精確診斷問題

---

### 2️⃣ 修正 Image.close() 時序問題 ✅
**位置**：`render()` 方法，第 208-212 行

```kotlin
// 之前（錯誤）：
bitmapFillYuv(encImg, bmp, videoW, videoH)
encImg.close()  // ❌ 過早 close，導致緩衝區失效
encoder.queueInputBuffer(encInIdx, 0, 0, pts, 0)

// 現在（正確）：
bitmapFillYuv(encImg, bmp, videoW, videoH)
encoder.queueInputBuffer(encInIdx, 0, 0, pts, 0)
encImg.close()  // ✅ 在 queueInputBuffer 之後 close
```

**目的**：確保 YUV 數據在進入編碼器時仍然有效

---

### 3️⃣ 加強 EOS 處理與驗證邏輯 ✅
**位置**：`render()` 方法，第 239-268 行

```kotlin
Log.d(TAG, "Signaling EOS to encoder")
val eosIdx = encoder.dequeueInputBuffer(100_000L)
if (eosIdx >= 0) {
    encoder.queueInputBuffer(eosIdx, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
    Log.d(TAG, "EOS queued at index $eosIdx")
} else {
    Log.w(TAG, "Failed to get input buffer for EOS: $eosIdx")
}

// 驗證編碼幀數
if (encodedFrames <= 0) {
    Log.e(TAG, "ERROR: encodedFrames=$encodedFrames ...")
    success = false
} else {
    Log.d(TAG, "SUCCESS: renderedFrames=$frameCount, encodedFrames=$encodedFrames ...")
}
```

**目的**：立即檢測編碼失敗，不要進入後續的 BallBlobExtractor

---

### 4️⃣ 加強 drainEncoder 日誌 ✅
**位置**：`drainEncoder()` 方法，第 475-506 行

新增日誌：
- `TRY_AGAIN_LATER` 事件
- `OUTPUT_FORMAT_CHANGED` 事件
- 每個 `idx >= 0` 的輸出幀詳情（size, flags, pts）
- `writeSampleData` 成功/失敗原因
- EOS 檢測

```kotlin
Log.d(TAG, "drainEncoder: idx=$idx, size=${info.size}, flags=${info.flags}, pts=${info.presentationTimeUs}")
if (buf != null && info.size > 0 && isMuxed()) {
    muxer.writeSampleData(getTrack(), buf, info)
    Log.d(TAG, "writeSampleData: size=${info.size}")  // ✅ 成功日誌
} else {
    Log.w(TAG, "writeSampleData skip: buf=$buf, size=${info.size}, isMuxed=${isMuxed()}")  // ✅ 失敗原因
}
```

---

## 預期行為改變

### 之前（有問題）
```
D/SkeletonOverlay: 骨架渲染完成: 151 幀 → hit_1_skeleton.mp4
I/MPEG4Writer: Received total/0-length (0/0) buffers and encoded 0 frames. - Video
E/MPEG4Writer: Stop() called but track is not started or stopped
```

### 現在（修復後）

#### 成功情況：
```
D/SkeletonOverlay: 片段: 1280x720 fps=30.0  scale=1.777x1.125
D/SkeletonOverlay: CSV 解析完成：151 幀
D/SkeletonOverlay: Signaling EOS to encoder
D/SkeletonOverlay: EOS queued at index X
D/SkeletonOverlay: Draining encoder with eos=true
D/SkeletonOverlay: drainEncoder: OUTPUT_FORMAT_CHANGED
D/SkeletonOverlay: drainEncoder: idx=0, size=51200, flags=0, pts=0
D/SkeletonOverlay: writeSampleData: size=51200
D/SkeletonOverlay: drainEncoder: idx=1, size=4800, flags=0, pts=33333
D/SkeletonOverlay: writeSampleData: size=4800
...
D/SkeletonOverlay: drainEncoder: EOS flag detected, breaking
D/SkeletonOverlay: Encoder drained, encodedFrames=151
D/SkeletonOverlay: SUCCESS: renderedFrames=151, encodedFrames=151, drainedOutputs=151, samplesWritten=151
D/SkeletonOverlay: 骨架渲染完成: 151 幀 → hit_1_skeleton.mp4
```

#### 失敗情況（新增檢測）：
```
D/SkeletonOverlay: Signaling EOS to encoder
D/SkeletonOverlay: EOS queued at index X
D/SkeletonOverlay: Draining encoder with eos=true
D/SkeletonOverlay: drainEncoder: TRY_AGAIN_LATER, eos=true
D/SkeletonOverlay: drainEncoder: EOS flag detected, breaking
D/SkeletonOverlay: Encoder drained, encodedFrames=0
E/SkeletonOverlay: ERROR: encodedFrames=0, drainedOutputs=0, samplesWritten=0
E/SkeletonOverlay: Skeleton MP4 編碼失敗: renderedFrames=151, encodedFrames=0
```

---

## 修復驗證清單

測試時應查看日誌確認：

- [ ] `OUTPUT_FORMAT_CHANGED` 被觸發 ✅ 表示編碼器正常啟動
- [ ] `writeSampleData: size=XXXX` 出現多次 ✅ 表示幀被寫入
- [ ] `encodedFrames` 計數 ≥ 預期幀數 ✅ 表示編碼成功
- [ ] 最後顯示 `SUCCESS` 而不是 `ERROR` ✅ 表示完整編碼

如果看到：
- [ ] `drainEncoder: TRY_AGAIN_LATER` 重複
- [ ] `encodedFrames=0`
- [ ] `ERROR: Skeleton MP4 編碼失敗`

→ 表示編碼器根本沒有輸出，需要調查其他根本原因

---

## 後續影響

### BallBlobExtractor 保護
現在當 `SkeletonOverlay.render()` 返回 `false` 時，BallBlobExtractor 將不會嘗試讀取無效的 MP4：

```kotlin
if (!skeletonOverlay.render(...)) {
    Log.e(TAG, "Skeleton overlay failed, skipping this hit")
    return@launch  // 不進入 BallBlobExtractor
}
```

### 錯誤鏈防斷
之前的錯誤鏈：
```
SkeletonOverlay 0 幀 → BallBlobExtractor 找不到 track → MediaMetadataRetriever 失敗 → 播放失敗
```

現在：
```
SkeletonOverlay 0 幀 → 立即返回 false → 整個 hit 處理終止
```

---

## 文件修改統計

| 項目 | 修改數 |
|------|-------|
| 新增計數變量 | 3 個 |
| 修正時序問題 | 1 個 |
| 日誌陳述句 | 15+ |
| 驗證邏輯 | 1 個 if-else 塊 |
| drainEncoder 改進 | 完全重寫 |

**總計**：5 個重要修復點

---

## 下一步建議

### 立即測試
1. 運行應用，進行一次揮桿錄製
2. 查看 logcat 日誌，確認新增的日誌出現
3. 驗證 `encodedFrames` 計數是否 > 0

### 如果仍為 0 幀
檢查：
1. YUV 轉換是否有問題（bitmapFillYuv）
2. 編碼器 format 是否正確
3. 編碼器是否收到有效的輸入幀

### 長期改進
1. 考慮使用 MediaCodec.createInputSurface() 進行 Surface-based 編碼
2. 添加編碼器性能監控
3. 實施編碼失敗的自動重試機制

---

## 參考文件
- 分析文檔：[SKELETON_OVERLAY_ENCODER_FIX_ANALYSIS.md](SKELETON_OVERLAY_ENCODER_FIX_ANALYSIS.md)
- 修改文件：[SkeletonOverlayRenderer.kt](android/app/src/main/kotlin/com/example/golf_score_app/SkeletonOverlayRenderer.kt)
