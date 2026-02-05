using Microsoft.EntityFrameworkCore;
using System;
using System.Collections.Generic;

namespace GroupLock {

    public class GroupLockContext : DbContext {
        public DbSet<GroupLock> GroupLocks { get; set; }

        public string DbPath { get; private set;}

        public GroupLockContext() {
            var path = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            DbPath = Path.Join(path, "grouplock.db");
        }

        protected override void OnConfiguring(DbContextOptionsBuilder optionsBuilder) {
            optionsBuilder.UseSqlite($"Data Source={DbPath}");
        }

        protected override void OnModelCreating(ModelBuilder modelBuilder) {
            modelBuilder.Entity<GroupLock>()
                .HasIndex(gl => gl.GroupName)
                .IsUnique();

            modelBuilder.Entity<GroupLock>()
                .HasIndex(gl => gl.GroupId)
                .IsUnique();
        }

    }
    
    public class GroupLock {
        public int Id { get; set; }
        public int GroupId { get; set; }
        public string? GroupName { get; set; }
        public int RequestType { get; set; }
        public DateTime ReleaseTime { get; set; }
    }
}
