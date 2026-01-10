using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace grouplock.Migrations
{
    /// <inheritdoc />
    public partial class UniqueGroupName : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateIndex(
                name: "IX_GroupLocks_GroupName",
                table: "GroupLocks",
                column: "GroupName",
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_GroupLocks_GroupName",
                table: "GroupLocks");
        }
    }
}
