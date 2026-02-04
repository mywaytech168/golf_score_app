using Microsoft.EntityFrameworkCore;
using Newtonsoft.Json;
using UploadServer.Data;
using UploadServer.Models;
using System.Diagnostics;
using System.Net.Http.Json;

namespace UploadServer.Services
{
    /// <summary>
    /// 處理隊列排程服務
    /// 定期檢查待處理的隊列項目，並將其發送到 Python Server 進行處理
    /// 特性：
    /// - 每秒檢查一次隊列
    /// - 一次只處理一個項目
    /// - 等待完成後再取下一個
    /// - 失敗重試機制
    /// </summary>
    public class ProcessingSchedulerService : BackgroundService
    {
        private readonly IServiceProvider _serviceProvider;
        private readonly ILogger<ProcessingSchedulerService> _logger;
        private readonly HttpClient _httpClient;
        private readonly IConfiguration _configuration;

        // 狀態標誌
        private bool _isProcessing = false;
        private string? _currentProcessingQueueId = null;
        private DateTime _lastCheckTime = DateTime.MinValue;

        public ProcessingSchedulerService(
            IServiceProvider serviceProvider,
            ILogger<ProcessingSchedulerService> logger,
            IHttpClientFactory httpClientFactory,
            IConfiguration configuration)
        {
            _serviceProvider = serviceProvider;
            _logger = logger;
            _httpClient = httpClientFactory.CreateClient();
            _configuration = configuration;
        }

        /// <summary>
        /// 後台服務的主執行方法
        /// </summary>
        protected override async Task ExecuteAsync(CancellationToken stoppingToken)
        {
            _logger.LogInformation("🚀 ProcessingSchedulerService 已啟動");

            // 延遲啟動以確保應用完全初始化
            await Task.Delay(2000, stoppingToken);

            // 主循環：每秒檢查一次
            while (!stoppingToken.IsCancellationRequested)
            {
                try
                {
                    // 每秒執行一次檢查
                    await Task.Delay(1000, stoppingToken);

                    // 如果沒有項目正在處理，則檢查是否有待處理的項目
                    if (!_isProcessing)
                    {
                        await ProcessNextQueueItemAsync(stoppingToken);
                    }
                    else
                    {
                        // 定期日誌輸出當前狀態
                        if ((DateTime.Now - _lastCheckTime).TotalSeconds > 30)
                        {
                            _logger.LogInformation($"⏳ 正在處理隊列項目: {_currentProcessingQueueId}");
                            _lastCheckTime = DateTime.Now;
                        }
                    }
                }
                catch (Exception ex)
                {
                    if (ex is not OperationCanceledException)
                    {
                        _logger.LogError(ex, "❌ 排程器發生錯誤");
                    }
                    _isProcessing = false;
                }
            }

            _logger.LogInformation("🛑 ProcessingSchedulerService 已停止");
        }

        /// <summary>
        /// 處理下一個隊列項目
        /// </summary>
        private async Task ProcessNextQueueItemAsync(CancellationToken stoppingToken)
        {
            try
            {
                // 從資料庫獲取待處理項目
                using (var scope = _serviceProvider.CreateScope())
                {
                    var dbContext = scope.ServiceProvider.GetRequiredService<VideoDbContext>();

                    // 查詢狀態為 "queued" 的項目，按創建時間先進先出
                    var queueItem = await dbContext.ProcessQueueItems
                        .AsNoTracking()
                        .Where(q => q.Status == "ready")
                        .OrderBy(q => q.CreatedAt)             // 按創建時間先進先出
                        .FirstOrDefaultAsync(stoppingToken);

                    if (queueItem == null)
                    {
                        // 沒有待處理項目，這是正常的
                        return;
                    }

                    _logger.LogInformation($"📋 發現待處理項目: {queueItem.Id} (VideoId: {queueItem.VideoId})");
                    // 標記為正在處理
                    _isProcessing = true;
                    _currentProcessingQueueId = queueItem.Id;

                    try
                    {
                        // 獲取 Python Server 的 URL
                        var pythonServerUrl = _configuration["ServiceUrls:PythonServerUrl"] 
                            ?? "http://localhost:5000";

                        _logger.LogInformation($"🔗 準備發送到 Python Server: {pythonServerUrl}");

                        // 獲取視頻的檔案目錄
                        var videoFiles = await dbContext.Files
                            .Where(f => f.VideoId == queueItem.VideoId)
                            .Where(f => f.Type == "clip")
                            .FirstOrDefaultAsync();
                        
                        var inputDir = "";
                        if (videoFiles != null && !string.IsNullOrEmpty(videoFiles.FilePath))
                        {
                            // 從檔案路徑提取目錄
                            inputDir = Path.GetDirectoryName(videoFiles.FilePath) ?? "";
                            _logger.LogInformation($"📁 提取的檔案目錄: {inputDir} (來自: {videoFiles.FilePath})");
                        }
                        else
                        {
                            _logger.LogWarning($"⚠️  無法找到視頻檔案，使用默認空目錄");
                        }

                        // 準備請求數據
                        var requestData = new
                        {
                            queueItemId = queueItem.Id,
                            videoId = queueItem.VideoId,
                            inputDir = inputDir,
                            timestamp = DateTime.UtcNow
                        };

                        // 發送到 Python Server
                        var response = await SendToPythonServerAsync(
                            pythonServerUrl,
                            queueItem.Id,
                            requestData,
                            stoppingToken);

                        if (response.IsSuccessStatusCode)
                        {
                            _logger.LogInformation($"✅ 成功發送到 Python Server: {queueItem.Id}");

                            // 等待 Python Server 的回調
                            // 立即標記為 queued
                            await UpdateQueueItemAsync(
                                 queueItem.Id,
                                 "queued",
                                 startedAt: DateTime.Now,
                                 dbContext: dbContext);

                        }
                        else
                        {
                            _logger.LogWarning(
                                $"❌ Python Server 返回錯誤: {response.StatusCode}");

                            // ✅ 改進：由 Python 端通過回調發送失敗狀態
                            // await UpdateQueueItemAsync(...)
                        }
                    }
                    catch (HttpRequestException ex)
                    {
                        _logger.LogError(ex, $"❌ 發送請求到 Python Server 時出錯");

                        // 重試計數
                        await IncrementRetryCountAsync(queueItem.Id, ex.Message, dbContext);
                    }
                    catch (OperationCanceledException)
                    {
                        _logger.LogWarning($"⏱️  發送請求超時: {queueItem.Id}");
                        
                        // ✅ 改進：由 Python 端通過回調發送失敗狀態
                        // await UpdateQueueItemAsync(...)
                    }
                    finally
                    {
                        _isProcessing = false;
                        _currentProcessingQueueId = null;
                    }
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "❌ 處理隊列項目時發生錯誤");
                _isProcessing = false;
            }
        }

