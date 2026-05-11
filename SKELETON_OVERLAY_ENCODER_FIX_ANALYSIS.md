# SkeletonOverlay 編碼器 0 幀問題 - 詳細分析與修復方案

## 問題診斷

### 日誌證據
```
D/SkeletonOverlay: 骨架渲染完成: 151 幀 → hit_1_skeleton.mp4
I/MPEG4Writer: Received total/0-length (0/0) buffers and encoded 0 frames. - Video
E/MPEG4Writer: Stop() called but track is not started or stopped
E/BallBlobExtractor: 找不到視頻 track
E/MediaMetadataRetrieverJNI: videoFrame is a NULL pointer
ParserException: Malformed sample table missing stsd
```

### 根本原因

SkeletonOverlayRenderer.kt 的 `drainEncoder` 函數有以下問題：

1. **編碼幀未被寫入 Muxer**
   - 雖然渲染了 151 幀，但編碼器的輸出可能未正確寫入
   - MP4Writer 報告 "encoded 0 frames" 表明 Muxer 沒收到任何樣本數據

2. **缺少編碼幀計數驗證**
   - 代碼只記錄「渲染幀數」（frameCount++），但不記錄「寫入幀數」
   - 無法區分：是編碼器沒輸出，還是輸出沒被寫入

3. **drainEncoder 邏輯風險**
   ```kotlin
   if (buf != null && info.size > 0 && isMuxed()) {
       muxer.writeSampleData(getTrack(), buf, info)
   }
   ```
   - 如果編碼器在 OUTPUT_FORMAT_CHANGED 之前就產生輸出，可能被遺漏
   - 需要驗證 OUTPUT_FORMAT_CHANGED 何時被觸發

### 可能的根本原因

#### 原因 1：編碼器未收到有效的 YUV 數據
```kotlin
encImg.close()  // <- 在 queueInputBuffer 之前 close，可能導致數據無效
encoder.queueInputBuffer(encInIdx, 0, 0, pts, 0)
```

#### 原因 2：EOS（End-of-Stream）未正確發送
```kotlin
encoder.queueInputBuffer(
    eosIdx, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM
)
```
- EOS 幀被立即放入而沒有等待編碼器處理
- drainEncoder 需要反覆調用以清空所有輸出緩衝區

#### 原因 3：緩衝區同步問題
- 可能 Bitmap → YUV 轉換不完整
- bitmapFillYuv 或 bitmapToNv12 的轉換可能有問題

---

## 修復方案

### 步驟 1：加入詳細日誌追蹤編碼狀態

**位置**：SkeletonOverlayRenderer.kt 主循環和 drainEncoder

```diff
private var encodedFrames = 0
private var drainedOutputs = 0
private var samplesWritten = 0

// 在 render() 中初始化
encodedFrames = 0
drainedOutputs = 0
samplesWritten = 0

// 在 drainEncoder 中加日誌
private fun drainEncoder(...) {
    val timeout = if (eos) 100_000L else 0L
    while (true) {
        val idx = encoder.dequeueOutputBuffer(info, timeout)
        when {
            idx == MediaCodec.INFO_TRY_AGAIN_LATER -> {
                Log.d(TAG, "drainEncoder: TRY_AGAIN_LATER, eos=$eos")
                if (!eos) break
            }
            idx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                Log.d(TAG, "drainEncoder: OUTPUT_FORMAT_CHANGED")
                val t = muxer.addTrack(encoder.outputFormat)
                muxer.start()
                setTrack(t)
            }
            idx >= 0 -> {
                drainedOutputs++
                Log.d(TAG, "drainEncoder: idx=$idx, size=${info.size}, flags=${info.flags}, pts=${info.presentationTimeUs}")
                
                val buf = encoder.getOutputBuffer(idx)
                if (buf != null && info.size > 0 && isMuxed()) {
                    buf.position(info.offset)
                    buf.limit(info.offset + info.size)
                    muxer.writeSampleData(getTrack(), buf, info)
                    samplesWritten++
                    encodedFrames++
                    Log.d(TAG, "writeSampleData: encodedFrames=$encodedFrames, size=${info.size}")
                } else {
                    Log.w(TAG, "writeSampleData skip: buf=$buf, size=${info.size}, isMuxed=${isMuxed()}")
                }
                
                encoder.releaseOutputBuffer(idx, false)
                if ((info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                    Log.d(TAG, "drainEncoder: EOS flag detected, breaking")
                    break
                }
            }
        }
    }
}

// 在 render() 的最後加驗證
if (encodedFrames <= 0) {
    Log.e(TAG, "ERROR: encodedFrames=$encodedFrames, drainedOutputs=$drainedOutputs, samplesWritten=$samplesWritten")
    throw IllegalStateException(
        "Skeleton MP4 編碼失敗: renderedFrames=$frameCount, " +
        "encodedFrames=$encodedFrames, drainedOutputs=$drainedOutputs, " +
        "samplesWritten=$samplesWritten"
    )
}
Log.d(TAG, "SUCCESS: renderedFrames=$frameCount, encodedFrames=$encodedFrames, " +
    "drainedOutputs=$drainedOutputs, samplesWritten=$samplesWritten")
```

