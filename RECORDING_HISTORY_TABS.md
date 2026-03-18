# 錄影歷史 TAB 功能指南

## 🎬 錄影歷史頁面新增 TAB 篩選功能

已為錄影歷史頁面添加與軌跡歷史相同的 TAB 篩選邏輯，允許用戶按影片類型進行篩選。

## 📋 功能概述

### TAB 選項

| 圖標 | 標籤 | 說明 |
|------|------|------|
| 🎥 | 本地原始影片 | 直接從應用錄製的原始影片 |
| ✂️ | 本地切片 | 本地分片後的影片片段 |
| ☁️ | 雲端切片 | 上傳至雲端的影片片段 |

### 影片卡片信息

每個影片卡片現在顯示：

1. **影片類型圖標** - 🎥/✂️/☁️ 快速識別
2. **同步狀態徽章** - 色碼標示：
   - ✓ 已同步 (綠色) - 已上傳到雲端
   - ↻ 未同步 (藍色) - 本地還未同步
   - ⟳ 同步中 (橙色) - 正在同步中
   - ✗ 失敗 (紅色) - 同步失敗

3. **基本信息**：
   - 影片名稱（可自訂）
   - 錄製時間
   - 影片時長
   - 錄製模式（含/不含 IMU）
   - 檔案名稱

## 🔄 使用流程

```
打開錄影歷史頁面
    ↓
選擇 TAB：本地原始/本地切片/雲端切片
    ↓
查看篩選後的影片清單
    ↓
查看同步狀態
    ↓
執行操作（播放/編輯/刪除）
```

## 💾 代碼實現

### 1. 模型更新 (`RecordingHistoryEntry`)

添加了新的枚舉和欄位：

```dart
/// 影片類型
enum VideoType {
  original,      // 本地原始影片
  localClip,     // 本地切片
  cloudClip;     // 雲端切片
  
  String get label { ... }  // 中文標籤
  String get icon { ... }   // 圖標
}

/// 同步狀態
enum SyncStatus {
  synced,        // 已同步
  notSynced,     // 未同步
  syncing,       // 同步中
  failed;        // 失敗
  
  String get label { ... }        // 中文標籤
  Color get badgeColor { ... }    // 徽章顏色
}

// 在 RecordingHistoryEntry 中添加：
final VideoType videoType;        // 影片類型
final SyncStatus syncStatus;      // 同步狀態
```

### 2. 頁面更新 (`RecordingHistoryPage`)

#### 狀態管理

```dart
class _RecordingHistoryPageState extends State<RecordingHistoryPage> {
  late List<RecordingHistoryEntry> _entries;
  VideoType _selectedFilter = VideoType.original;  // 預設篩選
  
  // 篩選方法
  List<RecordingHistoryEntry> _getFilteredEntries() {
    return _entries
        .where((entry) => entry.videoType == _selectedFilter)
        .toList();
  }
}
```

#### UI 布局

```dart
Column(
  children: [
    // TAB 篩選選項卡
    SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: VideoType.values.map((type) {
          return FilterChip(
            label: Text('${type.icon} ${type.label}'),
            selected: _selectedFilter == type,
            onSelected: (selected) {
              setState(() {
                _selectedFilter = type;
              });
            },
          );
        }).toList(),
      ),
    ),
    // 篩選後的影片列表
    Expanded(
      child: ListView.builder(
        itemCount: filteredEntries.length,
        itemBuilder: (context, index) {
          // 影片卡片
        },
      ),
    ),
  ],
)
```

#### 影片卡片顯示

每個卡片現在包括：

