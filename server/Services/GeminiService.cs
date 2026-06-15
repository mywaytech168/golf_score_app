using System.Text;
using System.Text.Json;

namespace UploadServer.Services
{
    public record GeminiCoachResult(
        string RawJson,
        string Summary,
        string Severity,
        int InputTokens,
        int OutputTokens,
        int? ResolvedV2Fps = null,
        string? ResolvedV2Resolution = null
    );

    public class GeminiService
    {
        private const long InlineLimitBytes = 20 * 1024 * 1024; // 20 MB

        // ── 提示詞版本 ─────────────────────────────────────────────────

        /// v1：原始版本（現有邏輯）
        private const string PromptV1 = """
            你是一位高爾夫 AI 教練，請根據「5 秒影片切片」、「模型分析 JSON」與「音訊分析 JSON」輸出教練評語。

            任務目標：
            - 用繁體中文回答。
            - 評語要像教練對學員說話，直接、具體、可執行。
            - 不要臆測影片外看不到的資訊。
            - 請以 P-System（P1 預備→P10 收桿）逐位置觀察揮桿，從中找出最主要的問題。
            - 如果模型分析 JSON 與影片觀察不一致，請明確指出「模型結果可能需要複查」。

            ── 影片骨架模型（判斷動作錯誤）──
            五種錯誤類型：
            1. Over the top（外切）：通過球桿角度偵測。
            2. Early release（casting）：通過下桿時手部節點偵測。
            3. Weight shift（重心沒轉）：通過腳部節點偵測。
            4. Spine angle 流失（姿勢跑掉）：通過軀幹節點偵測。
            5. Impact 沒壓桿（手在球後）：通過擊球時手部節點偵測與球桿位置偵測。

            ── 音訊分析（判斷擊球瞬間品質，不可用於判斷身體動作）──
            音訊共有 5 個特徵：rms_dbfs（音量）、spectral_centroid（頻率）、sharpness_hfxloud（清脆）、highband_amp（高頻）、peak_dbfs（峰值）。
            甜蜜點規則：每個特徵通過算 1 項。pass_count >= 3 代表聲音接近甜蜜點。
            音訊聲音分級：0~1 項→差；2 項→普通；3 項→接近甜蜜點；4 項→甜蜜點；5 項→高品質甜蜜點。
            音訊使用規則：
            - primary_error 以影片骨架模型為主；音訊只補充 impact 品質與甜蜜點描述。
            - 不可單獨依賴音訊判斷外切、重心未轉、脊椎角度等身體動作問題。
            - 若影片顯示 impact 錯誤且音訊 pass_count < 3，教練評語加強 impact 修正建議。
            - 若影片有動作錯誤但音訊 pass_count >= 3，說明「擊球品質尚可，但動作仍可優化」。
            - 若影片模型與音訊明顯矛盾，在 model_check.notes 寫「模型結果可能需要複查」。
            - 若音訊 available=false，impact_quality 仍須填入但 audio_feedback 填「無音訊分析資料」。

            impact_quality.quality_level 對應：0~1→"poor"；2→"fair"；3→"near_sweet_spot"；4→"sweet_spot"；5→"premium_sweet_spot"。

            請輸出嚴格 JSON，不要輸出 Markdown：
            {
              "summary": "一句整體評語",
              "primary_error": {
                "error_type": "錯誤類型英文 id",
                "zh_name": "中文名稱",
                "severity": "low|medium|high",
                "evidence": ["從影片或模型分析看到的依據"]
              },
              "impact_quality": {
                "audio_sweet_spot": true,
                "pass_count": 3,
                "total_features": 5,
                "quality_level": "near_sweet_spot",
                "audio_feedback": "音訊擊球品質說明（1~2句）"
              },
              "coach_feedback": ["評語 1（含音訊補充）", "評語 2"],
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

            音訊分析 JSON：
            {{AUDIO_ANALYSIS_JSON}}
            """;

