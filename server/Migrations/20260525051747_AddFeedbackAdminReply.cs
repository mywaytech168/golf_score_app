using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace UploadServer.Migrations
{
    /// <inheritdoc />
    public partial class AddFeedbackAdminReply : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<DateTime>(
                name: "AdminRepliedAt",
                table: "user_feedbacks",
                type: "datetime(6)",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "AdminReply",
                table: "user_feedbacks",
                type: "longtext",
                nullable: true)
                .Annotation("MySql:CharSet", "utf8mb4");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "AdminRepliedAt",
                table: "user_feedbacks");

            migrationBuilder.DropColumn(
                name: "AdminReply",
                table: "user_feedbacks");
        }
    }
}
