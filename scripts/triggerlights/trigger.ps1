param(
    [Parameter(Mandatory)][ValidateScript({(test-path $_ -PathType Leaf) -and (split-path $_ -Leaf).EndsWith('.clixml')})]$ConfigClixml,  # generate config with New-TriggerConfig
    [switch]$Block
)

$Config = Import-Clixml -Path $ConfigClixml

$EventName = [PSCustomObject]@{
    ButtonEvent = "ButtonEvent"
    Presence = "Presence"
}

Register-EngineEvent -SourceIdentifier $EventName.Presence -Action {
    $Event.MessageData.ModulesToImport | % {import-module $_}
    $manager = [GroupEvent.GroupManager]::new()
    New-ConbeeSessionUsingVault -hostname $Event.MessageData.Hostname
    $darknessEventType = 423
    $darknessLockOffset = $manager.GetPowerEventOffset($darknessEventType)  # $manager.NewPowerEventOffset(423, (New-TimeSpan -Hours 12))
    $Event.MessageData.TriggerSensors | Where-Object { [int]$_.apiid -eq [int]$Event.MessageData.sensorEvent.id } | % {
        $_.TriggerGroup | % {
            $TriggerGroup = $_
            $Group = Get-GroupByName -Name $TriggerGroup  # Gets the group state from the API
            $Group | Add-Member -MemberType NoteProperty -Name SupportsBrightness -Value $(if ($Group.Name -in $Event.MessageData.OnOffOnlyGroups) {$False} else {$True}) -Force
            # So we will have multiple sensors in one area, as we walk through said area each sensor will be processed. We don't want subsequent states
            # from tripping us up. So we have to consider if the group has already been processed due to an earlier (but still _current_) event.
            # To do this we will have the concept of effective darkness. If presence is detected and we are effectively in darkness (i.e. its dark, or sensors are set to ignore light levels)
            # we will always want to turn them on, the inverse for no presence detected.
            $GroupSensors = $Event.MessageData.TriggerSensors | Where-Object { $TriggerGroup -in $_.TriggerGroup }
            $LiveSensorState = Get-PresenceSensors | Where-Object { $_.ApiId -in $GroupSensors.ApiId }  # Api call
            $PresenceDetected = Test-AnySensorProperty -Sensors $LiveSensorState -Predicate { $_.state.presence }
            $CurrentLock = $manager.GetGroupLock($Group.Id) 
            if ($CurrentLock) {
                # TODO: Fix this horror up.
                # I hadn't initially intended for offsets to be so closely linked to requesttypes, but in practice it has turned out this way.
                # There were reasons for the offset table to be so loosey goosey when I was implementing it, but it was too long ago for me to remember right now.
                # Needs a bit of a shape change here.
                if ($CurrentLock.RequestType -eq $darknessEventType -and !$PresenceDetected) {
                    # We have set this to avoid subsequent detection events from fighting eachother whilst someone is in a room.
                    # However the room is now empty, so kill the lock.
                    Write-Debug "Nuking _darkness_ lock for '$($Group.name)' due to no presence being detected"
                    $manager.RemoveGroupLock($Group.Id)
                }
                # Currently for all non-darkness events, may end up doing button specific events later on.
                elseif ($CurrentLock.ReleaseTime -le (Get-Date -AsUTC)) {
                    # Lock has expired, kill it. We'll continue with the usual presence based setting/unsetting flow below.
                    Write-Debug "Nuking lock for '$($Group.name)' due to time expiry"
                    $manager.RemoveGroupLock($Group.Id)
                } else {
                    # Group is locked, move on fam.
                    return
                }
            }

            $LightGroupState = $Group | New-LightGroupState -transitiontime 10
            if ($Group.SupportsBrightness) {
                $LightGroupState.Bri = $Event.MessageData.MaximumLightBrightness
            }

            $IgnoreDaylightSetting = Test-AnySensorProperty -Sensors ($Event.MessageData.TriggerSensors | Where-Object { $TriggerGroup -in $_.TriggerGroup }) -Predicate { $_.IgnoreDaylight }
            if ($PresenceDetected -and ((Test-AnySensorProperty -Sensors $LiveSensorState -Predicate { $_.state.dark }) -or ($IgnoreDaylightSetting -or (-not (Get-DaylightSensors -IgnoreFilter).state.daylight)))) {
                # It is _dark_ (right hand side of the above if) and we have detected someone.
                # Set a group lock with the darkness lock event value, adding a large offset for just some form of safety really.
                Write-Debug "Presence detected for group $($Group.Name), ignore daylight setting: $IgnoreDaylightSetting"
                $manager.NewGroupLock([GroupEvent.GroupLockDTOWithOffset]::new([int]$Group.Id,$Group.Name,$darknessEventType,[GroupEvent.PowerState]::On,$darknessLockOffset))
            } else {
                # LightGroup default state is $MaximumLightBrightness, so just turn them off if we are in _effective_ daylight.
                Write-Debug "Turning group: $($Group.name) off"
                $LightGroupState.Bri = $null
                $LightGroupState.On = $false
            }
            $LightGroupState | Set-LightGroupState
        }
    }
    # an attempt to help with memory usage a little bit
    remove-variable manager -ErrorAction SilentlyContinue
}

