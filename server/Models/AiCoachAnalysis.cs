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

        /// <summary>pose_landmarks.csv 在 B2 的路徑；null 表示未上傳 CSV</summary>
        public string? CsvB2Path { get; set; }

        /// <summary>Worker 執行 ONNX 推論後序列化的 GolfSwingAnalysisResponse JSON</summary>
        public string? OnnxResultJson { get; set; }

        public string? ResultJson { get; set; }

        public string? Summary { get; set; }

        /// <summary>low | medium | high</summary>
        public string? Severity { get; set; }

        /// <summary>
        /// "posture_only" = 只跑 ONNX，完成後 Status → "idle"；
        /// "full"         = ONNX + Gemini，完成後 Status → "completed"
        /// </summary>
        public string Mode { get; set; } = "full";

        /// <summary>Gemini 提示詞版本："v1" | "v2" | "v3"</summary>
        public string PromptVersion { get; set; } = "v1";

        /// <summary>Gemini 輸入 token 數（usageMetadata.promptTokenCount）</summary>
        public int? InputTokens { get; set; }

        /// <summary>Gemini 輸出 token 數（usageMetadata.candidatesTokenCount）</summary>
        public int? OutputTokens { get; set; }

        public int RetryCount { get; set; } = 0;

        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

        public DateTime? CompletedAt { get; set; }

        // Navigation
        public User User { get; set; }
    }
}
