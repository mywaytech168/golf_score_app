using System;
using System.ComponentModel.DataAnnotations;

namespace UploadServer.Models
{
    public class AiCoachAnalysis
    {
        public string Id { get; set; } = Guid.NewGuid().ToString();

        public string UserId { get; set; }

        /// <summary>
        /// Optional local session identifier (e.g. "1779413178538_hit_1").
        /// No FK constraint; pure informational reference.
        /// </summary>
        [MaxLength(255)]
        public string? VideoId { get; set; }

        /// <summary>pending → queued → processing → completed | failed</summary>
        public string Status { get; set; } = "pending";

        public string? ErrorTypeHint { get; set; }

        public string? ClipB2Path { get; set; }

        public string? ResultJson { get; set; }

        public string? Summary { get; set; }

        /// <summary>low | medium | high</summary>
        public string? Severity { get; set; }

        public int RetryCount { get; set; } = 0;

        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

        public DateTime? CompletedAt { get; set; }

        // Navigation
        public User User { get; set; }
    }
}
