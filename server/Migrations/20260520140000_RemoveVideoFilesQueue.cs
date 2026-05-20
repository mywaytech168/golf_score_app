using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace UploadServer.Migrations
{
    /// <inheritdoc />
    public partial class RemoveVideoFilesQueue : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            // ── ai_coach_analyses: drop old FK → videos, add user_id ──
            migrationBuilder.DropForeignKey(
                name: "FK_ai_coach_analyses_videos_video_id",
                table: "ai_coach_analyses");

            migrationBuilder.DropIndex(
                name: "idx_ai_coach_video_id",
                table: "ai_coach_analyses");

            // Make video_id nullable (it was NOT NULL before)
            migrationBuilder.AlterColumn<string>(
                name: "video_id",
                table: "ai_coach_analyses",
                type: "varchar(36)",
                maxLength: 36,
                nullable: true,
                oldClrType: typeof(string),
                oldType: "varchar(36)",
                oldMaxLength: 36)
                .Annotation("MySql:CharSet", "utf8mb4")
                .OldAnnotation("MySql:CharSet", "utf8mb4");

            // Add user_id column
            migrationBuilder.AddColumn<string>(
                name: "user_id",
                table: "ai_coach_analyses",
                type: "varchar(36)",
                maxLength: 36,
                nullable: false,
                defaultValue: "");

            // Back-fill user_id from videos for existing rows (best-effort)
            migrationBuilder.Sql(
                @"UPDATE ai_coach_analyses aca
                  JOIN videos v ON v.id = aca.video_id
                  SET aca.user_id = v.user_id
                  WHERE aca.user_id = ''");

            // Any orphan rows get a sentinel user_id so FK won't reject them on insert
            // (they'll naturally have no user and won't appear in any user's results)

            migrationBuilder.CreateIndex(
                name: "idx_ai_coach_user_id",
                table: "ai_coach_analyses",
                column: "user_id");

            migrationBuilder.AddForeignKey(
                name: "FK_ai_coach_analyses_users_user_id",
                table: "ai_coach_analyses",
                column: "user_id",
                principalTable: "users",
                principalColumn: "id",
                onDelete: ReferentialAction.Cascade);

            // ── Drop child tables first ───────────────────────────────
            migrationBuilder.DropTable(name: "files");
            migrationBuilder.DropTable(name: "process_queue");

            // ── Drop parent table ─────────────────────────────────────
            migrationBuilder.DropTable(name: "videos");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            // Recreate videos
            migrationBuilder.CreateTable(
                name: "videos",
                columns: table => new
                {
                    id             = table.Column<string>(type: "varchar(36)", maxLength: 36, nullable: false).Annotation("MySql:CharSet", "utf8mb4"),
                    user_id        = table.Column<string>(type: "varchar(36)", maxLength: 36, nullable: false).Annotation("MySql:CharSet", "utf8mb4"),
                    name           = table.Column<string>(type: "varchar(255)", maxLength: 255, nullable: false).Annotation("MySql:CharSet", "utf8mb4"),
                    status         = table.Column<string>(type: "varchar(50)", maxLength: 50, nullable: false, defaultValue: "pending").Annotation("MySql:CharSet", "utf8mb4"),
                    type           = table.Column<string>(type: "varchar(50)", maxLength: 50, nullable: false, defaultValue: "original").Annotation("MySql:CharSet", "utf8mb4"),
                    parent_video_id = table.Column<string>(type: "varchar(36)", maxLength: 36, nullable: true).Annotation("MySql:CharSet", "utf8mb4"),
                    hit_second     = table.Column<double>(type: "DOUBLE", nullable: true),
                    start_second   = table.Column<double>(type: "DOUBLE", nullable: true),
                    end_second     = table.Column<double>(type: "DOUBLE", nullable: true),
                    peak_value     = table.Column<double>(type: "DOUBLE", nullable: true),
                    good_shot      = table.Column<bool>(type: "tinyint(1)", nullable: true),
                    audio_crispness = table.Column<double>(type: "DOUBLE", nullable: true),
                    created_at     = table.Column<DateTime>(type: "datetime", nullable: false),
                    updated_at     = table.Column<DateTime>(type: "datetime", nullable: false),
                    completed_at   = table.Column<DateTime>(type: "datetime", nullable: true),
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_videos", x => x.id);
                    table.ForeignKey(name: "FK_videos_users_user_id", column: x => x.user_id, principalTable: "users", principalColumn: "id", onDelete: ReferentialAction.Cascade);
                })
                .Annotation("MySql:CharSet", "utf8mb4");

            // Recreate files
            migrationBuilder.CreateTable(
                name: "files",
                columns: table => new
                {
                    id            = table.Column<string>(type: "varchar(36)", maxLength: 36, nullable: false).Annotation("MySql:CharSet", "utf8mb4"),
                    video_id      = table.Column<string>(type: "varchar(36)", maxLength: 36, nullable: false).Annotation("MySql:CharSet", "utf8mb4"),
                    type          = table.Column<string>(type: "varchar(50)", maxLength: 50, nullable: false).Annotation("MySql:CharSet", "utf8mb4"),
                    file_name     = table.Column<string>(type: "varchar(255)", maxLength: 255, nullable: false).Annotation("MySql:CharSet", "utf8mb4"),
                    file_path     = table.Column<string>(type: "varchar(500)", maxLength: 500, nullable: false).Annotation("MySql:CharSet", "utf8mb4"),
                    file_size     = table.Column<long>(type: "bigint", nullable: false, defaultValue: 0L),
                    mime_type     = table.Column<string>(type: "varchar(100)", maxLength: 100, nullable: false).Annotation("MySql:CharSet", "utf8mb4"),
                    status        = table.Column<string>(type: "varchar(50)", maxLength: 50, nullable: false, defaultValue: "pending").Annotation("MySql:CharSet", "utf8mb4"),
                    created_at    = table.Column<DateTime>(type: "datetime", nullable: false),
                    completed_at  = table.Column<DateTime>(type: "datetime", nullable: true),
                    error_message = table.Column<string>(type: "TEXT", nullable: true).Annotation("MySql:CharSet", "utf8mb4"),
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_files", x => x.id);
                    table.ForeignKey(name: "FK_files_videos_video_id", column: x => x.video_id, principalTable: "videos", principalColumn: "id", onDelete: ReferentialAction.Cascade);
                })
                .Annotation("MySql:CharSet", "utf8mb4");

            // Recreate process_queue
            migrationBuilder.CreateTable(
                name: "process_queue",
                columns: table => new
                {
                    id          = table.Column<string>(type: "varchar(36)", maxLength: 36, nullable: false).Annotation("MySql:CharSet", "utf8mb4"),
                    video_id    = table.Column<string>(type: "varchar(36)", maxLength: 36, nullable: false).Annotation("MySql:CharSet", "utf8mb4"),
                    status      = table.Column<string>(type: "varchar(50)", maxLength: 50, nullable: false, defaultValue: "queued").Annotation("MySql:CharSet", "utf8mb4"),
                    created_at  = table.Column<DateTime>(type: "datetime", nullable: false),
                    started_at  = table.Column<DateTime>(type: "datetime", nullable: true),
                    completed_at = table.Column<DateTime>(type: "datetime", nullable: true),
                    retry_count = table.Column<int>(type: "int", nullable: false, defaultValue: 0),
                    is_success  = table.Column<bool>(type: "tinyint(1)", nullable: false, defaultValue: false),
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_process_queue", x => x.id);
                    table.ForeignKey(name: "FK_process_queue_videos_video_id", column: x => x.video_id, principalTable: "videos", principalColumn: "id", onDelete: ReferentialAction.Cascade);
                })
                .Annotation("MySql:CharSet", "utf8mb4");

            // Revert ai_coach_analyses
            migrationBuilder.DropForeignKey(name: "FK_ai_coach_analyses_users_user_id", table: "ai_coach_analyses");
            migrationBuilder.DropIndex(name: "idx_ai_coach_user_id", table: "ai_coach_analyses");
            migrationBuilder.DropColumn(name: "user_id", table: "ai_coach_analyses");

            migrationBuilder.AlterColumn<string>(
                name: "video_id",
                table: "ai_coach_analyses",
                type: "varchar(36)",
                maxLength: 36,
                nullable: false,
                oldClrType: typeof(string),
                oldType: "varchar(36)",
                oldMaxLength: 36,
                oldNullable: true)
                .Annotation("MySql:CharSet", "utf8mb4")
                .OldAnnotation("MySql:CharSet", "utf8mb4");

            migrationBuilder.CreateIndex(name: "idx_ai_coach_video_id", table: "ai_coach_analyses", column: "video_id");

            migrationBuilder.AddForeignKey(
                name: "FK_ai_coach_analyses_videos_video_id",
                table: "ai_coach_analyses",
                column: "video_id",
                principalTable: "videos",
                principalColumn: "id",
                onDelete: ReferentialAction.Cascade);
        }
    }
}
