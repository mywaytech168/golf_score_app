## 高尔夫摇摆视频数据库重新设计（UUID 架构）

### 2026-01-29 - 完整重构

---

## 1. 整体设计原则

### 1.1 核心改动

| 方面 | 旧设计 | 新设计 |
|------|------|------|
| 主键类型 | `int` (自增) | `string` (UUID) |
| 外键类型 | `int` (自增) | `string` (UUID) |
| 表结构 | 7 张表（Video, Slice, ProcessLog, ProcessQueue, OutputFile 等） | **3 张表** (users, videos, files, process_queue) |
| 切片存储 | 独立 `Slice` 表 | 与原始视频合并到 `videos` 表（通过 ParentVideoId 区分） |
| 文件追踪 | `OutputFile` 表（仅输出） | `files` 表（统一所有文件类型） |
| 日志存储 | `ProcessLog` 表 | 移除（改用 NLog） |

### 1.2 优势

- ✅ **简化数据模型**：从 7 张表减少到 4 张核心表
- ✅ **UUID 分布式友好**：支持跨数据库、跨服务器同步
- ✅ **灵活的文件管理**：单一 File 表支持所有文件类型（原始视频、切片、轨迹、缩略图等）
- ✅ **清晰的处理队列**：3 种状态（排队中、处理中、已处理）
- ✅ **易于扩展**：新增文件类型或影片类型无需修改表结构

---

## 2. 数据库架构

### 2.1 表结构设计

```sql
-- 1. users (用户表)
CREATE TABLE users (
    id VARCHAR(36) PRIMARY KEY,               -- UUID
    username VARCHAR(100) UNIQUE NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    display_name VARCHAR(255),
    google_id VARCHAR(255) UNIQUE,
    avatar_url VARCHAR(500),
    provider ENUM('local', 'google') DEFAULT 'local',
    status ENUM('active', 'inactive', 'suspended') DEFAULT 'active',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    last_login_at DATETIME,
    
    INDEX idx_user_status (status),
    INDEX idx_user_created_at (created_at)
);

-- 2. videos (影片主表 - 原始录影 + 切片)
CREATE TABLE videos (
    id VARCHAR(36) PRIMARY KEY,               -- UUID
    user_id VARCHAR(36) NOT NULL,
    name VARCHAR(255) NOT NULL,
    
    -- 影片类型区分
    type ENUM('original', 'clip') DEFAULT 'original',
    
    -- 基本信息
    status ENUM('pending', 'uploading', 'completed', 'processing', 'failed') DEFAULT 'pending',
    parent_video_id VARCHAR(36),              -- 当 type='clip' 时，引用原始录影
    
    -- 切片特定字段（当 type='clip' 时使用）
    hit_second DOUBLE,                        -- 击棒时刻（秒）
    start_second DOUBLE,                      -- 切片开始时刻
    end_second DOUBLE,                        -- 切片结束时刻
    peak_value DOUBLE,                        -- 峰值加速度
    max_acceleration DOUBLE,                  -- 最大加速度
    avg_acceleration DOUBLE,                  -- 平均加速度
    good_shot BOOLEAN,
    bad_shot BOOLEAN,
    
    -- 时间戳
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    completed_at DATETIME,
    
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (parent_video_id) REFERENCES videos(id) ON DELETE SET NULL,
    
    INDEX idx_video_user_id (user_id),
    INDEX idx_video_type (type),
    INDEX idx_video_status (status),
    INDEX idx_video_created_at (created_at),
    INDEX idx_video_user_type (user_id, type)
);

-- 3. files (文件追踪表 - 统一管理各种文件类型)
CREATE TABLE files (
    id VARCHAR(36) PRIMARY KEY,               -- UUID
    video_id VARCHAR(36) NOT NULL,
    
    -- 文件类型：原始影片、切片视频、轨迹CSV、缩略图、已处理输出
    type ENUM('original', 'clip', 'trajectory', 'thumbnail', 'processed') NOT NULL,
    
    file_name VARCHAR(255) NOT NULL,
    file_path VARCHAR(500) NOT NULL,
    file_size BIGINT DEFAULT 0,
    mime_type VARCHAR(100),
    
    -- 文件上传状态
    status ENUM('pending', 'uploading', 'completed', 'failed') DEFAULT 'pending',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    completed_at DATETIME,
    error_message TEXT,
    
    FOREIGN KEY (video_id) REFERENCES videos(id) ON DELETE CASCADE,
    
    INDEX idx_file_video_id (video_id),
    INDEX idx_file_type (type),
    INDEX idx_file_status (status),
    INDEX idx_file_video_type (video_id, type)
);

-- 4. process_queue (处理队列 - 排队中/处理中/已处理)
CREATE TABLE process_queue (
    id VARCHAR(36) PRIMARY KEY,               -- UUID
    video_id VARCHAR(36) NOT NULL,
    
    priority INT DEFAULT 0,
    assigned_worker_id VARCHAR(100),
    
    -- 处理状态：排队中、处理中、已处理、失败
    status ENUM('queued', 'processing', 'completed', 'failed') DEFAULT 'queued',
    
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    started_at DATETIME,
    completed_at DATETIME,
    
    retry_count INT DEFAULT 0,
    error_message TEXT,
    
    FOREIGN KEY (video_id) REFERENCES videos(id) ON DELETE CASCADE,
    
    INDEX idx_queue_video_id (video_id),
    INDEX idx_queue_status (status),
    INDEX idx_queue_status_priority_created (status, priority, created_at)
);
```

