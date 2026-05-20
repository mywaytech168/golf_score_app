using System;

namespace UploadServer.Models
{
    /// <summary>
    /// AI 揮桿分析使用紀錄
    /// source 區分每日配額 vs 獎勵球數消耗
    /// </summary>
    public class AnalysisRecord
    {
        public string Id { get; set; } = Guid.NewGuid().ToString();

        public string UserId { get; set; }

        /// <summary>消耗來源: 'daily_quota' | 'bonus_ball'</summary>
        public string Source { get; set; }

        /// <summary>消耗球數（daily_quota 為 0，bonus_ball 為 1）</summary>
        public int BallsSpent { get; set; } = 0;

        /// <summary>關聯的影片 ID（可選）</summary>
        public string? VideoId { get; set; }

        public DateTime UsedAt { get; set; } = DateTime.UtcNow;

        // ── 導航屬性 ──────────────────────────────────────────────

        public User User { get; set; }
    }
}
