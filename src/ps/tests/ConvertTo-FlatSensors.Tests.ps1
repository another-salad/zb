import-module (Join-Path $PSScriptRoot '../conbee-api-client/conbee-api-client.psd1') -Force -ErrorAction Stop

BeforeAll {
    . $PSScriptRoot\TestData.ps1
}

Describe "Tests for ConvertTo-FlatSensors" {
    It "should un-nest pscustomobjects to an array of invidiual sensors" {
        $result = $RawPresenceSensors | ConvertTo-FlatSensors
        $result | Should -Not -BeNullOrEmpty
        $result | Should -BeOfType [PSCustomObject]
        $result[0].type | Should -Be "ZHAPresence"
        $result[0].name | Should -Be "sensor0"
        $result[0].uniqueid | Should -Be "00:ff:ff:ff:ff:ff:ff:ff:01"
        $result[0].state.presence | Should -Be $true
        $result[0].state.LastUpdated | Should -Be "2024-07-07T12:00:00Z"
        $result[0].state.dark | Should -Be $false
        $result[1].type | Should -Be "ZHAPresence"
        $result[1].name | Should -Be "sensor1"
        $result[1].uniqueid | Should -Be "00:ff:ff:ff:ff:ff:ff:ff:02"
        $result[1].state.presence | Should -Be $true
        $result[1].state.LastUpdated | Should -Be "2024-07-08T12:00:00Z"
        $result[1].state.dark | Should -Be $true

    }

    It "Should leave a single already flat sensor alone" {
        $result = $MultipleSensorsFlat[0] | ConvertTo-FlatSensors
        $result | Should -Not -BeNullOrEmpty
        $result | Should -BeOfType [PSCustomObject]
        $result.type | Should -Be "Daylight"
        $result.name | Should -Be "sandwich"
        $result.uniqueid | Should -Be "00:ff:ff:ff:ff:ff:ff:ff:03"
        $result.state.Daylight | Should -Be $True
    }

    It 'Should leave multiple already flat sensors alone' {
        $result = $MultipleSensorsFlat | ConvertTo-FlatSensors
        $result | Should -Not -BeNullOrEmpty
        $result | Should -BeOfType [PSCustomObject]
        $result[0].type | Should -Be "Daylight"
        $result[0].name | Should -Be "sandwich"
        $result[0].uniqueid | Should -Be "00:ff:ff:ff:ff:ff:ff:ff:03"
        $result[0].state.Daylight | Should -Be $True
        $result[1].type | Should -Be "ZHAPresence"
        $result[1].name | Should -Be "lemons"
        $result[1].uniqueid | Should -Be "00:ff:ff:ff:ff:ff:ff:ff:04"
        $result[1].state.presence | Should -Be $true
    }
}