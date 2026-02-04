# C# 後台處理服務實現總結

## 已完成的工作

### 1. 核心後台服務 (`MeshFlowProcessingService.cs`)

✅ **功能特性**:
- 每秒檢查 `ProcessQueue` 表中待處理的影片
- 按優先級 (Priority DESC) 和建立時間 (CreatedAt ASC) 排序
- 每次取出一筆進行同步處理
- 自動從 `Files` 表取得影片檔案路徑
- 呼叫 Python MeshFlow API 進行分析（同步等待）
- 根據 API 結果更新項目狀態
- 失敗自動重試（最多 3 次）
- 完整的日誌記錄 (NLog + ILogger)

✅ **關鍵方法**:
- `ExecuteAsync()`: 後台執行主迴圈
- `CheckAndProcessQueueAsync()`: 檢查並取出待處理項目
- `ProcessQueueItemAsync()`: 處理單個隊列項目
- `CallMeshFlowApiAsync()`: 呼叫 Python API
- `EnqueueVideoAsync()`: 手動添加影片到隊列
- `GetQueueStatsAsync()`: 取得隊列統計

### 2. 隊列管理 API 控制器 (`ProcessQueueController.cs`)

✅ **REST API 端點**:

| 端點 | 方法 | 說明 |
|------|------|------|
| `/api/processqueue/stats` | GET | 隊列統計 (queued/processing/completed/failed) |
| `/api/processqueue` | GET | 查詢隊列項目 (支援狀態過濾) |
| `/api/processqueue/{id}` | GET | 取得單個項目詳情 |
| `/api/processqueue/enqueue` | POST | 添加單個影片到隊列 |
| `/api/processqueue/enqueue-batch` | POST | 批量添加影片到隊列 |
| `/api/processqueue/{id}/retry` | PUT | 重試失敗的項目 |
| `/api/processqueue/{id}` | DELETE | 刪除隊列項目 |
| `/api/processqueue/clear-failed` | DELETE | 清除所有失敗項目 |

### 3. 配置更新

✅ **Program.cs**:
- 註冊 `HttpClient` 工廠
- 註冊 `MeshFlowProcessingService` 為 Singleton
- 註冊為 HostedService 自動啟動

✅ **appsettings.json**:
- 添加 `MeshFlow:ApiBaseUrl` 配置 (預設: `http://localhost:5001`)
- 添加 `MeshFlow:Enabled` 開關
- 添加配置說明註釋

### 4. 文檔

✅ **MESHFLOW_INTEGRATION_GUIDE.md**:
- 完整的架構設計圖
- 詳細的工作流程說明
- 資料庫模型定義
- API 使用示例
- 錯誤處理和重試邏輯
- 性能考慮和可擴展性
- 故障排除指南

## 工作流程 (時序圖)

```
用戶                C# 伺服器              Python API
 │                    │                      │
 ├──POST /enqueue────>│                      │
 │                    │                      │
 │                    ├─ 存入 process_queue  │
 │                    │                      │
 │  [每秒檢查]         │                      │
 │                    ├─ 查詢 queue 中 status='queued' 的項目
 │                    │                      │
 │                    ├─ 標記為 'processing' │
 │                    │                      │
 │                    ├─ 從 files 表取得影片路徑
 │                    │                      │
 │                    ├──POST /api/meshflow─>│
 │                    │ (同步等待回應)        │ [分析影片]
 │                    │                      │ - Stabilize
 │                    │                      │ - Audio Analysis
 │                    │                      │ - Audio Score
 │                    │                      │ - OpenPose
 │                    │                      │ - Ball Tracking
 │                    │<─ 200 OK + result ───│
 │                    │                      │
 │                    ├─ 標記為 'completed'  │
 │                    │ (或 'failed' 並重試) │
 │                    │                      │
 ├──GET /stats ──────>│                      │
 │<─ 統計資訊 ────────│                      │
 │                    │                      │
```

## 數據流

### 1. 入隊 (Enqueue)
```
POST /api/processqueue/enqueue
├─ 驗證 videoId 存在
├─ 檢查是否已在隊列中
└─ 建立 ProcessQueueItem
    └─ Status: "queued"
    └─ Priority: 0 (或指定值)
    └─ CreatedAt: now
```

### 2. 處理 (Process)
```
MeshFlowProcessingService (每秒執行一次)
├─ 查詢 Status='queued' 的第一項
├─ 標記為 "processing" + StartedAt=now
├─ 從 Files 表取得視頻路徑
├─ 呼叫 Python API
│  ├─ 成功 → Status='completed' + CompletedAt=now
│  └─ 失敗 → RetryCount++
│     ├─ 若 RetryCount < 3 → Status='queued' (重新排隊)
│     └─ 若 RetryCount >= 3 → Status='failed' + ErrorMessage
└─ 保存到資料庫
```

