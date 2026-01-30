# 軌跡歷史 - 後端 API 集成指南

## 概述

後端已添加對軌跡歷史功能的完整 DTO 支持，包括視頻類型、同步狀態和相關的查詢、同步操作 API。

## 文件變更

### 新增文件

#### `server/DTOs/TrajectoryHistoryDtos.cs`
包含所有軌跡歷史相關的 DTO：

```csharp
// 主要 DTO 類別：
- TrajectoryHistoryItem          // 軌跡歷史項目
- TrajectoryHistoryQueryRequest  // 查詢請求
- TrajectoryHistoryQueryResponse // 查詢響應
- SyncToCloudRequest             // 同步請求
- SyncStatusResponse             // 同步狀態響應
- TrajectoryHistoryStats         // 統計信息
- BulkOperationResponse          // 批量操作結果
- OperationError                 // 操作錯誤詳情
```

### 修改文件

#### `server/DTOs/VideoDtos.cs`

**添加的字段**：

1. **CreateVideoRequest**
   ```csharp
   /// 視頻類型："original" 或 "clip"
   public string Type { get; set; } = "original";
   ```

2. **VideoResponse**
   ```csharp
   /// 視頻類型
   public string Type { get; set; }
   
   /// 同步狀態："synced", "notSynced", "syncing", "failed"
   public string? SyncStatus { get; set; }
   ```

3. **VideoListItem**
   ```csharp
   /// 視頻類型
   public string Type { get; set; }
   
   /// 同步狀態
   public string? SyncStatus { get; set; }
   ```

## API 端點設計

### 推薦的 API 端點

#### 1. 獲取軌跡歷史列表
```http
POST /api/videos/trajectory/query
Content-Type: application/json

{
  "types": ["original", "localClip", "cloudClip"],
  "syncStatuses": ["synced", "notSynced"],
  "searchQuery": "2024-01",
  "sortBy": "newest",
  "pageNumber": 1,
  "pageSize": 20
}

Response:
{
  "items": [
    {
      "id": "video_001",
      "name": "Golf Practice",
      "type": "original",
      "syncStatus": "synced",
      "createdAt": "2024-01-29T10:00:00Z",
      "fileSize": 524288000,
      "hitSecond": 0.85,
      "startSecond": 0.2,
      "endSecond": 1.2,
      "peakValue": 45.3,
      "maxAcceleration": 32.5,
      "avgAcceleration": 18.2,
      "goodShot": true
    }
  ],
  "total": 25,
  "totalPages": 2,
  "currentPage": 1,
  "pageSize": 20
}
```

#### 2. 同步到雲端（單個）
```http
POST /api/videos/{videoId}/sync
Content-Type: application/json

{
  "targetCloud": "aws",
  "priority": 8
}

Response:
{
  "videoId": "video_001",
  "syncStatus": "syncing",
  "progressPercent": 0,
  "updatedAt": "2024-01-29T10:30:00Z"
}
```

#### 3. 批量同步
```http
POST /api/videos/sync/batch
Content-Type: application/json

{
  "videoIds": ["video_001", "video_002", "clip_001"],
  "targetCloud": "aws"
}

Response:
{
  "successfulIds": ["video_001", "clip_001"],
  "errors": [
    {
      "videoId": "video_002",
      "message": "File not found",
      "errorCode": "FILE_NOT_FOUND"
    }
  ],
  "totalCount": 3,
  "successCount": 2,
  "failureCount": 1
}
```

#### 4. 獲取統計信息
```http
GET /api/videos/trajectory/stats

Response:
{
  "originalVideos": 10,
  "localClips": 25,
  "cloudClips": 15,
  "syncedCount": 35,
  "unSyncedCount": 15,
  "syncingCount": 2,
  "failedCount": 0,
  "totalFileSize": 5368709120,
  "unSyncedFileSize": 1073741824
}
```

#### 5. 取消同步
```http
POST /api/videos/{videoId}/sync/cancel

Response:
{
  "videoId": "video_001",
  "syncStatus": "notSynced",
  "message": "Sync cancelled"
}
```

#### 6. 重試失敗的同步
```http
POST /api/videos/{videoId}/sync/retry

Response:
{
  "videoId": "video_001",
  "syncStatus": "syncing",
  "progressPercent": 5,
  "updatedAt": "2024-01-29T10:35:00Z"
}
```

## 實現步驟

### Step 1: 在 VideoService 中實現查詢方法

