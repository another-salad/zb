# Wrap this up in PSScheduledJob or cron, I don't want to know what OS you are using.
# focusing on presence sesnors as the trigger for the moment, likely to change with time.

param(
    [string]$Hostname
)

$InformationPreference = "Continue"

import-module conbee-api-client -MinimumVersion 0.0.11 -ErrorAction Stop

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
        # Using the inbuilt daylight sensor as the source of truth here (specifically the daylight property) as it has
        # inbuilt sunrise/sunset times that update and offsets that are sane. Goal here is for the light to come on
        # when it starts to get dark, not when we are actually plunged into darkness.
        $daylight = Get-DaylightSensors -IgnoreFilter
        $data = $ws | Receive-WsData
        foreach ($sensor in $triggerSensors) {
            if ($sensor.ApiId -eq $data.id) {
                # Check for valid button event, as some websocket events are just empty state changes (followed by an actual state change).
                $Group = Get-GroupByName -Name $sensor.TriggerGroup
                if ($sensor.type -eq "ZHASwitch" -and $data.state.buttonevent) {
                    Write-Information "Button event: $($data.state.buttonevent)"
                    $buttonState = [int]$data.state.buttonevent
                    # Some members of the group are off, turn them all on and state override lock (to avoid presence sensors taking over)
                    # NOTE(SALAD): MOVE THIS TO USE THE ANY_ONTRIGGERSTATE. THIS SHOULD BE AN OPTIONAL PROPERTY ON THE GROUP.
                    # THIS ALLOWS A BUTTON TO SET A LOCK FOR A GROUP TO BE IN AN ON OR AN OFF STATE.
                    if (-not $Group.state.any_on) {
                        # Default to an hour if the button event is unknown
                        $OverrideHours = if ($ButtonOverrideHours.ContainsKey($buttonState)) {$ButtonOverrideHours[$buttonState] } else { $ButtonOverrideHours.1002 }
                        $GroupStateLock[$Group.id] = (Get-Date).AddHours($OverrideHours)
                        Write-Information "Group $($Group.name) locked for $OverrideHours hours"
                        $Group | Set-GroupPowerState
                    } else {
                        if ($GroupStateLock.ContainsKey($Group.id)) {
                            $GroupStateLock.Remove($Group.id)
                            Write-Information "Group $($Group.name) unlocked"
                        }
                        $Group | Set-GroupPowerState -off
                        # If its dark, let the presence sensor take over. But we should at least do a cheeky flicker so we know the lock has been killed.
                        if (-not ($daylight.state.Daylight)) {
                            foreach ($powerState in @($true, $false, $true)) {
                                start-sleep -Seconds 1
                                $Group | Set-GroupPowerState -off:(!$powerState)
                            }
                        }
                    }
                # Will be a Presense sensor (as these are the only types we currently listen for)
                } else {
                    # The presense sensors will regulary send updates including state (even if there is no _change_).
                    # We will be able to abide by the lock and let the time expire (if it isn't nuked by a button press).
                    # The next update cycle after this time should bring us back to normal presense based operation.
                    # Since we just always pump the state we want to the API (seemed more logical than trying to deduce the state first given how
                    # the presense sensors work) the prior locked state should also be cleared.
                    if ($GroupStateLock.ContainsKey($Group.id)) {
                        # If the lock is set, ignore the presence sensor
                        if ($GroupStateLock[$Group.id] -gt (Get-Date)) {
                            continue
                        }
                        Write-Information "Nuking stale group lock for: $($Group.name)"
                        $GroupStateLock.Remove($Group.id)  # Kill lock if it exists
                    }
                    # NOTE: SALAD, THE BUG IS HERE.
                    # WE ARE OCCASIONALLY NOT GETTING A SENSOR FROM THE BELOW API CALL.
                    # TEMP HACK TO FOLLOW
                    $Psensor = get-presenceSensors | Where-Object {$_.ApiId -eq $data.id}
                    if (-not $Psensor) {
                        Write-Information "could not find sensor for: $($data.id), skipping."
                        continue
                    }
                    $powerState = $Psensor.state.presence -and ($sensor.IgnoreDaylight -or (-not $daylight.state.daylight))
                    Write-Information "Sensor state: $Psensor. Power state: $powerState"
                    Get-GroupByName -Name $sensor.TriggerGroup | Set-GroupPowerState -off:(!$powerState)
                }
            }
        }
    }
} finally {
    $ws | Close-WsConnection
}