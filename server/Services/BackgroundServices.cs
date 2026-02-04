using System;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.DependencyInjection;
using UploadServer.Data;
using Microsoft.EntityFrameworkCore;

namespace UploadServer.Services
{
    /// <summary>
    /// 數據庫連接池監視服務 (修復 5️⃣)
    /// </summary>
    public class DbConnectionPoolMonitor : IHostedService
    {
        private readonly ILogger<DbConnectionPoolMonitor> _logger;
        private readonly IServiceProvider _serviceProvider;
        private Timer _timer;

        public DbConnectionPoolMonitor(
            ILogger<DbConnectionPoolMonitor> logger,
            IServiceProvider serviceProvider)
        {
            _logger = logger;
            _serviceProvider = serviceProvider;
        }

        public async Task StartAsync(CancellationToken cancellationToken)
        {
            _logger.LogInformation("🚀 DB 連接池監視器已啟動");

            _timer = new Timer(async state =>
            {
                try
                {
                    using var scope = _serviceProvider.CreateScope();
                    var dbContext = scope.ServiceProvider
                        .GetRequiredService<VideoDbContext>();

                    var connection = dbContext.Database.GetDbConnection();
                    await connection.OpenAsync(cancellationToken);
                    await connection.CloseAsync();

                    _logger.LogDebug("✅ DB Connection Pool: Healthy");
                }
                catch (Exception ex)
                {
                    _logger.LogError($"❌ DB Connection Pool Error: {ex.Message}");
                }
            }, null, TimeSpan.Zero, TimeSpan.FromMinutes(5));

            await Task.CompletedTask;
        }

        public async Task StopAsync(CancellationToken cancellationToken)
        {
            _timer?.Dispose();
            _logger.LogInformation("🛑 DB 連接池監視器已停止");
            await Task.CompletedTask;
        }
    }

    /// <summary>
    /// JWT 密鑰輪換服務 (修復 6️⃣)
    /// </summary>
    public class JwtKeyRotationService : IHostedService
    {
        private readonly ILogger<JwtKeyRotationService> _logger;
        private readonly IConfiguration _config;
        private Timer _timer;

        public JwtKeyRotationService(
            ILogger<JwtKeyRotationService> logger,
            IConfiguration config)
        {
            _logger = logger;
            _config = config;
        }

        public async Task StartAsync(CancellationToken cancellationToken)
        {
            _logger.LogInformation("🚀 JWT 密鑰輪換服務已啟動");

            _timer = new Timer(state =>
            {
                CheckKeyRotation();
            }, null, TimeSpan.Zero, TimeSpan.FromDays(1));

            await Task.CompletedTask;
        }

        private void CheckKeyRotation()
        {
            try
            {
                _logger.LogInformation("🔄 JWT 密鑰輪換檢查...");

                var keyRotationIntervalDays = _config.GetValue<int>(
                    "Jwt:KeyRotationIntervalDays", 90);

                var lastRotationStr = _config.GetValue<string>(
                    "Jwt:LastKeyRotation", DateTime.UtcNow.ToString("O"));

                if (DateTime.TryParse(lastRotationStr, out var lastRotation))
                {
                    var daysSinceRotation = (DateTime.UtcNow - lastRotation).TotalDays;

                    if (daysSinceRotation > keyRotationIntervalDays)
                    {
                        _logger.LogWarning(
                            $"⚠️ 建議輪換 JWT 密鑰 (距離上次輪換 {daysSinceRotation:F1} 天)");
                        // 發送告警通知
                    }
                    else
                    {
                        var daysUntilRotation = keyRotationIntervalDays - daysSinceRotation;
                        _logger.LogDebug(
                            $"✅ JWT 密鑰有效 (還可使用 {daysUntilRotation:F1} 天)");
                    }
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "❌ JWT 密鑰輪換檢查異常");
            }
        }

        public async Task StopAsync(CancellationToken cancellationToken)
        {
            _timer?.Dispose();
            _logger.LogInformation("🛑 JWT 密鑰輪換服務已停止");
            await Task.CompletedTask;
        }
    }
}