Register-EngineEvent -SourceIdentifier $EventName.ButtonEvent -Action {
    $Event.MessageData.ModulesToImport | % {import-module $_}
    New-ConbeeSessionUsingVault -hostname $Event.MessageData.Hostname
    $manager = [GroupEvent.GroupManager]::new()
    $Event.MessageData.TriggerSensors | Where-Object { [int]$_.apiid -eq [int]$Event.MessageData.sensorEvent.id } | % {
        $_.TriggerGroup | % {
            $TriggerGroup = $_
            $Group = Get-GroupByName -Name $TriggerGroup  # Gets the group state from the API
            $Group | Add-Member -MemberType NoteProperty -Name SupportsBrightness -Value $(if ($Group.Name -in $Event.MessageData.OnOffOnlyGroups) {$False} else {$True}) -Force
            $LightGroupState = $Group | New-LightGroupState -transitiontime 10
            if ($Group.SupportsBrightness) {
                $LightGroupState.Bri = $Event.MessageData.MaximumLightBrightness
            }
            # Super speedy check if there are any presence sensors in our group before doing too much other work.
            if (!($Event.MessageData.TriggerSensors | Where-Object { $TriggerGroup -in $_.TriggerGroup } | where type -eq ZHAPresence)) {
                Write-Debug "No presence sensors associated with group $($Group.name). Button press authoritative. No state locking required."
                if ($Group.state.any_on) {
                    $LightGroupState.Bri = $null
                    $LightGroupState.On = $false
                } else {
                    $LightGroupState.On = $true
                }
                $LightGroupState | Set-LightGroupState
            } else {
                $buttonState = [int]$Event.MessageData.sensorEvent.state.buttonevent
                $ButtonOverride = $manager.GetPowerEventOffset($buttonState)
                if (!$ButtonOverride) {
                    Write-Error "Unknown button event state: $buttonState. I can offer you nothing."
                } else {
                    $currentLock = $manager.GetGroupLock($Group.Id)
                    if (!$currentLock) {
                        # We are wanting to lock a light on
                        Write-Debug "Locking group: $($Group.Name) on for + $($ButtonOverride.Offset)"
                        $manager.NewGroupLock(
                            [GroupEvent.GroupLockDTOWithOffset]::new([int]$Group.Id,$Group.Name,[int]$ButtonOverride.Name,[GroupEvent.PowerState]::On,$ButtonOverride)
                        )
                    } elseif ($currentLock.RequestType -eq 423){
                        # Light locked on by presence event, override due to button event and update offset time
                        Write-Debug "Overriding existing presence lock for: $($Group.Name) with new button event: $($ButtonOverride.Offset)"
                        $manager.SetGroupLock(
                            [GroupEvent.GroupLockDTOWithOffset]::new([int]$Group.Id,$Group.Name,[int]$ButtonOverride.Name,[GroupEvent.PowerState]::On,$ButtonOverride)
                        )
                    } else {
                        $IgnoreDaylightSetting = Test-AnySensorProperty -Sensors ($Event.MessageData.TriggerSensors | Where-Object { $TriggerGroup -in $_.TriggerGroup }) -Predicate { $_.IgnoreDaylight }
                        $manager.RemoveGroupLock($Group.Id)
                        Write-Debug "Group $($Group.name) unlocked"
                        # If its dark, let the presence sensor take over. But we should at least do a cheeky flicker so we know the lock has been killed.
                        if (-not ((Get-DaylightSensors -IgnoreFilter).state.Daylight) -or ($IgnoreDaylightSetting -and $group.state.any_on)) {
                            # If its dark or the group ignores daylight and is on, flicker the lights to show we are unlocking.
                            $LightGroupState | Set-LightAcknowledge -FlickerCount 2 -OnOffOnly:(!$Group.SupportsBrightness)
                        } else {
                            # If its daylight and the group conforms to that then just turn them off.
                            $LightGroupState.Bri = $null
                            $LightGroupState.On = $false
                            $LightGroupState | Set-LightGroupState
                        }
                        return  # as we have a unique light setting case
                    }
                    $LightGroupState | Set-LightGroupState
                    if ($Group.state.any_on) {  # Old value prior to button press.
                        # Lights were on prior, so we should acknowledge that a lock has been set.
                        $LightGroupState | Set-LightAcknowledge -OnOffOnly:(!$Group.SupportsBrightness)
                    }
                }
            }
        }
    }
    # an attempt to help with memory usage a little bit
    remove-variable manager -ErrorAction SilentlyContinue
}

