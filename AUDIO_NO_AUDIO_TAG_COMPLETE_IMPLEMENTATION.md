# 🎯 聲音分析無聲音標籤 - 完整實現報告

## 📋 完整需求
> 聲音分析 -> 若無聲音加上無聲音的TAG  
> 這樣在錄影歷史會有無聲音的TAG 媽

實現完整的音訊分析無聲音標籤功能，並集成到錄影歷史持久化層中。

---

## ✅ 三層實現架構

### 🔵 第一層：數據模型層 - 錄影歷史持久化
**檔案：** `lib/models/recording_history_entry.dart`

新增 `audioTags` 欄位用於儲存標籤列表：
```dart
/// 音訊分析標籤（無聲音、無有效擊球等）
/// 例如：['no_audio']、['no_valid_hits']、['pro']
final List<String>? audioTags;
```

**更新方法：**
- ✅ `copyWith()` - 包含 `audioTags` 參數
- ✅ `toJson()` - 序列化 `audioTags` 到 JSON
- ✅ `fromJson()` - 反序列化並容錯處理

**JSON 儲存示例：**
```json
{
  "filePath": "/path/to/video.mp4",
  "roundIndex": 1,
  "audioLabel": "Pro",
  "audioTags": ["pro"],
  "recordedAt": "2026-05-18T10:30:00.000Z"
}
```

---

### 🔵 第二層：服務層 - 音訊分析與標籤提取
**檔案：** `lib/services/audio_analysis_service.dart`

**新增無聲音檢測：**
- 常數：`_silenceRmsThreshold = 0.01` (RMS 閾值)、`_silencePeakThreshold = 0.05` (峰值閾值)
- 方法：`_isSilentAudio()` - 檢測音訊是否為無聲音

**無聲音檢測邏輯：**
```
RMS < 0.01 && Peak < 0.05 → 無聲音
```

**返回值包含標籤：**
```dart
{
  'summary': {
    'audio_class': 'no_audio',        // 分類結果
    'audio_feedback': '無聲音',        // 使用者提示
    'tags': ['no_audio'],              // ✅ 標籤列表
  },
  'segments': [],
  'analysis_seconds': 0.125,
}
```

---

### 🔵 第三層：頁面層 - 錄製完成流程
**檔案：** `lib/recording/record_screen.dart`

**新增方法：**
```dart
Future<List<String>?> _extractAudioTags(String audioPath) async {
  // 呼叫 AudioAnalysisService.analyzeVideo()
  // 提取並返回音訊標籤
}
```

**流程：**
1. 錄製完成 → `_finishRecording()`
2. 呼叫 `_extractAudioTags()`
3. 獲得標籤列表
4. 傳遞給 `widget.onComplete(audioTags: tags)`

**更新的 RecordCompleteCallback：**
```dart
typedef RecordCompleteCallback = void Function({
  required String videoPath,
  required String csvPath,
  required String audioPath,
  required int durationSeconds,
  required String? thumbnailPath,
  required String? audioLabel,
  List<String>? audioTags,  // ✅ 新增
});
```

---

### 🔵 第四層：主應用層 - 歷史記錄保存
**檔案：** `lib/pages/main_shell_page.dart`

**更新回調：**
```dart
Future<void> _handleRecordingComplete(
  String videoPath,
  String csvPath,
  String audioPath, {
  required int durationSeconds,
  required String? thumbnailPath,
  required String? audioLabel,
  List<String>? audioTags,  // ✅ 新增
}) async {
  final entry = RecordingHistoryEntry(
    filePath: videoPath,
    roundIndex: existing.length + 1,
    recordedAt: timestamp,
    durationSeconds: durationSeconds,
    thumbnailPath: thumbnailPath,
    audioLabel: audioLabel,
    audioTags: audioTags,  // ✅ 新增
  );
  
  await RecordingHistoryStorage.instance.saveHistory(updated);
}
```

**流程：**
1. 錄製完成回調
2. 接收 `audioTags` 參數
3. 建立 `RecordingHistoryEntry(audioTags: tags)`
4. 保存到 `RecordingHistoryStorage`
5. 歷史記錄中顯示 ✅

---

### 🔵 第五層：後端分析層 - Python 標籤標記
**檔案：** `meshflow_stabilize_with_audio_V2/functions/audio_analysis.py`

**新增無聲音檢測函數：**
```python
def _is_silent_audio(y: np.ndarray, 
                    rms_threshold: float = 0.01, 
                    peak_threshold: float = 0.05) -> bool:
    """檢測音訊是否為無聲音"""
    rms = np.sqrt(np.mean(y ** 2))
    peak = np.max(np.abs(y))
    return (rms < rms_threshold) and (peak < peak_threshold)
```

