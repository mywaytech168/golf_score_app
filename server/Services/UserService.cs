using Microsoft.EntityFrameworkCore;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using UploadServer.Data;
using UploadServer.DTOs;
using UploadServer.Models;

namespace UploadServer.Services
{
    /// <summary>
    /// 使用者方案與獎勵業務邏輯
    /// </summary>
    public class UserService
    {
        private readonly VideoDbContext _db;
        private readonly ILogger<UserService> _logger;
        private readonly IHttpClientFactory _httpClientFactory;
        private readonly IConfiguration _config;

        // 廣告獎勵每日上限
        private const int AdDailyCap = 5;
        // 各獎勵球數
        private const int AdBalls       = 1;
        private const int FeedbackBalls = 2;
        private const int UploadBalls   = 3;
        private const int InviteBalls   = 5;

        public UserService(
            VideoDbContext db,
            ILogger<UserService> logger,
            IHttpClientFactory httpClientFactory,
            IConfiguration config)
        {
            _db = db;
            _logger = logger;
            _httpClientFactory = httpClientFactory;
            _config = config;
        }

        // ── 輔助 ──────────────────────────────────────────────────

        /// <summary>台灣時間（UTC+8）的今日日期</summary>
        private static DateOnly Today => DateOnly.FromDateTime(DateTime.UtcNow.AddHours(8));

        private static int DailyLimitFor(string plan) => plan switch
        {
            "pro"   => 90,
            "elite" => -1,
            _       => 10,
        };

        // ════════════════════════════════════════════════════════════════
        // 方案
        // ════════════════════════════════════════════════════════════════

        public async Task<PlanStatusResponse?> GetPlanStatusAsync(string userId)
        {
            var user = await _db.Users.FindAsync(userId);
            if (user == null) return null;

            // 跨日重置今日用量
            var today = Today;
            if (user.TodayUsedDate != today)
            {
                user.TodayUsed     = 0;
                user.TodayUsedDate = today;
                await _db.SaveChangesAsync();
            }

            var limit = DailyLimitFor(user.Plan);
            return new PlanStatusResponse(user.Plan, limit, user.TodayUsed, user.BonusBalls);
        }

        public async Task<bool> UpdatePlanAsync(string userId, string plan)
        {
            if (plan is not ("free" or "pro" or "elite")) return false;

            var user = await _db.Users.FindAsync(userId);
            if (user == null) return false;

            user.Plan      = plan;
            user.UpdatedAt = DateTime.UtcNow;
            await _db.SaveChangesAsync();
            _logger.LogInformation("用戶 {UserId} 方案更新為 {Plan}", userId, plan);
            return true;
        }

        /// <summary>
        /// 增加今日用量（Flutter 每次分析後呼叫）
        /// </summary>
        public async Task<IncrementUsageResponse?> IncrementUsageAsync(string userId)
        {
            var user = await _db.Users.FindAsync(userId);
            if (user == null) return null;

            var today = Today;
            if (user.TodayUsedDate != today)
            {
                user.TodayUsed     = 0;
                user.TodayUsedDate = today;
            }

            user.TodayUsed++;
            await _db.SaveChangesAsync();

            var limit = DailyLimitFor(user.Plan);
            var total = limit < 0 ? -1 : limit + user.BonusBalls;
            var remaining = total < 0 ? -1 : Math.Max(0, total - user.TodayUsed);
            return new IncrementUsageResponse(user.TodayUsed, remaining);
        }

        // ════════════════════════════════════════════════════════════════
        // 獎勵狀態
        // ════════════════════════════════════════════════════════════════

        public async Task<RewardStatusResponse?> GetRewardStatusAsync(string userId)
        {
            var user = await _db.Users.FindAsync(userId);
            if (user == null) return null;

            var today = Today;

            // 跨日重置廣告計數
            if (user.AdClaimedDate != today)
            {
                user.AdClaimedToday = 0;
                user.AdClaimedDate  = today;
                await _db.SaveChangesAsync();
            }

            // 若邀請碼為空，自動生成
            if (string.IsNullOrEmpty(user.InviteCode))
            {
                user.InviteCode = GenerateInviteCode();
                await _db.SaveChangesAsync();
            }

            return new RewardStatusResponse(
                user.BonusBalls,
                user.AdClaimedToday,
                user.FeedbackClaimedDate == today,
                user.InviteCode,
                user.InviteCount
            );
        }

