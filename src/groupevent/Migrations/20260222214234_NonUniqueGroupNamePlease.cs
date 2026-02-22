using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace groupevent.Migrations
{
    /// <inheritdoc />
    public partial class NonUniqueGroupNamePlease : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_GroupLock_GroupName",
                table: "GroupLock");

            migrationBuilder.CreateIndex(
                name: "IX_GroupLock_GroupName",
                table: "GroupLock",
                column: "GroupName");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_GroupLock_GroupName",
                table: "GroupLock");

            migrationBuilder.CreateIndex(
                name: "IX_GroupLock_GroupName",
                table: "GroupLock",
                column: "GroupName",
                unique: true);
        }
    }
}
