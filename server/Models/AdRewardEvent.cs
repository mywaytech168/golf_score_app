namespace UploadServer.Models
{
    /// <summary>
    /// AdMob SSV（Server-Side Verification）驗簽通過的獎勵廣告觀看事件。
    /// Google 回呼一次建立一筆；用戶領獎時消耗（標記 ClaimedAt），
    /// TransactionId 唯一索引防重放。
    /// </summary>
    public class AdRewardEvent
    {
        public int Id { get; set; }

        /// <summary>關聯使用者 ID（FK → users.id），來自 SSV 的 user_id 參數</summary>
        public string UserId { get; set; } = "";

        /// <summary>AdMob transaction_id，全域唯一</summary>
        public string TransactionId { get; set; } = "";

        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

        /// <summary>領獎時間；null = 尚未被領取</summary>
        public DateTime? ClaimedAt { get; set; }

        public User? User { get; set; }
    }
}