        /// <summary>
        /// 發送請求到 Python Server
        /// </summary>
        private async Task<HttpResponseMessage> SendToPythonServerAsync(
            string pythonServerUrl,
            string queueItemId,
            object requestData,
            CancellationToken stoppingToken)
        {
            var endpoint = $"{pythonServerUrl}/api/tasks/process";

            // 配置超時
            var timeout = _configuration.GetValue<int>("ServiceUrls:RequestTimeout", 300);
            using (var cts = CancellationTokenSource.CreateLinkedTokenSource(stoppingToken))
            {
                cts.CancelAfter(TimeSpan.FromSeconds(timeout));

                _logger.LogInformation($"📤 發送請求到: {endpoint}");
                _logger.LogInformation($"📦 請求數據: {JsonConvert.SerializeObject(requestData)}");

                var response = await _httpClient.PostAsJsonAsync(
                    endpoint,
                    requestData,
                    cts.Token);

                return response;
            }
        }

        /// <summary>
        /// 更新隊列項目的狀態
        /// </summary>
        private async Task UpdateQueueItemAsync(
            string queueItemId,
            string status,
            DateTime? startedAt = null,
            DateTime? completedAt = null,
            string? errorMessage = null,
            VideoDbContext? dbContext = null)
        {
            using (var scope = _serviceProvider.CreateScope())
            {
                var context = dbContext ?? scope.ServiceProvider.GetRequiredService<VideoDbContext>();

                var queueItem = await context.ProcessQueueItems.FindAsync(queueItemId);
                if (queueItem != null)
                {
                    queueItem.Status = status;
                    if (startedAt.HasValue) queueItem.StartedAt = startedAt;
                    if (completedAt.HasValue) queueItem.CompletedAt = completedAt;

                    context.ProcessQueueItems.Update(queueItem);
                    await context.SaveChangesAsync();

                    _logger.LogInformation($"📝 更新隊列項目: {queueItemId}, 新狀態: {status}");
                }
            }
        }

        /// <summary>
        /// 增加重試計數
        /// </summary>
        private async Task IncrementRetryCountAsync(
            string queueItemId,
            string errorMessage,
            VideoDbContext? dbContext = null)
        {
            using (var scope = _serviceProvider.CreateScope())
            {
                var context = dbContext ?? scope.ServiceProvider.GetRequiredService<VideoDbContext>();

                var queueItem = await context.ProcessQueueItems.FindAsync(queueItemId);
                if (queueItem != null)
                {
                    queueItem.RetryCount++;

                    var maxRetries = _configuration.GetValue<int>("ServiceUrls:MaxRetries", 3);

                    if (queueItem.RetryCount >= maxRetries)
                    {
                        _logger.LogWarning(
                            $"⚠️  隊列項目 {queueItemId} 重試次數已達上限 ({queueItem.RetryCount}/{maxRetries})");
                        // queueItem.Status = "failed";
                    }
                    else
                    {
                        _logger.LogWarning(
                            $"🔄 隊列項目 {queueItemId} 將重試 ({queueItem.RetryCount}/{maxRetries})");
                        // queueItem.Status = "queued";  // 重新排隊
                    }

                    context.ProcessQueueItems.Update(queueItem);
                    await context.SaveChangesAsync();
                }
            }
        }
    }
}
