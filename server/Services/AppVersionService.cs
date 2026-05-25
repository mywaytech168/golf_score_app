using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using UploadServer.Data;
using UploadServer.DTOs;
using UploadServer.Models;

namespace UploadServer.Services
{
    /// <summary>
    /// App 版本管理：查詢與更新
    /// </summary>
    public class AppVersionService
    {
        private readonly VideoDbContext _db;
        private readonly ILogger<AppVersionService> _logger;

        public AppVersionService(VideoDbContext db, ILogger<AppVersionService> logger)
        {
            _db     = db;
            _logger = logger;
        }

        // ────────────────────────────────────────────────────────────
        // 公開查詢
        // ────────────────────────────────────────────────────────────

        /// <summary>
        /// 取得指定平台的版本資訊並判斷是否需要更新。
        /// 若資料庫尚無該平台記錄，回傳預設值（不需更新）。
        /// </summary>
        /// <param name="platform">"android" 或 "ios"</param>
        /// <param name="clientVersion">客戶端目前版本號，e.g. "1.0.0"</param>
        public async Task<AppVersionResponse> GetVersionAsync(string platform, string clientVersion)
        {
            var record = await _db.AppVersions
                .AsNoTracking()
                .FirstOrDefaultAsync(v => v.Platform == platform.ToLower());

            // 若尚未設定，回傳與客戶端相同版本（代表不需更新）
            if (record == null)
            {
                _logger.LogWarning("⚠️ 版本記錄不存在 platform={Platform}，回傳預設值", platform);
                return new AppVersionResponse(
                    LatestVersion:      clientVersion,
                    MinRequiredVersion: clientVersion,
                    ForceUpdate:        false,
                    UpdateUrl:          string.Empty,
                    ReleaseNotes:       [],
                    ReleaseDate:        string.Empty
                );
            }

            // 判斷是否強制：手動旗標 OR 客戶端版本 < MinRequiredVersion
            var forceUpdate = record.ForceUpdate ||
                              IsOlderThan(clientVersion, record.MinRequiredVersion);

            var notes = ParseNotes(record.ReleaseNotesJson);

            _logger.LogInformation(
                "✅ 版本查詢 platform={Platform} client={Client} latest={Latest} force={Force}",
                platform, clientVersion, record.LatestVersion, forceUpdate);

            return new AppVersionResponse(
                LatestVersion:      record.LatestVersion,
                MinRequiredVersion: record.MinRequiredVersion,
                ForceUpdate:        forceUpdate,
                UpdateUrl:          record.UpdateUrl,
                ReleaseNotes:       notes,
                ReleaseDate:        record.ReleaseDate
            );
        }

        // ────────────────────────────────────────────────────────────
        // 管理員操作
        // ────────────────────────────────────────────────────────────

        /// <summary>
        /// 建立或更新指定平台的版本設定（Upsert）。
        /// </summary>
        public async Task<AppVersion> UpsertVersionAsync(string platform, UpdateAppVersionRequest req)
        {
            var p = platform.ToLower();
            var record = await _db.AppVersions.FirstOrDefaultAsync(v => v.Platform == p);

            if (record == null)
            {
                record = new AppVersion { Platform = p };
                _db.AppVersions.Add(record);
            }

            record.LatestVersion      = req.LatestVersion.Trim();
            record.MinRequiredVersion = req.MinRequiredVersion.Trim();
            record.ForceUpdate        = req.ForceUpdate;
            record.UpdateUrl          = req.UpdateUrl?.Trim() ?? string.Empty;
            record.ReleaseNotesJson   = JsonSerializer.Serialize(req.ReleaseNotes ?? []);
            record.ReleaseDate        = req.ReleaseDate?.Trim() ?? string.Empty;
            record.UpdatedAt          = DateTime.UtcNow;

            await _db.SaveChangesAsync();

            _logger.LogInformation(
                "📝 版本設定已更新 platform={Platform} latest={Latest} min={Min} force={Force}",
                p, record.LatestVersion, record.MinRequiredVersion, record.ForceUpdate);

            return record;
        }

        /// <summary>取得所有平台的版本設定（管理後台用）</summary>
        public async Task<List<AppVersion>> GetAllAsync() =>
            await _db.AppVersions.AsNoTracking().OrderBy(v => v.Platform).ToListAsync();

        // ────────────────────────────────────────────────────────────
        // 工具方法
        // ────────────────────────────────────────────────────────────

        /// <summary>
        /// 語意版本比較：current &lt; target → true
        /// 支援 "1.0.0" 及 "1.0.0+4" 格式。
        /// </summary>
        private static bool IsOlderThan(string current, string target)
        {
            static int[] Parse(string v)
            {
                var base_ = v.Split('+')[0];
                var parts = base_.Split('.').Select(s => int.TryParse(s, out var n) ? n : 0).ToArray();
                return parts.Length >= 3 ? parts[..3] : [.. parts, .. Enumerable.Repeat(0, 3 - parts.Length)];
            }

            try
            {
                var c = Parse(current);
                var t = Parse(target);
                for (int i = 0; i < 3; i++)
                {
                    if (c[i] < t[i]) return true;
                    if (c[i] > t[i]) return false;
                }
                return false;
            }
            catch
            {
                return false;
            }
        }

        private static List<string> ParseNotes(string json)
        {
            try
            {
                return JsonSerializer.Deserialize<List<string>>(json) ?? [];
            }
            catch
            {
                return [];
            }
        }
    }
}
