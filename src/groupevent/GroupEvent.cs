using System.Linq.Expressions;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;

namespace GroupEvent {

    public class GroupLockDTO {
        public int GroupId { get; set; }

        public string? GroupName { get; set; }

        public int RequestType { get; set; }

        public PowerState PowerState { get; set; }

        private DateTime _releaseTime = DateTime.UtcNow;

        public DateTime ReleaseTime {
            get => _releaseTime;
            set => _releaseTime = value.ToUniversalTime();
        }

        public GroupLockDTO(){}

        public GroupLockDTO(int groupId, string? groupName, int requestType, PowerState powerState, DateTime releaseTime) {
            GroupId     = groupId;
            GroupName   = groupName;
            RequestType = requestType;
            PowerState  = powerState;
            ReleaseTime = releaseTime;
        }

        public GroupLockDTO(int groupId, string? groupName, int requestType, PowerState powerState) {
            GroupId     = groupId;
            GroupName   = groupName;
            RequestType = requestType;
            PowerState  = powerState;
        }
    }

    // For when we have the PowerEventOffset object to hand.
    public class GroupLockDTOWithOffset : GroupLockDTO {
        public PowerEventOffsetDto PowerEventOffset { get; set; }

        public new DateTime ReleaseTime {
            get => base.ReleaseTime;
            set => base.ReleaseTime = PowerEventOffset != null ? base.ReleaseTime.Add(PowerEventOffset.Offset) : value;
        }

        public GroupLockDTOWithOffset(int groupId, string? groupName, int requestType, PowerState powerState, PowerEventOffsetDto powerEventOffset) : base(groupId, groupName, requestType, powerState) {
            PowerEventOffset = powerEventOffset;
            ReleaseTime      = base.ReleaseTime;
        }

        public GroupLockDTOWithOffset(int groupId, string? groupName, int requestType, PowerState powerState, PowerEventOffsetDto powerEventOffset, DateTime releaseTime) : base(groupId, groupName, requestType, powerState, releaseTime) {
            PowerEventOffset = powerEventOffset;
            ReleaseTime      = releaseTime;
        }
    }

    public class PowerEventOffsetDto {
        public string? Name { get; set; }
        public TimeSpan Offset { get; set; }

        public PowerEventOffsetDto(string? name, TimeSpan offset) {
            Name   = name;
            Offset = offset;
        }

        public PowerEventOffsetDto() {}
    }

    public class PendingGroupPowerEventLogDTO {
        public int GroupId { get; set; }
        public string? GroupName { get; set; }
        public PowerState PowerState { get; set; }
        public DateTime? ReleaseTime { get; set; }

        public PendingGroupPowerEventLogDTO(){}

        public PendingGroupPowerEventLogDTO(int groupId, string? groupName, PowerState powerState, DateTime? releaseTime) {
            GroupId     = groupId;
            GroupName   = groupName;
            PowerState  = powerState;
            ReleaseTime = releaseTime?.ToUniversalTime();
        }

        public PendingGroupPowerEventLogDTO(GroupLockDTO groupLockDto) {
            GroupId     = groupLockDto.GroupId;
            GroupName   = groupLockDto.GroupName;
            PowerState  = groupLockDto.PowerState;
            ReleaseTime = groupLockDto.ReleaseTime;
        }

        public PendingGroupPowerEventLogDTO(GroupLockDTOWithOffset groupLockDto) {
            GroupId     = groupLockDto.GroupId;
            GroupName   = groupLockDto.GroupName;
            PowerState  = groupLockDto.PowerState;
            ReleaseTime = groupLockDto.ReleaseTime;
        }

    }

    public class CompletedGroupPowerEventLogDTO: PendingGroupPowerEventLogDTO {

        public DateTime EventRequestTime { get ; set ; }
        
        public CompletedGroupPowerEventLogDTO() {}

