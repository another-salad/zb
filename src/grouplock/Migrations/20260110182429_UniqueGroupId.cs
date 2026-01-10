using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace grouplock.Migrations
{
    /// <inheritdoc />
    public partial class UniqueGroupId : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateIndex(
                name: "IX_GroupLocks_GroupId",
                table: "GroupLocks",
                column: "GroupId",
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_GroupLocks_GroupId",
                table: "GroupLocks");
        }
    }
}
