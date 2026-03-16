BeforeAll {
    $VerbosePreference = "Continue"
    if ($PSVersionTable.PSVersion -le [System.Management.Automation.SemanticVersion]"7.5") {
        Throw "Must be run in Powershell 7.6+ (try pwsh-preview maybe)"
    }

    # This will need a dotnet 10 sdk, and pwsh 7.6+. I bet this will be a pain in GH actions. Worry about this later.
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

Describe "GroupManager Tests" {
    BeforeEach {
        $DbTestDir = join-path $TestsTempDir "$((New-Guid).ToString('N'))"
        New-Item -Path $DbTestDir -ItemType Directory
        $TestDataBase = join-path $DbTestDir "test.db"
        Write-Verbose "Expected database path: $TestDataBase"
        $manager = [GroupEvent.GroupManager]::new($TestDataBase)
    }

    Context "PowerEventOffset Management" {

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
