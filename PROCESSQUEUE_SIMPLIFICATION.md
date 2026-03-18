# ✅ ProcessQueueItem 字段精簡完成

**變更日期**: 2026-02-02

## 移除的字段

已從 `ProcessQueueItem` 模型中移除以下字段以簡化架構：

| 字段 | 原用途 | 移除原因 |
|------|--------|---------|
| `Priority` | 優先級排序 | 改用 FIFO (先進先出) |
| `AssignedWorkerId` | 工作進程分配 | 簡化設計，暫不需要 |
| `ErrorMessage` | 錯誤記錄 | 错误信息已通过 callback 传递，无需存储 |

## 保留的字段

| 字段 | 用途 |
|------|------|
| `Id` | 主鍵 (UUID) |
| `VideoId` | 關聯影片 |
| `Status` | 狀態: queued/processing/completed/failed |
| `CreatedAt` | 建立時間 |
| `StartedAt` | 開始處理時間 |
| `CompletedAt` | 完成時間 |
| `RetryCount` | 重試次數 |
| `IsSuccess` | 是否成功 (新增) |
| `ResultData` | 結果 JSON (新增) |

## 已更新的文件

### 模型 (Model)
- ✅ [server/Models/ProcessQueueItem.cs](server/Models/ProcessQueueItem.cs)

### 控制器 (Controller)
- ✅ [server/Controllers/CallbackController.cs](server/Controllers/CallbackController.cs)
  - 移除 `ErrorMessage` 賦值

### 服務 (Service)
- ✅ [server/Services/ProcessingSchedulerService.cs](server/Services/ProcessingSchedulerService.cs)
  - 修改排序邏輯：從 `Priority DESC, CreatedAt ASC` 改為 `CreatedAt ASC` (FIFO)

### 資料庫配置 (DbContext)
- ✅ [server/Data/VideoDbContext.cs](server/Data/VideoDbContext.cs)
  - 移除 Priority 配置
  - 移除 AssignedWorkerId 配置
  - 移除 ErrorMessage 配置
  - 移除索引 `idx_queue_status_priority_created`
  - 新增索引 `idx_queue_status_created`

### 資料庫遷移 (Migrations)
- ✅ [server/Migrations/20260202000002_RemoveProcessQueueFields.cs](server/Migrations/20260202000002_RemoveProcessQueueFields.cs)
- ✅ [server/Migrations/20260202000002_RemoveProcessQueueFields.Designer.cs](server/Migrations/20260202000002_RemoveProcessQueueFields.Designer.cs)
- ✅ [server/Migrations/VideoDbContextModelSnapshot.cs](server/Migrations/VideoDbContextModelSnapshot.cs)

## 最終表結構

```sql
CREATE TABLE process_queue (
  id VARCHAR(36) PRIMARY KEY,
  video_id VARCHAR(36) NOT NULL,
  status VARCHAR(50) DEFAULT 'queued',
  created_at DATETIME,
  started_at DATETIME,
  completed_at DATETIME,
  retry_count INT DEFAULT 0,
  is_success TINYINT(1) DEFAULT 0,
  result_data LONGTEXT,
  
  FOREIGN KEY (video_id) REFERENCES videos(id),
  
  INDEX idx_queue_status (status),
  INDEX idx_queue_video_id (video_id),
  INDEX idx_queue_is_success (is_success),
  INDEX idx_queue_completed_status (completed_at, status),
  INDEX idx_queue_status_created (status, created_at)
);
```

## 處理流程變更

### 舊流程 (使用 Priority)
```
Priority DESC, CreatedAt ASC
→ 高優先級先處理
→ 同優先級按創建時間 FIFO
```

### 新流程 (純 FIFO)
```
CreatedAt ASC
→ 按創建時間順序
→ 先來先服務
```

## 遷移執行步驟

```bash
# 1. 執行遷移
cd server
dotnet ef database update

# 2. 驗證表結構
# 應該看到以下已刪除：
# - assigned_worker_id 列
# - error_message 列
# - priority 列
# - idx_queue_status_priority_created 索引
#
# 應該看到以下已存在：
# - is_success 列
# - result_data 列
# - idx_queue_status_created 索引
```

## SQL 驗證命令

```sql
-- 查看表結構
DESC process_queue;

-- 查看索引
SHOW INDEXES FROM process_queue;

-- 驗證刪除列
SELECT * FROM process_queue LIMIT 0;
-- 應該看不到: assigned_worker_id, error_message, priority
```

## 簡化優勢

1. **更簡潔** - 減少 3 個不必要的字段
2. **更清楚** - 專注核心信息 (狀態、時間、結果)
3. **更快速** - 索引更簡單，查詢更快
4. **更易維護** - 減少配置複雜性

