using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace UploadServer.Migrations
{
    /// <inheritdoc />
    public partial class RefactorUserAuth : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            // ── 1. 建立 user_auths 表 ───────────────────────────────
            migrationBuilder.CreateTable(
                name: "user_auths",
                columns: table => new
                {
                    id = table.Column<string>(type: "varchar(36)", maxLength: 36, nullable: false)
                        .Annotation("MySql:CharSet", "utf8mb4"),
                    user_id = table.Column<string>(type: "varchar(36)", maxLength: 36, nullable: false)
                        .Annotation("MySql:CharSet", "utf8mb4"),
                    provider = table.Column<string>(type: "varchar(50)", maxLength: 50, nullable: false)
                        .Annotation("MySql:CharSet", "utf8mb4"),
                    provider_user_id = table.Column<string>(type: "varchar(255)", maxLength: 255, nullable: false)
                        .Annotation("MySql:CharSet", "utf8mb4"),
                    credential_hash = table.Column<string>(type: "varchar(255)", maxLength: 255, nullable: true)
                        .Annotation("MySql:CharSet", "utf8mb4"),
                    metadata_json = table.Column<string>(type: "TEXT", nullable: true)
                        .Annotation("MySql:CharSet", "utf8mb4"),
                    created_at = table.Column<DateTime>(type: "datetime", nullable: false),
                    last_used_at = table.Column<DateTime>(type: "datetime", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_user_auths", x => x.id);
                    table.ForeignKey(
                        name: "FK_user_auths_users_user_id",
                        column: x => x.user_id,
                        principalTable: "users",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                })
                .Annotation("MySql:CharSet", "utf8mb4");

            migrationBuilder.CreateIndex(
                name: "uk_auth_provider_uid",
                table: "user_auths",
                columns: new[] { "provider", "provider_user_id" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "idx_auth_user_id",
                table: "user_auths",
                column: "user_id");

            // ── 2. 遷移現有資料到 user_auths ────────────────────────
            // local 帳號：provider_user_id = email，credential_hash = password_hash
            migrationBuilder.Sql(@"
                INSERT INTO user_auths (id, user_id, provider, provider_user_id, credential_hash, created_at)
                SELECT
                    UUID()           AS id,
                    id               AS user_id,
                    'local'          AS provider,
                    email            AS provider_user_id,
                    password_hash    AS credential_hash,
                    created_at
                FROM users
                WHERE provider = 'local'
                  AND password_hash IS NOT NULL
                  AND password_hash != '[GOOGLE_AUTH]';
            ");

            // Google 帳號：provider_user_id = google_id
            migrationBuilder.Sql(@"
                INSERT INTO user_auths (id, user_id, provider, provider_user_id, created_at)
                SELECT
                    UUID()      AS id,
                    id          AS user_id,
                    'google'    AS provider,
                    google_id   AS provider_user_id,
                    created_at
                FROM users
                WHERE provider = 'google'
                  AND google_id IS NOT NULL;
            ");

            // ── 3. 移除 users 表中的舊欄位 ──────────────────────────
            migrationBuilder.DropIndex(
                name: "uk_google_id",
                table: "users");

            migrationBuilder.DropColumn(
                name: "password_hash",
                table: "users");

            migrationBuilder.DropColumn(
                name: "google_id",
                table: "users");

            migrationBuilder.DropColumn(
                name: "provider",
                table: "users");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            // ── 還原：重建 users 的舊欄位 ───────────────────────────
            migrationBuilder.AddColumn<string>(
                name: "password_hash",
                table: "users",
                type: "varchar(255)",
                maxLength: 255,
                nullable: false,
                defaultValue: "")
                .Annotation("MySql:CharSet", "utf8mb4");

            migrationBuilder.AddColumn<string>(
                name: "google_id",
                table: "users",
                type: "varchar(255)",
                maxLength: 255,
                nullable: true)
                .Annotation("MySql:CharSet", "utf8mb4");

            migrationBuilder.AddColumn<string>(
                name: "provider",
                table: "users",
                type: "varchar(50)",
                maxLength: 50,
                nullable: false,
                defaultValue: "local")
                .Annotation("MySql:CharSet", "utf8mb4");

            // 還原資料
            migrationBuilder.Sql(@"
                UPDATE users u
                JOIN user_auths a ON a.user_id = u.id AND a.provider = 'local'
                SET u.password_hash = a.credential_hash,
                    u.provider = 'local';
            ");

            migrationBuilder.Sql(@"
                UPDATE users u
                JOIN user_auths a ON a.user_id = u.id AND a.provider = 'google'
                SET u.google_id = a.provider_user_id,
                    u.provider = 'google';
            ");

            migrationBuilder.CreateIndex(
                name: "uk_google_id",
                table: "users",
                column: "google_id",
                unique: true);

            // 移除 user_auths 表
            migrationBuilder.DropTable(
                name: "user_auths");
        }
    }
}
