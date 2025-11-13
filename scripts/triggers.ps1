# Wrap this up in PSScheduledJob or cron, I don't want to know what OS you are using.
# focusing on presence sesnors as the trigger for the moment, likely to change with time.

param(
    [string]$Hostname,
    [Switch]$Testing,
    [int]$MaximumLightBrightness = 250  # Max brightness to set lights to when triggered. Default is 200 (out of 254).
)

$InformationPreference = "Continue"

# For testing local development changes
if ($testing) {
    Import-Module -Name "$PSScriptRoot\..\src\ps\conbee-api-client\conbee-api-client.psd1" -Force -ErrorAction Stop
} else{
    import-module conbee-api-client -MinimumVersion 0.0.14 -ErrorAction Stop
}

$ButtonOverrideHours = @{
    1002 = 1  # Short press
    1003 = 8 # Long press
    1004 = 2 # Double press
}

$GroupStateLock = @{}
$OnOffOnlyGroups = @("plugos")  # Unfortunately I cannot find a way of detecting what a group supports via the API.

Add-Type -AssemblyName System.Net.WebSockets.Client
New-ConbeeSessionUsingVault -hostname $Hostname | out-null
$ws = New-WsConnection
$triggerSensors = Import-TriggerSensors | ConvertTo-FlatObject

$DarkSensorCache = @{}


