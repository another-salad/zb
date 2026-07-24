param(
    [Parameter(Mandatory)][string]$Hostname,
    [int]$MaximumLightBrightness = 255,  # Max brightness to set lights to when triggered.
    [string[]]$OnOffOnlyGroups,  # Unfortunately I cannot find a way of detecting what a group supports via the API.
    [Parameter(Mandatory)][string[]]$ModulesToImport
)

$EventName = [PSCustomObject]@{
    ButtonEvent = "ButtonEvent"
    Presence = "Presence"
}

Register-EngineEvent -SourceIdentifier $EventName.Presence -Action {
    $Event.MessageData.ModulesToImport | % {import-module $_ -Force}
    $manager = [GroupEvent.GroupManager]::new()
    New-ConbeeSessionUsingVault -hostname $Event.MessageData.Hostname
    # Write-Host "Received presence event for sensor: $($Event.MessageData | ConvertTo-Json -Depth 3)"
}

Register-EngineEvent -SourceIdentifier $EventName.ButtonEvent -Action {
    $Event.MessageData.ModulesToImport | % {import-module $_ -Force}
    New-ConbeeSessionUsingVault -hostname $Event.MessageData.Hostname
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
                Write-Information "No presence sensors associated with group $($Group.name). Button press authoritative. No state locking required."
                if ($Group.state.any_on) {
                    $LightGroupState.Bri = $null
                    $LightGroupState.On = $false
                } else {
                    $LightGroupState.On = $true
                }
                $LightGroupState | Set-LightGroupState
            } else {
                $manager = [GroupEvent.GroupManager]::new()
                $buttonState = [int]$Event.MessageData.sensorEvent.state.buttonevent
                Write-Information "Button event: $buttonState"
                $ButtonOverride = $manager.GetPowerEventOffset($buttonState)
                if (!$ButtonOverride) {
                    Write-Error "Unknown button event state: $buttonState. I can offer you nothing."
                } else {
                    if (!$manager.GetGroupLock($Group.Id)) {
                        # We are wanting to lock a light on
                        Write-Information "Locking group: $($Group.Name) on for + $($ButtonOverride.Offset)"
                        $manager.NewGroupLock(
                            [GroupEvent.GroupLockDTOWithOffset]::new([int]$Group.Id,$Group.Name,[int]$ButtonOverride.Name,[GroupEvent.PowerState]::On,$ButtonOverride)
                        )
                        $LightGroupState | Set-LightGroupState
                        if ($Group.state.any_on) {  # Old value prior to button press.
                            # Lights were on prior, so we should acknowledge that a lock has been set.
                            $LightGroupState | Set-LightAcknowledge -OnOffOnly:(!$Group.SupportsBrightness)
                        }
                    } else {
                        $IgnoreDaylightSetting = Test-AnySensorProperty -Sensors ($Event.MessageData.TriggerSensors | Where-Object { $TriggerGroup -in $_.TriggerGroup }) -Predicate { $_.IgnoreDaylight }
                        $manager.RemoveGroupLock($Group.Id)
                        Write-Information "Group $($Group.name) unlocked"
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
                    }
                }
            }
        }
    }
}



start-job -name LightManager -scriptblock {
    $InformationPreference = "Continue"
    $using:ModulesToImport | % {import-module $_ -Force}
    New-ConbeeSessionUsingVault -hostname $using:Hostname
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
                    OnOffOnlyGroups        = $using:OnOffOnlyGroups
                    ModulesToImport        = $using:ModulesToImport
                    Hostname               = $using:HostName
                    MaximumLightBrightness = $using:MaximumLightBrightness
                }
                # We care about buttonevents or presence updates, generic state changed events can be dropped to the floor
                $EventType = if ($sensorEvent.state.ButtonEvent) { $using:EventName.ButtonEvent } elseif ($sensorEvent.state.Presence) { $using:EventName.Presence } else { $null }
                if ($EventType) {
                    New-Event -SourceIdentifier $EventType -MessageData $EventData 
                }
            }    
        }      
    } finally {
        $ws | Close-WsConnection
    }
}
