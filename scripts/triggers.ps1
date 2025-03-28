# Wrap this up in PSScheduledJob or cron, I don't want to know what OS you are using.
# focusing on presence sesnors as the trigger for the moment, likely to change with time.

param(
    [string]$Hostname
)

import-module conbee-api-client -MinimumVersion 0.0.6

Add-Type -AssemblyName System.Net.WebSockets.Client
New-ConbeeSessionUsingVault -hostname $Hostname
$ws = New-WsConnection
$triggerSensors = Import-TriggerSensors
try {
    while ($ws.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
        $data = $ws | Receive-WsData
        foreach ($sensor in $triggerSensors) {
            if ($sensor.PSObject.Properties.value.ApiId -eq $data.id) {
                $sensorState = get-presenceSensors | Where-Object {$_.ApiId -eq $data.id}
                # Write-Host "Sensor $($sensor.PSObject.Properties.value.ApiId) presence state: $($sensorState.state.presence)"
                if ($sensorState.state.presence) {
                    Get-GroupByName -Name $sensor.PSObject.Properties.value.TriggerGroup | Set-GroupPowerState
                } else {
                    Get-GroupByName -Name $sensor.PSObject.Properties.value.TriggerGroup | Set-GroupPowerState -off
                }
            }
        }
    }
} finally {
    $ws | Close-WsConnection
}