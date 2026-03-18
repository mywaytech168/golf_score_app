namespace UploadServer.DTOs
{
    /// <summary>
    /// 軌跡歷史相關的 DTOs
    /// </summary>

    // ============================================================
    // 軌跡歷史項目
    // ============================================================
    /// <summary>
    /// 單個軌跡歷史項目的完整信息
    /// </summary>
    public class TrajectoryHistoryItem
    {
        /// <summary>
        /// 唯一識別碼 (UUID)
        /// </summary>
        public string Id { get; set; }

        /// <summary>
        /// 影片名稱
        /// </summary>
        public string Name { get; set; }

        /// <summary>
        /// 視頻類型："original" (原始影片) 或 "clip" (切片)
        /// </summary>
        public string Type { get; set; }

        /// <summary>
        /// 同步狀態："synced" (已同步) | "notSynced" (未同步) | "syncing" (同步中) | "failed" (失敗)
        /// </summary>
        public string SyncStatus { get; set; }

        /// <summary>
        /// 父影片 ID（用於切片關聯）
        /// </summary>
        public string? ParentVideoId { get; set; }

        /// <summary>
        /// 創建時間
        /// </summary>
        public DateTime CreatedAt { get; set; }

        /// <summary>
        /// 完成時間
        /// </summary>
        public DateTime? CompletedAt { get; set; }

        /// <summary>
        /// 檔案大小（單位：字節）
        /// </summary>
        public long FileSize { get; set; }

        /// <summary>
        /// 擊球秒數
        /// </summary>
        public double? HitSecond { get; set; }

        /// <summary>
        /// 開始秒數
        /// </summary>
        public double? StartSecond { get; set; }

        /// <summary>
        /// 結束秒數
        /// </summary>
        public double? EndSecond { get; set; }

        /// <summary>
        /// 峰值
        /// </summary>
        public double? PeakValue { get; set; }

        /// <summary>
        /// 是否為好球
        /// </summary>
        public bool? GoodShot { get; set; }

        /// <summary>
        /// 聲音清脆度 (0-100)
        /// </summary>
        public double? AudioCrispness { get; set; }
    }

    // ============================================================
    // 軌跡歷史查詢請求
    // ============================================================
    /// <summary>
    /// 查詢軌跡歷史的請求參數
    /// </summary>
    public class TrajectoryHistoryQueryRequest
    {
        /// <summary>
        /// 篩選類型：original, localClip, cloudClip（可選，不指定則返回全部）
        /// </summary>
        public List<string>? Types { get; set; }

        /// <summary>
        /// 篩選同步狀態（可選）
        /// </summary>
        public List<string>? SyncStatuses { get; set; }

        /// <summary>
        /// 搜尋關鍵字（按名稱搜尋）
        /// </summary>
        public string? SearchQuery { get; set; }

        /// <summary>
        /// 排序方式：newest (默認), oldest, nameAsc, nameDesc
        /// </summary>
        public string SortBy { get; set; } = "newest";

        /// <summary>
        /// 頁碼（從 1 開始）
        /// </summary>
        public int PageNumber { get; set; } = 1;

        /// <summary>
        /// 每頁項數
        /// </summary>
        public int PageSize { get; set; } = 20;
    }

    // ============================================================
    // 軌跡歷史查詢響應
    // ============================================================
    /// <summary>
    /// 軌跡歷史查詢的分頁響應
    /// </summary>
    public class TrajectoryHistoryQueryResponse
    {
        /// <summary>
        /// 軌跡歷史項目列表
        /// </summary>
        public List<TrajectoryHistoryItem> Items { get; set; } = new();

        /// <summary>
        /// 總項數
        /// </summary>
        public int Total { get; set; }

        /// <summary>
        /// 總頁數
        /// </summary>
        public int TotalPages { get; set; }

        /// <summary>
        /// 當前頁碼
        /// </summary>
        public int CurrentPage { get; set; }

        /// <summary>
        /// 每頁項數
        /// </summary>
        public int PageSize { get; set; }
    }

    // ============================================================
    // 同步請求
    // ============================================================
    /// <summary>
    /// 同步單個影片或批量同步的請求
    /// </summary>
    public class SyncToCloudRequest
    {
        /// <summary>
        /// 影片 ID（單個同步）
        /// </summary>
        public string? VideoId { get; set; }

        /// <summary>
        /// 影片 ID 列表（批量同步）
        /// </summary>
        public List<string>? VideoIds { get; set; }

        /// <summary>
        /// 目標雲端位置（可選，默認為主伺服器）
        /// </summary>
        public string? TargetCloud { get; set; }

        /// <summary>
        /// 優先級（可選，1-10，默認 5）
        /// </summary>
        public int Priority { get; set; } = 5;
    }

    // ============================================================
    // 同步狀態響應
    // ============================================================
    /// <summary>
    /// 同步操作的結果響應
    /// </summary>
    public class SyncStatusResponse
    {
        /// <summary>
        /// 影片 ID
        /// </summary>
        public string VideoId { get; set; }

        /// <summary>
        /// 新的同步狀態
        /// </summary>
        public string SyncStatus { get; set; }

        /// <summary>
        /// 進度百分比（0-100）
        /// </summary>
        public int ProgressPercent { get; set; }

        /// <summary>
        /// 錯誤信息（如果有）
        /// </summary>
        public string? ErrorMessage { get; set; }

        /// <summary>
        /// 更新時間
        /// </summary>
        public DateTime UpdatedAt { get; set; }
    }

    // ============================================================
    // 統計信息
    // ============================================================
    /// <summary>
    /// 軌跡歷史統計信息
    /// </summary>
    public class TrajectoryHistoryStats
    {
        /// <summary>
        /// 原始影片數量
        /// </summary>
        public int OriginalVideos { get; set; }

        /// <summary>
        /// 本地切片數量
        /// </summary>
        public int LocalClips { get; set; }

        /// <summary>
        /// 雲端切片數量
        /// </summary>
        public int CloudClips { get; set; }

        /// <summary>
        /// 已同步項目數
        /// </summary>
        public int SyncedCount { get; set; }

        /// <summary>
        /// 未同步項目數
        /// </summary>
        public int UnSyncedCount { get; set; }

        /// <summary>
        /// 同步中項目數
        /// </summary>
        public int SyncingCount { get; set; }

        /// <summary>
        /// 同步失敗項目數
        /// </summary>
        public int FailedCount { get; set; }

        /// <summary>
        /// 總檔案大小（字節）
        /// </summary>
        public long TotalFileSize { get; set; }

        /// <summary>
        /// 未同步的總檔案大小（字節）
        /// </summary>
        public long UnSyncedFileSize { get; set; }
    }

    // ============================================================
    // 批量操作響應
    // ============================================================
    /// <summary>
    /// 批量操作的結果
    /// </summary>
    public class BulkOperationResponse
    {
        /// <summary>
        /// 成功操作的影片 ID 列表
        /// </summary>
        public List<string> SuccessfulIds { get; set; } = new();

        /// <summary>
        /// 失敗操作的詳細信息
        /// </summary>
        public List<OperationError> Errors { get; set; } = new();

        /// <summary>
        /// 總操作數
        /// </summary>
        public int TotalCount => SuccessfulIds.Count + Errors.Count;

        /// <summary>
        /// 成功數
        /// </summary>
        public int SuccessCount => SuccessfulIds.Count;

        /// <summary>
        /// 失敗數
        /// </summary>
        public int FailureCount => Errors.Count;
    }

    /// <summary>
    /// 操作錯誤詳情
    /// </summary>
    public class OperationError
    {
        /// <summary>
        /// 相關的影片 ID
        /// </summary>
        public string VideoId { get; set; }

        /// <summary>
        /// 錯誤信息
        /// </summary>
        public string Message { get; set; }

        /// <summary>
        /// 錯誤代碼
        /// </summary>
        public string? ErrorCode { get; set; }
    }
}
