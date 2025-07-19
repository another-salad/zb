import-module (Join-Path $PSScriptRoot '../conbee-api-client/conbee-api-client.psd1') -Force -ErrorAction Stop

BeforeAll {
    $sensor = [PSCustomObject]@{
        ApiId = 1
        type = "Daylight"
        name = "sandwich"
        uniqueid = "00:ff:ff:ff:ff:ff:ff:ff:03"
        state = @{
            Daylight = $True
            LastUpdated = "2024-07-07T12:00:00Z"
            dark = $false
            sunrise = "23/04/2025 05:55:55"
            sunset = "23/04/2025 18:55:55"
        }
    }
    $singleDarkPresenceSensor = [PSCustomObject]@{
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
    $MultipleSensors = @(
        $sensor,
        $singleDarkPresenceSensor
    )
    $allDarkSensors = @(
        $singleDarkPresenceSensor,
        [PSCustomObject]@{
            ApiId = 3
            type = "ZHAPresence"
            name = "darkness"
            uniqueid = "00:ff:ff:ff:ff:ff:ff:ff:05"
            state = @{
                Dark = $true
                LastUpdated = "2024-07-07T12:00:00Z"
                presence = $true
            }
        }
    )
}

Describe "Test-AnySensorProperty" {
    It "should return true if the predicate is met for a single sensor" {
        $result = Test-AnySensorProperty -Sensors $singleDarkPresenceSensor -Predicate { $_.state.Dark }
        $result | Should -Be $true
    }

    It "should return true if the predicate is met for any sensor" {
        $result = Test-AnySensorProperty -Sensors $MultipleSensors -Predicate { $_.state.dark }
        $result | Should -Be $true
    }

    It "should return true if the predicate is met for all sensors" {
        $result = Test-AnySensorProperty -Sensors $allDarkSensors -Predicate { $_.state.dark }
        $result | Should -Be $true
    }

    It "should return false if it can't find the property in the predicate" {
        $result = Test-AnySensorProperty -Sensors $sensor -Predicate { $_.state.NotAPropertySoz }
        $result | Should -Be $false
    }

    It "should return false if it can't find the property in the predicate for any sensor" {
        $result = Test-AnySensorProperty -Sensors $MultipleSensors -Predicate { $_.state.NotAPropertySoz }
        $result | Should -Be $false
    }

    It "should return true if the predicate is met for any sensor" {
        # Using daylight as it is only present in the first sensor
        $result = Test-AnySensorProperty -Sensors $MultipleSensors -Predicate { $_.state.Daylight }
        $result | Should -Be $true
    }

    It "should return false if it can't find the property in the predicate for any sensor" {
        $result = Test-AnySensorProperty -Sensors $MultipleSensors -Predicate { $_.state.NotAPropertySoz }
        $result | Should -Be $false
    }

}