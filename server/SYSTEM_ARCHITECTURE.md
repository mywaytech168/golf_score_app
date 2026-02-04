# 系統架構與集成圖

## 完整系統架構圖

```
┌────────────────────────────────────────────────────────────────────────────────┐
│                           Client Applications                                  │
│                    (Web UI / Mobile App / Desktop)                             │
└────────────────────────────────┬───────────────────────────────────────────────┘
                                 │
                    HTTP REST API Calls
                                 │
        ┌────────────────────────┼────────────────────────┐
        │                        │                        │
        ↓                        ↓                        ↓
┌──────────────────────┐  ┌──────────────────────┐  ┌──────────────────────┐
│  Upload Controller   │  │ Video Controller     │  │ ProcessQueue         │
│                      │  │                      │  │ Controller           │
│ POST /upload         │  │ GET /videos/{id}     │  │                      │
│ POST /videos         │  │ GET /user/videos     │  │ POST /enqueue        │
│ DELETE /videos/{id}  │  │ DELETE /videos/{id}  │  │ GET /stats           │
└──────┬───────────────┘  └──────┬───────────────┘  │ GET /processqueue    │
       │                         │                  │ PUT /retry           │
       │                         │                  │ DELETE /clear-failed │
       └─────────────────────────┼──────────────────┴──────────────────────┘
                                 │
                    ┌────────────┴────────────┐
                    │                         │
                    ↓                         ↓
        ┌──────────────────────┐   ┌──────────────────────┐
        │ VideoUploadService   │   │ AuthService          │
        │                      │   │                      │
        │ - 處理上傳           │   │ - JWT 驗證           │
        │ - 檔案儲存           │   │ - 用戶認證           │
        │ - 切片管理           │   │ - 權限檢查           │
        └──────┬───────────────┘   └──────┬───────────────┘
               │                          │
               ↓                          ↓
        ┌─────────────────────────────────────────────┐
        │         Entity Framework Core               │
        │         (Code-First ORM)                    │
        └──────────────────────┬──────────────────────┘
                               │
                 ┌─────────────┴─────────────┐
                 │                           │
                 ↓                           ↓
        ┌──────────────────────┐   ┌──────────────────────┐
        │   MySQL Database     │   │  File System         │
        │   (\\server\TekSwing) │   │  (Local Storage)     │
        │                      │   │                      │
        │ Tables:              │   │ /videos/             │
        │ - users              │   │ /uploads/            │
        │ - videos             │   │ /meshflow_output/    │
        │ - files              │   │                      │
        │ - process_queue      │   │                      │
        └──────────┬───────────┘   └──────────────────────┘
                   │
                   │ FOREIGN KEYS:
                   │ videos.user_id → users.id
                   │ files.video_id → videos.id
                   │ process_queue.video_id → videos.id
                   │
                   └──────────────────────────────────────


                    ┌─────────────────────────────────────┐
                    │   MESHFLOW 後台處理系統              │
                    │   (MeshFlowProcessingService)       │
                    │   HostedService - 後台執行          │
                    └──────────────┬──────────────────────┘
                                   │
                    ┌──────────────┴──────────────┐
                    │   每秒執行一次              │
                    └──────────────┬──────────────┘
                                   │
                ┌──────────────────┴──────────────────┐
                │                                     │
                ↓                                     ↓
        ┌──────────────────────┐           ┌──────────────────────┐
        │ CheckAndProcessQueue │           │  ProcessQueueItem    │
        │                      │           │  state machine       │
        │ 1. 查詢 status=queue │           │                      │
        │ 2. 按優先級排序      │           │ queued              │
        │ 3. 取出第一筆        │           │   ↓                 │
        │ 4. 標記 processing   │           │ processing          │
        └──────────┬───────────┘           │   ↓                 │
                   │                       │ completed ✓         │
                   │                       │   OR                │
                   │                       │ failed (retry >= 3) │
                   │                       └──────────────────────┘
                   │
                   ↓
        ┌──────────────────────┐
        │ ProcessQueueItem     │
        │                      │
        │ - Id (UUID)          │ GET from Files table
        │ - VideoId (FK)       │      ↓
        │ - Status             │ Video file path
        │ - Priority           │      ↓
        │ - CreatedAt          │ /videos/xyz.mp4
        │ - StartedAt          │
        │ - CompletedAt        │
        │ - RetryCount         │
        │ - ErrorMessage       │
        └──────────┬───────────┘
                   │
                   ↓
        ┌──────────────────────────────────────┐
        │  CallMeshFlowApiAsync                │
        │                                      │
        │  構建 HTTP POST 請求:                │
        │  {                                   │
        │    "input_dir": "/path/to/videos",   │
        │    "output_dir": "/path/to/output",  │
        │    "roi": [742, 255],                │
        │    "frames": 300,                    │
        │    "roi_size": 200,                  │
        │    ...                               │
        │  }                                   │
        └──────────┬───────────────────────────┘
                   │
                   │ HTTP POST (同步等待)
                   │
                   ↓
        ┌─────────────────────────────────────────┐
        │     Python MeshFlow API Server          │
        │     (localhost:5001)                    │
        │                                         │
        │  POST /api/meshflow                     │
        │                                         │
        │  Pipeline:                              │
        │  1. Stabilize        (MeshFlow)        │
        │  2. Audio Analysis   (Librosa+SciPy)  │
        │  3. Audio Score      (規則評分)        │
        │  4. OpenPose         (MediaPipe)       │
        │  5. Ball Tracking    (Kalman Filter)   │
        │                                         │
        │  Response:                              │
        │  {                                      │
        │    "success": true,                     │
        │    "message": "...",                    │
        │    "data": { ... }                      │
        │  }                                      │
        └──────────┬──────────────────────────────┘
                   │
                   │ 回傳回應
                   │
                   ↓
        ┌──────────────────────┐
        │ 更新隊列項目狀態     │
        │                      │
        │ if success:          │
        │   status='completed' │
        │   CompletedAt=now    │
        │ else:                │
        │   RetryCount++       │
        │   if count < 3:      │
        │     status='queued'  │
        │   else:              │
        │     status='failed'  │
        │     ErrorMessage=msg │
        └──────────┬───────────┘
                   │
                   ↓
        ┌──────────────────────┐
        │ 保存到 process_queue │
        │ 表中                 │
        └──────────────────────┘
```

