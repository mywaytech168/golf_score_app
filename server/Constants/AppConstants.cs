namespace UploadServer.Constants
{
    public static class VideoStatus
    {
        public const string Pending    = "pending";
        public const string Uploading  = "uploading";
        public const string Completed  = "completed";
        public const string Processing = "processing";
        public const string Failed     = "failed";
        public const string Unbind     = "unbind";
        public const string Deleted    = "deleted";
    }

    public static class FileStatus
    {
        public const string Pending   = "pending";
        public const string Uploading = "uploading";
        public const string Completed = "completed";
        public const string Failed    = "failed";
    }

    public static class QueueStatus
    {
        public const string Ready      = "ready";
        public const string Queued     = "queued";
        public const string Processing = "processing";
        public const string Completed  = "completed";
        public const string Failed     = "failed";
    }

    public static class UserStatus
    {
        public const string Active    = "active";
        public const string Inactive  = "inactive";
        public const string Suspended = "suspended";
    }

    public static class VideoType
    {
        public const string Original = "original";
        public const string Clip     = "clip";
    }

    public static class FileType
    {
        public const string Original         = "original";
        public const string Clip             = "clip";
        public const string PosePhaseVideo   = "pose_phase_trajectory_video";
        public const string ChestTrajectory  = "chest_trajectory";
        public const string WristTrajectory  = "wrist_trajectory";
        public const string Thumbnail        = "thumbnail";
    }

    public static class AuthProvider
    {
        public const string Local  = "local";
        public const string Google = "google";
        public const string Apple  = "apple";
    }

    public static class AnalysisSource
    {
        public const string DailyQuota = "daily_quota";
        public const string BonusBall  = "bonus_ball";
    }

    public static class BallReason
    {
        public const string Ad       = "ad";
        public const string Feedback = "feedback";
        public const string Invite   = "invite";
        public const string Upload   = "upload";
        public const string Analysis = "analysis";
        public const string Manual   = "manual";
        public const string Purchase = "purchase";
    }

    public static class PurchaseStatus
    {
        public const string Pending  = "pending";
        public const string Verified = "verified";
        public const string Failed   = "failed";
        public const string Refunded = "refunded";
    }
}
