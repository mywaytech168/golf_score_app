using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using System.Text;
using System.Text.Json;
using UploadServer.Data;
using UploadServer.DTOs;
using UploadServer.Models;
using UploadServer.Services;

namespace UploadServer.Controllers
{
    /// <summary>
    /// 接收 Google Play RTDN 和 Apple Server Notification V2 的 Webhook 端點。
    /// 這兩個端點不需要 JWT 驗證（由平台簽名保護）。
    /// </summary>
    [ApiController]
    [Route("api/webhook")]
    public class WebhookController : ControllerBase
    {
        private readonly SubscriptionService _subscriptionService;
        private readonly ILogger<WebhookController> _logger;
        private readonly IConfiguration _config;

        private static readonly JsonSerializerOptions _jsonOpts = new()
        {
            PropertyNameCaseInsensitive = true,
        };

        private readonly AdMobSsvVerifier _ssvVerifier;
        private readonly VideoDbContext _db;

        public WebhookController(
            SubscriptionService subscriptionService,
            ILogger<WebhookController> logger,
            IConfiguration config,
            AdMobSsvVerifier ssvVerifier,
            VideoDbContext db)
        {
            _subscriptionService = subscriptionService;
            _logger              = logger;
            _config              = config;
            _ssvVerifier         = ssvVerifier;
            _db                  = db;
        }

        // ════════════════════════════════════════════════════════════════
        // AdMob 獎勵廣告 SSV 回呼
        // GET /api/webhook/admob-ssv?...&user_id=...&transaction_id=...&signature=...&key_id=...
        // 驗簽通過才記錄觀看事件；領獎 API（POST /api/user/rewards/ad）消耗事件發球
        // ════════════════════════════════════════════════════════════════

        [HttpGet("admob-ssv")]
        public async Task<IActionResult> AdMobSsv()
        {
            var rawQuery = Request.QueryString.Value ?? "";
            if (!await _ssvVerifier.VerifyAsync(rawQuery))
            {
                _logger.LogWarning("AdMob SSV 驗簽失敗: {Query}", rawQuery);
                return BadRequest();
            }

            var userId        = Request.Query["user_id"].ToString();
            var transactionId = Request.Query["transaction_id"].ToString();

            // AdMob 後台「驗證 URL」測試 ping 不帶完整參數，驗簽過即回 200
            if (string.IsNullOrEmpty(userId) || string.IsNullOrEmpty(transactionId))
                return Ok();

            // transaction_id 唯一索引防重放；重複回呼直接視為成功
            var exists = await _db.AdRewardEvents.AnyAsync(e => e.TransactionId == transactionId);
            if (!exists)
            {
                _db.AdRewardEvents.Add(new AdRewardEvent
                {
                    UserId        = userId,
                    TransactionId = transactionId,
                });
                try
                {
                    await _db.SaveChangesAsync();
                    _logger.LogInformation("AdMob SSV 觀看事件入帳: user={UserId} tx={Tx}", userId, transactionId);
                }
                catch (DbUpdateException)
                {
                    // 並發重複回呼撞唯一索引：已有人寫入，等同成功
                }
            }

            return Ok();
        }

        // ════════════════════════════════════════════════════════════════
        // Google Play RTDN
        // POST /api/webhook/google-play
        // ════════════════════════════════════════════════════════════════

        [HttpPost("google-play")]
        public async Task<IActionResult> GooglePlay([FromBody] GooglePubSubPush push)
        {
            try
            {
                // 驗證 Pub/Sub token（設定 ?token=xxx 方式）
                var expectedToken = _config["GooglePlay:PubSubVerifyToken"];
                if (!string.IsNullOrEmpty(expectedToken))
                {
                    var receivedToken = Request.Query["token"].ToString();
                    if (receivedToken != expectedToken)
                    {
                        _logger.LogWarning("Google Pub/Sub token 驗證失敗");
                        return Unauthorized();
                    }
                }

                // 解碼 base64 → DeveloperNotification JSON
                var jsonBytes = Convert.FromBase64String(push.Message.Data);
                var json      = Encoding.UTF8.GetString(jsonBytes);

                _logger.LogDebug("Google RTDN payload: {Json}", json);

                var notification = JsonSerializer.Deserialize<GoogleDeveloperNotification>(json, _jsonOpts);
                if (notification?.SubscriptionNotification == null)
                {
                    _logger.LogInformation("Google RTDN: 非訂閱通知，忽略");
                    return Ok(); // 回 200 防止 Pub/Sub 重試
                }

                var sub = notification.SubscriptionNotification;
                await _subscriptionService.HandleGoogleNotificationAsync(
                    sub.NotificationType, sub.PurchaseToken, sub.SubscriptionId);

                return Ok();
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Google RTDN 處理失敗");
                // 故意回 200：讓 Pub/Sub 不要無限重試（已記錄 log）
                return Ok();
            }
        }

        // ════════════════════════════════════════════════════════════════
        // Apple Server Notifications V2
        // POST /api/webhook/apple
        // ════════════════════════════════════════════════════════════════

        [HttpPost("apple")]
        public async Task<IActionResult> Apple([FromBody] AppleNotificationBody body)
        {
            try
            {
                // 解碼 JWS（不驗簽名，僅解析 payload）
                // 生產環境建議：驗證 Apple 的 x5c 憑證鏈
                var payload = DecodeJwsPayload(body.SignedPayload);
                if (payload == null)
                {
                    _logger.LogWarning("Apple Notification: JWS payload 解碼失敗");
                    return Ok();
                }

                // 解碼 signedTransactionInfo
                var txInfo = DecodeJwsPayload<AppleTransactionInfo>(payload.Data.SignedTransactionInfo);
                if (txInfo == null)
                {
                    _logger.LogWarning("Apple Notification: signedTransactionInfo 解碼失敗");
                    return Ok();
                }

                await _subscriptionService.HandleAppleNotificationAsync(
                    notificationType:      payload.NotificationType,
                    subtype:               payload.Subtype,
                    originalTransactionId: txInfo.OriginalTransactionId,
                    productId:             txInfo.ProductId,
                    expiresDateMs:         txInfo.ExpiresDateMs,
                    revocationDateMs:      txInfo.RevocationDateMs);

                return Ok();
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Apple Server Notification 處理失敗");
                return Ok();
            }
        }

        // ════════════════════════════════════════════════════════════════
        // JWS 解碼輔助（decode-only，不驗簽）
        // ════════════════════════════════════════════════════════════════

        private static T? DecodeJwsPayload<T>(string jws) where T : class
        {
            var raw = DecodeJwsPayloadJson(jws);
            return raw == null ? null : JsonSerializer.Deserialize<T>(raw, _jsonOpts);
        }

        private static AppleJwsPayload? DecodeJwsPayload(string jws)
            => DecodeJwsPayload<AppleJwsPayload>(jws);

        private static string? DecodeJwsPayloadJson(string jws)
        {
            try
            {
                var parts = jws.Split('.');
                if (parts.Length < 2) return null;
                var payloadBase64 = parts[1].Replace('-', '+').Replace('_', '/');
                // 補齊 padding
                payloadBase64 = payloadBase64.PadRight(
                    payloadBase64.Length + (4 - payloadBase64.Length % 4) % 4, '=');
                var bytes = Convert.FromBase64String(payloadBase64);
                return Encoding.UTF8.GetString(bytes);
            }
            catch { return null; }
        }
    }
}