        /// v2：完整影片分析優化版本
        private const string PromptV2 = """
            你是一位頂尖高爾夫教練，現在要分析一段完整的揮桿影片，同時結合音訊分析判斷擊球品質。
            請**逐幀仔細觀看**整段影片，從 P1 預備到 P10 收桿全程進行分析。

            分析要求（P-System，依 P1→P10 順序逐一確認）：
            P1 預備（Address）：站姿、握桿、重心分佈、脊椎前傾
            P2 桿身水平·上桿（桿與地面平行）：起桿路徑、手臂與肩同動
            P3 引導臂水平·上桿（引導臂與地面平行）：手腕鉸鏈、桿面方向
            P4 頂點（Top）：肩膀轉動幅度、X-factor（肩髖分離）、脊椎角度保持
            P5 引導臂水平·下桿：下桿順序（髖部先行）、桿落在身體前
            P6 桿身水平·下桿（桿與地面平行）：是否外切、保留手腕角度（防早放）
            P7 擊球（Impact）：手部超前球、重心轉移到前腳、脊椎角度維持
            P8 桿身水平·送桿（桿與地面平行）：釋放與延展
            P9 引導臂水平·送桿：軀幹持續旋轉、手臂伸展
            P10 收桿（Finish）：平衡、完整度、重心完全到前腳

            註：P2/P3/P5/P6/P8/P9 為桿身/引導臂的「水平位置」，依影像中桿與手臂角度判讀。
            從以上 P1-P10 找出最主要的問題，並結合下方 ONNX 推論結果綜合判斷。

            ── 影片骨架模型五種常見錯誤（error_type 英文 id）──
            - early_release_casting：早放拋桿（下桿過早釋放手腕角）
            - impact：撞擊失誤（擊球時手部未超前球）
            - over_the_top：外側切入（下桿路徑由外向內）
            - spine_angle：脊柱角度流失（揮桿中軀幹抬起）
            - weight_shift：重心轉移不足（重心未完整轉向目標側）
            若揮桿完美無明顯錯誤，請設 "error_type": ""（空字串）。

            ── 音訊分析（判斷擊球瞬間品質，不可用於判斷身體動作）──
            音訊共有 5 個特徵：rms_dbfs（音量）、spectral_centroid（頻率）、sharpness_hfxloud（清脆）、highband_amp（高頻）、peak_dbfs（峰值）。
            甜蜜點規則：pass_count >= 3 代表聲音接近甜蜜點。
            音訊聲音分級：0~1 項→差；2 項→普通；3 項→接近甜蜜點；4 項→甜蜜點；5 項→高品質甜蜜點。
            音訊使用規則：
            - primary_error 以影片骨架模型為主；音訊只補充 impact 品質與甜蜜點描述。
            - 不可單獨依賴音訊判斷身體動作問題。
            - 若影片顯示 impact 錯誤且音訊 pass_count < 3，教練評語加強 impact 修正建議。
            - 若影片有動作錯誤但音訊 pass_count >= 3，說明「擊球品質尚可，但動作仍可優化」。
            - 若影片模型與音訊明顯矛盾，在 model_check.notes 寫「模型結果可能需要複查」。
            - 若音訊 available=false，impact_quality.audio_feedback 填「無音訊分析資料」。

            impact_quality.quality_level 對應：0~1→"poor"；2→"fair"；3→"near_sweet_spot"；4→"sweet_spot"；5→"premium_sweet_spot"。

            請輸出嚴格 JSON，不要輸出 Markdown：
            {
              "summary": "一句整體評語（不超過50字）",
              "primary_error": {
                "error_type": "錯誤類型英文 id 或空字串",
                "zh_name": "中文名稱",
                "severity": "low|medium|high",
                "evidence": ["P1~P10 各位置觀察到的具體動作依據"]
              },
              "impact_quality": {
                "audio_sweet_spot": true,
                "pass_count": 3,
                "total_features": 5,
                "quality_level": "near_sweet_spot",
                "audio_feedback": "音訊擊球品質說明（1~2句）"
              },
              "coach_feedback": ["評語1（針對具體動作，含音訊補充）", "評語2"],
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

            音訊分析 JSON：
            {{AUDIO_ANALYSIS_JSON}}
            """;

