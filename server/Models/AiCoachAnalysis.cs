using System;

namespace UploadServer.Models
{
    public class AiCoachAnalysis
    {
        public string Id { get; set; } = Guid.NewGuid().ToString();

        public string VideoId { get; set; }

        /// <summary>pending → queued → processing → completed | failed</summary>
        public string Status { get; set; } = "pending";

        /// <summary>Flutter 傳入的錯誤類型提示（可選）</summary>
        public string? ErrorTypeHint { get; set; }

        /// <summary>clip 在 B2 上的 object key</summary>
        public string? ClipB2Path { get; set; }

        /// <summary>Gemini 完整回應 JSON 文字</summary>
        public string? ResultJson { get; set; }

        /// <summary>快取的一句摘要（UI 快速顯示）</summary>
        public string? Summary { get; set; }

        /// <summary>low | medium | high</summary>
        public string? Severity { get; set; }

        public int RetryCount { get; set; } = 0;

        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

        public DateTime? CompletedAt { get; set; }

        // Navigation
        public Video Video { get; set; }
    }
}
