using System.Text;
using System.Text.Json;

namespace UploadServer.Services
{
    public record GeminiCoachResult(
        string RawJson,
        string Summary,
        string Severity,
        int InputTokens,
        int OutputTokens
    );

    public class GeminiService
    {
        private const long InlineLimitBytes = 20 * 1024 * 1024; // 20 MB

        // ── 提示詞版本 ─────────────────────────────────────────────────

        /// v1：原始版本（現有邏輯）
        private const string PromptV1 = """
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
              "coach_feedback": ["評語 1", "評語 2"],
              "practice_suggestions": [
                { "drill": "練習名稱", "instruction": "具體做法", "reps": "建議次數" }
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

        /// v2：完整影片分析優化版本
        private const string PromptV2 = """
            你是一位頂尖高爾夫教練，現在要分析一段完整的揮桿影片。
            請**逐幀仔細觀看**整段影片，從準備姿勢到收桿全程進行分析。

            分析要求（按順序逐一確認）：
            ① 準備姿勢（Address）：站姿、握桿、重心分佈
            ② 起桿（Takeaway）：手臂、肩膀與髖部的協調
            ③ 上桿（Backswing）：手腕角度、肩膀轉動幅度
            ④ 頂點（Top）：桿頭位置、脊柱角度保持
            ⑤ 下桿（Downswing）：髖部先行、肩膀跟上的順序
            ⑥ 擊球（Impact）：重心轉移完成、手部超前球
            ⑦ 送桿（Follow-through）：手臂伸展、軀幹旋轉
            ⑧ 收桿（Finish）：平衡與完整度

            從以上8個階段找出最主要的問題，並結合下方 ONNX 推論結果綜合判斷。

            五種常見錯誤（error_type 英文 id）：
            - early_release_casting：早放拋桿（下桿過早釋放手腕角）
            - impact：撞擊失誤（擊球時手部未超前球）
            - over_the_top：外側切入（下桿路徑由外向內）
            - spine_angle：脊柱角度流失（揮桿中軀幹抬起）
            - weight_shift：重心轉移不足（重心未完整轉向目標側）

            若揮桿完美無明顯錯誤，請設 "error_type": ""（空字串）。

            請輸出嚴格 JSON，不要輸出 Markdown：
            {
              "summary": "一句整體評語（不超過50字）",
              "primary_error": {
                "error_type": "錯誤類型英文 id 或空字串",
                "zh_name": "中文名稱",
                "severity": "low|medium|high",
                "evidence": ["階段①②…中觀察到的具體動作依據"]
              },
              "coach_feedback": ["評語1（針對具體動作）", "評語2"],
              "practice_suggestions": [
                { "drill": "練習名稱", "instruction": "具體操作步驟", "reps": "建議次數/組數" }
              ],
              "next_training_goal": "下一次練習的具體目標",
              "model_check": {
                "is_consistent_with_video": true,
                "notes": "ONNX 結果與影片觀察是否一致的說明"
              }
            }

            ONNX 推論結果（僅供參考，以影片觀察為主）：
            {{MODEL_ANALYSIS_JSON}}
            """;

        /// v3：關鍵禎讀取版本（用 phases 時間點引導 Gemini 聚焦關鍵幀）
        private const string PromptV3 = """
            你是一位高爾夫 AI 教練，正在分析一段揮桿影片。
            下方的「揮桿關鍵時間點」標示了8個最重要的動作節點（秒數），
            請在觀看影片時，重點觀察這些時間點的畫面，並以這些瞬間的姿勢為主要分析依據。

            {{PHASE_TIMESTAMPS}}

            針對每個時間點分別確認：
            - 準備（address）：站姿、重心、握桿
            - 起桿（takeaway）：手臂路徑是否內側
            - 上桿（backswing）：肩膀轉動與手腕鉸鏈
            - 頂點（top）：桿面角度、脊柱維持
            - 下桿（downswing）：髖部開始時機
            - 擊球（impact）：手部超前、重心在前腳
            - 送桿（followthrough）：手臂伸展
            - 收桿（finish）：完整平衡

            依以上關鍵禎觀察，結合 ONNX 推論結果，給出診斷。

            五種常見錯誤（error_type 英文 id）：
            - early_release_casting / impact / over_the_top / spine_angle / weight_shift
            若無明顯錯誤，error_type 填空字串。

