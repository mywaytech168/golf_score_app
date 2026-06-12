using Microsoft.EntityFrameworkCore;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
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
        // 個人資料
        // ════════════════════════════════════════════════════════════════

        public async Task<MeResponse?> GetMeAsync(string userId)
        {
            var user = await _db.Users
                .Include(u => u.UserAuths)
                .FirstOrDefaultAsync(u => u.Id == userId);
            if (user == null) return null;

            return new MeResponse(
                Id:           user.Id,
                Username:     user.Username,
                Email:        user.Email,
                DisplayName:  user.DisplayName,
                GoogleLinked: user.UserAuths.Any(a => a.Provider == AuthProvider.Google),
                HasPassword:  user.UserAuths.Any(a => a.Provider == AuthProvider.Local)
            );
        }

        public async Task<bool> UpdateDisplayNameAsync(string userId, string displayName)
        {
            var user = await _db.Users.FindAsync(userId);
            if (user == null) return false;

            user.DisplayName = displayName;
            user.UpdatedAt   = DateTime.UtcNow;
            await _db.SaveChangesAsync();
            return true;
        }

        /// <summary>
        /// 軟刪除帳號：標記 deleted、移除所有登入憑證（之後無法再登入），
        /// 並匿名化 email/username 釋出該信箱供重新註冊。
        /// </summary>
        public async Task<bool> DeleteAccountAsync(string userId)
        {
            var user = await _db.Users
                .Include(u => u.UserAuths)
                .FirstOrDefaultAsync(u => u.Id == userId);
            if (user == null) return false;

            _db.UserAuths.RemoveRange(user.UserAuths);
            user.Status      = "deleted";
            user.Email       = $"deleted_{user.Id}@deleted.local";
            user.Username    = $"deleted_{user.Id}";
            user.DisplayName = "已刪除帳號";
            user.UpdatedAt   = DateTime.UtcNow;
            await _db.SaveChangesAsync();

            _logger.LogInformation("🗑️ 帳號已軟刪除: UserId={UserId}", userId);
            return true;
        }

        // ════════════════════════════════════════════════════════════════
        // 方案
        // ════════════════════════════════════════════════════════════════

        public async Task<PlanStatusResponse?> GetPlanStatusAsync(string userId)
        {
            var user = await _db.Users.FindAsync(userId);
            if (user == null) return null;

            // 訂閱到期自動降回 free
            if (user.Plan != "free" && user.SubscriptionExpiry.HasValue
                && user.SubscriptionExpiry.Value < DateTime.UtcNow
                && user.SubscriptionStatus != "active")
            {
                user.Plan               = "free";
                user.SubscriptionStatus = "expired";
                user.UpdatedAt          = DateTime.UtcNow;
                _logger.LogInformation("用戶 {UserId} 訂閱已到期，降回 free", userId);
            }

            var today = Today;
            if (user.TodayUsedDate != today)
            {
                user.TodayUsed     = 0;
                user.TodayUsedDate = today;
            }
            await _db.SaveChangesAsync();

            var limit = DailyLimitFor(user.Plan);
            return new PlanStatusResponse(user.Plan, limit, user.TodayUsed, user.BonusBalls,
                user.SubscriptionExpiry, user.SubscriptionStatus);
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
            string userId, string type, string text,
            string? videoId = null, string? imageB2Key = null)
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

            // 驗證 B2 Key 長度
            var safeImageB2Key = imageB2Key?.Length > 500 ? null : imageB2Key;

            _db.UserFeedbacks.Add(new UserFeedback
            {
                Id                  = Guid.NewGuid().ToString(),
                UserId              = userId,
                Type                = type is "bug" or "feature" or "other" ? type : "other",
                Text                = text.Trim(),
                CreatedAt           = DateTime.UtcNow,
                AttachedVideoId     = string.IsNullOrWhiteSpace(videoId) ? null : videoId.Trim()[..Math.Min(255, videoId.Trim().Length)],
                AttachedImageB2Key  = safeImageB2Key,
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

        /// <summary>
        /// 分頁查詢自己提交的回饋（含管理員回覆）
        /// </summary>
        public async Task<MyFeedbacksResponse?> GetMyFeedbacksAsync(
            string userId, int page, int pageSize)
        {
            var user = await _db.Users.FindAsync(userId);
            if (user == null) return null;

            pageSize = Math.Clamp(pageSize, 1, 100);
            page     = Math.Max(1, page);

            var query = _db.UserFeedbacks
                .Where(f => f.UserId == userId)
                .OrderByDescending(f => f.CreatedAt);

            var total = await query.CountAsync();

            var items = await query
                .Skip((page - 1) * pageSize)
                .Take(pageSize)
                .Select(f => new MyFeedbackDto(
                    f.Id, f.Type, f.Text, f.AttachedVideoId,
                    f.AttachedImageB2Key, f.AdminReply, f.AdminRepliedAt, f.CreatedAt))
                .ToListAsync();

            return new MyFeedbacksResponse(total, page, pageSize, items);
        }

        // ════════════════════════════════════════════════════════════════
        // 上傳資料獎勵
        // ════════════════════════════════════════════════════════════════

        /// <summary>
        /// 審核制：提交上傳資料 → 建立 pending 列，不立即發球；
        /// 後台核准（ReviewDatasetUploadAsync）後才發 +3 球。
        /// 去重：同 user + ClientFilePath 已有 pending / approved 列 → 跳過；
        /// rejected 允許重新提交（新列）。
        /// </summary>
        public async Task<UploadRewardResponse?> ClaimUploadRewardAsync(
            string userId, List<SessionDataDto> sessions)
        {
            var user = await _db.Users.FindAsync(userId);
            if (user == null) return null;

            if (sessions.Count == 0)
                return new UploadRewardResponse(0, 0);

            // ── 去重：同 user + 同 ClientFilePath 已有 pending / approved 列者跳過 ──
            var filePaths = sessions.Select(s => s.FilePath).ToList();
            var existingSet = (await _db.DatasetUploads
                .Where(d => d.UserId == userId
                            && filePaths.Contains(d.ClientFilePath)
                            && d.Status != DatasetUploadStatus.Rejected)
                .Select(d => d.ClientFilePath)
                .ToListAsync()).ToHashSet();

            var newSessions = sessions
                .Where(s => !existingSet.Contains(s.FilePath))
                .GroupBy(s => s.FilePath)
                .Select(g => g.First())
                .ToList();

            if (newSessions.Count == 0)
            {
                _logger.LogInformation("用戶 {UserId} 上傳 {Count} 筆資料均為重複，不建立審核列",
                    userId, sessions.Count);
                return new UploadRewardResponse(0, 0);
            }

            var now = DateTime.UtcNow;
            foreach (var s in newSessions)
            {
                var hasFiles = !string.IsNullOrWhiteSpace(s.UploadId);
                _db.DatasetUploads.Add(new DatasetUpload
                {
                    Id              = hasFiles ? s.UploadId! : Guid.NewGuid().ToString("N"),
                    UserId          = userId,
                    B2VideoKey      = hasFiles ? B2Service.DatasetVideoKey(s.UploadId!) : null,
                    B2CsvKey        = hasFiles ? B2Service.DatasetCsvKey(s.UploadId!) : null,
                    ClientFilePath  = s.FilePath,
                    RecordedAt      = s.RecordedAt,
                    DurationSeconds = s.DurationSeconds,
                    GoodShot        = s.GoodShot,
                    AudioCrispness  = s.AudioCrispness,
                    AudioLabel      = s.AudioLabel,
                    VideoType       = s.VideoType,
                    CreatedAt       = now,
                    Status          = DatasetUploadStatus.Pending,
                });
            }

            await _db.SaveChangesAsync();

            _logger.LogInformation("用戶 {UserId} 上傳 {Count} 筆資料（新 {New} 筆），已建立待審核列（審核通過後發球）",
                userId, sessions.Count, newSessions.Count);
            return new UploadRewardResponse(0, newSessions.Count);
        }

        /// <summary>
        /// 後台審核資料上傳：核准 → 發 +3 球（每列僅一次）；拒絕 → 標記 rejected。
        /// 已審核過的列回 null（呼叫端回 409 防重複發球）。
        /// 回傳 (found, reviewed)：found=false 表示列不存在。
        /// </summary>
        public async Task<(bool Found, bool Reviewed)> ReviewDatasetUploadAsync(
            string uploadId, bool approve, string? note)
        {
            var upload = await _db.DatasetUploads.FindAsync(uploadId);
            if (upload == null) return (false, false);

            if (upload.Status != DatasetUploadStatus.Pending)
                return (true, false);   // 已審核過，防重複發球

            var now = DateTime.UtcNow;
            upload.Status     = approve ? DatasetUploadStatus.Approved : DatasetUploadStatus.Rejected;
            upload.ReviewedAt = now;
            upload.ReviewNote = string.IsNullOrWhiteSpace(note)
                                ? null
                                : note.Trim()[..Math.Min(500, note.Trim().Length)];

            if (approve)
            {
                var user = await _db.Users.FindAsync(upload.UserId);
                if (user != null)
                {
                    user.BonusBalls += UploadBalls;
                    _db.BallRecords.Add(new BallRecord
                    {
                        UserId       = upload.UserId,
                        Reason       = BallReason.Upload,
                        Delta        = UploadBalls,
                        BalanceAfter = user.BonusBalls,
                        CreatedAt    = now,
                    });
                }
            }

            await _db.SaveChangesAsync();

            _logger.LogInformation("資料上傳 {UploadId} 審核 {Result}（用戶 {UserId}）",
                uploadId, approve ? "核准 +3 球" : "拒絕", upload.UserId);
            return (true, true);
        }

        /// <summary>
        /// 分頁查詢自己的資料上傳審核狀態（App 顯示審核中 / 已通過 / 已拒絕）
        /// </summary>
        public async Task<MyDatasetUploadsResponse?> GetMyDatasetUploadsAsync(
            string userId, int page, int pageSize)
        {
            var user = await _db.Users.FindAsync(userId);
            if (user == null) return null;

            pageSize = Math.Clamp(pageSize, 1, 100);
            page     = Math.Max(1, page);

            var query = _db.DatasetUploads
                .Where(d => d.UserId == userId)
                .OrderByDescending(d => d.CreatedAt);

            var total         = await query.CountAsync();
            var pendingCount  = await query.CountAsync(d => d.Status == DatasetUploadStatus.Pending);
            var approvedCount = await query.CountAsync(d => d.Status == DatasetUploadStatus.Approved);

            var items = await query
                .Skip((page - 1) * pageSize)
                .Take(pageSize)
                .Select(d => new MyDatasetUploadDto(
                    d.Id, d.ClientFilePath, d.Status, d.CreatedAt, d.ReviewedAt, d.ReviewNote))
                .ToListAsync();

            return new MyDatasetUploadsResponse(
                total, pendingCount, approvedCount, page, pageSize, items);
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

            var result = await ValidateSubscriptionAsync(req);
            if (!result.Success)
            {
                purchaseRecord.Status = PurchaseStatus.Failed;
                await _db.SaveChangesAsync();
                _logger.LogWarning("用戶 {UserId} 訂閱驗證失敗 store={Store}", userId, req.Store);
                return new PurchasePlanResponse(false, "訂閱驗證失敗", null);
            }

            user.Plan                     = req.Plan;
            user.SubscriptionExpiry       = result.ExpiryTime;
            user.SubscriptionStatus       = "active";
            user.SubscriptionOriginalId   = result.OriginalTransactionId;
            user.UpdatedAt                = DateTime.UtcNow;
            purchaseRecord.Status                = PurchaseStatus.Verified;
            purchaseRecord.VerifiedAt            = DateTime.UtcNow;
            purchaseRecord.OriginalTransactionId = result.OriginalTransactionId;
            purchaseRecord.ExpiresAt             = result.ExpiryTime;
            purchaseRecord.IsAutoRenewing        = result.IsAutoRenewing;
            await _db.SaveChangesAsync();

            _logger.LogInformation("用戶 {UserId} 透過 {Store} 訂閱 {Plan}，到期 {Expiry}",
                userId, req.Store, req.Plan, result.ExpiryTime);
            return new PurchasePlanResponse(true, "訂閱成功", req.Plan);
        }

        public record SubscriptionValidationResult(
            bool Success,
            DateTime? ExpiryTime = null,
            string? OriginalTransactionId = null,
            bool? IsAutoRenewing = null
        );

        private async Task<SubscriptionValidationResult> ValidateSubscriptionAsync(PurchasePlanRequest req)
        {
            if (string.IsNullOrWhiteSpace(req.PurchaseToken))
                return new SubscriptionValidationResult(false);

            return req.Store switch
            {
                "google_play" => await ValidateGooglePlaySubscriptionAsync(req.PurchaseToken, req.ProductId),
                "app_store"   => await ValidateAppStoreSubscriptionAsync(req.PurchaseToken),
                _             => new SubscriptionValidationResult(false),
            };
        }

        /// <summary>
        /// 驗證 Google Play 訂閱（subscriptions API）並回傳到期資訊。
        /// 測試模式下接受 GooglePlay:TestTokens 設定中的 token。
        /// </summary>
        public async Task<SubscriptionValidationResult> ValidateGooglePlaySubscriptionAsync(
            string purchaseToken, string? subscriptionId)
        {
            var testMode   = _config.GetValue<bool>("GooglePlay:TestMode", false);
            var testTokens = _config.GetSection("GooglePlay:TestTokens").Get<string[]>() ?? [];

            if (testMode && testTokens.Contains(purchaseToken))
            {
                _logger.LogInformation("Google Play 測試模式：接受測試 token");
                return new SubscriptionValidationResult(true,
                    ExpiryTime: DateTime.UtcNow.AddMonths(1),
                    OriginalTransactionId: "test-order-id",
                    IsAutoRenewing: true);
            }

            var packageName        = _config["GooglePlay:PackageName"];
            var serviceAccountJson = _config["GooglePlay:ServiceAccountJson"];

            if (string.IsNullOrEmpty(packageName) || string.IsNullOrEmpty(serviceAccountJson)
                || string.IsNullOrEmpty(subscriptionId))
            {
                _logger.LogWarning("Google Play 配置不完整（PackageName / ServiceAccountJson / subscriptionId）");
                return new SubscriptionValidationResult(false);
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

                // subscriptions API（非 products API）
                var url = $"https://androidpublisher.googleapis.com/androidpublisher/v3/applications/" +
                          $"{packageName}/purchases/subscriptions/{subscriptionId}/tokens/{purchaseToken}";
                var response = await client.GetAsync(url);

                if (!response.IsSuccessStatusCode)
                {
                    _logger.LogWarning("Google Play 訂閱 API 回應錯誤: {Status}", response.StatusCode);
                    return new SubscriptionValidationResult(false);
                }

                var json = await response.Content.ReadAsStringAsync();
                using var doc = System.Text.Json.JsonDocument.Parse(json);
                var root = doc.RootElement;

                // paymentState: 0=pending, 1=received, 2=free trial
                var paymentState = root.TryGetProperty("paymentState", out var ps) ? ps.GetInt32() : -1;
                if (paymentState != 1 && paymentState != 2)
                {
                    _logger.LogWarning("Google Play 訂閱付款狀態異常: {State}", paymentState);
                    return new SubscriptionValidationResult(false);
                }

                var expiryMs = root.TryGetProperty("expiryTimeMillis", out var exp)
                    ? long.Parse(exp.GetString()!)
                    : 0L;
                var expiryTime = DateTimeOffset.FromUnixTimeMilliseconds(expiryMs).UtcDateTime;

                var orderId = root.TryGetProperty("orderId", out var oid) ? oid.GetString() : null;
                var autoRenewing = root.TryGetProperty("autoRenewing", out var ar) && ar.GetBoolean();

                return new SubscriptionValidationResult(true, expiryTime, orderId, autoRenewing);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Google Play 訂閱驗證失敗");
                return new SubscriptionValidationResult(false);
            }
        }

        /// <summary>
        /// 驗證 Apple App Store 訂閱收據（verifyReceipt）並回傳到期資訊。
        /// 注意：Apple 已宣布棄用此 API，未來應遷移至 App Store Server API。
        /// </summary>
        public async Task<SubscriptionValidationResult> ValidateAppStoreSubscriptionAsync(string receiptData)
        {
            var sharedSecret = _config["AppStore:SharedSecret"];
            var isSandbox    = _config.GetValue<bool>("AppStore:Sandbox", false);

            if (string.IsNullOrEmpty(sharedSecret))
            {
                _logger.LogWarning("App Store 配置不完整（缺少 SharedSecret）");
                return new SubscriptionValidationResult(false);
            }

            try
            {
                var client = _httpClientFactory.CreateClient();
                var body   = new { receipt_data = receiptData, password = sharedSecret };

                var url  = isSandbox
                    ? "https://sandbox.itunes.apple.com/verifyReceipt"
                    : "https://buy.itunes.apple.com/verifyReceipt";
                var resp = await client.PostAsJsonAsync(url, body);

                if (!resp.IsSuccessStatusCode)
                {
                    _logger.LogWarning("App Store API 回應錯誤: {Status}", resp.StatusCode);
                    return new SubscriptionValidationResult(false);
                }

                var json = await resp.Content.ReadAsStringAsync();
                using var doc = System.Text.Json.JsonDocument.Parse(json);
                var root   = doc.RootElement;
                var status = root.GetProperty("status").GetInt32();

                // status 21007 = sandbox receipt sent to production → retry sandbox
                if (status == 21007 && !isSandbox)
                {
                    _logger.LogInformation("App Store：偵測到 sandbox 收據，切換重試");
                    var sr = await client.PostAsJsonAsync(
                        "https://sandbox.itunes.apple.com/verifyReceipt", body);
                    if (!sr.IsSuccessStatusCode) return new SubscriptionValidationResult(false);
                    using var sd = System.Text.Json.JsonDocument.Parse(await sr.Content.ReadAsStringAsync());
                    root   = sd.RootElement.Clone();
                    status = root.GetProperty("status").GetInt32();
                }

                if (status != 0) return new SubscriptionValidationResult(false);

                // latest_receipt_info 是陣列，取最後一筆（最新 renewal）
                if (!root.TryGetProperty("latest_receipt_info", out var receiptInfoArr)
                    || receiptInfoArr.GetArrayLength() == 0)
                    return new SubscriptionValidationResult(false);

                // 找到最大 expires_date_ms
                JsonElement latestItem = default;
                bool foundLatest = false;
                long latestExpiry = 0;
                foreach (var item in receiptInfoArr.EnumerateArray())
                {
                    if (item.TryGetProperty("expires_date_ms", out var edMs)
                        && long.TryParse(edMs.GetString(), out var ms) && ms > latestExpiry)
                    {
                        latestExpiry = ms;
                        latestItem   = item;
                        foundLatest  = true;
                    }
                }
                if (!foundLatest) return new SubscriptionValidationResult(false);

                var expiryTime = DateTimeOffset.FromUnixTimeMilliseconds(latestExpiry).UtcDateTime;
                var originalTxId = latestItem.TryGetProperty("original_transaction_id", out var otid)
                    ? otid.GetString() : null;

                // pending_renewal_info で autoRenewStatus 確認
                var autoRenewing = false;
                if (root.TryGetProperty("pending_renewal_info", out var renewalArr))
                    foreach (var r in renewalArr.EnumerateArray())
                        if (r.TryGetProperty("auto_renew_status", out var ars))
                            autoRenewing = ars.GetString() == "1";

                return new SubscriptionValidationResult(true, expiryTime, originalTxId, autoRenewing);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "App Store 訂閱驗證失敗");
                return new SubscriptionValidationResult(false);
            }
        }

        /// <summary>
        /// 驗證 Google Play 一次性商品（products API，球數包等 consumable）。
        /// 測試模式下接受 GooglePlay:TestTokens 設定中的 token。
        /// </summary>
        public async Task<BallPackValidationResult> ValidateGooglePlayProductAsync(
            string purchaseToken, string productId)
        {
            var testMode   = _config.GetValue<bool>("GooglePlay:TestMode", false);
            var testTokens = _config.GetSection("GooglePlay:TestTokens").Get<string[]>() ?? [];

            if (testMode && testTokens.Contains(purchaseToken))
            {
                _logger.LogInformation("Google Play 測試模式：接受球包測試 token");
                return new BallPackValidationResult(true, $"test-{Guid.NewGuid()}");
            }

            var packageName        = _config["GooglePlay:PackageName"];
            var serviceAccountJson = _config["GooglePlay:ServiceAccountJson"];

            if (string.IsNullOrEmpty(packageName) || string.IsNullOrEmpty(serviceAccountJson))
            {
                _logger.LogWarning("Google Play 配置不完整（PackageName / ServiceAccountJson）");
                return new BallPackValidationResult(false);
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

                // products API（一次性商品；訂閱走 subscriptions API）
                var url = $"https://androidpublisher.googleapis.com/androidpublisher/v3/applications/" +
                          $"{packageName}/purchases/products/{productId}/tokens/{purchaseToken}";
                var response = await client.GetAsync(url);

                if (!response.IsSuccessStatusCode)
                {
                    _logger.LogWarning("Google Play 商品 API 回應錯誤: {Status}", response.StatusCode);
                    return new BallPackValidationResult(false);
                }

                var json = await response.Content.ReadAsStringAsync();
                using var doc = System.Text.Json.JsonDocument.Parse(json);
                var root = doc.RootElement;

                // purchaseState: 0=purchased, 1=canceled, 2=pending
                var purchaseState = root.TryGetProperty("purchaseState", out var st) ? st.GetInt32() : -1;
                if (purchaseState != 0)
                {
                    _logger.LogWarning("Google Play 商品購買狀態異常: {State}", purchaseState);
                    return new BallPackValidationResult(false);
                }

                var orderId = root.TryGetProperty("orderId", out var oid) ? oid.GetString() : null;
                return new BallPackValidationResult(true, orderId);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Google Play 球包驗證失敗");
                return new BallPackValidationResult(false);
            }
        }

        /// <summary>
        /// 驗證 Apple App Store 一次性商品（verifyReceipt，於 in_app 陣列中比對 product_id）。
        /// 回傳該筆交易的 transaction_id 供去重。
        /// </summary>
        public async Task<BallPackValidationResult> ValidateAppStoreProductAsync(
            string receiptData, string productId)
        {
            var sharedSecret = _config["AppStore:SharedSecret"];
            var isSandbox    = _config.GetValue<bool>("AppStore:Sandbox", false);

            if (string.IsNullOrEmpty(sharedSecret))
            {
                _logger.LogWarning("App Store 配置不完整（缺少 SharedSecret）");
                return new BallPackValidationResult(false);
            }

            try
            {
                var client = _httpClientFactory.CreateClient();
                var body   = new { receipt_data = receiptData, password = sharedSecret };

                var url  = isSandbox
                    ? "https://sandbox.itunes.apple.com/verifyReceipt"
                    : "https://buy.itunes.apple.com/verifyReceipt";
                var resp = await client.PostAsJsonAsync(url, body);

                if (!resp.IsSuccessStatusCode)
                {
                    _logger.LogWarning("App Store API 回應錯誤: {Status}", resp.StatusCode);
                    return new BallPackValidationResult(false);
                }

                var json = await resp.Content.ReadAsStringAsync();
                using var doc = System.Text.Json.JsonDocument.Parse(json);
                var root   = doc.RootElement;
                var status = root.GetProperty("status").GetInt32();

                // status 21007 = sandbox receipt sent to production → retry sandbox
                if (status == 21007 && !isSandbox)
                {
                    _logger.LogInformation("App Store：偵測到 sandbox 收據，切換重試");
                    var sr = await client.PostAsJsonAsync(
                        "https://sandbox.itunes.apple.com/verifyReceipt", body);
                    if (!sr.IsSuccessStatusCode) return new BallPackValidationResult(false);
                    using var sd = System.Text.Json.JsonDocument.Parse(await sr.Content.ReadAsStringAsync());
                    root   = sd.RootElement.Clone();
                    status = root.GetProperty("status").GetInt32();
                }

                if (status != 0) return new BallPackValidationResult(false);

                if (!root.TryGetProperty("receipt", out var receipt)
                    || !receipt.TryGetProperty("in_app", out var inApp))
                    return new BallPackValidationResult(false);

                // 取該商品最新一筆交易（同 receipt 可能含多次購買，靠 transaction_id 去重）
                string? latestTxId = null;
                long latestPurchaseMs = -1;
                foreach (var item in inApp.EnumerateArray())
                {
                    if (!item.TryGetProperty("product_id", out var pid)
                        || pid.GetString() != productId) continue;

                    var ms = item.TryGetProperty("purchase_date_ms", out var pd)
                        && long.TryParse(pd.GetString(), out var v) ? v : 0;
                    if (ms > latestPurchaseMs)
                    {
                        latestPurchaseMs = ms;
                        latestTxId = item.TryGetProperty("transaction_id", out var tid)
                            ? tid.GetString() : null;
                    }
                }

                if (latestTxId == null)
                {
                    _logger.LogWarning("App Store 收據中無 {ProductId} 交易", productId);
                    return new BallPackValidationResult(false);
                }

                return new BallPackValidationResult(true, latestTxId);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "App Store 球包驗證失敗");
                return new BallPackValidationResult(false);
            }
        }

        // ════════════════════════════════════════════════════════════════
        // 球數購買
        // ════════════════════════════════════════════════════════════════

        private static readonly Dictionary<string, int> _ballPackMap = new()
        {
            ["golf_balls_1"]   = 1,
            ["golf_balls_5"]   = 5,
            ["golf_balls_10"]  = 10,
            ["golf_balls_50"]  = 50,
            ["golf_balls_100"] = 100,
        };

        public record BallPackValidationResult(bool Success, string? TransactionId = null);

        public async Task<PurchaseBallsResponse> PurchaseBallsAsync(string userId, PurchaseBallsRequest req)
        {
            if (!_ballPackMap.TryGetValue(req.ProductId, out var balls))
                return new PurchaseBallsResponse(false, "無效的球包商品", 0, 0);

            if (string.IsNullOrWhiteSpace(req.PurchaseToken)
                || req.Store is not ("google_play" or "app_store"))
                return new PurchaseBallsResponse(false, "無效的購買憑證", 0, 0);

            var user = await _db.Users.FindAsync(userId);
            if (user == null) return new PurchaseBallsResponse(false, "用戶不存在", 0, 0);

            var testMode = _config.GetValue<bool>("GooglePlay:TestMode", false);

            // 同一 purchaseToken 已入帳 → 冪等回應，避免 client 重試佇列重複加值
            if (!testMode)
            {
                var dupToken = await _db.PurchaseRecords.FirstOrDefaultAsync(r =>
                    r.Plan == "balls"
                    && r.PurchaseToken == req.PurchaseToken
                    && r.Status == PurchaseStatus.Verified);
                if (dupToken != null)
                {
                    if (dupToken.UserId != userId)
                        return new PurchaseBallsResponse(false, "此購買憑證已被使用", 0, 0);
                    return new PurchaseBallsResponse(true, "此購買已入帳", 0, user.BonusBalls);
                }
            }

            var record = new PurchaseRecord
            {
                UserId        = userId,
                Plan          = "balls",
                Store         = req.Store,
                ProductId     = req.ProductId,
                PurchaseToken = req.PurchaseToken,
                Status        = PurchaseStatus.Pending,
                CreatedAt     = DateTime.UtcNow,
            };
            _db.PurchaseRecords.Add(record);
            await _db.SaveChangesAsync();

            var result = req.Store == "google_play"
                ? await ValidateGooglePlayProductAsync(req.PurchaseToken, req.ProductId)
                : await ValidateAppStoreProductAsync(req.PurchaseToken, req.ProductId);

            if (!result.Success)
            {
                record.Status = PurchaseStatus.Failed;
                await _db.SaveChangesAsync();
                _logger.LogWarning("用戶 {UserId} 球包驗證失敗 store={Store} product={ProductId}",
                    userId, req.Store, req.ProductId);
                return new PurchaseBallsResponse(false, "球包驗證失敗", 0, 0);
            }

            // App Store 的 token 是整份 receipt（內容會隨後續購買變動），需另以 transaction_id 去重
            if (!testMode && result.TransactionId != null)
            {
                var dupTx = await _db.PurchaseRecords.FirstOrDefaultAsync(r =>
                    r.Plan == "balls"
                    && r.OriginalTransactionId == result.TransactionId
                    && r.Status == PurchaseStatus.Verified
                    && r.Id != record.Id);
                if (dupTx != null)
                {
                    record.Status = PurchaseStatus.Failed;
                    await _db.SaveChangesAsync();
                    if (dupTx.UserId != userId)
                        return new PurchaseBallsResponse(false, "此購買憑證已被使用", 0, 0);
                    return new PurchaseBallsResponse(true, "此購買已入帳", 0, user.BonusBalls);
                }
            }

            record.Status                = PurchaseStatus.Verified;
            record.VerifiedAt            = DateTime.UtcNow;
            record.OriginalTransactionId = result.TransactionId;

            user.BonusBalls += balls;
            user.UpdatedAt   = DateTime.UtcNow;

            _db.BallRecords.Add(new BallRecord
            {
                UserId       = userId,
                Reason       = BallReason.Purchase,
                Delta        = balls,
                BalanceAfter = user.BonusBalls,
                CreatedAt    = DateTime.UtcNow,
            });

            await _db.SaveChangesAsync();
            _logger.LogInformation("用戶 {UserId} 購買 {ProductId} +{Balls} 球，新餘額 {Balance}",
                userId, req.ProductId, balls, user.BonusBalls);

            return new PurchaseBallsResponse(true, $"成功購買 {balls} 球", balls, user.BonusBalls);
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
