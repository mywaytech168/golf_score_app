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
    }

    public class AnalysisRequestResponse
    {
        public string AnalysisId { get; set; }
        /// <summary>Flutter 用此 URL 直傳 clip.mp4 到 B2</summary>
        public string ClipUploadUrl { get; set; }
        /// <summary>Flutter 用此 URL 直傳 pose_landmarks.csv 到 B2（HasCsv=true 時才有值）</summary>
        public string? CsvUploadUrl { get; set; }
    }

    public class AnalysisStatusResponse
    {
        public string AnalysisId { get; set; }
        /// <summary>客戶端傳入的 session 識別符（如 "1779413178538_hit_1"）</summary>
        public string? VideoId { get; set; }
        public string Status { get; set; }
        public string? Summary { get; set; }
        public string? Severity { get; set; }
        /// <summary>status=completed 時填入完整教練回應 JSON</summary>
        public object? Result { get; set; }
    }
}
