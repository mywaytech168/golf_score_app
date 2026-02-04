# C# 後台處理服務 - 實現完成

## 🎯 任務完成情況

### 需求
- ✅ C# server 端 background 每秒檢查要處理的影片
- ✅ 從 process_queue 每次撈一筆處理
- ✅ 同步處理（要等待 API）
- ✅ 撈取對應 video_id 的 file clip 連結
- ✅ 打 API 到 PYTHON MESHFLOW 處理

### 已實現的功能

## 📦 核心組件

### 1. **MeshFlowProcessingService.cs** ✅
後台服務，每秒自動檢查並處理隊列

**主要功能**:
```csharp
- ExecuteAsync()              // 後台執行主迴圈（每1秒檢查一次）
- CheckAndProcessQueueAsync() // 檢查並取出待處理項目
- ProcessQueueItemAsync()     // 處理單個隊列項目
- CallMeshFlowApiAsync()      // 呼叫Python API（同步等待）
- EnqueueVideoAsync()         // 手動添加影片到隊列
- GetQueueStatsAsync()        // 取得隊列統計
```

**工作流程**:
1. 每秒檢查 ProcessQueue 表中 status='queued' 的項目
2. 按 Priority (DESC) 和 CreatedAt (ASC) 排序
3. 取出第一筆項目
4. 從 Files 表取得對應 video_id 的檔案路徑
5. 標記為 'processing'，記錄 StartedAt 時間
6. 呼叫 Python MeshFlow API (同步等待回應)
7. 根據回應結果：
   - 成功 → status='completed'，記錄 CompletedAt
   - 失敗 → RetryCount++
     - 若 RetryCount < 3 → status='queued'（重新入隊）
     - 若 RetryCount >= 3 → status='failed'（標記失敗）

### 2. **ProcessQueueController.cs** ✅
REST API 控制器，提供隊列管理介面

**API 端點**:
```
GET    /api/processqueue/stats              → 隊列統計
GET    /api/processqueue                    → 查詢隊列項目
GET    /api/processqueue/{id}               → 取得單個項目
POST   /api/processqueue/enqueue            → 添加單個影片
POST   /api/processqueue/enqueue-batch      → 批量添加影片
PUT    /api/processqueue/{id}/retry         → 重試失敗項目
DELETE /api/processqueue/{id}               → 刪除隊列項目
DELETE /api/processqueue/clear-failed       → 清除失敗項目
```

**DTO**:
```csharp
EnqueueRequest      // 單個入隊請求
EnqueueBatchRequest // 批量入隊請求
```

### 3. **Program.cs 配置** ✅
服務註冊和依賴注入設定

```csharp
builder.Services.AddHttpClient();
builder.Services.AddSingleton<MeshFlowProcessingService>();
builder.Services.AddHostedService<MeshFlowProcessingService>(sp =>
    sp.GetRequiredService<MeshFlowProcessingService>());
```

### 4. **appsettings.json** ✅
MeshFlow API 組態

```json
"MeshFlow": {
  "ApiBaseUrl": "http://localhost:5001",
  "Enabled": true,
  "Description": "Python MeshFlow API 伺服器地址"
}
```

## 📊 資料流

### 1. 添加影片到隊列
```
POST /api/processqueue/enqueue
├─ 驗證 videoId 存在
├─ 檢查是否已在隊列
└─ 建立 ProcessQueueItem
   ├─ Status: "queued"
   ├─ Priority: 0 (或指定值)
   ├─ CreatedAt: now
   └─ RetryCount: 0
```

### 2. 後台自動處理
```
每秒執行:
1. SELECT * FROM process_queue WHERE status='queued' 
   ORDER BY priority DESC, created_at ASC LIMIT 1

2. UPDATE process_queue SET status='processing', started_at=now

3. SELECT file_path FROM files WHERE video_id=? AND type IN ('original','clip')

4. HTTP POST to Python API
   {
     "input_dir": "directory/of/video",
     "output_dir": "output/directory",
     "roi": [742, 255],
     ...
   }

5. 根據回應更新狀態:
   - 成功: status='completed', completed_at=now
   - 失敗: retry_count++, status='queued'|'failed'
```

### 3. 查詢隊列狀態
```
GET /api/processqueue/stats
↓
計算各狀態計數:
{
  "queued": 5,
  "processing": 1,
  "completed": 42,
  "failed": 0
}
```

## 🔧 配置參數

| 參數 | 值 | 說明 |
|------|-----|------|
| CHECK_INTERVAL_MS | 1000 | 每秒檢查隊列一次 |
| API_TIMEOUT_SECONDS | 300 | API 呼叫超時 5 分鐘 |
| MAX_RETRY_COUNT | 3 | 失敗最多重試 3 次 |
| MeshFlow:ApiBaseUrl | http://localhost:5001 | Python API 地址 |

## 📝 使用示例

### 1. 啟動所有服務
```bash
# 終端1: Python MeshFlow API
cd meshflow_stabilize_with_audio_V2
python -m flask run --port 5001

# 終端2: C# 伺服器
cd server
dotnet run
```