```csharp
public async Task<TrajectoryHistoryQueryResponse> QueryTrajectoryHistory(
    string userId, 
    TrajectoryHistoryQueryRequest request)
{
    var query = _context.Videos
        .AsNoTracking()
        .Where(v => v.UserId == userId);

    // 篩選類型
    if (request.Types?.Count > 0)
    {
        query = query.Where(v => request.Types.Contains(v.Type));
    }

    // 篩選同步狀態
    if (request.SyncStatuses?.Count > 0)
    {
        query = query.Where(v => request.SyncStatuses.Contains(v.SyncStatus ?? "notSynced"));
    }

    // 搜尋
    if (!string.IsNullOrEmpty(request.SearchQuery))
    {
        query = query.Where(v => v.Name.Contains(request.SearchQuery));
    }

    // 排序
    query = request.SortBy switch
    {
        "oldest" => query.OrderBy(v => v.CreatedAt),
        "nameAsc" => query.OrderBy(v => v.Name),
        "nameDesc" => query.OrderByDescending(v => v.Name),
        _ => query.OrderByDescending(v => v.CreatedAt), // newest
    };

    // 分頁
    var total = await query.CountAsync();
    var items = await query
        .Skip((request.PageNumber - 1) * request.PageSize)
        .Take(request.PageSize)
        .Select(v => new TrajectoryHistoryItem
        {
            Id = v.Id,
            Name = v.Name,
            Type = v.Type,
            SyncStatus = v.SyncStatus ?? "notSynced",
            ParentVideoId = v.ParentVideoId,
            CreatedAt = v.CreatedAt,
            CompletedAt = v.CompletedAt,
            FileSize = v.Files.Sum(f => f.FileSize),
            HitSecond = v.HitSecond,
            StartSecond = v.StartSecond,
            EndSecond = v.EndSecond,
            PeakValue = v.PeakValue,
            MaxAcceleration = v.MaxAcceleration,
            AvgAcceleration = v.AvgAcceleration,
            GoodShot = v.GoodShot,
            BadShot = v.BadShot,
        })
        .ToListAsync();

    var totalPages = (total + request.PageSize - 1) / request.PageSize;

    return new TrajectoryHistoryQueryResponse
    {
        Items = items,
        Total = total,
        TotalPages = totalPages,
        CurrentPage = request.PageNumber,
        PageSize = request.PageSize
    };
}
```

### Step 2: 在 VideoController 中添加端點

```csharp
[HttpPost("trajectory/query")]
[Authorize]
public async Task<ActionResult<TrajectoryHistoryQueryResponse>> QueryTrajectoryHistory(
    [FromBody] TrajectoryHistoryQueryRequest request)
{
    var userId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
    if (string.IsNullOrEmpty(userId))
        return Unauthorized();

    var result = await _videoService.QueryTrajectoryHistory(userId, request);
    return Ok(result);
}

[HttpPost("{videoId}/sync")]
[Authorize]
public async Task<ActionResult<SyncStatusResponse>> SyncToCloud(
    string videoId,
    [FromBody] SyncToCloudRequest request)
{
    var userId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
    if (string.IsNullOrEmpty(userId))
        return Unauthorized();

    var video = await _context.Videos.FindAsync(videoId);
    if (video == null)
        return NotFound();

    if (video.UserId != userId)
        return Forbid();

    // 更新同步狀態為 "syncing"
    video.SyncStatus = "syncing";
    await _context.SaveChangesAsync();

    // 觸發後台任務進行實際同步
    _ = _backgroundJobClient.Enqueue<ISyncService>(
        s => s.SyncVideoToCloudAsync(videoId, request.TargetCloud));

    return Ok(new SyncStatusResponse
    {
        VideoId = videoId,
        SyncStatus = "syncing",
        ProgressPercent = 0,
        UpdatedAt = DateTime.UtcNow
    });
}

[HttpGet("trajectory/stats")]
[Authorize]
public async Task<ActionResult<TrajectoryHistoryStats>> GetTrajectoryStats()
{
    var userId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
    if (string.IsNullOrEmpty(userId))
        return Unauthorized();

    var stats = await _videoService.GetTrajectoryStats(userId);
    return Ok(stats);
}
```

### Step 3: 實現同步服務

```csharp
public interface ISyncService
{
    Task SyncVideoToCloudAsync(string videoId, string? targetCloud = null);
    Task<bool> IsFileReadyForSync(string videoId);
}

public class SyncService : ISyncService
{
    private readonly VideoDbContext _context;
    private readonly ICloudStorageProvider _cloudStorage;
    private readonly ILogger<SyncService> _logger;

    public async Task SyncVideoToCloudAsync(string videoId, string? targetCloud = null)
    {
        try
        {
            var video = await _context.Videos
                .Include(v => v.Files)
                .FirstOrDefaultAsync(v => v.Id == videoId);

            if (video == null)
            {
                _logger.LogError("Video not found: {VideoId}", videoId);
                return;
            }

            // 同步所有文件
            foreach (var file in video.Files)
            {
                await _cloudStorage.UploadFileAsync(file.FilePath, targetCloud);
            }

            // 更新同步狀態
            video.SyncStatus = "synced";
            video.UpdatedAt = DateTime.UtcNow;
            await _context.SaveChangesAsync();

            _logger.LogInformation("Video synced successfully: {VideoId}", videoId);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error syncing video: {VideoId}", videoId);
            
            var video = await _context.Videos.FindAsync(videoId);
            if (video != null)
            {
                video.SyncStatus = "failed";
                await _context.SaveChangesAsync();
            }
        }
    }

    public async Task<bool> IsFileReadyForSync(string videoId)
    {
        var video = await _context.Videos
            .Include(v => v.Files)
            .FirstOrDefaultAsync(v => v.Id == videoId);

        return video?.Files.Count > 0 && video.Files.All(f => f.Status == "ready");
    }
}
```

