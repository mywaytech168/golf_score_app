# 🚀 前端 + C# Server 實施指南

**狀態**：Phase 1 - MVP 核心代碼完成  
**完成日期**：2026-01-27  
**進度**：約 30%（前端本地系統 + Server 基礎 API）

---

## ✅ 已完成的內容

### 📁 前端 (Flutter)

#### 1. **本地資料庫** 
**檔案**：[lib/services/local_slice_repository.dart](../lib/services/local_slice_repository.dart)

- ✅ SQLite 資料庫初始化
- ✅ 本地錄影紀錄表 (`local_recordings`)
- ✅ 本地切片紀錄表 (`local_slices`) 
- ✅ 完整的 CRUD 操作方法
- ✅ 統計查詢方法

**主要方法**：
```dart
// 插入錄影與切片
insertRecording()
insertSlice()
insertSlicesBatch()

// 更新狀態
updateSliceStatus()
markSliceAsUploaded()
syncSliceStatus()

// 查詢方法
getPendingSlices()
getSlicesByRecording()
getRecordingStats()
```

#### 2. **伺服器 API 客戶端**
**檔案**：[lib/services/video_server_client.dart](../lib/services/video_server_client.dart)

- ✅ 單個切片上傳
- ✅ 批量切片上傳
- ✅ 取得影片列表
- ✅ 查詢單個影片狀態
- ✅ 建立新影片紀錄
- ✅ 重試失敗的切片

**主要方法**：
```dart
uploadSlice()           // 上傳單個切片
uploadMultipleSlices()  // 批量上傳
getVideos()            // 拉取影片列表
getVideoStatus()       // 查詢影片狀態
createVideo()          // 建立影片紀錄
retrySlice()          // 重試失敗切片
downloadSliceResult()  // 下載結果
```

#### 3. **本地切片管理 UI**
**檔案**：[lib/pages/local_slice_management_page.dart](../lib/pages/local_slice_management_page.dart)

- ✅ 展示所有本地錄影列表
- ✅ 展示每個錄影的切片統計
- ✅ 可展開/收起錄影詳情
- ✅ 批量選擇切片
- ✅ 上傳進度對話框
- ✅ 實時伺服器狀態同步（每 10 秒）

**UI 組件**：
- `LocalSliceManagementPage` - 主頁面
- `_RecordingCard` - 錄影卡片
- `_SliceDetailsSheet` - 切片詳情底部工作表
- `_UploadProgressDialog` - 上傳進度對話框

---

### 🖥️ C# Server

#### 1. **資料模型**
**檔案**：`server/Models/`

- ✅ `Video.cs` - 影片模型
- ✅ `Slice.cs` - 切片模型
- ✅ `ProcessLog.cs` - 處理日誌模型
- ✅ `ProcessQueueItem.cs` - 隊列項目模型
- ✅ `OutputFile.cs` - 輸出檔案模型

#### 2. **數據傳輸對象 (DTOs)**
**檔案**：[server/DTOs/ApiDtos.cs](../server/DTOs/ApiDtos.cs)

- ✅ `UploadSliceRequest/Response`
- ✅ `VideoStatusResponse`
- ✅ `VideoListItemDto`
- ✅ `GetVideosResponse`
- ✅ `PaginationInfo`

#### 3. **服務層**
**檔案**：[server/Services/VideoUploadService.cs](../server/Services/VideoUploadService.cs)

- ✅ 建立影片紀錄
- ✅ 上傳單個切片
- ✅ 批量上傳切片
- ✅ 取得輸出檔案列表
- ✅ 清理已完成的切片檔案

**核心方法**：
```csharp
CreateVideoAsync()       // 建立新影片
UploadSliceAsync()       // 上傳單個切片
UploadMultipleSlicesAsync() // 批量上傳
GetSliceOutputFiles()    // 取得輸出檔案
CleanupSliceAsync()      // 清理檔案
```

