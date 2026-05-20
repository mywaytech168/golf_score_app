using Microsoft.EntityFrameworkCore;
using UploadServer.Data;
using UploadServer.DTOs;
using UploadServer.Models;

namespace UploadServer.Services
{
    public class ShareService
    {
        private readonly VideoDbContext _db;
        private readonly B2Service _b2;
        private readonly IConfiguration _config;
        private readonly ILogger<ShareService> _logger;

        private static readonly char[] _chars =
            "abcdefghijklmnopqrstuvwxyz0123456789".ToCharArray();

        public ShareService(VideoDbContext db, B2Service b2, IConfiguration config, ILogger<ShareService> logger)
        {
            _db     = db;
            _b2     = b2;
            _config = config;
            _logger = logger;
        }

        // ── 產生分享準備（pre-signed URL） ─────────────────────

        public async Task<SharePrepareResponse> PrepareAsync(SharePrepareRequest req)
        {
            var code       = GenerateCode(16);
            var prefix     = _config["B2:SharePrefix"] ?? "shares/";
            var b2FileName = $"{prefix}{code}.zip";

            var uploadUrl = _b2.GenerateUploadUrl(b2FileName);

            var link = new ShareLink
            {
                ShareCode  = code,
                B2FileName = b2FileName,
                Title      = req.Title,
                SizeBytes  = req.SizeBytes,
                SharerName = req.SharerName,
                Confirmed  = false,
                CreatedAt  = DateTime.UtcNow,
                ExpiresAt  = DateTime.UtcNow.AddDays(1),
            };

            _db.ShareLinks.Add(link);
            await _db.SaveChangesAsync();

            _logger.LogInformation("Share prepare: code={Code}", code);

            return new SharePrepareResponse
            {
                ShareCode  = code,
                UploadUrl  = uploadUrl,
                B2FileName = b2FileName,
            };
        }

        // ── 確認上傳完成 ────────────────────────────────────────

        public async Task<ShareConfirmResponse?> ConfirmAsync(string shareCode)
        {
            var link = await _db.ShareLinks.FirstOrDefaultAsync(l => l.ShareCode == shareCode);
            if (link == null) return null;

            link.Confirmed = true;
            await _db.SaveChangesAsync();

            _logger.LogInformation("Share confirmed: code={Code}", shareCode);

            return new ShareConfirmResponse { Ok = true, ExpiresAt = link.ExpiresAt };
        }

        // ── 取得分享資訊（含下載 URL） ──────────────────────────

        public async Task<ShareGetResponse?> GetAsync(string shareCode)
        {
            var link = await _db.ShareLinks.FirstOrDefaultAsync(
                l => l.ShareCode == shareCode && l.Confirmed && l.ExpiresAt > DateTime.UtcNow);

            if (link == null) return null;

            link.DownloadCount++;
            await _db.SaveChangesAsync();

            var downloadUrl = _b2.GenerateDownloadUrl(link.B2FileName);

            return new ShareGetResponse
            {
                Title       = link.Title ?? shareCode,
                SizeBytes   = link.SizeBytes,
                ExpiresAt   = link.ExpiresAt,
                DownloadUrl = downloadUrl,
                SharerName  = link.SharerName,
            };
        }

        // ── 工具 ────────────────────────────────────────────────

        private static string GenerateCode(int length)
        {
            var buf = System.Security.Cryptography.RandomNumberGenerator.GetBytes(length);
            return new string(buf.Select(b => _chars[b % _chars.Length]).ToArray());
        }
    }
}
