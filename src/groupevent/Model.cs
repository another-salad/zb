using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;

namespace GroupEvent {

    public class GroupEventsContext(string? dbPath = null) : DbContext {
        public string DbPath { get; set; } = dbPath ?? Path.Join(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "groupevent.db");

        public DbSet<GroupLock> GroupLock { get; set; }

        public DbSet<GroupPowerEventLog> GroupPowerEventLog { get; set; }

        public DbSet<PowerEventOffset> PowerEventOffset { get; set; }

        public DbSet<GroupLockScheduler> GroupLockScheduler { get; set; }

        protected override void OnConfiguring(DbContextOptionsBuilder optionsBuilder) {
            optionsBuilder.UseSqlite($"Data Source={DbPath}");
        }

        protected override void OnModelCreating(ModelBuilder modelBuilder) {
            modelBuilder.Entity<GroupLock>()
                .HasIndex(gl => gl.GroupName);

            modelBuilder.Entity<GroupLock>()
                .HasIndex(gl => gl.GroupId)
                .IsUnique();

            modelBuilder.Entity<GroupPowerEventLog>()
                .HasIndex(gpe => gpe.GroupId);

            modelBuilder.Entity<GroupPowerEventLog>()
                .Property(gpe => gpe.EventRequestTime)
                .HasDefaultValueSql("CURRENT_TIMESTAMP")
                .ValueGeneratedOnAdd();

            modelBuilder.Entity<PowerEventOffset>()
                .HasIndex(peo => peo.Name)
                .IsUnique();

            modelBuilder.Entity<GroupLockScheduler>()
                .HasIndex(gl => gl.GroupId)
                .IsUnique();
            }
            
        private void UpdateLastModified() {
            var entries = ChangeTracker
                .Entries()
                .Where(e => e.State == EntityState.Added || e.State == EntityState.Modified);

            foreach (var entry in entries) {
                if (entry.Metadata.FindProperty("LastModified") != null) {
                    entry.Property("LastModified").CurrentValue = DateTime.UtcNow;
                }
            }
        }

        public override int SaveChanges(bool acceptAllChangesOnSuccess) {
            UpdateLastModified();
            return base.SaveChanges(acceptAllChangesOnSuccess);
        }

        public override Task<int> SaveChangesAsync(bool acceptAllChangesOnSuccess, CancellationToken cancellationToken = default) {
            UpdateLastModified();
            return base.SaveChangesAsync(acceptAllChangesOnSuccess, cancellationToken);
        }
    }

    public enum PowerState {
        On = 1,
        Off = 2
    }
    
    public class GroupLock {
        public int Id { get; private set; }
        public int GroupId { get; set; }
        public string? GroupName { get; set; }
        public int RequestType { get; set; }
        public PowerState PowerState {get; set;}
        public DateTime ReleaseTime { get; set; }
    }

    public class GroupLockScheduler {
        public int Id { get; private set; }
        public int GroupId { get; set; }
        public string? GroupName { get; set; }
        public PowerState PowerState { get; set; }
        public TimeOnly StartTime { get; set; }
        public TimeOnly ReleaseTime { get; set; }
        public DateTime? LastModified { get; set; }
    }

    // I want the GroupLock table to only store records temporarily, therefore I can't strongly link a GroupLock entity in a GroupPowerEventLog record.
    // Since we still want the client code to be triggering all events (i.e. capturing trigger events, turning groups on/off and setting locks) I'll have the client
    // set GroupPowerEventLog appropriately. A weak link with a nullable Release time should be sufficent enough for logging.
    public class GroupPowerEventLog {
        public int Id { get; private set; }
        public int GroupId { get; set; }
        public string? GroupName { get; set; }
        public DateTime EventRequestTime { get; private set; }
        public DateTime? ReleaseTime { get; set; }
        public PowerState PowerState {get; set;}
    }

    public class PowerEventOffset {
        public int Id { get; private set; }
        public string? Name { get; set; }
        public TimeSpan OffSet { get; set; }
    }

    public class GroupEventsContextFactory : IDesignTimeDbContextFactory<GroupEventsContext> {
        public GroupEventsContext CreateDbContext(string[] args) {
            return new GroupEventsContext(null);
        }
    }

}