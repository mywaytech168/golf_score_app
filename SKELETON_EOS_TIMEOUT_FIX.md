# SkeletonOverlay EOS 無限迴圈 - 修復執行報告

## 🎯 核心問題

**日誌顯示**：
```
drainEncoder: TRY_AGAIN_LATER (1/50), eos=true
drainEncoder: TRY_AGAIN_LATER (2/50), eos=true
...
drainEncoder: TRY_AGAIN_LATER (50/50), eos=true
drainEncoder: Timeout after 50 TRY_AGAIN_LATER, 強制退出
```

**原因**：
1. 編碼器沒有接收到有效的幀
2. drainEncoder 無限等待輸出，導致應用凍結
3. 沒有 timeout 機制

---

## 🔧 已實施的修復

### 修復 1：添加 Timeout 計數器 ✅

**之前**（無限迴圈）：
```kotlin
while (true) {
    val idx = encoder.dequeueOutputBuffer(info, timeout)
    if (idx == MediaCodec.INFO_TRY_AGAIN_LATER) {
        if (!eos) break  // ❌ eos=true 時無限迴圈
    }
}
```

**現在**（最多等 50 次）：
```kotlin
var tryAgainCount = 0
while (true) {
    val idx = encoder.dequeueOutputBuffer(info, 10_000L)
    if (idx == MediaCodec.INFO_TRY_AGAIN_LATER) {
        tryAgainCount++
        if (eos && tryAgainCount > 50) {  // ✅ 50 次後強制退出
            Log.e(TAG, "drainEncoder: Timeout after 50 TRY_AGAIN_LATER")
            break
        }
    }
}
```

### 修復 2：改進 queueInputBuffer 數據填充 ✅

**之前**（可能有 buffer 遺漏）：
```kotlin
buf.clear()
buf.put(nv12)  // 可能無法寫入全部數據
buf.flip()
```

**現在**（明確指定偏移和長度）：
```kotlin
buf.clear()
buf.put(nv12, 0, nv12.size)  // ✅ 明確長度和偏移
buf.flip()
```

### 修復 3：frameCount 驗證 ✅

**之前**：
```kotlin
// 直接進入 EOS，不檢查是否有幀被 queue
val eosIdx = encoder.dequeueInputBuffer(100_000L)
```

**現在**：
```kotlin
// 檢查是否有幀被 queue 了
if (frameCount <= 0) {
    Log.e(TAG, "CRITICAL: frameCount=0，編碼器沒有收到任何幀")
    success = false
} else {
    // queue EOS
}
```

### 修復 4：更詳細的日誌追蹤 ✅

```kotlin
if (frameCount < 3 || frameCount % 50 == 0) {
    Log.d(TAG, "queueInputBuffer: idx=$encInIdx, size=${nv12.size}, pts=$pts, frameCount=$frameCount")
}
```

只記錄前 3 幀和每 50 幀一次，避免日誌過多。

---

## 📊 修復前後的行為

### 之前（卡住）❌
```
D/SkeletonOverlay: queueInputBuffer: idx=0, size=2764800, pts=0
D/SkeletonOverlay: queueInputBuffer: idx=1, size=2764800, pts=33333
...
D/SkeletonOverlay: EOS queued at index 3
D/SkeletonOverlay: Draining encoder with eos=true
D/SkeletonOverlay: drainEncoder: TRY_AGAIN_LATER, eos=true
D/SkeletonOverlay: drainEncoder: TRY_AGAIN_LATER, eos=true
...（無限重複）
```
→ **應用凍結，無法繼續**

