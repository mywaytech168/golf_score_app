# 雲端列表同步與去重實現

## 功能說明

在加載錄影歷史列表時，系統會自動：
1. ✅ 先從 API 獲取雲端錄影列表
2. ✅ 與本地列表進行對比去重
3. ✅ 標記有雲端綁定的項目
4. ✅ 自動保存更新後的本地列表

---

## 實現細節

### 1. 初始化流程 (`_RecordingHistoryPageState`)

在 `initState()` 中自動調用：
```dart
@override
void initState() {
  super.initState();
  // 初始化時從雲端同步錄影列表
  _syncWithCloudEntries();
}
```

### 2. 雲端同步方法：`_syncWithCloudEntries()`

**流程：**
```
1. 檢查登入狀態
   ↓
2. 若未登入 → 返回（跳過同步）
   ↓
3. 調用 API: serverClient.getVideos(limit: 100)
   ↓
4. 解析雲端列表
   ↓
5. 調用 _mergeCloudAndLocalEntries() 進行合併
   ↓
6. 保存更新後的列表
```

**狀態管理：**
- 設置 `_isLoadingCloudList = true` 開始同步
- 設置 `_isLoadingCloudList = false` 完成同步
- 可用於在 UI 顯示載入動畫

### 3. 列表合併方法：`_mergeCloudAndLocalEntries()`

**去重策略：**

1. **構建雲端映射**
   - 使用視頻 ID 作為主鍵
   - 使用視頻名稱作為備選鍵
   ```
   cloudVideoMap = {
     'video-id-123': {...video data...},
     'Video Name': {...video data...},
   }
   ```

2. **匹配本地項目**
   - 首先按 ID 匹配（精確匹配）
   - 如無 ID，按名稱匹配（精確 + 模糊匹配）

3. **更新本地條目**
   ```dart
   _entries[i] = _entries[i].copyWith(
     cloudVideoId: videoId,
     syncStatus: SyncStatus.synced,
   );
   ```

4. **保存本地狀態**
   ```dart
   await RecordingHistoryStorage.instance.saveHistory(_entries);
   ```

### 4. 名稱匹配方法：`_findCloudVideoByName()`

**匹配規則：**
- ✓ 精確匹配：本地名稱 = 雲端名稱
- ✓ 模糊匹配：本地名稱包含在雲端名稱中，或反之
- ✗ 無匹配：返回 null

---

## 數據結構

### 雲端視頻列表格式
```json
{
  "success": true,
  "data": [
    {
      "id": "video-123",
      "name": "REC_20260205123456",
      "type": "original",
      "status": "processed",
      "createdAt": "2026-02-05T12:34:56Z"
    },
    ...
  ]
}
```

### 更新後的本地條目
```dart
RecordingHistoryEntry {
  filePath: '/path/REC_20260205123456.mp4',
  displayTitle: 'REC_20260205123456',
  cloudVideoId: 'video-123',  // 新增：從雲端綁定
  syncStatus: SyncStatus.synced,  // 新增：標記為已同步
  // ... 其他字段
}
```

---

## 錯誤處理

| 情況 | 處理方式 |
|-----|--------|
| 未登入 | 跳過同步，繼續顯示本地列表 |
| API 請求失敗 | 記錄錯誤，繼續顯示本地列表 |
| 網絡錯誤 | 記錄錯誤，繼續顯示本地列表 |
| 解析失敗 | 記錄錯誤，保持現有狀態 |

---

## 調試日誌

系統會輸出詳細的日誌幫助調試：

```
[歷史頁] 開始從雲端同步錄影列表...
[歷史頁] ✅ 從雲端獲取 5 個視頻
[歷史頁] 開始合併雲端和本地列表...
[歷史頁] ✓ 本地視頻 "REC_001" 已有雲端綁定: video-123
[歷史頁] 🔗 發現雲端視頻匹配: "REC_002" -> ID: video-456
[歷史頁] 合併完成: 共匹配 3 個雲端視頻
[歷史頁] ✅ 雲端同步完成
```

---

## 相關代碼位置

- **主實現文件**：[recording_history_page.dart](lib/pages/recording_history_page.dart)
  - `_syncWithCloudEntries()` - 雲端同步
  - `_mergeCloudAndLocalEntries()` - 列表合併
  - `_findCloudVideoByName()` - 名稱匹配

- **服務文件**：[video_server_client.dart](lib/services/video_server_client.dart)
  - `getVideos()` - 獲取雲端列表 API

- **數據模型**：[recording_history_entry.dart](lib/models/recording_history_entry.dart)
  - `cloudVideoId` - 雲端綁定 ID
  - `syncStatus` - 同步狀態

---

## 使用流程

### 用戶視角
1. 打開「錄影歷史」頁面
2. 系統自動從雲端同步列表（後台進行）
3. 列表中已有雲端綁定的項目會顯示「已同步」標記
4. 未綁定的項目可以手動上傳綁定

### 開發者視角
1. 頁面初始化時調用 `_syncWithCloudEntries()`
2. 系統自動処理同步邏輯
3. 同步完成後更新本地存儲
4. UI 自動刷新顯示最新狀態

---

## 效能考慮

- **初始化延遲**：由於涉及 API 調用，首次加載可能有 1-3 秒延遲
- **列表大小**：限制為最多 100 個視頻（可調整 `limit` 參數）
- **網絡使用**：單次 API 調用，數據量較小

**改進建議：**
- 實現分頁加載（處理超過 100 個視頻的情況）
- 添加快取機制（避免重複同步）
- 實現背景同步（不阻塞 UI）

---

## 版本信息

- **實現日期**：2026-02-05
- **狀態**：已實現
- **測試狀態**：待驗證
