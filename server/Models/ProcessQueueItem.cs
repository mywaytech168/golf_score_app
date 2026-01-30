using System;

namespace UploadServer.Models
{
    /// <summary>
    /// 處理隊列項目 - 跟蹤影片的處理狀態
    /// 使用 UUID 作為主鍵和外鍵
    /// </summary>
    public class ProcessQueueItem
    {
        /// <summary>
        /// 主鍵：UUID
        /// </summary>
        public string Id { get; set; } = Guid.NewGuid().ToString();

        /// <summary>
        /// 關聯影片 ID（UUID）
        /// </summary>
        public string VideoId { get; set; }

        /// <summary>
        /// 優先級，數值越小越先處理（預設 0）
        /// </summary>
        public int Priority { get; set; } = 0;

        /// <summary>
        /// 分配給的 Worker ID
        /// </summary>
        public string? AssignedWorkerId { get; set; }

        /// <summary>
        /// 處理狀態：
        /// - "queued": 排隊中
        /// - "processing": 處理中
        /// - "completed": 已處理
        /// - "failed": 失敗
        /// </summary>
        public string Status { get; set; } = "queued";

        /// <summary>
        /// 建立時間
        /// </summary>
        public DateTime CreatedAt { get; set; } = DateTime.Now;

        /// <summary>
        /// 開始處理時間
        /// </summary>
        public DateTime? StartedAt { get; set; }

        /// <summary>
        /// 處理完成時間
        /// </summary>
        public DateTime? CompletedAt { get; set; }

        /// <summary>
        /// 重試次數
        /// </summary>
        public int RetryCount { get; set; } = 0;

        /// <summary>
        /// 失敗原因
        /// </summary>
        public string? ErrorMessage { get; set; }

        // 導航屬性
        /// <summary>
        /// 關聯的影片
        /// </summary>
        public Video Video { get; set; }
    }
}
