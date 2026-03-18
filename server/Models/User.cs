using System;
using System.Collections.Generic;

namespace UploadServer.Models
{
    /// <summary>
    /// 使用者帳戶數據模型
    /// 使用 UUID 作為主鍵
    /// </summary>
    public class User
    {
        /// <summary>
        /// 主鍵：UUID
        /// </summary>
        public string Id { get; set; } = Guid.NewGuid().ToString();

        /// <summary>
        /// 用戶名稱（登入名）
        /// </summary>
        public string Username { get; set; }

        /// <summary>
        /// 電子郵件
        /// </summary>
        public string Email { get; set; }

        /// <summary>
        /// 密碼雜湊值
        /// </summary>
        public string PasswordHash { get; set; }

        /// <summary>
        /// 顯示名稱
        /// </summary>
        public string DisplayName { get; set; }

        /// <summary>
        /// Google OAuth ID
        /// </summary>
        public string? GoogleId { get; set; }

        /// <summary>
        /// 用戶頭像 URL
        /// </summary>
        public string? AvatarUrl { get; set; }

        /// <summary>
        /// 登入提供商: 'local' | 'google'
        /// </summary>
        public string Provider { get; set; } = "local";

        /// <summary>
        /// 帳戶狀態: 'active' | 'inactive' | 'suspended'
        /// </summary>
        public string Status { get; set; } = "active";

        public DateTime CreatedAt { get; set; }

        public DateTime UpdatedAt { get; set; }

        public DateTime? LastLoginAt { get; set; }

        /// <summary>
        /// 導航屬性：該用戶上傳的影片
        /// </summary>
        public List<Video> Videos { get; set; } = new List<Video>();
    }
}
