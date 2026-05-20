namespace UploadServer.DTOs
{
    public class AnalysisRequestDto
    {
        /// <summary>可選：客戶端自定義的影片參考 ID（純字串，不驗證）</summary>
        public string? VideoId { get; set; }

        /// <summary>可選：錯誤類型提示（over_the_top / early_release_casting / ...）</summary>
        public string? ErrorTypeHint { get; set; }
    }

    public class AnalysisRequestResponse
    {
        public string AnalysisId { get; set; }
        /// <summary>Flutter 用此 URL 直傳 clip.mp4 到 B2</summary>
        public string ClipUploadUrl { get; set; }
    }

    public class AnalysisStatusResponse
    {
        public string AnalysisId { get; set; }
        public string Status { get; set; }
        public string? Summary { get; set; }
        public string? Severity { get; set; }
        /// <summary>status=completed 時填入完整教練回應 JSON</summary>
        public object? Result { get; set; }
    }
}
