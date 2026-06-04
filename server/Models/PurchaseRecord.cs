using System;

namespace UploadServer.Models
{
    /// <summary>
    /// 付費購買紀錄
    /// </summary>
    public class PurchaseRecord
    {
        public string Id { get; set; } = Guid.NewGuid().ToString();

        public string UserId { get; set; }

        /// <summary>購買的方案: 'pro' | 'elite'</summary>
        public string Plan { get; set; }

        /// <summary>購買渠道: 'google_pay' | 'google_play' | 'app_store'</summary>
        public string Store { get; set; }

        /// <summary>商品 ID（App 內購品項）</summary>
        public string? ProductId { get; set; }

        /// <summary>購買憑證 token / receipt（用於稽核）</summary>
        public string PurchaseToken { get; set; }

        /// <summary>驗證狀態: 'pending' | 'verified' | 'failed' | 'refunded'</summary>
        public string Status { get; set; } = "pending";

        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

        public DateTime? VerifiedAt { get; set; }

        /// <summary>原始訂閱交易 ID（Google orderId / Apple originalTransactionId），用於關聯 renewal</summary>
        public string? OriginalTransactionId { get; set; }

        /// <summary>此次訂閱到期時間（UTC）</summary>
        public DateTime? ExpiresAt { get; set; }

        /// <summary>是否仍在自動續費</summary>
        public bool? IsAutoRenewing { get; set; }

        // ── 導航屬性 ──────────────────────────────────────────────

        public User User { get; set; }
    }
}
