using System;

namespace UploadServer.Models
{
    /// <summary>
    /// 檔案追蹤模型 - 追蹤切片的各種檔案
    /// 使用 UUID 作為主鍵和外鍵
    /// </summary>
    public class File
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
        /// 檔案類型：
        /// - "original": 原始影片文件
        /// - "clip": 切片主要視頻文件
        /// - "chest_trajectory": 胸 軌跡 CSV 數據
        /// - "wrist_trajectory": 手腕 軌跡 CSV 數據
        /// - "thumbnail": 縮略圖
        /// </summary>
        public string Type { get; set; }

        /// <summary>
        /// 檔案名稱
        /// </summary>
        public string FileName { get; set; }

        /// <summary>
        /// 檔案儲存路徑
        /// </summary>
        public string FilePath { get; set; }

        /// <summary>
        /// 檔案大小（字節）
        /// </summary>
        public long FileSize { get; set; }

        /// <summary>
        /// 檔案的 MIME 類型
        /// </summary>
        public string MimeType { get; set; }

        /// <summary>
        /// 檔案上傳狀態：pending, uploading, completed, failed
        /// </summary>
        public string Status { get; set; } = "pending";

        /// <summary>
        /// 檔案建立時間
        /// </summary>
        public DateTime CreatedAt { get; set; } = DateTime.Now;

        /// <summary>
        /// 檔案上傳完成時間
        /// </summary>
        public DateTime? CompletedAt { get; set; }

        /// <summary>
        /// 檔案上傳失敗時的錯誤信息
        /// </summary>
        public string? ErrorMessage { get; set; }

        /// <summary>
        /// 對應的本地檔案路徑（用於追踪檔案來源，特別是雲端上傳的檔案）
        /// 用於識別多設備同步時的檔案來源
        /// </summary>
        public string? SourceLocalFilePath { get; set; }

        // 導航屬性
        /// <summary>
        /// 關聯的影片
        /// </summary>
        public Video Video { get; set; }
    }
}
