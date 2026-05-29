using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using UploadServer.Data;
using UploadServer.DTOs;

namespace UploadServer.Services
{
    /// <summary>
    /// 背景 Worker：輪詢 ai_coach_analyses 佇列，下載 clip（＋可選 CSV），
    /// 執行 ONNX 推論取得錯誤類型，再依 Mode 決定是否呼叫 Gemini。
    ///
    /// 狀態機：
    ///   pending  → queued（Controller /ready 觸發）
    ///   queued   → processing → idle      (Mode="posture_only"：ONNX only)
    ///   queued   → processing → completed (Mode="full"：ONNX + Gemini)
    ///   idle     → queued（Controller /upgrade 觸發，Mode 改為 "full"）
    ///   queued   → processing → completed (upgrade：OnnxResultJson 已有，跳過 ONNX)
    /// </summary>
    public class AiCoachWorkerService : BackgroundService
    {
        private static readonly TimeSpan _pollInterval = TimeSpan.FromSeconds(5);
        private const int MaxRetry = 3;

        private readonly IServiceScopeFactory _scopeFactory;
        private readonly B2Service _b2;
        private readonly GeminiService _gemini;
        private readonly GolfSwingAnalyzerService _onnx;
        private readonly IHttpClientFactory _httpFactory;
        private readonly ILogger<AiCoachWorkerService> _logger;

        public AiCoachWorkerService(
            IServiceScopeFactory scopeFactory,
            B2Service b2,
            GeminiService gemini,
            GolfSwingAnalyzerService onnx,
            IHttpClientFactory httpFactory,
            ILogger<AiCoachWorkerService> logger)
        {
            _scopeFactory = scopeFactory;
            _b2           = b2;
            _gemini       = gemini;
            _onnx         = onnx;
            _httpFactory  = httpFactory;
            _logger       = logger;
        }

        protected override async Task ExecuteAsync(CancellationToken ct)
        {
            _logger.LogInformation("AiCoachWorkerService 已啟動");
            await Task.Delay(TimeSpan.FromSeconds(10), ct);

            while (!ct.IsCancellationRequested)
            {
                try
                {
                    await ProcessNextAsync(ct);
                }
                catch (Exception ex) when (ex is not OperationCanceledException)
                {
                    _logger.LogError(ex, "AiCoachWorker 發生未預期錯誤");
                }

                await Task.Delay(_pollInterval, ct);
            }
        }

        private async Task ProcessNextAsync(CancellationToken ct)
        {
            using var scope = _scopeFactory.CreateScope();
            var db = scope.ServiceProvider.GetRequiredService<VideoDbContext>();

            var analysis = await db.AiCoachAnalyses
                .Where(a => a.Status == "queued" && a.RetryCount < MaxRetry)
                .OrderBy(a => a.CreatedAt)
                .FirstOrDefaultAsync(ct);

            if (analysis == null) return;

            _logger.LogInformation("開始處理 AI Coach 分析: {Id} Mode={Mode} PromptVersion={Ver}",
                analysis.Id, analysis.Mode, analysis.PromptVersion);

            analysis.Status = "processing";
            await db.SaveChangesAsync(ct);

            try
            {
                // --- 1. 下載 clip（V3 且已有 ONNX 結果時可省略）---
                // V3 Gemini 只用 keyframes + audio，不用 clipBytes；但 V1/V2 仍需
                bool isV3 = analysis.PromptVersion == "v3";
                bool onnxAlreadyDone = !string.IsNullOrEmpty(analysis.OnnxResultJson);
                bool needClip = !isV3 || !onnxAlreadyDone; // V3 upgrade 路徑也不需 clip

                byte[] clipBytes = [];
                if (needClip)
                {
                    var clipUrl = _b2.GenerateClipDownloadUrl(analysis.ClipB2Path!);
                    clipBytes   = await DownloadBytesAsync(clipUrl, ct);
                    _logger.LogInformation("Clip 下載完成: {KB}KB", clipBytes.Length / 1024);
                }
                else
                {
                    _logger.LogInformation("V3：跳過 clip 下載（Gemini 使用關鍵幀圖片）");
                }

                // --- 2. ONNX 推論（僅在尚未有結果時執行）---
                // upgrade 路徑：OnnxResultJson 已填入 → 直接跳過，解析既有結果取 effectiveHint
                string? effectiveHint = analysis.ErrorTypeHint;

                if (onnxAlreadyDone)
                {
                    effectiveHint = ExtractHintFromOnnxJson(analysis.OnnxResultJson!, effectiveHint);
                    _logger.LogInformation("升級路徑：沿用既有 ONNX 結果，effectiveHint={Hint}", effectiveHint ?? "(none)");
                }
                else if (analysis.CsvB2Path != null)
                {
                    effectiveHint = await RunOnnxAsync(analysis, effectiveHint, ct);
                }

                // --- 3. 依 Mode 決定後續 ---
                if (analysis.Mode == "posture_only")
                {
                    // 只做 ONNX，完成後進入 idle，不呼叫 Gemini
                    analysis.Status      = "idle";
                    analysis.CompletedAt = DateTime.UtcNow;
                    _logger.LogInformation("posture_only 完成，進入 idle: {Id}", analysis.Id);
                }
                else
                {
                    // full 模式（含 upgrade）：呼叫 Gemini
                    Dictionary<string, double>? phaseTimestamps = null;
                    if (!string.IsNullOrEmpty(analysis.PhaseTimestampsJson))
                    {
                        try { phaseTimestamps = JsonSerializer.Deserialize<Dictionary<string, double>>(analysis.PhaseTimestampsJson); }
                        catch { /* JSON 損毀時忽略 */ }
                    }

                    // v3：解析關鍵禎 + 下載 audio
                    string[]? keyframesBase64 = null;
                    byte[]? audioWavBytes = null;
                    if (analysis.PromptVersion == "v3")
                    {
                        if (!string.IsNullOrEmpty(analysis.KeyframesJson))
                        {
                            try { keyframesBase64 = JsonSerializer.Deserialize<string[]>(analysis.KeyframesJson); }
                            catch { /* JSON 損毀時忽略 */ }
                        }
                        if (!string.IsNullOrEmpty(analysis.AudioB2Path))
                        {
                            try
                            {
                                var audioUrl = _b2.GenerateDownloadUrlForKey(analysis.AudioB2Path);
                                audioWavBytes = await DownloadBytesAsync(audioUrl, ct);
                                _logger.LogInformation("V3 audio 下載完成: {KB}KB", audioWavBytes.Length / 1024);
                            }
                            catch (Exception ex)
                            {
                                _logger.LogWarning(ex, "V3 audio 下載失敗（略過）");
                            }
                        }
                    }

                    var result = await _gemini.AnalyzeAsync(
                        clipBytes,
                        effectiveHint,
                        analysis.PromptVersion,
                        phaseTimestamps:  phaseTimestamps,
                        audioAnalysisJson: analysis.AudioAnalysisJson,
                        keyframesBase64:  keyframesBase64,
                        audioWavBytes:    audioWavBytes,
                        v2Fps:            analysis.V2Fps,
                        v2Resolution:     analysis.V2Resolution,
                        ct: ct);

                    analysis.Status       = "completed";
                    analysis.ResultJson   = result.RawJson;
                    analysis.Summary      = result.Summary;
                    analysis.Severity     = result.Severity;
                    analysis.InputTokens  = result.InputTokens;
                    analysis.OutputTokens = result.OutputTokens;
                    analysis.CompletedAt  = DateTime.UtcNow;
                    if (result.ResolvedV2Fps        != null) analysis.V2Fps        = result.ResolvedV2Fps;
                    if (result.ResolvedV2Resolution != null) analysis.V2Resolution = result.ResolvedV2Resolution;

                    _logger.LogInformation(
                        "AI Coach 分析完成: {Id} tokens={In}/{Out}",
                        analysis.Id, result.InputTokens, result.OutputTokens);
                }
            }
            catch (Exception ex)
            {
                analysis.RetryCount++;
                analysis.Status = analysis.RetryCount >= MaxRetry ? "failed" : "queued";
                _logger.LogError(ex, "AI Coach 分析失敗: {Id}，重試次數={Retry}", analysis.Id, analysis.RetryCount);
            }

            await db.SaveChangesAsync(ct);
        }

