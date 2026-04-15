BeforeAll {
    $VerbosePreference = "Continue"
    if ($PSVersionTable.PSVersion -le [System.Management.Automation.SemanticVersion]"7.5") {
        Throw "Current PowerShell version: $($PSVersionTable.PSVersion). GroupEvent tests require PowerShell 7.6 or higher. (try pwsh-preview maybe)"
    }

    $projectDir = Join-Path $PSScriptRoot '..'
    Push-Location $projectDir
    & ([scriptBlock]::Create("dotnet clean; dotnet build -c Debug"))
    if ($LASTEXITCODE -ne 0) {
        Throw "Failed to build group event project (exit code $LASTEXITCODE)."
    }
    Pop-location

    Import-Module "$projectDir/bin/Debug/net10.0/linux-x64/groupevent.dll" -Force -ErrorAction Stop

    $TestsTempDir = New-Item -Path (join-path ([system.io.path]::GetTempPath()) "GroupEventSuite_$((New-Guid).ToString('N'))") -ItemType Directory
    Write-Verbose "Temp directory for test suite: $TestsTempDir"

}

Describe "DB-less GroupManager tests" -tag "NoDB" {

    Context "GroupLockDTO" {
        It "GroupLockDTO defaults to UTC ReleaseTime" {
            $dto = [GroupEvent.GroupLockDTO]::new()
            $dto.ReleaseTime.Kind | Should -Be 'Utc'
        }

        It "GroupLockDTO user provided times are converted to UTC" {
            $releaseTime = (Get-Date).AddHours(1)
            $dto = [GroupEvent.GroupLockDTO]::new(1, "Test Group", 0, [GroupEvent.PowerState]::On, $releaseTime)
            $dto.ReleaseTime.Kind | Should -Be 'Utc'
            $dto.ReleaseTime | Should -Be $releaseTime.ToUniversalTime()
        }
    }
}