        /// v3：關鍵幀圖片 + 音訊版本（不傳影片，用圖片直接分析 P-System 各位置）
        private const string PromptV3 = """
            你是一位高爾夫 AI 教練。以下提供揮桿動作的關鍵幀圖片（JPEG，依序對應 P-System 位置）以及擊球音訊（WAV），
            請仔細觀看每一張圖片，並聆聽音訊，綜合分析整個揮桿動作與擊球品質。

            {{PHASE_TIMESTAMPS}}

            請依序對每張關鍵幀分析對應的 P-System 位置：
            - P1 預備（address）：站姿、重心、握桿
            - P2 桿身水平·上桿：起桿路徑是否內側
            - P3 引導臂水平·上桿：肩膀轉動與手腕鉸鏈
            - P4 頂點（top）：桿面角度、X-factor、脊柱維持
            - P5 引導臂水平·下桿：髖部開始時機、桿落在身體前
            - P6 桿身水平·下桿：是否外切、保留手腕角度
            - P7 擊球（impact）：手部超前、重心在前腳
            - P8 桿身水平·送桿：釋放與延展
            - P9 引導臂水平·送桿：手臂伸展、軀幹旋轉
            - P10 收桿（finish）：完整平衡

            註：P2/P3/P5/P6/P8/P9 為桿身/引導臂的水平位置，依影像中桿與手臂角度判讀。
            依以上關鍵幀圖片觀察，結合 ONNX 骨架推論結果，給出診斷。

            ── ONNX 骨架模型五種常見錯誤（error_type 英文 id）──
            - early_release_casting / impact / over_the_top / spine_angle / weight_shift
            若無明顯錯誤，error_type 填空字串。

            ── 音訊分析（判斷擊球瞬間品質，不可用於判斷身體動作）──
            你已收到擊球音訊（WAV），請直接聆聽並判斷聲音品質；以下 JSON 為程式預計算的特徵值供參考。
            音訊共有 5 個特徵：rms_dbfs（音量）、spectral_centroid（頻率）、sharpness_hfxloud（清脆）、highband_amp（高頻）、peak_dbfs（峰值）。
            甜蜜點規則：pass_count >= 3 代表聲音接近甜蜜點。
            音訊聲音分級：0~1 項→差；2 項→普通；3 項→接近甜蜜點；4 項→甜蜜點；5 項→高品質甜蜜點。
            音訊使用規則：
            - primary_error 以關鍵幀圖片觀察為主；音訊只補充 impact 品質與甜蜜點描述。
            - 不可單獨依賴音訊判斷身體動作問題。
            - 若圖片顯示 impact 錯誤且音訊 pass_count < 3，教練評語加強 impact 修正建議。
            - 若圖片有動作錯誤但音訊 pass_count >= 3，說明「擊球品質尚可，但動作仍可優化」。
            - 若圖片觀察與音訊明顯矛盾，在 model_check.notes 寫「需要複查」。
            - 若音訊 available=false，impact_quality.audio_feedback 填「無音訊分析資料」。

            impact_quality.quality_level 對應：0~1→"poor"；2→"fair"；3→"near_sweet_spot"；4→"sweet_spot"；5→"premium_sweet_spot"。

            請輸出嚴格 JSON，不要輸出 Markdown：
            {
              "summary": "一句整體評語",
              "primary_error": {
                "error_type": "",
                "zh_name": "",
                "severity": "low|medium|high",
                "evidence": ["基於哪張關鍵幀（第幾張、哪個 P 位置）觀察到的"]
              },
              "impact_quality": {
                "audio_sweet_spot": true,
                "pass_count": 3,
                "total_features": 5,
                "quality_level": "near_sweet_spot",
                "audio_feedback": "音訊擊球品質說明（1~2句）"
              },
              "coach_feedback": ["評語1（含音訊補充）", "評語2"],
              "practice_suggestions": [
                { "drill": "練習名稱", "instruction": "具體做法", "reps": "建議次數" }
              ],
              "next_training_goal": "下次目標",
              "model_check": { "is_consistent_with_video": true, "notes": "" }
            }

            ONNX 骨架推論結果：
            {{MODEL_ANALYSIS_JSON}}

            音訊特徵 JSON（供參考，以實際聆聽為主）：
            {{AUDIO_ANALYSIS_JSON}}
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
        private readonly IConfiguration _config;
        private readonly ILogger<GeminiService> _logger;

        public GeminiService(IHttpClientFactory httpFactory, IConfiguration config, ILogger<GeminiService> logger)
        {
            _http   = httpFactory.CreateClient("gemini");
            _apiKey = config["Gemini:ApiKey"] ?? throw new InvalidOperationException("Gemini:ApiKey 未設定");
            _model  = config["Gemini:Model"]  ?? "gemini-2.5-flash";
            _config = config;
            _logger = logger;
        }

        /// <summary>
        /// 呼叫 Gemini 分析揮桿影片。
        /// v1   ：inline base64 影片（1 FPS，低 token）
        /// v2   ：Files API 上傳 + videoMetadata.fps（完整解析，高精度）
        /// v3   ：8 關鍵禎 JPEG（inline）+ audio WAV（inline）；不傳影片
        /// </summary>
        public async Task<GeminiCoachResult> AnalyzeAsync(
            byte[] clipBytes,
            string? errorTypeHint,
            string promptVersion = "v1",
            Dictionary<string, double>? phaseTimestamps = null,
            string? audioAnalysisJson = null,
            string[]? keyframesBase64 = null,
            byte[]? audioWavBytes = null,
            int? v2Fps = null,
            string? v2Resolution = null,
            string? swingMetricsJson = null,
            string? lang = null,
            CancellationToken ct = default)
        {
            var modelAnalysis = BuildModelAnalysis(clipBytes, errorTypeHint);
            var prompt        = RenderPrompt(modelAnalysis, promptVersion, phaseTimestamps, audioAnalysisJson, swingMetricsJson, lang);

            return promptVersion switch
            {
                "v2" => await AnalyzeWithFilesApiAsync(clipBytes, prompt, v2Fps, v2Resolution, ct),
                "v3" => await AnalyzeWithKeyframesAsync(keyframesBase64, audioWavBytes, prompt, ct),
                _    => await AnalyzeInlineAsync(clipBytes, prompt, ct),
            };
        }

        // ── v1 / v3：inline base64（同原本邏輯）──────────────────────────

        private async Task<GeminiCoachResult> AnalyzeInlineAsync(
            byte[] clipBytes, string prompt, CancellationToken ct)
        {
            if (clipBytes.Length >= InlineLimitBytes)
                throw new InvalidOperationException($"Clip 超過 20MB inline 限制 ({clipBytes.Length / 1024 / 1024}MB)");

            var body = new
            {
                contents = new[]
                {
                    new
                    {
                        parts = new object[]
                        {
                            new { inlineData = new { mimeType = "video/mp4", data = Convert.ToBase64String(clipBytes) } },
                            new { text = prompt },
                        }
                    }
                },
                generationConfig = new { responseMimeType = "application/json" },
            };

            return await CallGeminiAsync(body, "inline", clipBytes.Length, ct);
        }

        // ── v2：Files API + videoMetadata.fps（完整 FPS 解析）─────────────

        private const int DefaultV2Fps = 10;
        // 合法值："MEDIA_RESOLUTION_HIGH" | "MEDIA_RESOLUTION_MEDIUM"（預設 HIGH）
        private const string DefaultV2Resolution = "MEDIA_RESOLUTION_HIGH";

        private async Task<GeminiCoachResult> AnalyzeWithFilesApiAsync(
            byte[] clipBytes, string prompt,
            int? v2FpsOverride, string? v2ResolutionOverride,
            CancellationToken ct)
        {
            // per-request 值優先；fallback 到 appsettings.json；再 fallback 到 hardcoded 預設
            var fps        = v2FpsOverride        ?? _config.GetValue<int?>("Gemini:V2Fps")           ?? DefaultV2Fps;
            var resolution = v2ResolutionOverride ?? _config.GetValue<string?>("Gemini:V2Resolution") ?? DefaultV2Resolution;
            string? fileUri  = null;
            string? fileName = null;

            try
            {
                // 1. 上傳 clip 到 Gemini Files API
                (fileUri, fileName) = await UploadVideoFileAsync(clipBytes, ct);
                _logger.LogInformation("Files API 上傳完成: {Name} ({KB}KB)", fileName, clipBytes.Length / 1024);

                // 2. 等待 file 狀態變 ACTIVE（最多 30 秒）
                await WaitForFileActiveAsync(fileName, ct);

                // 3. 用 fileData + videoMetadata 請求分析
                var body = new
                {
                    contents = new[]
                    {
                        new
                        {
                            parts = new object[]
                            {
                                new
                                {
                                    fileData      = new { mimeType = "video/mp4", fileUri },
                                    videoMetadata = new { fps },
                                },
                                new { text = prompt },
                            }
                        }
                    },
                    generationConfig = new
                    {
                        responseMimeType = "application/json",
                        mediaResolution  = resolution,
                    },
                };

                var r = await CallGeminiAsync(body, $"filesApi/fps={fps}/res={resolution}", clipBytes.Length, ct);
                return r with { ResolvedV2Fps = fps, ResolvedV2Resolution = resolution };
            }
            finally
            {
                // 4. 分析完畢後刪除 file（不論成敗）
                if (fileName != null)
                    await DeleteVideoFileAsync(fileName, CancellationToken.None);
            }
        }

        /// <summary>上傳 clip 到 Gemini Files API，回傳 (fileUri, fileName)。</summary>
        private async Task<(string fileUri, string fileName)> UploadVideoFileAsync(
            byte[] clipBytes, CancellationToken ct)
        {
            var uploadUrl = $"https://generativelanguage.googleapis.com/upload/v1beta/files?key={_apiKey}";

            var metaJson = JsonSerializer.Serialize(new { file = new { display_name = "golf_swing_v2" } });

            var multipart = new MultipartContent("related");
            multipart.Add(new StringContent(metaJson, Encoding.UTF8, "application/json"));
            var videoPart = new ByteArrayContent(clipBytes);
            videoPart.Headers.ContentType = new System.Net.Http.Headers.MediaTypeHeaderValue("video/mp4");
            multipart.Add(videoPart);

            var req = new HttpRequestMessage(HttpMethod.Post, uploadUrl) { Content = multipart };
            req.Headers.Add("X-Goog-Upload-Protocol", "multipart");

            using var resp = await _http.SendAsync(req, ct);
            var raw = await resp.Content.ReadAsStringAsync(ct);

            if (!resp.IsSuccessStatusCode)
                throw new HttpRequestException($"Files API 上傳失敗 {resp.StatusCode}: {raw}");

            var doc      = JsonDocument.Parse(raw);
            var fileObj  = doc.RootElement.GetProperty("file");
            var fileUri  = fileObj.GetProperty("uri").GetString()!;
            var fileName = fileObj.GetProperty("name").GetString()!; // "files/xxxx"
            return (fileUri, fileName);
        }

        /// <summary>輪詢直到 file 狀態為 ACTIVE 或逾時（30 秒）。</summary>
        private async Task WaitForFileActiveAsync(string fileName, CancellationToken ct)
        {
            var getUrl = $"https://generativelanguage.googleapis.com/v1beta/{fileName}?key={_apiKey}";
            for (int i = 0; i < 10; i++)
            {
                await Task.Delay(3000, ct);
                using var resp = await _http.GetAsync(getUrl, ct);
                var raw = await resp.Content.ReadAsStringAsync(ct);
                if (!resp.IsSuccessStatusCode) continue;

                var doc   = JsonDocument.Parse(raw);
                var state = doc.RootElement.TryGetProperty("state", out var s) ? s.GetString() : null;
                _logger.LogDebug("Files API state={State}", state);
                if (state == "ACTIVE") return;
                if (state == "FAILED") throw new InvalidOperationException("Files API 處理失敗");
            }
            throw new TimeoutException("Files API 等待 ACTIVE 逾時（30 秒）");
        }

        /// <summary>刪除 Files API 上的 file（靜默忽略失敗）。</summary>
        private async Task DeleteVideoFileAsync(string fileName, CancellationToken ct)
        {
            var deleteUrl = $"https://generativelanguage.googleapis.com/v1beta/{fileName}?key={_apiKey}";
            try
            {
                using var resp = await _http.DeleteAsync(deleteUrl, ct);
                _logger.LogDebug("Files API 刪除 {Name}: {Status}", fileName, resp.StatusCode);
            }
            catch (Exception ex)
            {
                _logger.LogWarning("Files API 刪除失敗（忽略）: {Err}", ex.Message);
            }
        }

        // ── v3：8 關鍵禎 JPEG + audio WAV（inline，不傳影片）────────────

        private async Task<GeminiCoachResult> AnalyzeWithKeyframesAsync(
            string[]? keyframesBase64,
            byte[]? audioWavBytes,
            string prompt,
            CancellationToken ct)
        {
            if (keyframesBase64 == null || keyframesBase64.Length == 0)
                throw new InvalidOperationException("V3 分析需要關鍵禎圖片（keyframesBase64 不可為空）");

            var parts = new List<object>();

            // 8 JPEG keyframes
            foreach (var b64 in keyframesBase64)
                parts.Add(new { inlineData = new { mimeType = "image/jpeg", data = b64 } });

            // audio WAV（可選）
            if (audioWavBytes != null && audioWavBytes.Length > 0)
                parts.Add(new { inlineData = new { mimeType = "audio/wav", data = Convert.ToBase64String(audioWavBytes) } });

            parts.Add(new { text = prompt });

            var body = new
            {
                contents = new[]
                {
                    new { parts = parts.ToArray<object>() }
                },
                generationConfig = new { responseMimeType = "application/json" },
            };

            int payloadSize = keyframesBase64.Sum(b => b.Length * 3 / 4) + (audioWavBytes?.Length ?? 0);
            _logger.LogInformation(
                "V3 分析：{KF} 關鍵禎 + audio={HasAudio} 估計 payload={KB}KB",
                keyframesBase64.Length, audioWavBytes != null, payloadSize / 1024);

            return await CallGeminiAsync(body, $"v3/keyframes={keyframesBase64.Length}", payloadSize, ct);
        }

        // ── 共用：呼叫 Gemini generateContent ────────────────────────────

        private async Task<GeminiCoachResult> CallGeminiAsync(
            object body, string mode, int clipBytes, CancellationToken ct)
        {
            var url     = $"https://generativelanguage.googleapis.com/v1beta/models/{_model}:generateContent?key={_apiKey}";
            var content = new StringContent(JsonSerializer.Serialize(body), Encoding.UTF8, "application/json");

            _logger.LogInformation("呼叫 Gemini API ({Model}) mode={Mode} clip={KB}KB",
                _model, mode, clipBytes / 1024);

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
                "Gemini 分析完成 mode={Mode} severity={Severity} inputTokens={In} outputTokens={Out}",
                mode, severity, inputTokens, outputTokens);

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

        /// <summary>
        /// 將語言代碼映射為輸出語言名稱（給 Gemini 的指示用）。
        /// 預設繁體中文（lang 為 null / 未知時，向後相容）。
        /// </summary>
        private static string OutputLanguageName(string? lang) => lang switch
        {
            "en"                              => "English",
            "zh_CN" or "zh-CN" or "zh_Hans"   => "简体中文（Simplified Chinese）",
            _                                  => "繁體中文（Traditional Chinese）",
        };

        /// <summary>
        /// 強化版輸出語言指示：所有自由文字用目標語言，但 JSON key 與 enum 值保持英文不變。
        /// 放在 prompt 結尾再強調一次，提高遵循率。
        /// </summary>
        private static string OutputLanguageDirective(string? lang)
        {
            var name = OutputLanguageName(lang);
            return "\n\n──────────────────────────────\n"
                + $"【輸出語言 / OUTPUT LANGUAGE】所有「自由文字」欄位一律使用 {name}：\n"
                + "summary、primary_error.zh_name、primary_error.evidence、impact_quality.audio_feedback、"
                + "coach_feedback、practice_suggestions（drill / instruction / reps）、next_training_goal、model_check.notes。\n"
                + "但 JSON 的 key 名稱與下列 enum 值必須保持原樣英文、不可翻譯："
                + "error_type（over_the_top / early_release_casting / weight_shift / spine_angle / impact）、"
                + "quality_level（poor / fair / near_sweet_spot / sweet_spot / premium_sweet_spot）、"
                + "severity（low / medium / high）。\n";
        }

        private static string RenderPrompt(
            object modelAnalysis,
            string promptVersion,
            Dictionary<string, double>? phaseTimestamps,
            string? audioAnalysisJson = null,
            string? swingMetricsJson = null,
            string? lang = null)
        {
            var modelJson = JsonSerializer.Serialize(modelAnalysis, new JsonSerializerOptions { WriteIndented = true });

            var template = promptVersion switch
            {
                "v2" => PromptV2,
                "v3" => PromptV3,
                _    => PromptV1,
            };

            var result = template.Replace("{{MODEL_ANALYSIS_JSON}}", modelJson);

            // V1 內嵌的「用繁體中文回答。」改成依語系（V2/V3 無此句 → no-op，靠結尾指示）
            result = result.Replace("用繁體中文回答。", $"使用 {OutputLanguageName(lang)} 回答。");

            if (promptVersion == "v3")
            {
                var phaseBlock = BuildPhaseBlock(phaseTimestamps);
                result = result.Replace("{{PHASE_TIMESTAMPS}}", phaseBlock);
            }

            // 音訊分析替換（所有版本）
            var audioBlock = BuildAudioAnalysisBlock(audioAnalysisJson);
            result = result.Replace("{{AUDIO_ANALYSIS_JSON}}", audioBlock);

            // 裝置端生物力學量化（P1-P10 角度/分級）：若 client 提供，附加為客觀依據。
            // 「數值由規則、評語由 LLM」——要求 evidence 引用具體角度而非自行臆測。
            if (!string.IsNullOrWhiteSpace(swingMetricsJson))
            {
                result += "\n\n── 裝置端生物力學量化（P1-P10 角度/分級，客觀可重現數值）──\n"
                    + "請優先以下列數值為依據，coach_feedback / evidence 須引用具體角度"
                    + "（例：『P4 X-factor 偏小，上桿身體分離不足』）；勿自行臆測未提供的角度。\n"
                    + swingMetricsJson;
            }

            // 結尾再強調輸出語言（所有版本），提高 LLM 遵循率
            result += OutputLanguageDirective(lang);

            return result;
        }

        private static string BuildPhaseBlock(Dictionary<string, double>? phases)
        {
            if (phases == null || phases.Count == 0)
                return "（未提供關鍵禎時間點，請自行從影片中識別 P-System P1-P10 各位置）";

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
                // P-System（P2/P6/P8 桿身、P3/P5/P9 手臂為代理估計）
                "p1"  => "P1 預備",   "p2" => "P2 桿水平(上)", "p3" => "P3 臂水平(上)",
                "p4"  => "P4 頂點",   "p5" => "P5 臂水平(下)", "p6" => "P6 桿水平(下)",
                "p7"  => "P7 擊球",   "p8" => "P8 桿水平(送)", "p9" => "P9 臂水平(送)",
                "p10" => "P10 收桿",
                _               => key,
            };

            // 有 P1-P10 → 用 P-System 順序（業界標準）；否則退回舊 8 階段。
            var pOrder = new[] { "p1", "p2", "p3", "p4", "p5", "p6", "p7", "p8", "p9", "p10" };
            var hasP = pOrder.Any(phases.ContainsKey);
            var order = hasP
                ? pOrder
                : new[] { "address", "takeaway", "backswing", "top", "downswing", "impact", "followthrough", "finish" };
            var header = hasP
                ? "P-System 關鍵時間點（P1-P10，請重點觀察這些秒數的畫面）：\n"
                : "揮桿關鍵時間點（請重點觀察這些秒數的畫面）：\n";
            var lines = new System.Text.StringBuilder(header);
            foreach (var key in order)
            {
                if (phases.TryGetValue(key, out var sec))
                    lines.AppendLine($"  {PhaseName(key)}: {sec:F1}s");
            }
            return lines.ToString();
        }

        private static string BuildAudioAnalysisBlock(string? audioAnalysisJson)
        {
            if (string.IsNullOrWhiteSpace(audioAnalysisJson))
                return """{"available": false, "pass_count": 0, "total_features": 5, "sweet_spot": false, "notes": "無音訊分析資料"}""";
            return audioAnalysisJson;
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
