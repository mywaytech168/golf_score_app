using System.IdentityModel.Tokens.Jwt;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using NLog;
using NLog.Web;
using Swashbuckle.AspNetCore.SwaggerGen;
using UploadServer.Data;
using UploadServer.Middleware;
using UploadServer.Services;
using System.Text;
using System.Text.Json.Serialization;

// ============================================================
// NLog: 設置日誌記錄
// ============================================================
// 初始化 NLog - 確保日誌目錄存在
string logDir = Path.Combine(Directory.GetCurrentDirectory(), "logs");
if (!Directory.Exists(logDir))
{
    Directory.CreateDirectory(logDir);
}

// 加載 NLog 配置
var logger = NLog.LogManager.Setup().LoadConfigurationFromAppSettings().GetCurrentClassLogger();
logger.Debug("初始化日誌系統...");

LogManager.AutoShutdown = true;

try
{
    var builder = WebApplication.CreateBuilder(args);

    // IIS in-process 部署：請求體上限主要由 web.config requestLimits 控管，
    // [RequestSizeLimit] 屬性可再縮小。Kestrel 層保留 600MB 保底，
    // 避免脫離 IIS 直跑（docker/kestrel）時完全無上限。
    builder.WebHost.ConfigureKestrel(o =>
        o.Limits.MaxRequestBodySize = 600L * 1024 * 1024);

    // 使用 NLog 作為日誌提供程序
    builder.Logging.ClearProviders();  // 清除預設日誌提供者
    builder.Host.UseNLog();
    
    // 記錄應用啟動
    logger.Info("════════════════════════════════════════════════════════════");
    logger.Info("🚀 應用程序啟動初始化");
    logger.Info($"📂 當前目錄: {Directory.GetCurrentDirectory()}");
    logger.Info($"📂 日誌目錄: {logDir}");
    logger.Info($"🔧 環境: {builder.Environment.EnvironmentName}");
    logger.Info("════════════════════════════════════════════════════════════");

// ============================================================
// 1. EF Core DbContext 配置 (Code-First)
// ============================================================
var connectionString = builder.Configuration.GetConnectionString("DefaultConnection");
if (string.IsNullOrEmpty(connectionString))
    throw new InvalidOperationException("必須設定 ConnectionStrings:DefaultConnection");

builder.Services.AddDbContext<VideoDbContext>(options =>
    options.UseMySql(connectionString, ServerVersion.AutoDetect(connectionString)));

// ============================================================
// 2. 服務層依賴注入
// ============================================================
builder.Services.AddScoped<AuthService>();
builder.Services.AddSingleton<B2Service>();
builder.Services.AddScoped<ShareService>();
builder.Services.AddScoped<UserService>();
builder.Services.AddScoped<SubscriptionService>();
builder.Services.AddScoped<AppVersionService>();
builder.Services.AddScoped<AnnouncementService>();
builder.Services.AddSingleton<UploadServer.Services.ITokenBlacklistService, UploadServer.Services.TokenBlacklistService>();
builder.Services.AddScoped<UploadServer.Services.IEmailService, UploadServer.Services.SmtpEmailService>();

// HTTP 客戶端工廠配置
builder.Services.AddHttpClient();
builder.Services.AddHttpClient("gemini", c =>
{
    c.Timeout = TimeSpan.FromMinutes(5); // Gemini 影片分析可能較慢
});

// AI Coach 服務
builder.Services.AddSingleton<GeminiService>();
builder.Services.AddHostedService<AiCoachWorkerService>();

// 高爾夫揮桿 TCN 分析服務（Singleton：InferenceSession 執行緒安全且建立成本高）
builder.Services.AddSingleton<UploadServer.Services.GolfSwingAnalyzerService>();

// 球軌跡後端運算（Python worker subprocess）
builder.Services.AddSingleton<UploadServer.Services.BallTrajectoryPythonService>();
builder.Services.AddHostedService<UploadServer.Services.BallTrajectoryWorkerService>();

// 後台服務 - 排程器
builder.Services.AddHostedService<ShareCleanupService>();

// ============================================================
// 3. CORS 跨域配置
// ============================================================
// CORS：僅允許已知來源（mobile app 透過 scheme，管理後台透過 HTTPS）
builder.Services.AddCors(options =>
{
    options.AddPolicy("MobileApp", policy =>
        policy.WithOrigins(
                "https://orvia.com",
                "https://orvia.api.atk.tw",  // 管理後臺同站請求
                "http://localhost:3000"           // 本機開發用
            )
            .AllowAnyHeader()
            .AllowAnyMethod());
});

// ============================================================
// 4. JWT 身份驗證配置
// ============================================================
var jwtSecret = builder.Configuration["Jwt:Secret"];
if (string.IsNullOrEmpty(jwtSecret))
    throw new InvalidOperationException("必須設定 Jwt:Secret（建議 32 字元以上）");

builder.Services
    .AddAuthentication(options =>
    {
        options.DefaultAuthenticateScheme = "Bearer";
        options.DefaultChallengeScheme = "Bearer";
    })
    .AddJwtBearer(options =>
    {
        options.TokenValidationParameters = new Microsoft.IdentityModel.Tokens.TokenValidationParameters
        {
            ValidateIssuerSigningKey = true,
            IssuerSigningKey = new Microsoft.IdentityModel.Tokens.SymmetricSecurityKey(
                System.Text.Encoding.UTF8.GetBytes(jwtSecret)
            ),
            ValidateIssuer = true,
            ValidIssuers = new[] { builder.Configuration["Jwt:Issuer"]!, "GolfAdmin" },
            ValidateAudience = true,
            ValidAudiences = new[] { builder.Configuration["Jwt:Audience"]!, "GolfAdminUI" },
            ValidateLifetime = true,
            ClockSkew = System.TimeSpan.Zero,
        };
        options.Events = new JwtBearerEvents
        {
            OnTokenValidated = ctx =>
            {
                var blacklist = ctx.HttpContext.RequestServices
                    .GetRequiredService<UploadServer.Services.ITokenBlacklistService>();
                var jti = ctx.Principal?.FindFirst(JwtRegisteredClaimNames.Jti)?.Value;
                if (jti != null && blacklist.IsRevoked(jti))
                    ctx.Fail("Token has been revoked");
                return Task.CompletedTask;
            }
        };
    });

builder.Services.AddAuthorization();

    // ============================================================
    // 4. 控制器和 JSON 序列化配置
    // ============================================================
    builder.Services.AddControllers()
        .AddJsonOptions(options =>
        {
            options.JsonSerializerOptions.PropertyNamingPolicy = System.Text.Json.JsonNamingPolicy.CamelCase;
            options.JsonSerializerOptions.WriteIndented = true;
            options.JsonSerializerOptions.Converters.Add(new JsonStringEnumConverter());
        });

    // ============================================================
    // 5. API 文檔 (Swagger) - 可選
    // ============================================================
    builder.Services.AddEndpointsApiExplorer();
    builder.Services.AddSwaggerGen();

    // Health check：含 DB 連線探測，供 IIS/監控/load balancer 使用
    builder.Services.AddHealthChecks()
        .AddDbContextCheck<UploadServer.Data.VideoDbContext>("database");

    var app = builder.Build();

// ============================================================
// 6. 自動應用 EF Core Migration（Code-First）
// ============================================================
using (var scope = app.Services.CreateScope())
{
    var dbContext = scope.ServiceProvider.GetRequiredService<VideoDbContext>();
    
    // 應用所有待處理的遷移到資料庫
    try
    {
        dbContext.Database.Migrate();
        logger.Info("✅ 資料庫遷移已成功應用");
    }
    catch (Exception ex)
    {
        logger.Error(ex, "❌ 資料庫遷移失敗");
        throw;
    }
}

// ============================================================
// 7. HTTP 中間件配置
// ============================================================
if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();

    // 注入測試帳號（僅 Development）
    using var seedScope = app.Services.CreateScope();
    var seedDb     = seedScope.ServiceProvider.GetRequiredService<VideoDbContext>();
    var seedLogger = seedScope.ServiceProvider.GetRequiredService<ILogger<Program>>();
    await UploadServer.Data.TestDataSeeder.SeedAsync(seedDb, seedLogger);
}

