using Microsoft.EntityFrameworkCore;
using UploadServer.Data;

namespace UploadServer.Services
{
    /// <summary>
    /// 背景服務：每小時掃描過期的 share_links，刪除 B2 檔案並清除 DB 記錄
    /// </summary>
    public class ShareCleanupService : BackgroundService
    {
        private static readonly TimeSpan _interval = TimeSpan.FromHours(1);

        private readonly IServiceScopeFactory _scopeFactory;
        private readonly B2Service _b2;
        private readonly ILogger<ShareCleanupService> _logger;

        public ShareCleanupService(
            IServiceScopeFactory scopeFactory,
            B2Service b2,
            ILogger<ShareCleanupService> logger)
        {
            _scopeFactory = scopeFactory;
            _b2           = b2;
            _logger       = logger;
        }

        protected override async Task ExecuteAsync(CancellationToken stoppingToken)
        {
            _logger.LogInformation("ShareCleanupService 已啟動，每 {Hours} 小時執行一次", _interval.TotalHours);

            // 啟動後稍微延遲，讓其他服務先完成初始化
            await Task.Delay(TimeSpan.FromMinutes(1), stoppingToken);

            while (!stoppingToken.IsCancellationRequested)
            {
                try
                {
                    await CleanupExpiredAsync(stoppingToken);
                }
                catch (Exception ex) when (ex is not OperationCanceledException)
                {
                    _logger.LogError(ex, "ShareCleanupService 執行時發生錯誤");
                }

                await Task.Delay(_interval, stoppingToken);
            }
        }

        private async Task CleanupExpiredAsync(CancellationToken ct)
        {
            using var scope = _scopeFactory.CreateScope();
            var db = scope.ServiceProvider.GetRequiredService<VideoDbContext>();

            var expired = await db.ShareLinks
                .Where(l => l.ExpiresAt <= DateTime.Now)
                .ToListAsync(ct);

            if (expired.Count == 0)
            {
                _logger.LogDebug("ShareCleanup: 無過期記錄");
                return;
            }

            _logger.LogInformation("ShareCleanup: 找到 {Count} 筆過期記錄，開始清理", expired.Count);

            foreach (var link in expired)
            {
                // 先刪 B2（失敗不阻斷，B2Service 內部已 catch）
                await _b2.DeleteObjectAsync(link.B2FileName);
            }

            db.ShareLinks.RemoveRange(expired);
            await db.SaveChangesAsync(ct);

            _logger.LogInformation("ShareCleanup: 已清除 {Count} 筆過期記錄", expired.Count);
        }
    }
}
