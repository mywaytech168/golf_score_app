using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace UploadServer.Migrations
{
    /// <inheritdoc />
    public partial class RefactorVideoFields : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "avg_acceleration",
                table: "videos");

            migrationBuilder.DropColumn(
                name: "bad_shot",
                table: "videos");

            migrationBuilder.DropColumn(
                name: "max_acceleration",
                table: "videos");

            migrationBuilder.AddColumn<double>(
                name: "audio_crispness",
                table: "videos",
                type: "DOUBLE",
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "audio_crispness",
                table: "videos");

            migrationBuilder.AddColumn<double>(
                name: "max_acceleration",
                table: "videos",
                type: "DOUBLE",
                nullable: true);

            migrationBuilder.AddColumn<double>(
                name: "avg_acceleration",
                table: "videos",
                type: "DOUBLE",
                nullable: true);

            migrationBuilder.AddColumn<bool>(
                name: "bad_shot",
                table: "videos",
                type: "tinyint(1)",
                nullable: true);
        }
    }
}
