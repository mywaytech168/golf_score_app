# 🏌️ 系統實作完成報告 - ProcessQueue 結果存儲

**實作日期**: 2026-02-02  
**功能**: 將最終處理結果直接存儲在 `process_queue` 表中

---

## 📋 實作概要

已完成将处理结果直接存储在 `ProcessQueueItem` 中，而不是建立单独的 `ProcessingResult` 表。这样设计更加简洁、高效。

### 架構設計

```
C# Server                          Python Server
    ↓                                    ↓
[接收上傳]                         [處理任務]
    ↓                                    ↓
[ProcessQueue]                     [TaskQueue]
  (status=queued)                    ↓
    ↓                            [execute_pipeline]
[Scheduler]────HTTP────→ [POST /api/tasks/process]
    ↓                                    ↓
[status=processing]              [CallbackSender]
    ↓                                    ↓
[等待回調] ←────HTTP────── [POST /api/callback/processing-result]
    ↓
[status=completed]
[IsSuccess=true]
[ResultData=JSON]
```

---

## ✅ 已實作的功能

### 1. C# Server 變更

#### 📝 **模型更新** - [ProcessQueueItem.cs](server/Models/ProcessQueueItem.cs)

**新增字段**:
```csharp
/// <summary>
/// 處理是否成功
/// </summary>
public bool IsSuccess { get; set; } = false;

/// <summary>
/// 最終處理結果（JSON 格式）
/// 包含：軌跡數據、姿勢分析、音頻評分等
/// </summary>
public string? ResultData { get; set; }
```

#### 🗄️ **資料庫遷移** - [20260202000001_AddResultFieldsToProcessQueue.cs](server/Migrations/20260202000001_AddResultFieldsToProcessQueue.cs)

**新增欄位**:
- `is_success` (TINYINT) - 處理成功標誌
- `result_data` (LONGTEXT) - JSON 格式的結果數據

**新增索引**:
- `idx_queue_is_success` - 加速成功/失敗查詢
- `idx_queue_completed_status` - 加速完成狀態查詢

#### 📤 **回調處理器** - [CallbackController.cs](server/Controllers/CallbackController.cs) (新建)

**功能**:
- `POST /api/callback/processing-result` - 接收 Python 處理結果
  - 驗證隊列項目是否存在
  - 更新 `Status`、`IsSuccess`、`ResultData`、`ErrorMessage`
  - 返回成功/失敗響應

- `GET /api/callback/result/{queueItemId}` - 查詢已完成的結果
  - 返回完整的處理信息
  - 自動計算處理時長
  - 將 JSON 字符串反序列化為對象

- `GET /api/callback/health` - 健康檢查

**DTO 類** - [ProcessingResultDtos.cs](server/DTOs/ProcessingResultDtos.cs) (新建)
```csharp
public class ProcessingResultCallbackDto
{
    public string QueueItemId { get; set; }
    public bool Success { get; set; }
    public Dictionary<string, object> ResultData { get; set; }
    public string? ErrorMessage { get; set; }
    public DateTime CompletedAt { get; set; }
    public double ProcessingDurationSeconds { get; set; }
}
```

#### 🔄 **排程服務** - [ProcessingSchedulerService.cs](server/Services/ProcessingSchedulerService.cs) (新建)

**功能**:
- 後台服務 (`BackgroundService`)
- 每秒檢查 `process_queue` 表
- 查詢 `Status='queued'` 的項目
- 按優先級 + 創建時間排序取出第一個
- HTTP POST 到 Python Server: `POST /api/tasks/process`
- 更新隊列項目為 `processing` 狀態
- 失敗重試機制：
  - 最多重試 3 次（可配置）
  - 超過重試次數設為 `failed`

**配置參數**:
```json
"ServiceUrls": {
    "PythonServerUrl": "http://localhost:5000",
    "CSharpServerUrl": "http://localhost:5001",
    "RequestTimeout": 300,
    "MaxRetries": 3,
    "RetryDelayMs": 5000
}
```

#### 🔧 **服務註冊** - [Program.cs](server/Program.cs)

```csharp
// HTTP 客戶端工廠
builder.Services.AddHttpClient();

// 後台排程服務
builder.Services.AddHostedService<ProcessingSchedulerService>();
```

