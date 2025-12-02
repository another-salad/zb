# Wrap this up in PSScheduledJob or cron, I don't want to know what OS you are using.
# focusing on presence sesnors as the trigger for the moment, likely to change with time.

param(
    [string]$Hostname,
    [Switch]$Testing,
    [int]$MaximumLightBrightness = 255,  # Max brightness to set lights to when triggered.
    [string[]]$OnOffOnlyGroups  # Unfortunately I cannot find a way of detecting what a group supports via the API.
)

$InformationPreference = "Continue"
$WarningPreference = "Continue"

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

Add-Type -AssemblyName System.Net.WebSockets.Client
New-ConbeeSessionUsingVault -hostname $Hostname | out-null
$ws = New-WsConnection
$triggerSensors = Import-TriggerSensors | ConvertTo-FlatObject

$DarkGroupCache = @{}


try {
    while ($ws.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
        $data = $ws | Receive-WsData
        $CurrentSensor = $triggerSensors | Where-Object { $_.apiid -eq $data.id }
        # Initially planned to rely on button and presence states from the ws data, but it seems inconsistent for presence sensors.
        # Only care about sensors (button on presence) in our trigger list.
        if ($CurrentSensor) {
        # if ($data.state.ButtonEvent -or $data.state.Presence) {
            $daylight = Get-DaylightSensors -IgnoreFilter # Gets daylight state from the API
            # These are the events we care about, lets try and build up the group and light information now
            $CurrentSensor = $triggerSensors | Where-Object { $_.apiid -eq $data.id }
            if (!$CurrentSensor) {
                Write-Warning "Received button event for unknown sensor id $($data.id)"
                continue
            }
            # NOTE: Think about multiple groups per sensor?
            $Group = Get-GroupByName -Name $CurrentSensor.TriggerGroup  # Gets the group state from the API
            $Group | Add-Member -MemberType NoteProperty -Name SupportsBrightness -Value $(if ($Group.Name -in $OnOffOnlyGroups) {$False} else {$True}) -Force
            $LightGroupState = $Group | New-LightGroupState -transitiontime 10
            if ($Group.SupportsBrightness) {
                $LightGroupState.Bri = $MaximumLightBrightness
            } else {
                # This should already be $null, but lets be explicit.
                $LightGroupState.Bri = $null
            }
            $GroupSensors = $triggerSensors | Where-Object { $_.TriggerGroup -eq $CurrentSensor.TriggerGroup }
            $IgnoreDaylightSetting = Test-AnySensorProperty -Sensors $GroupSensors -Predicate { $_.IgnoreDaylight }
            if ($data.state.ButtonEvent) {
                Write-Host "Button event: $($data.state.buttonevent)"
                $buttonState = [int]$data.state.buttonevent
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
            } elseif ($CurrentSensor.type -eq "ZHAPresence") {
                # The presense sensors will regulary send updates including state (even if there is no _change_).
                # We will be able to abide by the lock and let the time expire (if it isn't nuked by a button press).
                # The next update cycle after this time should bring us back to normal presense based operation.
                # Since we just always pump the state we want to the API (seemed more logical than trying to deduce the state first given how
                # the presense sensors work) the prior locked state should also be cleared.
                Write-Host "Currently locked groups: $($GroupStateLock | ConvertTo-Json -Depth 3)"
                if ($GroupStateLock.ContainsKey($Group.id)) {
                    # If the lock is set, ignore the presence sensor
                    if ($GroupStateLock[$Group.id] -gt (Get-Date)) {
                        continue
                    }
                    Write-Host "Nuking stale group lock for: $($Group.name)"
                    $GroupStateLock.Remove($Group.id)  # Kill lock if it exists
                }
                # We support mutliple sensors per group, but we don't want the sensors fighting eachother if some detect presence and others don't.
                $LiveSensorState = Get-PresenceSensors | Where-Object { $_.ApiId -in $GroupSensors.ApiId } # Api call
                $PresenceDetected = Test-AnySensorProperty -Sensors $LiveSensorState -Predicate { $_.state.presence }
                $IsDark = Test-AnySensorProperty -Sensors $LiveSensorState -Predicate { $_.state.dark }
                if ($PresenceDetected) {
                    if ($IsDark -and (-not $DarkGroupCache.ContainsKey($Group.id))) {
                        $DarkGroupCache[$Group.id] = @{Dark = $true; TimeAdded = (Get-Date)}
                    }
                    # We are creating a cache as when you walk into the room the light will come on, meaning it is no longer dark. Therefore reading the direct
                    # state from the sensor will only bring you sadness.
                    # The cache will likely be empty here, but this is fine as we are also checking our ignore settings and the daylight sensor state (which is a virtual sensor,
                    # getting the sunrise/sunset values directly from the deconz API (including any offsets configured)).
                    $EffectiveDark = ($DarkGroupCache[$Group.id].Dark) -or ($IgnoreDaylightSetting -or (-not $daylight.state.daylight))
                } else {
                    $DarkGroupCache.Remove($Group.id)
                    # we don't see anyone, so effective dark is false (does a tree make a sound if no one is there to hear it? (Yes ofc it bloody does, but you get me...))
                    $EffectiveDark = $False
                }
                if (-not $EffectiveDark) {
                    # LightGroup default state is $MaximumLightBrightness, so just turn them off if we are in _effective_ daylight.
                    $LightGroupState.Bri = $null
                    $LightGroupState.On = $false
                }
                $LightGroupState | Set-LightGroupState
                Write-Host "Current dark group cache: $($DarkGroupCache | ConvertTo-Json -Depth 3)"
                Write-Host "Sensor: $($CurrentSensor.Name):$($CurrentSensor.ApiId) Presence detected: $PresenceDetected, Ignore Daylight: $IgnoreDaylightSetting, Real dark: $isDark, Effective dark (Power state): $EffectiveDark"
            }
        }
    }
} finally {
    $ws | Close-WsConnection
}
