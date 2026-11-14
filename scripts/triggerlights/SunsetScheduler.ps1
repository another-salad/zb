# Run me in a cron to configure the group lock schedules triggered via sunset

param(
    [Parameter(Mandatory)][ValidateScript({(test-path $_ -PathType Leaf) -and (split-path $_ -Leaf).EndsWith('.clixml')})]$ConfigClixml,
    [Parameter(Mandatory)][ValidateScript({(test-path $_ -PathType Leaf) -and (split-path $_ -Leaf).EndsWith('.clixml')})]$GroupClixml  # New-SunsetTimerConfig in setup 
)

$Config = Import-Clixml -Path $ConfigClixml
$GroupToSchedule = Import-clixml -Path $GroupClixml

$Config.ModulesToImport | % {import-module $_ -Force}

New-ConbeeSessionUsingVault -hostname $Config.HostName | Out-Null
$manager = [GroupEvent.GroupManager]::new()

$GroupToSchedule | % {
    $TriggerTime = [timeonly]((get-daylightSensors -IgnoreFilter | select -ExpandProperty state | select -ExpandProperty sunset).ToUniversalTime() + ($_.StartOffset)).ToLongTimeString()
    # Deal with some of the deserialized type woe due to clixml, its _fine_.
    $dto = [GroupEvent.GroupLockSchedulerDto]::new([int]$_.Group.id,$_.Group.Name,([GroupEvent.PowerState]$_.PowerState), $TriggerTime,[timeonly]($_.ReleasetimeUTC).ToString())
    if (-not $manager.GetGroupLockSchedule($_.Group.id)) {
        $manager.NewGroupLockSchedule($dto)
    } else {
        $manager.SetGroupLockSchedule($dto)
    }
}
