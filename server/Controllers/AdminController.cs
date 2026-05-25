using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using UploadServer.Data;
using UploadServer.DTOs;
using UploadServer.Services;

namespace UploadServer.Controllers
{
    /// <summary>
    /// 管理員專用 API（需 X-Admin-Key 標頭）
    /// </summary>
    [ApiController]
    [Route("api/admin")]
    public class AdminController : ControllerBase
    {
        private readonly VideoDbContext _db;
        private readonly IConfiguration _config;
        private readonly ILogger<AdminController> _logger;
        private readonly AppVersionService _versionService;

        public AdminController(
            VideoDbContext db,
            IConfiguration config,
            ILogger<AdminController> logger,
            AppVersionService versionService)
        {
            _db             = db;
            _config         = config;
            _logger         = logger;
            _versionService = versionService;
        }

        private bool IsAdmin() =>
            Request.Headers.TryGetValue("X-Admin-Key", out var key) &&
            key == _config["Admin:SecretKey"];

        /// <summary>
        /// GET /api/admin/feedbacks — 查看用戶回饋列表
        /// Query: page (預設1), size (預設50), type (bug|feature|other，可省略)
        /// </summary>
        [HttpGet("feedbacks")]
        public async Task<IActionResult> GetFeedbacks(
            [FromQuery] int page = 1,
            [FromQuery] int size = 50,
            [FromQuery] string? type = null)
        {
            if (!IsAdmin())
                return StatusCode(403, new { message = "需要管理員權限" });

            page = Math.Max(1, page);
            size = Math.Clamp(size, 1, 200);

            var query = _db.UserFeedbacks.AsQueryable();
            if (!string.IsNullOrEmpty(type))
                query = query.Where(f => f.Type == type);

            var total = await query.CountAsync();
            var items = await query
                .OrderByDescending(f => f.CreatedAt)
                .Skip((page - 1) * size)
                .Take(size)
                .Select(f => new
                {
                    f.Id,
                    f.UserId,
                    f.Type,
                    f.Text,
                    CreatedAt = f.CreatedAt.ToString("yyyy-MM-dd HH:mm:ss"),
                })
                .ToListAsync();

            _logger.LogInformation("管理員查看回饋: page={Page} size={Size} total={Total}", page, size, total);
            return Ok(new { total, page, size, data = items });
        }

        /// <summary>
        /// GET /api/admin/users — 查看用戶列表（含方案與球數統計）
        /// Query: page, size
        /// </summary>
        [HttpGet("users")]
        public async Task<IActionResult> GetUsers([FromQuery] int page = 1, [FromQuery] int size = 50)
        {
            if (!IsAdmin())
                return StatusCode(403, new { message = "需要管理員權限" });

            page = Math.Max(1, page);
            size = Math.Clamp(size, 1, 200);

            var total = await _db.Users.CountAsync();
            var items = await _db.Users
                .OrderByDescending(u => u.CreatedAt)
                .Skip((page - 1) * size)
                .Take(size)
                .Select(u => new
                {
                    u.Id,
                    u.Username,
                    u.Email,
                    u.Plan,
                    u.BonusBalls,
                    u.TodayUsed,
                    u.InviteCount,
                    Providers = u.UserAuths.Select(a => a.Provider).ToList(),
                    u.Status,
                    CreatedAt = u.CreatedAt.ToString("yyyy-MM-dd HH:mm:ss"),
                })
                .ToListAsync();

            return Ok(new { total, page, size, data = items });
        }

        // ════════════════════════════════════════════════════════════════
        // App 版本管理
        // ════════════════════════════════════════════════════════════════

        /// <summary>
        /// GET /api/admin/app/versions — 查看所有平台的版本設定
        /// </summary>
        [HttpGet("app/versions")]
        public async Task<IActionResult> GetAppVersions()
        {
            if (!IsAdmin())
                return StatusCode(403, new { message = "需要管理員權限" });

            var versions = await _versionService.GetAllAsync();
            var data = versions.Select(v => new
            {
                v.Id,
                v.Platform,
                v.LatestVersion,
                v.MinRequiredVersion,
                v.ForceUpdate,
                v.UpdateUrl,
                v.ReleaseNotesJson,
                v.ReleaseDate,
                UpdatedAt = v.UpdatedAt.ToString("yyyy-MM-dd HH:mm:ss"),
            });

            return Ok(new { data });
        }

        /// <summary>
        /// PUT /api/admin/app/version/{platform} — 建立或更新版本設定
        ///
        /// Path: platform = android | ios
        ///
        /// Body:
        /// {
        ///   "latestVersion": "1.2.0",
        ///   "minRequiredVersion": "1.0.0",
        ///   "forceUpdate": false,
        ///   "updateUrl": "https://play.google.com/...",
        ///   "releaseNotes": ["修正 A", "新增 B"],
        ///   "releaseDate": "2026-05-25"
        /// }
        /// </summary>
        [HttpPut("app/version/{platform}")]
        public async Task<IActionResult> UpsertAppVersion(
            string platform,
            [FromBody] UpdateAppVersionRequest req)
        {
            if (!IsAdmin())
                return StatusCode(403, new { message = "需要管理員權限" });

            if (platform != "android" && platform != "ios")
                return BadRequest(new { message = "platform 必須為 android 或 ios" });

            if (string.IsNullOrWhiteSpace(req.LatestVersion) ||
                string.IsNullOrWhiteSpace(req.MinRequiredVersion))
                return BadRequest(new { message = "latestVersion 與 minRequiredVersion 為必填" });

            try
            {
                var record = await _versionService.UpsertVersionAsync(platform, req);
                _logger.LogInformation("管理員更新版本設定 platform={Platform} latest={Latest}",
                    platform, record.LatestVersion);

                return Ok(new
                {
                    message = $"版本設定已更新（{platform}）",
                    data = new
                    {
                        record.Platform,
                        record.LatestVersion,
                        record.MinRequiredVersion,
                        record.ForceUpdate,
                        record.UpdateUrl,
                        record.ReleaseDate,
                        UpdatedAt = record.UpdatedAt.ToString("yyyy-MM-dd HH:mm:ss"),
                    }
                });
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "更新版本設定失敗 platform={Platform}", platform);
                return StatusCode(500, new { message = "伺服器錯誤" });
            }
        }
    }
}
