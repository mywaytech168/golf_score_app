using Microsoft.EntityFrameworkCore;
using UploadServer.Constants;
using UploadServer.Models;

namespace UploadServer.Data
{
    /// <summary>
    /// 開發/測試用帳號 Seeder（僅在 Development 環境執行）
    /// 執行時機：Program.cs 中 app.Environment.IsDevelopment() 區塊
    /// </summary>
    public static class TestDataSeeder
    {
        private static readonly DateOnly Today = DateOnly.FromDateTime(
            TimeZoneInfo.ConvertTimeFromUtc(DateTime.UtcNow,
                TimeZoneInfo.FindSystemTimeZoneById("China Standard Time")));

        public static async Task SeedAsync(VideoDbContext db, ILogger logger)
        {
            var accounts = BuildAccounts();

            foreach (var (user, auth) in accounts)
            {
                if (await db.Users.AnyAsync(u => u.Email == user.Email))
                    continue;

                db.Users.Add(user);
                db.UserAuths.Add(auth);
                logger.LogInformation("🌱 Seed: 建立測試帳號 [{Username}] plan={Plan}", user.Username, user.Plan);
            }

            await db.SaveChangesAsync();

            await SeedInviteRelationAsync(db, logger);

            logger.LogInformation("✅ TestDataSeeder 完成");
        }

        // ----------------------------------------------------------------
        // 帳號定義
        // ----------------------------------------------------------------
        private static List<(User user, UserAuth auth)> BuildAccounts() => new()
        {
            // A - 全新 Free 用戶（今日 0 次）
            MakeLocal("test_free",       "test_free@orvia.dev",       "Test1234!",
                      "測試Free用戶",    "free",  bonusBalls: 0,  todayUsed: 0),

            // B - Free 今日配額用完（10/10）
            MakeLocal("test_free_full",  "test_free_full@orvia.dev",  "Test1234!",
                      "Free配額耗盡",   "free",  bonusBalls: 0,  todayUsed: 10, setTodayDate: true),

            // B2 - Free 今日耗盡但有 Bonus Ball
            MakeLocal("test_free_balls", "test_free_balls@orvia.dev", "Test1234!",
                      "Free有BonusBall","free",  bonusBalls: 15, todayUsed: 10, setTodayDate: true),

            // B3 - Free 今日廣告獎勵也用完（adClaimedToday=5）
            MakeLocal("test_ad_full",    "test_ad_full@orvia.dev",    "Test1234!",
                      "廣告獎勵耗盡",   "free",  bonusBalls: 25, todayUsed: 10,
                      setTodayDate: true, adClaimedToday: 5),

            // C - Pro 用戶接近每日上限（88/90）
            MakeLocal("test_pro",        "test_pro@orvia.dev",        "Test1234!",
                      "Pro接近上限",     "pro",   bonusBalls: 0,  todayUsed: 88, setTodayDate: true),

            // D - Elite 用戶（無限制）
            MakeLocal("test_elite",      "test_elite@orvia.dev",      "Test1234!",
                      "Elite教練",       "elite", bonusBalls: 0,  todayUsed: 0),

            // E - 被停權帳號
            MakeLocal("test_suspended",  "test_suspended@orvia.dev",  "Test1234!",
                      "停權帳號",        "free",  bonusBalls: 0,  todayUsed: 0,
                      status: UserStatus.Suspended),

            // G - 分享功能測試者
            MakeLocal("test_sharer",     "test_sharer@orvia.dev",     "Test1234!",
                      "分享測試",        "pro",   bonusBalls: 0,  todayUsed: 0),

            // H - AI Coach 分析測試者
            MakeLocal("test_aicoach",    "test_aicoach@orvia.dev",    "Test1234!",
                      "AI教練測試",      "pro",   bonusBalls: 0,  todayUsed: 0),

            // I - IAP 購買測試者
            MakeLocal("test_iap",        "test_iap@orvia.dev",        "Test1234!",
                      "購買測試",        "free",  bonusBalls: 0,  todayUsed: 0),

            // J - 邀請者（invite_code = TESTINVITE0001）
            MakeLocal("test_inviter",    "test_inviter@orvia.dev",    "Test1234!",
                      "邀請者",          "free",  bonusBalls: 0,  todayUsed: 0,
                      inviteCode: "TESTINVITE0001"),

            // J - 被邀請者（尚未使用邀請碼，保持空白供測試用）
            MakeLocal("test_invitee",    "test_invitee@orvia.dev",    "Test1234!",
                      "被邀請者",        "free",  bonusBalls: 0,  todayUsed: 0),

            // F - 用於 Token 測試（正常帳號，搭配手動過期 token 測試）
            MakeLocal("test_token",      "test_token@orvia.dev",      "Test1234!",
                      "Token測試",       "free",  bonusBalls: 0,  todayUsed: 0),
        };

