namespace UploadServer.Models
{
    /// <summary>
    /// 聯絡我們訊息（App 與官網「聯絡表單」共用；匿名可送，登入則帶 UserId）
    /// </summary>
    public class ContactMessage
    {
        /// <summary>主鍵：UUID</summary>
        public string Id { get; set; } = Guid.NewGuid().ToString();

        /// <summary>來源: 'app' | 'web'</summary>
        public string Source { get; set; } = "web";

        /// <summary>聯絡人姓名（選填）</summary>
        public string? Name { get; set; }

        /// <summary>聯絡人 Email（回覆用，必填）</summary>
        public string Email { get; set; } = string.Empty;

        /// <summary>主旨（選填）</summary>
        public string? Subject { get; set; }

        /// <summary>訊息內容</summary>
        public string Message { get; set; } = string.Empty;

        /// <summary>提交者 UserId（登入用戶才有；匿名為 null）</summary>
        public string? UserId { get; set; }

        /// <summary>提交時間（UTC）</summary>
        public DateTime CreatedAt { get; set; }

        // ── 處理狀態 ──────────────────────────────────────────────

        /// <summary>是否已由客服處理</summary>
        public bool Handled { get; set; }

        /// <summary>處理時間（UTC）；null 表示未處理</summary>
        public DateTime? HandledAt { get; set; }

        /// <summary>客服處理備註；null 表示無</summary>
        public string? AdminNote { get; set; }
    }
}
