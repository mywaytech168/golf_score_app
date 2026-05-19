namespace UploadServer.DTOs
{
    // ── 上傳準備 ──────────────────────────────────────────────

    public class SharePrepareRequest
    {
        /// <summary>顯示標題（如擊球時間）</summary>
        public string? Title { get; set; }

        /// <summary>zip 檔案大小（bytes），用於 pre-sign 驗證</summary>
        public long SizeBytes { get; set; }

        /// <summary>分享者顯示名稱</summary>
        public string? SharerName { get; set; }
    }

    public class SharePrepareResponse
    {
        /// <summary>16 碼分享碼</summary>
        public string ShareCode { get; set; } = string.Empty;

        /// <summary>Flutter 直傳 B2 的 pre-signed PUT URL（15 分鐘有效）</summary>
        public string UploadUrl { get; set; } = string.Empty;

        /// <summary>B2 物件路徑，confirm 時回傳用</summary>
        public string B2FileName { get; set; } = string.Empty;
    }

    // ── 上傳確認 ──────────────────────────────────────────────

    public class ShareConfirmRequest
    {
        public string ShareCode { get; set; } = string.Empty;
    }

    public class ShareConfirmResponse
    {
        public bool Ok { get; set; }
        public DateTime ExpiresAt { get; set; }
    }

    // ── 取得分享 ──────────────────────────────────────────────

    public class ShareGetResponse
    {
        public string Title { get; set; } = string.Empty;
        public long SizeBytes { get; set; }
        public DateTime ExpiresAt { get; set; }

        /// <summary>B2 pre-signed GET URL（5 分鐘有效）</summary>
        public string DownloadUrl { get; set; } = string.Empty;

        /// <summary>分享者顯示名稱</summary>
        public string? SharerName { get; set; }
    }
}
