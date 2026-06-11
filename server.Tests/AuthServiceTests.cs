using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging.Abstractions;
using UploadServer.Constants;
using UploadServer.Data;
using UploadServer.Models;
using UploadServer.Services;

namespace UploadServer.Tests
{
    /// <summary>
    /// AuthService 整合測試：SQLite in-memory 取代 MySQL，
    /// 涵蓋 Google 綁定、設定密碼、修改密碼三條路徑。
    /// </summary>
    public class AuthServiceTests : IDisposable
    {
        private readonly SqliteConnection _connection;
        private readonly VideoDbContext _db;
        private readonly AuthService _service;

        public AuthServiceTests()
        {
            _connection = new SqliteConnection("DataSource=:memory:");
            _connection.Open();

            var options = new DbContextOptionsBuilder<VideoDbContext>()
                .UseSqlite(_connection)
                .Options;
            _db = new VideoDbContext(options);
            _db.Database.EnsureCreated();

            var config = new ConfigurationBuilder()
                .AddInMemoryCollection(new Dictionary<string, string?>
                {
                    ["Jwt:Secret"] = "unit_test_secret_key_at_least_32_chars!!",
                    ["Jwt:ExpiryMinutes"] = "60",
                })
                .Build();

            _service = new AuthService(_db, config, NullLogger<AuthService>.Instance);
        }

        public void Dispose()
        {
            _db.Dispose();
            _connection.Dispose();
        }

        private async Task<User> SeedUserAsync(
            string id = "u1", string email = "u1@test.com",
            string? localPassword = null, string? googleId = null)
        {
            var user = new User
            {
                Id = id,
                Username = email,
                Email = email,
                DisplayName = "Test User",
                CreatedAt = DateTime.UtcNow,
                UpdatedAt = DateTime.UtcNow,
            };
            _db.Users.Add(user);

            if (localPassword != null)
            {
                _db.UserAuths.Add(new UserAuth
                {
                    UserId = id,
                    Provider = AuthProvider.Local,
                    ProviderUserId = email,
                    CredentialHash = BCrypt.Net.BCrypt.HashPassword(localPassword),
                });
            }
            if (googleId != null)
            {
                _db.UserAuths.Add(new UserAuth
                {
                    UserId = id,
                    Provider = AuthProvider.Google,
                    ProviderUserId = googleId,
                });
            }
            await _db.SaveChangesAsync();
            return user;
        }

        // ── LinkGoogleAsync ──────────────────────────────────────────

        [Fact]
        public async Task LinkGoogle_NewBinding_Succeeds()
        {
            await SeedUserAsync(localPassword: "Abcd1234");

            var (success, error) = await _service.LinkGoogleAsync("u1", "g-123");

            Assert.True(success, error);
            var auth = await _db.UserAuths.SingleAsync(
                a => a.UserId == "u1" && a.Provider == AuthProvider.Google);
            Assert.Equal("g-123", auth.ProviderUserId);
        }

        [Fact]
        public async Task LinkGoogle_SameUserSameGoogleId_IsIdempotent()
        {
            await SeedUserAsync(googleId: "g-123");

            var (success, error) = await _service.LinkGoogleAsync("u1", "g-123");

            Assert.True(success, error);
            Assert.Equal(1, await _db.UserAuths.CountAsync(
                a => a.UserId == "u1" && a.Provider == AuthProvider.Google));
        }

        [Fact]
        public async Task LinkGoogle_GoogleIdBoundToOtherUser_Fails()
        {
            await SeedUserAsync(id: "u1", email: "u1@test.com", googleId: "g-123");
            await SeedUserAsync(id: "u2", email: "u2@test.com", localPassword: "Abcd1234");

            var (success, error) = await _service.LinkGoogleAsync("u2", "g-123");

            Assert.False(success);
            Assert.Contains("已綁定其他帳號", error);
        }

        [Fact]
        public async Task LinkGoogle_UserAlreadyHasAnotherGoogle_Fails()
        {
            await SeedUserAsync(googleId: "g-old");

            var (success, error) = await _service.LinkGoogleAsync("u1", "g-new");

            Assert.False(success);
            Assert.Contains("已綁定其他 Google 帳號", error);
        }

        [Fact]
        public async Task LinkGoogle_UnknownUser_Fails()
        {
            var (success, error) = await _service.LinkGoogleAsync("nobody", "g-123");

            Assert.False(success);
            Assert.Equal("用戶不存在", error);
        }

        // ── AppleLoginAsync ──────────────────────────────────────────