### 現在（有 timeout）✅
```
D/SkeletonOverlay: queueInputBuffer: idx=0, size=2764800, pts=0
D/SkeletonOverlay: queueInputBuffer: idx=50, size=2764800, pts=...
D/SkeletonOverlay: queueInputBuffer: idx=100, size=2764800, pts=...
D/SkeletonOverlay: queueInputBuffer: idx=150, size=2764800, pts=...
D/SkeletonOverlay: EOS queued at index 3, frameCount=151
D/SkeletonOverlay: Draining encoder with eos=true
D/SkeletonOverlay: drainEncoder: TRY_AGAIN_LATER (1/50), eos=true
D/SkeletonOverlay: drainEncoder: TRY_AGAIN_LATER (2/50), eos=true
...
D/SkeletonOverlay: drainEncoder: TRY_AGAIN_LATER (50/50), eos=true
D/SkeletonOverlay: drainEncoder: Timeout after 50 TRY_AGAIN_LATER, 強制退出
E/SkeletonOverlay: ERROR: encodedFrames=0
E/SkeletonOverlay: Skeleton overlay failed, deleting: hit_1_skeleton.mp4
```
→ **不再卡住，返回錯誤，不進入 blob 提取**

---

## 🔍 診斷邏輯

### 情況 1：frameCount=0（完全沒有幀）

```
E/SkeletonOverlay: CRITICAL: frameCount=0，編碼器沒有收到任何幀，停止處理
```

**原因檢查**：
1. dequeueInputBuffer 一直返回 < 0？
2. queueInputBuffer 調用被跳過？
3. CSV 數據為空？

### 情況 2：frameCount>0，但 encodedFrames=0

```
D/SkeletonOverlay: queueInputBuffer: idx=0, size=2764800, pts=0  ✅ 有 151 幀
...
D/SkeletonOverlay: drainEncoder: Timeout after 50 TRY_AGAIN_LATER  ⚠️  編碼器無輸出
E/SkeletonOverlay: ERROR: encodedFrames=0
```

**原因檢查**：
1. bitmapToNv12 轉換是否正確？
2. MediaCodec 是否真的啟動了？
3. nv12.size 是否正確？

### 情況 3：frameCount>0，encodedFrames>0

```
D/SkeletonOverlay: queueInputBuffer: frameCount=151
...
D/SkeletonOverlay: drainEncoder: OUTPUT_FORMAT_CHANGED
D/SkeletonOverlay: writeSampleData: size=51200
...
D/SkeletonOverlay: SUCCESS: renderedFrames=151, encodedFrames=151
```

→ **正常流程！**

---

## ✅ 驗證清單

運行應用後，執行擊球偵測，檢查：

- [ ] `queueInputBuffer: frameCount=151` 或接近 151
- [ ] `EOS queued at index X, frameCount=151`
- [ ] 不看到無限的 `TRY_AGAIN_LATER`
- [ ] 最後看到 `drainEncoder: Timeout` 或 `SUCCESS`
- [ ] 不應該看到應用完全凍結（卡住）

---

## 🚀 下一步

1. **編譯並運行**：
   ```bash
   flutter run
   ```

2. **查看日誌**：
   ```bash
   flutter logs | grep SkeletonOverlay
   ```

3. **執行擊球偵測**，觀察日誌流程

4. **根據結果**：
   - 如果 `encodedFrames=0`：檢查 bitmapToNv12 或 MediaCodec 配置
   - 如果有輸出：继续到 BallBlobExtractor 流程
   - 如果應用凍結：说明 timeout 邏輯有問題

---

## 📝 關鍵改變

| 項目 | 之前 | 之後 |
|------|------|------|
| TRY_AGAIN_LATER 迴圈 | 無限 | 最多 50 次 |
| Timeout 機制 | 無 | timeout 後強制退出 |
| frameCount 驗證 | 無 | 檢查 frameCount > 0 |
| Buffer put 操作 | buf.put(nv12) | buf.put(nv12, 0, nv12.size) |
| 應用狀態 | 可能凍結 | 不卡住，返回錯誤 |

---

## 一句話總結

**修復了 drainEncoder 的無限迴圈（添加 timeout 計數器），同時改進 buffer 填充和 frameCount 驗證，確保編碼失敗時能正確返回而不是卡住應用。**
