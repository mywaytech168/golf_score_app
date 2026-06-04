using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace UploadServer.Migrations
{
    /// <inheritdoc />
    public partial class AddSubscriptionFields : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            // ── users ──────────────────────────────────────────────────
            migrationBuilder.AddColumn<DateTime>(
                name: "subscription_expiry",
                table: "users",
                type: "datetime",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "subscription_status",
                table: "users",
                type: "varchar(20)",
                maxLength: 20,
                nullable: false,
                defaultValue: "none");

            migrationBuilder.AddColumn<string>(
                name: "subscription_original_id",
                table: "users",
                type: "varchar(255)",
                maxLength: 255,
                nullable: true);

            // ── purchase_records ───────────────────────────────────────
            migrationBuilder.AddColumn<string>(
                name: "original_transaction_id",
                table: "purchase_records",
                type: "varchar(255)",
                maxLength: 255,
                nullable: true);

            migrationBuilder.AddColumn<DateTime>(
                name: "expires_at",
                table: "purchase_records",
                type: "datetime",
                nullable: true);

            migrationBuilder.AddColumn<bool>(
                name: "is_auto_renewing",
                table: "purchase_records",
                type: "tinyint(1)",
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(name: "subscription_expiry",       table: "users");
            migrationBuilder.DropColumn(name: "subscription_status",       table: "users");
            migrationBuilder.DropColumn(name: "subscription_original_id",  table: "users");
            migrationBuilder.DropColumn(name: "original_transaction_id",   table: "purchase_records");
            migrationBuilder.DropColumn(name: "expires_at",                table: "purchase_records");
            migrationBuilder.DropColumn(name: "is_auto_renewing",          table: "purchase_records");
        }
    }
}
