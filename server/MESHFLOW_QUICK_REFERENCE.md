# MeshFlow C# 後台服務 - 快速參考

## 系統架構

```
C# ASP.NET (localhost:5000)
    ↓
ProcessQueueController (API 端點)
    ↓
MeshFlowProcessingService (每秒檢查一次)
    ↓
Python MeshFlow API (localhost:5001)
    ↓
分析結果 → 更新資料庫
```

## 核心概念

### 1. 隊列 (Queue)
- 存儲在 `ProcessQueue` 表中
- 每個項目有唯一 UUID (`Id`)
- 關聯至 `Videos` 表的 UUID (`VideoId`)
- 狀態: `queued` → `processing` → `completed`/`failed`

### 2. 優先級 (Priority)
- 數值越小，優先級越高
- 同優先級按建立時間排序 (FIFO)
- 範例:
  - Priority = 0: 立即處理
  - Priority = 1: 次序處理
  - Priority = 10: 最後處理

### 3. 重試 (Retry)
- 失敗最多重試 3 次
- 每次重試重新入隊
- 達到上限後標記為 `failed`

## 快速命令

### 啟動服務

```bash
# 終端 1: 啟動 Python MeshFlow API
cd meshflow_stabilize_with_audio_V2
python -m flask run --port 5001

# 終端 2: 啟動 C# 伺服器
cd server
dotnet run
```

### API 調用

```bash
# 查詢隊列統計
curl http://localhost:5000/api/processqueue/stats

# 添加單個影片
curl -X POST http://localhost:5000/api/processqueue/enqueue \
  -H "Content-Type: application/json" \
  -d '{"videoId": "YOUR_VIDEO_UUID"}'

# 添加多個影片
curl -X POST http://localhost:5000/api/processqueue/enqueue-batch \
  -H "Content-Type: application/json" \
  -d '{
    "videoIds": ["id-1", "id-2", "id-3"],
    "priority": 0
  }'

# 查詢待處理的項目
curl "http://localhost:5000/api/processqueue?status=queued"

# 查詢正在處理的項目
curl "http://localhost:5000/api/processqueue?status=processing"

# 查詢已完成的項目
curl "http://localhost:5000/api/processqueue?status=completed"

# 查詢失敗的項目
curl "http://localhost:5000/api/processqueue?status=failed"

# 重試失敗的項目
curl -X PUT http://localhost:5000/api/processqueue/QUEUE_ID/retry

# 清除所有失敗項目
curl -X DELETE http://localhost:5000/api/processqueue/clear-failed
```

## 重要文件位置

| 文件 | 路徑 | 說明 |
|------|------|------|
| 後台服務 | `server/Services/MeshFlowProcessingService.cs` | 核心後台邏輯 |
| 控制器 | `server/Controllers/ProcessQueueController.cs` | REST API 端點 |
| 模型 | `server/Models/ProcessQueueItem.cs` | 隊列項目資料模型 |
| 資料庫 | `server/Data/VideoDbContext.cs` | EF Core 資料庫上下文 |
| 配置 | `server/appsettings.json` | MeshFlow API 地址 |
| 程式進入點 | `server/Program.cs` | 服務註冊 |
| 完整指南 | `server/MESHFLOW_INTEGRATION_GUIDE.md` | 詳細文檔 |

## 狀態轉移圖

```
                    ┌──────────┐
                    │  queued  │ ← 添加到隊列 / 重試
                    └─────┬────┘
                          │
                          ↓
                    ┌──────────────┐
                    │  processing  │ ← 後台服務取出
                    └─────┬────────┘
                          │
                ┌─────────┴──────────┐
                ↓                    ↓
          ┌─────────────┐    ┌──────────┐
          │ completed   │    │ failed   │
          │ (已完成)     │    │ (已失敗) │
          └─────────────┘    └──────────┘
                ↑                   ↑
                │                   │
              成功                失敗 × 3 次
                                 (無法重試)
```

## 配置說明

### appsettings.json - MeshFlow 段

