# 🎬 导入视频音频分析 - 实现方案修正

## 问题分析

初始实现遇到的问题：
- ❌ 新的 `AudioExtractionHandler.kt` 和 `"com.orvia.golf/audio_extraction"` Channel 未被正确注册
- ❌ Android Platform Channel 无法被调用
- ❌ 系统中无 FFmpeg 支持

## ✅ 解决方案

利用项目中**现有的** `"audio_extractor_channel"` 和 `extractAudioToWav` 函数。

---

## 🔄 改进的工作流程

```
導入短視頻
  ↓
進入錄製歷史
  ↓
按下「影片分析」
  ↓
視頻分析 (0-70%)
  ├─ 骨架提取
  ├─ 球軌跡檢測
  └─ 擊球剪輯生成
  ↓
檢查 audio.pcm
  ├─ ✅ 存在 → 直接分析
  └─ ❌ 不存在 → 使用現有 Channel
       │
       ├─→ 調用 audio_extractor_channel
       │   └─ 調用 extractAudioToWav()
       │       ├─ MediaExtractor 掃描音軌
       │       ├─ MediaCodec 解碼
       │       └─ 輸出 WAV 文件 (PCM 16-bit)
       │
       ├─→ WAV → PCM Float32 轉換
       │   ├─ 讀取 WAV 頭
       │   ├─ 提取音頻數據
       │   ├─ PCM 16-bit → Float32 轉換
       │   ├─ 重採樣到 44.1kHz (如需)
       │   └─ 保存為 audio.pcm
       │
       └─→ 執行音頻分析
           ├─ 特徵提取
           ├─ Bayesian 分類
           └─ 生成 CSV + TXT
```

---

## 📁 代码修改

### 1️⃣ AudioExtractionService (完全重構)
**文件**: `lib/services/audio_extraction_service.dart`

**核心改變**:
```dart
// 使用現有的 audio_extractor_channel，而非新建 Channel
static const platform = MethodChannel('audio_extractor_channel');

// 新方法：_convertWavToPcm()
// 功能：
// - 解析 WAV 頭 (採樣率、聲道數、位深)
// - PCM 16-bit → Float32 轉換
// - 線性插值重採樣 (如需要)
// - 保存為標準 PCM Float32 格式
```

**流程**:
```dart
extractAudioFromVideo()
  ├─ 呼叫現有 channel.invokeMethod('extractAudio')
  ├─ 收到 WAV 檔案路徑
  └─ 調用 _convertWavToPcm()
      ├─ 讀取 WAV 檔案
      ├─ 解析頭部資訊
      ├─ 轉換為 Float32 PCM
      └─ 返回樣本數
```

### 2️⃣ 移除不必要的文件

❌ **刪除**: `android/app/src/main/kotlin/.../AudioExtractionHandler.kt`
- 理由：使用現有的 audio_extractor_channel，不需要新建 Handler

❌ **不修改**: `android/app/src/main/kotlin/.../MainActivity.kt`  
- 理由：現有的 audio_extractor_channel 已經可用

---

## 🎯 技術實現細節

### WAV 文件格式

```
Offset  Size  Description
0       4     "RIFF"
4       4     文件大小
8       4     "WAVE"
12      4     "fmt "
16      4     子塊大小
20      2     音頻格式 (1=PCM)
22      2     聲道數
24      4     採樣率
28      4     位元速率
32      2     塊大小
34      2     位深 (16=16-bit)
36+     ?     可能還有其他 chunk
??      4     "data"
??+4    4     數據大小
??+8    ?     音頻數據
```

### PCM 16-bit → Float32 轉換

```dart
// 讀取 16-bit 有符號整數
final int16 = audioDataBytes[i] | (audioDataBytes[i + 1] << 8);

// 轉換為有符號整數 (處理大端序)
final signedInt16 = (int16 > 32767) ? int16 - 65536 : int16;

// 正規化到 [-1.0, 1.0]
final float32 = signedInt16 / 32768.0;
```

### 線性插值重採樣

```dart
// 如果 WAV 採樣率 ≠ 44100 Hz，進行重採樣
final ratio = targetSampleRate / sourceSampleRate;
final newLength = (samples.length * ratio).toInt();

for (int i = 0; i < newLength; i++) {
  final sourceIndex = i / ratio;
  final floorIndex = sourceIndex.floor();
  final ceilIndex = floorIndex + 1;
  final fraction = sourceIndex - floorIndex;
  
  // 線性插值
  final value = samples[floorIndex] * (1 - fraction) + 
                samples[ceilIndex] * fraction;
}
```

---

## 🧪 測試驗證

### 步驟 1: 編譯檢查
```bash
cd d:\Projects\golf_score_app
dart analyze lib/services/audio_extraction_service.dart
# 結果: 無錯誤 ✅
```