#### 4. **API 控制器**
**檔案**：[server/Controllers/VideoController.cs](../server/Controllers/VideoController.cs)

**已實現的端點**：

| 方法 | 端點 | 功能 | 狀態 |
|------|------|------|------|
| POST | `/api/videos/create` | 建立新影片紀錄 | ✅ |
| POST | `/api/slices/upload` | 上傳切片 | ✅ |
| GET | `/api/videos` | 取得影片列表 | ✅ 示例 |
| GET | `/api/videos/{id}/status` | 取得影片狀態 | ✅ 示例 |
| POST | `/api/slices/{id}/retry` | 重試失敗切片 | ✅ 骨架 |
| GET | `/api/slices/{id}/download/{fileName}` | 下載結果 | ⚠️ 待實現 |

#### 5. **MySQL 資料庫初始化**
**檔案**：[server/database-init.sql](../server/database-init.sql)

- ✅ Videos 表
- ✅ Slices 表
- ✅ ProcessLogs 表
- ✅ ProcessQueue 表
- ✅ OutputFiles 表
- ✅ 所有必要索引

---

## 📋 下一步行動

### Phase 2：連接前端與後端

#### 🔌 1. 實現前端 API 調用
**優先級**：⭐⭐⭐

需要在 Flutter 中完整實現：
```dart
// VideoServerClient 中的上傳邏輯
// 當前為架構，需要實現實際檔案讀取和 HTTP 上傳
uploadSlice() {
  // 需要實現：
  // 1. 檢查本地檔案是否存在
  // 2. 構造 multipart/form-data 請求
  // 3. 發送到 C# Server
  // 4. 接收 server_id 和狀態
  // 5. 更新本地 SQLite 紀錄
}
```

#### 🗄️ 2. 實現 C# Server 數據庫操作
**優先級**：⭐⭐⭐

需要：
- 設置 MySQL 連接字符串
- 實現 Entity Framework Core DbContext
- 在各個 API 端點中實現實際的資料庫 CRUD 操作

```csharp
// 範例：GetVideos 中使用真實資料庫查詢
var videos = await _context.Videos
    .Where(v => v.UserId == userId && (status == null || v.Status == status))
    .Skip((page - 1) * limit)
    .Take(limit)
    .ToListAsync();
```

#### 📡 3. 實現伺服器狀態同步
**優先級**：⭐⭐

在 Flutter 中實現定期同步邏輯：
```dart
_syncServerStatus() {
  // 定期調用 GET /api/videos
  // 比對本地 server_id 與伺服器返回的狀態
  // 更新本地切片狀態
}
```

---

## 🎯 環境配置

### 前端需求
```yaml
# pubspec.yaml 中需要添加
dependencies:
  sqflite: ^2.2.0  # SQLite 資料庫
  http: ^1.1.0     # HTTP 客戶端
  intl: ^0.18.0    # 日期格式化
  path: ^1.8.0     # 路徑操作
```

### C# Server 需求
```xml
<!-- UploadServer.csproj 中需要添加 -->
<PackageReference Include="Pomelo.EntityFrameworkCore.MySql" Version="7.0.0" />
<PackageReference Include="Microsoft.EntityFrameworkCore" Version="7.0.0" />
<PackageReference Include="Microsoft.EntityFrameworkCore.Tools" Version="7.0.0" />
```

### MySQL 資料庫設置
```bash
# 1. 在 MySQL 中執行初始化腳本
mysql -u root -p < server/database-init.sql

# 2. 更新連接字符串在 appsettings.json
"ConnectionStrings": {
  "DefaultConnection": "Server=localhost;Database=VideoSliceUploadDB;User=root;Password=your_password;"
}
```

---

## 🔗 工作流程檢查表

