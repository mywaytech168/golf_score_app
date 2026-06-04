using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace UploadServer.Migrations
{
    /// <inheritdoc />
    public partial class AddBallTrajectoryAnalysis : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "ball_trajectory_analyses",
                columns: table => new
                {
                    id = table.Column<string>(type: "varchar(36)", maxLength: 36, nullable: false)
                        .Annotation("MySql:CharSet", "utf8mb4"),
                    user_id = table.Column<string>(type: "varchar(36)", maxLength: 36, nullable: false)
                        .Annotation("MySql:CharSet", "utf8mb4"),
                    video_id = table.Column<string>(type: "varchar(255)", maxLength: 255, nullable: true)
                        .Annotation("MySql:CharSet", "utf8mb4"),
                    status = table.Column<string>(type: "varchar(50)", maxLength: 50, nullable: false, defaultValue: "pending")
                        .Annotation("MySql:CharSet", "utf8mb4"),
                    clip_b2_path = table.Column<string>(type: "varchar(512)", maxLength: 512, nullable: true)
                        .Annotation("MySql:CharSet", "utf8mb4"),
                    hit_sec = table.Column<double>(type: "double", nullable: true),
                    flip_mode = table.Column<int>(type: "int", nullable: false, defaultValue: 0),
                    roi_cx_ratio = table.Column<double>(type: "double", nullable: false),
                    roi_cy_ratio = table.Column<double>(type: "double", nullable: false),
                    roi_radius = table.Column<int>(type: "int", nullable: false, defaultValue: 200),
                    track_pts_json = table.Column<string>(type: "MEDIUMTEXT", nullable: true)
                        .Annotation("MySql:CharSet", "utf8mb4"),
                    video_fps = table.Column<double>(type: "double", nullable: true),
                    video_width = table.Column<int>(type: "int", nullable: true),
                    video_height = table.Column<int>(type: "int", nullable: true),
                    video_rotation = table.Column<int>(type: "int", nullable: true),
                    error_message = table.Column<string>(type: "varchar(1024)", maxLength: 1024, nullable: true)
                        .Annotation("MySql:CharSet", "utf8mb4"),
                    retry_count = table.Column<int>(type: "int", nullable: false, defaultValue: 0),
                    created_at = table.Column<DateTime>(type: "datetime", nullable: false),
                    completed_at = table.Column<DateTime>(type: "datetime", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_ball_trajectory_analyses", x => x.id);
                    table.ForeignKey(
                        name: "fk_btraj_user",
                        column: x => x.user_id,
                        principalTable: "users",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                })
                .Annotation("MySql:CharSet", "utf8mb4");

            migrationBuilder.CreateIndex(
                name: "idx_btraj_created_at",
                table: "ball_trajectory_analyses",
                column: "created_at");

            migrationBuilder.CreateIndex(
                name: "idx_btraj_status",
                table: "ball_trajectory_analyses",
                column: "status");

            migrationBuilder.CreateIndex(
                name: "idx_btraj_user_id",
                table: "ball_trajectory_analyses",
                column: "user_id");

            migrationBuilder.CreateIndex(
                name: "idx_btraj_video_id",
                table: "ball_trajectory_analyses",
                column: "video_id");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "ball_trajectory_analyses");
        }
    }
}
