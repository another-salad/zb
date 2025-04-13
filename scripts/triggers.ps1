# Wrap this up in PSScheduledJob or cron, I don't want to know what OS you are using.
# focusing on presence sesnors as the trigger for the moment, likely to change with time.

param(
    [string]$Hostname
)

import-module conbee-api-client -MinimumVersion 0.0.9 -ErrorAction Stop

$ButtonOverrideHours = @{
    1002 = 1  # Short press
    1003 = 8 # Long press
    1004 = 2 # Double press
}

$GroupStateLock = @{}

Add-Type -AssemblyName System.Net.WebSockets.Client
New-ConbeeSessionUsingVault -hostname $Hostname | out-null
$ws = New-WsConnection
$triggerSensors = Import-TriggerSensors | ConvertTo-FlatObject
try {
    while ($ws.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
        $data = $ws | Receive-WsData
        foreach ($sensor in $triggerSensors) {
            if ($sensor.ApiId -eq $data.id) {
                $Group = Get-GroupByName -Name $sensor.TriggerGroup
                # Check for valid button event, as some websocket events are just empty state changes (followed by an actual state change).
                if ($sensor.type -eq "ZHASwitch" -and $data.state.buttonevent) {
                    $buttonState = [int]$data.state.buttonevent
                    # Some members of the group are off, turn them all on and state override lock (to avoid presence sensors taking over)
                    if (-not $Group.state.any_on) {
                        # Default to an hour if the button event is unknown
                        $OverrideHours = if ($ButtonOverrideHours.ContainsKey($buttonState)) {$ButtonOverrideHours[$buttonState] } else { $ButtonOverrideHours.1002 }
                        $GroupStateLock[$Group.id] = (Get-Date).AddHours($OverrideHours)
                        Write-Information "Group $($Group.name) locked for $OverrideHours hours"
                        $Group | Set-GroupPowerState
                    } else {
                        # Nuke the lock and turn everything off
                        $GroupStateLock.Remove($Group.id)
                        $Group | Set-GroupPowerState -off
                    }
                # Will be a Presense sensor (as these are the only types we currently listen for)
                } else {
                    # The presense sensors will regulary send updates including state (even if there is no _change_).
                    # We will be able to abide by the lock and let the time expire (if it isn't nuked by a button press).
                    # The next update cycle after this time should bring us back to normal presense based operation.
                    # Since we just always pump the state we want to the API (seemed more logical than trying to deduce the state first given how
                    # the presense sensors work) the prior locked state should also be cleared.
                    if ($GroupStateLock.ContainsKey($Group.id) -and $GroupStateLock[$Group.id] -gt (Get-Date)) {
                        # If the lock is set, ignore the presence sensor
                        continue
                    }
                    $GroupStateLock.Remove($Group.id)  # Kill lock if it exists
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
    }
} finally {
    $ws | Close-WsConnection
}