### ✅ 前端流程
- [ ] 本地 SQLite 資料庫初始化
- [ ] 錄製完畢後建立本地紀錄
- [ ] UI 顯示本地切片列表
- [ ] 用戶選擇並點擊「上傳」
- [ ] 實現實際上傳邏輯（讀取檔案 → HTTP 請求）
- [ ] 接收 server_id 並保存
- [ ] 定期同步伺服器狀態
- [ ] 更新 UI 顯示進度

### ✅ 後端流程
- [ ] MySQL 資料庫初始化
- [ ] EF Core DbContext 設置
- [ ] 實現 `POST /api/videos/create` 資料庫操作
- [ ] 實現 `POST /api/slices/upload` 檔案儲存 + DB
- [ ] 實現 `GET /api/videos` 資料庫查詢
- [ ] 實現 `GET /api/videos/{id}/status` 詳細查詢
- [ ] 添加錯誤處理和日誌
- [ ] 測試所有 API 端點

---

## 📞 API 集成檢查清單

### 測試上傳端點
```bash
# 1. 建立新影片
curl -X POST http://localhost:5000/api/videos/create \
  -H "Content-Type: application/json" \
  -d '{"name":"test_video","user_id":1,"total_slices":3}'

# 2. 上傳切片
curl -X POST http://localhost:5000/api/slices/upload \
  -F "video_id=1" \
  -F "slice_index=0" \
  -F "video_file=@slice_0.mp4" \
  -F "trajectory_csv=@trajectory.csv"

# 3. 取得影片列表
curl http://localhost:5000/api/videos?user_id=1

# 4. 取得影片狀態
curl http://localhost:5000/api/videos/1/status
```

---

## 📝 代碼架構圖

```
前端 (Flutter)
├── lib/services/
│   ├── local_slice_repository.dart ✅ SQLite 資料庫
│   └── video_server_client.dart ✅ API 客戶端
├── lib/pages/
│   └── local_slice_management_page.dart ✅ UI 頁面
└── [待完成] 實際上傳邏輯

C# Server
├── Models/ ✅ 資料模型
├── DTOs/ ✅ 數據傳輸對象
├── Services/ ✅ 業務邏輯層
│   └── VideoUploadService.cs ✅ 上傳服務
├── Controllers/ ✅ API 端點
│   └── VideoController.cs ✅ 控制器
├── [待完成] DbContext (EF Core)
├── [待完成] 並列處理隊列
└── database-init.sql ✅ 資料庫初始化

Python 處理端
└── [未開始] process_video_slice() 函數
```

---

## 🐛 已知問題與待修復

1. **前端上傳邏輯** - 當前 `uploadSlice()` 是框架，需實現實際檔案讀取
2. **C# Server 資料庫** - 需設置 EF Core DbContext
3. **伺服器狀態同步** - 本地和伺服器狀態匹配邏輯待完善
4. **錯誤處理** - 需添加完善的異常捕獲和重試邏輯
5. **進度跟蹤** - 上傳進度條需與實際進度綁定

---

## 💡 建議優化

1. **並發上傳** - 支援同時上傳多個切片
2. **斷點續傳** - 支援上傳中斷後恢復
3. **離線隊列** - 無網路時先存儲本地，待網路恢復後自動上傳
4. **重試機制** - 自動重試失敗的上傳
5. **流量優化** - 壓縮影片或分塊上傳

---

## 📚 參考文檔

- [Flutter SQLite 文檔](https://pub.dev/packages/sqflite)
- [ASP.NET Core 上傳檔案](https://docs.microsoft.com/en-us/aspnet/core/mvc/models/file-uploads)
- [Entity Framework Core](https://docs.microsoft.com/en-us/ef/core/)
- [MySQL 官方文檔](https://dev.mysql.com/doc/)

---

**下一步建議**：
1. 先完成 MySQL 資料庫初始化
2. 設置 EF Core DbContext
3. 實現前端的實際檔案上傳邏輯
4. 進行端到端集成測試

祝您開發順利！🚀
