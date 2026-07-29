param(
    # Dotnet build and pass in path to groupevent.dll
    [Parameter(Mandatory)][ValidateScript({ Test-Path $_ })]$DllPath
)

Import-module $DllPath -Force

$manager = [GroupEvent.GroupManager]::new()
$manager.NewPowerEventOffset(423, (New-TimeSpan -Hours 12)) # _darkness_ state event offset
$manager.NewPowerEventOffset(1002, (New-TimeSpan -Hours 1)) # Button short
$manager.NewPowerEventOffset(1003, (New-TimeSpan -Hours 8)) # Button long
$manager.NewPowerEventOffset(1004, (New-TimeSpan -Hours 2)) # Double Press
$manager.GetPowerEventOffset()
