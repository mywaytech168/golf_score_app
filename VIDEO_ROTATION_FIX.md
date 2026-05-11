# 影片變行（方向錯誤）修復

## 🎯 問題

**症狀**：
- 骨架覆蓋輸出的影片方向被修改
- 原本豎屏（portrait）變成橫屏（landscape）
- 或縱橫比被壓扁

**原因**：
1. 原始視頻含有旋轉元數據（KEY_ROTATION：90, 180, 270 度）
2. MediaExtractor 提取時讀取了旋轉資訊
3. **但編碼器和 Muxer 沒有保留這個旋轉資訊**
4. 結果：輸出影片失去旋轉，方向變掉

---

## ✅ 修復方案

### 修復 1：提取原始視頻的旋轉資訊

**位置**：line ~115-130，讀取 inputFormat 時

**修改內容**：
```kotlin
// ✅ 提取旋轉信息（重要！避免影片變行）
val rotation  = runCatching {
    inputFormat.getInteger(MediaFormat.KEY_ROTATION)
}.getOrElse { 0 }
Log.d(TAG, "提取旋轉信息: rotation=$rotation°")
```

**效果**：
- 讀取原始視頻的旋轉角度（通常是 0, 90, 180, 270）
- 記錄日誌以便診斷

---

### 修復 2：設置編碼器輸出格式包含旋轉信息

**位置**：line ~130-140，配置 MediaFormat 時

**修改內容**：
```kotlin
val encFmt = MediaFormat.createVideoFormat("video/avc", videoW, videoH).apply {
    setInteger(MediaFormat.KEY_COLOR_FORMAT, CodecCapabilities.COLOR_FormatYUV420Flexible)
    setInteger(MediaFormat.KEY_BIT_RATE, 4_000_000)
    setInteger(MediaFormat.KEY_FRAME_RATE, fps.roundToInt())
    setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
    // ✅ 保留旋轉信息到編碼器輸出格式
    if (rotation != 0) {
        setInteger(MediaFormat.KEY_ROTATION, rotation)
        Log.d(TAG, "編碼器設置旋轉: $rotation°")
    }
}
```

**效果**：
- 告訴編碼器應該輸出帶有旋轉資訊的視頻
- 非零旋轉才設置（避免多餘資訊）

---

### 修復 3：修改 drainEncoder 簽名，添加 rotation 參數

**位置**：line ~500-510，drainEncoder 函數定義

**修改內容**：
```kotlin
private fun drainEncoder(
    encoder: MediaCodec, muxer: MediaMuxer, info: MediaCodec.BufferInfo,
    setTrack: (Int) -> Unit, getTrack: () -> Int, isMuxed: () -> Boolean,
    eos: Boolean,
    rotation: Int = 0,  // ✅ 新增：旋轉資訊
    onSampleWritten: () -> Unit = {},
)
```

**效果**：
- 讓函數可以接收旋轉參數
- 將旋轉資訊傳遞到 Muxer

---

### 修復 4：在 OUTPUT_FORMAT_CHANGED 時添加旋轉到 Muxer

**位置**：line ~525-535，OUTPUT_FORMAT_CHANGED 分支

**修改內容**：
```kotlin
idx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
    tryAgainCount = 0
    Log.d(TAG, "drainEncoder: OUTPUT_FORMAT_CHANGED")
    val outputFormat = encoder.outputFormat
    // ✅ 將旋轉信息添加到輸出格式
    if (rotation != 0) {
        outputFormat.setInteger(MediaFormat.KEY_ROTATION, rotation)
        Log.d(TAG, "drainEncoder: 添加旋轉信息到 Muxer: $rotation°")
    }
    val t = muxer.addTrack(outputFormat)
    muxer.start(); setTrack(t)
}
```

**效果**：
- 告訴 Muxer 輸出的視頻應該有旋轉資訊
- 確保 MP4 文件包含正確的方向元數據

---

### 修復 5：所有 drainEncoder 調用都傳遞 rotation

**位置**：line ~240-250 和 line ~275-285

