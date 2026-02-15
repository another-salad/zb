using System.Diagnostics;
using Microsoft.EntityFrameworkCore;

namespace GroupEvent {

    public class GroupEventsContext : DbContext {
        public DbSet<GroupLock> GroupLock { get; set; }

        public DbSet<GroupPowerEvent> GroupPowerEvent { get; set; }

        public DbSet<PowerEventOffset> PowerEventOffset { get; set; }

        public string DbPath { get; private set;}

        public GroupEventsContext() {
            var path = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            DbPath = Path.Join(path, "groupevent.db");
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

            modelBuilder.Entity<GroupPowerEvent>()
                .HasIndex(gpe => gpe.GroupId);

            modelBuilder.Entity<GroupPowerEvent>()
                .Property(gpe => gpe.EventRequestTime)
                .HasDefaultValueSql("CURRENT_TIMESTAMP")
                .ValueGeneratedOnAdd();
            }

    }
    
    public class GroupLock {
        public int Id { get; private set; }
        public int GroupId { get; set; }
        public string? GroupName { get; set; }
        public int RequestType { get; set; }
        public DateTime ReleaseTime { get; set; }
    }

    // TODO: Look at current light requests (both with and without brightness and create below db table)
    public class GroupPowerEvent {
        public int Id { get; private set; }
        public int GroupId { get; set; }
        public string? GroupName { get; set; }
        public DateTime EventRequestTime { get; private set; }
    }

    // What do I want to do here? 
    public class PowerEventOffset {
        public int Id { get; private set; }
        public string? Name { get; set; }
        public TimeSpan OffSet { get; set; }
    }

}