$job = start-job -name LightManager -scriptblock {
    $using:Config.ModulesToImport | % {import-module $_}
    New-ConbeeSessionUsingVault -hostname $using:Config.HostName
    $ws = New-WsConnection
    $triggerSensors = Import-TriggerSensors | ConvertTo-FlatObject

    # Register event forwarding once at startup
    $using:EventName | gm -MemberType NoteProperty | select -ExpandProperty Name | % { Register-EngineEvent -SourceIdentifier $_ -Forward } 
    
    try {
        while ($ws.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
            $sensorEvent = $ws | Receive-WsData | where id -in $triggerSensors.ApiId
            if ($sensorEvent) {
                $EventData = [pscustomobject]@{
                    sensorEvent            = $sensorEvent
                    TriggerSensors         = $triggerSensors
                    # I know the unpacking is a little hideous, but I still think its nicer to hold for the events if the config is unpacked.
                    OnOffOnlyGroups        = $using:Config.OnOffOnlyGroups
                    ModulesToImport        = $using:Config.ModulesToImport
                    Hostname               = $using:Config.HostName
                    MaximumLightBrightness = $using:Config.MaximumLightBrightness
                }
                # We care about buttonevents or presence updates, generic state changed events can be dropped to the floor
                $EventType = if ($sensorEvent.state.ButtonEvent) { $using:EventName.ButtonEvent } elseif ($sensorEvent.state | gm -name Presence) { $using:EventName.Presence } else { $null }
                if ($EventType) {
                    New-Event -SourceIdentifier $EventType -MessageData $EventData 
                }
            }    
        }      
    } finally {
        $ws | Close-WsConnection
    }
}

if ($Block) {
    try {
        while ($True) {
            # check on all of the Event jobs we spawn
            $failed = Get-job | where state -eq failed
            if ($failed) {
                Throw "Jobs: $($failed.name -join ', ') failed"
            }
            Start-Sleep -Seconds 1
        }
    } finally {
        get-job | stop-job
    }
}
