using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace UploadServer.Migrations
{
    /// <inheritdoc />
    public partial class FeedbackImageB2 : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "attached_image_base64",
                table: "user_feedbacks");

            migrationBuilder.AddColumn<string>(
                name: "attached_image_b2_key",
                table: "user_feedbacks",
                type: "varchar(500)",
                maxLength: 500,
                nullable: true)
                .Annotation("MySql:CharSet", "utf8mb4");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "attached_image_b2_key",
                table: "user_feedbacks");

            migrationBuilder.AddColumn<string>(
                name: "attached_image_base64",
                table: "user_feedbacks",
                type: "MEDIUMTEXT",
                nullable: true)
                .Annotation("MySql:CharSet", "utf8mb4");
        }
    }
}
