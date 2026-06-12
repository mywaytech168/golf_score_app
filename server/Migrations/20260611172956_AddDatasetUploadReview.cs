using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace UploadServer.Migrations
{
    /// <inheritdoc />
    public partial class AddDatasetUploadReview : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "review_note",
                table: "dataset_uploads",
                type: "varchar(500)",
                maxLength: 500,
                nullable: true)
                .Annotation("MySql:CharSet", "utf8mb4");

            migrationBuilder.AddColumn<DateTime>(
                name: "reviewed_at",
                table: "dataset_uploads",
                type: "datetime",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "status",
                table: "dataset_uploads",
                type: "varchar(20)",
                maxLength: 20,
                nullable: false,
                defaultValue: "pending")
                .Annotation("MySql:CharSet", "utf8mb4");

            migrationBuilder.CreateIndex(
                name: "idx_dataset_status",
                table: "dataset_uploads",
                column: "status");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "idx_dataset_status",
                table: "dataset_uploads");

            migrationBuilder.DropColumn(
                name: "review_note",
                table: "dataset_uploads");

            migrationBuilder.DropColumn(
                name: "reviewed_at",
                table: "dataset_uploads");

            migrationBuilder.DropColumn(
                name: "status",
                table: "dataset_uploads");
        }
    }
}
