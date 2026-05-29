using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using UploadServer.Data;

#nullable disable

namespace UploadServer.Migrations
{
    [DbContext(typeof(VideoDbContext))]
    [Migration("20260528000001_AddModePromptVersionTokens")]
    public partial class AddModePromptVersionTokens : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "Mode",
                table: "ai_coach_analyses",
                type: "varchar(32)",
                maxLength: 32,
                nullable: false,
                defaultValue: "full")
                .Annotation("MySql:CharSet", "utf8mb4");

            migrationBuilder.AddColumn<string>(
                name: "PromptVersion",
                table: "ai_coach_analyses",
                type: "varchar(8)",
                maxLength: 8,
                nullable: false,
                defaultValue: "v1")
                .Annotation("MySql:CharSet", "utf8mb4");

            migrationBuilder.AddColumn<int>(
                name: "InputTokens",
                table: "ai_coach_analyses",
                type: "int",
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "OutputTokens",
                table: "ai_coach_analyses",
                type: "int",
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(name: "Mode",          table: "ai_coach_analyses");
            migrationBuilder.DropColumn(name: "PromptVersion", table: "ai_coach_analyses");
            migrationBuilder.DropColumn(name: "InputTokens",   table: "ai_coach_analyses");
            migrationBuilder.DropColumn(name: "OutputTokens",  table: "ai_coach_analyses");
        }
    }
}
