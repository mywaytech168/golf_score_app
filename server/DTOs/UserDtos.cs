namespace UploadServer.DTOs
{
    // ════════════════════════════════════════════════════════════════
    // 方案相關
    // ════════════════════════════════════════════════════════════════

    /// <summary>GET /api/user/plan 回應</summary>
    public record PlanStatusResponse(
        string Plan,
        int DailyLimit,
        int TodayUsed,
        int BonusBalls
    );

    /// <summary>PUT /api/user/plan 請求</summary>
    public record UpdatePlanRequest(string Plan);

    /// <summary>POST /api/user/plan/use 回應</summary>
    public record IncrementUsageResponse(int TodayUsed, int Remaining);

    // ════════════════════════════════════════════════════════════════
    // 獎勵相關
    // ════════════════════════════════════════════════════════════════

    /// <summary>GET /api/user/rewards 回應</summary>
    public record RewardStatusResponse(
        int BonusBalls,
        int AdClaimedToday,
        bool FeedbackClaimedToday,
        string? InviteCode,
        int InviteCount,
        /// <summary>是否已使用過別人的邀請碼（true = 已使用，不可再套用）</summary>
        bool HasAppliedInviteCode
    );

    /// <summary>POST /api/user/invite/apply 回應</summary>
    public record ApplyInviteResponse(bool Success, string Message, int BallsEarned);

    /// <summary>POST /api/user/rewards/ad 回應</summary>
    public record ClaimAdRewardResponse(int Balls, int AdClaimedToday);

    /// <summary>GET /api/user/invite-code 回應</summary>
    public record InviteCodeResponse(string Code, int InviteCount);

    /// <summary>POST /api/user/rewards/feedback 請求</summary>
    public record SubmitFeedbackRequest(string Type, string Text);

    /// <summary>POST /api/user/rewards/feedback 回應</summary>
    public record FeedbackRewardResponse(int Balls);

    /// <summary>POST /api/user/rewards/upload 請求中的單筆錄影資料</summary>
    public record SessionDataDto(
        string FilePath,
        string RecordedAt,
        int DurationSeconds,
        bool? GoodShot,
        double? AudioCrispness,
        string? AudioLabel,
        string VideoType
    );

    /// <summary>POST /api/user/rewards/upload 請求</summary>
    public record UploadSessionsRequest(List<SessionDataDto> Sessions);

    /// <summary>POST /api/user/rewards/upload 回應</summary>
    public record UploadRewardResponse(int Balls, int Uploaded);

    // ════════════════════════════════════════════════════════════════
    // 付款購買
    // ════════════════════════════════════════════════════════════════

    /// <summary>
    /// POST /api/user/plan/purchase 請求
    /// store: "google_pay" | "google_play" | "app_store"
    /// purchaseToken: Google Pay payment token / Google Play purchase token / App Store receipt (base64)
    /// </summary>
    public record PurchasePlanRequest(string Plan, string Store, string PurchaseToken, string? ProductId = null);

    /// <summary>POST /api/user/plan/purchase 回應</summary>
    public record PurchasePlanResponse(bool Success, string Message, string? Plan);

    // ════════════════════════════════════════════════════════════════
    // 邀請好友列表
    // ════════════════════════════════════════════════════════════════

    /// <summary>GET /api/user/invite/friends — 單筆已邀請好友</summary>
    public record InvitedFriendDto(
        string DisplayName,
        string? AvatarUrl,
        DateTime JoinedAt,
        int BallsEarned
    );

    /// <summary>GET /api/user/invite/friends 回應</summary>
    public record InvitedFriendsResponse(
        int Total,
        List<InvitedFriendDto> Friends
    );
}