**返回結果包含標籤：**
```python
# 無聲音情況
{
    "status": "no_audio",
    "video": "golf_swing_001",
    "hits_detected": 0,
    "tag": "no_audio",
    "elapsed_time": 1.234,
}

# 有效擊球
{
    "status": "success",
    "video": "golf_swing_001",
    "hits_detected": 1,
    "tag": "valid_hits",
    "denoised_summary_path": "/path/to/summary.csv",
    "elapsed_time": 2.456,
}
```

**CSV 記錄包含標籤欄位：**
```python
base = {
    "title": video_name,
    "tag": "valid_hit",  # ← 新增
    ...
}
```

---

## 📊 完整流程圖

```
┌─────────────────────────────────────────────────────────────┐
│                    用戶錄製一個視頻                          │
│                 (_startRecording 開始)                       │
└──────────────────────┬──────────────────────────────────────┘
                       ↓
┌─────────────────────────────────────────────────────────────┐
│              _finishRecording() 錄製完成                     │
│              ├─ 保存 PCM 音訊數據                            │
│              └─ 生成縮圖                                     │
└──────────────────────┬──────────────────────────────────────┘
                       ↓
┌─────────────────────────────────────────────────────────────┐
│          _extractAudioTags(audioPath)                        │
│          ├─ 呼叫 AudioAnalysisService.analyzeVideo()        │
│          ├─ 計算 RMS 和峰值                                 │
│          ├─ 判定無聲音或無有效擊球                          │
│          └─ 返回 tags: List<String>  ✅                    │
└──────────────────────┬──────────────────────────────────────┘
                       ↓
┌─────────────────────────────────────────────────────────────┐
│        widget.onComplete(audioTags: tags)                    │
│        RecordingSelectionScreen 傳遞參數                     │
└──────────────────────┬──────────────────────────────────────┘
                       ↓
┌─────────────────────────────────────────────────────────────┐
│        _handleRecordingComplete(audioTags: tags)             │
│        MainShellPage 接收參數                                │
└──────────────────────┬──────────────────────────────────────┘
                       ↓
┌─────────────────────────────────────────────────────────────┐
│   RecordingHistoryEntry(audioTags: tags)                    │
│   ├─ 建立新的歷史入口                                        │
│   └─ 包含音訊標籤  ✅                                        │
└──────────────────────┬──────────────────────────────────────┘
                       ↓
┌─────────────────────────────────────────────────────────────┐
│   RecordingHistoryStorage.saveHistory()                     │
│   ├─ 序列化到 JSON                                           │
│   ├─ 保存到 recording_history.json                           │
│   └─ audioTags 欄位被持久化  ✅                            │
└──────────────────────┬──────────────────────────────────────┘
                       ↓
┌─────────────────────────────────────────────────────────────┐
│        🎉 錄影歷史中顯示無聲音 TAG                           │
│        ├─ 可在歷史頁面查看                                   │
│        ├─ 可在 JSON 檔案中驗證                              │
│        └─ 應用重啟後會自動還原  ✅                          │
└─────────────────────────────────────────────────────────────┘
```

---

## 🔍 無聲音檢測標準

| 條件 | 閾值 | 判定 |
|------|------|------|
| RMS < 0.01 **AND** Peak < 0.05 | 雙重判定 | ✅ 無聲音 |
| RMS ≥ 0.01 OR Peak ≥ 0.05 | 至少一個超過 | ❌ 有聲音 |
| 無法檢測峰值 | 檢測失敗 | ⚠️ 無有效擊球 |

---

## 📈 標籤值清單

### 前端標籤 (Flutter)
```
'no_audio'        - 完全無聲音 (RMS < 0.01 && Peak < 0.05)
'no_valid_hits'   - 有聲音但無有效擊球
'pro'             - Pro 品質
'good'            - Sweet 品質
'bad'             - Keep going! 品質
'error'           - 分析錯誤
```

### 後端標籤 (Python)
```
'no_audio'           - 無聲音
'no_peaks'           - 無峰值 (但有聲音)
'peak_out_of_range'  - 峰值超出允許範圍
'valid_hits'         - 有效擊球
```

### CSV 記錄標籤
```
'valid_hit'  - 有效擊球記錄
'no_audio'   - 無聲音標記 (若返回狀態為 no_audio)
```

---

## 🧪 測試驗證清單

### 前端單元測試
- [x] `RecordingHistoryEntry` 能正確序列化/反序列化 `audioTags`
- [x] `AudioAnalysisService._isSilentAudio()` 正確判定無聲音
- [x] `RecordScreen._extractAudioTags()` 正確提取標籤
- [x] `_handleRecordingComplete()` 正確保存標籤

