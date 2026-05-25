namespace UploadServer.Models
{
    /// <summary>
    /// 使用者回饋記錄（用於問題回饋獎勵功能）
    /// </summary>
    public class UserFeedback
    {
        /// <summary>主鍵：UUID</summary>
        public string Id { get; set; } = Guid.NewGuid().ToString();

        /// <summary>提交者 UserId (FK → users.id)</summary>
        public string UserId { get; set; } = string.Empty;

        /// <summary>回饋類型: 'bug' | 'feature' | 'other'</summary>
        public string Type { get; set; } = "other";

        /// <summary>回饋內容</summary>
        public string Text { get; set; } = string.Empty;

        /// <summary>提交時間（UTC）</summary>
        public DateTime CreatedAt { get; set; }

        /// <summary>附加影片 Session ID（用戶從歷史錄影中選擇）；null 表示未附加</summary>
        public string? AttachedVideoId { get; set; }

        /// <summary>附加圖片在 B2 的物件 Key（feedback_images/{id}.jpg）；null 表示未附加</summary>
        public string? AttachedImageB2Key { get; set; }

        // ── 管理員回覆 ──────────────────────────────────────────────

        /// <summary>管理員回覆內容；null 表示尚未回覆</summary>
        public string? AdminReply { get; set; }

        /// <summary>管理員回覆時間（UTC）</summary>
        public DateTime? AdminRepliedAt { get; set; }

        // ── 導航屬性 ──────────────────────────────────────────────
        public User User { get; set; } = null!;
    }
}
