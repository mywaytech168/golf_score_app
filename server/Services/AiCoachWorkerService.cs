using Microsoft.EntityFrameworkCore;
using UploadServer.Data;

namespace UploadServer.Services
{
    /// <summary>
    /// 背景 Worker：輪詢 ai_coach_analyses 佇列，下載 clip 並呼叫 Gemini
    /// </summary>
    public class AiCoachWorkerService : BackgroundService
    {
        private static readonly TimeSpan _pollInterval = TimeSpan.FromSeconds(5);
        private const int MaxRetry = 3;

        private readonly IServiceScopeFactory _scopeFactory;
        private readonly B2Service _b2;
        private readonly GeminiService _gemini;
        private readonly IHttpClientFactory _httpFactory;
        private readonly ILogger<AiCoachWorkerService> _logger;

        public AiCoachWorkerService(
            IServiceScopeFactory scopeFactory,
            B2Service b2,
            GeminiService gemini,
            IHttpClientFactory httpFactory,
            ILogger<AiCoachWorkerService> logger)
        {
            _scopeFactory = scopeFactory;
            _b2           = b2;
            _gemini       = gemini;
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
                // 1. 從 B2 下載 clip（透過 Presigned GET）
                var downloadUrl = _b2.GenerateClipDownloadUrl(analysis.ClipB2Path!);
                var clipBytes   = await DownloadBytesAsync(downloadUrl, ct);

                _logger.LogInformation("Clip 下載完成: {KB}KB", clipBytes.Length / 1024);

                // 2. 呼叫 Gemini 分析
                var result = await _gemini.AnalyzeAsync(clipBytes, analysis.ErrorTypeHint, ct);

                // 3. 寫回結果
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
