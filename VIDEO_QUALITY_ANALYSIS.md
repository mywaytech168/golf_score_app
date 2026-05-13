# 視頻本地處理質量分析

## 🔴 發現的核心問題

### 1. **逐級質量損失（8.4MB → 4.5MB → 3.3MB）**

視頻經過多個編碼階段，每次都損失質量：

```
原始視頻 (8.4MB)
    ↓ VideoTrimmer 裁切 + 編碼
4.5MB (骨架版本)
    ↓ SkeletonOverlayRenderer 解碼→繪製→重新編碼
    ↓ TrajectoryOverlayRenderer 解碼→繪製→重新編碼
3.3MB (最終版本)
```

**根本原因：每次編碼都使用固定低比特率**

### 2. **比特率計算過於激進**

在 `SkeletonOverlayRenderer.kt:154` 和 `TrajectoryOverlayRenderer.kt:155`：

```kotlin
val bitRate = (displayW.toLong() * displayH * fps * 0.25)
    .toLong().coerceIn(6_000_000L, 20_000_000L).toInt()
```

**問題：**
- 係數 `0.25 bpp`（每像素 0.25 位）非常激進
- 例如 1080x1920@30fps = 約 8.7 Mbps → 限制在 6-20 Mbps 下限
- 多次編碼累積損失

**實例計算：**
```
第1次編碼（裁切）: 8.4 MB
第2次編碼（骨架）: 係數 0.25 bpp → 4.5 MB (-46%)
第3次編碼（軌跡）: 係數 0.25 bpp → 3.3 MB (-27%)
```

### 3. **幀率降低問題**

在 `SkeletonOverlayRenderer.kt:153`：

```kotlin
setInteger(MediaFormat.KEY_FRAME_RATE, fps.roundToInt())
```

**問題：**
- 四捨五入可能改變幀率（例如 29.97fps → 30fps）
- 編碼器無法精確保持原始幀率
- 可能導致音頻-視頻不同步

### 4. **最後幾幀丟失/卡頓問題**

在 `SkeletonOverlayRenderer.kt:250-270` 和 `TrajectoryOverlayRenderer.kt` 類似代碼：

```kotlin
while (true) {
    // ... 編碼邏輯 ...
    
    if ((decBufInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) 
        break  // ❌ 立即跳出，未等待所有編碼器輸出
}

// ❌ 未進行編碼器洩出（encoder draining）
encoder.signalEndOfInputStream()
```

**問題：**
- 解碼完成後立即停止，編碼器中仍有未編碼的幀
- 最後幾幀被遺棄
- 導致結尾幀跳過/卡頓

---

## 📊 改進方案

### 優先級 1️⃣：修復最後幀丟失（最高優先）

**方案：正確的編碼器洩出流程**

```kotlin
// 1. 解碼輸入全部讀完
while (!inputEos) {
    val inIdx = decoder.dequeueInputBuffer(...)
    // ... 讀取樣本 ...
    if (size < 0) {
        decoder.queueInputBuffer(..., MediaCodec.BUFFER_FLAG_END_OF_STREAM)
        inputEos = true
    }
}

// 2. 等待解碼器輸出所有幀
var decoderEos = false
while (!decoderEos) {
    val outIdx = decoder.dequeueOutputBuffer(decBufInfo, ...)
    if (outIdx >= 0) {
        // ... 處理解碼幀 ...
        decoder.releaseOutputBuffer(outIdx, false)
        if ((decBufInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0)
            decoderEos = true
    }
}

// 3. 告知編碼器結束
encoder.signalEndOfInputStream()

// 4. 洩出所有編碼器輸出
while (true) {
    val outIdx = encoder.dequeueOutputBuffer(encBufInfo, ...)
    if (outIdx >= 0) {
        // ... 寫入 muxer ...
        encoder.releaseOutputBuffer(outIdx, false)
        if ((encBufInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0)
            break
    }
}
```

### 優先級 2️⃣：提高比特率以保留質量

**方案：調整係數並考慮內容複雜度**

```kotlin
// 當前（過低）：0.25 bpp
// 建議改為：0.5-1.0 bpp（取決於解析度和動作複雜度）

val bitRate = when {
    // 高解析度（1440p+）：高動作複雜度（高爾夫揮桿）
    displayW >= 1440 -> (displayW.toLong() * displayH * fps * 1.0)
    // 中解析度（1080p）
    displayW >= 1080 -> (displayW.toLong() * displayH * fps * 0.8)
    // 低解析度
    else -> (displayW.toLong() * displayH * fps * 0.5)
}.toLong().coerceIn(8_000_000L, 25_000_000L).toInt()
```

**預期結果：**
```
第1次：8.4 MB（原始）
第2次：~6.5 MB（-23%，質量損失最小）
第3次：~5.5 MB（-15%）
```

### 優先級 3️⃣：減少編碼次數

**當前流程：**
```
原始 → [VideoTrimmer 編碼 1] → [SkeletonOverlay 編碼 2] → [TrajectoryOverlay 編碼 3]
```

**改進方案：**
```
原始 → [裁切 + 解碼] → [繪製骨架 + 繪製軌跡 + 單次編碼]
```

這樣可以避免多次編碼造成的質量損失。

### 優先級 4️⃣：修復幀率精度

```kotlin
// 改為浮點比較，避免四捨五入損失
val actualFps = runCatching {
    inputFormat.getInteger(MediaFormat.KEY_FRAME_RATE).toFloat()
}.getOrElse { 30f }

// 對編碼器設置時間戳間隔而非幀率
val frameIntervalUs = (1_000_000f / actualFps).toLong()
// ... 在編碼時使用 frameIntervalUs 計算準確時間戳
```

---

## 🎯 實施步驟

1. **立即修復編碼器洩出** (修復最後幀丟失)
   - 在 SkeletonOverlayRenderer.kt 和 TrajectoryOverlayRenderer.kt 中添加正確的 EOS 處理

2. **提升比特率係數** (改善質量)
   - 將 0.25 bpp 改為 0.8-1.0 bpp

3. **併合編碼步驟** (進一步減少損失)
   - 重構為單次編碼流程

4. **測試驗證**
   - 測試最終視頻大小、幀率、質量
