using Microsoft.EntityFrameworkCore;
using UploadServer.Models;

namespace UploadServer.Data
{
    public class VideoDbContext : DbContext
    {
        public VideoDbContext(DbContextOptions<VideoDbContext> options) : base(options)
        {
        }

        public DbSet<User> Users { get; set; }
        public DbSet<UserAuth> UserAuths { get; set; }
        public DbSet<AnalysisRecord> AnalysisRecords { get; set; }
        public DbSet<BallRecord> BallRecords { get; set; }
        public DbSet<InviteRecord> InviteRecords { get; set; }
        public DbSet<PurchaseRecord> PurchaseRecords { get; set; }
        public DbSet<ShareLink> ShareLinks { get; set; }
        public DbSet<UserFeedback> UserFeedbacks { get; set; }
        public DbSet<AiCoachAnalysis> AiCoachAnalyses { get; set; }
        public DbSet<PasswordResetToken> PasswordResetTokens { get; set; }
        public DbSet<AppVersion> AppVersions { get; set; }
        public DbSet<Announcement> Announcements { get; set; }

        protected override void OnModelCreating(ModelBuilder modelBuilder)
        {
            base.OnModelCreating(modelBuilder);

            // ============================================================
            // Users
            // ============================================================
            modelBuilder.Entity<User>(entity =>
            {
                entity.ToTable("users");

                entity.HasKey(e => e.Id);

                entity.Property(e => e.Id)
                    .HasColumnName("id")
                    .HasMaxLength(36)
                    .IsRequired();

                entity.Property(e => e.Username)
                    .HasColumnName("username")
                    .HasMaxLength(100)
                    .IsRequired();

                entity.Property(e => e.Email)
                    .HasColumnName("email")
                    .HasMaxLength(255)
                    .IsRequired();

                entity.Property(e => e.DisplayName)
                    .HasColumnName("display_name")
                    .HasMaxLength(255);

                entity.Property(e => e.AvatarUrl)
                    .HasColumnName("avatar_url")
                    .HasMaxLength(500);

                entity.Property(e => e.Status)
                    .HasColumnName("status")
                    .HasMaxLength(50)
                    .HasDefaultValue("active");

                entity.Property(e => e.CreatedAt)
                    .HasColumnName("created_at")
                    .HasColumnType("datetime");

                entity.Property(e => e.UpdatedAt)
                    .HasColumnName("updated_at")
                    .HasColumnType("datetime");

                entity.Property(e => e.LastLoginAt)
                    .HasColumnName("last_login_at")
                    .HasColumnType("datetime");

                entity.Property(e => e.Plan)
                    .HasColumnName("plan")
                    .HasMaxLength(50)
                    .HasDefaultValue("free");

                entity.Property(e => e.BonusBalls)
                    .HasColumnName("bonus_balls")
                    .HasDefaultValue(0);

                entity.Property(e => e.TodayUsed)
                    .HasColumnName("today_used")
                    .HasDefaultValue(0);

                entity.Property(e => e.TodayUsedDate)
                    .HasColumnName("today_used_date")
                    .HasColumnType("date");

                entity.Property(e => e.AdClaimedToday)
                    .HasColumnName("ad_claimed_today")
                    .HasDefaultValue(0);

                entity.Property(e => e.AdClaimedDate)
                    .HasColumnName("ad_claimed_date")
                    .HasColumnType("date");

                entity.Property(e => e.FeedbackClaimedDate)
                    .HasColumnName("feedback_claimed_date")
                    .HasColumnType("date");

                entity.Property(e => e.InviteCode)
                    .HasColumnName("invite_code")
                    .HasMaxLength(16);

                entity.Property(e => e.InviteCount)
                    .HasColumnName("invite_count")
                    .HasDefaultValue(0);

                entity.Property(e => e.InvitedByCode)
                    .HasColumnName("invited_by_code")
                    .HasMaxLength(16);

                entity.HasIndex(e => e.Username).IsUnique().HasDatabaseName("uk_username");
                entity.HasIndex(e => e.Email).IsUnique().HasDatabaseName("uk_email");
                entity.HasIndex(e => e.InviteCode).IsUnique().HasDatabaseName("uk_invite_code");
                entity.HasIndex(e => e.Status).HasDatabaseName("idx_user_status");
                entity.HasIndex(e => e.CreatedAt).HasDatabaseName("idx_user_created_at");

                entity.HasMany(u => u.UserAuths)
                    .WithOne(a => a.User)
                    .HasForeignKey(a => a.UserId)
                    .OnDelete(DeleteBehavior.Cascade);

                entity.HasMany(u => u.Feedbacks)
                    .WithOne(f => f.User)
                    .HasForeignKey(f => f.UserId)
                    .OnDelete(DeleteBehavior.Cascade);
            });

            // ============================================================
            // UserAuths
            // ============================================================
            modelBuilder.Entity<UserAuth>(entity =>
            {
                entity.ToTable("user_auths");

                entity.HasKey(e => e.Id);

                entity.Property(e => e.Id)
                    .HasColumnName("id")
                    .HasMaxLength(36)
                    .IsRequired();

                entity.Property(e => e.UserId)
                    .HasColumnName("user_id")
                    .HasMaxLength(36)
                    .IsRequired();

                entity.Property(e => e.Provider)
                    .HasColumnName("provider")
                    .HasMaxLength(50)
                    .IsRequired();

                entity.Property(e => e.ProviderUserId)
                    .HasColumnName("provider_user_id")
                    .HasMaxLength(255)
                    .IsRequired();

                entity.Property(e => e.CredentialHash)
                    .HasColumnName("credential_hash")
                    .HasMaxLength(255);

                entity.Property(e => e.MetadataJson)
                    .HasColumnName("metadata_json")
                    .HasColumnType("TEXT");

                entity.Property(e => e.CreatedAt)
                    .HasColumnName("created_at")
                    .HasColumnType("datetime");

                entity.Property(e => e.LastUsedAt)
                    .HasColumnName("last_used_at")
                    .HasColumnType("datetime");

                entity.HasIndex(e => new { e.Provider, e.ProviderUserId })
                    .IsUnique()
                    .HasDatabaseName("uk_auth_provider_uid");

                entity.HasIndex(e => e.UserId)
                    .HasDatabaseName("idx_auth_user_id");

                entity.HasOne(a => a.User)
                    .WithMany(u => u.UserAuths)
                    .HasForeignKey(a => a.UserId)
                    .OnDelete(DeleteBehavior.Cascade);
            });

            // ============================================================
            // AnalysisRecords
            // ============================================================
            modelBuilder.Entity<AnalysisRecord>(entity =>
            {
                entity.ToTable("analysis_records");

                entity.HasKey(e => e.Id);

                entity.Property(e => e.Id)
                    .HasColumnName("id")
                    .HasMaxLength(36)
                    .IsRequired();

                entity.Property(e => e.UserId)
                    .HasColumnName("user_id")
                    .HasMaxLength(36)
                    .IsRequired();

                entity.Property(e => e.Source)
                    .HasColumnName("source")
                    .HasMaxLength(20)
                    .IsRequired();

                entity.Property(e => e.BallsSpent)
                    .HasColumnName("balls_spent")
                    .HasDefaultValue(0);

                entity.Property(e => e.VideoId)
                    .HasColumnName("video_id")
                    .HasMaxLength(36);

                entity.Property(e => e.UsedAt)
                    .HasColumnName("used_at")
                    .HasColumnType("datetime");

                entity.HasIndex(e => e.UserId).HasDatabaseName("idx_ar_user_id");
                entity.HasIndex(e => e.UsedAt).HasDatabaseName("idx_ar_used_at");
                entity.HasIndex(e => new { e.UserId, e.UsedAt }).HasDatabaseName("idx_ar_user_used_at");

                entity.HasOne(e => e.User)
                    .WithMany()
                    .HasForeignKey(e => e.UserId)
                    .OnDelete(DeleteBehavior.Cascade);
            });

            // ============================================================
            // BallRecords
            // ============================================================
            modelBuilder.Entity<BallRecord>(entity =>
            {
                entity.ToTable("ball_records");

                entity.HasKey(e => e.Id);

                entity.Property(e => e.Id)
                    .HasColumnName("id")
                    .HasMaxLength(36)
                    .IsRequired();

                entity.Property(e => e.UserId)
                    .HasColumnName("user_id")
                    .HasMaxLength(36)
                    .IsRequired();

                entity.Property(e => e.Reason)
                    .HasColumnName("reason")
                    .HasMaxLength(20)
                    .IsRequired();

                entity.Property(e => e.Delta)
                    .HasColumnName("delta");

                entity.Property(e => e.BalanceAfter)
                    .HasColumnName("balance_after");

                entity.Property(e => e.RefId)
                    .HasColumnName("ref_id")
                    .HasMaxLength(36);

                entity.Property(e => e.CreatedAt)
                    .HasColumnName("created_at")
                    .HasColumnType("datetime");

                entity.HasIndex(e => e.UserId).HasDatabaseName("idx_br_user_id");
                entity.HasIndex(e => e.CreatedAt).HasDatabaseName("idx_br_created_at");
                entity.HasIndex(e => new { e.UserId, e.CreatedAt }).HasDatabaseName("idx_br_user_created_at");

                entity.HasOne(e => e.User)
                    .WithMany()
                    .HasForeignKey(e => e.UserId)
                    .OnDelete(DeleteBehavior.Cascade);
            });

            // ============================================================
            // InviteRecords
            // ============================================================
            modelBuilder.Entity<InviteRecord>(entity =>
            {
                entity.ToTable("invite_records");

                entity.HasKey(e => e.Id);

                entity.Property(e => e.Id)
                    .HasColumnName("id")
                    .HasMaxLength(36)
                    .IsRequired();

                entity.Property(e => e.InviterUserId)
                    .HasColumnName("inviter_user_id")
                    .HasMaxLength(36)
                    .IsRequired();

                entity.Property(e => e.InviteeUserId)
                    .HasColumnName("invitee_user_id")
                    .HasMaxLength(36)
                    .IsRequired();

                entity.Property(e => e.InviteCode)
                    .HasColumnName("invite_code")
                    .HasMaxLength(16)
                    .IsRequired();

                entity.Property(e => e.InviterBalls)
                    .HasColumnName("inviter_balls");

                entity.Property(e => e.InviteeBalls)
                    .HasColumnName("invitee_balls");

                entity.Property(e => e.CreatedAt)
                    .HasColumnName("created_at")
                    .HasColumnType("datetime");

                entity.HasIndex(e => e.InviterUserId).HasDatabaseName("idx_ir_inviter");
                entity.HasIndex(e => e.InviteeUserId).IsUnique().HasDatabaseName("uk_ir_invitee");

                entity.HasOne(e => e.Inviter)
                    .WithMany()
                    .HasForeignKey(e => e.InviterUserId)
                    .OnDelete(DeleteBehavior.Cascade);

                entity.HasOne(e => e.Invitee)
                    .WithMany()
                    .HasForeignKey(e => e.InviteeUserId)
                    .OnDelete(DeleteBehavior.Restrict);
            });

            // ============================================================
            // PurchaseRecords
            // ============================================================
            modelBuilder.Entity<PurchaseRecord>(entity =>
            {
                entity.ToTable("purchase_records");

                entity.HasKey(e => e.Id);

                entity.Property(e => e.Id)
                    .HasColumnName("id")
                    .HasMaxLength(36)
                    .IsRequired();

                entity.Property(e => e.UserId)
                    .HasColumnName("user_id")
                    .HasMaxLength(36)
                    .IsRequired();

                entity.Property(e => e.Plan)
                    .HasColumnName("plan")
                    .HasMaxLength(50)
                    .IsRequired();

                entity.Property(e => e.Store)
                    .HasColumnName("store")
                    .HasMaxLength(50)
                    .IsRequired();

                entity.Property(e => e.ProductId)
                    .HasColumnName("product_id")
                    .HasMaxLength(100);

                entity.Property(e => e.PurchaseToken)
                    .HasColumnName("purchase_token")
                    .HasColumnType("TEXT")
                    .IsRequired();

                entity.Property(e => e.Status)
                    .HasColumnName("status")
                    .HasMaxLength(20)
                    .HasDefaultValue("pending");

                entity.Property(e => e.CreatedAt)
                    .HasColumnName("created_at")
                    .HasColumnType("datetime");

                entity.Property(e => e.VerifiedAt)
                    .HasColumnName("verified_at")
                    .HasColumnType("datetime");

                entity.HasIndex(e => e.UserId).HasDatabaseName("idx_pr_user_id");
                entity.HasIndex(e => e.Status).HasDatabaseName("idx_pr_status");
                entity.HasIndex(e => e.CreatedAt).HasDatabaseName("idx_pr_created_at");

                entity.HasOne(e => e.User)
                    .WithMany()
                    .HasForeignKey(e => e.UserId)
                    .OnDelete(DeleteBehavior.Cascade);
            });

            // ============================================================
            // ShareLinks
            // ============================================================
            modelBuilder.Entity<ShareLink>(entity =>
            {
                entity.ToTable("share_links");

                entity.HasKey(e => e.Id);

                entity.Property(e => e.Id)
                    .HasColumnName("id")
                    .ValueGeneratedOnAdd();

                entity.Property(e => e.ShareCode)
                    .HasColumnName("share_code")
                    .HasMaxLength(16)
                    .IsRequired();

                entity.Property(e => e.B2FileName)
                    .HasColumnName("b2_file_name")
                    .HasMaxLength(255)
                    .IsRequired();

                entity.Property(e => e.Title)
                    .HasColumnName("title")
                    .HasMaxLength(255);

                entity.Property(e => e.SharerName)
                    .HasColumnName("sharer_name")
                    .HasMaxLength(100);

                entity.Property(e => e.SizeBytes)
                    .HasColumnName("size_bytes");

                entity.Property(e => e.Confirmed)
                    .HasColumnName("confirmed")
                    .HasDefaultValue(false);

                entity.Property(e => e.DownloadCount)
                    .HasColumnName("download_count")
                    .HasDefaultValue(0);

                entity.Property(e => e.CreatedAt)
                    .HasColumnName("created_at")
                    .HasColumnType("datetime");

                entity.Property(e => e.ExpiresAt)
                    .HasColumnName("expires_at")
                    .HasColumnType("datetime");

                entity.HasIndex(e => e.ShareCode)
                    .IsUnique()
                    .HasDatabaseName("idx_share_code");

                entity.HasIndex(e => e.ExpiresAt)
                    .HasDatabaseName("idx_share_expires_at");
            });

            // ============================================================
            // UserFeedbacks
            // ============================================================
            modelBuilder.Entity<UserFeedback>(entity =>
            {
                entity.ToTable("user_feedbacks");

                entity.HasKey(e => e.Id);

                entity.Property(e => e.Id)
                    .HasColumnName("id")
                    .HasMaxLength(36)
                    .IsRequired();

                entity.Property(e => e.UserId)
                    .HasColumnName("user_id")
                    .HasMaxLength(36)
                    .IsRequired();

                entity.Property(e => e.Type)
                    .HasColumnName("type")
                    .HasMaxLength(20)
                    .HasDefaultValue("other");

                entity.Property(e => e.Text)
                    .HasColumnName("text")
                    .HasColumnType("TEXT")
                    .IsRequired();

                entity.Property(e => e.CreatedAt)
                    .HasColumnName("created_at")
                    .HasColumnType("datetime");

                entity.Property(e => e.AttachedVideoId)
                    .HasColumnName("attached_video_id")
                    .HasMaxLength(255)
                    .IsRequired(false);

                entity.Property(e => e.AttachedImageB2Key)
                    .HasColumnName("attached_image_b2_key")
                    .HasMaxLength(500)
                    .IsRequired(false);

                entity.HasIndex(e => e.UserId).HasDatabaseName("idx_feedback_user_id");
                entity.HasIndex(e => e.CreatedAt).HasDatabaseName("idx_feedback_created_at");

                entity.HasOne(f => f.User)
                    .WithMany(u => u.Feedbacks)
                    .HasForeignKey(f => f.UserId)
                    .OnDelete(DeleteBehavior.Cascade);
            });

            // ============================================================
            // AiCoachAnalyses
            // ============================================================
            modelBuilder.Entity<AiCoachAnalysis>(entity =>
            {
                entity.ToTable("ai_coach_analyses");

                entity.HasKey(e => e.Id);

                entity.Property(e => e.Id)
                    .HasColumnName("id")
                    .HasMaxLength(36)
                    .IsRequired();

                entity.Property(e => e.UserId)
                    .HasColumnName("user_id")
                    .HasMaxLength(36)
                    .IsRequired();

                entity.Property(e => e.VideoId)
                    .HasColumnName("video_id")
                    .HasMaxLength(36);

                entity.Property(e => e.Status)
                    .HasColumnName("status")
                    .HasMaxLength(50)
                    .HasDefaultValue("pending");

                entity.Property(e => e.ErrorTypeHint)
                    .HasColumnName("error_type_hint")
                    .HasMaxLength(64);

                entity.Property(e => e.ClipB2Path)
                    .HasColumnName("clip_b2_path")
                    .HasMaxLength(512);

                entity.Property(e => e.CsvB2Path)
                    .HasColumnName("csv_b2_path")
                    .HasMaxLength(512);

                entity.Property(e => e.ResultJson)
                    .HasColumnName("result_json")
                    .HasColumnType("LONGTEXT");

                entity.Property(e => e.Summary)
                    .HasColumnName("summary")
                    .HasColumnType("TEXT");

                entity.Property(e => e.Severity)
                    .HasColumnName("severity")
                    .HasMaxLength(16);

                entity.Property(e => e.RetryCount)
                    .HasColumnName("retry_count")
                    .HasDefaultValue(0);

                entity.Property(e => e.CreatedAt)
                    .HasColumnName("created_at")
                    .HasColumnType("datetime");

                entity.Property(e => e.CompletedAt)
                    .HasColumnName("completed_at")
                    .HasColumnType("datetime");

                entity.Property(e => e.Mode)
                    .HasMaxLength(32)
                    .HasColumnType("varchar(32)")
                    .HasDefaultValue("full");

                entity.Property(e => e.PromptVersion)
                    .HasMaxLength(8)
                    .HasColumnType("varchar(8)")
                    .HasDefaultValue("v1");

                entity.Property(e => e.PhaseTimestampsJson)
                    .HasColumnName("phase_timestamps_json")
                    .HasColumnType("TEXT");

                entity.Property(e => e.AudioAnalysisJson)
                    .HasColumnName("audio_analysis_json")
                    .HasColumnType("LONGTEXT");

                entity.Property(e => e.KeyframesJson)
                    .HasColumnName("keyframes_json")
                    .HasColumnType("LONGTEXT");

                entity.Property(e => e.AudioB2Path)
                    .HasColumnName("audio_b2_path")
                    .HasMaxLength(512);

                entity.Property(e => e.V2Fps)
                    .HasColumnName("v2_fps");

                entity.Property(e => e.V2Resolution)
                    .HasColumnName("v2_resolution")
                    .HasMaxLength(64);

                entity.HasIndex(e => e.UserId).HasDatabaseName("idx_ai_coach_user_id");
                entity.HasIndex(e => e.Status).HasDatabaseName("idx_ai_coach_status");

                entity.HasOne(e => e.User)
                    .WithMany()
                    .HasForeignKey(e => e.UserId)
                    .OnDelete(DeleteBehavior.Cascade);
            });

            // ============================================================
            // PasswordResetTokens
            // ============================================================
            modelBuilder.Entity<PasswordResetToken>(entity =>
            {
                entity.ToTable("password_reset_tokens");

                entity.HasKey(e => e.Id);

                entity.Property(e => e.Id)
                    .HasColumnName("id")
                    .HasMaxLength(36)
                    .IsRequired();

                entity.Property(e => e.UserId)
                    .HasColumnName("user_id")
                    .HasMaxLength(36)
                    .IsRequired();

                entity.Property(e => e.CodeHash)
                    .HasColumnName("code_hash")
                    .HasMaxLength(255)
                    .IsRequired();

                entity.Property(e => e.ExpiresAt)
                    .HasColumnName("expires_at")
                    .HasColumnType("datetime");

                entity.Property(e => e.IsUsed)
                    .HasColumnName("is_used")
                    .HasDefaultValue(false);

                entity.Property(e => e.CreatedAt)
                    .HasColumnName("created_at")
                    .HasColumnType("datetime");

                entity.HasIndex(e => e.UserId).HasDatabaseName("idx_prt_user_id");
                entity.HasIndex(e => e.ExpiresAt).HasDatabaseName("idx_prt_expires_at");

                entity.HasOne(e => e.User)
                    .WithMany()
                    .HasForeignKey(e => e.UserId)
                    .OnDelete(DeleteBehavior.Cascade);
            });

            // ============================================================
            // AppVersions
            // ============================================================
            modelBuilder.Entity<AppVersion>(entity =>
            {
                entity.ToTable("app_versions");

                entity.HasKey(e => e.Id);

                entity.Property(e => e.Id)
                    .HasColumnName("id")
                    .ValueGeneratedOnAdd();

                entity.Property(e => e.Platform)
                    .HasColumnName("platform")
                    .HasMaxLength(16)
                    .IsRequired();

                entity.Property(e => e.LatestVersion)
                    .HasColumnName("latest_version")
                    .HasMaxLength(20)
                    .IsRequired();

                entity.Property(e => e.MinRequiredVersion)
                    .HasColumnName("min_required_version")
                    .HasMaxLength(20)
                    .IsRequired();

                entity.Property(e => e.ForceUpdate)
                    .HasColumnName("force_update")
                    .HasDefaultValue(false);

                entity.Property(e => e.UpdateUrl)
                    .HasColumnName("update_url")
                    .HasMaxLength(500);

                entity.Property(e => e.ReleaseNotesJson)
                    .HasColumnName("release_notes_json")
                    .HasColumnType("TEXT")
                    .HasDefaultValue("[]");

                entity.Property(e => e.ReleaseDate)
                    .HasColumnName("release_date")
                    .HasMaxLength(20);

                entity.Property(e => e.UpdatedAt)
                    .HasColumnName("updated_at")
                    .HasColumnType("datetime");

                entity.HasIndex(e => e.Platform)
                    .IsUnique()
                    .HasDatabaseName("uk_appversion_platform");
            });

            // ============================================================
            // Announcements
            // ============================================================
            modelBuilder.Entity<Announcement>(entity =>
            {
                entity.ToTable("announcements");

                entity.HasKey(e => e.Id);

                entity.Property(e => e.Id)
                    .HasColumnName("id")
                    .HasMaxLength(36)
                    .IsRequired();

                entity.Property(e => e.Title)
                    .HasColumnName("title")
                    .HasMaxLength(255)
                    .IsRequired();

                entity.Property(e => e.Body)
                    .HasColumnName("body")
                    .HasColumnType("TEXT")
                    .IsRequired();

                entity.Property(e => e.Type)
                    .HasColumnName("type")
                    .HasMaxLength(20)
                    .HasDefaultValue("info");

                entity.Property(e => e.PublishedAt)
                    .HasColumnName("published_at")
                    .HasColumnType("datetime");

                entity.Property(e => e.ExpiresAt)
                    .HasColumnName("expires_at")
                    .HasColumnType("datetime");

                entity.Property(e => e.ImageUrl)
                    .HasColumnName("image_url")
                    .HasMaxLength(500);

                entity.Property(e => e.IsActive)
                    .HasColumnName("is_active")
                    .HasDefaultValue(true);

                entity.Property(e => e.CreatedAt)
                    .HasColumnName("created_at")
                    .HasColumnType("datetime");

                entity.Property(e => e.UpdatedAt)
                    .HasColumnName("updated_at")
                    .HasColumnType("datetime");

                entity.HasIndex(e => e.IsActive).HasDatabaseName("idx_ann_is_active");
                entity.HasIndex(e => e.PublishedAt).HasDatabaseName("idx_ann_published_at");
                entity.HasIndex(e => e.ExpiresAt).HasDatabaseName("idx_ann_expires_at");
            });
        }
    }
}
