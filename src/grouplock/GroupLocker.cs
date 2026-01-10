using Microsoft.EntityFrameworkCore;
using System;
using System.Linq;
using System.Text.RegularExpressions;

namespace GroupLock {
    public class GroupLocker {
        private readonly GroupLockContext _context;

        public GroupLocker() {
            _context = new GroupLockContext();
        }

        // This is a nicer transport object as we can hide away the internal database Id field.
        public class GroupLockDTO {
            public int GroupId { get; set; }
            public string? GroupName { get; set; }
            public int RequestType { get; set; }
            public DateTime ReleaseTime { get; set; }
        }

        public void AddOrUpdate(int groupId, string groupName, int requestType, DateTime releaseTime) {
            GroupLock? existingLock = _context.GroupLocks.FirstOrDefault(gl => gl.GroupId == groupId);
            if (existingLock != null) {
                existingLock.RequestType = requestType;
                existingLock.ReleaseTime = releaseTime;
                _context.GroupLocks.Update(existingLock);
            } else {
                GroupLock groupLock = new() {
                    GroupId     = groupId,
                    GroupName   = groupName,
                    RequestType = requestType,
                    ReleaseTime = releaseTime
                };
                _context.GroupLocks.Add(groupLock);
            }
            _context.SaveChanges();
        }

        public void Remove(int groupId) {
            GroupLock? groupLock = _context.GroupLocks.FirstOrDefault(gl => gl.GroupId == groupId);
            if (groupLock != null) {
                _context.GroupLocks.Remove(groupLock);
                _context.SaveChanges();
            }
        }

        public GroupLockDTO? Get(int groupId) {
            GroupLock? groupLock = _context.GroupLocks.FirstOrDefault(gl => gl.GroupId == groupId);
            return groupLock == null ? null : new GroupLockDTO {
                GroupId     = groupLock.GroupId,
                GroupName   = groupLock.GroupName,
                RequestType = groupLock.RequestType,
                ReleaseTime = groupLock.ReleaseTime
            };
        }

        public List<GroupLockDTO?> Get(){
            return [.. _context.GroupLocks.Select(gl => new GroupLockDTO {
                GroupId     = gl.GroupId,
                GroupName   = gl.GroupName,
                RequestType = gl.RequestType,
                ReleaseTime = gl.ReleaseTime
            })];
        }

        public void ClearChangeTracker() {
            // If a prior operation failed, the change tracker may have stale entries.
            // I'd rather not swallow exceptions and decide what YOU want to see or do.
            // Exposing this gives YOU the power to do what you want in whatever connecting client.
            _context.ChangeTracker.Clear();
        }
        
    }
}
