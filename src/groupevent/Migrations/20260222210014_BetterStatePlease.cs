using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace groupevent.Migrations
{
    /// <inheritdoc />
    public partial class BetterStatePlease : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<int>(
                name: "PowerState",
                table: "GroupLock",
                type: "INTEGER",
                nullable: false,
                defaultValue: 0);
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "PowerState",
                table: "GroupLock");
        }
    }
}