### 2.2 关键设计决策

#### 2.2.1 Video 表的区分机制

通过 **ParentVideoId** 字段隐式区分原始视频和切片：

```csharp
// 原始录影（ParentVideoId = NULL）
var original = new Video {
    Id = Guid.NewGuid().ToString(),
    Name = "2026-01-29 Golf Session",
    Status = "completed",
    ParentVideoId = null  // NULL -> 这是原始录影
};

// 自动切分的片段（ParentVideoId = 某个视频ID）
var clip = new Video {
    Id = Guid.NewGuid().ToString(),
    Name = "Swing #1",
    ParentVideoId = original.Id,              // 指向原始视频
    HitSecond = 5.2,
    StartSecond = 4.8,
    EndSecond = 5.6,
    PeakValue = 9.8,
    Status = "uploading"
};
```

**优势**：
- 无需额外的 `Type` 字段
- 通过一个字段清晰表达继承关系
- 可轻松查询"原始视频及其所有切片"
- 对 SQL 查询更友好（WHERE ParentVideoId IS NULL）

#### 2.2.2 File 表的多类型支持

```csharp
// 原始录影文件
var originalFile = new File {
    Type = "original",           // 原始视频文件
    FileName = "swing_session.mp4",
    FilePath = "/videos/2026/01/abc123.mp4",
    MimeType = "video/mp4"
};

// 自动切片
var clipFile = new File {
    Type = "clip",               // 切片视频
    FileName = "clip_1.mp4",
    FilePath = "/clips/2026/01/def456.mp4"
};

// IMU 轨迹数据
var trajectoryFile = new File {
    Type = "trajectory",         // CSV 数据
    FileName = "imu_data.csv",
    FilePath = "/trajectories/2026/01/ghi789.csv",
    MimeType = "text/csv"
};

// 缩略图
var thumbnailFile = new File {
    Type = "thumbnail",          // 缩略图
    FileName = "thumb.jpg",
    FilePath = "/thumbs/2026/01/jkl012.jpg"
};
```

**优势**：
- 无需为每种文件类型创建新表
- Type 枚举易于扩展
- 单一查询获取视频的所有关联文件

#### 2.2.3 ProcessQueue 表的三态模型