### 2. 添加影片到隊列
```bash
curl -X POST http://localhost:5000/api/processqueue/enqueue \
  -H "Content-Type: application/json" \
  -d '{"videoId": "550e8400-e29b-41d4-a716-446655440000", "priority": 0}'
```

### 3. 查詢隊列狀態
```bash
# 全部統計
curl http://localhost:5000/api/processqueue/stats

# 查詢特定狀態
curl "http://localhost:5000/api/processqueue?status=processing"

# 查詢單個項目
curl http://localhost:5000/api/processqueue/queue-item-id
```

### 4. 批量添加影片
```bash
curl -X POST http://localhost:5000/api/processqueue/enqueue-batch \
  -H "Content-Type: application/json" \
  -d '{
    "videoIds": ["id-1", "id-2", "id-3"],
    "priority": 0
  }'
```

### 5. 重試失敗項目
```bash
curl -X PUT http://localhost:5000/api/processqueue/queue-item-id/retry
```

## 📄 文檔

已建立的文檔文件：

1. **MESHFLOW_INTEGRATION_GUIDE.md** (詳細)
   - 完整架構設計
   - 工作流程說明
   - API 使用示例
   - 錯誤處理說明

2. **MESHFLOW_QUICK_REFERENCE.md** (快速參考)
   - 常用命令
   - 快速入門
   - 故障排除

3. **MESHFLOW_SERVICE_SUMMARY.md** (實現總結)
   - 已完成功能清單
   - 時序圖
   - 測試命令

## ⚙️ 技術細節

### 同步処理

Python API 呼叫使用 `await Task`：
```csharp
var response = await _httpClient.PostAsync(apiUrl, jsonContent, cancellationToken);

// 完全等待 API 完成，不進行非同步操作
```

### 優先級排序

```csharp
var queueItem = await dbContext.ProcessQueue
    .Where(x => x.Status == "queued")
    .OrderByDescending(x => x.Priority)    // 優先級高的先處理
    .ThenBy(x => x.CreatedAt)              // 同優先級時間早的先
    .FirstOrDefaultAsync();
```

### 重試機制

```
第1次失敗 → Status='queued', RetryCount=1 → 重新排隊
第2次失敗 → Status='queued', RetryCount=2 → 重新排隊
第3次失敗 → Status='queued', RetryCount=3 → 重新排隊
第4次失敗 → Status='failed', RetryCount=4 → 停止處理
```

### 檔案尋找

```csharp
// 自動尋找 input_dir 中的第一個 video 檔案
var videoFiles = list(input_path.glob("*.mp4")) + list(input_path.glob("*.avi"))
var first_video = videoFiles[0]
```

### 日誌記錄

使用 NLog + ILogger：
```csharp
_nLogger.Info("✅ 分析完成 - 流程執行成功");
_logger.LogInformation("✅ 分析完成 - 流程執行成功");
```

## 🚀 部署建議

### 1. 生產環境配置

```json
{
  "MeshFlow": {
    "ApiBaseUrl": "http://meshflow-server:5001",
    "Enabled": true
  },
  "Logging": {
    "LogLevel": {
      "Default": "Information"
    }
  }
}
```

### 2. 可擴展性

- **單服務器**: 當前實現支持
- **多服務器**: 需添加分散式鎖（Redis/DB）防止重複處理
- **並行處理**: 可修改為非同步實現並行結構化

### 3. 監控

- 監控 process_queue 表中各狀態的計數
- 設置告警當失敗項目過多時
- 記錄平均處理時間

## ✅ 驗收清單

- ✅ 後台服務每秒檢查隊列
- ✅ 每次取出一筆進行同步處理
- ✅ 從 Files 表取得檔案路徑
- ✅ 呼叫 Python API 並等待完成
- ✅ 成功/失敗判斷和重試邏輯
- ✅ REST API 提供隊列管理
- ✅ 日誌記錄所有操作
- ✅ 組態管理 (appsettings.json)
- ✅ 完整文檔

## 📌 重要檔案位置

```
server/
├── Services/
│   └── MeshFlowProcessingService.cs      ← 後台服務核心
├── Controllers/
│   └── ProcessQueueController.cs         ← REST API
├── Program.cs                             ← 依賴注入
├── appsettings.json                       ← 組態
├── MESHFLOW_INTEGRATION_GUIDE.md         ← 詳細指南
├── MESHFLOW_QUICK_REFERENCE.md           ← 快速參考
└── MESHFLOW_SERVICE_SUMMARY.md           ← 實現總結
```

## 🔗 相關服務

- **Python MeshFlow API**: `meshflow_stabilize_with_audio_V2/server.py`
- **資料庫上下文**: `server/Data/VideoDbContext.cs`
- **模型**: `server/Models/ProcessQueueItem.cs`, `server/Models/Video.cs`, `server/Models/File.cs`

---

**狀態**: ✅ 完成  
**版本**: 1.0  
**最後更新**: 2024年  