app.UseHttpsRedirection();

// 提供 wwwroot 靜態檔案（包含管理後臺 /admin/ 與 APK 下載）
// 需額外註冊 .apk MIME 類型，否則靜態檔案中介層預設不服務未知副檔名
var contentTypeProvider = new Microsoft.AspNetCore.StaticFiles.FileExtensionContentTypeProvider();
contentTypeProvider.Mappings[".apk"] = "application/vnd.android.package-archive";
app.UseStaticFiles(new StaticFileOptions { ContentTypeProvider = contentTypeProvider });

// 安全 HTTP headers
app.Use(async (ctx, next) =>
{
    ctx.Response.Headers["X-Content-Type-Options"] = "nosniff";
    ctx.Response.Headers["X-Frame-Options"] = "DENY";
    ctx.Response.Headers["X-XSS-Protection"] = "1; mode=block";
    ctx.Response.Headers["Referrer-Policy"] = "strict-origin-when-cross-origin";
    ctx.Response.Headers["Permissions-Policy"] = "camera=(), microphone=(), geolocation=()";
    await next();
});

app.UseCors("MobileApp");

// ============================================================
// 請求日誌 + 速率限制中間件
// ============================================================
app.UseMiddleware<RequestLoggingMiddleware>();
app.UseMiddleware<IpRateLimitMiddleware>();
app.UseMiddleware<UserRateLimitMiddleware>();

// ============================================================
// JWT 身份驗證中間件
// ============================================================
app.UseAuthentication();
app.UseAuthorization();

// ============================================================
// 8. 路由映射
// ============================================================
app.MapControllers();
app.MapHealthChecks("/health");

// ============================================================
// 11. 應用啟動
// ============================================================
logger.Info("════════════════════════════════════════════════════════════");
logger.Info("✅ ORVIA 高爾夫揮桿分析伺服器啟動");
logger.Info("════════════════════════════════════════════════════════════");
logger.Info($"📊 數據庫: {(connectionString != null ? "已配置" : "使用默認本地配置")}");
logger.Info($"☁️  存儲: Backblaze B2");
logger.Info($"🔌 服務埠: https://localhost:5000");
logger.Info($"📚 API 文檔: https://localhost:5000/swagger");
logger.Info("════════════════════════════════════════════════════════════");

app.Run();
}
catch (Exception ex)
{
    logger.Error(ex, "❌ 應用程序啟動失敗");
    logger.Error($"錯誤信息: {ex.Message}");
    logger.Error($"堆棧跟蹤: {ex.StackTrace}");
    throw;
}
finally
{
    logger.Info("════════════════════════════════════════════════════════════");
    logger.Info("🛑 伺服器已停止");
    logger.Info("════════════════════════════════════════════════════════════");
    NLog.LogManager.Shutdown();
}
