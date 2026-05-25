namespace UploadServer.DTOs
{
    // ════════════════════════════════════════════════════════════════
    // GET /api/app/version 回應
    // ════════════════════════════════════════════════════════════════

    /// <summary>
    /// 版本檢查回應（Flutter 端直接 map 此格式）
    /// </summary>
    public record AppVersionResponse(
        string LatestVersion,
        string MinRequiredVersion,
        bool ForceUpdate,
        string UpdateUrl,
        List<string> ReleaseNotes,
        string ReleaseDate
    );

    // ════════════════════════════════════════════════════════════════
    // PUT /api/admin/app/version 請求
    // ════════════════════════════════════════════════════════════════

    /// <summary>
    /// 管理員更新版本設定
    /// </summary>
    public record UpdateAppVersionRequest(
        string LatestVersion,
        string MinRequiredVersion,
        bool ForceUpdate,
        string UpdateUrl,
        List<string> ReleaseNotes,
        string ReleaseDate
    );

    // ════════════════════════════════════════════════════════════════
    // 管理員 API 請求 DTOs
    // ════════════════════════════════════════════════════════════════

    public record AdminLoginRequest(string Username, string Password);

    public record AdminAdjustBallsRequest(int Delta);

    public record AdminFeedbackReplyRequest(string Reply);
}