```json
{
  "MeshFlow": {
    "ApiBaseUrl": "http://localhost:5001",
    "Enabled": true
  }
}
```

**環境變數覆蓋** (如需要):
```bash
MeshFlow__ApiBaseUrl=http://your-server:5001
```

## 常見問題

### Q: 如何確認後台服務正在運行?

**A**: 
1. 查看應用啟動日誌，應看到: `✅ MeshFlow 後台處理服務已註冊`
2. 查看日誌檔案 (logs/YYYY-MM-DD.log)
3. 呼叫 `/api/processqueue/stats` 查看是否有變化

### Q: 影片卡在 "processing" 狀態怎麼辦?

**A**: 
1. 檢查 Python API 是否運行
2. 檢查網路連接
3. 查看詳細日誌找出具體錯誤
4. 手動調用 `/retry` 端點重試

### Q: 如何並行處理多個影片?

**A**: 
- 目前實現為每秒取一個進行同步處理
- 可通過添加多個 C# 伺服器實例實現並行 (需要分散式鎖)
- 或修改服務為非同步並行処理

### Q: 如何取消正在處理的任務?

**A**: 
- 當前版本不支持中途取消
- 可刪除隊列項目後手動停止 Python 進程

## 日誌位置

```
server/logs/YYYY-MM-DD.log
```

**日誌示例**:
```
2024-02-01 10:30:45 INFO 🚀 MeshFlow 後台處理服務已啟動
2024-02-01 10:30:46 DEBUG 📋 找到待處理項目: queue-123 (Video: video-456)
2024-02-01 10:30:46 INFO ⚙️  開始處理隊列項目: queue-123
2024-02-01 10:30:46 INFO 📹 影片檔案路徑: \\server\videos\video.mp4
2024-02-01 10:30:46 INFO 🌐 呼叫 MeshFlow API: http://localhost:5001/api/meshflow
2024-02-01 10:30:250 INFO ✅ 分析完成 - 流程執行成功
```

## 資料庫查詢

### 查看隊列狀態

```sql
SELECT 
    Status,
    COUNT(*) as Count,
    MIN(CreatedAt) as OldestItem
FROM process_queue
GROUP BY Status;
```

### 查看失敗項目

```sql
SELECT 
    id,
    video_id,
    retry_count,
    error_message,
    created_at
FROM process_queue
WHERE status = 'failed'
ORDER BY created_at DESC;
```

### 查看處理時間

```sql
SELECT 
    id,
    TIMESTAMPDIFF(SECOND, started_at, completed_at) as processing_time_sec,
    status
FROM process_queue
WHERE status = 'completed'
ORDER BY completed_at DESC
LIMIT 10;
```

## 效能指標

| 指標 | 數值 | 說明 |
|------|------|------|
| 檢查間隔 | 1 秒 | 每秒檢查一次隊列 |
| 最大並行 | 1 | 當前為同步單線程 |
| API 超時 | 300 秒 | 5 分鐘超時設定 |
| 最大重試 | 3 次 | 失敗最多重試 3 次 |

## 技術棧

- **後端框架**: ASP.NET Core 6+
- **資料庫**: MySQL/EF Core Code-First
- **日誌**: NLog
- **HTTP 客戶端**: HttpClient (內建)
- **序列化**: System.Text.Json

## 相關檔案

| 檔案 | 用途 |
|------|------|
| `server/Services/MeshFlowProcessingService.cs` | 後台服務核心 |
| `server/Controllers/ProcessQueueController.cs` | REST API |
| `server/Program.cs` | 依賴注入和啟動 |
| `server/appsettings.json` | 組態設定 |
| `meshflow_stabilize_with_audio_V2/server.py` | Python API |

## 下一步

1. ✅ 實現基本後台隊列處理
2. ✅ 實現 REST API 端點
3. ⏳ 添加監控和告警
4. ⏳ 實現分散式處理
5. ⏳ 添加 WebSocket 進度通知

---

**快速入門**: 見 MESHFLOW_INTEGRATION_GUIDE.md  
**故障排除**: 見 MESHFLOW_INTEGRATION_GUIDE.md 末尾
