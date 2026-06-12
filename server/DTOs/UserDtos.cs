namespace UploadServer.DTOs
{
    // ════════════════════════════════════════════════════════════════
    // 個人資料
    // ════════════════════════════════════════════════════════════════

    /// <summary>GET /api/user/me 回應</summary>
    public record MeResponse(
        string Id,
        string Username,
        string Email,
        string DisplayName,
        /// <summary>是否已綁定 Google 登入</summary>
        bool GoogleLinked,
        /// <summary>是否已設定本地密碼（false = 純 OAuth 帳號）</summary>
        bool HasPassword,
        /// <summary>是否已綁定 Apple 登入</summary>
        bool AppleLinked = false
    );

    /// <summary>PATCH /api/user/me 請求</summary>
    public record UpdateMeRequest(string? DisplayName);

    // ════════════════════════════════════════════════════════════════
    // 方案相關
    // ════════════════════════════════════════════════════════════════

    /// <summary>GET /api/user/plan 回應</summary>
    public record PlanStatusResponse(
        string Plan,
        int DailyLimit,
        int TodayUsed,
        int BonusBalls,
        /// <summary>訂閱到期時間（UTC ISO8601），null = 免費或未訂閱</summary>
        DateTime? SubscriptionExpiry = null,
        /// <summary>"none" | "active" | "cancel_pending" | "expired"</summary>
        string SubscriptionStatus = "none"
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
    public record SubmitFeedbackRequest(
        string Type,
        string Text,
        string? VideoId,
        string? ImageB2Key);

    /// <summary>GET /api/user/rewards/feedback/image-upload-url 回應</summary>
    public record FeedbackImageUploadUrlResponse(string UploadUrl, string ImageId);

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
        string VideoType,
        string? UploadId = null
    );

    /// <summary>POST /api/user/rewards/upload 請求</summary>
    public record UploadSessionsRequest(List<SessionDataDto> Sessions);

    /// <summary>
    /// POST /api/user/rewards/upload 回應（審核制）
    /// Balls 固定 0（審核通過後才發球）；Pending = 本次新建立的待審核筆數
    /// </summary>
    public record UploadRewardResponse(int Balls, int Pending);

    /// <summary>GET /api/user/rewards/uploads — 單筆上傳審核狀態</summary>
    public record MyDatasetUploadDto(
        string Id,
        string ClientFilePath,
        string Status,
        DateTime CreatedAt,
        DateTime? ReviewedAt,
        string? Note);

    /// <summary>GET /api/user/rewards/uploads 回應</summary>
    public record MyDatasetUploadsResponse(
        int Total,
        int PendingCount,
        int ApprovedCount,
        int RejectedCount,
        int Page,
        int PageSize,
        List<MyDatasetUploadDto> Items);

    /// <summary>POST /api/user/rewards/upload/prepare 回應（presigned PUT URL）</summary>
    public record PrepareDatasetUploadResponse(
        string UploadId,
        string VideoUploadUrl,
        string CsvUploadUrl);

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

    /// <summary>
    /// POST /api/user/balls/purchase 請求
    /// productId: "orvia_golf_balls_1" | "orvia_golf_balls_5" | "orvia_golf_balls_10" | "orvia_golf_balls_50" | "orvia_golf_balls_100"
    /// store: "google_play" | "app_store"
    /// </summary>
    public record PurchaseBallsRequest(string ProductId, string Store, string PurchaseToken);

    /// <summary>POST /api/user/balls/purchase 回應</summary>
    public record PurchaseBallsResponse(bool Success, string Message, int BallsAdded, int NewBalance);

    // ════════════════════════════════════════════════════════════════
    // 使用紀錄
    // ════════════════════════════════════════════════════════════════

    /// <summary>GET /api/user/analysis/history — 單筆分析紀錄</summary>
    public record AnalysisRecordDto(
        string Id,
        /// <summary>"daily_quota" | "bonus_ball"</summary>
        string Source,
        int BallsSpent,
        DateTime UsedAt
    );

    /// <summary>GET /api/user/analysis/history 回應</summary>
    public record AnalysisHistoryResponse(
        int Total,
        int TodayUsed,
        int Page,
        int PageSize,
        List<AnalysisRecordDto> Items
    );

    /// <summary>GET /api/user/balls/history — 單筆球數流水</summary>
    public record BallRecordDto(
        string Id,
        /// <summary>"ad" | "feedback" | "invite" | "upload" | "analysis" | "manual"</summary>
        string Reason,
        int Delta,
        int BalanceAfter,
        DateTime CreatedAt
    );

    /// <summary>GET /api/user/balls/history 回應</summary>
    public record BallsHistoryResponse(
        int Total,
        int CurrentBalls,
        int Page,
        int PageSize,
        List<BallRecordDto> Items
    );

    /// <summary>GET /api/user/feedbacks — 單筆回饋（ImageB2Key 由 Controller 轉成臨時下載 URL）</summary>
    public record MyFeedbackDto(
        string Id,
        /// <summary>"bug" | "feature" | "other"</summary>
        string Type,
        string Text,
        string? VideoId,
        string? ImageB2Key,
        string? AdminReply,
        DateTime? RepliedAt,
        DateTime CreatedAt
    );

    /// <summary>GET /api/user/feedbacks 回應</summary>
    public record MyFeedbacksResponse(
        int Total,
        int Page,
        int PageSize,
        List<MyFeedbackDto> Items
    );

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

    // ════════════════════════════════════════════════════════════════
    // Webhook — Google Play RTDN
    // ════════════════════════════════════════════════════════════════

    /// <summary>Google Pub/Sub push 包裝</summary>
    public record GooglePubSubPush(GooglePubSubMessage Message, string Subscription);
    public record GooglePubSubMessage(string Data, string MessageId, string PublishTime);

    /// <summary>Google DeveloperNotification（解 base64 後）</summary>
    public record GoogleDeveloperNotification(
        string Version,
        string PackageName,
        string EventTimeMillis,
        GoogleSubscriptionNotification? SubscriptionNotification
    );
    public record GoogleSubscriptionNotification(
        string Version,
        int NotificationType,
        string PurchaseToken,
        string SubscriptionId
    );

    // ════════════════════════════════════════════════════════════════
    // Webhook — Apple Server Notifications V2
    // ════════════════════════════════════════════════════════════════

    /// <summary>Apple Server Notification V2 外層</summary>
    public record AppleNotificationBody(string SignedPayload);

    /// <summary>JWS Payload 解碼後（只取需要的欄位）</summary>
    public record AppleJwsPayload(
        string NotificationType,
        string? Subtype,
        AppleJwsData Data
    );
    public record AppleJwsData(
        string SignedTransactionInfo,
        string? SignedRenewalInfo,
        string Environment
    );

    /// <summary>signedTransactionInfo 解碼後</summary>
    public record AppleTransactionInfo(
        string OriginalTransactionId,
        string ProductId,
        long ExpiresDateMs,
        long? RevocationDateMs,
        string? RevocationReason
    );
}