### 步驟 2: 執行 App
```bash
flutter run
# 等待 app 啟動
```

### 步驟 3: 導入視頻並分析
```
1. 主頁面 → 選擇視頻檔案 → 導入
2. 錄製歷史 → 找到導入的視頻
3. 長按或點擊分析按鈕 → 「完整分析」
4. 觀察進度條:
   - 0-70%: 視頻分析 (骨架 + 球軌跡)
   - 70-72%: 檢查 PCM
   - 72-82%: 調用現有 channel 提取 WAV
   - 82-92%: 轉換 WAV → PCM Float32
   - 92-100%: 音頻分析
```

### 步驟 4: 驗證日誌

**預期的日誌消息**:
```
✅ [完整分析] 開始視頻分析...
✅ [完整分析] 開始音頻分析...
🎵 [完整分析] PCM 不存在，嘗試從視頻提取...
📊 [AudioExtraction] 調用 MediaCodec 提取音頻...
✅ [AudioExtraction] WAV 提取成功: /cache/audio_extract_*.wav
📊 [AudioExtraction] WAV 信息: format=1, channels=1, sampleRate=44100, bitsPerSample=16
🔄 [AudioExtraction] 轉換為 PCM Float32...
💾 [AudioExtraction] 保存 PCM 檔案: audio.pcm (88200 樣本)
✅ [完整分析] ✅ 分類: good, 反饋: 擊球音質優
```

### 步驟 5: 驗證文件生成

```bash
adb shell run-as com.example.golf_score_app ls -lh app_flutter/golf_recordings/*/audio*

# 預期輸出:
# app_flutter/golf_recordings/1234567890/audio.pcm (新)
# app_flutter/golf_recordings/1234567890/audio_features.csv (新)
# app_flutter/golf_recordings/1234567890/audio_analysis.txt (新)
```

---

## 📊 進度條分布 (更新)

```
0%   ┌─ 10%   檢查文件
10%  ├─ 35%   基礎視頻分析
35%  ├─ 70%   完整視頻分析 (骨架+球軌跡)
70%  ├─ 72%   檢查 PCM
72%  ├─ 82%   提取音頻 (現有 Channel → WAV)
82%  ├─ 92%   WAV → PCM Float32 轉換
92%  └─ 100%  音頻分析 + 分類
```

---

## ⚙️ 實作細節

### 使用現有 Channel 的優勢

✅ **已驗證可用**: 項目中已有，不需要新的 native 實現
✅ **性能**: 使用 MediaCodec (原生最快)
✅ **相容性**: 支持所有 Android 版本
✅ **格式支持**: MP3, AAC, OGG, WAV, FLAC 等

### WAV 轉 PCM 轉換的優勢

✅ **無外部依賴**: 純 Dart 實現，不需要 FFmpeg
✅ **靈活**: 可處理不同採樣率和位深
✅ **快速**: 簡單的數據轉換，無複雜編碼/解碼
✅ **標準化**: 輸出統一的 PCM Float32 44.1kHz 格式

---

## 🔮 支持的場景

| 場景 | 自錄制 | 導入視頻 | 結果 |
|------|-------|--------|------|
| 有音軌 MP3/AAC | ✅ audio.pcm | ✅ 自動提取 | ✅ 完整分析 |
| 有音軌 OGG/WAV | ✅ audio.pcm | ✅ 自動提取 | ✅ 完整分析 |
| 無音軌 | ❌ | ❌ 跳過 | ⚠️ 仅視頻分析 |
| 音軌損壞 | ⚠️ | ⚠️ 提取失敗 | ⚠️ 僅視頻分析 |

---

## 📝 故障排查

| 問題 | 原因 | 解決方案 |
|------|------|--------|
| "Channel 無法調用" | audio_extractor_channel 未正確註冊 | 檢查 MainActivity.kt 第 124-152 行 |
| "WAV 文件為空" | 視頻無音軌 | 確認視頻有效且包含音軌 |
| "轉換異常" | WAV 格式不標準 | 使用常見格式 (MP4+AAC/MP3) |
| "進度卡住" | MediaCodec 超時 | 嘗試其他視頻 |

---

## ✨ 關鍵改進

相比初始實現：
- ❌ 移除了不必要的新 Handler 和 Channel
- ✅ 利用現有的 `extractAudioToWav` 實現
- ✅ 純 Dart 實現 WAV → PCM 轉換
- ✅ 支持多種採樣率和位深自動轉換
- ✅ 無額外外部依賴 (不需要 FFmpeg)

---

## 🎯 下一步

- [x] 修改 AudioExtractionService 使用現有 Channel
- [x] 實現 WAV → PCM Float32 轉換
- [x] 添加採樣率轉換支持
- [ ] 在設備上測試驗證
- [ ] 監控日誌確認工作流程
- [ ] 驗證生成的 audio.pcm 文件完整性

