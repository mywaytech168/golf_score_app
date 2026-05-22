using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using UploadServer.Data;
using UploadServer.DTOs;

namespace UploadServer.Services
{
    /// <summary>
    /// 背景 Worker：輪詢 ai_coach_analyses 佇列，下載 clip（＋可選 CSV），
    /// 執行 ONNX 推論取得錯誤類型，再呼叫 Gemini 產出教練回饋。
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
            await Task.Delay(TimeSpan.FromSeconds(10), ct); // 等待其他服務初始化

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

            _logger.LogInformation("開始處理 AI Coach 分析: {Id}", analysis.Id);

            analysis.Status = "processing";
            await db.SaveChangesAsync(ct);

            try
            {
                // 1. 從 B2 下載 clip
                var clipUrl   = _b2.GenerateClipDownloadUrl(analysis.ClipB2Path!);
                var clipBytes = await DownloadBytesAsync(clipUrl, ct);
                _logger.LogInformation("Clip 下載完成: {KB}KB", clipBytes.Length / 1024);

                // 2. 若有 CSV，執行 ONNX 推論取得錯誤類型
                string? effectiveHint = analysis.ErrorTypeHint;
                if (analysis.CsvB2Path != null)
                {
                    if (_onnx.IsAvailable)
                    {
                        try
                        {
                            var csvUrl     = _b2.GenerateDownloadUrlForKey(analysis.CsvB2Path);
                            var csvBytes   = await DownloadBytesAsync(csvUrl, ct);
                            var csvContent = System.Text.Encoding.UTF8.GetString(csvBytes);
                            var frames     = GolfSwingAnalyzerService.ParseCsvToFrames(csvContent);

                            if (frames.Count >= 2)
                            {
                                var onnxResult = _onnx.Analyze(new GolfSwingAnalysisRequest(frames));
                                analysis.OnnxResultJson = JsonSerializer.Serialize(onnxResult);

                                var onnxTop = onnxResult.OfficialErrors.FirstOrDefault()
                                           ?? onnxResult.SuspectErrors.FirstOrDefault();
                                if (onnxTop != null)
                                {
                                    effectiveHint = onnxTop;
                                    _logger.LogInformation(
                                        "ONNX 推論完成: topError={Error} frames={N}",
                                        effectiveHint, frames.Count);
                                }
                                else
                                {
                                    _logger.LogInformation(
                                        "ONNX 推論完成但無明確錯誤，沿用 hint={Hint}", effectiveHint ?? "(none)");
                                }
                            }
                            else
                            {
                                _logger.LogWarning("CSV 幀數不足 ({N})，跳過 ONNX", frames.Count);
                            }
                        }
                        catch (Exception ex)
                        {
                            _logger.LogWarning(ex, "ONNX 推論失敗（略過，繼續 Gemini）");
                        }
                    }
                    else
                    {
                        _logger.LogInformation("ONNX 模型未就緒，跳過 CSV 分析");
                    }
                }

                // 3. 呼叫 Gemini 分析
                var result = await _gemini.AnalyzeAsync(clipBytes, effectiveHint, ct);

                // 4. 寫回結果
                analysis.Status      = "completed";
                analysis.ResultJson  = result.RawJson;
                analysis.Summary     = result.Summary;
                analysis.Severity    = result.Severity;
                analysis.CompletedAt = DateTime.UtcNow;

                _logger.LogInformation("AI Coach 分析完成: {Id}", analysis.Id);
            }
            catch (Exception ex)
            {
                analysis.RetryCount++;
                analysis.Status = analysis.RetryCount >= MaxRetry ? "failed" : "queued";
                _logger.LogError(ex, "AI Coach 分析失敗: {Id}，重試次數={Retry}", analysis.Id, analysis.RetryCount);
            }

            await db.SaveChangesAsync(ct);
        }

        private async Task<byte[]> DownloadBytesAsync(string url, CancellationToken ct)
        {
            var http = _httpFactory.CreateClient();
            http.Timeout = TimeSpan.FromMinutes(3);
            return await http.GetByteArrayAsync(url, ct);
        }
    }
}
