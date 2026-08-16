param(
    [Parameter(Mandatory)][ValidateScript({(test-path $_ -PathType Leaf) -and (split-path $_ -Leaf).EndsWith('.clixml')})]$ConfigClixml,  # generate config with New-TriggerConfig
    [switch]$Block
)

$Config = Import-Clixml -Path $ConfigClixml

$EventName = [PSCustomObject]@{
    ButtonEvent = "ButtonEvent"
    DimmerEvent = "DimmerEvent"  # Also a button event, but with specific nuance
    Presence = "Presence"
}


$job = start-job -name LightManager -scriptblock {
    $using:Config.ModulesToImport | % {import-module $_}
    New-ConbeeSessionUsingVault -hostname $using:Config.HostName
    $ws = New-WsConnection
    $triggerSensors = Import-TriggerSensors | ConvertTo-FlatObject
    $manager = [GroupEvent.GroupManager]::new()

    # TODO: Should be in a better place (like the DB), but here for now.
    $XyColourDefaults = [PSCustomObject]@{                                                                                    
        0 = @{         
            # Green                                                                                                  
            xy = @(0.2, 0.7)   
        }
        1 = @{
            # Yellow
            xy = @(0.45, 0.5)
        }
        2 = @{
            # Red
            xy = @(0.6, 0.3)
        }
        3 = @{
            # Purple
            xy = @(0.45, 0.2)
        }
        4 = @{
            # blue
            xy = @(0.165, 0.0975)
        }
        5 = @{
            # light blue
            xy = @(0.125, 0.325)
        }
        6 = @{
            # minty?
            xy = @(0.25, 0.48)
        }
        7 = @{
            # white
            xy = @(0.35, 0.35)
        }
    }
    
    # TODO: Move this too
    Function XyArrayWithinTolerance {
        # When setting X,Y colour values to some lights (an RGB TV strip for example), what you set is not always what you get.
        # The deconz API seemingly sets a close approximation of the CIE xy colour space coordinates, or rounding is hard or whatever. 
        param(
            $RequestedXy,
            $CurrentXy,
            $tolerance = 20 # A percentage
        )
        for ($i=0;$i -lt $CurrentXy.Count;$i++) {
            if (([math]::Abs(($RequestedXy[$i] - $CurrentXy[$i]) / $CurrentXy[$i]) * 100) -gt $tolerance) {
                $false
                return
            }
        }
        $True
    }

    Register-EngineEvent -SourceIdentifier $using:EventName.Presence -Action {
        $darknessEventType = 423
        $darknessLockOffset = $manager.GetPowerEventOffset($darknessEventType)  # $manager.NewPowerEventOffset(423, (New-TimeSpan -Hours 12))
        $TriggerSensors | Where-Object { [int]$_.apiid -eq [int]$Event.MessageData.sensorEvent.id } | % {
            $_.TriggerGroup | % {
                $TriggerGroup = $_
                $Group = Get-GroupByName -Name $TriggerGroup  # Gets the group state from the API
                $Group | Add-Member -MemberType NoteProperty -Name SupportsBrightness -Value $(if ($Group.Name -in $Event.MessageData.OnOffOnlyGroups) {$False} else {$True}) -Force
                # So we will have multiple sensors in one area, as we walk through said area each sensor will be processed. We don't want subsequent states
                # from tripping us up. So we have to consider if the group has already been processed due to an earlier (but still _current_) event.
                # To do this we will have the concept of effective darkness. If presence is detected and we are effectively in darkness (i.e. its dark, or sensors are set to ignore light levels)
                # we will always want to turn them on, the inverse for no presence detected.
                $GroupSensors = $TriggerSensors | Where-Object { $TriggerGroup -in $_.TriggerGroup }
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

                $IgnoreDaylightSetting = Test-AnySensorProperty -Sensors ($TriggerSensors | Where-Object { $TriggerGroup -in $_.TriggerGroup }) -Predicate { $_.IgnoreDaylight }
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
    }

    Register-EngineEvent -SourceIdentifier $using:EventName.ButtonEvent -Action {
        $TriggerSensors | Where-Object { [int]$_.apiid -eq [int]$Event.MessageData.sensorEvent.id } | % {
            $_.TriggerGroup | % {
                $TriggerGroup = $_
                $Group = Get-GroupByName -Name $TriggerGroup  # Gets the group state from the API
                $Group | Add-Member -MemberType NoteProperty -Name SupportsBrightness -Value $(if ($Group.Name -in $Event.MessageData.OnOffOnlyGroups) {$False} else {$True}) -Force
                $LightGroupState = $Group | New-LightGroupState -transitiontime 10
                if ($Group.SupportsBrightness) {
                    $LightGroupState.Bri = $Event.MessageData.MaximumLightBrightness
                }
                # Super speedy check if there are any presence sensors in our group before doing too much other work.
                if (!($TriggerSensors | Where-Object { $TriggerGroup -in $_.TriggerGroup } | where type -eq ZHAPresence)) {
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
                            $IgnoreDaylightSetting = Test-AnySensorProperty -Sensors ($TriggerSensors | Where-Object { $TriggerGroup -in $_.TriggerGroup }) -Predicate { $_.IgnoreDaylight }
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
    }

    Register-EngineEvent -SourceIdentifier $using:EventName.DimmerEvent -Action {
        $TriggerSensors | Where-Object { [int]$_.apiid -eq [int]$Event.MessageData.sensorEvent.id } | % {
            $_.TriggerGroup | % {
                $TriggerGroup = $_
                $Group = Get-GroupByName -Name $TriggerGroup  # Gets the group state from the API
                $buttonEvent = [int]$Event.MessageData.sensorEvent.state.ButtonEvent
                $LightGroupState = $Group | New-LightGroupState -transitiontime 10  # 10 actually looks good in the real world.
                $LightGroupState.On = $true
                if ($buttonEvent -eq 4002) {  # A Press and release of the scene button (labled hue on philips switches)
                    # A _speedy enough_ way of iterating through the colour cycle without having to known what is before or behind you.
                    $LightGroupState.xy = $(
                        if     (XyArrayWithinTolerance $XyColourDefaults."0".xy $Group.action.xy) {$XyColourDefaults."1".xy}  # 0 maps to 1
                        elseif (XyArrayWithinTolerance $XyColourDefaults."1".xy $Group.action.xy) {$XyColourDefaults."2".xy}  # 1 maps to 2
                        elseif (XyArrayWithinTolerance $XyColourDefaults."2".xy $Group.action.xy) {$XyColourDefaults."3".xy}  # 2 maps to 3
                        elseif (XyArrayWithinTolerance $XyColourDefaults."3".xy $Group.action.xy) {$XyColourDefaults."4".xy}  # 3 maps to 4
                        elseif (XyArrayWithinTolerance $XyColourDefaults."4".xy $Group.action.xy) {$XyColourDefaults."5".xy}  # 4 maps to 5
                        elseif (XyArrayWithinTolerance $XyColourDefaults."5".xy $Group.action.xy) {$XyColourDefaults."6".xy}  # 5 maps to 6
                        elseif (XyArrayWithinTolerance $XyColourDefaults."6".xy $Group.action.xy) {$XyColourDefaults."7".xy}  # 6 maps to 7
                        else   {$XyColourDefaults."0".xy}
                    )
                } else {
                    $LightGroupState.Bri = if ($buttonEvent -lt 3000) {
                        # 200X events are to increase light levels
                        [math]::Min($Group.action.bri + 40, $Event.MessageData.MaximumLightBrightness)  # don't want to go above max brightness
                    } elseif ($buttonEvent -lt 4000) {
                        # 300X events are to decrease
                        [math]::Max($Group.action.bri - 40, 20)  # don't want to go below zero
                    } else {
                        return # these events are meaningless, so lets get out of here
                    }
                }
                $LightGroupState | Set-LightGroupState
            }
        }
    }

    # Register event forwarding once at startup
    # $using:EventName | gm -MemberType NoteProperty | select -ExpandProperty Name | % { Register-EngineEvent -SourceIdentifier $_ -Forward }
    
    try {
        while ($ws.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
            $sensorEvent = $ws | Receive-WsData | where id -in $triggerSensors.ApiId
            if ($sensorEvent) {
                $EventData = [pscustomobject]@{
                    sensorEvent            = $sensorEvent
                    # I know the unpacking is a little hideous, but I still think its nicer to hold for the events if the config is unpacked.
                    OnOffOnlyGroups        = $using:Config.OnOffOnlyGroups
                    ModulesToImport        = $using:Config.ModulesToImport
                    Hostname               = $using:Config.HostName
                    MaximumLightBrightness = $using:Config.MaximumLightBrightness
                }
                # We care about buttonevents (dimmer or standard) or presence updates, generic state changed events can be dropped to the floor
                if ($sensorEvent.state.ButtonEvent) {
                    # We can be a normal button press or a dimmer
                    if ($manager.GetPowerEventOffset([int]$sensorEvent.state.ButtonEvent)) {
                        # Dimmers aren't used to lock lights on, they only care about light level state when they are being processed.
                        # If we have a powerevent offset hit, we must be a normal on/off request (or a _darkness_ event).
                        New-Event -SourceIdentifier $using:EventName.ButtonEvent -MessageData $EventData
                    } elseif (($sensorEvent.state | gm -name eventduration) -and ($sensorEvent.state.eventduration -gt 0)) {
                        # Dimmers send null duration events when a button is pressed. We don't care about these, we only want the later emitted events which show which press type occurred (long/hold/short).
                        New-Event -SourceIdentifier $using:EventName.DimmerEvent -MessageData $EventData
                    }
                } elseif ($sensorEvent.state | gm -name Presence) {
                    New-Event -SourceIdentifier $using:EventName.Presence -MessageData $EventData
                }
            }    
        }      
    } finally {
        $ws | Close-WsConnection
    }
}

if ($Block) {
    while ($job.State -eq 'Running') {start-sleep -Seconds 0.1 }
}
