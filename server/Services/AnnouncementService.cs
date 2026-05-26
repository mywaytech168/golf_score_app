using Microsoft.EntityFrameworkCore;
using UploadServer.Data;
using UploadServer.DTOs;
using UploadServer.Models;

namespace UploadServer.Services
{
    public class AnnouncementService
    {
        private readonly VideoDbContext _db;
        private readonly ILogger<AnnouncementService> _logger;

        public AnnouncementService(VideoDbContext db, ILogger<AnnouncementService> logger)
        {
            _db     = db;
            _logger = logger;
        }

        // ── 公開查詢 ─────────────────────────────────────────────────

        /// <summary>
        /// 取得目前有效的公告列表（isActive=true、publishedAt ≤ now、未過期）
        /// 依 publishedAt 降冪排序。
        /// </summary>
        public async Task<List<AnnouncementResponse>> GetActiveAsync()
        {
            var now = DateTime.UtcNow;
            var list = await _db.Announcements
                .AsNoTracking()
                .Where(a => a.IsActive
                         && a.PublishedAt <= now
                         && (a.ExpiresAt == null || a.ExpiresAt > now))
                .OrderByDescending(a => a.PublishedAt)
                .Select(a => new AnnouncementResponse(
                    a.Id, a.Title, a.Body, a.Type,
                    a.PublishedAt, a.ExpiresAt, a.ImageUrl))
                .ToListAsync();

            _logger.LogInformation("📢 公告查詢：回傳 {Count} 則", list.Count);
            return list;
        }

        // ── 管理員 CRUD ──────────────────────────────────────────────

        public async Task<List<AnnouncementResponse>> GetAllAdminAsync()
        {
            return await _db.Announcements
                .AsNoTracking()
                .OrderByDescending(a => a.PublishedAt)
                .Select(a => new AnnouncementResponse(
                    a.Id, a.Title, a.Body, a.Type,
                    a.PublishedAt, a.ExpiresAt, a.ImageUrl))
                .ToListAsync();
        }

        public async Task<AnnouncementResponse> CreateAsync(UpsertAnnouncementRequest req)
        {
            var entity = new Announcement
            {
                Id          = Guid.NewGuid().ToString(),
                Title       = req.Title.Trim(),
                Body        = req.Body.Trim(),
                Type        = ValidateType(req.Type),
                PublishedAt = req.PublishedAt?.ToUniversalTime() ?? DateTime.UtcNow,
                ExpiresAt   = req.ExpiresAt?.ToUniversalTime(),
                ImageUrl    = req.ImageUrl?.Trim(),
                IsActive    = req.IsActive,
                CreatedAt   = DateTime.UtcNow,
                UpdatedAt   = DateTime.UtcNow,
            };

            _db.Announcements.Add(entity);
            await _db.SaveChangesAsync();

            _logger.LogInformation("📝 公告已建立 id={Id} title={Title}", entity.Id, entity.Title);
            return ToDto(entity);
        }

        public async Task<AnnouncementResponse?> UpdateAsync(string id, UpsertAnnouncementRequest req)
        {
            var entity = await _db.Announcements.FindAsync(id);
            if (entity == null) return null;

            entity.Title       = req.Title.Trim();
            entity.Body        = req.Body.Trim();
            entity.Type        = ValidateType(req.Type);
            entity.PublishedAt = req.PublishedAt?.ToUniversalTime() ?? entity.PublishedAt;
            entity.ExpiresAt   = req.ExpiresAt?.ToUniversalTime();
            entity.ImageUrl    = req.ImageUrl?.Trim();
            entity.IsActive    = req.IsActive;
            entity.UpdatedAt   = DateTime.UtcNow;

            await _db.SaveChangesAsync();

            _logger.LogInformation("✏️ 公告已更新 id={Id}", id);
            return ToDto(entity);
        }

        public async Task<bool> DeleteAsync(string id)
        {
            var entity = await _db.Announcements.FindAsync(id);
            if (entity == null) return false;

            _db.Announcements.Remove(entity);
            await _db.SaveChangesAsync();

            _logger.LogInformation("🗑️ 公告已刪除 id={Id}", id);
            return true;
        }

        // ── 工具 ────────────────────────────────────────────────────

        private static readonly HashSet<string> _validTypes =
            ["info", "important", "event", "update"];

        private static string ValidateType(string type) =>
            _validTypes.Contains(type) ? type : "info";

        private static AnnouncementResponse ToDto(Announcement a) =>
            new(a.Id, a.Title, a.Body, a.Type, a.PublishedAt, a.ExpiresAt, a.ImageUrl);
    }
}
