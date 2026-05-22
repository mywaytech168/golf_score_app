namespace UploadServer.Models
{
    /// <summary>
    /// 密碼重設驗證碼記錄
    /// 每次請求重設密碼都建立一筆新紀錄；使用後標記 IsUsed=true
    /// </summary>
    public class PasswordResetToken
    {
        public string Id { get; set; } = Guid.NewGuid().ToString();

        /// <summary>關聯使用者 ID（FK → users.id）</summary>
        public string UserId { get; set; } = "";

        /// <summary>6 位數驗證碼的 BCrypt 雜湊值</summary>
        public string CodeHash { get; set; } = "";

        /// <summary>過期時間（UTC）；通常 CreatedAt + 15 分鐘</summary>
        public DateTime ExpiresAt { get; set; }

        /// <summary>是否已使用（使用後立即標記，防重送）</summary>
        public bool IsUsed { get; set; } = false;

        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

        // ── 導航屬性 ──────────────────────────────────────────────
        public User? User { get; set; }
    }
}