        public CompletedGroupPowerEventLogDTO(GroupPowerEventLog groupPowerEventLog) : base(groupPowerEventLog.GroupId, groupPowerEventLog.GroupName, groupPowerEventLog.PowerState, groupPowerEventLog.ReleaseTime) {
            EventRequestTime = DateTime.SpecifyKind(groupPowerEventLog.EventRequestTime, DateTimeKind.Utc);
        }
    }

    public class GroupManager {
        private readonly GroupEventsContext _context;

        private readonly ILogger logger;

        public GroupManager(string? dbPath = null) {
            _context = new GroupEventsContext(dbPath);
            _context.Database.Migrate();
            using ILoggerFactory factory = LoggerFactory.Create(builder => builder.AddConsole());
            logger = factory.CreateLogger<GroupManager>();
        }

        public string DataBasePath => _context.DbPath;

        private static readonly Expression<Func<GroupLock, GroupLockDTO>> _toGlDto = 
            gl => new GroupLockDTO {
                GroupId     = gl.GroupId,
                GroupName   = gl.GroupName,
                RequestType = gl.RequestType,
                PowerState  = gl.PowerState,
                ReleaseTime = DateTime.SpecifyKind(gl.ReleaseTime, DateTimeKind.Utc)
            };

        private static (DateTime from, DateTime to) ResolveDateRange(DateTime? from, DateTime? to){
            return (from ?? DateTime.MinValue, to ?? DateTime.UtcNow);
        }

        public void NewGroupLock(int groupId, string groupName, int requestType, PowerState powerState, DateTime releaseTime) {
            GroupLock? existingLock = _context.GroupLock.FirstOrDefault(gl => gl.GroupId == groupId);
            if (existingLock != null) {
                logger.LogWarning("GroupLock with id: {groupId} found. Use SetGroupLock to update an existing lock.", groupId);
            } else {
                GroupLock groupLock = new() {
                    GroupId     = groupId,
                    GroupName   = groupName,
                    RequestType = requestType,
                    PowerState  = powerState,
                    ReleaseTime = releaseTime.ToUniversalTime()
                };
                _context.GroupLock.Add(groupLock);
                _context.SaveChanges();
            }
        }

        public void NewGroupLock(GroupLockDTO groupLockDto) {
            NewGroupLock(groupLockDto.GroupId, groupLockDto.GroupName!, groupLockDto.RequestType, groupLockDto.PowerState, groupLockDto.ReleaseTime);   
        }

        public void NewGroupLock(GroupLockDTOWithOffset groupLockDto) {
            NewGroupLock(groupLockDto.GroupId, groupLockDto.GroupName!, groupLockDto.RequestType, groupLockDto.PowerState, groupLockDto.ReleaseTime);   
        }

        // Direct call without a pre-determined offset. The offsets are useful for automated runs as we will be dealing with
        // button event types. Having these map directly to pre-determined offsets will mean no random hardcoded offests in
        // client code.
        public void SetGroupLock(int groupId, string groupName, int requestType, PowerState powerState, DateTime releaseTime) {
            GroupLock? existingLock = _context.GroupLock.FirstOrDefault(gl => gl.GroupId == groupId);
            if (existingLock != null) {
                existingLock.RequestType = requestType;
                existingLock.PowerState  = powerState;
                existingLock.ReleaseTime = releaseTime.ToUniversalTime();
                _context.GroupLock.Update(existingLock);
                _context.SaveChanges();
            } else {
                logger.LogWarning("No GroupLock with id: {groupId} found. Use NewGroupLock for a new lock.", groupId);
            }
        }

        // Dto to hand but not _offset aware_
        public void SetGroupLock(GroupLockDTO groupLockDto) {
            SetGroupLock(groupLockDto.GroupId, groupLockDto.GroupName!, groupLockDto.RequestType, groupLockDto.PowerState, groupLockDto.ReleaseTime);   
        }