try {
    while ($ws.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
        # Using the inbuilt daylight sensor as the source of truth here (specifically the daylight property) as it has
        # inbuilt sunrise/sunset times that update and offsets that are sane. Goal here is for the light to come on
        # when it starts to get dark, not when we are actually plunged into darkness.
        $daylight = Get-DaylightSensors -IgnoreFilter
        $data = $ws | Receive-WsData
        foreach ($sensor in $triggerSensors) {
            if ($sensor.ApiId -eq $data.id) {
                $Group = Get-GroupByName -Name $sensor.TriggerGroup
                $Group | Add-Member -MemberType NoteProperty -Name SupportsBrightness -Value $(if ($Group.Name -in $OnOffOnlyGroups) {$False} else {$True}) -Force
                $LightGroupState = $Group | New-LightGroupState -transitiontime 10
                if ($Group.SupportsBrightness) {
                    $LightGroupState.Bri = $MaximumLightBrightness
                } else {
                    # This should already be $null, but lets be explicit.
                    $LightGroupState.Bri = $null
                }
                # Check for valid button event, as some websocket events are just empty state changes (followed by an actual state change).
                if ($sensor.type -eq "ZHASwitch" -and $data.state.buttonevent) {
                    Write-Host "Button event: $($data.state.buttonevent)"
                    $buttonState = [int]$data.state.buttonevent
                    # Some members of the group are off, turn them all on and state override lock (to avoid presence sensors taking over)
                    # NOTE(SALAD): MOVE THIS TO USE THE ANY_ONTRIGGERSTATE. THIS SHOULD BE AN OPTIONAL PROPERTY ON THE GROUP.
                    # THIS ALLOWS A BUTTON TO SET A LOCK FOR A GROUP TO BE IN AN ON OR AN OFF STATE.
                    # Think about how to handle state switching when less sleepy: Old condition: -not $Group.state.any_on)
                    if (-not $GroupStateLock.ContainsKey($Group.id)) {
                        # Default to an hour if the button event is unknown
                        $OverrideHours = if ($ButtonOverrideHours.ContainsKey($buttonState)) {$ButtonOverrideHours[$buttonState] } else { $ButtonOverrideHours.1002 }
                        $GroupStateLock[$Group.id] = (Get-Date).AddHours($OverrideHours)
                        Write-Host "Group $($Group.name) locked for $OverrideHours hours"
                        $LightGroupState | Set-LightGroupState
                        if ($Group.state.any_on) {  # Old value prior to button press.
                            # Lights were on prior, so we should acknowledge that a lock has been set.
                            $LightGroupState | Set-LightAcknowledge -OnOffOnly:(!$Group.SupportsBrightness)
                            
                        }
                    } else {
                        $GroupStateLock.Remove($Group.id)
                        Write-Host "Group $($Group.name) unlocked"
                        # NOTE (SALAD): THIS NEEDS CENTRALISING AS IT IS DUPLICATED BELOW.
                        # We want consistent behaviour when the light group is on and we are unlocking it (as groups can ignore daylight).
                        $GroupTriggerSensors = $triggerSensors | Where-Object {$_.TriggerGroup -eq $sensor.TriggerGroup -and $_.type -eq "ZHAPresence"}
                        $IgnoreDaylightSetting = Test-AnySensorProperty -Sensors $GroupTriggerSensors -Predicate { $_.IgnoreDaylight }
                        # If its dark, let the presence sensor take over. But we should at least do a cheeky flicker so we know the lock has been killed.
                        if (-not ($daylight.state.Daylight) -or ($IgnoreDaylightSetting -and $group.state.any_on)) {
                            # If its dark or the group ignores daylight and is on, flicker the lights to show we are unlocking.
                            $LightGroupState | Set-LightAcknowledge -FlickerCount 2 -OnOffOnly:(!$Group.SupportsBrightness)
                        } else {
                            # If its daylight and the group conforms to that then just turn them off.
                            $LightGroupState.Bri = $null
                            $LightGroupState.On = $false
                            $LightGroupState | Set-LightGroupState
                        }
                    }
                } elseif ($sensor.type -eq "ZHAPresence") {
                    # The presense sensors will regulary send updates including state (even if there is no _change_).
                    # We will be able to abide by the lock and let the time expire (if it isn't nuked by a button press).
                    # The next update cycle after this time should bring us back to normal presense based operation.
                    # Since we just always pump the state we want to the API (seemed more logical than trying to deduce the state first given how
                    # the presense sensors work) the prior locked state should also be cleared.
                    # Write-Host "Currently locked groups: $($GroupStateLock | ConvertTo-Json -Depth 3)"
                    if ($GroupStateLock.ContainsKey($Group.id)) {
                        # If the lock is set, ignore the presence sensor
                        if ($GroupStateLock[$Group.id] -gt (Get-Date)) {
                            continue
                        }
                        Write-Host "Nuking stale group lock for: $($Group.name)"
                        $GroupStateLock.Remove($Group.id)  # Kill lock if it exists
                    }

                    $allActiveSensors = Get-PresenceSensors
                    # Get all sensors from TriggerSensors that have the same TriggerGroup as the current sensor.
                    $GroupTriggerSensors = $triggerSensors | Where-Object {$_.TriggerGroup -eq $sensor.TriggerGroup -and $_.type -eq "ZHAPresence"}
                    # Keep this hack in as we were having null responses from the API turn off lights for no good reason and its annoying.
                    $missingSensors = $GroupTriggerSensors | Where-Object {$AllActiveSensors.ApiId -notcontains $_.ApiId}
                    if ($missingSensors) {
                        Write-Host "Could not find these sensors in api response: $($missingSensors.ApiId -join ', '), skipping."
                        continue
                    }
                    # Get current state of all relevant sensors for later processing.
                    $LiveGroupSensorStates = $allActiveSensors | Where-Object {$GroupTriggerSensors.ApiId -eq $_.ApiId}
                    $PresenceDetected = Test-AnySensorProperty -Sensors $LiveGroupSensorStates -Predicate { $_.state.presence }
                    $IsDark = Test-AnySensorProperty -Sensors $LiveGroupSensorStates -Predicate { $_.state.dark }
                    $IgnoreDaylightSetting = Test-AnySensorProperty -Sensors $GroupTriggerSensors -Predicate { $_.IgnoreDaylight }

                    if ($PresenceDetected) {
                        if ($IsDark -and (-not $DarkSensorCache.ContainsKey($sensor.ApiId))) {
                            $DarkSensorCache[$sensor.ApiId] = @{Dark = $true; TimeAdded = (Get-Date)}
                        }
                        # We are creating a cache as when you walk into the room the light will come on, meaning it is no longer dark. Therefore reading the direct
                        # state from the sensor will only bring you sadness.
                        # The cache will likely be empty here, but this is fine as we are also checking our ignore settings and the daylight sensor state (which is a virtual sensor,
                        # getting the sunrise/sunset values directly from the deconz API (including any offsets configured)).
                        $EffectiveDark = ($DarkSensorCache[$sensor.ApiId].Dark) -or ($IgnoreDaylightSetting -or (-not $daylight.state.daylight))
                    } else {
                        $DarkSensorCache.Remove($sensor.ApiId)
                        # we don't see anyone, so effective dark is false (does a tree make a sound if no one is there to hear it? (Yes ofc it bloody does, but you get me...))
                        $EffectiveDark = $False
                    }
                    # Write-Host "Current dark sensor cache: $($DarkSensorCache | ConvertTo-Json -Depth 3)"

                    Write-Host "Sensor Id: $($sensor.ApiId) Presence detected: $PresenceDetected, Ignore Daylight: $IgnoreDaylightSetting, Real dark: $isDark, Effective dark (Power state): $EffectiveDark"
                    if (-not $EffectiveDark) {
                        # LightGroup default state is $MaximumLightBrightness, so just turn them off if we are in _effective_ daylight.
                        $LightGroupState.Bri = $null
                        $LightGroupState.On = $false
                    }
                    $LightGroupState | Set-LightGroupState
                }
            }
        }
    }
} finally {
    $ws | Close-WsConnection
}