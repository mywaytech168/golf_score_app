using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
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
        private readonly B2Service _b2;
        private readonly IWebHostEnvironment _env;

        public AdminController(
            VideoDbContext db,
            IConfiguration config,
            ILogger<AdminController> logger,
            AppVersionService versionService,
            B2Service b2,
            IWebHostEnvironment env)
        {
            _db             = db;
            _config         = config;
            _logger         = logger;
            _versionService = versionService;
            _b2             = b2;
            _env            = env;
        }

        // ── 認證輔助 ──────────────────────────────────────────────

        private bool IsAdmin()
        {
            // 支援兩種方式：Bearer JWT（登入後）或 X-Admin-Key（舊相容）
            if (Request.Headers.TryGetValue("Authorization", out var authHeader))
            {
                var token = authHeader.ToString().Replace("Bearer ", "").Trim();
                if (ValidateAdminJwt(token)) return true;
            }
            if (Request.Headers.TryGetValue("X-Admin-Key", out var key))
                return key == _config["Admin:SecretKey"];
            return false;
        }

        private bool ValidateAdminJwt(string token)
        {
            try
            {
                var secret  = _config["Admin:JwtSecret"] ?? _config["Jwt:Secret"] ?? "fallback-secret";
                var handler = new JwtSecurityTokenHandler();
                handler.ValidateToken(token, new TokenValidationParameters
                {
                    ValidateIssuerSigningKey = true,
                    IssuerSigningKey         = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(secret)),
                    ValidateIssuer           = true,
                    ValidIssuer              = "GolfAdmin",
                    ValidateAudience         = true,
                    ValidAudience            = "GolfAdminUI",
                    ClockSkew                = TimeSpan.Zero,
                }, out _);
                return true;
            }
            catch { return false; }
        }

        // ════════════════════════════════════════════════════════════════
        // 登入
        // ════════════════════════════════════════════════════════════════

        /// <summary>
        /// POST /api/admin/login — 管理員帳密登入，回傳 JWT
        /// Body: { "username": "admin", "password": "admin" }
        /// </summary>
        [HttpPost("login")]
        public IActionResult Login([FromBody] AdminLoginRequest req)
        {
            var expectedUser = _config["Admin:Username"] ?? "admin";
            var expectedPass = _config["Admin:Password"] ?? "admin";

            if (req.Username != expectedUser || req.Password != expectedPass)
            {
                _logger.LogWarning("管理員登入失敗: username={Username}", req.Username);
                return StatusCode(401, new { message = "帳號或密碼錯誤" });
            }

            var secret  = _config["Admin:JwtSecret"] ?? _config["Jwt:Secret"] ?? "fallback-secret";
            var key     = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(secret));
            var creds   = new SigningCredentials(key, SecurityAlgorithms.HmacSha256);
            var expires = DateTime.UtcNow.AddHours(8);

            var jwt = new JwtSecurityToken(
                issuer:             "GolfAdmin",
                audience:           "GolfAdminUI",
                claims:             [new Claim("role", "admin")],
                expires:            expires,
                signingCredentials: creds
            );
            var tokenStr = new JwtSecurityTokenHandler().WriteToken(jwt);

            _logger.LogInformation("管理員登入成功: {Username}", req.Username);
            return Ok(new { token = tokenStr, expiresAt = expires.ToString("yyyy-MM-ddTHH:mm:ssZ") });
        }

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
                    f.AttachedVideoId,
                    HasImage      = f.AttachedImageB2Key != null,
                    f.AdminReply,
                    AdminRepliedAt = f.AdminRepliedAt.HasValue
                                     ? f.AdminRepliedAt.Value.ToString("yyyy-MM-dd HH:mm:ss")
                                     : (string?)null,
                    CreatedAt = f.CreatedAt.ToString("yyyy-MM-dd HH:mm:ss"),
                })
                .ToListAsync();

            _logger.LogInformation("管理員查看回饋: page={Page} size={Size} total={Total}", page, size, total);
            return Ok(new { total, page, size, data = items });
        }

        /// <summary>
        /// GET /api/admin/feedbacks/{id}/image — 取得回饋圖片的臨時下載 URL
        /// </summary>
        [HttpGet("feedbacks/{id}/image")]
        public async Task<IActionResult> GetFeedbackImageUrl(string id)
        {
            if (!IsAdmin())
                return StatusCode(403, new { message = "需要管理員權限" });

            var feedback = await _db.UserFeedbacks.FindAsync(id);
            if (feedback == null)
                return NotFound(new { message = "回饋不存在" });

            if (string.IsNullOrEmpty(feedback.AttachedImageB2Key))
                return NotFound(new { message = "此回饋無附加圖片" });

            var url = _b2.GenerateFeedbackImageDownloadUrl(feedback.AttachedImageB2Key);
            return Ok(new { data = new { url } });
        }

        /// <summary>
        /// GET /api/admin/users — 查看用戶列表（含方案與球數統計）
        /// Query: page, size
        /// </summary>
        [HttpGet("users")]
        public async Task<IActionResult> GetUsers(
            [FromQuery] int page = 1,
            [FromQuery] int size = 50,
            [FromQuery] string? search = null)
        {
            if (!IsAdmin())
                return StatusCode(403, new { message = "需要管理員權限" });

            page = Math.Max(1, page);
            size = Math.Clamp(size, 1, 200);

            var query = _db.Users.AsQueryable();
            if (!string.IsNullOrEmpty(search))
                query = query.Where(u => u.Email.Contains(search) || u.Username.Contains(search));

            var total = await query.CountAsync();
            var items = await query
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

        // ════════════════════════════════════════════════════════════════
        // AI 分析記錄
        // ════════════════════════════════════════════════════════════════

        /// <summary>
        /// GET /api/admin/analyses — 查看所有 AI 分析記錄
        /// Query: page, size, status (pending|queued|processing|completed|failed)
        /// </summary>
        [HttpGet("analyses")]
        public async Task<IActionResult> GetAnalyses(
            [FromQuery] int page     = 1,
            [FromQuery] int size     = 50,
            [FromQuery] string? status = null,
            [FromQuery] string? userId = null)
        {
            if (!IsAdmin()) return StatusCode(403, new { message = "需要管理員權限" });

            page = Math.Max(1, page);
            size = Math.Clamp(size, 1, 200);

            var query = _db.AiCoachAnalyses.AsQueryable();
            if (!string.IsNullOrEmpty(status)) query = query.Where(a => a.Status == status);
            if (!string.IsNullOrEmpty(userId)) query = query.Where(a => a.UserId == userId);

            var total = await query.CountAsync();
            var items = await query
                .OrderByDescending(a => a.CreatedAt)
                .Skip((page - 1) * size)
                .Take(size)
                .Select(a => new
                {
                    a.Id,
                    a.UserId,
                    a.VideoId,
                    a.Status,
                    a.ErrorTypeHint,
                    a.Severity,
                    a.Summary,
                    a.RetryCount,
                    HasResult      = a.ResultJson != null,
                    HasOnnxResult  = a.OnnxResultJson != null,
                    CreatedAt      = a.CreatedAt.ToString("yyyy-MM-dd HH:mm:ss"),
                    CompletedAt    = a.CompletedAt.HasValue
                                     ? a.CompletedAt.Value.ToString("yyyy-MM-dd HH:mm:ss")
                                     : (string?)null,
                })
                .ToListAsync();

            return Ok(new { total, page, size, data = items });
        }

        // ════════════════════════════════════════════════════════════════
        // 球數流水帳
        // ════════════════════════════════════════════════════════════════

        /// <summary>
        /// GET /api/admin/ball-records — 查看球數流水帳
        /// Query: page, size, userId, reason
        /// </summary>
        [HttpGet("ball-records")]
        public async Task<IActionResult> GetBallRecords(
            [FromQuery] int page      = 1,
            [FromQuery] int size      = 50,
            [FromQuery] string? userId = null,
            [FromQuery] string? reason = null)
        {
            if (!IsAdmin()) return StatusCode(403, new { message = "需要管理員權限" });

            page = Math.Max(1, page);
            size = Math.Clamp(size, 1, 200);

            var query = _db.BallRecords.AsQueryable();
            if (!string.IsNullOrEmpty(userId)) query = query.Where(b => b.UserId == userId);
            if (!string.IsNullOrEmpty(reason)) query = query.Where(b => b.Reason == reason);

            var total = await query.CountAsync();
            var items = await query
                .OrderByDescending(b => b.CreatedAt)
                .Skip((page - 1) * size)
                .Take(size)
                .Select(b => new
                {
                    b.Id,
                    b.UserId,
                    b.Reason,
                    b.Delta,
                    b.BalanceAfter,
                    b.RefId,
                    CreatedAt = b.CreatedAt.ToString("yyyy-MM-dd HH:mm:ss"),
                })
                .ToListAsync();

            return Ok(new { total, page, size, data = items });
        }

        // ════════════════════════════════════════════════════════════════
        // 用戶球數調整
        // ════════════════════════════════════════════════════════════════

        /// <summary>
        /// POST /api/admin/users/{id}/balls — 手動調整某用戶球數
        /// Body: { "delta": 10, "reason": "manual" }
        /// </summary>
        [HttpPost("users/{id}/balls")]
        public async Task<IActionResult> AdjustUserBalls(string id, [FromBody] AdminAdjustBallsRequest req)
        {
            if (!IsAdmin()) return StatusCode(403, new { message = "需要管理員權限" });
            if (req.Delta == 0) return BadRequest(new { message = "delta 不可為 0" });

            var user = await _db.Users.FindAsync(id);
            if (user == null) return NotFound(new { message = "用戶不存在" });

            user.BonusBalls = Math.Max(0, user.BonusBalls + req.Delta);
            user.UpdatedAt  = DateTime.UtcNow;

            _db.BallRecords.Add(new Models.BallRecord
            {
                UserId       = id,
                Reason       = "manual",
                Delta        = req.Delta,
                BalanceAfter = user.BonusBalls,
                RefId        = null,
            });

            await _db.SaveChangesAsync();

            _logger.LogInformation("管理員調整球數 userId={UserId} delta={Delta} balance={Balance}",
                id, req.Delta, user.BonusBalls);

            return Ok(new { message = "球數已調整", userId = id, delta = req.Delta, bonusBalls = user.BonusBalls });
        }

        // ════════════════════════════════════════════════════════════════
        // 管理員回覆 Feedback
        // ════════════════════════════════════════════════════════════════

        /// <summary>
        /// POST /api/admin/feedbacks/{id}/reply — 管理員回覆用戶回饋
        /// Body: { "reply": "感謝您的回饋..." }
        /// </summary>
        [HttpPost("feedbacks/{id}/reply")]
        public async Task<IActionResult> ReplyFeedback(string id, [FromBody] AdminFeedbackReplyRequest req)
        {
            if (!IsAdmin()) return StatusCode(403, new { message = "需要管理員權限" });
            if (string.IsNullOrWhiteSpace(req.Reply)) return BadRequest(new { message = "回覆內容不可為空" });

            var feedback = await _db.UserFeedbacks.FindAsync(id);
            if (feedback == null) return NotFound(new { message = "回饋不存在" });

            feedback.AdminReply     = req.Reply.Trim();
            feedback.AdminRepliedAt = DateTime.UtcNow;
            await _db.SaveChangesAsync();

            _logger.LogInformation("管理員回覆 Feedback id={Id}", id);
            return Ok(new { message = "回覆已儲存", feedbackId = id });
        }

        // ════════════════════════════════════════════════════════════════
        // 資料上傳審核（上傳獎勵審核制）
        // ════════════════════════════════════════════════════════════════

        /// <summary>
        /// GET /api/admin/dataset-uploads — 資料上傳審核列表
        /// Query: status (pending|approved|rejected，預設 pending)、page、pageSize
        /// </summary>
        [HttpGet("dataset-uploads")]
        public async Task<IActionResult> GetDatasetUploads(
            [FromQuery] string status = "pending",
            [FromQuery] int page = 1,
            [FromQuery] int pageSize = 50)
        {
            if (!IsAdmin())
                return StatusCode(403, new { message = "需要管理員權限" });

            page     = Math.Max(1, page);
            pageSize = Math.Clamp(pageSize, 1, 200);

            var query = _db.DatasetUploads.AsQueryable();
            if (!string.IsNullOrEmpty(status) && status != "all")
                query = query.Where(d => d.Status == status);

            var total = await query.CountAsync();
            var rows = await query
                .OrderByDescending(d => d.CreatedAt)
                .Skip((page - 1) * pageSize)
                .Take(pageSize)
                .Join(_db.Users,
                    d => d.UserId,
                    u => u.Id,
                    (d, u) => new
                    {
                        d.Id,
                        d.UserId,
                        Username    = u.Username,
                        DisplayName = u.DisplayName,
                        d.ClientFilePath,
                        d.DurationSeconds,
                        d.GoodShot,
                        d.VideoType,
                        d.Status,
                        d.ReviewNote,
                        d.B2VideoKey,
                        d.B2CsvKey,
                        d.CreatedAt,
                        d.ReviewedAt,
                    })
                .ToListAsync();

            var items = rows.Select(d => new
            {
                d.Id,
                d.UserId,
                d.Username,
                d.DisplayName,
                d.ClientFilePath,
                d.DurationSeconds,
                d.GoodShot,
                d.VideoType,
                d.Status,
                d.ReviewNote,
                VideoDownloadUrl = d.B2VideoKey != null
                                   ? _b2.GenerateDownloadUrlForKey(d.B2VideoKey, 60)
                                   : null,
                CsvDownloadUrl   = d.B2CsvKey != null
                                   ? _b2.GenerateDownloadUrlForKey(d.B2CsvKey, 60)
                                   : null,
                CreatedAt  = d.CreatedAt.ToString("yyyy-MM-dd HH:mm:ss"),
                ReviewedAt = d.ReviewedAt.HasValue
                             ? d.ReviewedAt.Value.ToString("yyyy-MM-dd HH:mm:ss")
                             : null,
            });

            return Ok(new { total, page, pageSize, data = items });
        }

        /// <summary>
        /// POST /api/admin/dataset-uploads/{id}/review — 審核資料上傳
        /// Body: { "approve": true|false, "note": "..." }
        /// 核准 → 發 +3 球（僅一次）；已審核過回 409 防重複發球
        /// </summary>
        [HttpPost("dataset-uploads/{id}/review")]
        public async Task<IActionResult> ReviewDatasetUpload(
            string id, [FromBody] AdminDatasetReviewRequest req,
            [FromServices] UserService userService)
        {
            if (!IsAdmin()) return StatusCode(403, new { message = "需要管理員權限" });

            var (found, reviewed) = await userService.ReviewDatasetUploadAsync(id, req.Approve, req.Note);
            if (!found)    return NotFound(new { message = "上傳紀錄不存在" });
            if (!reviewed) return Conflict(new { message = "此筆已審核過，不可重複審核" });

            return Ok(new
            {
                message  = req.Approve ? "已核准並發放獎勵" : "已拒絕",
                uploadId = id,
                status   = req.Approve ? "approved" : "rejected",
            });
        }

        // ════════════════════════════════════════════════════════════════
        // APK 自託管上傳 / 刪除
        // ════════════════════════════════════════════════════════════════

        private string ApksDir => Path.Combine(_env.WebRootPath, "apks");
        private string BaseUrl  => (_config["App:BaseUrl"] ?? "https://orvia.api.atk.tw").TrimEnd('/');

        /// <summary>
        /// POST /api/admin/app/version/android/apk
        /// Content-Type: multipart/form-data  (field name: "file")
        /// 
        /// 上傳 APK 至 wwwroot/apks/，並自動更新 android 版本的 UpdateUrl。
        /// 回應: { message, fileName, downloadUrl, sizeKb }
        /// </summary>
        [HttpPost("app/version/android/apk")]
        [RequestSizeLimit(500 * 1024 * 1024)]                        // 整體請求上限 500 MB
        [RequestFormLimits(MultipartBodyLengthLimit = 500 * 1024 * 1024)]  // multipart 單段上限（預設僅 128 MB）
        public async Task<IActionResult> UploadApk(IFormFile file)
        {
            if (!IsAdmin()) return StatusCode(403, new { message = "需要管理員權限" });

            if (file == null || file.Length == 0)
                return BadRequest(new { message = "未收到檔案" });

            var ext = Path.GetExtension(file.FileName).ToLowerInvariant();
            if (ext != ".apk")
                return BadRequest(new { message = "只接受 .apk 檔案" });

            var maxMb = _config.GetValue<int>("App:ApkMaxMb", 200);
            if (file.Length > maxMb * 1024L * 1024L)
                return BadRequest(new { message = $"檔案超過 {maxMb} MB 上限" });

            // 取得 android 版本號，用於命名
            var record = await _db.AppVersions.FirstOrDefaultAsync(v => v.Platform == "android");
            var version = record?.LatestVersion ?? "unknown";

            // 安全化版本號（只保留字母、數字、點）
            var safeVersion = System.Text.RegularExpressions.Regex.Replace(version, @"[^\w\.]", "");
            var fileName    = $"android-{safeVersion}.apk";

            Directory.CreateDirectory(ApksDir);

            // 寫入版本檔 + 覆蓋 latest
            var versionedPath = Path.Combine(ApksDir, fileName);
            var latestPath    = Path.Combine(ApksDir, "android-latest.apk");

            try
            {
                await using (var stream = System.IO.File.Create(versionedPath))
                    await file.CopyToAsync(stream);

                System.IO.File.Copy(versionedPath, latestPath, overwrite: true);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "APK 寫入失敗 path={Path}", versionedPath);
                return StatusCode(500, new { message = $"APK 寫入失敗：{ex.Message}" });
            }

            // 更新 AppVersion.UpdateUrl & ApkFileName（若記錄不存在則自動建立）
            var downloadUrl = $"{BaseUrl}/apks/{fileName}";
            if (record != null)
            {
                record.UpdateUrl   = downloadUrl;
                record.ApkFileName = fileName;
                record.UpdatedAt   = DateTime.UtcNow;
            }
            else
            {
                _db.AppVersions.Add(new Models.AppVersion
                {
                    Platform           = "android",
                    LatestVersion      = version == "unknown" ? "1.0.0" : version,
                    MinRequiredVersion = "1.0.0",
                    UpdateUrl          = downloadUrl,
                    ApkFileName        = fileName,
                    UpdatedAt          = DateTime.UtcNow,
                });
            }
            await _db.SaveChangesAsync();

            _logger.LogInformation("管理員上傳 APK: {File} size={Size}KB", fileName, file.Length / 1024);

            return Ok(new
            {
                message     = "APK 上傳成功",
                fileName,
                downloadUrl,
                latestUrl   = $"{BaseUrl}/apks/android-latest.apk",
                sizeKb      = file.Length / 1024,
            });
        }

        /// <summary>
        /// GET /api/admin/app/version/android/apk — 查詢目前伺服器上的 APK 狀態
        /// </summary>
        [HttpGet("app/version/android/apk")]
        public async Task<IActionResult> GetApkInfo()
        {
            if (!IsAdmin()) return StatusCode(403, new { message = "需要管理員權限" });

            var record = await _db.AppVersions.AsNoTracking()
                            .FirstOrDefaultAsync(v => v.Platform == "android");

            if (record?.ApkFileName == null)
                return Ok(new { exists = false });

            var filePath = Path.Combine(ApksDir, record.ApkFileName);
            var exists   = System.IO.File.Exists(filePath);
            var sizeKb   = exists ? (long?)new FileInfo(filePath).Length / 1024 : null;

            return Ok(new
            {
                exists,
                fileName    = record.ApkFileName,
                downloadUrl = $"{BaseUrl}/apks/{record.ApkFileName}",
                latestUrl   = $"{BaseUrl}/apks/android-latest.apk",
                sizeKb,
                updatedAt   = record.UpdatedAt.ToString("yyyy-MM-dd HH:mm:ss"),
            });
        }

        /// <summary>
        /// DELETE /api/admin/app/version/android/apk — 刪除伺服器上的 APK 檔案
        /// </summary>
        [HttpDelete("app/version/android/apk")]
        public async Task<IActionResult> DeleteApk()
        {
            if (!IsAdmin()) return StatusCode(403, new { message = "需要管理員權限" });

            var record = await _db.AppVersions.FirstOrDefaultAsync(v => v.Platform == "android");

            if (record?.ApkFileName != null)
            {
                var path = Path.Combine(ApksDir, record.ApkFileName);
                if (System.IO.File.Exists(path)) System.IO.File.Delete(path);

                var latest = Path.Combine(ApksDir, "android-latest.apk");
                if (System.IO.File.Exists(latest)) System.IO.File.Delete(latest);

                record.ApkFileName = null;
                record.UpdateUrl   = string.Empty;
                record.UpdatedAt   = DateTime.UtcNow;
                await _db.SaveChangesAsync();
            }

            _logger.LogInformation("管理員刪除 APK");
            return Ok(new { message = "APK 已刪除" });
        }
    }
}