        public void SetGroupLock(GroupLockDTOWithOffset groupLockDto) {
            SetGroupLock(groupLockDto.GroupId, groupLockDto.GroupName!, groupLockDto.RequestType, groupLockDto.PowerState, groupLockDto.ReleaseTime);   
        }

        public void RemoveGroupLock(int groupId) {
            GroupLock? groupLock = _context.GroupLock.FirstOrDefault(gl => gl.GroupId == groupId);
            if (groupLock != null) {
                _context.GroupLock.Remove(groupLock);
                _context.SaveChanges();
            }
        }

        public void RemoveGroupLock(GroupLockDTO groupLockDto) {
            RemoveGroupLock(groupLockDto.GroupId);
        }

        public void RemoveGroupLock(GroupLockDTOWithOffset groupLockDto) {
            RemoveGroupLock(groupLockDto.GroupId);
        }

        public void RemoveGroupLock(List<GroupLockDTO> groupLockDTOs) {
            var ids = groupLockDTOs.Select(dto => dto.GroupId).ToList();
            _context.GroupLock.RemoveRange(_context.GroupLock.Where(gl => ids.Contains(gl.GroupId)));
            _context.SaveChanges();
        }

        public GroupLockDTO? GetGroupLock(int groupId) {
            return _context.GroupLock.Where(gl => gl.GroupId == groupId).Select(_toGlDto).FirstOrDefault();
        }

        // Potentially an odd one, but I want the abilty to see if the DTO in my hand is stale
        public GroupLockDTO? GetGroupLock(GroupLockDTO groupLockDTO){
            return GetGroupLock(groupLockDTO.GroupId);
        }

        // May feel a little odd to get a GroupLockDTO (i.e. no offset) back, but this is due to a GroupLockDTOWithOffset only really
        // existing at the construction phase in the client. Its a small convenience wrapper for generating the release time.
        public GroupLockDTO? GetGroupLock(GroupLockDTOWithOffset groupLockDTO){
            return GetGroupLock(groupLockDTO.GroupId);
        }

        public List<GroupLockDTO?> GetGroupLock(){
            return [.. _context.GroupLock.Select(_toGlDto)];
        }

        public List<PowerEventOffsetDto> GetPowerEventOffset() {
            return [.. _context.PowerEventOffset.Select(pet => new PowerEventOffsetDto {
                Name   = pet.Name,
                Offset = pet.OffSet
            })];
        }

        public PowerEventOffsetDto? GetPowerEventOffset(string name) {
            PowerEventOffset? powerEventOffset = _context.PowerEventOffset.FirstOrDefault(pet => pet.Name == name);
            return powerEventOffset == null ? null : new PowerEventOffsetDto {
                Name = powerEventOffset.Name,
                Offset = powerEventOffset.OffSet
            };
        }

        public void NewPowerEventOffset(string name, TimeSpan offset) {
            PowerEventOffset? existingPowerEventTime = _context.PowerEventOffset.FirstOrDefault(pet => pet.Name == name);
            if (existingPowerEventTime != null) {
                logger.LogWarning("A PowerEventOffset with the name {Name} already exists. Use SetPowerEventOffSet to update the offset value.", name);
            } else {
                PowerEventOffset powerEventTime = new() {
                    Name   = name,
                    OffSet = offset
                };
                _context.PowerEventOffset.Add(powerEventTime);
                _context.SaveChanges();
            }
        }

        public void NewPowerEventOffset(PowerEventOffsetDto powerEventOffsetDto) {
            NewPowerEventOffset(powerEventOffsetDto.Name!, powerEventOffsetDto.Offset);
        }

        public void SetPowerEventOffset(string name, TimeSpan offset) {
            PowerEventOffset? existingPowerEventTime = _context.PowerEventOffset.FirstOrDefault(pet => pet.Name == name);
            if (existingPowerEventTime != null) {
                existingPowerEventTime.OffSet = offset;
                _context.PowerEventOffset.Update(existingPowerEventTime);
                _context.SaveChanges();
            } else {
                logger.LogWarning("No PowerEventOffset with the name {Name} exists. Use NewPowerEventOffSet to create a new entry.", name);
            }
        }

