# 影片上傳與建檔實現總結

## 功能概述

實現了一個完整的影片錄製、建檔、上傳工作流程，包括：
1. ✅ 錄影完成後自動彈窗提示上傳選項
2. ✅ 支持三種上傳模式：影片上傳、軌跡上傳、全部上傳
3. ✅ 自動切片機制（使用 SwingSplitService）
4. ✅ 自動縮圖生成
5. ✅ 軌跡數據（IMU CSV）支持
6. ✅ 在錄影歷史頁面修改上傳按鈕以支持選擇性上傳

---

## 實現細節

### 1. 錄影會話頁面 (`recording_session_page.dart`)

#### 新增方法：`_showUploadDialog()`
在錄影保存完成後，顯示彈窗提供用戶上傳選項：
- **稍後上傳** - 關閉對話框，文件已保存到本地
- **上傳影片** - 調用 `_uploadRecordingWithVideo()`
- **上傳軌跡** - 調用 `_uploadRecordingWithTrajectory()`
- **上傳全部** - 調用 `_uploadRecordingWithBoth()`

#### 新增方法：`_uploadRecordingWithVideo()`
- 執行視頻切片操作（使用 `SwingSplitService.split()`）
- 自動檢測擊棒並生成多個切片
- 提供用戶反饋（分割完成消息）
- 不上傳軌跡數據和縮圖

#### 新增方法：`_uploadRecordingWithTrajectory()`
- 檢查是否存在 IMU CSV 文件
- 驗證軌跡數據的有效性
- 為後續上傳做準備

#### 新增方法：`_uploadRecordingWithBoth()`
- 結合上述兩種操作
- 分割視頻並準備所有數據
- 為完整上傳做準備

#### 修改方法：`_stopRecordingAndSave()`
在 finally 塊中添加：
```dart
// Show upload dialog after recording is saved
if (mounted) {
  _showUploadDialog(entry);
}
```

### 2. 錄影歷史頁面 (`recording_history_page.dart`)

#### 修改方法簽名：`_uploadEntry()`
```dart
Future<void> _uploadEntry(RecordingHistoryEntry entry, {
  String? uploadType, // 'video', 'trajectory', or null for full upload
}) async
```

#### 上傳邏輯優化
根據 `uploadType` 參數有選擇地執行上傳步驟：

- **uploadType = 'video'** 
  - 只上傳視頻文件和縮圖
  - 跳過 CSV 文件上傳

- **uploadType = 'trajectory'**
  - 只上傳 CSV 文件（IMU 數據）
  - 跳過視頻和縮圖上傳

- **uploadType = null**（預設，完整上傳）
  - 上傳視頻、CSV 文件和縮圖

條件檢查：
```dart
// 2. 上傳視頻文件（除非只上傳軌跡）
if (uploadType != 'trajectory') { ... }

// 2.5 上傳 CSV 文件（除非只上傳影片）
if (uploadType != 'video') { ... }

// 2.6 上傳縮略圖（除非只上傳軌跡）
if (uploadType != 'trajectory') { ... }
```

---

## 關鍵特性

### 視頻切片
- 利用現有的 `SwingSplitService.split()` 方法
- 參數配置：
  - `windowBeforeSec = 3.0` - 擊棒前 3 秒
  - `windowAfterSec = 1.0` - 擊棒後 1 秒
  - `threshG = 20.0` - 加速度閾值 20G
- 返回 `List<SwingClipResult>` - 包含每個切片的詳細信息

### 縮圖生成
- 使用 `video_thumbnail` 套件
- 從視頻第 0 毫秒提取 JPEG 縮圖
- 品質設置：75
- 自動路徑生成：`{baseName}_thumb.jpg`

### IMU 數據支持
- 支持多個 IMU 源（RIGHT_WRIST, CHEST 等）
- 存儲在 `RecordingHistoryEntry.imuCsvPaths` Map 中
- 按標籤分別上傳到服務器

---

## 工作流程

### 錄影端（Recording Session）
```
1. 用戶完成錄影
   ↓
2. _stopRecordingAndSave() 執行
   ↓
3. 保存視頻和 IMU 數據到本地
   ↓
4. 生成縮圖
   ↓
5. 顯示 _showUploadDialog() 彈窗
   ↓
6. 用戶選擇上傳選項
   ↓
7. 如選擇上傳，執行相應的 _uploadRecording...() 方法
```

### 歷史頁面（Recording History）
```
1. 用戶點擊上傳按鈕
   ↓
2. _uploadEntry(entry, uploadType: '...') 被調用
   ↓
3. 在服務器上建立視頻紀錄（若尚未綁定）
   ↓
4. 根據 uploadType 有選擇地上傳：
   - 視頻文件
   - CSV 文件（軌跡數據）
   - 縮圖
   ↓
5. 標記上傳完成
   ↓
6. 更新本地狀態為 SyncStatus.synced
```

---

## 數據流向

### 錄製完成後的狀態
```
RecordingHistoryEntry {
  filePath: '/path/REC_20260205123456.mp4',
  imuCsvPaths: {
    'RIGHT_WRIST': '/path/REC_20260205123456_RIGHT_WRIST.csv',
    'CHEST': '/path/REC_20260205123456_CHEST.csv',
  },
  thumbnailPath: '/path/REC_20260205123456_thumb.jpg',
  durationSeconds: 45,
  recordedAt: DateTime.now(),
}
```

### 切片生成後的狀態
```
SwingClipResult {
  tag: 'hit_001',
  hitSecond: 15.3,
  startSecond: 12.3,
  endSecond: 16.3,
  peakValue: 32.5,  // G
  videoPath: '/path/cut/hit_001.mp4',
  csvPath: '/path/cut/hit_001_imu.csv',
  goodShot: true,
  badShot: false,
}
```

---

## 錯誤處理

### 在錄影會話中
- 檢查 IMU 數據是否存在
- 處理切片失敗情況
- 提供用戶友善的錯誤消息

### 在歷史頁面中
- 401 未授權 → 導航到登入頁面
- 文件不存在 → 提示用戶
- 上傳失敗 → 保存錯誤信息並允許重試

---

## 測試檢查清單

- [ ] 錄影完成後彈窗正常顯示
- [ ] 四個按鈕功能正常
- [ ] 視頻分割成功
- [ ] 縮圖生成無誤
- [ ] 軌跡數據驗證正確
- [ ] 歷史頁面上傳按鈕支持三種上傳模式
- [ ] 登入驗證機制正常
- [ ] 錯誤恢復流程正確

---

## 未來改進方向

1. **進度跟蹤** - 實現上傳進度條
2. **批量操作** - 支持多個錄影同時上傳
3. **斷點續傳** - 支持網絡中斷後續傳
4. **本地快取** - 未連接時本地保存上傳隊列
5. **後台上傳** - 使用 WorkManager 實現後台上傳
6. **雲端同步** - 實時同步雲端端狀態

---

## 相關文件

- `lib/pages/recording_session_page.dart` - 錄影頁面
- `lib/pages/recording_history_page.dart` - 歷史頁面
- `lib/services/swing_split_service.dart` - 切片服務
- `lib/models/recording_history_entry.dart` - 數據模型
- `lib/services/video_server_client.dart` - 服務器通信

---

## 版本信息

- **實現日期** 2026-02-05
- **狀態** 已完成功能實現
- **測試狀態** 待驗證