```dart
Row(
  children: [
    Expanded(
      child: Column(
        children: [
          // 標題 + 同步狀態徽章
          Row(
            children: [
              Expanded(child: Text(entry.displayTitle)),
              // 同步狀態徽章
              Container(
                decoration: BoxDecoration(
                  color: entry.syncStatus.badgeColor.withAlpha(30),
                  border: Border.all(
                    color: entry.syncStatus.badgeColor,
                  ),
                ),
                child: Text(entry.syncStatus.label),
              ),
            ],
          ),
          // 時間、時長、模式
          Text('$formattedTime · ${entry.durationSeconds} 秒 · ${entry.modeLabel}'),
          // 影片類型 + 檔名
          Row(
            children: [
              Text('${entry.videoType.icon} ${entry.videoType.label}'),
              Text(entry.fileName),
            ],
          ),
        ],
      ),
    ),
  ],
)
```

## 🎯 影片類型和同步狀態的映射

### 預設值

- **新建錄影**：`VideoType.original`, `SyncStatus.notSynced`
- **本地分片**：`VideoType.localClip`, `SyncStatus.notSynced`
- **上傳後**：`VideoType.cloudClip`, `SyncStatus.synced`

### 狀態轉換流程

```
錄製原始影片
  ↓ (VideoType.original, SyncStatus.notSynced)
  ↓
用戶點擊上傳
  ↓ (VideoType.original, SyncStatus.syncing)
  ↓
上傳成功
  ↓ (VideoType.original 或 cloudClip, SyncStatus.synced)

本地分片
  ↓ (VideoType.localClip, SyncStatus.notSynced)
  ↓
上傳分片
  ↓ (VideoType.cloudClip, SyncStatus.synced)
```

## 📊 JSON 序列化

模型的 `toJson()` 和 `fromJson()` 方法已更新以支持新欄位：

```dart
Map<String, dynamic> toJson() {
  return {
    // ... 其他欄位 ...
    'videoType': videoType.name,      // 'original', 'localClip', 'cloudClip'
    'syncStatus': syncStatus.name,    // 'synced', 'notSynced', 'syncing', 'failed'
  };
}

factory RecordingHistoryEntry.fromJson(Map<String, dynamic> json) {
  // 解析 VideoType
  VideoType videoType = VideoType.original;
  final videoTypeStr = json['videoType'] as String?;
  if (videoTypeStr != null) {
    videoType = VideoType.values.byName(videoTypeStr);
  }
  
  // 解析 SyncStatus
  SyncStatus syncStatus = SyncStatus.notSynced;
  final syncStatusStr = json['syncStatus'] as String?;
  if (syncStatusStr != null) {
    syncStatus = SyncStatus.values.byName(syncStatusStr);
  }
  
  return RecordingHistoryEntry(
    // ... 其他欄位 ...
    videoType: videoType,
    syncStatus: syncStatus,
  );
}
```

## ✅ 編譯狀態

- ✅ `RecordingHistoryPage` - 編譯成功
- ✅ `RecordingHistoryEntry` - 編譯成功
- ✅ `HomePage` - 編譯成功
- ✅ 無編譯錯誤

## 🚀 使用方式

### 在首頁打開錄影歷史

```dart
// 在 HomePage 中
await Navigator.of(context).push<List<RecordingHistoryEntry>>(
  MaterialPageRoute(
    builder: (_) => RecordingHistoryPage(entries: historyData),
  ),
);
```

### 篩選影片

用戶可以在錄影歷史頁面頂部點擊 TAB 來篩選：
1. 🎥 本地原始影片
2. ✂️ 本地切片
3. ☁️ 雲端切片

### 查看同步狀態

每個影片卡片上方顯示顏色編碼的同步狀態：
- 綠色 = ✓ 已同步
- 藍色 = ↻ 未同步
- 橙色 = ⟳ 同步中
- 紅色 = ✗ 失敗

## 📝 後續改進

可以考慮的改進項目：

1. **影片縮圖** - 為不同類型顯示不同的默認圖標
2. **拖動排序** - 允許用戶重新排序影片
3. **批量操作** - 同時選擇多個影片進行操作
4. **快速篩選** - 按同步狀態篩選（已同步/未同步）
5. **實時同步指示** - 顯示同步進度百分比
6. **搜尋功能** - 按名稱或日期搜尋影片

---

**現在錄影歷史頁面支持完整的 TAB 篩選和同步狀態顯示！** 🎉
