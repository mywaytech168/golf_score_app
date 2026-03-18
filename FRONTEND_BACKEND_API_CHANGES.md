# 前後端 API 改動分析

## 需求概述
前端在上傳影片紀錄時需要新增以下字段：

### 原始影片切成切片時需要的字段
- `HitSecond` - 擊球時刻（秒數）
- `StartSecond` - 切片開始秒數
- `EndSecond` - 切片結束秒數

### 軌跡峰值字段
- `PeakValue` - 該軌跡的峰值

---

## 前端改動清單

### 1. 修改 RecordingHistoryEntry 模型
**檔案**: `lib/models/recording_history_entry.dart`

**新增字段**:
```dart
class RecordingHistoryEntry {
  // ... 現有字段 ...
  
  /// 擊球時刻（秒數），用於切片標識
  final double? hitSecond;
  
  /// 切片開始秒數
  final double? startSecond;
  
  /// 切片結束秒數
  final double? endSecond;
  
  /// 軌跡的峰值（對應 imuCsvPaths 中的軌跡）
  /// 鍵為軌跡標籤（如 'chest'、'right_wrist'），值為峰值
  final Map<String, double>? peakValues;
}
```

**需要更新的方法**:
- ✅ `copyWith()` - 新增參數
- ✅ `toJson()` - 序列化新字段
- ✅ `fromJson()` - 反序列化新字段

### 2. 修改上傳流程
**檔案**: `lib/pages/recording_history_page.dart`

**在 `_uploadEntry()` 方法中**:

#### 步驟 1：建立視頻紀錄時傳送新字段
```dart
// 修改 createVideo 呼叫
final createResponse = await serverClient.createVideo(
  name: entry.displayTitle,
  type: 'original',
  // 新增字段
  hitSecond: entry.hitSecond,
  startSecond: entry.startSecond,
  endSecond: entry.endSecond,
);
```

#### 步驟 2：上傳 CSV 文件時傳送峰值
```dart
// 在上傳 CSV 時加入峰值信息
if (uploadType != 'video') {
  for (final csvEntry in entry.imuCsvPaths.entries) {
    final csvLabel = csvEntry.key;
    final csvPath = csvEntry.value;
    final peakValue = entry.peakValues?[csvLabel] ?? 0.0;
    
    final csvResponse = await serverClient.uploadVideoFile(
      videoId: videoId,
      videoFilePath: csvPath,
      fileType: csvLabel.toLowerCase(),
      sourceLocalFilePath: csvPath,
      peakValue: peakValue,  // 新增
    );
  }
}
```

### 3. 修改 VideoServerClient API 方法
**檔案**: `lib/services/video_server_client.dart`

#### 方法 1：updateCreateVideo()
```dart
Future<Map<String, dynamic>> createVideo({
  required String name,
  required String type,
  String? parentVideoId,
  // 新增參數
  double? hitSecond,
  double? startSecond,
  double? endSecond,
}) async {
  final response = await http.post(
    url,
    headers: headers,
    body: jsonEncode({
      'name': name,
      'type': type,
      if (parentVideoId != null) 'parentVideoId': parentVideoId,
      // 新增字段
      if (hitSecond != null) 'hitSecond': hitSecond,
      if (startSecond != null) 'startSecond': startSecond,
      if (endSecond != null) 'endSecond': endSecond,
    }),
  );
}
```

#### 方法 2：updateUploadVideoFile()
```dart
Future<Map<String, dynamic>> uploadVideoFile({
  required String videoId,
  required String videoFilePath,
  required String fileType,
  required String sourceLocalFilePath,
  // 新增參數
  double? peakValue,
}) async {
  // 在 FormData 或 request body 中加入 peakValue
  // 根據後端期望的傳送方式調整
}
```

---

## 後端改動清單

### 1. 修改 Video 模型/Schema
**需要更新的字段**:
```
✅ hitSecond (double, nullable)
✅ startSecond (double, nullable)
✅ endSecond (double, nullable)
```

### 2. 修改 API 端點

#### POST /api/videos (建立視頻紀錄)
**請求 Body**:
```json
{
  "name": "string",
  "type": "original|clip",
  "parentVideoId": "string (optional)",
  "hitSecond": "double (optional)",
  "startSecond": "double (optional)",
  "endSecond": "double (optional)"
}
```

**需要做的事**:
- ✅ 接收新參數
- ✅ 驗證秒數邏輯（startSecond < hitSecond < endSecond）
- ✅ 保存到數據庫

#### POST /api/videos/{videoId}/files (上傳檔案)
**現有支持**:
- 視頻檔案上傳
- CSV 檔案上傳
- 縮圖上傳

**需要新增**:
- 在上傳 CSV 時傳送該軌跡的峰值
- 可選方案：
  - **方案 A**: 在 Form 中增加 `peakValue` 字段
  - **方案 B**: 增加新的 API 端點用於更新軌跡信息
  - **方案 C**: 在標記完成時傳送所有軌跡峰值

### 3. 修改處理隊列儲存
**需要確保**:
- ✅ 切片時能讀取到 `hitSecond`、`startSecond`、`endSecond`
- ✅ 切片時能讀取到各軌跡的 `peakValue`
- ✅ 這些值被正確保存在相應的切片紀錄中

---

## 數據流圖

```
前端：錄影紀錄
  ├─ 影片信息（filePath、duration 等）
  ├─ 新增：hitSecond、startSecond、endSecond
  └─ 新增：peakValues (chest/right_wrist -> peak value)
      ↓
API: POST /api/videos
  ├─ 建立視頻紀錄
  ├─ 保存 hitSecond、startSecond、endSecond
  └─ 返回 videoId
      ↓
API: POST /api/videos/{videoId}/files
  ├─ 上傳視頻檔案
  ├─ 上傳 CSV 檔案（帶 peakValue）
  └─ 上傳縮圖
      ↓
API: POST /api/videos/{videoId}/complete
  └─ 標記上傳完成，觸發切片隊列
      ↓
後端：切片隊列處理
  ├─ 讀取 hitSecond、startSecond、endSecond
  ├─ 讀取各軌跡的 peakValue
  └─ 執行切片邏輯
```

---

## 實作優先級

### 高優先級（必需）
1. ✅ RecordingHistoryEntry 新增字段
2. ✅ createVideo API 傳送時間字段
3. ✅ 後端 Video 模型更新

### 中優先級（建議）
1. ✅ 計算並填入 peakValue
2. ✅ uploadVideoFile 傳送峰值
3. ✅ 後端儲存峰值信息

### 低優先級（優化）
1. ✅ UI 中新增這些字段的編輯介面
2. ✅ 驗證邏輯（秒數合理性檢查）
3. ✅ 錯誤處理和重試邏輯

---

## 驗證檢查清單

- [ ] RecordingHistoryEntry 包含所有新字段
- [ ] copyWith() 正確處理新字段
- [ ] toJson()/fromJson() 正確序列化/反序列化
- [ ] createVideo() 傳送新參數
- [ ] uploadVideoFile() 傳送 peakValue
- [ ] 後端 API 接收並驗證新字段
- [ ] 數據庫模式支持新字段
- [ ] 切片邏輯正確使用新字段
- [ ] 單元測試覆蓋新字段
- [ ] 集成測試驗證端對端流程
