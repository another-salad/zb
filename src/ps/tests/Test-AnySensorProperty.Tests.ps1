import-module (Join-Path $PSScriptRoot '../conbee-api-client/conbee-api-client.psd1') -Force -ErrorAction Stop

BeforeAll {
    . $PSScriptRoot\TestData.ps1
}

Describe "Test-AnySensorProperty" {
    It "should return true if the predicate is met for a single sensor" {
        $result = Test-AnySensorProperty -Sensors $singleDarkPresenceSensor -Predicate { $_.state.Dark }
        $result | Should -Be $true
    }

    It "should return true if the predicate is met for any sensor" {
        $result = Test-AnySensorProperty -Sensors $MultipleSensorsFlat -Predicate { $_.state.dark }
        $result | Should -Be $true
    }

    It "should return true if the predicate is met for all sensors" {
        $result = Test-AnySensorProperty -Sensors $allDarkSensorsFlat -Predicate { $_.state.dark }
        $result | Should -Be $true
    }

    It "should return false if it can't find the property in the predicate" {
        $result = Test-AnySensorProperty -Sensors $DaylightSensor -Predicate { $_.state.NotAPropertySoz }
        $result | Should -Be $false
    }

    It "should return false if it can't find the property in the predicate for any sensor" {
        $result = Test-AnySensorProperty -Sensors $MultipleSensorsFlat -Predicate { $_.state.NotAPropertySoz }
        $result | Should -Be $false
    }

    It "should return true if the predicate is met for any sensor" {
        # Using daylight as it is only present in the first sensor
        $result = Test-AnySensorProperty -Sensors $MultipleSensorsFlat -Predicate { $_.state.Daylight }
        $result | Should -Be $true
    }

    It "should return false if it can't find the property in the predicate for any sensor" {
        $result = Test-AnySensorProperty -Sensors $MultipleSensorsFlat -Predicate { $_.state.NotAPropertySoz }
        $result | Should -Be $false
    }

}