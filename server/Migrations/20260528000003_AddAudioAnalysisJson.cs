using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using UploadServer.Data;

#nullable disable

namespace UploadServer.Migrations
{
    [DbContext(typeof(VideoDbContext))]
    [Migration("20260528000003_AddAudioAnalysisJson")]
    public partial class AddAudioAnalysisJson : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "audio_analysis_json",
                table: "ai_coach_analyses",
                type: "LONGTEXT",
                nullable: true)
                .Annotation("MySql:CharSet", "utf8mb4");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "audio_analysis_json",
                table: "ai_coach_analyses");
        }
    }
}