        /// <summary>執行 ONNX 推論並將結果寫回 analysis.OnnxResultJson；回傳最佳錯誤類型字串。</summary>
        private async Task<string?> RunOnnxAsync(
            UploadServer.Models.AiCoachAnalysis analysis,
            string? fallbackHint,
            CancellationToken ct)
        {
            if (!_onnx.IsAvailable)
            {
                _logger.LogInformation("ONNX 模型未就緒，跳過 CSV 分析");
                return fallbackHint;
            }

            try
            {
                var csvUrl     = _b2.GenerateDownloadUrlForKey(analysis.CsvB2Path!);
                var csvBytes   = await DownloadBytesAsync(csvUrl, ct);
                var csvContent = System.Text.Encoding.UTF8.GetString(csvBytes);
                var frames     = GolfSwingAnalyzerService.ParseCsvToFrames(csvContent);

                if (frames.Count < 2)
                {
                    _logger.LogWarning("CSV 幀數不足 ({N})，跳過 ONNX", frames.Count);
                    return fallbackHint;
                }

                var onnxResult = _onnx.Analyze(new GolfSwingAnalysisRequest(frames));
                analysis.OnnxResultJson = JsonSerializer.Serialize(onnxResult);

                var topError = onnxResult.OfficialErrors.FirstOrDefault()
                            ?? onnxResult.SuspectErrors.FirstOrDefault();

                if (topError != null)
                {
                    _logger.LogInformation("ONNX 推論完成: topError={Error} frames={N}", topError, frames.Count);
                    return topError;
                }

                _logger.LogInformation("ONNX 推論完成但無明確錯誤，沿用 hint={Hint}", fallbackHint ?? "(none)");
                return fallbackHint;
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "ONNX 推論失敗（略過，繼續後續步驟）");
                return fallbackHint;
            }
        }

        /// <summary>從已序列化的 OnnxResultJson 中解析出最佳錯誤類型字串。</summary>
        private static string? ExtractHintFromOnnxJson(string json, string? fallback)
        {
            try
            {
                var doc = JsonSerializer.Deserialize<JsonElement>(json);
                // OfficialErrors 優先
                if (doc.TryGetProperty("officialErrors", out var off) && off.GetArrayLength() > 0)
                    return off[0].GetString() ?? fallback;
                if (doc.TryGetProperty("suspectErrors", out var sus) && sus.GetArrayLength() > 0)
                    return sus[0].GetString() ?? fallback;
            }
            catch { /* JSON 損毀時忽略 */ }
            return fallback;
        }

        private async Task<byte[]> DownloadBytesAsync(string url, CancellationToken ct)
        {
            var http = _httpFactory.CreateClient();
            http.Timeout = TimeSpan.FromMinutes(3);
            return await http.GetByteArrayAsync(url, ct);
        }
    }
}
