using Microsoft.EntityFrameworkCore;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using UploadServer.Constants;
using UploadServer.Data;
using UploadServer.DTOs;
using UploadServer.Models;

namespace UploadServer.Services
{
    public class UserService
    {
        private readonly VideoDbContext _db;
        private readonly ILogger<UserService> _logger;
        private readonly IHttpClientFactory _httpClientFactory;
        private readonly IConfiguration _config;

        private const int AdDailyCap    = 5;
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
            _db                = db;
            _logger            = logger;
            _httpClientFactory = httpClientFactory;
            _config            = config;
        }

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
        /// 每次 AI 分析後呼叫：判斷來源（每日配額 or 獎勵球），
        /// 寫入 analysis_records，若消耗球數則一併寫入 ball_records。
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

            var limit = DailyLimitFor(user.Plan);
            // 判斷這次消耗來自配額還是球數
            // elite (limit=-1) 永遠走 daily_quota
            string source;
            int ballsSpent;
            if (limit < 0 || user.TodayUsed <= limit)
            {
                source     = AnalysisSource.DailyQuota;
                ballsSpent = 0;
            }
            else
            {
                source     = AnalysisSource.BonusBall;
                ballsSpent = 1;
                user.BonusBalls = Math.Max(0, user.BonusBalls - 1);
            }

            var record = new AnalysisRecord
            {
                UserId     = userId,
                Source     = source,
                BallsSpent = ballsSpent,
                UsedAt     = DateTime.UtcNow,
            };
            _db.AnalysisRecords.Add(record);

            if (ballsSpent > 0)
            {
                _db.BallRecords.Add(new BallRecord
                {
                    UserId       = userId,
                    Reason       = BallReason.Analysis,
                    Delta        = -ballsSpent,
                    BalanceAfter = user.BonusBalls,
                    RefId        = record.Id,
                    CreatedAt    = DateTime.UtcNow,
                });
            }

            await _db.SaveChangesAsync();

            var total     = limit < 0 ? -1 : limit + user.BonusBalls;
            var remaining = total  < 0 ? -1 : Math.Max(0, total - user.TodayUsed);
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
            if (user.AdClaimedDate != today)
            {
                user.AdClaimedToday = 0;
                user.AdClaimedDate  = today;
                await _db.SaveChangesAsync();
            }

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
                user.InviteCount,
                !string.IsNullOrEmpty(user.InvitedByCode)
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
            if (user.AdClaimedDate != today)
            {
                user.AdClaimedToday = 0;
                user.AdClaimedDate  = today;
            }

            if (user.AdClaimedToday >= AdDailyCap)
            {
                _logger.LogWarning("用戶 {UserId} 廣告獎勵已達每日上限", userId);
                return new ClaimAdRewardResponse(0, user.AdClaimedToday);
            }

            user.AdClaimedToday++;
            user.BonusBalls += AdBalls;

            _db.BallRecords.Add(new BallRecord
            {
                UserId       = userId,
                Reason       = BallReason.Ad,
                Delta        = AdBalls,
                BalanceAfter = user.BonusBalls,
                CreatedAt    = DateTime.UtcNow,
            });

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

            string code;
            do { code = GenerateInviteCode(); }
            while (await _db.Users.AnyAsync(u => u.InviteCode == code));

