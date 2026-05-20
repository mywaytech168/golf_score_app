using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace UploadServer.Services
{
    public record GeminiCoachResult(
        string RawJson,
        string Summary,
        string Severity
    );

    public class GeminiService
    {
        private const long InlineLimitBytes = 20 * 1024 * 1024; // 20 MB

        // Prompt 範本（移植自 gemini_ai_coach_prompt_template.md）
        private const string PromptTemplate = """
            你是一位高爾夫 AI 教練，請根據「5 秒影片切片」與「模型分析 JSON」輸出教練評語。

            任務目標：
            - 用繁體中文回答。
            - 評語要像教練對學員說話，直接、具體、可執行。
            - 不要臆測影片外看不到的資訊。
            - 如果模型分析 JSON 與影片觀察不一致，請明確指出「模型結果可能需要複查」。

            五種錯誤類型：
            1. Over the top（外切）：通過球桿角度偵測。
            2. Early release（casting）：通過下桿時手部節點偵測。
            3. Weight shift（重心沒轉）：通過腳部節點偵測。
            4. Spine angle 流失（姿勢跑掉）：通過軀幹節點偵測。
            5. Impact 沒壓桿（手在球後）：通過擊球時手部節點偵測與球桿位置偵測。

            請輸出嚴格 JSON，不要輸出 Markdown：
            {
              "summary": "一句整體評語",
              "primary_error": {
                "error_type": "錯誤類型英文 id",
                "zh_name": "中文名稱",
                "severity": "low|medium|high",
                "evidence": ["從影片或模型分析看到的依據"]
              },
              "coach_feedback": [
                "評語 1",
                "評語 2"
              ],
              "practice_suggestions": [
                {
                  "drill": "練習名稱",
                  "instruction": "具體做法",
                  "reps": "建議次數"
                }
              ],
              "next_training_goal": "下一次練習目標",
              "model_check": {
                "is_consistent_with_video": true,
                "notes": "如果有疑慮，寫出需要複查的地方"
              }
            }

            模型分析 JSON：
            {{MODEL_ANALYSIS_JSON}}
            """;

        // 錯誤類型目錄
        private static readonly Dictionary<string, (string ZhName, string Detector, string[] Signals)> ErrorCatalog = new()
        {
            ["over_the_top"] = ("外切", "club_angle",
                ["club_shaft_angle_sequence", "clubhead_path"]),
            ["early_release_casting"] = ("Early release / casting", "downswing_hand_nodes",
                ["left_wrist", "right_wrist", "elbow_wrist_angle", "downswing_phase"]),
            ["weight_shift_no_rotation"] = ("重心沒轉", "foot_nodes",
                ["left_ankle", "right_ankle", "hip_center_shift"]),
            ["spine_angle_loss"] = ("Spine angle 流失 / 姿勢跑掉", "torso_nodes",
                ["left_shoulder", "right_shoulder", "left_hip", "right_hip", "torso_tilt_angle"]),
            ["impact_no_shaft_lean"] = ("Impact 沒壓桿 / 手在球後", "impact_hand_nodes_and_club_position",
                ["impact_frame", "lead_wrist_position", "ball_position", "club_shaft_angle"]),
        };

        private readonly HttpClient _http;
        private readonly string _apiKey;
        private readonly string _model;
        private readonly ILogger<GeminiService> _logger;

        public GeminiService(IHttpClientFactory httpFactory, IConfiguration config, ILogger<GeminiService> logger)
        {
            _http    = httpFactory.CreateClient("gemini");
            _apiKey  = config["Gemini:ApiKey"] ?? throw new InvalidOperationException("Gemini:ApiKey 未設定");
            _model   = config["Gemini:Model"] ?? "gemini-2.5-flash";
            _logger  = logger;
        }

        public async Task<GeminiCoachResult> AnalyzeAsync(
            byte[] clipBytes,
            string? errorTypeHint,
            CancellationToken ct = default)
        {
            if (clipBytes.Length >= InlineLimitBytes)
                throw new InvalidOperationException($"Clip 超過 20MB inline 限制 ({clipBytes.Length / 1024 / 1024}MB)");

            var modelAnalysis = BuildModelAnalysis(clipBytes, errorTypeHint);
            var prompt        = RenderPrompt(modelAnalysis);
            var videoB64      = Convert.ToBase64String(clipBytes);

            var body = new
            {
                contents = new[]
                {
                    new
                    {
                        parts = new object[]
                        {
                            new { inlineData = new { mimeType = "video/mp4", data = videoB64 } },
                            new { text = prompt },
                        }
                    }
                },
                generationConfig = new { responseMimeType = "application/json" },
            };

            var url = $"https://generativelanguage.googleapis.com/v1beta/models/{_model}:generateContent?key={_apiKey}";
            var content = new StringContent(JsonSerializer.Serialize(body), Encoding.UTF8, "application/json");

            _logger.LogInformation("呼叫 Gemini API ({Model}), clip={KB}KB", _model, clipBytes.Length / 1024);

            using var resp = await _http.PostAsync(url, content, ct);
            var raw = await resp.Content.ReadAsStringAsync(ct);

            if (!resp.IsSuccessStatusCode)
            {
                _logger.LogError("Gemini API 錯誤 {Code}: {Body}", resp.StatusCode, raw);
                throw new HttpRequestException($"Gemini API 回傳 {resp.StatusCode}");
            }

            var resultJson = ExtractText(raw);
            var (summary, severity) = ParseSummary(resultJson);

            _logger.LogInformation("Gemini 分析完成，severity={Severity}", severity);
            return new GeminiCoachResult(resultJson, summary, severity);
        }

        // ── 私有方法 ────────────────────────────────────────────────────

        private static object BuildModelAnalysis(byte[] clipBytes, string? errorTypeHint)
        {
            List<object> detectedErrors = [];
            if (!string.IsNullOrEmpty(errorTypeHint) && ErrorCatalog.TryGetValue(errorTypeHint, out var cat))
            {
                detectedErrors.Add(new
                {
                    error_type       = errorTypeHint,
                    zh_name          = cat.ZhName,
                    confidence       = 0.95,
                    severity         = "high",
                    source           = "flutter_hint",
                    detector         = cat.Detector,
                    required_signals = cat.Signals,
                });
            }

            return new
            {
                schema_version = "ai_coach_model_analysis.v0.1",
                created_at     = DateTime.UtcNow.ToString("o"),
                clip = new
                {
                    size_bytes            = clipBytes.Length,
                    mime_type             = "video/mp4",
                    is_inline_gemini_ready = clipBytes.Length < InlineLimitBytes,
                },
                model_outputs = new
                {
                    error_detection_model = new
                    {
                        status          = detectedErrors.Count > 0 ? "hint_provided" : "no_hint",
                        detected_errors = detectedErrors,
                    }
                },
                profile = new { experience_level = "unknown", dominant_hand = "unknown" },
            };
        }

        private static string RenderPrompt(object modelAnalysis)
        {
            var json = JsonSerializer.Serialize(modelAnalysis, new JsonSerializerOptions { WriteIndented = true });
            return PromptTemplate.Replace("{{MODEL_ANALYSIS_JSON}}", json);
        }

        private static string ExtractText(string geminiRaw)
        {
            try
            {
                var doc = JsonDocument.Parse(geminiRaw);
                foreach (var candidate in doc.RootElement.GetProperty("candidates").EnumerateArray())
                {
                    foreach (var part in candidate.GetProperty("content").GetProperty("parts").EnumerateArray())
                    {
                        if (part.TryGetProperty("text", out var text))
                            return text.GetString() ?? geminiRaw;
                    }
                }
            }
            catch { /* fall through */ }
            return geminiRaw;
        }

        private static (string summary, string severity) ParseSummary(string resultJson)
        {
            try
            {
                var doc      = JsonDocument.Parse(resultJson);
                var summary  = doc.RootElement.TryGetProperty("summary", out var s) ? s.GetString() ?? "" : "";
                var severity = doc.RootElement.TryGetProperty("primary_error", out var pe)
                    && pe.TryGetProperty("severity", out var sev)
                    ? sev.GetString() ?? "medium"
                    : "medium";
                return (summary, severity);
            }
            catch
            {
                return ("", "medium");
            }
        }
    }
}