## 模組互動流程圖

```
客戶端                C# 伺服器              資料庫          Python API
  │                    │                     │               │
  ├─POST /enqueue─────>│                     │               │
  │                    ├─驗證 videoId─────>  │               │
  │                    │<─回傳検查結果─────  │               │
  │                    ├─建立隊列項目──────> │               │
  │                    │                     │               │
  │                    │<─儲存完成───────────│               │
  │<─成功回應──────────┤                     │               │
  │                    │                     │               │
  │ [每秒]             │                     │               │
  │                    ├─查詢 queued 項目──> │               │
  │                    │<─取出第一筆─────────│               │
  │                    │                     │               │
  │                    ├─標記 processing────>│               │
  │                    │                     │               │
  │                    ├─查詢檔案路徑──────> │               │
  │                    │<─檔案位置───────────│               │
  │                    │                     │               │
  │                    ├──────────────POST /api/meshflow──────>│
  │                    │ (同步等待回應)      │               │ [分析]
  │                    │                     │               │
  │                    │                     │               │ - Stabilize
  │                    │                     │               │ - Analysis
  │                    │                     │               │ - Scoring
  │                    │                     │               │ - OpenPose
  │                    │                     │               │ - Tracking
  │                    │                     │               │
  │                    │<─────────200 OK + result─────────────│
  │                    │                     │               │
  │                    ├─標記 completed────>│               │
  │                    │                     │               │
  │                    │<─儲存完成───────────│               │
  │                    │                     │               │
  │─GET /stats────────>│                     │               │
  │<─統計資訊──────────┤                     │               │
  │                    │                     │               │
```

