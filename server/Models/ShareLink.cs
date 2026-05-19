namespace UploadServer.Models
{
    public class ShareLink
    {
        public int Id { get; set; }

        /// <summary>16 碼隨機英數分享碼</summary>
        public string ShareCode { get; set; } = string.Empty;

        /// <summary>B2 物件路徑（shares/{code}.zip）</summary>
        public string B2FileName { get; set; } = string.Empty;

        /// <summary>顯示標題（擊球時間戳）</summary>
        public string? Title { get; set; }

        /// <summary>分享者顯示名稱</summary>
        public string? SharerName { get; set; }

        /// <summary>zip 檔案大小（bytes）</summary>
        public long SizeBytes { get; set; }

        /// <summary>上傳已確認（B2 直傳完成後 confirm）</summary>
        public bool Confirmed { get; set; } = false;

        public int DownloadCount { get; set; } = 0;

        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

        /// <summary>建立後 1 天過期</summary>
        public DateTime ExpiresAt { get; set; }
    }
}
