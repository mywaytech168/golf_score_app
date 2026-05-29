using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using UploadServer.Data;

#nullable disable

namespace UploadServer.Migrations
{
    [DbContext(typeof(VideoDbContext))]
    [Migration("20260528000002_AddPhaseTimestampsJson")]
    public partial class AddPhaseTimestampsJson : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "phase_timestamps_json",
                table: "ai_coach_analyses",
                type: "TEXT",
                nullable: true)
                .Annotation("MySql:CharSet", "utf8mb4");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "phase_timestamps_json",
                table: "ai_coach_analyses");
        }
    }
}