## 數據庫遷移

### 新增遷移（如果還未執行）

```powershell
cd server
dotnet ef migrations add AddVideoTypeAndSyncStatus -o Migrations
dotnet ef database update
```

### Migration SQL（MySQL）

```sql
-- 如果還未執行 AddVideoType 遷移
ALTER TABLE videos ADD COLUMN type VARCHAR(50) NOT NULL DEFAULT 'original';
CREATE INDEX idx_video_type ON videos(type);

-- 添加同步狀態列
ALTER TABLE videos ADD COLUMN sync_status VARCHAR(50) DEFAULT 'notSynced';
CREATE INDEX idx_video_sync_status ON videos(sync_status);

-- 添加複合索引用於查詢優化
CREATE INDEX idx_video_type_sync_status ON videos(type, sync_status);
CREATE INDEX idx_video_user_type ON videos(user_id, type);
CREATE INDEX idx_video_user_sync_status ON videos(user_id, sync_status);
```

## 類型常數

建議在常數文件中定義：

```csharp
public static class VideoConstants
{
    public static class Types
    {
        public const string Original = "original";
        public const string Clip = "clip";
    }

    public static class SyncStatus
    {
        public const string Synced = "synced";
        public const string NotSynced = "notSynced";
        public const string Syncing = "syncing";
        public const string Failed = "failed";
    }
}
```

## 測試用例

### 單位測試

```csharp
[TestClass]
public class TrajectoryHistoryTests
{
    [TestMethod]
    public async Task QueryTrajectoryHistory_WithFilters_ReturnsFilteredResults()
    {
        // Arrange
        var userId = "user_001";
        var request = new TrajectoryHistoryQueryRequest
        {
            Types = new List<string> { "original" },
            SyncStatuses = new List<string> { "notSynced" },
            PageSize = 10
        };

        // Act
        var result = await _videoService.QueryTrajectoryHistory(userId, request);

        // Assert
        Assert.IsNotNull(result);
        Assert.IsTrue(result.Items.All(i => i.Type == "original"));
        Assert.IsTrue(result.Items.All(i => i.SyncStatus == "notSynced"));
    }

    [TestMethod]
    public async Task SyncToCloud_UpdatesVideoStatus()
    {
        // Arrange
        var videoId = "video_001";
        var syncRequest = new SyncToCloudRequest { Priority = 8 };

        // Act
        var video = await _context.Videos.FindAsync(videoId);
        await _syncService.SyncVideoToCloudAsync(videoId);

        // Assert
        Assert.AreEqual("synced", video.SyncStatus);
    }
}
```

## 性能優化

### 數據庫索引

```sql
-- 關鍵查詢的索引
CREATE INDEX idx_video_user_created_desc ON videos(user_id, created_at DESC);
CREATE INDEX idx_video_type_sync_created ON videos(type, sync_status, created_at DESC);
```

### 緩存策略

```csharp
// 使用 Redis 緩存統計信息
private static readonly TimeSpan _statsCacheDuration = TimeSpan.FromMinutes(5);

public async Task<TrajectoryHistoryStats> GetTrajectoryStats(string userId)
{
    var cacheKey = $"trajectory_stats:{userId}";
    
    var cached = await _cache.GetAsync<TrajectoryHistoryStats>(cacheKey);
    if (cached != null)
        return cached;

    // 計算統計信息...
    var stats = CalculateStats(userId);

    await _cache.SetAsync(cacheKey, stats, _statsCacheDuration);
    return stats;
}
```

## 後續開發項

- [ ] 實現批量同步 API
- [ ] 實現批量刪除 API
- [ ] 添加同步進度 WebSocket
- [ ] 實現重試機制
- [ ] 添加同步日誌和審計
- [ ] 實現智能同步調度
- [ ] 添加帶寬限制
- [ ] 實現增量同步

## 故障排除

### 同步失敗

1. 檢查文件是否存在
2. 檢查雲端存儲憑據
3. 查看應用日誌
4. 驗證網絡連接

### 查詢性能慢

1. 檢查數據庫索引
2. 啟用查詢日誌
3. 檢查分頁參數
4. 考慮添加緩存

## 相關文檔

- `TRAJECTORY_HISTORY_GUIDE.md` - Flutter 前端完整文檔
- `TRAJECTORY_HISTORY_QUICK_REFERENCE.md` - 快速參考卡片
- 模型定義：`server/Models/Video.cs`
- DTO 定義：`server/DTOs/TrajectoryHistoryDtos.cs`
