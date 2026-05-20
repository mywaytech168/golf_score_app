using System;

namespace UploadServer.Models
{
    /// <summary>
    /// 使用者登入方式（支援多種 OAuth 提供商）
    /// provider + provider_user_id 唯一確定一個登入憑證
    /// </summary>
    public class UserAuth
    {
        public string Id { get; set; } = Guid.NewGuid().ToString();

        /// <summary>關聯的使用者 ID（FK → users.id）</summary>
        public string UserId { get; set; }

        /// <summary>登入提供商: 'local' | 'google' | 'apple' | 'line'</summary>
        public string Provider { get; set; }

        /// <summary>
        /// 提供商端的使用者識別碼
        /// - local: email（用於查找）
        /// - google: Google Subject (sub)
        /// - apple: Apple user ID
        /// </summary>
        public string ProviderUserId { get; set; }

        /// <summary>本地帳號的 BCrypt 密碼雜湊；OAuth 登入為 null</summary>
        public string? CredentialHash { get; set; }

        /// <summary>JSON 格式的額外資訊（如 OAuth 頭像、存取 token 等）</summary>
        public string? MetadataJson { get; set; }

        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

        public DateTime? LastUsedAt { get; set; }

        // ── 導航屬性 ──────────────────────────────────────────────

        public User User { get; set; }
    }
}
