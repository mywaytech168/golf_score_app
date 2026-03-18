# 🏌️ 系統審查報告 - 已實作 vs 未實作

**報告生成日期**: 2026-02-02  
**系統**: 高爾夫球軌跡分析平台

---

## 📊 架構概覽

```
Client (Flutter App)
         ↓
┌────────────────────────────────────────────┐
│  C# Server (UploadServer)                  │
│  - 檔案上傳接收                             │
│  - 資料庫管理 (EF Core)                     │
│  - 認證授權 (JWT)                           │
│  - 排程服務 ❌ 未實作                       │
│  - 回調接收 ❌ 未實作                       │
└────────────────────────────────────────────┘
         ↓
┌────────────────────────────────────────────┐
│  Python Server (MeshFlow V2)               │
│  - 影片穩定化                              │
│  - 音頻分析                                 │
│  - 高爾夫揮桿評分                           │
│  - 姿勢識別 (OpenPose)                      │
│  - 球軌跡追蹤                               │
│  - 任務隊列 ❌ 未實作                       │
│  - 排程器 ❌ 未實作                         │
└────────────────────────────────────────────┘
```

---

## ✅ 已實作的功能

### C# 服務器 (UploadServer)

| 功能 | 狀態 | 位置 |
|------|------|------|
| 檔案上傳接收 | ✅ | [VideoController.cs](server/Controllers/VideoController.cs#L150) |
| 影片紀錄建立 | ✅ | [VideoUploadService.cs](server/Services/VideoUploadService.cs#L40) |
| 檔案存儲管理 | ✅ | [VideoUploadService.cs](server/Services/VideoUploadService.cs#L68) |
| 資料庫模型 (EF Core) | ✅ | [Models/](server/Models/) |
| JWT 認證 | ✅ | [Program.cs](server/Program.cs#L100) |
| 資料庫遷移 | ✅ | [Migrations/](server/Migrations/) |
| 日誌系統 (NLog) | ✅ | [Program.cs](server/Program.cs#L1) |
| 處理隊列資料模型 | ✅ | [ProcessQueueItem.cs](server/Models/ProcessQueueItem.cs) |
| Swagger API 文檔 | ✅ | [Program.cs](server/Program.cs#L125) |

**資料庫表結構**:
- `videos` - 影片主紀錄
- `users` - 用戶帳戶
- `files` - 上傳的檔案
- `process_queue` - 處理隊列（已建立但未使用）

### Python 服務器 (MeshFlow V2)

| 功能 | 狀態 | 位置 |
|------|------|------|
| 影片穩定化 (Stabilization) | ✅ | [functions/meshflow_stabilization.py](meshflow_stabilize_with_audio_V2/functions/meshflow_stabilization.py) |
| 音頻分析 | ✅ | [functions/audio_analysis.py](meshflow_stabilize_with_audio_V2/functions/audio_analysis.py) |
| 高爾夫揮桿評分 | ✅ | [functions/audio_scoring.py](meshflow_stabilize_with_audio_V2/functions/audio_scoring.py) |
| 姿勢識別 (OpenPose/MediaPose) | ✅ | [functions/openpose_analysis.py](meshflow_stabilize_with_audio_V2/functions/openpose_analysis.py) |
| 球軌跡追蹤 | ✅ | [functions/ball_tracking.py](meshflow_stabilize_with_audio_V2/functions/ball_tracking.py) |
| 完整流程管道 | ✅ | [server.py](meshflow_stabilize_with_audio_V2/server.py#L174) |
| 批量處理模式 | ✅ | [main.py](meshflow_stabilize_with_audio_V2/main.py#L60) |
| 單支視頻模式 | ✅ | [main.py](meshflow_stabilize_with_audio_V2/main.py#L40) |
| Flask REST API | ✅ | [server.py](meshflow_stabilize_with_audio_V2/server.py#L600) |

---

## ❌ 未實作的功能

### 🔴 優先級: 關鍵 - 必須實作

#### 1️⃣ C# 服務器 - 排程器 (BackgroundService)

**缺少的功能**:
- 每秒檢查一次待處理任務的排程器
- 將待處理資料夾發送到 Python 服務器
- 一次只處理一個，等待完成後再取下一個
- 失敗重試機制

**期望位置**: `server/Services/ProcessingSchedulerService.cs`

**需實作的 API 端點**: `POST /api/queue/send-task`

**代碼框架**:
```csharp
public class ProcessingSchedulerService : BackgroundService
{
    // TODO: 實作排程邏輯
    // 1. 每秒查詢 process_queue 表中 Status='queued' 的項目
    // 2. 取第一個（按優先級排序）
    // 3. HTTP POST 到 Python Server
    // 4. 更新狀態為 'processing'
    // 5. 等待回調結果
}
```

---

#### 2️⃣ C# 服務器 - 回調接收端點

**缺少的功能**:
- 接收 Python 服務器的處理結果
- 更新資料庫中的處理狀態
- 記錄成功/失敗信息

**期望位置**: `server/Controllers/CallbackController.cs` (新增)

**需實作的 API 端點**: `POST /api/callback/processing-result`

**DTO 結構**:
```csharp
public class ProcessingResultCallbackDto
{
    public string QueueItemId { get; set; }
    public bool Success { get; set; }
    public string? ErrorMessage { get; set; }
    public Dictionary<string, object>? ProcessedData { get; set; }
    public DateTime CompletedAt { get; set; }
}
```

---

#### 3️⃣ Python 服務器 - 任務隊列管理

**缺少的功能**:
- 使用 Queue 接收來自 C# Server 的任務
- 維護待處理隊列
- 併列處理隊列中的資料夾

**期望位置**: `meshflow_stabilize_with_audio_V2/services/task_queue.py` (新增)

**需實作的 API 端點**: `POST /api/tasks/process`

**代碼框架**:
```python
from queue import Queue
from threading import Thread

task_queue = Queue()
processing_lock = False

@app.route('/api/tasks/process', methods=['POST'])
def receive_task():
    # TODO: 接收 C# 發送的任務
    # 將任務加入隊列
    pass

def process_queue_scheduler():
    # TODO: 每秒處理一個任務
    # 執行 execute_pipeline()
    # 發送結果回 C#
    pass
```

---

#### 4️⃣ Python 服務器 - 回調發送

**缺少的功能**:
- 處理完成後 HTTP POST 回 C# Server
- 發送處理結果（成功/失敗）
- 重試機制

**期望位置**: `meshflow_stabilize_with_audio_V2/services/callback_sender.py` (新增)

**需實作的函數**:
```python
def send_result_to_csharp(queue_item_id, success, data=None, error=None):
    # TODO: 實作回調邏輯
    # POST 到 http://csharp-server:5001/api/callback/processing-result
    pass
```

---

### 🟡 優先級: 高 - 應該實作

#### 5️⃣ 資料庫 ProcessingResult 表

**缺少的功能**:
- 記錄每個任務的最終處理結果
- 存儲詳細的處理數據（JSON 格式）

**期望模型**: `server/Models/ProcessingResult.cs`

```csharp
public class ProcessingResult
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string QueueItemId { get; set; }
    public bool Success { get; set; }
    public string? ResultData { get; set; } // JSON
    public string? ErrorMessage { get; set; }
    public DateTime CompletedAt { get; set; }
    
    // 外鍵
    public ProcessQueueItem QueueItem { get; set; }
}
```

**需新增遷移**: `add-migration AddProcessingResult`

---

#### 6️⃣ 服務間通信配置

**缺少的功能**:
- C# Server 需要知道 Python Server 地址
- Python Server 需要知道 C# Server 地址
- 需要配置超時和重試策略

**期望位置**: `server/appsettings.json` 和 `server/Configuration/ServiceUrls.cs`

**配置範例**:
```json
{
  "ServiceUrls": {
    "PythonServerUrl": "http://python-server:5000",
    "CSharpServerUrl": "http://csharp-server:5001",
    "RequestTimeout": 300,
    "RetryAttempts": 3
  }
}
```

---

#### 7️⃣ 錯誤處理和重試機制

**缺少的功能**:
- 當 Python 服務無法連接時的重試邏輯
- 失敗任務重新排隊
- 死信隊列 (DLQ) - 多次失敗的任務

**期望位置**: `server/Services/ProcessingSchedulerService.cs`

---

#### 8️⃣ 監控和日誌

**缺少的功能**:
- 任務處理狀態的實時監控
- 詳細的處理日誌
- 性能指標 (處理時間、成功率等)

**期望位置**: `server/Controllers/MonitoringController.cs` (新增)

---

### 🟢 優先級: 低 - 可選

#### 9️⃣ Web 儀表板

**缺少的功能**:
- 實時任務監控頁面
- 處理結果查看
- 統計圖表

---

#### 🔟 Docker 編排

**缺少的功能**:
- `docker-compose.yml` 完整配置
- 容器間通信設置
- 數據持久化配置

---

## 📋 實作優先順序

### Phase 1 (立即)
1. ✋ **ProcessingSchedulerService** - C# 排程器
2. ✋ **CallbackController** - C# 回調接收
3. ✋ **task_queue.py** - Python 任務隊列
4. ✋ **callback_sender.py** - Python 回調發送

### Phase 2 (重要)
5. 📝 **ProcessingResult** 資料庫模型
6. 🔧 **服務配置** (ServiceUrls)
7. 🔄 **重試機制** 和錯誤處理

### Phase 3 (加強)
8. 📊 **監控 API**
9. 🌐 **Web 儀表板**
10. 🐳 **Docker 編排**

---

## 🔄 集成流程圖

```
┌─────────────────────────────────────────────────────────────────┐
│                        C# Server                                │
│                                                                   │
│  1. 接收切片 ✅           2. 創建隊列任務 ✅                      │
│     ↓                        ↓                                   │
│  [VideoController]      [ProcessQueueItem]                       │
│     ↓                        ↓                                   │
│  3. 儲存文件 ✅          4. 排程器檢查 ❌                         │
│     ↓                        ↓                                   │
│  [FileStorage]          [ProcessingScheduler]                    │
│     ↓                        ↓                                   │
│  5. 寫入資料庫 ✅        6. HTTP POST ❌                          │
│                              ↓                                   │
└─────────────────────────────┼──────────────────────────────────┘
                              │
                    ┌─────────▼──────────┐
                    │  Python Server     │
                    │                    │
                    │ 7. 接收任務 ❌     │
                    │    ↓               │
                    │ [task_queue.py]    │
                    │    ↓               │
                    │ 8. 排隊等待 ❌     │
                    │    ↓               │
                    │ 9. 執行管道 ✅     │
                    │    ↓               │
                    │ 10. 回調 ❌        │
                    │                    │
                    └─────────┬──────────┘
                              │
┌─────────────────────────────▼──────────────────────────────────┐
│                        C# Server                                │
│                                                                   │
│ 11. 接收回調 ❌                                                 │
│     ↓                                                           │
│ [CallbackController]                                            │
│     ↓                                                           │
│ 12. 更新隊列狀態 ❌                                             │
│     ↓                                                           │
│ 13. 保存結果 ❌                                                 │
│     ↓                                                           │
│ [ProcessingResult Table]                                        │
└─────────────────────────────────────────────────────────────────┘
```

---

## 📝 開發檢查清單

### Phase 1: 實現排程和回調機制

- [ ] 建立 `ProcessingSchedulerService.cs`
  - [ ] 實現 `BackgroundService` 基礎
  - [ ] 每秒檢查邏輯
  - [ ] HTTP 客戶端配置
  - [ ] 任務狀態更新

- [ ] 建立 `CallbackController.cs`
  - [ ] POST 端點定義
  - [ ] 結果驗證
  - [ ] 資料庫更新

- [ ] 建立 `task_queue.py`
  - [ ] Flask 路由
  - [ ] 隊列初始化
  - [ ] 排程線程

- [ ] 建立 `callback_sender.py`
  - [ ] HTTP 回調函數
  - [ ] 重試邏輯
  - [ ] 錯誤處理

### Phase 2: 資料模型和配置

- [ ] 新增 `ProcessingResult.cs` 模型
- [ ] 創建資料庫遷移
- [ ] 更新 DbContext
- [ ] 新增 `ServiceUrls` 配置
- [ ] 更新 `appsettings.json`

### Phase 3: 測試和部署

- [ ] 單元測試 (C# 排程器)
- [ ] 集成測試 (C# ↔ Python)
- [ ] 負載測試
- [ ] Docker 編排文件
- [ ] 部署文檔

---

## 📞 關鍵配置參數

```csharp
// C# Server 需要配置
- PythonServerUrl: "http://localhost:5000"
- ProcessQueueCheckInterval: 1000 (毫秒)
- RequestTimeout: 300000 (毫秒)
- MaxRetries: 3
- RetryDelayMs: 5000
```

```python
# Python Server 需要配置
- CSHARP_SERVER_URL = "http://localhost:5001"
- TASK_QUEUE_CHECK_INTERVAL = 1  # 秒
- MAX_WORKERS = 4
- REQUEST_TIMEOUT = 300  # 秒
```

---

## 💡 實作建議

1. **立即開始**: ProcessingSchedulerService，這是核心
2. **並行開發**: Python 側的任務隊列
3. **測試驅動**: 在真實環境中測試 HTTP 通信
4. **監控先行**: 早期添加日誌，便於調試
5. **容錯設計**: 考慮網絡故障和超時場景

