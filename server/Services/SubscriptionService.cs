using Microsoft.EntityFrameworkCore;
using System.Text.Json;
using UploadServer.Constants;
using UploadServer.Data;
using UploadServer.Models;

namespace UploadServer.Services
{
    /// <summary>
    /// 處理 Google Play RTDN 和 Apple Server Notification 的訂閱事件，
    /// 更新 User.Plan / SubscriptionExpiry / SubscriptionStatus。
    /// </summary>
    public class SubscriptionService
    {
        private readonly VideoDbContext _db;
        private readonly UserService _userService;
        private readonly ILogger<SubscriptionService> _logger;
        private readonly IConfiguration _config;

        // Google notificationType 常數
        private const int GoogleRenewed  = 2;
        private const int GoogleCanceled = 3;
        private const int GoogleExpired  = 12;
        private const int GoogleRevoked  = 13;

        public SubscriptionService(
            VideoDbContext db,
            UserService userService,
            ILogger<SubscriptionService> logger,
            IConfiguration config)
        {
            _db          = db;
            _userService = userService;
            _logger      = logger;
            _config      = config;
        }

        // ════════════════════════════════════════════════════════════════
        // Google Play RTDN
        // ════════════════════════════════════════════════════════════════

        public async Task HandleGoogleNotificationAsync(
            int notificationType, string purchaseToken, string subscriptionId)
        {
            _logger.LogInformation("Google RTDN type={Type} sub={Sub}", notificationType, subscriptionId);

            switch (notificationType)
            {
                case GoogleRenewed:
                    await HandleGoogleRenewalAsync(purchaseToken, subscriptionId);
                    break;
                case GoogleCanceled:
                    await SetCancelPendingByTokenAsync(purchaseToken);
                    break;
                case GoogleExpired:
                    await ExpireByTokenAsync(purchaseToken);
                    break;
                case GoogleRevoked:
                    await RevokeByTokenAsync(purchaseToken);
                    break;
                default:
                    _logger.LogInformation("Google RTDN type={Type} 忽略", notificationType);
                    break;
            }
        }

        private async Task HandleGoogleRenewalAsync(string purchaseToken, string subscriptionId)
        {
            var result = await _userService.ValidateGooglePlaySubscriptionAsync(purchaseToken, subscriptionId);
            if (!result.Success || result.ExpiryTime == null)
            {
                _logger.LogWarning("Google renewal 驗證失敗 token={Token}", purchaseToken[..Math.Min(20, purchaseToken.Length)]);
                return;
            }

            var user = await FindUserByOriginalIdOrTokenAsync(result.OriginalTransactionId, purchaseToken);
            if (user == null)
            {
                _logger.LogWarning("Google renewal: 找不到對應用戶 originalId={Id}", result.OriginalTransactionId);
                return;
            }

            user.SubscriptionExpiry  = result.ExpiryTime;
            user.SubscriptionStatus  = "active";
            user.UpdatedAt           = DateTime.UtcNow;

            _db.PurchaseRecords.Add(new PurchaseRecord
            {
                UserId               = user.Id,
                Plan                 = user.Plan,
                Store                = "google_play",
                ProductId            = subscriptionId,
                PurchaseToken        = purchaseToken,
                Status               = PurchaseStatus.Verified,
                OriginalTransactionId = result.OriginalTransactionId,
                ExpiresAt            = result.ExpiryTime,
                IsAutoRenewing       = result.IsAutoRenewing,
                CreatedAt            = DateTime.UtcNow,
                VerifiedAt           = DateTime.UtcNow,
            });

            await _db.SaveChangesAsync();
            _logger.LogInformation("Google renewal 成功：用戶 {UserId} 到期 {Expiry}", user.Id, result.ExpiryTime);
        }

        private async Task SetCancelPendingByTokenAsync(string purchaseToken)
        {
            var user = await FindUserByTokenAsync(purchaseToken);
            if (user == null) return;
            // 取消後仍可用到到期日
            user.SubscriptionStatus = "cancel_pending";
            user.UpdatedAt          = DateTime.UtcNow;
            await _db.SaveChangesAsync();
            _logger.LogInformation("用戶 {UserId} 取消訂閱（cancel_pending），到期 {Expiry}", user.Id, user.SubscriptionExpiry);
        }

        private async Task ExpireByTokenAsync(string purchaseToken)
        {
            var user = await FindUserByTokenAsync(purchaseToken);
            if (user == null) return;
            user.Plan               = "free";
            user.SubscriptionStatus = "expired";
            user.UpdatedAt          = DateTime.UtcNow;
            await _db.SaveChangesAsync();
            _logger.LogInformation("用戶 {UserId} 訂閱到期，降回 free", user.Id);
        }

        private async Task RevokeByTokenAsync(string purchaseToken)
        {
            var user = await FindUserByTokenAsync(purchaseToken);
            if (user == null) return;
            user.Plan               = "free";
            user.SubscriptionStatus = "expired";
            user.SubscriptionExpiry = null;
            user.UpdatedAt          = DateTime.UtcNow;
            await _db.SaveChangesAsync();
            _logger.LogInformation("用戶 {UserId} 訂閱被撤銷（退款），立即降回 free", user.Id);
        }

