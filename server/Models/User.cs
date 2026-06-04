using System;
using System.Collections.Generic;

namespace UploadServer.Models
{
    /// <summary>
    /// 使用者帳戶數據模型（身份主體）
    /// 登入方式獨立存放於 UserAuth 表
    /// </summary>
    public class User
    {
        public string Id { get; set; } = Guid.NewGuid().ToString();

        /// <summary>用戶名稱（登入名）</summary>
        public string Username { get; set; }

        /// <summary>電子郵件</summary>
        public string Email { get; set; }

        /// <summary>顯示名稱</summary>
        public string DisplayName { get; set; }

        /// <summary>用戶頭像 URL</summary>
        public string? AvatarUrl { get; set; }

        /// <summary>帳戶狀態: 'active' | 'inactive' | 'suspended'</summary>
        public string Status { get; set; } = "active";

        public DateTime CreatedAt { get; set; }

        public DateTime UpdatedAt { get; set; }

        public DateTime? LastLoginAt { get; set; }

        // ── 方案 ──────────────────────────────────────────────────

        /// <summary>使用者方案: 'free' | 'pro' | 'elite'</summary>
        public string Plan { get; set; } = "free";

        /// <summary>累積獎勵球數（看廣告、邀請、回饋、上傳）</summary>
        public int BonusBalls { get; set; } = 0;

        /// <summary>今日用量（分析次數）</summary>
        public int TodayUsed { get; set; } = 0;

        /// <summary>今日用量對應的日期（UTC+8），跨日時重置 TodayUsed</summary>
        public DateOnly? TodayUsedDate { get; set; }

        // ── 廣告獎勵 ──────────────────────────────────────────────

        /// <summary>今日已領廣告獎勵次數（上限 5）</summary>
        public int AdClaimedToday { get; set; } = 0;

        /// <summary>廣告獎勵計數對應日期，跨日重置</summary>
        public DateOnly? AdClaimedDate { get; set; }

        // ── 回饋獎勵 ──────────────────────────────────────────────

        /// <summary>今日是否已提交回饋（每日限 1 次）</summary>
        public DateOnly? FeedbackClaimedDate { get; set; }

        // ── 邀請系統 ──────────────────────────────────────────────

        /// <summary>使用者唯一邀請碼（首次請求時生成）</summary>
        public string? InviteCode { get; set; }

        /// <summary>已成功邀請的好友數</summary>
        public int InviteCount { get; set; } = 0;

        /// <summary>註冊時使用的邀請碼（被邀請方）</summary>
        public string? InvitedByCode { get; set; }

        // ── 訂閱 ──────────────────────────────────────────────────

        /// <summary>訂閱到期時間（UTC）；null = 從未訂閱</summary>
        public DateTime? SubscriptionExpiry { get; set; }

        /// <summary>訂閱狀態: 'none' | 'active' | 'cancel_pending' | 'expired'</summary>
        public string SubscriptionStatus { get; set; } = "none";

        /// <summary>原始訂閱交易 ID（Google orderId / Apple originalTransactionId）</summary>
        public string? SubscriptionOriginalId { get; set; }

        // ── 導航屬性 ──────────────────────────────────────────────

        public List<UserAuth> UserAuths { get; set; } = new();

        public List<UserFeedback> Feedbacks { get; set; } = new();
    }
}