#### 🗂️ **DbContext 配置** - [VideoDbContext.cs](server/Data/VideoDbContext.cs)

```csharp
entity.Property(e => e.IsSuccess)
    .HasColumnName("is_success")
    .HasDefaultValue(false);

entity.Property(e => e.ResultData)
    .HasColumnName("result_data")
    .HasColumnType("longtext");

entity.HasIndex(e => e.IsSuccess).HasDatabaseName("idx_queue_is_success");
entity.HasIndex(e => new { e.CompletedAt, e.Status })
    .HasDatabaseName("idx_queue_completed_status");
```

---

### 2. Python Server 變更

#### 📬 **任務隊列模塊** - [services/task_queue.py](meshflow_stabilize_with_audio_V2/services/task_queue.py) (新建)

**功能**:
- `TaskQueue` 類
- `add_task(queue_item_id, video_id)` - 添加任務
- `start_scheduler()` - 啟動排程器
- `_scheduler_loop()` - 每秒檢查一次隊列
- `_process_task(task)` - 執行實際處理
- `_run_processing_pipeline(task)` - 調用分析流程
- `_send_result_to_csharp()` - 回調 C# Server
- `get_status()` - 獲取隊列狀態

**關鍵方法**:
```python
def add_task(self, queue_item_id: str, video_id: str):
    """添加任務到隊列"""
    
def start_scheduler(self):
    """啟動排程器線程"""
    
def _send_result_to_csharp(
    self,
    queue_item_id: str,
    success: bool,
    result_data: dict = None,
    error: str = None,
    processing_time: float = 0
):
    """發送結果回 C# Server"""
```

#### 🔌 **API 端點集成** - [server.py](meshflow_stabilize_with_audio_V2/server.py)

**新增端點**:

1. **`POST /api/tasks/process`** - 接收任務
   - 從 C# Server 接收待處理任務
   - 驗證 `queueItemId`
   - 添加到隊列
   - 返回 202 Accepted

2. **`GET /api/tasks/status`** - 查詢隊列狀態
   - 返回隊列大小
   - 當前處理狀態
   - 當前任務 ID

3. **`GET /api/tasks/health`** - 健康檢查
   - 驗證服務可用性

**初始化代碼**:
```python
from services.task_queue import get_task_queue

CSHARP_SERVER_URL = os.getenv('CSHARP_SERVER_URL', 'http://localhost:5001')
task_queue = get_task_queue(CSHARP_SERVER_URL)

# 在 Flask 啟動時啟動排程器
task_queue.start_scheduler()
```

---

## 🔄 完整處理流程

### 時序圖

```
時間  C# Server           Python Server        Database
──────────────────────────────────────────────────────
T0   [POST /files]
     └─> 保存上傳的切片
     └─> 建立 ProcessQueueItem
         Status = 'queued'
         
T1   [Scheduler 檢查]
     └─> 查詢 Status='queued'
     └─> 發現任務
     
T2   ├─ 更新 Status='processing'
     │
     └─────> [POST /api/tasks/process]
             QueueItemId, VideoId
             
T3            └─> 接收任務
              └─> 加入隊列
              └─> 返回 202
              
T4            [排程器檢查]
              └─> 取出任務
              └─> 執行 execute_pipeline()
              └─> 併列處理流程
              
T(n-1)        [處理完成]
              └─> 準備回調數據
              └─> ResultData = JSON
              
Tn           ├─ 接收回調
             ├─ 更新 Status='completed'
             ├─ IsSuccess=true
             └─ ResultData=JSON格式結果
```

---

## 💾 資料庫表結構

### process_queue 表

```sql
CREATE TABLE process_queue (
  id VARCHAR(36) PRIMARY KEY,
  video_id VARCHAR(36) NOT NULL,
  priority INT DEFAULT 0,
  assigned_worker_id VARCHAR(100),
  status VARCHAR(50) DEFAULT 'queued',
  created_at DATETIME,
  started_at DATETIME,
  completed_at DATETIME,
  retry_count INT DEFAULT 0,
  error_message TEXT,
  is_success TINYINT(1) DEFAULT 0,        ← 新增
  result_data LONGTEXT,                    ← 新增
  
  FOREIGN KEY (video_id) REFERENCES videos(id),
  
  INDEX idx_queue_status (status),
  INDEX idx_queue_video_id (video_id),
  INDEX idx_queue_is_success (is_success),           ← 新增
  INDEX idx_queue_completed_status (completed_at, status), ← 新增
  INDEX idx_queue_status_priority_created (status, priority, created_at)
);
```

