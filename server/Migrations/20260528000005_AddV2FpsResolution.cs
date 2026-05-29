using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using UploadServer.Data;

#nullable disable

namespace UploadServer.Migrations
{
    [DbContext(typeof(VideoDbContext))]
    [Migration("20260528000005_AddV2FpsResolution")]
    public partial class AddV2FpsResolution : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<int>(
                name: "v2_fps",
                table: "ai_coach_analyses",
                type: "int",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "v2_resolution",
                table: "ai_coach_analyses",
                type: "varchar(64)",
                maxLength: 64,
                nullable: true)
                .Annotation("MySql:CharSet", "utf8mb4");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "v2_fps",
                table: "ai_coach_analyses");

            migrationBuilder.DropColumn(
                name: "v2_resolution",
                table: "ai_coach_analyses");
        }
    }
}
