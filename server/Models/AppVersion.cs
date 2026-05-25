namespace UploadServer.Models
{
    /// <summary>
    /// App 版本設定（每個平台一筆）
    /// platform: "android" | "ios"
    /// </summary>
    public class AppVersion
    {
        public int Id { get; set; }

        /// <summary>平台：android | ios</summary>
        public string Platform { get; set; } = string.Empty;

        /// <summary>目前最新版本號，e.g. "1.2.0"</summary>
        public string LatestVersion { get; set; } = "1.0.0";

        /// <summary>最低支援版本；低於此版本強制更新</summary>
        public string MinRequiredVersion { get; set; } = "1.0.0";

        /// <summary>
        /// 手動強制更新旗標。
        /// true = 所有低於 LatestVersion 的版本都強制更新；
        /// false = 由 MinRequiredVersion 自動判斷。
        /// </summary>
        public bool ForceUpdate { get; set; } = false;

        /// <summary>商店連結（Play Store / App Store）</summary>
        public string UpdateUrl { get; set; } = string.Empty;

        /// <summary>更新說明，JSON 陣列字串，e.g. ["修正 A","新增 B"]</summary>
        public string ReleaseNotesJson { get; set; } = "[]";

        /// <summary>發布日期，e.g. "2026-05-25"</summary>
        public string ReleaseDate { get; set; } = string.Empty;

        public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
    }
}
