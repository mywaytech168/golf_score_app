using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using UploadServer.Data;

namespace UploadServer.Services;

/// <summary>
/// 背景 Worker：輪詢 ball_trajectory_analyses 佇列，
/// 下載 clip → 執行 Python worker → 寫回軌跡 JSON。
///
/// 狀態機：
///   pending  → queued（Controller /ready 觸發）
///   queued   → processing → completed
///   queued   → processing → failed（重試超過 MaxRetry）
/// </summary>
public class BallTrajectoryWorkerService : BackgroundService
{
    private static readonly TimeSpan _pollInterval = TimeSpan.FromSeconds(5);
    private const int MaxRetry = 3;

    private readonly IServiceScopeFactory              _scopeFactory;
    private readonly B2Service                         _b2;
    private readonly BallTrajectoryPythonService       _python;
    private readonly ILogger<BallTrajectoryWorkerService> _logger;

    public BallTrajectoryWorkerService(
        IServiceScopeFactory         scopeFactory,
        B2Service                    b2,
        BallTrajectoryPythonService  python,
        ILogger<BallTrajectoryWorkerService> logger)
    {
        _scopeFactory = scopeFactory;
        _b2           = b2;
        _python       = python;
        _logger       = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken ct)
    {
        if (!_python.IsAvailable)
        {
            _logger.LogWarning(
                "BallTrajectoryWorkerService: Python worker 不可用（ScriptPath 未設定或腳本不存在），服務已停用");
            return;
        }

        _logger.LogInformation("BallTrajectoryWorkerService 已啟動");
        await Task.Delay(TimeSpan.FromSeconds(12), ct); // 讓 DB 先就緒

        while (!ct.IsCancellationRequested)
        {
            try
            {
                await ProcessNextAsync(ct);
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                _logger.LogError(ex, "BallTrajectoryWorker 未預期錯誤");
            }
            await Task.Delay(_pollInterval, ct);
        }
    }

    private async Task ProcessNextAsync(CancellationToken ct)
    {
        using var scope = _scopeFactory.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<VideoDbContext>();

        var analysis = await db.BallTrajectoryAnalyses
            .Where(a => a.Status == "queued" && a.RetryCount < MaxRetry)
            .OrderBy(a => a.CreatedAt)
            .FirstOrDefaultAsync(ct);

        if (analysis == null) return;

        _logger.LogInformation("開始處理球軌跡: {Id} VideoId={Vid}", analysis.Id, analysis.VideoId);

        analysis.Status = "processing";
        await db.SaveChangesAsync(ct);

        try
        {
            // 1. 產生 B2 presigned download URL，讓 Flask server 自己下載
            //    （C# 與 Flask 在不同機器，不能共用本地路徑）
            var clipUrl = _b2.GenerateDownloadUrlForKey(analysis.ClipB2Path!, expiryMinutes: 15);
            _logger.LogInformation("Clip URL 已產生: {Id}", analysis.Id);

            // 2. 呼叫 Flask server（傳 URL，Flask 自行下載到本地暫存）
            var result = await _python.RunAsync(
                videoUrl   : clipUrl,
                hitSec     : analysis.HitSec,
                flipMode   : analysis.FlipMode,
                roiCxRatio : analysis.RoiCxRatio,
                roiCyRatio : analysis.RoiCyRatio,
                roiRadius  : analysis.RoiRadius,
                ct         : ct);

            // 3. 寫回結果
            analysis.TrackPtsJson  = JsonSerializer.Serialize(result.TrackPts);
            analysis.VideoFps      = result.Fps;
            analysis.VideoWidth    = result.Width;
            analysis.VideoHeight   = result.Height;
            analysis.VideoRotation = result.Rotation;
            analysis.Status        = "completed";
            analysis.CompletedAt   = DateTime.UtcNow;

            _logger.LogInformation(
                "球軌跡完成: {Id} pts={N} fps={Fps} size={W}x{H} rot={R}°",
                analysis.Id, result.TrackPts.Count, result.Fps, result.Width, result.Height, result.Rotation);
        }
        catch (Exception ex)
        {
            analysis.RetryCount++;
            analysis.ErrorMessage = ex.Message;
            analysis.Status       = analysis.RetryCount >= MaxRetry ? "failed" : "queued";
            _logger.LogError(ex, "球軌跡分析失敗: {Id} retry={R}", analysis.Id, analysis.RetryCount);
        }

        await db.SaveChangesAsync(ct);
    }

}
