using System;
using System.Security.Claims;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Logging;

namespace UploadServer.Middleware
{
    /// <summary>
    /// 請求日誌中間件 (修復 3️⃣: 結構化日誌)
    /// </summary>
    public class RequestLoggingMiddleware
    {
        private readonly RequestDelegate _next;
        private readonly ILogger<RequestLoggingMiddleware> _logger;

        public RequestLoggingMiddleware(RequestDelegate next, ILogger<RequestLoggingMiddleware> logger)
        {
            _next = next;
            _logger = logger;
        }

        public async Task InvokeAsync(HttpContext context)
        {
            var request = context.Request;
            var userId = context.User.FindFirst(ClaimTypes.NameIdentifier)?.Value ?? "Anonymous";
            var ipAddress = context.Connection.RemoteIpAddress?.ToString() ?? "Unknown";

            var startTime = DateTime.UtcNow;

            // 只在 DEBUG 或詳細模式記錄請求詳情
            _logger.LogDebug(
                "API Request: {Method} {Path} | User: {UserId} | IP: {IP}",
                request.Method,
                request.Path,
                userId,
                ipAddress);

            try
            {
                await _next(context);

                var duration = DateTime.UtcNow - startTime;

                // 記錄響應
                var level = context.Response.StatusCode >= 500 
                    ? LogLevel.Error
                    : context.Response.StatusCode >= 400 
                        ? LogLevel.Warning
                        : LogLevel.Information;

                _logger.Log(
                    level,
                    "API Response: {Method} {Path} | Status: {Status} | Duration: {Duration}ms | User: {UserId}",
                    request.Method,
                    request.Path,
                    context.Response.StatusCode,
                    duration.TotalMilliseconds,
                    userId);
            }
            catch (Exception ex)
            {
                var duration = DateTime.UtcNow - startTime;
                _logger.LogError(
                    ex,
                    "API Error: {Method} {Path} | Duration: {Duration}ms | User: {UserId}",
                    request.Method,
                    request.Path,
                    duration.TotalMilliseconds,
                    userId);

                throw;
            }
        }
    }

    /// <summary>
    /// IP 層速率限制：針對 register / login 等公開端點防爆破
    /// </summary>
    public class IpRateLimitMiddleware
    {
        private readonly RequestDelegate _next;
        private readonly ILogger<IpRateLimitMiddleware> _logger;
        private readonly Dictionary<string, UserRateLimit> _ipLimits = new();
        private readonly object _lock = new();

        // path → (上限次數, 視窗分鐘)。重設密碼類端點更嚴格，防驗證碼爆破
        private static readonly Dictionary<string, (int Max, int WindowMin)> _protectedPaths =
            new(StringComparer.OrdinalIgnoreCase)
        {
            { "/api/auth/register",        (10, 15) },
            { "/api/auth/login",           (10, 15) },
            { "/api/auth/google-login",    (10, 15) },
            { "/api/auth/forgot-password", (5,  60) },
            { "/api/auth/reset-password",  (5,  60) },
            { "/api/contact",              (5,  60) },  // 聯絡表單防灌爆
        };

        public IpRateLimitMiddleware(RequestDelegate next, ILogger<IpRateLimitMiddleware> logger)
        {
            _next = next;
            _logger = logger;
        }

        public async Task InvokeAsync(HttpContext context)
        {
            var path = context.Request.Path.Value ?? "";
            if (_protectedPaths.TryGetValue(path, out var policy))
            {
                var ip = context.Connection.RemoteIpAddress?.ToString() ?? "unknown";
                var key = $"{ip}:{path}";

                UserRateLimit limit;
                lock (_lock)
                {
                    if (!_ipLimits.TryGetValue(key, out limit!))
                        _ipLimits[key] = limit = new UserRateLimit(policy.Max, policy.WindowMin);
                }

                if (limit.IsLimited())
                {
                    _logger.LogWarning("⚠️ IP {IP} 超過 auth 速率限制", ip);
                    context.Response.StatusCode = 429;
                    context.Response.ContentType = "application/json";
                    await context.Response.WriteAsync("{\"error\":\"請求過於頻繁，請稍後再試\"}");
                    return;
                }

                limit.IncrementRequest();
            }

            await _next(context);
        }
    }

    /// <summary>
    /// 用戶級別的速率限制中間件 (修復 7️⃣)
    /// </summary>
    public class UserRateLimitMiddleware
    {
        private readonly RequestDelegate _next;
        private readonly ILogger<UserRateLimitMiddleware> _logger;
        private readonly Dictionary<string, UserRateLimit> _userLimits;
        private readonly object _lockObject = new object();

        private const int MAX_REQUESTS_PER_HOUR = 1000;
        private const int WINDOW_MINUTES = 60;

        public UserRateLimitMiddleware(
            RequestDelegate next,
            ILogger<UserRateLimitMiddleware> logger)
        {
            _next = next;
            _logger = logger;
            _userLimits = new Dictionary<string, UserRateLimit>();
        }

        public async Task InvokeAsync(HttpContext context)
        {
            var userId = context.User.FindFirst(ClaimTypes.NameIdentifier)?.Value;

            // 對已驗證用戶施加速率限制
            if (!string.IsNullOrEmpty(userId))
            {
                lock (_lockObject)
                {
                    if (!_userLimits.ContainsKey(userId))
                    {
                        _userLimits[userId] = new UserRateLimit(
                            MAX_REQUESTS_PER_HOUR,
                            WINDOW_MINUTES);
                    }
                }

                var limit = _userLimits[userId];

                if (limit.IsLimited())
                {
                    _logger.LogWarning(
                        $"⚠️ 用戶 {userId} 超越速率限制 ({limit.RequestCount}/{limit.MaxRequests})");

                    context.Response.StatusCode = 429;
                    context.Response.ContentType = "application/json";
                    await context.Response.WriteAsync(
                        "{\"error\": \"用戶請求已超過限制，請稍後再試\"}");
                    return;
                }

                limit.IncrementRequest();

                // 添加速率限制信息到響應頭
                context.Response.Headers.Add("X-RateLimit-Limit", 
                    limit.MaxRequests.ToString());
                context.Response.Headers.Add("X-RateLimit-Remaining", 
                    (limit.MaxRequests - limit.RequestCount).ToString());
                context.Response.Headers.Add("X-RateLimit-Reset", 
                    ((long)limit.ResetTime.ToUniversalTime()
                        .Subtract(new DateTime(1970, 1, 1)).TotalSeconds).ToString());
            }

            await _next(context);
        }
    }

    /// <summary>
    /// 用戶速率限制追蹤類
    /// </summary>
    public class UserRateLimit
    {
        private int _requestCount;
        private DateTime _windowStart;
        public int MaxRequests { get; }
        public int WindowMinutes { get; }

        public int RequestCount => _requestCount;
        public DateTime ResetTime => _windowStart.AddMinutes(WindowMinutes);

        public UserRateLimit(int maxRequests, int windowMinutes)
        {
            MaxRequests = maxRequests;
            WindowMinutes = windowMinutes;
            _windowStart = DateTime.UtcNow;
            _requestCount = 0;
        }

        public bool IsLimited()
        {
            RefreshWindow();
            return _requestCount >= MaxRequests;
        }

        public void IncrementRequest()
        {
            RefreshWindow();
            _requestCount++;
        }

        private void RefreshWindow()
        {
            var now = DateTime.UtcNow;
            if ((now - _windowStart).TotalMinutes >= WindowMinutes)
            {
                _windowStart = now;
                _requestCount = 0;
            }
        }
    }
}