**修改內容**：
```kotlin
// 第一次調用（非 EOS）
drainEncoder(
    encoder, muxer, encBufInfo,
    setTrack = { t -> muxTrack = t; muxStarted = true },
    getTrack = { muxTrack },
    isMuxed  = { muxStarted },
    eos      = false,
    rotation = rotation,  // ✅ 傳遞旋轉資訊
    onSampleWritten = { encodedFrames++; samplesWritten++ },
)

// 第二次調用（EOS）
drainEncoder(
    encoder, muxer, encBufInfo,
    setTrack = { t -> muxTrack = t; muxStarted = true },
    getTrack = { muxTrack },
    isMuxed  = { muxStarted },
    eos      = true,
    rotation = rotation,  // ✅ 傳遞旋轉資訊
    onSampleWritten = { encodedFrames++; samplesWritten++ },
)
```

**效果**：
- 確保每次調用都傳遞旋轉資訊
- 使所有編碼操作都保留方向元數據

---

## 📊 修復前後對比

| 項目 | 之前 | 之後 |
|------|------|------|
| 原始視頻旋轉信息 | ✅ 讀取但忽略 | ✅ 讀取並保留 |
| 編碼器配置 | ❌ 無旋轉信息 | ✅ 包含旋轉信息 |
| Muxer 元數據 | ❌ 無旋轉信息 | ✅ 包含旋轉信息 |
| 輸出視頻方向 | ❌ 變掉/壓扁 | ✅ 正確 |
| 播放器顯示 | ❌ 旋轉錯誤 | ✅ 正確 |

---

## 🔍 診斷日誌

修復後，你應該看到：

```
D/SkeletonOverlay: 提取旋轉信息: rotation=90°          ✅ 讀取成功
D/SkeletonOverlay: 編碼器設置旋轉: 90°              ✅ 編碼器已配置
D/SkeletonOverlay: drainEncoder: OUTPUT_FORMAT_CHANGED
D/SkeletonOverlay: drainEncoder: 添加旋轉信息到 Muxer: 90°  ✅ Muxer 已保存
D/SkeletonOverlay: SUCCESS: renderedFrames=151, encodedFrames=151  ✅ 完成
```

或者如果原始視頻無旋轉：
```
D/SkeletonOverlay: 提取旋轉信息: rotation=0°          ✅ 正常的豎屏視頻
D/SkeletonOverlay: 編碼器設置旋轉: 不設置（0° 跳過）  ✅ 保持原樣
```

---

## 🚀 測試步驟

1. **編譯**：
   ```bash
   flutter run
   ```

2. **查看日誌**：
   ```bash
   flutter logs | grep -E "SkeletonOverlay|旋轉|rotation"
   ```

3. **執行擊球偵測**

4. **驗證結果**：
   - 檢查 `hit_1_skeleton.mp4` 的方向是否正確
   - 用 Android Studio 或 ffprobe 檢查元數據：
     ```bash
     ffprobe -v error -select_streams v:0 -show_entries stream=rotation -of csv=p=0 hit_1_skeleton.mp4
     ```
   - 應該輸出原始視頻的旋轉角度（0, 90, 180, 或 270）

---

## 💡 技術背景

**為什麼視頻需要旋轉信息？**

1. **智能手機錄製**：
   - 手機傳感器檢測方向（縱屏或橫屏）
   - 系統在 MP4 元數據中記錄旋轉角度
   - 播放器根據元數據自動旋轉

2. **媒體處理**：
   - MediaExtractor 提取元數據時讀取旋轉
   - 但如果編碼過程中沒有保留，輸出 MP4 的旋轉信息就會丟失
   - 播放器看不到旋轉信息，按原始寬高顯示 → 方向錯誤

3. **此修復的作用**：
   - 確保編碼管道的每一步都保留旋轉信息
   - 最終輸出 MP4 包含正確的方向元數據
   - 播放器能正確顯示視頻

---

## 一句話總結

**添加旋轉資訊的提取、編碼器配置、和 Muxer 保存，確保骨架覆蓋影片保留原始視頻的方向。**