        // ----------------------------------------------------------------
        // 邀請關係 Seed（test_inviter 已成功邀請 test_invitee 的狀態）
        // 需在兩個帳號都建立後才能執行
        // ----------------------------------------------------------------
        private static async Task SeedInviteRelationAsync(VideoDbContext db, ILogger logger)
        {
            var inviter = await db.Users.FirstOrDefaultAsync(u => u.Username == "test_inviter");
            var invitee = await db.Users.FirstOrDefaultAsync(u => u.Username == "test_invitee");

            if (inviter == null || invitee == null) return;

            if (await db.InviteRecords.AnyAsync(r => r.InviteeUserId == invitee.Id)) return;

            // 已完成邀請：雙方各 +5 balls
            var record = new InviteRecord
            {
                InviterUserId = inviter.Id,
                InviteeUserId = invitee.Id,
                InviteCode    = "TESTINVITE0001",
                InviterBalls  = 5,
                InviteeBalls  = 5,
                CreatedAt     = DateTime.UtcNow,
            };

            inviter.BonusBalls  += 5;
            inviter.InviteCount += 1;
            invitee.BonusBalls  += 5;
            invitee.InvitedByCode = "TESTINVITE0001";

            db.InviteRecords.Add(record);
            await db.SaveChangesAsync();

            logger.LogInformation("🌱 Seed: 邀請關係建立完成 inviter={Inviter} invitee={Invitee}",
                inviter.Username, invitee.Username);
        }

        // ----------------------------------------------------------------
        // 工廠方法
        // ----------------------------------------------------------------
        private static (User, UserAuth) MakeLocal(
            string username,
            string email,
            string password,
            string displayName,
            string plan,
            int bonusBalls,
            int todayUsed,
            bool setTodayDate    = false,
            int adClaimedToday   = 0,
            string status        = UserStatus.Active,
            string? inviteCode   = null)
        {
            var now  = DateTime.UtcNow;
            var user = new User
            {
                Username          = username,
                Email             = email,
                DisplayName       = displayName,
                Status            = status,
                Plan              = plan,
                BonusBalls        = bonusBalls,
                TodayUsed         = todayUsed,
                TodayUsedDate     = setTodayDate ? DateOnly.FromDateTime(
                    TimeZoneInfo.ConvertTimeFromUtc(now,
                        TimeZoneInfo.FindSystemTimeZoneById("China Standard Time"))) : null,
                AdClaimedToday    = adClaimedToday,
                AdClaimedDate     = adClaimedToday > 0 ? DateOnly.FromDateTime(
                    TimeZoneInfo.ConvertTimeFromUtc(now,
                        TimeZoneInfo.FindSystemTimeZoneById("China Standard Time"))) : null,
                InviteCode        = inviteCode,
                CreatedAt         = now,
                UpdatedAt         = now,
            };

            var auth = new UserAuth
            {
                UserId         = user.Id,
                Provider       = AuthProvider.Local,
                ProviderUserId = email,
                CredentialHash = BCrypt.Net.BCrypt.HashPassword(password),
                CreatedAt      = now,
            };

            return (user, auth);
        }
    }
}
