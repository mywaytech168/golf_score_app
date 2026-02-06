using Microsoft.EntityFrameworkCore;
using UploadServer.Models;
using FileModel = UploadServer.Models.File;

namespace UploadServer.Data
{
    /// <summary>
    /// Code-First DbContext for Golf Video Management System
    /// EF Core will generate database schema from these model definitions
    /// 
    /// Schema Design (All using UUID):
    /// - users: 用戶帳戶
    /// - videos: 影片主檔（原始錄影和切片）
    /// - files: 檔案追蹤（原始影片、切片、軌跡數據）
    /// - process_queue: 處理隊列（排隊中、處理中、已處理）
    /// </summary>
    public class VideoDbContext : DbContext
    {
        public VideoDbContext(DbContextOptions<VideoDbContext> options) : base(options)
        {
        }

        // DbSets for each entity
        public DbSet<User> Users { get; set; }
        public DbSet<Video> Videos { get; set; }
        public DbSet<FileModel> Files { get; set; }
        public DbSet<ProcessQueueItem> ProcessQueueItems { get; set; }

        protected override void OnModelCreating(ModelBuilder modelBuilder)
        {
            base.OnModelCreating(modelBuilder);

            // ============================================================
            // Users Table Configuration
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

                entity.Property(e => e.PasswordHash)
                    .HasColumnName("password_hash")
                    .HasMaxLength(255)
                    .IsRequired();

                entity.Property(e => e.DisplayName)
                    .HasColumnName("display_name")
                    .HasMaxLength(255);

                entity.Property(e => e.GoogleId)
                    .HasColumnName("google_id")
                    .HasMaxLength(255);

                entity.Property(e => e.AvatarUrl)
                    .HasColumnName("avatar_url")
                    .HasMaxLength(500);

                entity.Property(e => e.Provider)
                    .HasColumnName("provider")
                    .HasMaxLength(50)
                    .HasDefaultValue("local");

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

                // Unique indexes
                entity.HasIndex(e => e.Username).IsUnique().HasDatabaseName("uk_username");
                entity.HasIndex(e => e.Email).IsUnique().HasDatabaseName("uk_email");
                entity.HasIndex(e => e.GoogleId).IsUnique().HasDatabaseName("uk_google_id");

                // Regular indexes
                entity.HasIndex(e => e.Status).HasDatabaseName("idx_user_status");
                entity.HasIndex(e => e.CreatedAt).HasDatabaseName("idx_user_created_at");

                // One-to-Many relationship with Videos
                entity.HasMany(u => u.Videos)
                    .WithOne(v => v.User)
                    .HasForeignKey(v => v.UserId)
                    .OnDelete(DeleteBehavior.Cascade);
            });

            // ============================================================
            // Videos Table Configuration
            // ============================================================
            modelBuilder.Entity<Video>(entity =>
            {
                entity.ToTable("videos");

                entity.HasKey(e => e.Id);

                entity.Property(e => e.Id)
                    .HasColumnName("id")
                    .HasMaxLength(36)
                    .IsRequired();

                entity.Property(e => e.UserId)
                    .HasColumnName("user_id")
                    .HasMaxLength(36)
                    .IsRequired();

                entity.Property(e => e.Name)
                    .HasColumnName("name")
                    .HasMaxLength(255)
                    .IsRequired();

                entity.Property(e => e.Status)
                    .HasColumnName("status")
                    .HasMaxLength(50)
                    .HasDefaultValue("pending");

                entity.Property(e => e.Type)
                    .HasColumnName("type")
                    .HasMaxLength(50)
                    .HasDefaultValue("original");

                entity.Property(e => e.ParentVideoId)
                    .HasColumnName("parent_video_id")
                    .HasMaxLength(36);

                entity.Property(e => e.HitSecond)
                    .HasColumnName("hit_second")
                    .HasColumnType("DOUBLE");

                entity.Property(e => e.StartSecond)
                    .HasColumnName("start_second")
                    .HasColumnType("DOUBLE");

                entity.Property(e => e.EndSecond)
                    .HasColumnName("end_second")
                    .HasColumnType("DOUBLE");

                entity.Property(e => e.PeakValue)
                    .HasColumnName("peak_value")
                    .HasColumnType("DOUBLE");

                entity.Property(e => e.GoodShot)
                    .HasColumnName("good_shot");

                entity.Property(e => e.AudioCrispness)
                    .HasColumnName("audio_crispness")
                    .HasColumnType("DOUBLE");

                entity.Property(e => e.CreatedAt)
                    .HasColumnName("created_at")
                    .HasColumnType("datetime");

                entity.Property(e => e.UpdatedAt)
                    .HasColumnName("updated_at")
                    .HasColumnType("datetime");

                entity.Property(e => e.CompletedAt)
                    .HasColumnName("completed_at")
                    .HasColumnType("datetime");

                // Indexes
                entity.HasIndex(e => e.UserId).HasDatabaseName("idx_video_user_id");
                entity.HasIndex(e => e.Status).HasDatabaseName("idx_video_status");
                entity.HasIndex(e => e.Type).HasDatabaseName("idx_video_type");
                entity.HasIndex(e => e.CreatedAt).HasDatabaseName("idx_video_created_at");
                entity.HasIndex(e => e.ParentVideoId).HasDatabaseName("idx_video_parent_id");

                // Foreign Key relationship with User
                entity.HasOne(v => v.User)
                    .WithMany(u => u.Videos)
                    .HasForeignKey(v => v.UserId)
                    .OnDelete(DeleteBehavior.Cascade);

                // One-to-Many relationship with Files
                entity.HasMany(v => v.Files)
                    .WithOne(f => f.Video)
                    .HasForeignKey(f => f.VideoId)
                    .OnDelete(DeleteBehavior.Cascade);

                // One-to-Many relationship with ProcessQueueItems
                entity.HasMany(v => v.QueueItems)
                    .WithOne(q => q.Video)
                    .HasForeignKey(q => q.VideoId)
                    .OnDelete(DeleteBehavior.Cascade);
            });

