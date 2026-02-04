using System;
using System.Collections.Generic;

namespace UploadServer.DTOs
{
    /// <summary>
    /// Python Server 發送的處理結果回調
    /// </summary>
    public class ProcessingResultCallbackDto
    {
        /// <summary>
        /// 隊列項目 ID
        /// </summary>
        public string QueueItemId { get; set; }

        /// <summary>
        /// 處理狀態
        /// - "processing": 處理中
        /// - "completed": 處理完畢
        /// - "failed": 處理失敗
        /// </summary>
        public string Status { get; set; } = "processing";

        /// <summary>
        /// 處理結果數據（JSON 格式）
        /// 包含：軌跡數據、姿勢分析、音頻評分、穩定化視頻等
        /// 處理中或失敗時可能為 null
        /// </summary>
        public Dictionary<string, object> ResultData { get; set; }

        /// <summary>
        /// 錯誤信息（如果失敗）
        /// </summary>
        public string? ErrorMessage { get; set; }

        /// <summary>
        /// 處理完成時間
        /// 處理中時可以設置當前進度時間
        /// </summary>
        public DateTime? CompletedAt { get; set; }

        /// <summary>
        /// 處理耗時（秒）
        /// 用於記錄已消耗的時間
        /// </summary>
        public double ProcessingDurationSeconds { get; set; }

        /// <summary>
        /// 進度百分比 (0-100)
        /// 處理中時使用此字段表示進度
        /// </summary>
        public int? ProgressPercent { get; set; }
    }

    /// <summary>
    /// 回調響應
    /// </summary>
    public class CallbackResponseDto
    {
        /// <summary>
        /// 是否成功接收
        /// </summary>
        public bool Success { get; set; }

        /// <summary>
        /// 響應消息
        /// </summary>
        public string Message { get; set; }

        /// <summary>
        /// 隊列項目 ID
        /// </summary>
        public string QueueItemId { get; set; }

        /// <summary>
        /// 時間戳
        /// </summary>
        public DateTime Timestamp { get; set; } = DateTime.UtcNow;
    }
}
