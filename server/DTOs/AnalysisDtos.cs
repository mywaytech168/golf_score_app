namespace UploadServer.DTOs
{
    public class AnalysisRequestDto
    {
        /// <summary>可選：客戶端自定義的影片參考 ID（純字串，不驗證）</summary>
        public string? VideoId { get; set; }

        /// <summary>
        /// 可選：客戶端明確指定的錯誤類型提示。
        /// 若為 null 且 HasCsv=true，Worker 會自行用 ONNX 推論決定。
        /// </summary>
        public string? ErrorTypeHint { get; set; }

        /// <summary>客戶端是否會一併上傳 pose_landmarks.csv；true 時回傳 CsvUploadUrl</summary>
        public bool HasCsv { get; set; } = false;

        /// <summary>v3：客戶端是否會一併上傳 audio.wav；true 時回傳 AudioUploadUrl</summary>
        public bool HasAudio { get; set; } = false;

        /// <summary>
        /// 分析模式：
        ///   "posture_only" = 只跑 ONNX，完成後 Status → "idle"（不呼叫 Gemini）；
        ///   "full"         = ONNX + Gemini（預設）
        /// </summary>
        public string Mode { get; set; } = "full";

        /// <summary>Gemini 提示詞版本："v1"（預設）| "v2" | "v3"</summary>
        public string PromptVersion { get; set; } = "v1";

        /// <summary>v3 時傳入的揮桿 8 階段秒數（key=address/takeaway/...，value=秒數）；null = 未提供</summary>
        public Dictionary<string, double>? PhaseTimestamps { get; set; }

        /// <summary>V3: Base64 encoded keyframe images</summary>
        public List<string>? Keyframes { get; set; }

        /// <summary>客戶端音訊分析結果 JSON（含 pass_count / passes / features）；null = 無音訊分析</summary>
        public string? AudioAnalysisJson { get; set; }

        /// <summary>v2：每秒取樣幀數（覆蓋 server 設定）；null = 使用 server 預設值</summary>
        public int? V2Fps { get; set; }

        /// <summary>v2：影片解析度，"MEDIA_RESOLUTION_HIGH" | "MEDIA_RESOLUTION_MEDIUM"；null = 使用 server 預設值</summary>
        public string? V2Resolution { get; set; }
    }

    public class AnalysisUpgradeDto
    {
        /// <summary>升級時可選擇新的提示詞版本；null = 沿用原始版本</summary>
        public string? PromptVersion { get; set; }
    }

    public class AnalysisRequestResponse
    {
        public string AnalysisId { get; set; }
        /// <summary>Flutter 用此 URL 直傳 clip.mp4 到 B2</summary>
        public string ClipUploadUrl { get; set; }
        /// <summary>Flutter 用此 URL 直傳 pose_landmarks.csv 到 B2（HasCsv=true 時才有值）</summary>
        public string? CsvUploadUrl { get; set; }

        /// <summary>Flutter 用此 URL 直傳 audio.wav 到 B2（HasAudio=true 時才有值）</summary>
        public string? AudioUploadUrl { get; set; }
    }

    public class AnalysisStatusResponse
    {
        public string AnalysisId { get; set; }
        /// <summary>客戶端傳入的 session 識別符（如 "1779413178538_hit_1"）</summary>
        public string? VideoId { get; set; }
        public string Status { get; set; }

        /// <summary>"posture_only" | "full"</summary>
        public string? Mode { get; set; }

        /// <summary>"v1" | "v2" | "v3"</summary>
        public string? PromptVersion { get; set; }

        public string? Summary { get; set; }
        public string? Severity { get; set; }

        /// <summary>status=completed 時填入完整教練回應 JSON</summary>
        public object? Result { get; set; }

        /// <summary>ONNX 推論原始結果；status=idle 或 completed 且有 CSV 時填入</summary>
        public object? OnnxResult { get; set; }

        /// <summary>Gemini 輸入 token 數</summary>
        public int? InputTokens { get; set; }

        /// <summary>Gemini 輸出 token 數</summary>
        public int? OutputTokens { get; set; }
    }
}