Describe "GroupManager DataBase Tests" -Tag "DB" {
    BeforeEach {
        $DbTestDir = join-path $TestsTempDir "$((New-Guid).ToString('N'))"
        New-Item -Path $DbTestDir -ItemType Directory
        $TestDataBase = join-path $DbTestDir "test.db"
        Write-Verbose "Expected database path: $TestDataBase"
        $manager = [GroupEvent.GroupManager]::new($TestDataBase)
    }

    Context "PowerEventOffset" -Tag "PowerEventOffset" {

        BeforeEach {
            $manager.NewPowerEventOffset('test-offset', (New-TimeSpan -Hours 2))
        }

        It "NewPowerEventOffset should create a new PowerEventOffset" {
            $offset = $manager.GetPowerEventOffset('test-offset')
            $offset | Should -Not -BeNullOrEmpty
            $offset.Name | Should -Be 'test-offset'
            $offset.Offset | Should -Be ([TimeSpan]::FromHours(2))
        }

        It "NewPowerEventOffset should not update an existing PowerEventOffset" {
            $manager.NewPowerEventOffset('test-offset', (New-TimeSpan -Hours 4))
            $offset = $manager.GetPowerEventOffset('test-offset')
            $offset.Offset | Should -Be ([TimeSpan]::FromHours(2))
        }

        It "GetPowerEventOffset returns a valid DTO" {
            $offset = $manager.GetPowerEventOffset('test-offset')
            $offset | Should -Not -BeNullOrEmpty
            $offset.Name | Should -Be 'test-offset'
            $offset.Offset | Should -Be ([TimeSpan]::FromHours(2))
        }

        It "GetPowerEventOffset should return null for non-existent offset" {
            $offset = $manager.GetPowerEventOffset('non-existent-offset')
            $offset | Should -Be $null
        }

        It "SetPowerEventOffset should update an existing PowerEventOffset" {
            $manager.SetPowerEventOffset('test-offset', (New-TimeSpan -Minutes 30))
            $offset = $manager.GetPowerEventOffset('test-offset')
            $offset.Offset | Should -Be ([TimeSpan]::FromMinutes(30))
        }

        It "RemovePowerEventOffset should remove a PowerEventOffset" {
            $manager.RemovePowerEventOffset('test-offset')
            $result = $manager.GetPowerEventOffset('test-offset')
            $result | Should -Be $null
        }
    }

    Context "GroupLock" -Tag "GroupLock" {

        It "should set and get group locks with NewGroupLock and GetGroupLock with DTOs" {
            $groupLockDto = [GroupEvent.GroupLockDTO]::new(1,"test-group",100,[GroupEvent.PowerState]::On)
            $manager.NewGroupLock($groupLockDto)
            $res = $manager.GetGroupLock($groupLockDto)
            $res | should -Be GroupEvent.GroupLockDTO
            $res.GroupId | should -Be 1
            $res.GroupName | should -Be "test-group"
            $res.RequestType | should -Be 100
            $res.PowerState | should -Be ([GroupEvent.PowerState]::On)
            $currentDateTime = Get-Date -AsUTC
            # The seconds will differ so lets just ignore them
            $res.releasetime.Kind | Should -Be 'Utc'
            $res.ReleaseTime.ToShortTimeString() | Should -Be $currentDateTime.ToShortTimeString()
            $res.ReleaseTime.ToShortDateString() | Should -Be $currentDateTime.ToShortDateString()
        }

        It "should update existing group locks with SetGroupLock" {
            $groupLockDto = [GroupEvent.GroupLockDTO]::new(1,"test-group",100,[GroupEvent.PowerState]::On)
            $manager.NewGroupLock($groupLockDto)

            $groupLockDto.RequestType = 200
            $groupLockDto.PowerState = [GroupEvent.PowerState]::Off
            $manager.SetGroupLock($groupLockDto)

            $res = $manager.GetGroupLock($groupLockDto)
            $res.RequestType | should -Be 200
            $res.PowerState | should -Be ([GroupEvent.PowerState]::Off)
        }

        It "should remove group lock with RemoveGroupLock" {
            $groupLockDto = [GroupEvent.GroupLockDTO]::new(1,"test-group",100,[GroupEvent.PowerState]::On)
            $manager.NewGroupLock($groupLockDto)

            $manager.RemoveGroupLock($groupLockDto)

            $res = $manager.GetGroupLock($groupLockDto)
            $res | Should -Be $null
        }

        It "should remove all group locks provided to RemoveGroupLock" {
            $ToRemove = @()
            foreach ($i in 1..5) {
                $groupLockDto = [GroupEvent.GroupLockDTO]::new($i,"test-group-$i",100,[GroupEvent.PowerState]::On)
                $manager.NewGroupLock($groupLockDto)
                $ToRemove += $groupLockDto
            }
            $manager.GetGroupLock() | Should -HaveCount 5
            $manager.RemoveGroupLock($ToRemove)
            $manager.GetGroupLock() | Should -BeNullOrEmpty
        }

        It "should only remove provided group locks with RemoveGroupLock" {
            foreach ($i in 1..5) {
                $manager.NewGroupLock([GroupEvent.GroupLockDTO]::new($i,"test-group-$i",100,[GroupEvent.PowerState]::On))
            }
            $lockedGroups = $manager.GetGroupLock()
            $lockedGroups | Should -HaveCount 5
            $manager.RemoveGroupLock(($lockedGroups | Sort-Object GroupId |select-object -First 3))
            $remainingLocks = $manager.GetGroupLock()
            $remainingLocks | Should -HaveCount 2
            $remainingLocks.GroupId | Should -Not -Contain 1
            $remainingLocks.GroupId | Should -Not -Contain 2
            $remainingLocks.GroupId | Should -Not -Contain 3
            $remainingLocks.GroupId | Should -Contain 4
            $remainingLocks.GroupId | Should -Contain 5
        }

        It "NewGroupLock should create a new group lock with GroupLockDTOWithOffset" {
            $manager.NewPowerEventOffset('test-offset', (New-TimeSpan -Hours 4))
            $groupLockDto = [GroupEvent.GroupLockDTOWithOffset]::new(1,"test-group",100,[GroupEvent.PowerState]::On, $manager.GetPowerEventOffset('test-offset'))
            $manager.NewGroupLock($groupLockDto)
            $res = $manager.GetGroupLock($groupLockDto)
            $res | should -Be GroupEvent.GroupLockDTO
            $res.GroupId | should -Be 1
            $res.GroupName | should -Be "test-group"
            $res.RequestType | should -Be 100
            $res.PowerState | should -Be ([GroupEvent.PowerState]::On)
            $res.releasetime.Kind | Should -Be 'Utc'
            $expectedReleaseTime = (Get-Date -AsUTC).AddHours(4)  
            $res.ReleaseTime.ToShortDateString() | Should -Be $expectedReleaseTime.ToShortDateString()
            $res.ReleaseTime.ToShortTimeString() | Should -Be $expectedReleaseTime.ToShortTimeString()
        }
    }

    Context "GroupPowerEventLog" -Tag "GroupPowerEventLog" {

        BeforeEach {
            $manager.NewPowerEventOffset('test-offset', (New-TimeSpan -Hours 4))
            foreach ($i in 1..5) {
                $groupLockDto = [GroupEvent.GroupLockDTOWithOffset]::new($i,"test-group-$i",100,[GroupEvent.PowerState]::On, $manager.GetPowerEventOffset('test-offset'))
                $manager.NewGroupPowerEventLog([GroupEvent.PendingGroupPowerEventLogDTO]::new($groupLockDto))
            }
            $logs = $manager.GetGroupPowerEventLog()
            $logs | Should -HaveCount 5
        }

        It "Should create new power event log with NewGroupPowerEventLog" {
            $logs | foreach-object -Begin {$i=1} -Process {
                $_ | Should -Be GroupEvent.CompletedGroupPowerEventLogDTO
                $_.GroupId | Should -Be $i
                $_.GroupName | Should -Be "test-group-$i"
                $_.PowerState | Should -Be ([GroupEvent.PowerState]::On)
                $_.ReleaseTime.Kind | Should -Be 'Utc'
                $_.EventRequestTime.Kind | Should -Be 'Utc'
                $_.EventRequestTime | Should -BeGreaterOrEqual (Get-Date -AsUTC).AddMinutes(-1) # EventRequestTime should be recent
                $i++
            }
        }

        It "Should remove power event logs with RemoveGroupPowerEventLog" {
            $manager.RemoveGroupPowerEventLog($logs)
            $manager.GetGroupPowerEventLog() | Should -BeNullOrEmpty
        }

        It "Should only remove specified power event logs with RemoveGroupPowerEventLog" {
            $logsToRemove = $logs | Select-Object -First 3
            $manager.RemoveGroupPowerEventLog($logsToRemove)
            $remainingLogs = $manager.GetGroupPowerEventLog()
            $remainingLogs | Should -HaveCount 2
            $remainingLogs.GroupId | Should -Not -Contain 1
            $remainingLogs.GroupId | Should -Not -Contain 2
            $remainingLogs.GroupId | Should -Not -Contain 3
            $remainingLogs.GroupId | Should -Contain 4
            $remainingLogs.GroupId | Should -Contain 5
        }

        It "should only remove power events from within date range with RemoveGroupPowerEventLog" {
            $cutOffTime = (Get-Date -AsUtc)
            Start-Sleep -Seconds 2 # Ensure some time has passed so we have a clear cutoff
            $groupLockDto = [GroupEvent.GroupLockDTOWithOffset]::new(999,"test-group-999",100,[GroupEvent.PowerState]::On, $manager.GetPowerEventOffset('test-offset'))
            $manager.NewGroupPowerEventLog([GroupEvent.PendingGroupPowerEventLogDTO]::new($groupLockDto))
            $logs = $manager.GetGroupPowerEventLog()
            $logs | should -havecount 6
            $manager.RemoveGroupPowerEventLog((get-date -AsUTC).AddMinutes(-5), $cutOffTime)
            $remainingLogs = $manager.GetGroupPowerEventLog()
            $remainingLogs | Should -HaveCount 1
            $remainingLogs[0].GroupId | Should -Be 999
        }
    }
}
