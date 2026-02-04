# C# 後台處理服務 - MeshFlow 集成指南

## 概述

本文檔說明 C# ASP.NET 後台服務如何與 Python MeshFlow API 進行集成，實現影片的自動處理流程。

## 架構設計

```
┌─────────────────────────────────────────────────────────────┐
│                    C# ASP.NET 伺服器                         │
│                    (localhost:5000)                          │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  ProcessQueueController                              │   │
│  │  提供 REST API 管理隊列                               │   │
│  │  - GET /api/processqueue/stats (隊列統計)            │   │
│  │  - GET /api/processqueue (查詢隊列項目)              │   │
│  │  - POST /api/processqueue/enqueue (添加到隊列)       │   │
│  │  - POST /api/processqueue/enqueue-batch (批量添加)   │   │
│  │  - PUT /api/processqueue/{id}/retry (重試)          │   │
│  │  - DELETE /api/processqueue/{id} (刪除)              │   │
│  └──────────────────────────────────────────────────────┘   │
│                          ↓ 通知                             │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  MeshFlowProcessingService                           │   │
│  │  (HostedService - 後台執行)                          │   │
│  │                                                      │   │
│  │  每秒 (CHECK_INTERVAL_MS = 1000ms):                  │   │
│  │  1. 查詢 process_queue 表中 status='queued' 的項目   │   │
│  │  2. 按優先級排序 (Priority DESC, CreatedAt ASC)     │   │
│  │  3. 取出第一筆                                       │   │
│  │  4. 標記為 'processing'                              │   │
│  │  5. 從 files 表取得影片檔案路徑                      │   │
│  │  6. 呼叫 Python MeshFlow API (同步等待)              │   │
│  │  7. 根據結果標記為 'completed' 或 'failed'           │   │
│  │  (失敗時重試，達上限後標記為 failed)                │   │
│  └──────────────────────────────────────────────────────┘   │
│                          ↓ HTTP POST                        │
└─────────────────────────────────────────────────────────────┘
                           ↓
        ┌──────────────────────────────────────┐
        │   Python MeshFlow API 伺服器          │
        │   (localhost:5001)                   │
        │                                      │
        │  POST /api/meshflow                  │
        │  {                                   │
        │    "input_dir": "path/to/video",     │
        │    "output_dir": "path/to/output",   │
        │    "roi": [742, 255],                │
        │    "frames": 300,                    │
        │    ...                               │
        │  }                                   │
        │                                      │
        │  Response:                           │
        │  {                                   │
        │    "success": true/false,            │
        │    "message": "...",                 │
        │    "data": {...}                     │
        │  }                                   │
        └──────────────────────────────────────┘
```

## 資料庫模型

### ProcessQueueItem 表

```csharp
public class ProcessQueueItem
{
    public string Id { get; set; }                  // UUID (主鍵)
    public string VideoId { get; set; }             // UUID (影片外鍵)
    public int Priority { get; set; }               // 優先級 (小於等於為先)
    public string Status { get; set; }              // queued|processing|completed|failed
    public string? AssignedWorkerId { get; set; }   // Worker ID (保留)
    public DateTime CreatedAt { get; set; }         // 建立時間
    public DateTime? StartedAt { get; set; }        // 開始處理時間
    public DateTime? CompletedAt { get; set; }      // 完成時間
    public int RetryCount { get; set; }             // 重試次數 (預設 0)
    public string? ErrorMessage { get; set; }       // 失敗原因
    public Video Video { get; set; }                // 導航屬性
}
```

## 工作流程

### 1. 添加影片到隊列

**API 端點**: `POST /api/processqueue/enqueue`

```bash
curl -X POST http://localhost:5000/api/processqueue/enqueue \
  -H "Content-Type: application/json" \
  -d '{
    "videoId": "550e8400-e29b-41d4-a716-446655440000",
    "priority": 0
  }'
```

**回應**:
```json
{
  "success": true,
  "message": "影片已添加到處理隊列",
  "data": {
    "videoId": "550e8400-e29b-41d4-a716-446655440000"
  }
}
```

### 2. 後台服務自動處理

後台服務每秒執行以下步驟:

```csharp
// 1. 查詢待處理項目
var queueItem = await dbContext.ProcessQueue
    .Where(x => x.Status == "queued")
    .OrderByDescending(x => x.Priority)    // 優先級高的先
    .ThenBy(x => x.CreatedAt)              // 同優先級的舊項目先
    .FirstOrDefaultAsync();

// 2. 標記為 processing
queueItem.Status = "processing";
queueItem.StartedAt = DateTime.Now;

// 3. 取得影片檔案路徑
var video = await dbContext.Videos.FindAsync(queueItem.VideoId);
var videoFile = await dbContext.Files
    .Where(f => f.VideoId == queueItem.VideoId && f.Type == "original" || f.Type == "clip")
    .FirstOrDefaultAsync();

// 4. 呼叫 Python API (同步等待)
var response = await httpClient.PostAsync(
    "http://localhost:5001/api/meshflow",
    requestBody);

// 5. 根據結果更新狀態
if (response.IsSuccessStatusCode)
{
    queueItem.Status = "completed";
    queueItem.CompletedAt = DateTime.Now;
}
else
{
    queueItem.RetryCount++;
    if (queueItem.RetryCount >= MAX_RETRY_COUNT)
    {
        queueItem.Status = "failed";
    }
    else
    {
        queueItem.Status = "queued";  // 重新排隊
    }
}
```

### 3. 查詢隊列狀態

