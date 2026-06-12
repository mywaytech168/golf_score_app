namespace UploadServer.Models
{
    /// <summary>
    /// 上傳資料獎勵：使用者貢獻的訓練資料集（影片 + 骨架 CSV）紀錄
    /// </summary>
    public class DatasetUpload
    {
        /// <summary>主鍵：UUID（= prepare 階段發出的 uploadId）</summary>
        public string Id { get; set; } = Guid.NewGuid().ToString("N");

        /// <summary>上傳者 UserId (FK → users.id)</summary>
        public string UserId { get; set; } = string.Empty;

        /// <summary>影片在 B2 的物件 Key（dataset/{id}/clip.mp4）；null 表示未上傳檔案（僅 metadata）</summary>
        public string? B2VideoKey { get; set; }

        /// <summary>骨架 CSV 在 B2 的物件 Key（dataset/{id}/pose_landmarks.csv）；null 表示無 CSV</summary>
        public string? B2CsvKey { get; set; }

        /// <summary>用戶端原始檔案路徑（去重依據）</summary>
        public string ClientFilePath { get; set; } = string.Empty;

        /// <summary>影片原始錄製時間（用戶端時間）</summary>
        public string RecordedAt { get; set; } = string.Empty;

        /// <summary>錄影秒數</summary>
        public int DurationSeconds { get; set; }

        /// <summary>是否好球（用戶端自動分析結果）</summary>
        public bool? GoodShot { get; set; }

        /// <summary>擊球音清脆度</summary>
        public double? AudioCrispness { get; set; }

        /// <summary>音訊標籤</summary>
        public string? AudioLabel { get; set; }

        /// <summary>影片類型（full / clip…）</summary>
        public string VideoType { get; set; } = string.Empty;

        /// <summary>建立時間（UTC）</summary>
        public DateTime CreatedAt { get; set; }

        /// <summary>審核狀態：pending | approved | rejected</summary>
        public string Status { get; set; } = DatasetUploadStatus.Pending;

        /// <summary>審核時間（UTC）；null 表示尚未審核</summary>
        public DateTime? ReviewedAt { get; set; }

        /// <summary>審核備註（拒絕原因等）</summary>
        public string? ReviewNote { get; set; }
    }

    /// <summary>DatasetUpload.Status 常數</summary>
    public static class DatasetUploadStatus
    {
        public const string Pending  = "pending";
        public const string Approved = "approved";
        public const string Rejected = "rejected";
    }
}
