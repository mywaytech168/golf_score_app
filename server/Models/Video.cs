using System;
using System.Collections.Generic;

namespace UploadServer.Models
{
    /// <summary>
    /// 影片數據模型 - 用戶切片主要存檔
    /// 使用 UUID 作為主鍵和外鍵
    /// </summary>
    public class Video
    {
        /// <summary>
        /// 主鍵：UUID
        /// </summary>
        public string Id { get; set; } = Guid.NewGuid().ToString();

        /// <summary>
        /// 所有者用戶 ID（UUID）
        /// </summary>
        public string UserId { get; set; }

        /// <summary>
        /// 影片名稱
        /// </summary>
        public string Name { get; set; }

        /// <summary>
        /// 狀態：pending, uploading, completed, processing, failed, unbind
        /// </summary>
        public string Status { get; set; } = "pending";

        /// <summary>
        /// 影片類型：original（原始錄影）, clip（自動切片）
        /// </summary>
        public string Type { get; set; } = "original";

        /// <summary>
        /// 父影片 ID（原始錄影）
        /// 若為 NULL，則此為原始錄影；若不為 NULL，則為自動切片
        /// </summary>
        public string? ParentVideoId { get; set; }

        /// <summary>
        /// 擊棒時刻（秒，當為切片時使用）
        /// </summary>
        public double? HitSecond { get; set; }

        /// <summary>
        /// 切片開始時刻（秒，當為切片時使用）
        /// </summary>
        public double? StartSecond { get; set; }

        /// <summary>
        /// 切片結束時刻（秒，當為切片時使用）
        /// </summary>
        public double? EndSecond { get; set; }

        /// <summary>
        /// 峰值加速度（G）
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
        /// 影片建立時間
        /// </summary>
        public DateTime CreatedAt { get; set; } = DateTime.Now;

        /// <summary>
        /// 更新時間
        /// </summary>
        public DateTime UpdatedAt { get; set; } = DateTime.Now;

        /// <summary>
        /// 影片上傳完成時間
        /// </summary>
        public DateTime? CompletedAt { get; set; }

        // 導航屬性
        /// <summary>
        /// 影片所有者
        /// </summary>
        public User User { get; set; }

        /// <summary>
        /// 關聯的檔案（原始影片、主要切片、軌跡等）
        /// </summary>
        public List<File> Files { get; set; } = new List<File>();

        /// <summary>
        /// 關聯的處理隊列項目
        /// </summary>
        public List<ProcessQueueItem> QueueItems { get; set; } = new List<ProcessQueueItem>();
    }
}