        // ════════════════════════════════════════════════════════════════
        // 廣告獎勵
        // ════════════════════════════════════════════════════════════════

        public async Task<ClaimAdRewardResponse?> ClaimAdRewardAsync(string userId)
        {
            var user = await _db.Users.FindAsync(userId);
            if (user == null) return null;

            var today = Today;

            // 跨日重置
            if (user.AdClaimedDate != today)
            {
                user.AdClaimedToday = 0;
                user.AdClaimedDate  = today;
            }

            // 已達每日上限
            if (user.AdClaimedToday >= AdDailyCap)
            {
                _logger.LogWarning("用戶 {UserId} 廣告獎勵已達每日上限", userId);
                return new ClaimAdRewardResponse(0, user.AdClaimedToday);
            }

            user.AdClaimedToday++;
            user.BonusBalls += AdBalls;
            await _db.SaveChangesAsync();

            _logger.LogInformation("用戶 {UserId} 廣告獎勵 +{Balls} 球 (今日第 {Count} 次)",
                userId, AdBalls, user.AdClaimedToday);
            return new ClaimAdRewardResponse(AdBalls, user.AdClaimedToday);
        }

        // ════════════════════════════════════════════════════════════════
        // 邀請碼
        // ════════════════════════════════════════════════════════════════

        public async Task<string?> GetOrCreateInviteCodeAsync(string userId)
        {
            var user = await _db.Users.FindAsync(userId);
            if (user == null) return null;

            if (!string.IsNullOrEmpty(user.InviteCode)) return user.InviteCode;

            // 生成唯一邀請碼（重試直到無衝突）
            string code;
            do { code = GenerateInviteCode(); }
            while (await _db.Users.AnyAsync(u => u.InviteCode == code));

            user.InviteCode = code;
            await _db.SaveChangesAsync();
            return code;
        }

        /// <summary>
        /// 用邀請碼完成邀請（被邀請者註冊後呼叫）：
        /// 邀請者 +InviteBalls，被邀請者 +InviteBalls
        /// </summary>
        public async Task ApplyInviteRewardAsync(string newUserId, string inviteCode)
        {
            var inviter = await _db.Users.FirstOrDefaultAsync(u => u.InviteCode == inviteCode);
            if (inviter == null) return;

            var newUser = await _db.Users.FindAsync(newUserId);
            if (newUser == null) return;

            inviter.BonusBalls += InviteBalls;
            inviter.InviteCount++;
            newUser.BonusBalls += InviteBalls;
            newUser.InvitedByCode = inviteCode;

            await _db.SaveChangesAsync();
            _logger.LogInformation("邀請獎勵：邀請者 {InviterId} 與被邀請者 {NewUserId} 各 +{Balls} 球",
                inviter.Id, newUserId, InviteBalls);
        }

        // ════════════════════════════════════════════════════════════════
        // 問題回饋
        // ════════════════════════════════════════════════════════════════

        public async Task<FeedbackRewardResponse?> SubmitFeedbackAsync(
            string userId, string type, string text)
        {
            var user = await _db.Users.FindAsync(userId);
            if (user == null) return null;

            var today = Today;
            if (user.FeedbackClaimedDate == today)
            {
                _logger.LogWarning("用戶 {UserId} 今日已提交回饋", userId);
                return new FeedbackRewardResponse(0);
            }

            if (string.IsNullOrWhiteSpace(text) || text.Length > 2000)
                return new FeedbackRewardResponse(0);

            // 儲存回饋
            _db.UserFeedbacks.Add(new UserFeedback
            {
                Id        = Guid.NewGuid().ToString(),
                UserId    = userId,
                Type      = type is "bug" or "feature" or "other" ? type : "other",
                Text      = text.Trim(),
                CreatedAt = DateTime.UtcNow,
            });

            user.FeedbackClaimedDate = today;
            user.BonusBalls         += FeedbackBalls;
            await _db.SaveChangesAsync();

            _logger.LogInformation("用戶 {UserId} 回饋獎勵 +{Balls} 球", userId, FeedbackBalls);
            return new FeedbackRewardResponse(FeedbackBalls);
        }

