# Can then be exported as clixml
Function New-SunsetTimerConfig {
    [pscustomobject]@{
        PsTypeName = "SunsetTimerConfig"
        Group = $null
        PowerState = "On"
        ReleaseTimeUTC = [TimeOnly]::Parse("21:00:00")
        StartOffset = [TimeSpan]::Parse("00:30:00")
    }
}