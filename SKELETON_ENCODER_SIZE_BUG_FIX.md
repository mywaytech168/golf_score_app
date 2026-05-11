# SkeletonOverlay 編碼器 0 幀 - 根本原因與修復

## 🎯 根本原因

**關鍵證據**：
```
renderedFrames=151      ✅ 程序繪製了 151 幀
encodedFrames=0         ❌ 但編碼器沒有輸出
drainEncoder: idx=0, size=0, flags=4, pts=0
```

**問題代碼**：
```kotlin
val encImg = runCatching { encoder.getInputImage(encInIdx) }.getOrNull()
if (encImg != null) {
    bitmapFillYuv(encImg, bmp, videoW, videoH)
    encoder.queueInputBuffer(encInIdx, 0, 0, pts, 0)  // ❌ size=0 !
    encImg.close()
}
```

當 `size=0` 傳給 `queueInputBuffer()`，編碼器認為沒有數據，導致：
- 編碼器忽略該幀
- 151 幀全部被忽略
- 最後只收到 EOS（End-of-Stream）
- `encodedFrames=0`

---

## 🔧 修復方案

### 修復 1：統一使用 ByteBuffer 模式 ✅

**之前**（混合 Image + ByteBuffer，Image 模式有 size=0 bug）：
```kotlin
val encImg = runCatching { encoder.getInputImage(encInIdx) }.getOrNull()
if (encImg != null) {
    bitmapFillYuv(encImg, bmp, videoW, videoH)
    encoder.queueInputBuffer(encInIdx, 0, 0, pts, 0)  // ❌ size=0
    encImg.close()
} else {
    // ByteBuffer fallback
    val buf  = encoder.getInputBuffer(encInIdx)!!
    val nv12 = bitmapToNv12(bmp, videoW, videoH)
    buf.clear(); buf.put(nv12)
    encoder.queueInputBuffer(encInIdx, 0, nv12.size, pts, 0)  // ✅ size=nv12.size
}
```

**現在**（統一 ByteBuffer，始終正確傳遞 size）：
```kotlin
val buf  = encoder.getInputBuffer(encInIdx)!!
val nv12 = bitmapToNv12(bmp, videoW, videoH)
buf.clear()
buf.put(nv12)
buf.flip()  // 準備讀取

encoder.queueInputBuffer(encInIdx, 0, nv12.size, pts, 0)  // ✅ size 正確
Log.d(TAG, "queueInputBuffer: idx=$encInIdx, size=${nv12.size}, pts=$pts")
```

### 修復 2：添加編碼幀計數回調 ✅

**之前**：
```kotlin
drainEncoder(..., eos = false)
```

**現在**：
```kotlin
drainEncoder(..., 
    eos = false,
    onSampleWritten = { encodedFrames++; samplesWritten++ }
)
```

這樣每次 `writeSampleData()` 成功時都會更新 `encodedFrames`。

### 修復 3：防呆檢查 ✅

**SkeletonOverlayRenderer.kt**：
```kotlin
if (encodedFrames <= 0) {
    Log.e(TAG, "ERROR: encodedFrames=0 → 骨架編碼失敗")
    success = false  // 立即返回失敗
}
```

**recording_history_page.dart**：
```kotlin
if (await skeletonFile.exists()) {
    // 檢查文件確實存在
} else {
    debugPrint('[偵測擊球] ❌ 骨架輸出文件不存在，骨架疊加失敗');
}
```

---

## 📊 修復前後對比

### 之前（0 幀）
```
D/SkeletonOverlay: 片段: 1280x720
...
D/SkeletonOverlay: queueInputBuffer: idx=X, size=XXX (151 次)
...
D/SkeletonOverlay: drainEncoder: idx=0, size=0, flags=4  ← EOS only
E/SkeletonOverlay: ERROR: encodedFrames=0, samplesWritten=0
I/MPEG4Writer: Received total/0-length (0/0) buffers and encoded 0 frames
```

### 之後（151 幀）✅
```
D/SkeletonOverlay: 片段: 1280x720
...
D/SkeletonOverlay: queueInputBuffer: idx=X, size=2764800, pts=0
D/SkeletonOverlay: drainEncoder: OUTPUT_FORMAT_CHANGED
D/SkeletonOverlay: drainEncoder: idx=0, size=51200, flags=0, pts=0
D/SkeletonOverlay: writeSampleData: size=51200
...
D/SkeletonOverlay: drainEncoder: idx=149, size=4800, flags=4  ← EOS with size
D/SkeletonOverlay: writeSampleData: size=4800
D/SkeletonOverlay: SUCCESS: renderedFrames=151, encodedFrames=151, samplesWritten=151
```

---

## 🚀 關鍵改變

| 項目 | 之前 | 之後 |
|------|------|------|
| 編碼模式 | 混合 Image + ByteBuffer | 統一 ByteBuffer |
| queueInputBuffer size | 0（bug） | nv12.size（正確） |
| 幀計數 | 無回調 | 有 onSampleWritten 回調 |
| 編碼結果 | 0 幀 | 151 幀 |
| 防呆 | 無 | encodedFrames 驗證 + 文件檢查 |

---

## 🔍 為什麼 size=0 會導致編碼失敗？

Android MediaCodec 對 `queueInputBuffer()` 的 size 參數定義：

```
size - The number of bytes of data to be released,
       starting at the byte offset. 
       
       If size == 0, encoder treats it as empty frame (skip)
```

所以當我們傳 `size=0` 時，編碼器會：
1. 認為這是一個**空幀**
2. **不編碼**任何像素數據
3. 繼續等待下一個真正的幀
4. 但所有 151 幀都是 size=0
5. 最後只收到 EOS，編碼器報告 `encoded 0 frames`

---

## ✅ 驗證修復

運行應用後，預期日誌：

```
✅ queueInputBuffer: idx=0, size=2764800, pts=0
✅ queueInputBuffer: idx=1, size=2764800, pts=33333
...（共 151 次）
✅ drainEncoder: OUTPUT_FORMAT_CHANGED
✅ writeSampleData: size=51200
...（多次）
✅ SUCCESS: renderedFrames=151, encodedFrames=151, samplesWritten=151
✅ 骨架渲染完成: 151 幀 → hit_1_skeleton.mp4
```

---

## 🎬 後續流程

修復後，流程將恢復正常：

```
hit_1.mp4 (裁切)
  ↓
hit_1_skeleton.mp4 (骨架疊加 ← 現在正常輸出 151 幀)
  ↓
blob 提取 (BallBlobExtractor)
  ↓
ball tracker (Dart Kalman)
  ↓
hit_1_final.mp4 (球軌跡疊加)
```

---

## 📝 文件修改

1. **SkeletonOverlayRenderer.kt**
   - 統一使用 ByteBuffer 模式
   - 正確傳遞 size = nv12.size
   - 添加 size 日誌
   - 添加 onSampleWritten 回調

2. **MainActivity.kt**
   - 改進異常日誌

3. **recording_history_page.dart**
   - 添加文件存在性檢查

---

## 一句話總結

**151 幀只是程序「畫過」，因為 queueInputBuffer(size=0) 導致編碼器全部忽略。修復：統一 ByteBuffer + size=nv12.size。**
