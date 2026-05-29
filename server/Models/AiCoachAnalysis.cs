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

        /// <summary>v3 時傳入的揮桿 8 階段秒數 JSON（{"address":0.5,...}）；null = 未提供</summary>
        public string? PhaseTimestampsJson { get; set; }

        /// <summary>Flutter 客戶端音訊分析結果 JSON（含 pass_count / passes / features）；null = 無音訊分析</summary>
        public string? AudioAnalysisJson { get; set; }

        /// <summary>v3：8 個關鍵禎 base64 JPEG 陣列的 JSON（["data...", ...]）；null = 未提供</summary>
        public string? KeyframesJson { get; set; }

        /// <summary>v3：audio.wav 在 B2 的路徑；null = 未上傳音訊</summary>
        public string? AudioB2Path { get; set; }

        /// <summary>v2 每秒取樣幀數；null = 使用 server 預設值</summary>
        public int? V2Fps { get; set; }

        /// <summary>v2 影片解析度："MEDIA_RESOLUTION_HIGH" | "MEDIA_RESOLUTION_MEDIUM"；null = 使用 server 預設值</summary>
        public string? V2Resolution { get; set; }

        // Navigation
        public User User { get; set; }
    }
}
