import-module (Join-Path $PSScriptRoot '../conbee-api-client/conbee-api-client.psd1') -Force -ErrorAction Stop

BeforeAll {
    . $PSScriptRoot\TestData.ps1
}

Describe "Test Add-ApiIdToSensors" {
    It "should add the ApiId property to each sensor" {
        $sensors = $RawPresenceSensors | Add-ApiIdToSensors
        $sensors | Should -Not -BeNullOrEmpty
        $sensors."1".ApiId | Should -Be 1
        $sensors."2".ApiId | Should -Be 2
    }

}