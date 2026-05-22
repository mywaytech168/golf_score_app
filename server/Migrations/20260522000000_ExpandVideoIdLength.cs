using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace UploadServer.Migrations
{
    /// <summary>
    /// 擴充 ai_coach_analyses.video_id 從 varchar(36) 到 varchar(255)。
    /// 前端以 session 目錄名稱（如 "1779413178538_hit_1"）作為 videoId，
    /// 雖小於 36，但保留空間供未來格式彈性調整。
    /// </summary>
    public partial class ExpandVideoIdLength : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AlterColumn<string>(
                name: "video_id",
                table: "ai_coach_analyses",
                type: "varchar(255)",
                maxLength: 255,
                nullable: true,
                oldClrType: typeof(string),
                oldType: "varchar(36)",
                oldMaxLength: 36,
                oldNullable: true)
                .Annotation("MySql:CharSet", "utf8mb4")
                .OldAnnotation("MySql:CharSet", "utf8mb4");
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AlterColumn<string>(
                name: "video_id",
                table: "ai_coach_analyses",
                type: "varchar(36)",
                maxLength: 36,
                nullable: true,
                oldClrType: typeof(string),
                oldType: "varchar(255)",
                oldMaxLength: 255,
                oldNullable: true)
                .Annotation("MySql:CharSet", "utf8mb4")
                .OldAnnotation("MySql:CharSet", "utf8mb4");
        }
    }
}