### 步驟 2：修復 Image.close() 時序問題

**位置**：render() 主循環

```diff
if (encImg != null) {
    bitmapFillYuv(encImg, bmp, videoW, videoH)
-   encImg.close()  // 過早 close，會使數據無效！
    encoder.queueInputBuffer(encInIdx, 0, 0, pts, 0)
+   encImg.close()  // 在 queueInputBuffer 之後才 close
} else {
    // fallback: use byte array
    ...
}
```

### 步驟 3：加強 EOS 處理與編碼器排空

**位置**：render() EOS 部分

```diff
// ── EOS ─────────────────────────────────────────────
Log.d(TAG, "Signaling EOS to encoder")
val eosIdx = encoder.dequeueInputBuffer(100_000L)
if (eosIdx >= 0) {
    encoder.queueInputBuffer(
        eosIdx, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM
    )
    Log.d(TAG, "EOS queued at index $eosIdx")
} else {
    Log.w(TAG, "Failed to get input buffer for EOS: $eosIdx")
}

// 充分排空編碼器
Log.d(TAG, "Draining encoder with eos=true")
drainEncoder(
    encoder, muxer, encBufInfo,
    setTrack = { t -> muxTrack = t; muxStarted = true },
    getTrack = { muxTrack },
    isMuxed  = { muxStarted },
    eos      = true,  // 這裡會設定較長的 timeout
)
Log.d(TAG, "Encoder drained, encodedFrames=$encodedFrames")
```

### 步驟 4：驗證 YUV 轉換完整性

**檢查**：bitmapFillYuv 是否正確處理所有 UV 平面

```kotlin
// 在 bitmapFillYuv 後加驗證
private fun verifyYuvImage(image: Image, w: Int, h: Int): Boolean {
    val yP = image.planes[0]; val uP = image.planes[1]; val vP = image.planes[2]
    val ySize = w * h
    val uvSize = w * h / 4
    
    val yBuf = yP.buffer; val uBuf = uP.buffer; val vBuf = vP.buffer
    
    Log.d(TAG, "YUV planes: y.cap=${yBuf.capacity()}, u.cap=${uBuf.capacity()}, v.cap=${vBuf.capacity()}")
    Log.d(TAG, "Expected: y=$ySize, uv=$uvSize")
    
    return yBuf.capacity() >= ySize && uBuf.capacity() >= uvSize && vBuf.capacity() >= uvSize
}
```

### 步驟 5：改進錯誤報告

**位置**：render() 返回前

```diff
- if (!success) runCatching { File(outputPath).delete() }
+ if (!success) {
+     Log.e(TAG, "Skeleton overlay failed, deleting: $outputPath")
+     Log.e(TAG, "Final stats: renderedFrames=$frameCount, encodedFrames=$encodedFrames, " +
+         "samplesWritten=$samplesWritten")
+     runCatching { File(outputPath).delete() }
+ }
```

---

## 測試驗證清單

1. **第一次運行**：應該在日誌中看到
   ```
   D/SkeletonOverlay: drainEncoder: OUTPUT_FORMAT_CHANGED
   D/SkeletonOverlay: drainEncoder: idx=0, size=XXXX (not 0)
   D/SkeletonOverlay: writeSampleData: encodedFrames=1, size=XXXX
   ```

2. **如果仍然是 0 幀**：檢查
   ```
   D/SkeletonOverlay: drainEncoder: TRY_AGAIN_LATER, eos=false
   ```
   → 表示編碼器根本沒有輸出

3. **如果看到異常**：
   ```
   E/SkeletonOverlay: ERROR: encodedFrames=0, drainedOutputs=0
   ```
   → 立即停止執行，不進入 BallBlobExtractor

---

## 預期結果

修復後，日誌應該顯示：
```
D/SkeletonOverlay: 片段: 1280x720 fps=30.0  scale=1.777x1.125
D/SkeletonOverlay: CSV 解析完成：151 幀
D/SkeletonOverlay: drainEncoder: OUTPUT_FORMAT_CHANGED
D/SkeletonOverlay: drainEncoder: idx=0, size=51200, flags=0, pts=0
D/SkeletonOverlay: writeSampleData: encodedFrames=1, size=51200
D/SkeletonOverlay: drainEncoder: idx=1, size=4800, flags=0, pts=33333
D/SkeletonOverlay: writeSampleData: encodedFrames=2, size=4800
...
D/SkeletonOverlay: drainEncoder: TRY_AGAIN_LATER, eos=false
D/SkeletonOverlay: drainEncoder: EOS flag detected, breaking
D/SkeletonOverlay: SUCCESS: renderedFrames=151, encodedFrames=151, samplesWritten=151
D/SkeletonOverlay: 骨架渲染完成: 151 幀 → hit_1_skeleton.mp4
```

---

## 優先修復順序

1. ✅ 加日誌追蹤 encodedFrames
2. ✅ 修正 Image.close() 時序
3. ✅ 加強 EOS 和 drainEncoder
4. ✅ 驗證 YUV 轉換
5. ⛔ 如果 encodedFrames = 0，拋出異常，不要進入後續流程
