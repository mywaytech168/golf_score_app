using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using UploadServer.Data;

#nullable disable

namespace UploadServer.Migrations
{
    [DbContext(typeof(VideoDbContext))]
    [Migration("20260528000004_AddKeyframesAndAudioB2Path")]
    public partial class AddKeyframesAndAudioB2Path : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "keyframes_json",
                table: "ai_coach_analyses",
                type: "LONGTEXT",
                nullable: true)
                .Annotation("MySql:CharSet", "utf8mb4");

            migrationBuilder.AddColumn<string>(
                name: "audio_b2_path",
                table: "ai_coach_analyses",
                type: "varchar(512)",
                maxLength: 512,
                nullable: true)
                .Annotation("MySql:CharSet", "utf8mb4");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "keyframes_json",
                table: "ai_coach_analyses");

            migrationBuilder.DropColumn(
                name: "audio_b2_path",
                table: "ai_coach_analyses");
        }
    }
}
