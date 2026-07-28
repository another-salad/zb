using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace groupevent.Migrations
{
    /// <inheritdoc />
    public partial class PowerEventTimeAndFriends : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_GroupPowerEvent_PowerEventType_PowerEventTypeId",
                table: "GroupPowerEvent");

            migrationBuilder.DropTable(
                name: "PowerEventType");

            migrationBuilder.DropIndex(
                name: "IX_GroupPowerEvent_PowerEventTypeId",
                table: "GroupPowerEvent");

            migrationBuilder.DropColumn(
                name: "EventTime",
                table: "GroupPowerEvent");

            migrationBuilder.DropColumn(
                name: "PowerEventTypeId",
                table: "GroupPowerEvent");

            migrationBuilder.AddColumn<DateTime>(
                name: "EventRequestTime",
                table: "GroupPowerEvent",
                type: "TEXT",
                nullable: false,
                defaultValueSql: "CURRENT_TIMESTAMP");

            migrationBuilder.CreateTable(
                name: "PowerEventTime",
                columns: table => new
                {
                    Id = table.Column<int>(type: "INTEGER", nullable: false)
                        .Annotation("Sqlite:Autoincrement", true),
                    Name = table.Column<string>(type: "TEXT", nullable: true),
                    OffSet = table.Column<TimeOnly>(type: "TEXT", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_PowerEventTime", x => x.Id);
                });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "PowerEventTime");

            migrationBuilder.DropColumn(
                name: "EventRequestTime",
                table: "GroupPowerEvent");

            migrationBuilder.AddColumn<DateTime>(
                name: "EventTime",
                table: "GroupPowerEvent",
                type: "TEXT",
                nullable: false,
                defaultValue: new DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeKind.Unspecified));

            migrationBuilder.AddColumn<int>(
                name: "PowerEventTypeId",
                table: "GroupPowerEvent",
                type: "INTEGER",
                nullable: true);

            migrationBuilder.CreateTable(
                name: "PowerEventType",
                columns: table => new
                {
                    Id = table.Column<int>(type: "INTEGER", nullable: false)
                        .Annotation("Sqlite:Autoincrement", true),
                    Name = table.Column<string>(type: "TEXT", nullable: true),
                    Value = table.Column<string>(type: "TEXT", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_PowerEventType", x => x.Id);
                });

            migrationBuilder.CreateIndex(
                name: "IX_GroupPowerEvent_PowerEventTypeId",
                table: "GroupPowerEvent",
                column: "PowerEventTypeId");

            migrationBuilder.AddForeignKey(
                name: "FK_GroupPowerEvent_PowerEventType_PowerEventTypeId",
                table: "GroupPowerEvent",
                column: "PowerEventTypeId",
                principalTable: "PowerEventType",
                principalColumn: "Id");
        }
    }
}
