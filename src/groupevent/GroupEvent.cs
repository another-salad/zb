namespace GroupEvent {

    public class GroupLockDTO {
        public int GroupId { get; set; }

        public string? GroupName { get; set; }

        public int RequestType { get; set; }

        // non‑nullable – we initialise it to DateTime.Now by default
        public DateTime ReleaseTime { get; set; } = DateTime.Now;

        public GroupLockDTO(){}

        public GroupLockDTO(int groupId, string? groupName, int requestType, DateTime releaseTime) {
            GroupId     = groupId;
            GroupName   = groupName;
            RequestType = requestType;
            ReleaseTime = releaseTime;
        }

        public GroupLockDTO(int groupId, string? groupName, int requestType) {
            GroupId = groupId;
            GroupName = groupName;
            RequestType = requestType;
        }
    }

    // For when we have the PowerEventOffset object to hand.
    public class GroupLockDTOWithOffset : GroupLockDTO {
        public PowerEventOffsetDto? PowerEventOffset { get; set; }

        public new DateTime ReleaseTime {
            set {
                base.ReleaseTime = PowerEventOffset != null ? base.ReleaseTime.Add(PowerEventOffset.Offset) : value;
            }
            get {
                return base.ReleaseTime;
            }
        }
        public GroupLockDTOWithOffset(){}

        public GroupLockDTOWithOffset(int groupId, string? groupName, int requestType, PowerEventOffsetDto? powerEventOffset) : base(groupId, groupName, requestType) {
            PowerEventOffset = powerEventOffset;
            ReleaseTime = base.ReleaseTime;
        }

        public GroupLockDTOWithOffset(int groupId, string? groupName, int requestType, PowerEventOffsetDto? powerEventOffset, DateTime releaseTime) : base(groupId, groupName, requestType, releaseTime) {
            PowerEventOffset = powerEventOffset;
            ReleaseTime = releaseTime;
        }
    }

    public class GroupPowerEventDto {
        public int GroupId { get; set; }
        public string? GroupName { get; set; }
        public int PowerEventType { get; set; }
        public DateTime EventTime { get; set; }
    }

    public class PowerEventOffsetDto {
        public string? Name { get; set; }
        public TimeSpan Offset { get; set; }
    }

    public class GroupManager {
        private readonly GroupEventsContext _context;

        public GroupManager() {
            _context = new GroupEventsContext();
        }

        // Direct call without a pre-determined offset. The offsets are useful for automated runs as we will be dealing with
        // button event types. Having these map directly to pre-determined offsets will mean no random hardcoded offests in
        // client code.
        public void SetGroupLock(int groupId, string groupName, int requestType, DateTime? releaseTime) {
            GroupLock? existingLock = _context.GroupLock.FirstOrDefault(gl => gl.GroupId == groupId);
            if (existingLock != null) {
                existingLock.RequestType = requestType;
                existingLock.ReleaseTime = releaseTime ?? DateTime.Now;
                _context.GroupLock.Update(existingLock);
            } else {
                GroupLock groupLock = new() {
                    GroupId     = groupId,
                    GroupName   = groupName,
                    RequestType = requestType,
                    ReleaseTime = releaseTime ?? DateTime.Now
                };
                _context.GroupLock.Add(groupLock);
            }
            _context.SaveChanges();
        }

        // Dto to hand but not _offset aware_
        public void SetGroupLock(GroupLockDTO groupLockDto) {
            SetGroupLock(groupLockDto.GroupId, groupLockDto.GroupName!, groupLockDto.RequestType, groupLockDto.ReleaseTime);   
        }

        public void SetGroupLock(GroupLockDTOWithOffset groupLockDto) {
            SetGroupLock(groupLockDto.GroupId, groupLockDto.GroupName!, groupLockDto.RequestType, groupLockDto.ReleaseTime);   
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

        public GroupLockDTO? GetGroupLock(int groupId) {
            GroupLock? groupLock = _context.GroupLock.FirstOrDefault(gl => gl.GroupId == groupId);
            return groupLock == null ? null : new GroupLockDTO {
                GroupId     = groupLock.GroupId,
                GroupName   = groupLock.GroupName,
                RequestType = groupLock.RequestType,
                ReleaseTime = groupLock.ReleaseTime
            };
        }

        // Potentially an odd one, but I want the abilty to see if the DTO in my hand is stale
        public GroupLockDTO? GetGroupLock(GroupLockDTO groupLockDTO){
            return GetGroupLock(groupLockDTO.GroupId);
        }

        public GroupLockDTO? GetGroupLock(GroupLockDTOWithOffset groupLockDTO){
            return GetGroupLock(groupLockDTO.GroupId);
        }

        public List<GroupLockDTO?> GetGroupLock(){
            return [.. _context.GroupLock.Select(gl => new GroupLockDTO {
                GroupId     = gl.GroupId,
                GroupName   = gl.GroupName,
                RequestType = gl.RequestType,
                ReleaseTime = gl.ReleaseTime
            })];
        }

        public List<PowerEventOffsetDto> GetPowerEventOffset() {
            return [.. _context.PowerEventOffset.Select(pet => new PowerEventOffsetDto {
                Name = pet.Name,
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
                existingPowerEventTime.OffSet = offset;
                _context.PowerEventOffset.Update(existingPowerEventTime);
            } else {
                PowerEventOffset powerEventTime = new() {
                    Name = name,
                    OffSet = offset
                };
                _context.PowerEventOffset.Add(powerEventTime);
            }
            _context.SaveChanges();
        }

        public void NewPowerEventOffset(PowerEventOffsetDto powerEventOffsetDto) {
            NewPowerEventOffset(powerEventOffsetDto.Name!, powerEventOffsetDto.Offset);
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

        public void ClearChangeTracker() {
            // If a prior operation failed, the change tracker may have stale entries.
            // I'd rather not swallow exceptions and decide what YOU want to see or do.
            // Exposing this gives YOU the power to do what you want in whatever connecting client.
            _context.ChangeTracker.Clear();
        }

    }
}
