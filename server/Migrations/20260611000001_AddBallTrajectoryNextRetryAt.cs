using System;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using UploadServer.Data;

#nullable disable

namespace UploadServer.Migrations
{
    [DbContext(typeof(VideoDbContext))]
    [Migration("20260611000001_AddBallTrajectoryNextRetryAt")]
    public partial class AddBallTrajectoryNextRetryAt : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<DateTime>(
                name: "next_retry_at",
                table: "ball_trajectory_analyses",
                type: "datetime",
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "next_retry_at",
                table: "ball_trajectory_analyses");
        }
    }
}
