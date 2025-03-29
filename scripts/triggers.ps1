# Wrap this up in PSScheduledJob or cron, I don't want to know what OS you are using.
# focusing on presence sesnors as the trigger for the moment, likely to change with time.

param(
    [string]$Hostname
)

import-module conbee-api-client -MinimumVersion 0.0.8 -ErrorAction Stop

Add-Type -AssemblyName System.Net.WebSockets.Client
New-ConbeeSessionUsingVault -hostname $Hostname | out-null
$ws = New-WsConnection
$triggerSensors = Import-TriggerSensors | ConvertTo-FlatObject
try {
    while ($ws.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
        $data = $ws | Receive-WsData
        foreach ($sensor in $triggerSensors) {
            if ($sensor.ApiId -eq $data.id) {
                $sensorState = get-presenceSensors | Where-Object {$_.ApiId -eq $data.id}
                # Using the inbuilt daylight sensor as the source of truth here (specifically the daylight property) as it has
                # inbuilt sunrise/sunset times that update and offsets that are sane. Goal here is for the light to come on
                # when it starts to get dark, not when we are actually plunged into darkness.
                $daylight = Get-DaylightSensors -IgnoreFilter
                $powerState = $sensorState.state.presence -and (-not $daylight.state.daylight -or $sensor.IgnoreDaylight)
                Get-GroupByName -Name $sensor.TriggerGroup | Set-GroupPowerState -off:(!$powerState)
            }
        }
    }
} finally {
    $ws | Close-WsConnection
}