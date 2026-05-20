using System;

namespace UploadServer.Models
{
    /// <summary>
    /// 邀請好友紀錄（邀請者 + 被邀請者雙方各獲得獎勵）
    /// </summary>
    public class InviteRecord
    {
        public string Id { get; set; } = Guid.NewGuid().ToString();

        /// <summary>邀請者（發出邀請碼的人）</summary>
        public string InviterUserId { get; set; }

        /// <summary>被邀請者（使用邀請碼的新用戶）</summary>
        public string InviteeUserId { get; set; }

        /// <summary>使用的邀請碼</summary>
        public string InviteCode { get; set; }

        /// <summary>邀請者獲得的球數</summary>
        public int InviterBalls { get; set; }

        /// <summary>被邀請者獲得的球數</summary>
        public int InviteeBalls { get; set; }

        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

        // ── 導航屬性 ──────────────────────────────────────────────

        public User Inviter { get; set; }
        public User Invitee { get; set; }
    }
}
