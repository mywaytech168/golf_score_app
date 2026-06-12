using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging.Abstractions;
using UploadServer.Constants;
using UploadServer.Data;
using UploadServer.DTOs;
using UploadServer.Models;
using UploadServer.Services;

namespace UploadServer.Tests
{
    /// <summary>
    /// PurchaseBallsAsync 測試：商店驗證閘門、測試模式入帳、token 去重（冪等 / 跨用戶盜用）。
    /// 透過 GooglePlay:TestMode + TestTokens 走測試驗證路徑，不打外部 API。
    /// </summary>
    public class PurchaseBallsTests : IDisposable
    {
        private readonly SqliteConnection _connection;
        private readonly VideoDbContext _db;

        private class DummyHttpClientFactory : IHttpClientFactory
        {
            public HttpClient CreateClient(string name) => new();
        }

        public PurchaseBallsTests()
        {
            _connection = new SqliteConnection("DataSource=:memory:");
            _connection.Open();

            var options = new DbContextOptionsBuilder<VideoDbContext>()
                .UseSqlite(_connection)
                .Options;
            _db = new VideoDbContext(options);
            _db.Database.EnsureCreated();
        }

        public void Dispose()
        {
            _db.Dispose();
            _connection.Dispose();
        }

        private UserService CreateService(bool testMode)
        {
            var config = new ConfigurationBuilder()
                .AddInMemoryCollection(new Dictionary<string, string?>
                {
                    ["GooglePlay:TestMode"] = testMode ? "true" : "false",
                    ["GooglePlay:TestTokens:0"] = "test_purchased",
                })
                .Build();

            return new UserService(_db, NullLogger<UserService>.Instance,
                new DummyHttpClientFactory(), config);
        }

        private async Task<User> SeedUserAsync(string id = "u1")
        {
            var user = new User
            {
                Id = id,
                Username = $"{id}@test.com",
                Email = $"{id}@test.com",
                DisplayName = "Test User",
                BonusBalls = 0,
                CreatedAt = DateTime.UtcNow,
                UpdatedAt = DateTime.UtcNow,
            };
            _db.Users.Add(user);
            await _db.SaveChangesAsync();
            return user;
        }

        [Fact]
        public async Task PurchaseBalls_InvalidProduct_Fails()
        {
            await SeedUserAsync();
            var service = CreateService(testMode: true);

            var resp = await service.PurchaseBallsAsync("u1",
                new PurchaseBallsRequest("orvia_golf_balls_999", "google_play", "test_purchased"));

            Assert.False(resp.Success);
        }

        [Fact]
        public async Task PurchaseBalls_EmptyToken_Fails()
        {
            await SeedUserAsync();
            var service = CreateService(testMode: true);

            var resp = await service.PurchaseBallsAsync("u1",
                new PurchaseBallsRequest("orvia_golf_balls_10", "google_play", ""));

            Assert.False(resp.Success);
        }

        [Fact]
        public async Task PurchaseBalls_InvalidStore_Fails()
        {
            await SeedUserAsync();
            var service = CreateService(testMode: true);

            var resp = await service.PurchaseBallsAsync("u1",
                new PurchaseBallsRequest("orvia_golf_balls_10", "unknown_store", "test_purchased"));

            Assert.False(resp.Success);
        }

        [Fact]
        public async Task PurchaseBalls_TestMode_AddsBallsAndRecordsVerified()
        {
            await SeedUserAsync();
            var service = CreateService(testMode: true);

            var resp = await service.PurchaseBallsAsync("u1",
                new PurchaseBallsRequest("orvia_golf_balls_10", "google_play", "test_purchased"));

            Assert.True(resp.Success);
            Assert.Equal(10, resp.BallsAdded);
            Assert.Equal(10, resp.NewBalance);

            var record = await _db.PurchaseRecords.SingleAsync();
            Assert.Equal(PurchaseStatus.Verified, record.Status);
            Assert.Equal("balls", record.Plan);
            Assert.Equal("orvia_golf_balls_10", record.ProductId);
        }

        [Fact]
        public async Task PurchaseBalls_ProductionMode_UnverifiableToken_DoesNotAddBalls()
        {
            await SeedUserAsync();
            var service = CreateService(testMode: false);  // 無 ServiceAccountJson → 驗證必失敗

            var resp = await service.PurchaseBallsAsync("u1",
                new PurchaseBallsRequest("orvia_golf_balls_100", "google_play", "fake_token"));

            Assert.False(resp.Success);
            var user = await _db.Users.FindAsync("u1");
            Assert.Equal(0, user!.BonusBalls);
            var record = await _db.PurchaseRecords.SingleAsync();
            Assert.Equal(PurchaseStatus.Failed, record.Status);
        }

        [Fact]
        public async Task PurchaseBalls_DuplicateToken_SameUser_IsIdempotent()
        {
            await SeedUserAsync();
            // 先以測試模式入帳一筆
            var resp1 = await CreateService(testMode: true).PurchaseBallsAsync("u1",
                new PurchaseBallsRequest("orvia_golf_balls_10", "google_play", "test_purchased"));
            Assert.True(resp1.Success);

            // 再以正式模式重送同一 token：應冪等回應、不重複加值
            var resp2 = await CreateService(testMode: false).PurchaseBallsAsync("u1",
                new PurchaseBallsRequest("orvia_golf_balls_10", "google_play", "test_purchased"));

            Assert.True(resp2.Success);
            Assert.Equal(0, resp2.BallsAdded);
            var user = await _db.Users.FindAsync("u1");
            Assert.Equal(10, user!.BonusBalls);
        }

        [Fact]
        public async Task PurchaseBalls_DuplicateToken_OtherUser_Rejected()
        {
            await SeedUserAsync("u1");
            await SeedUserAsync("u2");

            var resp1 = await CreateService(testMode: true).PurchaseBallsAsync("u1",
                new PurchaseBallsRequest("orvia_golf_balls_10", "google_play", "test_purchased"));
            Assert.True(resp1.Success);

            var resp2 = await CreateService(testMode: false).PurchaseBallsAsync("u2",
                new PurchaseBallsRequest("orvia_golf_balls_10", "google_play", "test_purchased"));

            Assert.False(resp2.Success);
            var u2 = await _db.Users.FindAsync("u2");
            Assert.Equal(0, u2!.BonusBalls);
        }
    }
}
