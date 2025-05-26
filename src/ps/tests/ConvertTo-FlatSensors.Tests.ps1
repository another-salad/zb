import-module (Join-Path $PSScriptRoot '../conbee-api-client/conbee-api-client.psd1') -Force -ErrorAction Stop

BeforeAll {
    $NonFlatSensors = [PSCustomObject]@{
        1 = [PSCustomObject]@{
            ApiId = 1
            type = "Daylight"
            name = "sandwich"
            uniqueid = "00:ff:ff:ff:ff:ff:ff:ff:03"
            state = @{
                Daylight = $false
                LastUpdated = "2024-07-07T12:00:00Z"
                status = 190
                dark = $false
                sunrise = "23/04/2025 05:55:55"
                sunset = "23/04/2025 18:55:55"
            }
        }
        2 = [PSCustomObject]@{
            ApiId = 2
            type = "ZHAPresence"
            name = "lemons"
            uniqueid = "00:ff:ff:ff:ff:ff:ff:ff:04"
            state = @{
                presence = $true
                LastUpdated = "2024-07-07T12:00:00Z"
                dark = $true
            }
        }
    }
    $FlatSensor = $NonFlatSensors.1
}

Describe "ConvertTo-FlatSensors" {
    It "should un-nest pscustomobjects to an array of invidiual sensors" {
        $result = $NonFlatSensors | ConvertTo-FlatSensors
        $result | Should -Not -BeNullOrEmpty
        $result | Should -BeOfType [PSCustomObject]
        $result.Count | Should -Be 2
        $result[0].ApiId | Should -Be 1
        $result[0].type | Should -Be "Daylight"
        $result[0].name | Should -Be "sandwich"
        $result[0].uniqueid | Should -Be "00:ff:ff:ff:ff:ff:ff:ff:03"
        $result.state.Daylight | Should -Be $false
        $result[1].ApiId | Should -Be 2
        $result[1].type | Should -Be "ZHAPresence"
        $result[1].name | Should -Be "lemons"
        $result[1].uniqueid | Should -Be "00:ff:ff:ff:ff:ff:ff:ff:04"
        $result[1].state.presence | Should -Be $true
    }
    It "Should leave an already flat sensor alone" {
        $result = $FlatSensor | ConvertTo-FlatSensors
        $result | Should -Not -BeNullOrEmpty
        $result | Should -BeOfType [PSCustomObject]
        $result.ApiId | Should -Be 1
        $result.type | Should -Be "Daylight"
        $result.name | Should -Be "sandwich"
        $result.uniqueid | Should -Be "00:ff:ff:ff:ff:ff:ff:ff:03"
        $result.state.Daylight | Should -Be $false
    }
}