        public void SetPowerEventOffset(PowerEventOffsetDto powerEventOffsetDto) {
            SetPowerEventOffset(powerEventOffsetDto.Name!, powerEventOffsetDto.Offset);
        }

        public void RemovePowerEventOffset(string name) {
            PowerEventOffset? powerEventOffset = _context.PowerEventOffset.FirstOrDefault(pet => pet.Name == name);
            if (powerEventOffset != null) {
                _context.PowerEventOffset.Remove(powerEventOffset);
                _context.SaveChanges();
            }
        }

        public void RemovePowerEventOffset(PowerEventOffsetDto powerEventOffsetDto) {
            RemovePowerEventOffset(powerEventOffsetDto.Name!);
        }

        public void NewGroupPowerEventLog(int groupId, string? groupName, PowerState powerState, DateTime? releaseTime) {
            GroupPowerEventLog groupPowerEventLog = new() {
                GroupId     = groupId,
                GroupName   = groupName,
                PowerState  = powerState,
                ReleaseTime = releaseTime
            };
            _context.GroupPowerEventLog.Add(groupPowerEventLog);
            _context.SaveChanges();
        }

        public void NewGroupPowerEventLog(PendingGroupPowerEventLogDTO pendingGroupPowerEvent) {
            NewGroupPowerEventLog(pendingGroupPowerEvent.GroupId, pendingGroupPowerEvent.GroupName, pendingGroupPowerEvent.PowerState, pendingGroupPowerEvent.ReleaseTime);
        }

        public List<CompletedGroupPowerEventLogDTO> GetGroupPowerEventLog() {
            return [.. _context.GroupPowerEventLog.Select(gpe => new CompletedGroupPowerEventLogDTO(gpe))];
        }

        public List<CompletedGroupPowerEventLogDTO> GetGroupPowerEventLog(DateTime? from = null, DateTime? to = null) {
            var (resolvedFrom, resolvedTo) = ResolveDateRange(from, to);
            return [.. _context.GroupPowerEventLog.Where(gpe => gpe.EventRequestTime >= resolvedFrom && gpe.EventRequestTime <= resolvedTo).Select(gpe => new CompletedGroupPowerEventLogDTO(gpe))];
        }

        public void RemoveGroupPowerEventLog(DateTime? from = null, DateTime? to = null) {
            var (resolvedFrom, resolvedTo) = ResolveDateRange(from, to);
            _context.GroupPowerEventLog.RemoveRange([.. _context.GroupPowerEventLog.Where(gpe => gpe.EventRequestTime >= resolvedFrom && gpe.EventRequestTime <= resolvedTo)]);
            _context.SaveChanges();
        }

        public void RemoveGroupPowerEventLog(List<CompletedGroupPowerEventLogDTO> groupPowerEventLogDtos) {
            var targetIds = groupPowerEventLogDtos.Select(dto => dto.GroupId).ToHashSet();
            var targetTimes = groupPowerEventLogDtos.Select(dto => dto.EventRequestTime).ToHashSet();
            // I'm likely holding this wrong but trying to query groupPowerEventLogDtos within the scope of the RemoveRange call was causing LINQ expression translation exceptions.
            _context.GroupPowerEventLog.RemoveRange([.. _context.GroupPowerEventLog.Where(gpe => targetIds.Contains(gpe.GroupId) && targetTimes.Contains(gpe.EventRequestTime))]);
            _context.SaveChanges();
        }

        public void ClearChangeTracker() {
            // If a prior operation failed, the change tracker may have stale entries.
            // I'd rather not swallow exceptions and decide what YOU want to see or do.
            // Exposing this gives YOU the power to do what you want in whatever connecting client.
            _context.ChangeTracker.Clear();
        }

    }
}
