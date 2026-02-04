# 錄影歷史 - 雲端與本地列表合併指南

## 🔍 概述

`RecordingHistoryPage` 會同時取得：
- ✅ **本地列表**：從設備存儲載入
- ☁️ **雲端列表**：從 API 服務器獲取（已建立在 Entry 中）

然後進行 **去重 + 合併**，顯示統一視圖。

---

## 📊 數據結構

### RecordingHistoryEntry 字段

```dart
class RecordingHistoryEntry {
  // 唯一識別
  final String filePath;              // 本地路徑
  final String? cloudVideoId;         // 雲端 ID（已上傳時有值）
  
  // 影片類型和位置
  final VideoType videoType;          // original / localClip / cloudOriginal / cloudClip
  final String? sourceLocalFilePath;  // 雲端影片對應的本地來源路徑
  
  // 同步狀態
  final UploadStatus uploadStatus;    // local / uploading / uploaded / failed
  final SyncStatus syncStatus;        // synced / notSynced / syncing / failed
  
  // 其他元數據
  final DateTime recordedAt;
  final String? customName;
  final String? thumbnailPath;
  final Map<String, String> imuCsvPaths;
}
```

### 雲端影片類型

| VideoType | 含義 | 來源 | 特性 |
|-----------|------|------|------|
| `original` | 本地原始影片 | 本地設備 | 完整錄影 |
| `localClip` | 本地切片 | 本地設備 | 分割出的擊球片段 |
| `cloudOriginal` | 雲端原始影片 | API 服務器 | 已上傳的完整錄影 |
| `cloudClip` | 雲端切片 | API 服務器 | 雲端切分的片段 |

---

## 🔄 合併邏輯（當前實現）

### 第一步：載入本地列表

**文件**：`lib/services/recording_history_storage.dart`

```dart
Future<List<RecordingHistoryEntry>> loadHistory() async {
  // 從本地 SharedPreferences 或 SQLite 載入
  // 返回所有 VideoType.original 和 VideoType.localClip
  return localEntries;
}
```