            user.InviteCode = code;
            await _db.SaveChangesAsync();
            return code;
        }

        /// <summary>
        /// 完成邀請獎勵：雙方各得球數，寫入 invite_records 和 ball_records。
        /// 回傳 ApplyInviteResponse（含成功/失敗訊息與被邀請者得到的球數）。
        /// </summary>
        public async Task<ApplyInviteResponse> ApplyInviteRewardAsync(string newUserId, string inviteCode)
        {
            var newUser = await _db.Users.FindAsync(newUserId);
            if (newUser == null)
                return new ApplyInviteResponse(false, "用戶不存在", 0);

            if (!string.IsNullOrEmpty(newUser.InvitedByCode))
            {
                _logger.LogWarning("用戶 {UserId} 已套用過邀請碼，忽略重複請求", newUserId);
                return new ApplyInviteResponse(false, "你已套用過邀請碼，每個帳號只能使用一次", 0);
            }

            if (!string.IsNullOrEmpty(newUser.InviteCode) &&
                newUser.InviteCode.Equals(inviteCode, StringComparison.OrdinalIgnoreCase))
            {
                _logger.LogWarning("用戶 {UserId} 嘗試套用自己的邀請碼", newUserId);
                return new ApplyInviteResponse(false, "不能使用自己的邀請碼", 0);
            }

            var inviter = await _db.Users.FirstOrDefaultAsync(
                u => u.InviteCode != null && u.InviteCode.ToLower() == inviteCode.ToLower());
            if (inviter == null)
                return new ApplyInviteResponse(false, "邀請碼無效，請確認後再試", 0);

            inviter.BonusBalls   += InviteBalls;
            inviter.InviteCount++;
            newUser.BonusBalls   += InviteBalls;
            newUser.InvitedByCode = inviteCode.ToUpperInvariant();

            var inviteRecord = new InviteRecord
            {
                InviterUserId = inviter.Id,
                InviteeUserId = newUserId,
                InviteCode    = inviteCode.ToUpperInvariant(),
                InviterBalls  = InviteBalls,
                InviteeBalls  = InviteBalls,
                CreatedAt     = DateTime.UtcNow,
            };
            _db.InviteRecords.Add(inviteRecord);

            _db.BallRecords.Add(new BallRecord
            {
                UserId       = inviter.Id,
                Reason       = BallReason.Invite,
                Delta        = InviteBalls,
                BalanceAfter = inviter.BonusBalls,
                RefId        = inviteRecord.Id,
                CreatedAt    = DateTime.UtcNow,
            });
            _db.BallRecords.Add(new BallRecord
            {
                UserId       = newUserId,
                Reason       = BallReason.Invite,
                Delta        = InviteBalls,
                BalanceAfter = newUser.BonusBalls,
                RefId        = inviteRecord.Id,
                CreatedAt    = DateTime.UtcNow,
            });

            await _db.SaveChangesAsync();
            _logger.LogInformation("邀請獎勵：邀請者 {InviterId} 與被邀請者 {NewUserId} 各 +{Balls} 球",
                inviter.Id, newUserId, InviteBalls);

            return new ApplyInviteResponse(true, $"邀請碼套用成功！雙方各獲得 +{InviteBalls} 球", InviteBalls);
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

            _db.BallRecords.Add(new BallRecord
            {
                UserId       = userId,
                Reason       = BallReason.Feedback,
                Delta        = FeedbackBalls,
                BalanceAfter = user.BonusBalls,
                CreatedAt    = DateTime.UtcNow,
            });

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

            user.BonusBalls += UploadBalls;

            _db.BallRecords.Add(new BallRecord
            {
                UserId       = userId,
                Reason       = BallReason.Upload,
                Delta        = UploadBalls,
                BalanceAfter = user.BonusBalls,
                CreatedAt    = DateTime.UtcNow,
            });

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

            // 先建立 pending 記錄，確保驗證失敗也留下嘗試紀錄
            var purchaseRecord = new PurchaseRecord
            {
                UserId        = userId,
                Plan          = req.Plan,
                Store         = req.Store,
                ProductId     = req.ProductId,
                PurchaseToken = req.PurchaseToken,
                Status        = PurchaseStatus.Pending,
                CreatedAt     = DateTime.UtcNow,
            };
            _db.PurchaseRecords.Add(purchaseRecord);
            await _db.SaveChangesAsync();

            if (!await ValidatePurchaseTokenAsync(req))
            {
                purchaseRecord.Status = PurchaseStatus.Failed;
                await _db.SaveChangesAsync();
                _logger.LogWarning("用戶 {UserId} 付款驗證失敗 store={Store}", userId, req.Store);
                return new PurchasePlanResponse(false, "付款驗證失敗", null);
            }

            user.Plan               = req.Plan;
            user.UpdatedAt          = DateTime.UtcNow;
            purchaseRecord.Status     = PurchaseStatus.Verified;
            purchaseRecord.VerifiedAt = DateTime.UtcNow;
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
            var testMode = _config.GetValue<bool>("GooglePay:TestMode", false);

            if (!testMode)
            {
                _logger.LogError("Google Pay 生產環境驗證尚未實作，拒絕付款請求");
                return false;
            }

            try
            {
                using var doc = System.Text.Json.JsonDocument.Parse(token);
                return doc.RootElement.ValueKind == System.Text.Json.JsonValueKind.Object;
            }
            catch { return false; }
        }

        private async Task<bool> ValidateGooglePlayTokenAsync(string purchaseToken, string? productId)
        {
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
            var isSandbox    = _config.GetValue<bool>("AppStore:Sandbox", false);

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

        // ════════════════════════════════════════════════════════════════
        // 使用紀錄
        // ════════════════════════════════════════════════════════════════

        /// <summary>
        /// 分頁查詢 AI 分析紀錄（含每日配額與球數消耗）
        /// </summary>
        public async Task<AnalysisHistoryResponse?> GetAnalysisHistoryAsync(
            string userId, int page, int pageSize)
        {
            var user = await _db.Users.FindAsync(userId);
            if (user == null) return null;

            pageSize = Math.Clamp(pageSize, 1, 100);
            page     = Math.Max(1, page);

            var today = Today;

            var query = _db.AnalysisRecords
                .Where(r => r.UserId == userId)
                .OrderByDescending(r => r.UsedAt);

            var total    = await query.CountAsync();
            var todayUsed = user.TodayUsedDate == today ? user.TodayUsed : 0;

            var items = await query
                .Skip((page - 1) * pageSize)
                .Take(pageSize)
                .Select(r => new AnalysisRecordDto(r.Id, r.Source, r.BallsSpent, r.UsedAt))
                .ToListAsync();

            return new AnalysisHistoryResponse(total, todayUsed, page, pageSize, items);
        }

        /// <summary>
        /// 分頁查詢球數流水帳（獲得 + 消耗）
        /// </summary>
        public async Task<BallsHistoryResponse?> GetBallsHistoryAsync(
            string userId, int page, int pageSize)
        {
            var user = await _db.Users.FindAsync(userId);
            if (user == null) return null;

            pageSize = Math.Clamp(pageSize, 1, 100);
            page     = Math.Max(1, page);

            var query = _db.BallRecords
                .Where(r => r.UserId == userId)
                .OrderByDescending(r => r.CreatedAt);

            var total = await query.CountAsync();

            var items = await query
                .Skip((page - 1) * pageSize)
                .Take(pageSize)
                .Select(r => new BallRecordDto(r.Id, r.Reason, r.Delta, r.BalanceAfter, r.CreatedAt))
                .ToListAsync();

            return new BallsHistoryResponse(total, user.BonusBalls, page, pageSize, items);
        }

        // ════════════════════════════════════════════════════════════════
        // 已邀請好友列表
        // ════════════════════════════════════════════════════════════════

        /// <summary>
        /// 查詢某用戶曾成功邀請的好友清單。
        /// 回傳：顯示名稱、大頭貼、加入時間、獎勵球數。
        /// </summary>
        public async Task<InvitedFriendsResponse?> GetInvitedFriendsAsync(string userId)
        {
            var user = await _db.Users.FindAsync(userId);
            if (user == null) return null;

            var records = await _db.InviteRecords
                .Where(r => r.InviterUserId == userId)
                .OrderByDescending(r => r.CreatedAt)
                .Select(r => new
                {
                    r.CreatedAt,
                    r.InviterBalls,
                    InviteeDisplayName = r.Invitee != null ? r.Invitee.DisplayName : "好友",
                    InviteeAvatarUrl   = r.Invitee != null ? r.Invitee.AvatarUrl   : null,
                })
                .ToListAsync();

            var friends = records.Select(r => new InvitedFriendDto(
                r.InviteeDisplayName,
                r.InviteeAvatarUrl,
                r.CreatedAt,
                r.InviterBalls
            )).ToList();

            return new InvitedFriendsResponse(friends.Count, friends);
        }

        private static string GenerateInviteCode()
        {
            const string chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
            var bytes = System.Security.Cryptography.RandomNumberGenerator.GetBytes(8);
            return new string(bytes.Select(b => chars[b % chars.Length]).ToArray());
        }
    }
}
