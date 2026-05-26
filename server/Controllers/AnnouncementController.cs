using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using UploadServer.DTOs;
using UploadServer.Services;

namespace UploadServer.Controllers
{
    /// <summary>
    /// 公告欄 API
    ///   公開：GET  /api/announcements
    ///   管理：POST   /api/announcements/admin
    ///         PUT    /api/announcements/admin/{id}
    ///         DELETE /api/announcements/admin/{id}
    ///         GET    /api/announcements/admin        （全部，含未啟用）
    /// </summary>
    [ApiController]
    [Route("api/announcements")]
    public class AnnouncementController : ControllerBase
    {
        private readonly AnnouncementService _svc;
        private readonly IConfiguration _config;
        private readonly ILogger<AnnouncementController> _logger;

        public AnnouncementController(
            AnnouncementService svc,
            IConfiguration config,
            ILogger<AnnouncementController> logger)
        {
            _svc    = svc;
            _config = config;
            _logger = logger;
        }

        // ════════════════════════════════════════════════════════════════
        // 公開端點（App 端呼叫，Bearer token 可選）
        // ════════════════════════════════════════════════════════════════

        /// <summary>
        /// GET /api/announcements
        /// 回傳目前有效的公告列表（已發佈、未過期、isActive=true）。
        /// 不需登入即可存取。
        ///
        /// 回應：
        /// {
        ///   "data": [
        ///     {
        ///       "id": "...",
        ///       "title": "...",
        ///       "body": "...",
        ///       "type": "info",
        ///       "publishedAt": "2026-05-26T00:00:00Z",
        ///       "expiresAt": null,
        ///       "imageUrl": null
        ///     }
        ///   ]
        /// }
        /// </summary>
        [HttpGet]
        [AllowAnonymous]
        public async Task<IActionResult> GetAnnouncements()
        {
            try
            {
                var list = await _svc.GetActiveAsync();
                return Ok(new { data = list });
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "取得公告列表失敗");
                return StatusCode(500, new { message = "伺服器錯誤" });
            }
        }

        // ════════════════════════════════════════════════════════════════
        // 管理員端點（X-Admin-Key 或 Admin JWT）
        // ════════════════════════════════════════════════════════════════

        /// <summary>
        /// GET /api/announcements/admin
        /// 取得所有公告（含未啟用、未來發佈）。
        /// </summary>
        [HttpGet("admin")]
        public async Task<IActionResult> GetAllAdmin()
        {
            if (!IsAdmin()) return Unauthorized(new { message = "需要管理員權限" });
            try
            {
                var list = await _svc.GetAllAdminAsync();
                return Ok(new { data = list });
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "管理員取得公告列表失敗");
                return StatusCode(500, new { message = "伺服器錯誤" });
            }
        }

        /// <summary>
        /// POST /api/announcements/admin
        /// 建立新公告。
        ///
        /// Body：
        /// {
        ///   "title": "...",
        ///   "body": "...",
        ///   "type": "info",          // info | important | event | update
        ///   "publishedAt": null,     // null = 立即發佈
        ///   "expiresAt": null,
        ///   "imageUrl": null,
        ///   "isActive": true
        /// }
        /// </summary>
        [HttpPost("admin")]
        public async Task<IActionResult> Create([FromBody] UpsertAnnouncementRequest req)
        {
            if (!IsAdmin()) return Unauthorized(new { message = "需要管理員權限" });
            if (!ModelState.IsValid) return BadRequest(ModelState);
            try
            {
                var result = await _svc.CreateAsync(req);
                return CreatedAtAction(nameof(GetAnnouncements), new { }, new { data = result });
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "建立公告失敗");
                return StatusCode(500, new { message = "伺服器錯誤" });
            }
        }

        /// <summary>
        /// PUT /api/announcements/admin/{id}
        /// 更新公告內容。
        /// </summary>
        [HttpPut("admin/{id}")]
        public async Task<IActionResult> Update(string id, [FromBody] UpsertAnnouncementRequest req)
        {
            if (!IsAdmin()) return Unauthorized(new { message = "需要管理員權限" });
            if (!ModelState.IsValid) return BadRequest(ModelState);
            try
            {
                var result = await _svc.UpdateAsync(id, req);
                if (result == null) return NotFound(new { message = "公告不存在" });
                return Ok(new { data = result });
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "更新公告失敗 id={Id}", id);
                return StatusCode(500, new { message = "伺服器錯誤" });
            }
        }

        /// <summary>
        /// DELETE /api/announcements/admin/{id}
        /// 刪除公告（永久）。如需軟刪除請使用 PUT 將 isActive 設為 false。
        /// </summary>
        [HttpDelete("admin/{id}")]
        public async Task<IActionResult> Delete(string id)
        {
            if (!IsAdmin()) return Unauthorized(new { message = "需要管理員權限" });
            try
            {
                var ok = await _svc.DeleteAsync(id);
                if (!ok) return NotFound(new { message = "公告不存在" });
                return Ok(new { message = "已刪除" });
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "刪除公告失敗 id={Id}", id);
                return StatusCode(500, new { message = "伺服器錯誤" });
            }
        }

        // ── 認證輔助（與 AdminController 相同邏輯）────────────────────

        private bool IsAdmin()
        {
            if (Request.Headers.TryGetValue("X-Admin-Key", out var key))
                return key == _config["Admin:SecretKey"];

            if (Request.Headers.TryGetValue("Authorization", out var authHeader))
            {
                var token = authHeader.ToString().Replace("Bearer ", "").Trim();
                return ValidateAdminJwt(token);
            }
            return false;
        }

        private bool ValidateAdminJwt(string token)
        {
            try
            {
                var secret = _config["Admin:JwtSecret"] ?? _config["Jwt:Secret"] ?? "fallback-secret";
                var key    = new Microsoft.IdentityModel.Tokens.SymmetricSecurityKey(
                                 System.Text.Encoding.UTF8.GetBytes(secret));
                var handler = new System.IdentityModel.Tokens.Jwt.JwtSecurityTokenHandler();
                handler.ValidateToken(token, new Microsoft.IdentityModel.Tokens.TokenValidationParameters
                {
                    ValidateIssuerSigningKey = true,
                    IssuerSigningKey         = key,
                    ValidateIssuer           = false,
                    ValidateAudience         = false,
                    ClockSkew                = TimeSpan.Zero,
                }, out var validated);

                var jwt   = (System.IdentityModel.Tokens.Jwt.JwtSecurityToken)validated;
                var role  = jwt.Claims.FirstOrDefault(c => c.Type == "role")?.Value;
                return role == "admin";
            }
            catch
            {
                return false;
            }
        }
    }
}
