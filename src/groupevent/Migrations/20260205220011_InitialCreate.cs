using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace groupevent.Migrations
{
    /// <inheritdoc />
    public partial class InitialCreate : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "GroupLock",
                columns: table => new
                {
                    Id = table.Column<int>(type: "INTEGER", nullable: false)
                        .Annotation("Sqlite:Autoincrement", true),
                    GroupId = table.Column<int>(type: "INTEGER", nullable: false),
                    GroupName = table.Column<string>(type: "TEXT", nullable: true),
                    RequestType = table.Column<int>(type: "INTEGER", nullable: false),
                    ReleaseTime = table.Column<DateTime>(type: "TEXT", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_GroupLock", x => x.Id);
                });

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

            migrationBuilder.CreateTable(
                name: "GroupPowerEvent",
                columns: table => new
                {
                    Id = table.Column<int>(type: "INTEGER", nullable: false)
                        .Annotation("Sqlite:Autoincrement", true),
                    GroupId = table.Column<int>(type: "INTEGER", nullable: false),
                    GroupName = table.Column<string>(type: "TEXT", nullable: true),
                    PowerEventTypeId = table.Column<int>(type: "INTEGER", nullable: true),
                    EventTime = table.Column<DateTime>(type: "TEXT", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_GroupPowerEvent", x => x.Id);
                    table.ForeignKey(
                        name: "FK_GroupPowerEvent_PowerEventType_PowerEventTypeId",
                        column: x => x.PowerEventTypeId,
                        principalTable: "PowerEventType",
                        principalColumn: "Id");
                });

            migrationBuilder.CreateIndex(
                name: "IX_GroupLock_GroupId",
                table: "GroupLock",
                column: "GroupId",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_GroupLock_GroupName",
                table: "GroupLock",
                column: "GroupName",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_GroupPowerEvent_GroupId",
                table: "GroupPowerEvent",
                column: "GroupId");

            migrationBuilder.CreateIndex(
                name: "IX_GroupPowerEvent_PowerEventTypeId",
                table: "GroupPowerEvent",
                column: "PowerEventTypeId");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "GroupLock");

            migrationBuilder.DropTable(
                name: "GroupPowerEvent");

            migrationBuilder.DropTable(
                name: "PowerEventType");
        }
    }
}