            請輸出嚴格 JSON，不要輸出 Markdown：
            {
              "summary": "一句整體評語",
              "primary_error": {
                "error_type": "",
                "zh_name": "",
                "severity": "low|medium|high",
                "evidence": ["基於哪個關鍵禎（幾秒）觀察到的"]
              },
              "coach_feedback": ["評語1", "評語2"],
              "practice_suggestions": [
                { "drill": "練習名稱", "instruction": "具體做法", "reps": "建議次數" }
              ],
              "next_training_goal": "下次目標",
              "model_check": { "is_consistent_with_video": true, "notes": "" }
            }

            ONNX 推論結果：
            {{MODEL_ANALYSIS_JSON}}
            """;

        // ── 錯誤類型目錄 ──────────────────────────────────────────────

        private static readonly Dictionary<string, (string ZhName, string Detector, string[] Signals)> ErrorCatalog = new()
        {
            ["over_the_top"]            = ("外切", "club_angle",          ["club_shaft_angle_sequence", "clubhead_path"]),
            ["early_release_casting"]   = ("Early release / casting", "downswing_hand_nodes",
                                           ["left_wrist", "right_wrist", "elbow_wrist_angle", "downswing_phase"]),
            ["weight_shift"]            = ("重心沒轉", "foot_nodes",
                                           ["left_ankle", "right_ankle", "hip_center_shift"]),
            ["spine_angle"]             = ("Spine angle 流失", "torso_nodes",
                                           ["left_shoulder", "right_shoulder", "left_hip", "right_hip", "torso_tilt_angle"]),
            ["impact"]                  = ("Impact 沒壓桿", "impact_hand_nodes_and_club_position",
                                           ["impact_frame", "lead_wrist_position", "ball_position", "club_shaft_angle"]),
        };

        private readonly HttpClient _http;
        private readonly string _apiKey;
        private readonly string _model;
        private readonly ILogger<GeminiService> _logger;

        public GeminiService(IHttpClientFactory httpFactory, IConfiguration config, ILogger<GeminiService> logger)
        {
            _http   = httpFactory.CreateClient("gemini");
            _apiKey = config["Gemini:ApiKey"] ?? throw new InvalidOperationException("Gemini:ApiKey 未設定");
            _model  = config["Gemini:Model"]  ?? "gemini-2.5-flash";
            _logger = logger;
        }

        /// <summary>
        /// 呼叫 Gemini 分析揮桿影片。
        /// </summary>
        /// <param name="clipBytes">clip.mp4 位元組（&lt; 20MB）</param>
        /// <param name="errorTypeHint">ONNX 推論最可能的錯誤；null = 無提示</param>
        /// <param name="promptVersion">"v1" | "v2" | "v3"</param>
        /// <param name="phaseTimestamps">v3 時傳入的關鍵禎秒數字典（key = address/takeaway/...）</param>
        public async Task<GeminiCoachResult> AnalyzeAsync(
            byte[] clipBytes,
            string? errorTypeHint,
            string promptVersion = "v1",
            Dictionary<string, double>? phaseTimestamps = null,
            CancellationToken ct = default)
        {
            if (clipBytes.Length >= InlineLimitBytes)
                throw new InvalidOperationException($"Clip 超過 20MB inline 限制 ({clipBytes.Length / 1024 / 1024}MB)");

            var modelAnalysis = BuildModelAnalysis(clipBytes, errorTypeHint);
            var prompt        = RenderPrompt(modelAnalysis, promptVersion, phaseTimestamps);
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

            var url     = $"https://generativelanguage.googleapis.com/v1beta/models/{_model}:generateContent?key={_apiKey}";
            var content = new StringContent(JsonSerializer.Serialize(body), Encoding.UTF8, "application/json");

            _logger.LogInformation("呼叫 Gemini API ({Model}) promptVersion={Ver}, clip={KB}KB",
                _model, promptVersion, clipBytes.Length / 1024);

            using var resp = await _http.PostAsync(url, content, ct);
            var raw = await resp.Content.ReadAsStringAsync(ct);

            if (!resp.IsSuccessStatusCode)
            {
                _logger.LogError("Gemini API 錯誤 {Code}: {Body}", resp.StatusCode, raw);
                throw new HttpRequestException($"Gemini API 回傳 {resp.StatusCode}");
            }

            var (resultJson, inputTokens, outputTokens) = ExtractResult(raw);
            var (summary, severity) = ParseSummary(resultJson);

            _logger.LogInformation(
                "Gemini 分析完成 severity={Severity} inputTokens={In} outputTokens={Out}",
                severity, inputTokens, outputTokens);

            return new GeminiCoachResult(resultJson, summary, severity, inputTokens, outputTokens);
        }

        // ── 私有方法 ──────────────────────────────────────────────────

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
                    source           = "onnx_inference",
                    detector         = cat.Detector,
                    required_signals = cat.Signals,
                });
            }

            return new
            {
                schema_version = "ai_coach_model_analysis.v0.2",
                created_at     = DateTime.UtcNow.ToString("o"),
                clip           = new
                {
                    size_bytes             = clipBytes.Length,
                    mime_type              = "video/mp4",
                    is_inline_gemini_ready = clipBytes.Length < InlineLimitBytes,
                },
                model_outputs = new
                {
                    error_detection_model = new
                    {
                        status          = detectedErrors.Count > 0 ? "onnx_result" : "no_hint",
                        detected_errors = detectedErrors,
                    }
                },
                profile = new { experience_level = "unknown", dominant_hand = "unknown" },
            };
        }

        private static string RenderPrompt(
            object modelAnalysis,
            string promptVersion,
            Dictionary<string, double>? phaseTimestamps)
        {
            var modelJson = JsonSerializer.Serialize(modelAnalysis, new JsonSerializerOptions { WriteIndented = true });

            var template = promptVersion switch
            {
                "v2" => PromptV2,
                "v3" => PromptV3,
                _    => PromptV1,
            };

            var result = template.Replace("{{MODEL_ANALYSIS_JSON}}", modelJson);

            if (promptVersion == "v3")
            {
                var phaseBlock = BuildPhaseBlock(phaseTimestamps);
                result = result.Replace("{{PHASE_TIMESTAMPS}}", phaseBlock);
            }

            return result;
        }

        private static string BuildPhaseBlock(Dictionary<string, double>? phases)
        {
            if (phases == null || phases.Count == 0)
                return "（未提供關鍵禎時間點，請自行從影片中識別8個揮桿階段）";

            static string PhaseName(string key) => key switch
            {
                "address"       => "①準備姿勢",
                "takeaway"      => "②起桿",
                "backswing"     => "③上桿",
                "top"           => "④頂點",
                "downswing"     => "⑤下桿",
                "impact"        => "⑥擊球",
                "followthrough" => "⑦送桿",
                "finish"        => "⑧收桿",
                _               => key,
            };

            var order = new[] { "address", "takeaway", "backswing", "top", "downswing", "impact", "followthrough", "finish" };
            var lines = new System.Text.StringBuilder("揮桿關鍵時間點（請重點觀察這些秒數的畫面）：\n");
            foreach (var key in order)
            {
                if (phases.TryGetValue(key, out var sec))
                    lines.AppendLine($"  {PhaseName(key)}: {sec:F1}s");
            }
            return lines.ToString();
        }

        private static (string text, int inputTokens, int outputTokens) ExtractResult(string geminiRaw)
        {
            string text = geminiRaw;
            int inputTokens = 0, outputTokens = 0;

            try
            {
                var doc = JsonDocument.Parse(geminiRaw);

                // 提取 candidates[0].content.parts[0].text
                foreach (var candidate in doc.RootElement.GetProperty("candidates").EnumerateArray())
                {
                    foreach (var part in candidate.GetProperty("content").GetProperty("parts").EnumerateArray())
                    {
                        if (part.TryGetProperty("text", out var t))
                        {
                            text = t.GetString() ?? geminiRaw;
                            break;
                        }
                    }
                    break;
                }

                // 提取 usageMetadata
                if (doc.RootElement.TryGetProperty("usageMetadata", out var usage))
                {
                    if (usage.TryGetProperty("promptTokenCount",     out var pt)) inputTokens  = pt.GetInt32();
                    if (usage.TryGetProperty("candidatesTokenCount", out var ct)) outputTokens = ct.GetInt32();
                }
            }
            catch { /* fall through with geminiRaw */ }

            return (text, inputTokens, outputTokens);
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