        // ════════════════════════════════════════════════════════════════
        // Apple Server Notifications
        // ════════════════════════════════════════════════════════════════

        public async Task HandleAppleNotificationAsync(
            string notificationType, string? subtype,
            string originalTransactionId, string productId,
            long expiresDateMs, long? revocationDateMs)
        {
            _logger.LogInformation("Apple Notification type={Type} sub={Sub} originalTxId={Id}",
                notificationType, subtype, originalTransactionId);

            switch (notificationType)
            {
                case "DID_RENEW":
                    await HandleAppleRenewalAsync(originalTransactionId, productId, expiresDateMs);
                    break;
                case "DID_CHANGE_RENEWAL_STATUS" when subtype == "AUTO_RENEW_DISABLED":
                    await SetCancelPendingByOriginalIdAsync(originalTransactionId);
                    break;
                case "EXPIRED":
                    await ExpireByOriginalIdAsync(originalTransactionId);
                    break;
                case "REFUND":
                    await RevokeByOriginalIdAsync(originalTransactionId);
                    break;
                default:
                    _logger.LogInformation("Apple Notification type={Type} 忽略", notificationType);
                    break;
            }
        }

        private async Task HandleAppleRenewalAsync(
            string originalTransactionId, string productId, long expiresDateMs)
        {
            var user = await _db.Users.FirstOrDefaultAsync(
                u => u.SubscriptionOriginalId == originalTransactionId);
            if (user == null)
            {
                _logger.LogWarning("Apple renewal: 找不到對應用戶 originalTxId={Id}", originalTransactionId);
                return;
            }

            var expiryTime = DateTimeOffset.FromUnixTimeMilliseconds(expiresDateMs).UtcDateTime;
            user.SubscriptionExpiry = expiryTime;
            user.SubscriptionStatus = "active";
            user.UpdatedAt          = DateTime.UtcNow;

            var plan = productId.Contains("elite") ? "elite" : "pro";
            user.Plan = plan;

            _db.PurchaseRecords.Add(new PurchaseRecord
            {
                UserId               = user.Id,
                Plan                 = plan,
                Store                = "app_store",
                ProductId            = productId,
                PurchaseToken        = originalTransactionId,
                Status               = PurchaseStatus.Verified,
                OriginalTransactionId = originalTransactionId,
                ExpiresAt            = expiryTime,
                IsAutoRenewing       = true,
                CreatedAt            = DateTime.UtcNow,
                VerifiedAt           = DateTime.UtcNow,
            });

            await _db.SaveChangesAsync();
            _logger.LogInformation("Apple renewal 成功：用戶 {UserId} 到期 {Expiry}", user.Id, expiryTime);
        }

        private async Task SetCancelPendingByOriginalIdAsync(string originalTransactionId)
        {
            var user = await _db.Users.FirstOrDefaultAsync(
                u => u.SubscriptionOriginalId == originalTransactionId);
            if (user == null) return;
            user.SubscriptionStatus = "cancel_pending";
            user.UpdatedAt          = DateTime.UtcNow;
            await _db.SaveChangesAsync();
        }

        private async Task ExpireByOriginalIdAsync(string originalTransactionId)
        {
            var user = await _db.Users.FirstOrDefaultAsync(
                u => u.SubscriptionOriginalId == originalTransactionId);
            if (user == null) return;
            user.Plan               = "free";
            user.SubscriptionStatus = "expired";
            user.UpdatedAt          = DateTime.UtcNow;
            await _db.SaveChangesAsync();
            _logger.LogInformation("Apple 訂閱到期：用戶 {UserId} 降回 free", user.Id);
        }

        private async Task RevokeByOriginalIdAsync(string originalTransactionId)
        {
            var user = await _db.Users.FirstOrDefaultAsync(
                u => u.SubscriptionOriginalId == originalTransactionId);
            if (user == null) return;
            user.Plan               = "free";
            user.SubscriptionStatus = "expired";
            user.SubscriptionExpiry = null;
            user.UpdatedAt          = DateTime.UtcNow;
            await _db.SaveChangesAsync();
            _logger.LogInformation("Apple 退款撤銷：用戶 {UserId} 降回 free", user.Id);
        }

        // ════════════════════════════════════════════════════════════════
        // 輔助查詢
        // ════════════════════════════════════════════════════════════════

        private async Task<User?> FindUserByTokenAsync(string purchaseToken)
        {
            var record = await _db.PurchaseRecords
                .Where(r => r.PurchaseToken == purchaseToken && r.Status == PurchaseStatus.Verified)
                .OrderByDescending(r => r.CreatedAt)
                .FirstOrDefaultAsync();
            if (record == null) return null;
            return await _db.Users.FindAsync(record.UserId);
        }

        private async Task<User?> FindUserByOriginalIdOrTokenAsync(string? originalId, string purchaseToken)
        {
            if (!string.IsNullOrEmpty(originalId))
            {
                var user = await _db.Users.FirstOrDefaultAsync(
                    u => u.SubscriptionOriginalId == originalId);
                if (user != null) return user;
            }
            return await FindUserByTokenAsync(purchaseToken);
        }
    }
}
