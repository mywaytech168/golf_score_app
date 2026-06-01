using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using UploadServer.Data;

#nullable disable

namespace UploadServer.Migrations
{
    [DbContext(typeof(VideoDbContext))]
    [Migration("20260529000001_ReplaceKeyframesJsonWithCount")]
    public partial class ReplaceKeyframesJsonWithCount : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "keyframes_json",
                table: "ai_coach_analyses");

            migrationBuilder.AddColumn<int>(
                name: "keyframe_count",
                table: "ai_coach_analyses",
                type: "int",
                nullable: false,
                defaultValue: 0);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "keyframe_count",
                table: "ai_coach_analyses");

            migrationBuilder.AddColumn<string>(
                name: "keyframes_json",
                table: "ai_coach_analyses",
                type: "LONGTEXT",
                nullable: true)
                .Annotation("MySql:CharSet", "utf8mb4");
        }
    }
}
