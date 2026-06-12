using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging.Abstractions;
using UploadServer.Data;
using UploadServer.Models;
using UploadServer.Services;

namespace UploadServer.Tests
{
    /// <summary>
    /// GetMyFeedbacksAsync 測試：只回傳自己的回饋、依時間倒序、分頁、管理員回覆欄位。
    /// </summary>
    public class MyFeedbacksTests : IDisposable
    {
        private class DummyHttpClientFactory : IHttpClientFactory
        {
            public HttpClient CreateClient(string name) => new();
        }

        private readonly SqliteConnection _connection;
        private readonly VideoDbContext _db;
        private readonly UserService _service;

        public MyFeedbacksTests()
        {
            _connection = new SqliteConnection("DataSource=:memory:");
            _connection.Open();

            var options = new DbContextOptionsBuilder<VideoDbContext>()
                .UseSqlite(_connection)
                .Options;
            _db = new VideoDbContext(options);
            _db.Database.EnsureCreated();

            var config = new ConfigurationBuilder().Build();
            _service = new UserService(_db, NullLogger<UserService>.Instance,
                new DummyHttpClientFactory(), config);
        }

        public void Dispose()
        {
            _db.Dispose();
            _connection.Dispose();
        }

        private async Task SeedUserAsync(string id)
        {
            _db.Users.Add(new User
            {
                Id          = id,
                Username    = $"{id}@test.com",
                Email       = $"{id}@test.com",
                DisplayName = "Test User",
                CreatedAt   = DateTime.UtcNow,
                UpdatedAt   = DateTime.UtcNow,
            });
            await _db.SaveChangesAsync();
        }

        private async Task SeedFeedbackAsync(
            string userId, string text, DateTime createdAt,
            string type = "bug", string? adminReply = null)
        {
            _db.UserFeedbacks.Add(new UserFeedback
            {
                Id             = Guid.NewGuid().ToString(),
                UserId         = userId,
                Type           = type,
                Text           = text,
                CreatedAt      = createdAt,
                AdminReply     = adminReply,
                AdminRepliedAt = adminReply != null ? createdAt.AddHours(1) : null,
            });
            await _db.SaveChangesAsync();
        }

        [Fact]
        public async Task GetMyFeedbacks_UserNotFound_ReturnsNull()
        {
            var result = await _service.GetMyFeedbacksAsync("nobody", 1, 20);
            Assert.Null(result);
        }

        [Fact]
        public async Task GetMyFeedbacks_OnlyOwnFeedbacks_NewestFirst()
        {
            await SeedUserAsync("u1");
            await SeedUserAsync("u2");
            await SeedFeedbackAsync("u1", "old", DateTime.UtcNow.AddDays(-2));
            await SeedFeedbackAsync("u1", "new", DateTime.UtcNow, type: "feature",
                adminReply: "thanks");
            await SeedFeedbackAsync("u2", "other user", DateTime.UtcNow);

            var result = await _service.GetMyFeedbacksAsync("u1", 1, 20);

            Assert.NotNull(result);
            Assert.Equal(2, result!.Total);
            Assert.Equal(2, result.Items.Count);
            Assert.Equal("new", result.Items[0].Text);
            Assert.Equal("feature", result.Items[0].Type);
            Assert.Equal("thanks", result.Items[0].AdminReply);
            Assert.NotNull(result.Items[0].RepliedAt);
            Assert.Equal("old", result.Items[1].Text);
            Assert.Null(result.Items[1].AdminReply);
        }

        [Fact]
        public async Task GetMyFeedbacks_Pagination_Works()
        {
            await SeedUserAsync("u1");
            for (var i = 0; i < 5; i++)
                await SeedFeedbackAsync("u1", $"fb{i}", DateTime.UtcNow.AddMinutes(-i));

            var page2 = await _service.GetMyFeedbacksAsync("u1", 2, 2);

            Assert.NotNull(page2);
            Assert.Equal(5, page2!.Total);
            Assert.Equal(2, page2.Page);
            Assert.Equal(2, page2.Items.Count);
            Assert.Equal("fb2", page2.Items[0].Text);
            Assert.Equal("fb3", page2.Items[1].Text);
        }
    }
}
