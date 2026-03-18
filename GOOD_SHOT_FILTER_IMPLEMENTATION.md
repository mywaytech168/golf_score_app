# Good Shot (好球/壞球) 過濾實現

## 概述
已實現在錄影歷史中獲取和顯示 `goodShot` 數據，用於區分好球和壞球，並支援過濾功能。

## 實現詳情

### 1. RecordingHistoryEntry 數據模型
- **字段**：`final bool? goodShot;` 
- **位置**：lib/models/recording_history_entry.dart
- 可為 null（未分類）、true（好球）、false（壞球）

### 2. 數據來源

#### 從雲端同步
當從雲端同步視頻時，會從 API 響應中提取 `goodShot` 信息：
```dart
// lib/pages/recording_history_page.dart (line ~2164)
if (videoDetail['goodShot'] != null) {
  goodShot = videoDetail['goodShot'] as bool?;
}
```

### 3. 過濾機制

#### 錄影歷史頁面（Recording History Page）
- **位置**：lib/pages/recording_history_page.dart
- **功能**：
  - `_selectedGoodShot` 變數：存儲用戶選擇的過濾條件
    - null：顯示全部
    - true：只顯示好球
    - false：只顯示壞球
  
- **過濾邏輯**（line ~2319）：
```dart
final filteredEntries = _selectedGoodShot == null
    ? _entries
    : _entries.where((entry) => entry.goodShot == _selectedGoodShot).toList();
```

- **UI 按鈕**（line ~2360）：
  - 「全部」按鈕：`_selectedGoodShot = null`
  - 「好球」按鈕：`_selectedGoodShot = true`
  - 「壞球」按鈕：`_selectedGoodShot = false`

### 4. UI 指示器

#### 錄影歷史列表中的徽章
**位置**：lib/pages/recording_history_page.dart (_HistoryTile 組件)
- **外觀**：顏色徽章，顯示在狀態徽章區域
- **綠色**（✓ 好球）：goodShot == true
- **紅色**（✗ 壞球）：goodShot == false
- **隱藏**：goodShot == null（未分類）

#### 首頁視頻卡片中的徽章
**位置**：lib/pages/home_page.dart (_buildVideoTile 方法)
- **外觀**：卡片左上角的標籤
- **綠色背景**（好球）：goodShot == true
- **紅色背景**（壞球）：goodShot == false
- **灰色背景**（未分類）：goodShot == null

### 5. API 集成

#### getVideoDetail() 方法
- **位置**：lib/services/video_server_client.dart
- **功能**：獲取單個視頻詳細信息，包括 goodShot 字段

#### 後端 API 要求
後端視頻詳情 API 需要返回 goodShot 字段：
```json
{
  "success": true,
  "data": {
    "id": 123,
    "name": "視頻名稱",
    "goodShot": true,  // 或 false、null
    ...
  }
}
```

## 使用流程

### 在錄影歷史頁面過濾
1. 用戶打開「錄影歷史」頁面
2. 點擊「好球」、「壞球」或「全部」按鈕進行過濾
3. 列表會根據 goodShot 值進行過濾和顯示

### 查看 goodShot 狀態
- **首頁**：每個視頻卡片左上角顯示 goodShot 狀態徽章
- **錄影歷史**：每個列表項在狀態徽章區域顯示 goodShot 指示器

## 數據流
```
後端 API (VideoController)
    ↓
VideoServerClient.getVideoDetail()
    ↓
取得 JSON 中的 goodShot 字段
    ↓
RecordingHistoryEntry.copyWith(goodShot: value)
    ↓
UI 顯示和過濾
```

## 限制和注意事項
1. **數據來源**：goodShot 數據僅來自後端 API，本地視頻默認 goodShot = null
2. **同步狀態**：只有雲端同步的視頻才能獲得 goodShot 信息
3. **實時更新**：需要手動重新同步才能獲得最新的 goodShot 值

## 相關文件
- `lib/models/recording_history_entry.dart` - 數據模型
- `lib/services/video_server_client.dart` - API 客戶端
- `lib/pages/recording_history_page.dart` - 錄影歷史頁面（含過濾和UI）
- `lib/pages/home_page.dart` - 首頁視頻庫顯示

## 未來改進
- [ ] 支援在首頁也顯示過濾按鈕
- [ ] 新增「自動同步更新 goodShot」功能
- [ ] 支援批量編輯 goodShot 值
- [ ] 新增 goodShot 統計信息（好球率）