**API 端點**: `GET /api/processqueue/stats`

```bash
curl http://localhost:5000/api/processqueue/stats
```

**回應**:
```json
{
  "success": true,
  "message": "隊列統計資訊已取得",
  "data": {
    "queued": 5,
    "processing": 1,
    "completed": 23,
    "failed": 2
  }
}
```

## 配置說明

### appsettings.json

```json
{
  "MeshFlow": {
    "ApiBaseUrl": "http://localhost:5001",
    "Enabled": true,
    "Description": "Python MeshFlow API 伺服器地址"
  }
}
```

### Program.cs 中的註冊

```csharp
// 1. 添加 HttpClient 工廠
builder.Services.AddHttpClient();

// 2. 註冊後台服務
builder.Services.AddSingleton<MeshFlowProcessingService>();
builder.Services.AddHostedService<MeshFlowProcessingService>(sp =>
    sp.GetRequiredService<MeshFlowProcessingService>());
```

## API 端點參考

### 隊列管理 API

| 方法 | 端點 | 說明 |
|------|------|------|
| GET | `/api/processqueue/stats` | 取得隊列統計 |
| GET | `/api/processqueue` | 取得隊列項目列表 |
| GET | `/api/processqueue/{id}` | 取得單個項目詳情 |
| POST | `/api/processqueue/enqueue` | 添加單個影片到隊列 |
| POST | `/api/processqueue/enqueue-batch` | 批量添加影片到隊列 |
| PUT | `/api/processqueue/{id}/retry` | 重試失敗的項目 |
| DELETE | `/api/processqueue/{id}` | 刪除隊列項目 |
| DELETE | `/api/processqueue/clear-failed` | 清除所有失敗項目 |

### 查詢參數

- **GET /api/processqueue**
  - `status`: queued | processing | completed | failed (可選)
  - `limit`: 最大返回數量，預設 100

## 錯誤處理

### 重試邏輯

- **MAX_RETRY_COUNT = 3**: 失敗後最多重試 3 次
- 失敗原因可能包括:
  - Python API 伺服器不可達
  - 影片檔案不存在
  - API 超時 (300 秒)
  - 其他 HTTP 錯誤

### 日誌記錄

系統使用 NLog 記錄所有操作:

```
[2024-XX-XX HH:MM:SS] ⚙️  開始處理隊列項目: queue-id-123
[2024-XX-XX HH:MM:SS] 📹 影片檔案路徑: /path/to/video.mp4
[2024-XX-XX HH:MM:SS] 🌐 呼叫 MeshFlow API: http://localhost:5001/api/meshflow
[2024-XX-XX HH:MM:SS] ✅ 分析完成 - 流程執行成功
```

## 性能考慮

### 處理速度

- **檢查間隔**: 1 秒 (可配置 CHECK_INTERVAL_MS)
- **API 超時**: 300 秒 (可配置 API_TIMEOUT_SECONDS)
- **平均處理時間**: 取決於影片長度和 Python API 效能

### 資料庫

- 使用 `AsNoTracking()` 查詢以提高效能
- 按優先級和時間排序確保公平性
- 支持水平擴展 (多個 Worker)

### 可擴展性

當需要並行處理多個影片時，可以:

1. **增加服務執行個體**: 部署多個 C# 伺服器實例
2. **添加 Worker 識別**: 使用 `AssignedWorkerId` 欄位追蹤處理者
3. **分散式鎖**: 使用 Redis 或資料庫鎖防止重複處理
4. **消息隊列**: 集成 RabbitMQ 或 Kafka 進行非同步處理

## 完整工作流範例

### 1. 上傳影片

用戶通過 `/api/upload` 上傳影片，系統在 `files` 表中建立記錄

### 2. 添加到隊列

```csharp
POST /api/processqueue/enqueue
{
  "videoId": "video-uuid",
  "priority": 0
}
```

### 3. 後台自動處理

- 後台服務每秒檢查一次
- 發現新項目後標記為 processing
- 呼叫 Python API 進行分析
- 等待 API 完成 (同步)
- 更新項目狀態為 completed 或 failed

### 4. 查詢結果

```csharp
GET /api/processqueue/{queue-id}

Response:
{
  "success": true,
  "data": {
    "id": "queue-id",
    "videoId": "video-uuid",
    "status": "completed",
    "startedAt": "2024-XX-XX HH:MM:SS",
    "completedAt": "2024-XX-XX HH:MM:SS",
    "errorMessage": null
  }
}
```

## 故障排除

### 問題: 後台服務不執行

**解決方案**:
1. 檢查 `appsettings.json` 中的 MeshFlow 配置
2. 查看應用日誌確認服務是否啟動
3. 確保資料庫連接正常

### 問題: API 呼叫失敗

**解決方案**:
1. 確認 Python MeshFlow API 伺服器正在運行
2. 檢查 `ApiBaseUrl` 配置是否正確
3. 驗證網路連接和防火牆設定
4. 查看詳細日誌信息

### 問題: 影片卡在 "processing" 狀態

**解決方案**:
1. 檢查 Python API 是否正常回應
2. 手動調用 `/api/processqueue/{id}/retry` 重試
3. 檢查影片檔案是否存在且可訪問

## 相關文件

- [MeshFlow Python API 文件](../meshflow_stabilize_with_audio_V2/README.md)
- [資料庫模型文件](./Models/)
- [服務層實現](./Services/MeshFlowProcessingService.cs)
- [控制器實現](./Controllers/ProcessQueueController.cs)