### ResultData 的 JSON 結構範例

```json
{
  "queueItemId": "uuid-1234",
  "videoId": "video-uuid",
  "processedAt": "2026-02-02T10:30:00Z",
  "steps": {
    "stabilization": {
      "status": "completed",
      "output_file": "clip_stabilized.mp4",
      "duration_ms": 15000
    },
    "audio_analysis": {
      "status": "completed",
      "peaks_detected": 5,
      "frequency_analysis": {...}
    },
    "audio_scoring": {
      "status": "completed",
      "score": 85.5,
      "metrics": {...}
    },
    "openpose_analysis": {
      "status": "completed",
      "keypoints": [...],
      "confidence": 0.95
    },
    "ball_tracking": {
      "status": "completed",
      "trajectory_points": 250,
      "output_file": "trajectory.mp4"
    }
  },
  "finalOutputs": [
    "trajectory_overlay.mp4",
    "pose_analysis.mp4"
  ]
}
```

---

## 🚀 使用流程

### 步驟 1: 上傳視頻和創建隊列項目（C#）
```csharp
POST /api/videos/{videoId}/files
Content-Type: multipart/form-data

Response:
{
  "success": true,
  "fileId": "file-uuid",
  "queueItemId": "queue-uuid"  // 自動建立
}
```

### 步驟 2: 排程器定期檢查（C# 後台）
```
每秒檢查:
SELECT * FROM process_queue 
WHERE status='queued' 
ORDER BY priority DESC, created_at ASC 
LIMIT 1
```

### 步驟 3: 發送到 Python（C#）
```csharp
POST http://python-server:5000/api/tasks/process
Content-Type: application/json

{
  "queueItemId": "queue-uuid",
  "videoId": "video-uuid",
  "timestamp": "2026-02-02T10:00:00Z"
}
```

### 步驟 4: 任務排隊（Python）
```python
POST /api/tasks/process
# 驗證
# 添加到隊列
# 返回 202
```

### 步驟 5: 處理任務（Python 排程器）
```python
# 每秒檢查
task = queue.get()  # 取出任務
result = execute_pipeline(task)
# 併列處理流程
```

### 步驟 6: 回調結果（Python）
```csharp
POST http://csharp-server:5001/api/callback/processing-result
Content-Type: application/json

{
  "queueItemId": "queue-uuid",
  "success": true,
  "resultData": { /* 完整結果JSON */ },
  "completedAt": "2026-02-02T10:05:00Z",
  "processingDurationSeconds": 300
}
```

### 步驟 7: 更新資料庫（C#）
```csharp
// 自動更新
queue_item.Status = "completed"
queue_item.IsSuccess = true
queue_item.ResultData = JSON字符串
queue_item.CompletedAt = now
```

### 步驟 8: 查詢結果（客户端）
```csharp
GET /api/callback/result/{queueItemId}

Response:
{
  "queueItemId": "uuid",
  "videoId": "uuid",
  "status": "completed",
  "success": true,
  "createdAt": "...",
  "completedAt": "...",
  "processingDurationMs": 300000,
  "resultData": { /* 反序列化後的 JSON */ }
}
```

---

## 📊 查詢範例

### SQL 查詢

```sql
-- 查詢所有成功完成的項目
SELECT * FROM process_queue 
WHERE is_success = 1 AND status = 'completed'
ORDER BY completed_at DESC;

-- 查詢正在處理中的項目
SELECT * FROM process_queue 
WHERE status = 'processing'
ORDER BY created_at ASC;

-- 查詢失敗的項目
SELECT id, video_id, error_message, retry_count 
FROM process_queue 
WHERE status = 'failed'
ORDER BY completed_at DESC;

-- 統計處理成功率
SELECT 
  COUNT(*) as total,
  SUM(CASE WHEN is_success = 1 THEN 1 ELSE 0 END) as successful,
  ROUND(100.0 * SUM(CASE WHEN is_success = 1 THEN 1 ELSE 0 END) / COUNT(*), 2) as success_rate
FROM process_queue
WHERE status = 'completed';

-- 查詢平均處理時間
SELECT 
  AVG(TIMESTAMPDIFF(SECOND, started_at, completed_at)) as avg_seconds,
  MIN(TIMESTAMPDIFF(SECOND, started_at, completed_at)) as min_seconds,
  MAX(TIMESTAMPDIFF(SECOND, started_at, completed_at)) as max_seconds
FROM process_queue
WHERE status = 'completed';
```

