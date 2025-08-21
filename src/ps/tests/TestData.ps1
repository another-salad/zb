$RawPresenceSensors = [PSCustomObject]@{
    1 = [PSCustomObject]@{
        type = "ZHAPresence"
        name = "sensor0"
        uniqueid = "00:ff:ff:ff:ff:ff:ff:ff:01"
        state = @{
            presence = $true
            LastUpdated = "2024-07-07T12:00:00Z"
            dark = $false
        }
    }
    2 = [PSCustomObject]@{
        type = "ZHAPresence"
        name = "sensor1"
        uniqueid = "00:ff:ff:ff:ff:ff:ff:ff:02"
        state = @{
            presence = $true
            LastUpdated = "2024-07-08T12:00:00Z"
            dark = $true
        }
    }
}

$DaylightSensor = [PSCustomObject]@{
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

$MultipleSensorsFlat = @(
    $DaylightSensor,
    $singleDarkPresenceSensor
)

$allDarkSensorsFlat = @(
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