        [Fact]
        public async Task AppleLogin_FirstAuth_CreatesUserWithEmail()
        {
            var (success, _, _, user, error) = await _service.AppleLoginAsync(
                "apple-sub-001", "relay@privaterelay.appleid.com", "Hung Chen");

            Assert.True(success, error);
            Assert.Equal("relay@privaterelay.appleid.com", user.Email);
            Assert.Equal("Hung Chen", user.DisplayName);
            Assert.NotNull(await _db.UserAuths.SingleOrDefaultAsync(
                a => a.Provider == AuthProvider.Apple && a.ProviderUserId == "apple-sub-001"));
        }

        [Fact]
        public async Task AppleLogin_SubsequentLoginWithoutEmail_FindsSameUser()
        {
            var (_, _, _, first, _) = await _service.AppleLoginAsync(
                "apple-sub-001", "relay@privaterelay.appleid.com", "Hung Chen");

            // 後續登入 Apple 不再給 email/displayName
            var (success, _, _, again, error) = await _service.AppleLoginAsync(
                "apple-sub-001", null, null);

            Assert.True(success, error);
            Assert.Equal(first.Id, again.Id);
            Assert.Equal(1, await _db.Users.CountAsync());
        }

        [Fact]
        public async Task AppleLogin_SameEmailAsExistingUser_MergesAccount()
        {
            await SeedUserAsync(localPassword: "Abcd1234"); // u1@test.com

            var (success, _, _, user, error) = await _service.AppleLoginAsync(
                "apple-sub-002", "u1@test.com", null);

            Assert.True(success, error);
            Assert.Equal("u1", user.Id);
            Assert.Equal(2, await _db.UserAuths.CountAsync(a => a.UserId == "u1"));
        }

        [Fact]
        public async Task AppleLogin_NoEmailNoRecord_CreatesPlaceholderUser()
        {
            var (success, _, _, user, error) = await _service.AppleLoginAsync(
                "apple-sub-003-long-id", null, null);

            Assert.True(success, error);
            Assert.StartsWith("apple_", user.Email);
            Assert.EndsWith("@apple.local", user.Email);
        }

        // ── SetPasswordAsync ─────────────────────────────────────────

        [Fact]
        public async Task SetPassword_PureOAuthAccount_CreatesLocalAuth()
        {
            await SeedUserAsync(googleId: "g-123");

            var (success, error) = await _service.SetPasswordAsync("u1", "Abcd1234");

            Assert.True(success, error);
            var auth = await _db.UserAuths.SingleAsync(
                a => a.UserId == "u1" && a.Provider == AuthProvider.Local);
            Assert.Equal("u1@test.com", auth.ProviderUserId);
            Assert.True(BCrypt.Net.BCrypt.Verify("Abcd1234", auth.CredentialHash));
        }

        [Fact]
        public async Task SetPassword_AlreadyHasLocalPassword_Fails()
        {
            await SeedUserAsync(localPassword: "Abcd1234");

            var (success, error) = await _service.SetPasswordAsync("u1", "Efgh5678");

            Assert.False(success);
            Assert.Contains("已設定密碼", error);
        }

        [Fact]
        public async Task SetPassword_UnknownUser_Fails()
        {
            var (success, error) = await _service.SetPasswordAsync("nobody", "Abcd1234");

            Assert.False(success);
            Assert.Equal("用戶不存在", error);
        }

        // ── ChangePasswordAsync ──────────────────────────────────────

        [Fact]
        public async Task ChangePassword_CorrectOldPassword_UpdatesHash()
        {
            await SeedUserAsync(localPassword: "Abcd1234");

            var (success, error) = await _service.ChangePasswordAsync("u1", "Abcd1234", "Efgh5678");

            Assert.True(success, error);
            var auth = await _db.UserAuths.SingleAsync(
                a => a.UserId == "u1" && a.Provider == AuthProvider.Local);
            Assert.True(BCrypt.Net.BCrypt.Verify("Efgh5678", auth.CredentialHash));
        }

        [Fact]
        public async Task ChangePassword_WrongOldPassword_Fails()
        {
            await SeedUserAsync(localPassword: "Abcd1234");

            var (success, error) = await _service.ChangePasswordAsync("u1", "Wrong000", "Efgh5678");

            Assert.False(success);
            Assert.Equal("舊密碼錯誤", error);
        }

        [Fact]
        public async Task ChangePassword_PureOAuthAccount_Fails()
        {
            await SeedUserAsync(googleId: "g-123");

            var (success, error) = await _service.ChangePasswordAsync("u1", "Abcd1234", "Efgh5678");

            Assert.False(success);
            Assert.Equal("此帳號未設定本地密碼", error);
        }

        [Fact]
        public async Task ChangePassword_TooShortNewPassword_Fails()
        {
            await SeedUserAsync(localPassword: "Abcd1234");

            var (success, error) = await _service.ChangePasswordAsync("u1", "Abcd1234", "Ab1");

            Assert.False(success);
            Assert.Contains("至少 8 位", error);
        }
    }
}
