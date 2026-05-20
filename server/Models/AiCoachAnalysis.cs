using System;

namespace UploadServer.Models
{
    public class AiCoachAnalysis
    {
        public string Id { get; set; } = Guid.NewGuid().ToString();

        public string UserId { get; set; }

        /// <summary>optional reference to a clip; no FK constraint</summary>
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