## 資料庫關聯圖

```
┌─────────────┐
│   users     │
│─────────────│
│ id (PK)     │
│ username    │
│ email       │
│ password    │
│ ...         │
└──────┬──────┘
       │ 1
       │
       │ N
       ↓
┌─────────────────────┐
│    videos           │
│─────────────────────│
│ id (PK, FK)         │
│ user_id (FK) ──────┐
│ name                │
│ status              │ ← "pending" | "uploading" 
│ type                │   "completed" | "processing" | "failed"
│ parent_video_id     │ ← 用於切片管理
│ ...                 │
└──────────┬──────────┘
           │ 1
           │
           │ N
           ↓
┌────────────────────────┐
│    files               │
│────────────────────────│
│ id (PK)                │
│ video_id (FK) ────────┐
│ type                   │ ← "original" | "clip" | "trajectory"
│ file_name              │
│ file_path              │
│ file_size              │
│ status                 │
│ ...                    │
└────────────────────────┘

        以及
        
┌────────────────────────────┐
│    process_queue           │
│────────────────────────────│
│ id (PK)                    │
│ video_id (FK) ────────────┐
│ priority                   │ ← 數值小優先處理
│ status                     │ ← "queued" | "processing"
│ assigned_worker_id         │   "completed" | "failed"
│ created_at                 │
│ started_at                 │
│ completed_at               │
│ retry_count                │
│ error_message              │
└────────────────────────────┘
```

## 元件責任矩陣

| 元件 | 責任 |
|------|------|
| ProcessQueueController | 提供 REST API、驗證輸入、調用服務 |
| MeshFlowProcessingService | 後台檢查隊列、呼叫 Python API、更新狀態 |
| VideoDbContext | 資料庫連接、ORM 映射 |
| Files/Videos/ProcessQueue 模型 | 資料結構定義 |
| Python API | 執行分析管道、返回結果 |
| HttpClient | HTTP 通訊 |
| NLog | 日誌記錄 |

## 狀態轉移圖（詳細）

```
                    入隊時
                      │
                      ↓
                   ┌─────────┐
                   │ queued  │ ← 初始狀態
                   └────┬────┘
                        │ 後台服務發現
                        ↓
                   ┌──────────────┐
                   │ processing   │ ← StartedAt 記錄
                   └────┬────┬────┘
                        │    │
              成功──────┘    └────── 失敗
              │                    │
              ↓                    ↓
         ┌─────────────┐      RetryCount++
         │ completed   │      │
         │ CompletedAt │      ├─ < 3? ─→ status='queued' ─┐
         │ 記錄        │      │                          │
         └─────────────┘      ├─ >= 3?                  │
                              │                        │
                              ↓                        │
                           ┌────────┐                  │
                           │ failed │◄──────────────────┘
                           │ Error  │
                           │ Msg    │
                           └────────┘

或者手動重試:
                     PUT /retry
                        │
                        ↓
                    ┌─────────┐
          ┌────────>│ queued  │
          │         └─────────┘
          │
    RetryCount=0
    status='queued'
```

## 調度順序圖

```
時刻  操作
────────────────────────────────────────────────────

0s   後台服務啟動

1s   - 查詢第一個 queued 項目 (Priority=0, CreatedAt=最早)
     - 標記為 processing
     - 呼叫 Python API

10s  - API 回傳完成
     - 標記為 completed
     - 查詢第二個 queued 項目
     - 標記為 processing
     - 呼叫 Python API

20s  - API 回傳完成
     - 標記為 completed
     - 查詢下一個 queued 項目 (已無)
     - 進入等待

21s  - 新項目入隊（優先級=1）
     - 查詢到該項目
     - 標記為 processing
     - 呼叫 Python API

...
```

---

**備註**: 所有時間點都是近似值，實際時間取決於 API 處理時間
