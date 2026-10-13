using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace groupevent.Migrations
{
    /// <inheritdoc />
    public partial class GroupLockSchedulerFixups : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.RenameColumn(
                name: "ReleaseDateTime",
                table: "GroupLockScheduler",
                newName: "ReleaseTime");

            migrationBuilder.AlterColumn<DateTime>(
                name: "LastModified",
                table: "GroupLockScheduler",
                type: "TEXT",
                nullable: true,
                oldClrType: typeof(DateTime),
                oldType: "TEXT");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.RenameColumn(
                name: "ReleaseTime",
                table: "GroupLockScheduler",
                newName: "ReleaseDateTime");

            migrationBuilder.AlterColumn<DateTime>(
                name: "LastModified",
                table: "GroupLockScheduler",
                type: "TEXT",
                nullable: false,
                defaultValue: new DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeKind.Unspecified),
                oldClrType: typeof(DateTime),
                oldType: "TEXT",
                oldNullable: true);
        }
    }
}
