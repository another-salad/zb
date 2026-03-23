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

Describe "DB-less GroupManager tests" {

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

Describe "GroupManager DataBase Tests" {
    BeforeEach {
        $DbTestDir = join-path $TestsTempDir "$((New-Guid).ToString('N'))"
        New-Item -Path $DbTestDir -ItemType Directory
        $TestDataBase = join-path $DbTestDir "test.db"
        Write-Verbose "Expected database path: $TestDataBase"
        $manager = [GroupEvent.GroupManager]::new($TestDataBase)
    }

    Context "PowerEventOffset" {

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
}
