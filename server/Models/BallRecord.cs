using System;

namespace UploadServer.Models
{
    /// <summary>
    /// 獎勵球數流水帳（每次變動留一筆）
    /// delta > 0 = 獲得；delta &lt; 0 = 消耗
    /// </summary>
    public class BallRecord
    {
        public string Id { get; set; } = Guid.NewGuid().ToString();

        public string UserId { get; set; }

        /// <summary>
        /// 變動原因:
        /// 獲得: 'ad' | 'feedback' | 'invite' | 'upload'
        /// 消耗: 'analysis'
        /// 其他: 'manual'
        /// </summary>
        public string Reason { get; set; }

        /// <summary>變動量（正數=獲得，負數=消耗）</summary>
        public int Delta { get; set; }

        /// <summary>變動後的 bonus_balls 快照</summary>
        public int BalanceAfter { get; set; }

        /// <summary>關聯紀錄 ID（如 analysis_record.id、invite_record.id、purchase_record.id）</summary>
        public string? RefId { get; set; }

        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

        // ── 導航屬性 ──────────────────────────────────────────────

        public User User { get; set; }
    }
}
