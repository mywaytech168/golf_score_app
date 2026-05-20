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
        /// 處理狀態：
        /// - "ready": 準備中
        /// - "queued": 排隊中
        /// - "processing": 處理中
        /// - "completed": 已處理
        /// - "failed": 失敗
        /// </summary>
        public string Status { get; set; } = "queued";

        /// <summary>
        /// 建立時間
        /// </summary>
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

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
        /// 處理是否成功
        /// </summary>
        public bool IsSuccess { get; set; } = false;

        // 導航屬性
        /// <summary>
        /// 關聯的影片
        /// </summary>
        public Video Video { get; set; }
    }
}

