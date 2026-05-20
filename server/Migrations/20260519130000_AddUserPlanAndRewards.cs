using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace UploadServer.Migrations
{
    /// <inheritdoc />
    public partial class AddUserPlanAndRewards : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            // ── 新增 users 方案與獎勵欄位 ──────────────────────────────
            migrationBuilder.AddColumn<string>(
                name: "plan",
                table: "users",
                type: "varchar(50)",
                maxLength: 50,
                nullable: false,
                defaultValue: "free")
                .Annotation("MySql:CharSet", "utf8mb4");

            migrationBuilder.AddColumn<int>(
                name: "bonus_balls",
                table: "users",
                type: "int",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<int>(
                name: "today_used",
                table: "users",
                type: "int",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<DateOnly>(
                name: "today_used_date",
                table: "users",
                type: "date",
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "ad_claimed_today",
                table: "users",
                type: "int",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<DateOnly>(
                name: "ad_claimed_date",
                table: "users",
                type: "date",
                nullable: true);

            migrationBuilder.AddColumn<DateOnly>(
                name: "feedback_claimed_date",
                table: "users",
                type: "date",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "invite_code",
                table: "users",
                type: "varchar(16)",
                maxLength: 16,
                nullable: true)
                .Annotation("MySql:CharSet", "utf8mb4");

            migrationBuilder.AddColumn<int>(
                name: "invite_count",
                table: "users",
                type: "int",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<string>(
                name: "invited_by_code",
                table: "users",
                type: "varchar(16)",
                maxLength: 16,
                nullable: true)
                .Annotation("MySql:CharSet", "utf8mb4");

            migrationBuilder.CreateIndex(
                name: "uk_invite_code",
                table: "users",
                column: "invite_code",
                unique: true);

            // ── 建立 user_feedbacks 資料表 ─────────────────────────────
            migrationBuilder.CreateTable(
                name: "user_feedbacks",
                columns: table => new
                {
                    id = table.Column<string>(type: "varchar(36)", maxLength: 36, nullable: false)
                        .Annotation("MySql:CharSet", "utf8mb4"),
                    user_id = table.Column<string>(type: "varchar(36)", maxLength: 36, nullable: false)
                        .Annotation("MySql:CharSet", "utf8mb4"),
                    type = table.Column<string>(type: "varchar(20)", maxLength: 20, nullable: false, defaultValue: "other")
                        .Annotation("MySql:CharSet", "utf8mb4"),
                    text = table.Column<string>(type: "TEXT", nullable: false)
                        .Annotation("MySql:CharSet", "utf8mb4"),
                    created_at = table.Column<DateTime>(type: "datetime", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_user_feedbacks", x => x.id);
                    table.ForeignKey(
                        name: "FK_user_feedbacks_users_user_id",
                        column: x => x.user_id,
                        principalTable: "users",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                })
                .Annotation("MySql:CharSet", "utf8mb4");

            migrationBuilder.CreateIndex(
                name: "idx_feedback_user_id",
                table: "user_feedbacks",
                column: "user_id");

            migrationBuilder.CreateIndex(
                name: "idx_feedback_created_at",
                table: "user_feedbacks",
                column: "created_at");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(name: "user_feedbacks");

            migrationBuilder.DropIndex(name: "uk_invite_code", table: "users");

            migrationBuilder.DropColumn(name: "plan", table: "users");
            migrationBuilder.DropColumn(name: "bonus_balls", table: "users");
            migrationBuilder.DropColumn(name: "today_used", table: "users");
            migrationBuilder.DropColumn(name: "today_used_date", table: "users");
            migrationBuilder.DropColumn(name: "ad_claimed_today", table: "users");
            migrationBuilder.DropColumn(name: "ad_claimed_date", table: "users");
            migrationBuilder.DropColumn(name: "feedback_claimed_date", table: "users");
            migrationBuilder.DropColumn(name: "invite_code", table: "users");
            migrationBuilder.DropColumn(name: "invite_count", table: "users");
            migrationBuilder.DropColumn(name: "invited_by_code", table: "users");
        }
    }
}