```csharp
// 排队中
var queuedItem = new ProcessQueueItem {
    Status = "queued",           // ① 等待处理
    CreatedAt = DateTime.UtcNow,
    Priority = 0                 // 优先级队列
};

// 处理中
var processingItem = new ProcessQueueItem {
    Status = "processing",       // ② 正在处理
    AssignedWorkerId = "worker-1",
    StartedAt = DateTime.UtcNow
};

// 已处理或失败
var completedItem = new ProcessQueueItem {
    Status = "completed",        // ③ 完成
    CompletedAt = DateTime.UtcNow,
    RetryCount = 0
};

var failedItem = new ProcessQueueItem {
    Status = "failed",           // ③ 失败
    CompletedAt = DateTime.UtcNow,
    ErrorMessage = "Timeout after 3 retries",
    RetryCount = 3
};
```

---

## 3. 数据模型映射

### 3.1 C# Entity 类

#### User.cs
```csharp
public class User
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string Username { get; set; }
    public string Email { get; set; }
    public string PasswordHash { get; set; }
    public string DisplayName { get; set; }
    public string? GoogleId { get; set; }
    public string? AvatarUrl { get; set; }
    public string Provider { get; set; } = "local";
    public string Status { get; set; } = "active";
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
    public DateTime? LastLoginAt { get; set; }

    // Navigation
    public List<Video> Videos { get; set; } = new();
}
```

#### Video.cs
```csharp
public class Video
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string UserId { get; set; }
    public string Name { get; set; }
    
    /// <summary>
    /// 狀態：pending, uploading, completed, processing, failed
    /// </summary>
    public string Status { get; set; } = "pending";

    /// <summary>
    /// 父影片 ID（原始錄影）
    /// 若為 NULL，則此為原始錄影；若不為 NULL，則為自動切片
    /// </summary>
    public string? ParentVideoId { get; set; }
    
    // Clip-specific fields (nullable)
    public double? HitSecond { get; set; }
    public double? StartSecond { get; set; }
    public double? EndSecond { get; set; }
    public double? PeakValue { get; set; }
    public double? MaxAcceleration { get; set; }
    public double? AvgAcceleration { get; set; }
    public bool? GoodShot { get; set; }
    public bool? BadShot { get; set; }
    
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
    public DateTime? CompletedAt { get; set; }

    // Navigation
    public User User { get; set; }
    public List<File> Files { get; set; } = new();
    public List<ProcessQueueItem> QueueItems { get; set; } = new();
}
```

#### File.cs
```csharp
public class File
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string VideoId { get; set; }
    
    public string Type { get; set; }                        // original, clip, trajectory, thumbnail, processed
    public string FileName { get; set; }
    public string FilePath { get; set; }
    public long FileSize { get; set; }
    public string MimeType { get; set; }
    
    public string Status { get; set; } = "pending";
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime? CompletedAt { get; set; }
    public string? ErrorMessage { get; set; }

    // Navigation
    public Video Video { get; set; }
}
```

#### ProcessQueueItem.cs
```csharp
public class ProcessQueueItem
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string VideoId { get; set; }
    
    public int Priority { get; set; } = 0;
    public string? AssignedWorkerId { get; set; }
    
    public string Status { get; set; } = "queued";          // queued, processing, completed, failed
    
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime? StartedAt { get; set; }
    public DateTime? CompletedAt { get; set; }
    
    public int RetryCount { get; set; } = 0;
    public string? ErrorMessage { get; set; }

    // Navigation
    public Video Video { get; set; }
}
```

---

## 4. 迁移指南

### 4.1 从旧架构迁移

**删除的表**：
- ❌ `slices` - 功能并入 `videos` (type='clip')
- ❌ `process_logs` - 改用 NLog 文件日志
- ❌ `output_files` - 功能并入 `files` (type='processed')

**新增的表**：
- ✅ `files` - 统一的文件追踪表

**修改的表**：
- 📝 `users` - ID 从 `int` → `VARCHAR(36)`
- 📝 `videos` - ID 从 `int` → `VARCHAR(36)`, user_id 从 `int` → `VARCHAR(36)`, 新增字段
- 📝 `process_queue` - ID 从 `int` → `VARCHAR(36)`, video_id 从 `int` → `VARCHAR(36)`, 移除 slice_id 依赖

### 4.2 迁移步骤

