using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace UploadServer.Migrations
{
    /// <inheritdoc />
    public partial class AddAnnouncements : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "announcements",
                columns: table => new
                {
                    id = table.Column<string>(type: "varchar(36)", maxLength: 36, nullable: false)
                        .Annotation("MySql:CharSet", "utf8mb4"),
                    title = table.Column<string>(type: "varchar(255)", maxLength: 255, nullable: false)
                        .Annotation("MySql:CharSet", "utf8mb4"),
                    body = table.Column<string>(type: "TEXT", nullable: false)
                        .Annotation("MySql:CharSet", "utf8mb4"),
                    type = table.Column<string>(type: "varchar(20)", maxLength: 20, nullable: false, defaultValue: "info")
                        .Annotation("MySql:CharSet", "utf8mb4"),
                    published_at = table.Column<DateTime>(type: "datetime", nullable: false),
                    expires_at = table.Column<DateTime>(type: "datetime", nullable: true),
                    image_url = table.Column<string>(type: "varchar(500)", maxLength: 500, nullable: true)
                        .Annotation("MySql:CharSet", "utf8mb4"),
                    is_active = table.Column<bool>(type: "tinyint(1)", nullable: false, defaultValue: true),
                    created_at = table.Column<DateTime>(type: "datetime", nullable: false),
                    updated_at = table.Column<DateTime>(type: "datetime", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_announcements", x => x.id);
                })
                .Annotation("MySql:CharSet", "utf8mb4");

            migrationBuilder.CreateIndex(
                name: "idx_ann_expires_at",
                table: "announcements",
                column: "expires_at");

            migrationBuilder.CreateIndex(
                name: "idx_ann_is_active",
                table: "announcements",
                column: "is_active");

            migrationBuilder.CreateIndex(
                name: "idx_ann_published_at",
                table: "announcements",
                column: "published_at");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "announcements");
        }
    }
}