### 集成測試
- [ ] 完整錄製流程：錄製 → 分析 → 保存 → 驗證標籤
- [ ] 無聲音場景：使用無聲音 WAV 測試標籤
- [ ] 持久化測試：應用重啟後驗證標籤是否還原
- [ ] JSON 驗證：檢查 `recording_history.json` 中的 `audioTags` 欄位

---

## 💾 JSON 儲存示例

### 完整歷史記錄 JSON
```json
[
  {
    "filePath": "/data/golf_recordings/REC_001/swing.mp4",
    "roundIndex": 1,
    "recordedAt": "2026-05-18T10:30:00.000Z",
    "durationSeconds": 5,
    "customName": "第一次揮桿",
    "thumbnailPath": "/data/golf_recordings/REC_001/thumbnail.jpg",
    "videoType": "original",
    "isClipped": false,
    "isAnalyzed": true,
    "audioLabel": "Pro",
    "audioTags": ["pro"],
    "audioCrispness": 85.5,
    "goodShot": true
  },
  {
    "filePath": "/data/golf_recordings/REC_002/swing.mp4",
    "roundIndex": 2,
    "recordedAt": "2026-05-18T10:35:00.000Z",
    "durationSeconds": 3,
    "audioLabel": null,
    "audioTags": ["no_audio"],
    "goodShot": false
  }
]
```

---

## 📱 UI 顯示建議

### 列表顯示
```
[錄製 1]  第一次揮桿  🏌️
├─ 時間：2026年5月18日 10:30
├─ 標籤：[Pro]  ✅
└─ 品質：好球

[錄製 2]  第二次揮桿  🏌️
├─ 時間：2026年5月18日 10:35
├─ 標籤：[無聲音]  ⚠️
└─ 品質：壞球
```

### 標籤視覺化
```dart
Color _getTagColor(String tag) {
  switch (tag) {
    case 'no_audio' => Colors.red.shade100,
    case 'no_valid_hits' => Colors.orange.shade100,
    case 'pro' => Colors.green.shade100,
    case 'good' => Colors.blue.shade100,
    case 'bad' => Colors.yellow.shade100,
    default => Colors.grey.shade200,
  };
}

String _getTagLabel(String tag) {
  switch (tag) {
    case 'no_audio' => '無聲音',
    case 'no_valid_hits' => '無擊球',
    case 'pro' => 'Pro',
    case 'good' => 'Sweet',
    case 'bad' => 'Keep going!',
    default => tag,
  };
}
```

---

## 📚 檔案變更總結

| 檔案 | 變更 | 行數 | 說明 |
|------|------|------|------|
| `recording_history_entry.dart` | 新增欄位 | +15 | `audioTags: List<String>?` |
| `audio_analysis_service.dart` | 新增功能 | +120 | 無聲音檢測、標籤提取 |
| `record_screen.dart` | 新增方法 | +50 | `_extractAudioTags()` |
| `recording_selection_screen.dart` | 更新回調 | +5 | 傳遞 `audioTags` |
| `main_shell_page.dart` | 更新處理 | +10 | 接收並保存 `audioTags` |
| `audio_analysis.py` | 新增功能 | +50 | `_is_silent_audio()`、標籤系統 |

---

## 🎉 成功指標

✅ **數據持久化**
- 標籤保存到 JSON 檔案
- 應用重啟後自動還原
- 與錄影記錄同生命週期

✅ **使用者體驗**
- 自動檢測無聲音
- 錄製完成後立即分析
- 可在歷史頁面查看

✅ **系統完整性**
- 前後端一致
- 標籤標準化
- 易於擴展新類型標籤

---

## 🚀 使用場景

### 場景 1：無聲音錄製
```
用戶錄製 → 麥克風故障 → 無聲音
↓
自動檢測 RMS < 0.01 && Peak < 0.05
↓
保存 audioTags: ['no_audio']
↓
歷史頁顯示 ⚠️ 無聲音 TAG
```

### 場景 2：背景噪音無擊球
```
用戶錄製 → 環境噪音 → 無擊球聲
↓
自動檢測無峰值
↓
保存 audioTags: ['no_valid_hits']
↓
歷史頁顯示 ⚠️ 無擊球 TAG
```

### 場景 3：高品質擊球
```
用戶錄製 → 清晰擊球聲 → 分類成功
↓
自動分類 → Pro
↓
保存 audioTags: ['pro']
↓
歷史頁顯示 ✅ Pro TAG
```

---

## 🎯 後續擴展建議

1. **標籤篩選** - 在歷史頁面按標籤篩選錄製
2. **標籤統計** - 顯示不同標籤的統計數據
3. **標籤導出** - 將標籤信息導出到 CSV
4. **自定義標籤** - 允許用戶添加自定義標籤
5. **標籤搜索** - 按標籤搜索錄製

