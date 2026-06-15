using System.Security.Claims;
using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using UploadServer.Data;
using UploadServer.DTOs;
using UploadServer.Models;
using UploadServer.Services;

namespace UploadServer.Controllers
{
    /// <summary>
    /// 聯絡我們表單（公開端點，App 與官網共用）。
    /// 寫入 contact_messages 表，並轉寄客服信箱（support@atk.tw）。
    /// 速率限制由 IpRateLimitMiddleware 對 /api/contact 套用。
    /// </summary>
    [ApiController]
    [Route("api/contact")]
    public class ContactController : ControllerBase
    {
        private readonly VideoDbContext _db;
        private readonly IEmailService _email;
        private readonly ILogger<ContactController> _logger;
        private readonly IHttpClientFactory _httpFactory;
        private readonly IConfiguration _config;

        private const string TurnstileVerifyUrl =
            "https://challenges.cloudflare.com/turnstile/v0/siteverify";

        private static readonly Regex EmailRegex =
            new(@"^[^@\s]+@[^@\s]+\.[^@\s]+$", RegexOptions.Compiled);

        public ContactController(
            VideoDbContext db, IEmailService email, ILogger<ContactController> logger,
            IHttpClientFactory httpFactory, IConfiguration config)
        {
            _db          = db;
            _email       = email;
            _logger      = logger;
            _httpFactory = httpFactory;
            _config      = config;
        }

        /// <summary>
        /// POST /api/contact — 提交聯絡表單（匿名可送；登入則自動帶 UserId）
        /// Body: { name?, email, subject?, message, source? }
        /// </summary>
        [HttpPost]
        [AllowAnonymous]
        public async Task<IActionResult> Submit([FromBody] ContactMessageRequest req)
        {
            if (req == null)
                return BadRequest(new ContactMessageResponse(false, "請求格式錯誤"));

            var email   = req.Email?.Trim() ?? "";
            var message = req.Message?.Trim() ?? "";

            if (string.IsNullOrWhiteSpace(email) || !EmailRegex.IsMatch(email) || email.Length > 255)
                return BadRequest(new ContactMessageResponse(false, "請填寫有效的 Email"));

            if (string.IsNullOrWhiteSpace(message))
                return BadRequest(new ContactMessageResponse(false, "訊息內容不得為空"));
            if (message.Length > 5000)
                return BadRequest(new ContactMessageResponse(false, "訊息內容過長（上限 5000 字）"));

            var source = req.Source == "app" ? "app" : "web";

            // Cloudflare Turnstile 人機驗證：僅官網（web）來源，且已設定 SecretKey 時強制。
            // App 來源走平台級裝置驗證（Play Integrity / App Attest），不需 Turnstile。
            // SecretKey 未設定時整段略過 → 部署金鑰前表單照常可用。
            var turnstileSecret = _config["Turnstile:SecretKey"];
            if (source == "web" && !string.IsNullOrWhiteSpace(turnstileSecret))
            {
                var passed = await VerifyTurnstileAsync(turnstileSecret, req.Turnstile);
                if (!passed)
                    return BadRequest(new ContactMessageResponse(false, "人機驗證失敗，請重新驗證後再送出"));
            }

            var name   = string.IsNullOrWhiteSpace(req.Name) ? null : req.Name.Trim();
            if (name?.Length > 100) name = name[..100];
            var subject = string.IsNullOrWhiteSpace(req.Subject) ? null : req.Subject.Trim();
            if (subject?.Length > 200) subject = subject[..200];

            // 若帶有有效 JWT，記錄 UserId（匿名則為 null）
            var userId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;

            var entity = new ContactMessage
            {
                Id        = Guid.NewGuid().ToString(),
                Source    = source,
                Name      = name,
                Email     = email,
                Subject   = subject,
                Message   = message,
                UserId    = string.IsNullOrWhiteSpace(userId) ? null : userId,
                CreatedAt = DateTime.UtcNow,
            };

            _db.ContactMessages.Add(entity);
            await _db.SaveChangesAsync();
            _logger.LogInformation("收到聯絡表單 {Id}（來源 {Source}, email {Email}）", entity.Id, source, email);

            // 轉寄客服信箱：失敗不影響表單已成功寫入 DB
            try
            {
                await _email.SendContactNotificationAsync(source, name, email, subject, message);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "聯絡表單 {Id} 轉寄客服信箱失敗（已存 DB，可於後台查看）", entity.Id);
            }

            return Ok(new ContactMessageResponse(true, "已收到您的訊息，我們會盡快回覆"));
        }

        /// <summary>
        /// 向 Cloudflare 驗證 Turnstile token。網路/解析失敗一律視為未通過（fail-closed）。
        /// </summary>
        private async Task<bool> VerifyTurnstileAsync(string secret, string? token)
        {
            if (string.IsNullOrWhiteSpace(token))
                return false;

            var remoteIp = HttpContext.Request.Headers["CF-Connecting-IP"].FirstOrDefault()
                ?? HttpContext.Request.Headers["X-Forwarded-For"].FirstOrDefault()?.Split(',')[0].Trim()
                ?? HttpContext.Connection.RemoteIpAddress?.ToString();

            try
            {
                var fields = new List<KeyValuePair<string, string>>
                {
                    new("secret", secret),
                    new("response", token),
                };
                if (!string.IsNullOrWhiteSpace(remoteIp))
                    fields.Add(new("remoteip", remoteIp));

                var client = _httpFactory.CreateClient();
                client.Timeout = TimeSpan.FromSeconds(10);
                using var resp = await client.PostAsync(
                    TurnstileVerifyUrl, new FormUrlEncodedContent(fields));

                var json = await resp.Content.ReadAsStringAsync();
                using var doc = JsonDocument.Parse(json);
                var ok = doc.RootElement.TryGetProperty("success", out var s) &&
                         s.ValueKind == JsonValueKind.True;

                if (!ok)
                    _logger.LogWarning("Turnstile 驗證未通過：{Json}", json);
                return ok;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Turnstile 驗證請求失敗");
                return false; // fail-closed：驗證服務不可用時擋下，避免被當作繞過
            }
        }
    }
}
