namespace UploadServer.DTOs
{
    /// <summary>
    /// 处理队列相关的 DTOs
    /// </summary>

    // ============================================================
    // 隊列項目響應
    // ============================================================
    public class ProcessQueueItemResponse
    {
        public string Id { get; set; }
        public string VideoId { get; set; }
        public int Priority { get; set; }
        public string Status { get; set; }
        public string? AssignedWorkerId { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? StartedAt { get; set; }
        public DateTime? CompletedAt { get; set; }
        public int RetryCount { get; set; }
        public string? ErrorMessage { get; set; }
    }

    // ============================================================
    // 隊列統計信息
    // ============================================================
    public class QueueStatsResponse
    {
        /// <summary>
        /// 排隊中的項目數
        /// </summary>
        public int QueuedCount { get; set; }

        /// <summary>
        /// 處理中的項目數
        /// </summary>
        public int ProcessingCount { get; set; }

        /// <summary>
        /// 已處理的項目數
        /// </summary>
        public int CompletedCount { get; set; }

        /// <summary>
        /// 失敗的項目數
        /// </summary>
        public int FailedCount { get; set; }

        /// <summary>
        /// 總項目數
        /// </summary>
        public int TotalCount { get; set; }

        /// <summary>
        /// 平均處理時間（秒）
        /// </summary>
        public double? AvgProcessingTime { get; set; }

        /// <summary>
        /// 成功率（%）
        /// </summary>
        public double SuccessRate { get; set; }
    }

    // ============================================================
    // 更新隊列項目狀態請求
    // ============================================================
    public class UpdateQueueItemStatusRequest
    {
        /// <summary>
        /// 新狀態：queued, processing, completed, failed
        /// </summary>
        public string Status { get; set; }

        /// <summary>
        /// Worker ID（如果分配）
        /// </summary>
        public string? AssignedWorkerId { get; set; }

        /// <summary>
        /// 錯誤訊息（如果失敗）
        /// </summary>
        public string? ErrorMessage { get; set; }
    }

    // ============================================================
    // 批量取消隊列項目請求
    // ============================================================
    public class BulkCancelQueueItemsRequest
    {
        public List<string> QueueItemIds { get; set; } = new();
    }

    // ============================================================
    // 批量取消隊列項目響應
    // ============================================================
    public class BulkCancelQueueItemsResponse
    {
        public int CancelledCount { get; set; }
        public List<string> FailedIds { get; set; } = new();
    }

    // ============================================================
    // 優先級隊列
    // ============================================================
    public class PriorityQueueResponse
    {
        /// <summary>
        /// 下一個待處理項目
        /// </summary>
        public ProcessQueueItemResponse? NextItem { get; set; }

        /// <summary>
        /// 排隊中的項目列表
        /// </summary>
        public List<ProcessQueueItemResponse> QueuedItems { get; set; } = new();

        /// <summary>
        /// 隊列深度
        /// </summary>
        public int QueueDepth { get; set; }
    }
}
