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
builder.Services.AddDbContext<VideoDbContext>(options =>
{
    if (connectionString != null)
    {
        options.UseMySql(connectionString, ServerVersion.AutoDetect(connectionString));
    }
    else
    {
        // 默認本地 MySQL 配置（如未配置連接字符串）
        var defaultConnection = "Server=localhost;Database=VideoSliceUploadDB;Uid=root;Pwd=;";
        options.UseMySql(defaultConnection, ServerVersion.AutoDetect(defaultConnection));
    }
});

// ============================================================
// 2. 服務層依賴注入
// ============================================================
builder.Services.AddScoped<AuthService>();
builder.Services.AddSingleton<B2Service>();
builder.Services.AddScoped<ShareService>();
builder.Services.AddScoped<UserService>();
builder.Services.AddSingleton<UploadServer.Services.ITokenBlacklistService, UploadServer.Services.TokenBlacklistService>();

// HTTP 客戶端工廠配置
builder.Services.AddHttpClient();

// 後台服務 - 排程器
builder.Services.AddHostedService<ShareCleanupService>();

// ============================================================
// 3. CORS 跨域配置
// ============================================================
builder.Services.AddCors(options =>
{
    options.AddDefaultPolicy(policy =>
        policy.AllowAnyOrigin().AllowAnyHeader().AllowAnyMethod());
});

// ============================================================
// 4. JWT 身份驗證配置
// ============================================================
var jwtSecret = builder.Configuration["Jwt:Secret"];
if (string.IsNullOrEmpty(jwtSecret))
{
    jwtSecret = "default-secret-key-please-change-in-production";
}

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
            ValidateIssuer = false,
            ValidateAudience = false,
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
}

app.UseHttpsRedirection();

app.UseCors();

// ============================================================
// 請求日誌 + 速率限制中間件
// ============================================================
app.UseMiddleware<RequestLoggingMiddleware>();
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

// ============================================================
// 11. 應用啟動
// ============================================================
logger.Info("════════════════════════════════════════════════════════════");
logger.Info("✅ TekSwing 高爾夫揮桿分析伺服器啟動");
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