### C# 查詢

```csharp
// LINQ 查詢成功的項目
var successfulItems = _context.ProcessQueue
    .Where(q => q.IsSuccess && q.Status == "completed")
    .OrderByDescending(q => q.CompletedAt)
    .ToList();

foreach (var item in successfulItems)
{
    var result = JsonConvert.DeserializeObject(item.ResultData);
    Console.WriteLine($"Video: {item.VideoId}, Result: {result}");
}
```

---

## 🔧 配置檔案

### appsettings.json 更新
```json
{
  "ServiceUrls": {
    "PythonServerUrl": "http://localhost:5000",
    "CSharpServerUrl": "http://localhost:5001",
    "RequestTimeout": 300,
    "MaxRetries": 3,
    "RetryDelayMs": 5000
  }
}
```

### 環境變數（Python Server）
```bash
# 在 docker-compose.yml 或 .env 中設置
CSHARP_SERVER_URL=http://csharp-server:5001
```

---

## 📈 性能優化

### 索引策略
- `idx_queue_status` - 排程器查詢 (O(log n))
- `idx_queue_is_success` - 統計查詢
- `idx_queue_completed_status` - 複合查詢

### JSON 存儲優化
- 使用 LONGTEXT 而非無限大小的 TEXT
- 建議單個 ResultData < 1MB
- 定期歸檔舊記錄

---

## ✅ 遷移執行步驟

### 1. 更新代碼
```bash
git pull
```

### 2. 執行資料庫遷移（C#）
```bash
cd server
dotnet ef database update
```

### 3. 驗證表結構
```sql
DESC process_queue;  -- 應該看到 is_success 和 result_data 欄位
```

### 4. 重啟服務
```bash
# C# Server
dotnet run --project server/UploadServer.csproj

# Python Server
python meshflow_stabilize_with_audio_V2/server.py
```

---

## 🧪 測試流程

### 1. 健康檢查
```bash
curl http://localhost:5001/api/health
curl http://localhost:5000/api/health
```

### 2. 上傳測試
```bash
curl -X POST http://localhost:5001/api/videos/test-video/files \
  -H "Authorization: Bearer $TOKEN" \
  -F "fileType=raw" \
  -F "file=@test.mp4"
```

### 3. 驗證隊列
```bash
curl http://localhost:5000/api/tasks/status
```

### 4. 查詢結果
```bash
curl http://localhost:5001/api/callback/result/{queueItemId}
```

---

## 🎯 優勢

1. **簡化架構** - 無需單獨的 ProcessingResult 表
2. **一致性** - 所有狀態和結果在同一條記錄
3. **性能** - 減少表關聯查詢
4. **可追蹤** - 完整的生命週期在一個表中
5. **JSON 靈活性** - 支援各種結果格式

---

## ❌ 可能的問題和解決方案

### 問題 1: ResultData 過大
**解決**: 實施結果分片或外部存儲
```python
# 大結果存到文件，ResultData 存文件路徑
result_data = {
    "files": {
        "trajectory": "/output/trajectory.json",
        "metadata": "/output/metadata.json"
    }
}
```

### 問題 2: 編碼問題
**解決**: 確保 MySQL 使用 utf8mb4
```sql
ALTER TABLE process_queue CONVERT TO CHARACTER SET utf8mb4;
```

### 問題 3: 超時
**解決**: 增加 RequestTimeout
```json
"RequestTimeout": 600  // 10 分鐘
```

---

## 📝 下一步工作

- [ ] 實施詳細的監控儀表板
- [ ] 添加結果匯出功能 (CSV/Excel)
- [ ] 實施結果緩存策略
- [ ] 添加批量 API
- [ ] 性能測試 (1000+ 項目)
- [ ] 災難恢復備份