        // ════════════════════════════════════════════════════════════════
        // 上傳資料獎勵
        // ════════════════════════════════════════════════════════════════

        public async Task<UploadRewardResponse?> ClaimUploadRewardAsync(
            string userId, List<SessionDataDto> sessions)
        {
            var user = await _db.Users.FindAsync(userId);
            if (user == null) return null;

            if (sessions.Count == 0)
                return new UploadRewardResponse(0, 0);

            // 每次上傳固定 +UploadBalls（不論筆數，防止刷量）
            user.BonusBalls += UploadBalls;
            await _db.SaveChangesAsync();

            _logger.LogInformation("用戶 {UserId} 上傳 {Count} 筆資料，獎勵 +{Balls} 球",
                userId, sessions.Count, UploadBalls);
            return new UploadRewardResponse(UploadBalls, sessions.Count);
        }

        // ════════════════════════════════════════════════════════════════
        // 付款購買升級
        // ════════════════════════════════════════════════════════════════

        public async Task<PurchasePlanResponse> PurchasePlanAsync(string userId, PurchasePlanRequest req)
        {
            var user = await _db.Users.FindAsync(userId);
            if (user == null) return new PurchasePlanResponse(false, "用戶不存在", null);

            if (req.Plan is not ("pro" or "elite"))
                return new PurchasePlanResponse(false, "無效的方案", null);

            if (!await ValidatePurchaseTokenAsync(req))
            {
                _logger.LogWarning("用戶 {UserId} 付款驗證失敗 store={Store}", userId, req.Store);
                return new PurchasePlanResponse(false, "付款驗證失敗", null);
            }

            user.Plan      = req.Plan;
            user.UpdatedAt = DateTime.UtcNow;
            await _db.SaveChangesAsync();

            _logger.LogInformation("用戶 {UserId} 透過 {Store} 升級為 {Plan}", userId, req.Store, req.Plan);
            return new PurchasePlanResponse(true, "方案已升級", req.Plan);
        }

        private async Task<bool> ValidatePurchaseTokenAsync(PurchasePlanRequest req)
        {
            if (string.IsNullOrWhiteSpace(req.PurchaseToken)) return false;

            return req.Store switch
            {
                "google_pay"  => ValidateGooglePayToken(req.PurchaseToken),
                "google_play" => await ValidateGooglePlayTokenAsync(req.PurchaseToken, req.ProductId),
                "app_store"   => await ValidateAppStoreReceiptAsync(req.PurchaseToken),
                _             => false,
            };
        }

        private bool ValidateGooglePayToken(string token)
        {
            // Google Pay TEST 環境：token 為 JSON payload，驗證基本結構即可。
            // 生產環境應將此 token 送至 Stripe/Braintree 等金流商進行扣款驗證。
            try
            {
                using var doc = System.Text.Json.JsonDocument.Parse(token);
                return doc.RootElement.ValueKind == System.Text.Json.JsonValueKind.Object;
            }
            catch { return false; }
        }

