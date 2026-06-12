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
    /// 上傳獎勵審核制測試：claim 建立 pending 列不發球；
    /// approve 發球一次（重複 approve 不重發）；reject 不發球且同 filePath 可重新提交；
    /// pending / approved 阻擋重複提交。
    /// </summary>
    public class UploadRewardTests : IDisposable
    {
        private class DummyHttpClientFactory : IHttpClientFactory
        {
            public HttpClient CreateClient(string name) => new();
        }

        private readonly SqliteConnection _connection;
        private readonly VideoDbContext _db;
        private readonly UserService _service;

        public UploadRewardTests()
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

        private static SessionDataDto Session(string filePath, string? uploadId = null) =>
            new(filePath, "2026-06-12T10:00:00", 60, true, 0.8, "crisp", "clip", uploadId);

        [Fact]
        public async Task Claim_UserNotFound_ReturnsNull()
        {
            var result = await _service.ClaimUploadRewardAsync("nobody", [Session("/a/clip.mp4")]);
            Assert.Null(result);
        }

        [Fact]
        public async Task Claim_PersistsPendingRow_NoBallsAwarded()
        {
            await SeedUserAsync("u1");

            var result = await _service.ClaimUploadRewardAsync(
                "u1", [Session("/a/clip.mp4", "abc123")]);

            Assert.NotNull(result);
            Assert.Equal(0, result!.Balls);
            Assert.Equal(1, result.Pending);

            var row = await _db.DatasetUploads.SingleAsync();
            Assert.Equal("abc123", row.Id);
            Assert.Equal("u1", row.UserId);
            Assert.Equal("/a/clip.mp4", row.ClientFilePath);
            Assert.Equal("dataset/abc123/clip.mp4", row.B2VideoKey);
            Assert.Equal("dataset/abc123/pose_landmarks.csv", row.B2CsvKey);
            Assert.Equal("clip", row.VideoType);
            Assert.Equal(DatasetUploadStatus.Pending, row.Status);
            Assert.Null(row.ReviewedAt);

            // 未發球
            Assert.Equal(0, await _db.BallRecords.CountAsync());
            var user = await _db.Users.FindAsync("u1");
            Assert.Equal(0, user!.BonusBalls);
        }

        [Fact]
        public async Task Claim_WithoutUploadId_PersistsMetadataOnly()
        {
            await SeedUserAsync("u1");

            var result = await _service.ClaimUploadRewardAsync("u1", [Session("/a/clip.mp4")]);

            Assert.NotNull(result);
            var row = await _db.DatasetUploads.SingleAsync();
            Assert.Null(row.B2VideoKey);
            Assert.Null(row.B2CsvKey);
        }

        [Fact]
        public async Task Claim_PendingDuplicateFilePath_Blocked()
        {
            await SeedUserAsync("u1");

            var first = await _service.ClaimUploadRewardAsync("u1", [Session("/a/clip.mp4", "id1")]);
            Assert.Equal(1, first!.Pending);

            var second = await _service.ClaimUploadRewardAsync("u1", [Session("/a/clip.mp4", "id2")]);
            Assert.NotNull(second);
            Assert.Equal(0, second!.Balls);
            Assert.Equal(0, second.Pending);

            Assert.Equal(1, await _db.DatasetUploads.CountAsync());
            Assert.Equal(0, await _db.BallRecords.CountAsync());
        }

        [Fact]
        public async Task Claim_ApprovedDuplicateFilePath_Blocked()
        {
            await SeedUserAsync("u1");
            await _service.ClaimUploadRewardAsync("u1", [Session("/a/clip.mp4", "id1")]);
            await _service.ReviewDatasetUploadAsync("id1", approve: true, note: null);

            var second = await _service.ClaimUploadRewardAsync("u1", [Session("/a/clip.mp4", "id2")]);

            Assert.Equal(0, second!.Pending);
            Assert.Equal(1, await _db.DatasetUploads.CountAsync());
        }

        [Fact]
        public async Task Claim_MixedNewAndDuplicate_CountsNewOnly()
        {
            await SeedUserAsync("u1");
            await _service.ClaimUploadRewardAsync("u1", [Session("/a/clip.mp4", "id1")]);

            var result = await _service.ClaimUploadRewardAsync(
                "u1", [Session("/a/clip.mp4", "id2"), Session("/b/clip.mp4", "id3")]);

            Assert.Equal(0, result!.Balls);
            Assert.Equal(1, result.Pending);
            Assert.Equal(2, await _db.DatasetUploads.CountAsync());
        }

        [Fact]
        public async Task Claim_SameFilePathDifferentUser_StillAccepted()
        {
            await SeedUserAsync("u1");
            await SeedUserAsync("u2");
            await _service.ClaimUploadRewardAsync("u1", [Session("/a/clip.mp4", "id1")]);

            var result = await _service.ClaimUploadRewardAsync("u2", [Session("/a/clip.mp4", "id2")]);

            Assert.Equal(1, result!.Pending);
            Assert.Equal(2, await _db.DatasetUploads.CountAsync());
        }

        // ── 審核 ─────────────────────────────────────────────────────

        [Fact]
        public async Task Review_Approve_AwardsBallsOnce()
        {
            await SeedUserAsync("u1");
            await _service.ClaimUploadRewardAsync("u1", [Session("/a/clip.mp4", "id1")]);

            var (found, reviewed) = await _service.ReviewDatasetUploadAsync("id1", approve: true, note: "good");
            Assert.True(found);
            Assert.True(reviewed);

            var row = await _db.DatasetUploads.SingleAsync();
            Assert.Equal(DatasetUploadStatus.Approved, row.Status);
            Assert.NotNull(row.ReviewedAt);
            Assert.Equal("good", row.ReviewNote);

            var user = await _db.Users.FindAsync("u1");
            Assert.Equal(3, user!.BonusBalls);
            var record = await _db.BallRecords.SingleAsync();
            Assert.Equal(BallReason.Upload, record.Reason);
            Assert.Equal(3, record.Delta);

            // 重複 approve → 不重發
            var (found2, reviewed2) = await _service.ReviewDatasetUploadAsync("id1", approve: true, note: null);
            Assert.True(found2);
            Assert.False(reviewed2);
            Assert.Equal(1, await _db.BallRecords.CountAsync());
            Assert.Equal(3, (await _db.Users.FindAsync("u1"))!.BonusBalls);
        }

        [Fact]
        public async Task Review_Reject_NoBalls_BlocksResubmit()
        {
            await SeedUserAsync("u1");
            await _service.ClaimUploadRewardAsync("u1", [Session("/a/clip.mp4", "id1")]);

            var (found, reviewed) = await _service.ReviewDatasetUploadAsync("id1", approve: false, note: "blurry");
            Assert.True(found);
            Assert.True(reviewed);

            var row = await _db.DatasetUploads.SingleAsync();
            Assert.Equal(DatasetUploadStatus.Rejected, row.Status);
            Assert.Equal("blurry", row.ReviewNote);
            Assert.Equal(0, await _db.BallRecords.CountAsync());
            Assert.Equal(0, (await _db.Users.FindAsync("u1"))!.BonusBalls);

            // rejected → 同 filePath 不可重新提交
            var resubmit = await _service.ClaimUploadRewardAsync("u1", [Session("/a/clip.mp4", "id2")]);
            Assert.Equal(0, resubmit!.Pending);
            Assert.Equal(1, await _db.DatasetUploads.CountAsync());
        }

        [Fact]
        public async Task Review_NotFound_ReturnsFalse()
        {
            var (found, _) = await _service.ReviewDatasetUploadAsync("nope", approve: true, note: null);
            Assert.False(found);
        }

        [Fact]
        public async Task GetMyDatasetUploads_ReturnsCountsAndItems()
        {
            await SeedUserAsync("u1");
            await _service.ClaimUploadRewardAsync(
                "u1", [Session("/a/clip.mp4", "id1"), Session("/b/clip.mp4", "id2")]);
            await _service.ReviewDatasetUploadAsync("id1", approve: true, note: null);

            var result = await _service.GetMyDatasetUploadsAsync("u1", 1, 20);

            Assert.NotNull(result);
            Assert.Equal(2, result!.Total);
            Assert.Equal(1, result.PendingCount);
            Assert.Equal(1, result.ApprovedCount);
            Assert.Equal(2, result.Items.Count);
        }
    }
}