**代碼位置**：[home_page.dart#L560](home_page.dart#L560)

```dart
Future<void> _loadInitialHistory() async {
  final entries = await RecordingHistoryStorage.instance.loadHistory();
  final regenerated = await _cleanInvalidThumbnails(entries);
  final finalEntries = regenerated ?? entries;

  setState(() {
    _recordingHistory
      ..clear()
      ..addAll(finalEntries);  // ✅ 添加本地列表
  });
}
```

### 第二步：載入雲端列表（待實現）

**建議的 API 調用**：

```dart
Future<void> _loadCloudHistory() async {
  try {
    final token = await AuthTokenStorage.instance.getToken();
    if (token == null) return; // 未登入，跳過

    final cloudEntries = await VideoServerClient.instance.listVideos(
      token: token,
      memberId: _memberId,
    );
    
    // cloudEntries 應返回 VideoType.cloudOriginal 和 cloudClip
    if (!mounted) return;
    setState(() {
      _recordingHistory.addAll(cloudEntries); // ✅ 添加雲端列表
    });
  } catch (e) {
    debugPrint('❌ 載入雲端列表失敗：$e');
  }
}
```

### 第三步：去重和排序

```dart
Future<void> _mergeHistoryLists(
  List<RecordingHistoryEntry> localList,
  List<RecordingHistoryEntry> cloudList,
) async {
  final merged = <RecordingHistoryEntry>[];
  final seen = <String>{};  // 用於去重（key: filePath 或 cloudVideoId）

  // 1️⃣ 先添加本地列表（優先級高）
  for (final entry in localList) {
    final key = entry.filePath;
    if (!seen.contains(key)) {
      merged.add(entry);
      seen.add(key);
    }
  }

  // 2️⃣ 再添加雲端列表（避免重複）
  for (final cloudEntry in cloudList) {
    // 檢查是否已有對應的本地版本
    final existsLocally = localList.any((local) =>
        local.cloudVideoId == cloudEntry.cloudVideoId ||
        local.sourceLocalFilePath == cloudEntry.filePath);
    
    if (!existsLocally) {
      // ✅ 新的雲端影片，添加到列表
      if (!seen.contains(cloudEntry.filePath)) {
        merged.add(cloudEntry);
        seen.add(cloudEntry.filePath);
      }
    }
  }

  // 3️⃣ 按時間戳記排序（最新在前）
  merged.sort((a, b) => b.recordedAt.compareTo(a.recordedAt));

  if (!mounted) return;
  setState(() {
    _recordingHistory
      ..clear()
      ..addAll(merged);
  });
}
```

---

## 📌 去重策略

### 場景 1：本地影片已上傳到雲端

```
本地：
  filePath = "/local/video.mp4"
  cloudVideoId = "abc123"
  uploadStatus = uploaded

雲端：
  cloudVideoId = "abc123"
  videoType = cloudOriginal

✅ 合併結果：只保留本地版本（filePath 優先）
```

### 場景 2：新的雲端影片（未在本地）

```
本地：(無對應項)

雲端：
  cloudVideoId = "xyz789"
  videoType = cloudOriginal
  sourceLocalFilePath = null

✅ 合併結果：添加雲端版本到列表
```

### 場景 3：雲端切片 + 本地切片

```
本地：
  filePath = "/local/clip_1.mp4"
  videoType = localClip

雲端：
  cloudVideoId = "clip_abc"
  videoType = cloudClip
  sourceLocalFilePath = "/local/clip_1.mp4"

✅ 合併結果：
   - 本地切片優先顯示
   - 記錄雲端同步狀態
```

---

## 🎯 當前實現狀態

| 功能 | 狀態 | 位置 |
|------|------|------|
| ✅ 本地列表載入 | 已完成 | [home_page.dart#L560](home_page.dart#L560) |
| ☁️ 雲端列表載入 | 未完成 | - |
| 🔄 合併邏輯 | 未完成 | - |
| 🎯 去重策略 | 未完成 | - |

---

## 📝 實現建議

### 步驟 1：在 `_loadInitialHistory()` 後添加雲端加載

```dart
@override
void initState() {
  super.initState();
  _loadInitialHistory();
  _loadCloudHistory();  // ← 並行加載
}
```

### 步驟 2：建立 `_loadCloudHistory()` 方法

```dart
Future<void> _loadCloudHistory() async {
  if (_memberId == null) return; // 未登入

  try {
    final cloudVideos = await VideoServerClient.instance.listUserVideos(
      memberId: _memberId!,
    );
    
    final cloudEntries = cloudVideos
        .map((video) => RecordingHistoryEntry(
          filePath: video.videoUrl,
          cloudVideoId: video.id,
          recordedAt: video.createdAt,
          videoType: VideoType.cloudOriginal,
          // ... 其他字段
        ))
        .toList();

    if (!mounted) return;
    setState(() {
      _recordingHistory.addAll(cloudEntries);
    });
  } catch (e) {
    debugPrint('❌ 雲端列表加載失敗：$e');
  }
}
```

### 步驟 3：建立去重函數

```dart
List<RecordingHistoryEntry> _deduplicateEntries(
  List<RecordingHistoryEntry> entries,
) {
  final seen = <String>{};
  final result = <RecordingHistoryEntry>[];

  // 優先本地，再加雲端
  for (final entry in entries) {
    final key = entry.cloudVideoId ?? entry.filePath;
    if (!seen.contains(key)) {
      result.add(entry);
      seen.add(key);
    }
  }

  return result..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
}
```

---

## 🔗 相關服務

- **本地存儲**：[recording_history_storage.dart](recording_history_storage.dart)
- **雲端 API**：[video_server_client.dart](video_server_client.dart)
- **身份驗證**：[auth_token_storage.dart](auth_token_storage.dart)
- **UI 展示**：[recording_history_page.dart](recording_history_page.dart)

---

## ⚠️ 注意事項

1. **網路延遲**：雲端加載可能較慢，建議使用 `FutureBuilder` 顯示加載中狀態
2. **離線模式**：若無網路連接，只顯示本地列表
3. **去重鍵**：使用 `cloudVideoId` 和 `sourceLocalFilePath` 識別同一影片
4. **時間同步**：本地和雲端的時間戳記應保持一致