        private async Task<bool> ValidateGooglePlayTokenAsync(string purchaseToken, string? productId)
        {
            // 測試模式：接受預設測試 token（Google Play 靜態測試商品）
            var testMode   = _config.GetValue<bool>("GooglePlay:TestMode", false);
            var testTokens = _config.GetSection("GooglePlay:TestTokens").Get<string[]>() ?? [];

            if (testMode && testTokens.Contains(purchaseToken))
            {
                _logger.LogInformation("Google Play 測試模式：接受測試 token {Token}", purchaseToken);
                return true;
            }

            var packageName        = _config["GooglePlay:PackageName"];
            var serviceAccountJson = _config["GooglePlay:ServiceAccountJson"];

            if (string.IsNullOrEmpty(packageName) || string.IsNullOrEmpty(serviceAccountJson) || string.IsNullOrEmpty(productId))
            {
                _logger.LogWarning("Google Play 驗證配置不完整（PackageName / ServiceAccountJson / productId）");
                return false;
            }

            try
            {
                // 用服務帳戶取得 access token
                var credential = Google.Apis.Auth.OAuth2.GoogleCredential
                    .FromJson(serviceAccountJson)
                    .CreateScoped("https://www.googleapis.com/auth/androidpublisher");

                var accessToken = await credential.UnderlyingCredential.GetAccessTokenForRequestAsync();

                var client = _httpClientFactory.CreateClient();
                client.DefaultRequestHeaders.Authorization =
                    new AuthenticationHeaderValue("Bearer", accessToken);

                var url = $"https://androidpublisher.googleapis.com/androidpublisher/v3/applications/{packageName}/purchases/products/{productId}/tokens/{purchaseToken}";
                var response = await client.GetAsync(url);

                if (!response.IsSuccessStatusCode)
                {
                    _logger.LogWarning("Google Play API 回應錯誤: {Status}", response.StatusCode);
                    return false;
                }

                var json = await response.Content.ReadAsStringAsync();
                using var doc = System.Text.Json.JsonDocument.Parse(json);
                // purchaseState: 0 = Purchased, 1 = Cancelled, 2 = Pending
                return doc.RootElement.GetProperty("purchaseState").GetInt32() == 0;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Google Play 驗證失敗");
                return false;
            }
        }

        private async Task<bool> ValidateAppStoreReceiptAsync(string receiptData)
        {
            var sharedSecret = _config["AppStore:SharedSecret"];
            // Sandbox: true = 沙盒測試；false = 正式
            var isSandbox = _config.GetValue<bool>("AppStore:Sandbox", false);

            if (string.IsNullOrEmpty(sharedSecret))
            {
                _logger.LogWarning("App Store 驗證配置不完整（缺少 SharedSecret）");
                return false;
            }

            try
            {
                var url    = isSandbox
                    ? "https://sandbox.itunes.apple.com/verifyReceipt"
                    : "https://buy.itunes.apple.com/verifyReceipt";

                var client = _httpClientFactory.CreateClient();
                var body   = new { receipt_data = receiptData, password = sharedSecret };
                var resp   = await client.PostAsJsonAsync(url, body);

                if (!resp.IsSuccessStatusCode)
                {
                    _logger.LogWarning("App Store API 回應錯誤: {Status}", resp.StatusCode);
                    return false;
                }

                var json = await resp.Content.ReadAsStringAsync();
                using var doc = System.Text.Json.JsonDocument.Parse(json);
                var status = doc.RootElement.GetProperty("status").GetInt32();

                // 21007 = sandbox receipt 送到正式端點 → 切換 sandbox 重試
                if (status == 21007 && !isSandbox)
                {
                    _logger.LogInformation("App Store：偵測到 sandbox 收據，切換 sandbox 端點重試");
                    var sr = await client.PostAsJsonAsync("https://sandbox.itunes.apple.com/verifyReceipt", body);
                    if (!sr.IsSuccessStatusCode) return false;
                    using var sd = System.Text.Json.JsonDocument.Parse(await sr.Content.ReadAsStringAsync());
                    status = sd.RootElement.GetProperty("status").GetInt32();
                }

                return status == 0;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "App Store 驗證失敗");
                return false;
            }
        }

        // ── 邀請碼生成 ────────────────────────────────────────────

        private static string GenerateInviteCode()
        {
            const string chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // 去掉易混淆字元
            var rng  = new Random();
            return new string(Enumerable.Range(0, 8).Select(_ => chars[rng.Next(chars.Length)]).ToArray());
        }
    }
}