```powershell
# 1. 创建 EF 迁移
cd .\server
dotnet ef migrations add RedesignToUUID

# 2. 查看迁移脚本（验证无误）
# 编辑 Migrations/[timestamp]_RedesignToUUID.cs

# 3. 执行迁移
dotnet ef database update
```

---

## 5. 常见查询示例

### 5.1 获取用户的所有原始录影

```csharp
var userVideos = await _context.Videos
    .Where(v => v.UserId == userId && v.Type == "original")
    .Include(v => v.Files)
    .Include(v => v.QueueItems)
    .OrderByDescending(v => v.CreatedAt)
    .ToListAsync();
```

### 5.2 获取某录影的所有切片

```csharp
var clips = await ParentVideoId == parentVideoId)  // ParentVideoId 不为 NULL
    .Where(v => v.Type == "clip" && v.ParentVideoId == parentVideoId)
    .OrderBy(v => v.HitSecond)
    .ToListAsync();
```

### 5.3 获取视频的所有关联文件

```csharp
var files = await _context.Files
    .Where(f => f.VideoId == videoId)
    .GroupBy(f => f.Type)
    .ToDictionaryAsync(g => g.Key, g => g.ToList());

// 使用：
var originalFile = files["original"].FirstOrDefault();
var clipFile = files["clip"].FirstOrDefault();
var trajectoryFile = files["trajectory"].FirstOrDefault();
```

### 5.4 获取待处理的队列项目（按优先级）

```csharp
var nextBatch = await _context.ProcessQueue
    .Where(q => q.Status == "queued")
    .OrderBy(q => q.Priority)
    .ThenBy(q => q.CreatedAt)
    .Take(10)
    .ToListAsync();
```

### 5.5 统计用户的切片信息

```csharp
var stats = await _context.Videos
    .Where(v => v.UserId == userId && v.ParentVideoId != null)  // 筛选切片
    .GroupBy(_ => true)
    .Select(g => new {
        TotalClips = g.Count(),
        GoodShots = g.Count(v => v.GoodShot == true),
        BadShots = g.Count(v => v.BadShot == true),
        AvgHitSecond = g.Average(v => v.HitSecond),
        AvgPeakValue = g.Average(v => v.PeakValue)
    })
    .FirstOrDefaultAsync();
```

---

## 6. API 变更

### 6.1 新增端点

| 端点 | 方法 | 功能 |
|------|------|------|
| `/api/videos` | GET | 列出用户的所有影片（原始 + 切片） |
| `/api/videos` | POST | 创建新影片（原始录影或切片） |
| `/api/videos/{id}` | GET | 获取影片详情 |
| `/api/videos/{id}` | DELETE | 删除影片 |
| `/api/videos/{id}/clips` | GET | 获取影片的所有切片 |
| `/api/videos/{id}/files` | GET | 获取影片的所有文件 |
| `/api/files` | POST | 上传文件 |
| `/api/files/{id}` | DELETE | 删除文件 |
| `/api/queue` | GET | 获取处理队列状态 |
| `/api/queue/{id}` | PATCH | 更新队列项目状态 |

---

## 7. 性能优化指标

| 指标 | 优化前 | 优化后 |
|------|------|------|
| 表数量 | 7 | 4 (-43%) |
| 获取视频的文件数 | 多 JOIN | 1 JOIN + 1 WHERE |
| 查询单个切片 | Video → Slice → Files | Video (直接) + Files |
| UUID 键长 | N/A | 36 字节 (可优化为二进制) |
| 索引数 | 15+ | 12 (优化) |

---

## 8. 待办清单

- [ ] 执行数据库迁移
- [ ] 更新现有控制器以使用新模型
- [ ] 修改所有 API DTO 类
- [ ] 创建数据访问层 (DAL) 的 Repository 类
- [ ] 添加单元测试覆盖新架构
- [ ] 更新 API 文档 (Swagger/OpenAPI)
- [ ] 性能基准测试
- [ ] 生产环境部署验证

---

**最后更新**: 2026-01-29