            // ============================================================
            // Files Table Configuration
            // ============================================================
            modelBuilder.Entity<FileModel>(entity =>
            {
                entity.ToTable("files");

                entity.HasKey(e => e.Id);

                entity.Property(e => e.Id)
                    .HasColumnName("id")
                    .HasMaxLength(36)
                    .IsRequired();

                entity.Property(e => e.VideoId)
                    .HasColumnName("video_id")
                    .HasMaxLength(36)
                    .IsRequired();

                entity.Property(e => e.Type)
                    .HasColumnName("type")
                    .HasMaxLength(50)
                    .IsRequired();

                entity.Property(e => e.FileName)
                    .HasColumnName("file_name")
                    .HasMaxLength(255)
                    .IsRequired();

                entity.Property(e => e.FilePath)
                    .HasColumnName("file_path")
                    .HasMaxLength(500)
                    .IsRequired();

                entity.Property(e => e.FileSize)
                    .HasColumnName("file_size")
                    .HasDefaultValue(0);

                entity.Property(e => e.MimeType)
                    .HasColumnName("mime_type")
                    .HasMaxLength(100);

                entity.Property(e => e.Status)
                    .HasColumnName("status")
                    .HasMaxLength(50)
                    .HasDefaultValue("pending");

                entity.Property(e => e.CreatedAt)
                    .HasColumnName("created_at")
                    .HasColumnType("datetime");

                entity.Property(e => e.CompletedAt)
                    .HasColumnName("completed_at")
                    .HasColumnType("datetime");

                entity.Property(e => e.ErrorMessage)
                    .HasColumnName("error_message")
                    .HasColumnType("TEXT");

                // Indexes
                entity.HasIndex(e => e.VideoId).HasDatabaseName("idx_file_video_id");
                entity.HasIndex(e => e.Type).HasDatabaseName("idx_file_type");
                entity.HasIndex(e => e.Status).HasDatabaseName("idx_file_status");
                entity.HasIndex(e => new { e.VideoId, e.Type }).HasDatabaseName("idx_file_video_type");

                // Foreign Key relationship with Video
                entity.HasOne(f => f.Video)
                    .WithMany(v => v.Files)
                    .HasForeignKey(f => f.VideoId)
                    .OnDelete(DeleteBehavior.Cascade);
            });

            // ============================================================
            // ProcessQueue Table Configuration
            // ============================================================
            modelBuilder.Entity<ProcessQueueItem>(entity =>
            {
                entity.ToTable("process_queue");

                entity.HasKey(e => e.Id);

                entity.Property(e => e.Id)
                    .HasColumnName("id")
                    .HasMaxLength(36)
                    .IsRequired();

                entity.Property(e => e.VideoId)
                    .HasColumnName("video_id")
                    .HasMaxLength(36)
                    .IsRequired();

                entity.Property(e => e.Status)
                    .HasColumnName("status")
                    .HasMaxLength(50)
                    .HasDefaultValue("queued");

                entity.Property(e => e.CreatedAt)
                    .HasColumnName("created_at")
                    .HasColumnType("datetime");

                entity.Property(e => e.StartedAt)
                    .HasColumnName("started_at")
                    .HasColumnType("datetime");

                entity.Property(e => e.CompletedAt)
                    .HasColumnName("completed_at")
                    .HasColumnType("datetime");

                entity.Property(e => e.RetryCount)
                    .HasColumnName("retry_count")
                    .HasDefaultValue(0);

                entity.Property(e => e.IsSuccess)
                    .HasColumnName("is_success")
                    .HasDefaultValue(false);

                // Indexes
                entity.HasIndex(e => e.VideoId).HasDatabaseName("idx_queue_video_id");
                entity.HasIndex(e => e.Status).HasDatabaseName("idx_queue_status");
                entity.HasIndex(e => e.IsSuccess).HasDatabaseName("idx_queue_is_success");
                entity.HasIndex(e => new { e.CompletedAt, e.Status })
                    .HasDatabaseName("idx_queue_completed_status");
                entity.HasIndex(e => new { e.Status, e.CreatedAt })
                    .HasDatabaseName("idx_queue_status_created");

                // Foreign Key relationship with Video
                entity.HasOne(q => q.Video)
                    .WithMany(v => v.QueueItems)
                    .HasForeignKey(q => q.VideoId)
                    .OnDelete(DeleteBehavior.Cascade);
            });
        }
    }
}