### 3. 查詢 (Query)
```
GET /api/processqueue/stats
└─ 計算各狀態的計數
    ├─ queued (待處理)
    ├─ processing (處理中)
    ├─ completed (已完成)
    └─ failed (已失敗)
```

## 關鍵設置

| 設置項 | 值 | 說明 |
|--------|-----|------|
| CHECK_INTERVAL_MS | 1000 | 每 1 秒檢查一次隊列 |
| API_TIMEOUT_SECONDS | 300 | API 最長等待 5 分鐘 |
| MAX_RETRY_COUNT | 3 | 失敗最多重試 3 次 |
| MeshFlow:ApiBaseUrl | http://localhost:5001 | Python API 地址 |

## 使用範例

### 1. 添加影片到隊列

```bash
curl -X POST http://localhost:5000/api/processqueue/enqueue \
  -H "Content-Type: application/json" \
  -d '{"videoId": "550e8400-e29b-41d4-a716-446655440000", "priority": 0}'
```

### 2. 查詢隊列狀態

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
    "completed": 42,
    "failed": 0
  }
}
```

### 3. 查詢隊列項目

```bash
curl "http://localhost:5000/api/processqueue?status=processing&limit=10"
```

### 4. 批量添加

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
curl -X PUT http://localhost:5000/api/processqueue/abc-123-def/retry
```

## 系統整合

### 與 Python MeshFlow API 的連接

```csharp
// MeshFlowProcessingService 中
var response = await _httpClient.PostAsync(
    $"{_meshflowApiBaseUrl}/api/meshflow",
    jsonContent);

// API 請求體
{
  "input_dir": "/path/to/video/directory",
  "output_dir": "/path/to/output",
  "roi": [742, 255],
  "frames": 300,
  "roi_size": 200,
  ...
}

// API 回應
{
  "success": true,
  "message": "流程執行成功",
  "data": {
    "steps": { ... },
    "final_outputs": [ ... ]
  }
}
```

### 與資料庫的連接

- **ProcessQueue 表**: 存儲隊列項目狀態
- **Videos 表**: 儲存影片信息
- **Files 表**: 儲存影片檔案路徑

## 下一步建議

### 1. 測試
- [ ] 單元測試 ProcessQueueController
- [ ] 集成測試 MeshFlowProcessingService
- [ ] 端對端測試完整流程

### 2. 監控
- [ ] 添加 Health Check 端點
- [ ] 集成 Application Insights 監控
- [ ] 設置告警規則

### 3. 優化
- [ ] 實現分散式鎖防止重複處理
- [ ] 添加任務優先級隊列
- [ ] 實現並行處理 (多個 Worker)
- [ ] 集成消息隊列 (RabbitMQ/Kafka)

### 4. 功能擴展
- [ ] 支持複雜的調度規則 (Cron)
- [ ] 添加進度通知 (WebSocket)
- [ ] 實現結果回調機制
- [ ] 支持長期運行的任務

## 測試命令

### 1. 啟動服務
```bash
# Python MeshFlow API
cd meshflow_stabilize_with_audio_V2
python -m flask run --port 5001

# C# 伺服器
cd server
dotnet run
```

### 2. 測試工作流

```bash
# 1. 查詢初始狀態
curl http://localhost:5000/api/processqueue/stats

# 2. 添加影片 (假設已上傳，videoId 為已知值)
VIDEO_ID="550e8400-e29b-41d4-a716-446655440000"
curl -X POST http://localhost:5000/api/processqueue/enqueue \
  -H "Content-Type: application/json" \
  -d "{\"videoId\": \"$VIDEO_ID\"}"

# 3. 等待 1-2 秒

# 4. 查詢狀態 (應看到 processing 或 completed)
curl http://localhost:5000/api/processqueue/stats

# 5. 查詢詳情
curl "http://localhost:5000/api/processqueue?status=completed"
```

## 故障排除檢查列表

- [ ] Python API 伺服器是否運行？ (`http://localhost:5001`)
- [ ] C# 伺服器是否啟動？ (`http://localhost:5000`)
- [ ] 資料庫連接是否正常？
- [ ] 影片檔案路徑是否正確？
- [ ] 日誌中是否有錯誤信息？
- [ ] 防火牆是否允許 5000 和 5001 埠口？

---

**狀態**: ✅ 已完成所有核心功能  
**最後更新**: 2024年  
**版本**: 1.0
