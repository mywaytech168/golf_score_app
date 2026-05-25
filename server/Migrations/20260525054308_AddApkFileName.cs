using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace UploadServer.Migrations
{
    /// <inheritdoc />
    public partial class AddApkFileName : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "ApkFileName",
                table: "app_versions",
                type: "longtext",
                nullable: true)
                .Annotation("MySql:CharSet", "utf8mb4");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "ApkFileName",
                table: "app_versions");
        }
    }
}
