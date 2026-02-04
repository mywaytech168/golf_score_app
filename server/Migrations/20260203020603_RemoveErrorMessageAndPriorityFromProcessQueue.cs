using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace UploadServer.Migrations
{
    /// <inheritdoc />
    public partial class RemoveErrorMessageAndPriorityFromProcessQueue : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "idx_queue_status_priority_created",
                table: "process_queue");

            migrationBuilder.DropColumn(
                name: "assigned_worker_id",
                table: "process_queue");

            migrationBuilder.DropColumn(
                name: "error_message",
                table: "process_queue");

            migrationBuilder.DropColumn(
                name: "priority",
                table: "process_queue");

            migrationBuilder.AddColumn<bool>(
                name: "is_success",
                table: "process_queue",
                type: "tinyint(1)",
                nullable: false,
                defaultValue: false);

            migrationBuilder.AddColumn<string>(
                name: "result_data",
                table: "process_queue",
                type: "longtext",
                nullable: true)
                .Annotation("MySql:CharSet", "utf8mb4");

            migrationBuilder.CreateIndex(
                name: "idx_queue_completed_status",
                table: "process_queue",
                columns: new[] { "completed_at", "status" });

            migrationBuilder.CreateIndex(
                name: "idx_queue_is_success",
                table: "process_queue",
                column: "is_success");

            migrationBuilder.CreateIndex(
                name: "idx_queue_status_created",
                table: "process_queue",
                columns: new[] { "status", "created_at" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "idx_queue_completed_status",
                table: "process_queue");

            migrationBuilder.DropIndex(
                name: "idx_queue_is_success",
                table: "process_queue");

            migrationBuilder.DropIndex(
                name: "idx_queue_status_created",
                table: "process_queue");

            migrationBuilder.DropColumn(
                name: "is_success",
                table: "process_queue");

            migrationBuilder.DropColumn(
                name: "result_data",
                table: "process_queue");

            migrationBuilder.AddColumn<string>(
                name: "assigned_worker_id",
                table: "process_queue",
                type: "varchar(100)",
                maxLength: 100,
                nullable: true)
                .Annotation("MySql:CharSet", "utf8mb4");

            migrationBuilder.AddColumn<string>(
                name: "error_message",
                table: "process_queue",
                type: "TEXT",
                nullable: true)
                .Annotation("MySql:CharSet", "utf8mb4");

            migrationBuilder.AddColumn<int>(
                name: "priority",
                table: "process_queue",
                type: "int",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.CreateIndex(
                name: "idx_queue_status_priority_created",
                table: "process_queue",
                columns: new[] { "status", "priority", "created_at" });
        }
    }
}
