namespace UploadServer.DTOs
{
    /// <summary>
    /// 影片相关的 DTOs
    /// </summary>
    
    // ============================================================
    // 影片创建请求
    // ============================================================
    public class CreateVideoRequest
    {
        /// <summary>
        /// 影片名稱
        /// </summary>
        public string Name { get; set; }

        /// <summary>
        /// 視頻類型："original" (原始影片) 或 "clip" (切片)，默認為 "original"
        /// </summary>
        public string Type { get; set; } = "original";

        /// <summary>
        /// 父影片 ID（若為 NULL 則建立原始錄影，否則建立切片）
        /// </summary>
        public string? ParentVideoId { get; set; }

        /// <summary>
        /// 當 Type="clip" 時，擊棒時刻
        /// </summary>
        public double? HitSecond { get; set; }

        /// <summary>
        /// 當 Type="clip" 時，切片開始時刻
        /// </summary>
        public double? StartSecond { get; set; }

        /// <summary>
        /// 當 Type="clip" 時，切片結束時刻
        /// </summary>
        public double? EndSecond { get; set; }

        /// <summary>
        /// 峰值加速度
        /// </summary>
        public double? PeakValue { get; set; }

        /// <summary>
        /// 是否好球
        /// </summary>
        public bool? GoodShot { get; set; }

        /// <summary>
        /// 聲音清脆度 (0-100)
        /// </summary>
        public double? AudioCrispness { get; set; }

        /// <summary>
        /// 對應的本地檔案路徑（用於追踪檔案來源）
        /// </summary>
        public string? SourceLocalFilePath { get; set; }
    }

    // ============================================================
    // 影片响应
    // ============================================================
    public class VideoResponse
    {
        public string Id { get; set; }
        public string Name { get; set; }
        public string Status { get; set; }
        /// <summary>
        /// 視頻類型："original" 或 "clip"
        /// </summary>
        public string Type { get; set; }
        /// <summary>
        /// 同步狀態："synced", "notSynced", "syncing", "failed"
        /// </summary>
        public string? SyncStatus { get; set; }
        public string? ParentVideoId { get; set; }
        public bool IsClip => !string.IsNullOrEmpty(ParentVideoId);
        public double? HitSecond { get; set; }
        public double? StartSecond { get; set; }
        public double? EndSecond { get; set; }
        public double? PeakValue { get; set; }
        public bool? GoodShot { get; set; }
        public double? AudioCrispness { get; set; }
        /// <summary>
        /// 對應的本地檔案路徑（用於追踪檔案來源）
        /// </summary>
        public string? SourceLocalFilePath { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime UpdatedAt { get; set; }
        public DateTime? CompletedAt { get; set; }
        public List<FileResponse> Files { get; set; } = new();
    }

    // ============================================================
    // 影片列表項目
    // ============================================================
    public class VideoListItem
    {
        public string Id { get; set; }
        public string Name { get; set; }
        public string Status { get; set; }
        /// <summary>
        /// 視頻類型："original", "localClip", "cloudOriginal", "cloudClip"
        /// </summary>
        public string Type { get; set; }
        /// <summary>
        /// 同步狀態："synced", "notSynced", "syncing", "failed"
        /// </summary>
        public string? SyncStatus { get; set; }
        public bool IsClip { get; set; }  // true if ParentVideoId is not null
        public DateTime CreatedAt { get; set; }
        public int FileCount { get; set; }
    }

    // ============================================================
    // 批量删除请求
    // ============================================================
    public class BulkDeleteVideosRequest
    {
        public List<string> VideoIds { get; set; } = new();
    }

    // ============================================================
    // 批量删除响应
    // ============================================================
    public class BulkDeleteVideosResponse
    {
        public int DeletedCount { get; set; }
        public List<string> FailedIds { get; set; } = new();
    }

    // ============================================================
    // 影片统计信息
    // ============================================================
    public class VideoStatsResponse
    {
        /// <summary>
        /// 總影片數（原始錄影）
        /// </summary>
        public int TotalOriginalVideos { get; set; }

        /// <summary>
        /// 總切片數
        /// </summary>
        public int TotalClips { get; set; }

        /// <summary>
        /// 好球數
        /// </summary>
        public int GoodShotsCount { get; set; }

        /// <summary>
        /// 壞球數
        /// </summary>
        public int BadShotsCount { get; set; }

        /// <summary>
        /// 平均擊棒時刻
        /// </summary>
        public double? AvgHitSecond { get; set; }

        /// <summary>
        /// 最後上傳時間
        /// </summary>
        public DateTime? LastUploadedAt { get; set; }

        /// <summary>
        /// 本月切片數
        /// </summary>
        public int MonthlyClips { get; set; }

        /// <summary>
        /// 本週切片數
        /// </summary>
        public int WeeklyClips { get; set; }
    }

    // ============================================================
    // 更新影片名稱請求
    // ============================================================
    public class UpdateVideoNameRequest
    {
        /// <summary>
        /// 影片的新名稱
        /// </summary>
        public string Name { get; set; }
    }
}
