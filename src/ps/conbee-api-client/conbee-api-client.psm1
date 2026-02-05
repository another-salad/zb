$script:ConbeeVaultName = "ConbeeVault-Client"
$script:DefaultConbeeApiSecretName = "ConbeeApiToken"
$script:SensorsToIgnoreXMLPath = "$($env:HOME)/SensorsToIgnore.clixml"
$script:TriggerSensorsXMLPath = "$($env:HOME)/TriggerSensors.clixml"

## Secret vault fun
# https://learn.microsoft.com/en-us/powershell/utility-modules/secretmanagement/get-started/using-secretstore?view=ps-modules

#region SecretVaultFunctions
Function Set-NonInteractiveConbeeVault {
    [CmdletBinding()]
    param (
        [string]$vaultName = $script:ConbeeVaultName
    )
    # You can't set some vaults to be non-interactive and some to be interactive. It's all or nothing.
    # If you want an interactive vault, simply run, set-conbeevault.
    # Even in this non-interactive mode, you'll need to set an initial password, once the config is complete you won't be
    # prompted for this again.
    Write-Warning "This will set ALL VAULTS to non-interactive, no authentication mode. Think about this wisely."
    Set-SecretStoreConfiguration -Interaction None -Authentication None -Scope CurrentUser
    Set-Conbeevault -vaultName $vaultName
}

Function Set-Conbeevault {
    [CmdletBinding()]
    param (
        [string]$vaultName = $script:ConbeeVaultName
    )
    Register-SecretVault -Name $vaultName -ModuleName Microsoft.PowerShell.SecretStore
    Get-SecretVault -Name $vaultName
}

Function Set-ApiTokenToVault {
    [CmdletBinding()]
    param (
        [string]$secretName = $script:DefaultConbeeApiSecretName,
        [string]$vaultName = $script:ConbeeVaultName
    )
    $apiToken = Read-Host -Prompt "Enter the API token for the Conbee API" -AsSecureString
    Set-Secret -Name $secretName -Secret $apiToken -Vault $vaultName
}

Function Get-ApiTokenFromVault {
    [CmdletBinding()]
    param (
        [string]$secretName = $script:DefaultConbeeApiSecretName,
        [string]$vaultName = $script:ConbeeVaultName
    )
    Get-Secret -Name $secretName -Vault $vaultName
}
#endregion

#region Generic Functions
Function ConvertTo-FlatObject {
    # I must admit, I hate approved verbs.
    # In short, this returns all the property values within the parent PsCustomObject.
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        $PsObj
    )
    process {
        $PsObj | ForEach-Object { $r = $_.PSObject.Properties.Value; $r}
    }
}

Function Test-NullableParamWithinRange {
    [CmdletBinding()]
    param (
        [Nullable[int]]$Value,
        [Parameter(Mandatory)]
        [int]$Min,
        [Parameter(Mandatory)]
        [int]$Max
    )
    # Allows nullable params to be range validated.
    if ($null -ne $Value -and ($Value -lt $Min -or $Value -gt $Max)) {
        Write-Error "Value must be between $Min and $Max"
    } else {
        $Value
    }
}
#endregion

#region ConbeeSession
class ConbeeConfig {
    [string]$Hostname = "127.0.0.1"
    [securestring]$Token
    [bool]$Ssl = $false
}

Function New-ConbeeConfig {
    [ConbeeConfig]::new()
}

Function New-ConbeeSession {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [ConbeeConfig]$ConbeeConfig
    )
    $script:ConbeeHostName = $ConbeeConfig.Hostname
    $script:BaseUri = "$(if ($ConbeeConfig.Ssl) {'https'} else {'http'})://$($ConbeeConfig.Hostname)"
    $script:Token = if (-not $ConbeeConfig.Token) {Get-ApiTokenFromVault} else {$ConbeeConfig.Token}
}

Function New-ConbeeSessionUsingVault {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$HostName
    )
    $conf = New-ConbeeConfig
    $conf.Token = Get-ApiTokenFromVault
    $conf.Hostname = $HostName
    $conf | New-ConbeeSession
    $conf
}
#endregion

#region CoreApiWrappers
Function New-ConbeeApiCall {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Method,
        [Parameter(Mandatory)]
        [string]$Endpoint,
        [hashtable]$Data
    )
    $params = @{
        Uri = "$($script:BaseUri)/api/$($script:Token | ConvertFrom-SecureString -AsPlainText)/$endpoint/"
        Method = $method
        Headers = @{Accept = "application/json"}
    }
    if ($Data) {
        $params.Add("Body", ($Data | ConvertTo-Json -ErrorAction Stop -Depth 10))
        $params.Headers.Add("Content-Type", "application/json")
    }

    Invoke-RestMethod @params
}

Function Add-ApiIdToSensor {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSCustomObject]$Sensors
    )
    end {
        foreach ($sensor in $Sensors.PSObject.Properties) {
            $sensor.Value | Add-Member -Type NoteProperty -Name ApiId -Value $sensor.Name -Force
        }
        $Sensors
    }
}
#endregion
#region ZHASwitch Specific Config
Function Add-Any_OnTargetValue {
    [CmdletBinding()]
    # Specific to ZHASwitches and a little odd to hold. This will allow you to set a ZHASwitch to either turn a group
    # on or off when a button is pressed.
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSCustomObject]$Sensors,
        [bool]$Any_OnTargetValue = $True  # Default to true, i.e. set the Group to 'on'
    )
    process {
        $Sensors | Add-Member -Type NoteProperty -Name Any_OnTargetValue  -Value $Any_OnTargetValue -Force
    }
    end {
        $Sensors
    }
}

#endregion

#region ConbeeConfig
Function Get-ConbeeConfig {
    New-ConbeeApiCall -Method GET -Endpoint "config"
}
#endregion

#region SensorManagement
Function ConvertTo-FlatSensor {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSCustomObject]$Sensor
    )
    process {
        $_ | ForEach-Object {
            if ($_.PSObject.Properties.Name -contains "uniqueid") {
                # Already flattened, use as-is
                $_
            } else {
                $_ | ConvertTo-FlatObject
            }
        }
    }
}

Function Export-SensorsToIgnore {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSCustomObject]$Sensors
    )
    $Sensors | Export-Clixml -Path $script:SensorsToIgnoreXMLPath -Force
}

Function Import-SensorsToIgnore {
    Import-Clixml -Path $script:SensorsToIgnoreXMLPath -ErrorAction SilentlyContinue
}

Function Import-TriggerSensors {
    Import-Clixml -Path $script:TriggerSensorsXMLPath -ErrorAction SilentlyContinue
}

Function Export-TriggerSensors {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSCustomObject]$Sensors
    )
    $Sensors | Export-Clixml -Path $script:TriggerSensorsXMLPath -Force
}

Function Get-SensorsFromProperties {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSCustomObject]$Sensors
    )
    process {
        $Sensors | Get-Member -MemberType NoteProperty
    }
}

Function New-SensorTriggerConfig {
    [pscustomobject]@{
        TriggerGroup = $null
        IgnoreDaylight = $false
    }
}

Function Add-TriggerConfigToSensors {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSCustomObject]$Sensors,
        [Parameter(Mandatory)]
        [pscustomobject]$TriggerConfig
    )
    process {
        $Sensors | ForEach-Object {
            $sensor = $_
            $TriggerConfig.PSObject.Properties | ForEach-Object {
                $sensor | Add-Member -Type NoteProperty -Name $_.Name -Value $_.Value -Force
            }
            $sensor
        }
    }
}

Function Add-SensorToClixml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSCustomObject]$Sensors,
        [PSCustomObject]$SensorXml
    )
    begin {
        if ($SensorXml -eq $null) {
            $SensorXml = [PSCustomObject]@{}
        }
        $nextVal = [int]($SensorXml | Get-SensorsFromProperties | Sort-Object { [int]$_.Name } -Descending | Select-Object -First 1 -ExpandProperty Name) + 1
    }
    process {
        foreach ($Sensor in $Sensors) {
            if (-not [bool](Get-SensorsByUniqueID -Sensors $SensorXml -SensorToCheck $Sensor)) {
                $SensorXml | Add-Member -Type NoteProperty -Name $nextVal -Value $Sensor | out-null
                $nextVal += 1
            } else {
                Write-Warning "Sensor with UniqueID $($Sensor.UniqueID) already exists, skipping add. Use Remove-SensorFromTriggers to remove it first if you want to re-add it."
            }
        }
    }
    end {
        $SensorXml
    }

}

Function Add-SensorToIgnore {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSCustomObject]$Sensors
    )
    process {
        $sensors | ConvertTo-FlatSensor | Add-SensorToClixml -SensorXml (Import-SensorsToIgnore) | Export-SensorsToIgnore
    }
}

Function Add-SensorToTriggers {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSCustomObject]$Sensors
    )
    process {
        $Sensors | ConvertTo-FlatSensor | ForEach-Object {
            if (-not $_.TriggerGroup) {
                Write-Warning "Add TriggerGroup to: $_ via Add-TriggerGroupToSensor"; return
            }
            $_ | Add-SensorToClixml -SensorXml (Import-TriggerSensors) | Export-TriggerSensors
        }
    }
}

Function Remove-SensorFromClixml {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSCustomObject]$Sensors,
        [PSCustomObject]$SensorXml
    )
    process {
        $Sensors | ConvertTo-FlatSensor | Foreach-Object {$SensorXml = Remove-SensorsByUniqueID $SensorXml $_}
    }
    end {
        $SensorXml
    }
}

Function Remove-SensorFromIgnore {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSCustomObject]$Sensors
    )
    process {
        $sensors | Remove-SensorFromClixml -SensorXml (Import-SensorsToIgnore) | Export-SensorsToIgnore
    }
}

Function Remove-SensorFromTriggers {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSCustomObject]$Sensors
    )
    process {
        $sensors | Remove-SensorFromClixml -SensorXml (Import-TriggerSensors) | Export-TriggerSensors
    }
}
#endregion

#region Filters/Formatters
Filter Get-SensorsByUniqueID {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [PSCustomObject]$Sensors,
        [Parameter(Mandatory)]
        [PSCustomObject]$SensorToCheck
    )
    process {
        $Sensors | Get-SensorsFromProperties | Where-Object { $Sensors.($_.Name).UniqueID -eq $SensorToCheck.UniqueID }
    }
}

Filter Remove-SensorsByUniqueID {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [PSCustomObject]$Sensors,
        [Parameter(Mandatory)]
        [PSCustomObject]$SensorToFilter
    )
    begin {
        $NewSensorObject = [PSCustomObject]@{}
    }
    process {
        $Sensors | Get-SensorsFromProperties | Where-Object { $Sensors.($_.Name).UniqueID -ne $SensorToFilter.UniqueID } | ForEach-Object { $NewSensorObject |Add-Member -Type NoteProperty -Name $_.Name -Value $sensors.($_.Name) }
        $NewSensorObject
    }
}

Function Format-ZBDevices {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSCustomObject]$ZBDevices
    )
    process {
        $ZBDevices | Get-SensorsFromProperties | ForEach-Object { $ZBDevices.($_.Name) }
    }
}

Filter Set-SensorFilter {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSCustomObject]$Sensors
    )
    begin {
        $SensorstoIgnore = Import-SensorsToIgnore
        $IdsToIgnore = $SensorstoIgnore | Get-SensorsFromProperties | ForEach-Object {$SensorstoIgnore.($_.Name).UniqueID}  # Note, think about filter Get-SensorsByUniqueID
    }
    process {
        # NOTE(Another-Salad): There is still likely a better way of doing this but here we are.
        $Sensors | Format-ZBDevices | Where-object {$_.uniqueid -notin $IdsToIgnore}
    }
}

Function Test-AnySensorProperty {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [PSCustomObject]$Sensors,
        [Parameter(Mandatory)]
        [ScriptBlock]$Predicate
    )
    [bool]($Sensors | Where-Object $Predicate | Select-Object -First 1)
}
#endregion

#region SensorFunctions
$SensorTypes = [pscustomobject]@{
    Humidity = "ZHAHumidity"
    Temperature = "ZHATemperature"
    Presence = "ZHAPresence"
    Power = "ZHAPower"
    Consumption = "ZHAConsumption"
    LightLevel = "ZHALightLevel"
    Daylight = "Daylight"
    Switch = "ZHASwitch"
}

# Get-AllSensorsRaw | Set-SensorFilter
Function Get-AllSensorsRaw {
    # Ok, this isn't really _raw_ anymore. I'm adding the ID of the sensor to its returned data for an easy life.
    New-ConbeeApiCall -Method GET -Endpoint "sensors" | Add-ApiIdToSensor
}

Function Get-FitleredSensorData {
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline, Mandatory)]
        [string]$SensorType
    )
    Get-AllSensorsRaw | Set-SensorFilter | Where-Object { $_.type -eq $SensorType }
}

Function Update-ZHAStateValueToFloat {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline, Mandatory)]
        [PSCustomObject]$Sensors
    )
    process {
        $Sensors | ForEach-Object {$_.state.PSObject.Properties | ForEach-Object {if ($_.Name -in @("temperature", "humidity")) {$_.Value = [math]::round($_.Value / 100, 2)}}}
        $Sensors
    }
}

Function Get-TemperatureSensors {
    $SensorTypes.Temperature | Get-FitleredSensorData | Update-ZHAStateValueToFloat
}

Function Get-HumiditySensors {
    $SensorTypes.Humidity| Get-FitleredSensorData | Update-ZHAStateValueToFloat
}

Function Get-PresenceSensors {
    $SensorTypes.Presence | Get-FitleredSensorData
}

Function Get-PowerSensors {
    $SensorTypes.Power | Get-FitleredSensorData
}

Function Get-ConsumptionSensors {
    $SensorTypes.Consumption | Get-FitleredSensorData
}

Function Get-LightLevelSensors {
    $SensorTypes.LightLevel | Get-FitleredSensorData
}

Function Get-SwitchSensors {
    $SensorTypes.Switch | Get-FitleredSensorData
}

Function Get-DaylightSensors {
    # If you are like me, you have likely ignored the default daylight sensor in the DeConz API.
    # I found this to mostly be noise, until now ofc.
    [CmdletBinding()]
    param(
        [switch]$IgnoreFilter
    )
    if ($IgnoreFilter) {
        Get-AllSensorsRaw | Format-ZBDevices | Where-Object { $_.type -eq $SensorTypes.Daylight }
    } else {
        $SensorTypes.Daylight | Get-FitleredSensorData
    }
}

Function Rename-Sensor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Sensor,
        [Parameter(Mandatory)]
        [string]$NewName
    )
    # name has to be lower case as the API is case sensitive, fantastic.
    New-ConbeeApiCall -Method PUT -Endpoint "sensors/$($Sensor.ApiId)" -Data @{name = $NewName}
}

# Get-LightLevelSensors | Update-SensorConfig -Config @{tholddark = 10000}  # Default is 12000
Function Update-SensorConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory,ValueFromPipeline)]
        [PSCustomObject]$Sensor,
        [Parameter(Mandatory)]
        [hashtable]$Config
    )
    process {
        New-ConbeeApiCall -Method PUT -Endpoint "sensors/$($Sensor.ApiId)/config" -Data $Config
    }
}

Function Show-CurrentTemperature {
    [CmdletBinding()]
    param()
    Get-TemperatureSensors | Select-Object name, @{Name='temperature';Expression={ '{0:N2}' -f $_.state.temperature }} | Format-Table -AutoSize
}
#endregion

#region Groups
# You'll see interactions with groups which can combine many lights, plugs, etc into single entities.
# Plugs are a little interesting in the DeConz API as you cannot (at the time of writing March 2025)
# control their state (on/off) directly. However, if they are put into a group (can be a group of one)
# then you can. I foresee many interactions with single plugs abstracted via groups.

# https://dresden-elektronik.github.io/deconz-rest-doc/endpoints/groups/#set-group-state
# Example params:
# {
#   "on": true,
#   "bri": 180,
#   "hue": 43680,
#   "sat": 255,
#   "transitiontime": 10
# }

# I've seen some oddities with the deconz api I need to investigate futher. Setting the brightness to 0 has inconsistent behaviour.
# I have seen it 'turn off', but I have also seen 0 set it to a very low brightness.
# I've also seen some bulbs get stuck at a certain brightness, and only an on/off toggle will reset them.
# OK, I either dreamt of a world where setting bri to 0 would turn off the light, or there has been a change in the API.
# https://dresden-elektronik.github.io/deconz-rest-doc/endpoints/groups/#set-group-state
# I swear this used to explain that supplying a bri value would supercede the on/off state.
# I now see two requests being sent if I supply the api with both an On and a Bri value:
# success
# -------
# @{/groups/8/action/on=True}
# @{/groups/8/action/bri=150}
# To turn off the light, I can't send a bri and an on=false, I have to just send on=false. Good.
#
Function New-LightGroupState {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateScript({$_.type -eq "LightGroup"})]  # From deconz API
        [pscustomobject]$Group,
        [switch]$Off,
        # If these aren't explicitly defaulted to $null they'll be a 0, which is a valid value for the API.
        # $null means "don't set this value".
        [Nullable[int]]$Brightness     = $null,
        [Nullable[int]]$Hue            = $null,
        [Nullable[int]]$Saturation     = $null,
        [Nullable[int]]$Transitiontime = $null
    )
    Test-NullableParamWithinRange $Brightness -Min 0 -Max 255 | out-null
    Test-NullableParamWithinRange $Hue -Min 0 -Max 65535 | out-null
    Test-NullableParamWithinRange $Saturation -Min 0 -Max 254 | out-null
    Test-NullableParamWithinRange $Transitiontime -Min 1 -Max 10 | out-null
    [PSCustomObject]@{
        PsTypeName     = 'LightGroupState'
        Group          = $Group
        Bri            = $Brightness
        On             = !$Off
        Hue            = $Hue
        Sat            = $Saturation
        Transitiontime = $Transitiontime
    }
}

Function Get-AllGroups {
    New-ConbeeApiCall -Method GET -Endpoint "groups"
}

Function Get-GroupByName {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Name
    )
    Get-AllGroups | ConvertTo-FlatObject | Where-Object {$_.Name -match $Name}
}

Function Get-GroupAttributes {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [pscustomobject]$Group
    )
    process {
        New-ConbeeApiCall -Method GET -Endpoint "groups/$($Group.id)"
    }
}

# $conf = Get-GroupByName -Name "Living Room" | New-LightGroupState -Bri 200
# $conf | Set-LightGroupState 
Function Set-LightGroupState {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [PsCustomobject][PsTypeName('LightGroupState')]$GroupState
    )
    process {
        $data = @{}
        Foreach ($prop in $GroupState.PSObject.Properties) {
            if ($prop.Name -ne "Group" -and $null -ne $prop.Value) {
                $data.Add($prop.Name.ToLower(), $prop.Value)
            }
        }
        New-ConbeeApiCall -Method PUT -Endpoint "groups/$($GroupState.Group.id)/action" -Data $data
        if ($GroupState.Transitiontime) {
            # item (likely a light has a transistion time which is in 1/10 seconds), wait for it to complete before returning.
            Start-Sleep -Seconds ([float]$GroupState.Transitiontime / 10)
        }
    }
}
#endregion

#region LightGroup Helpers
Function Set-LightAcknowledge {
    # Useful if you want to acknowledge something like a button event when the lights are on.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [PsCustomobject][PsTypeName('LightGroupState')]$GroupState,
        [int]$FlickerCount = 1,
        [switch]$OnOffOnly
    )
    process {
        if (-not $GroupState.Transitiontime) {
            Write-Warning "No transition time set, setting to 5 (0.5 seconds) for flicker effect unless you won't see anything."
            $GroupState.Transitiontime = 5
        }
        $originalBri = $GroupState.Bri
        for ($i = 0; $i -lt $FlickerCount; $i++) {
            if ($OnOffOnly) {
                $GroupState.Bri = $null  # Ensure brightness isn't set, as that will override on/off.
                $GroupState.On = $false
                $GroupState | Set-LightGroupState
                $GroupState.On = $true
                $GroupState | Set-LightGroupState
            } else {
                # Flicker by halving brightness, then restoring it.
                $GroupState.Bri = $GroupState.Bri / 2
                $GroupState | Set-LightGroupState
                $GroupState.Bri = $GroupState.Bri * 2
                $GroupState | Set-LightGroupState
            }
        }
        # These API calls are relatively fire and forget, I don't want to potentially spend ages changing state and
        # confirming the state is correct if these can be lossy, as I just want to room to be bright again.
        # The point of the above is to give the user some form of feedback that an action has been registered.
        # I'd prefer that to potentially look a little odd, rather than spend ages getting it perfect.
        # Lets make sure we are actually at the original brightness here though, as that will be annoying if not.
        if ($originalBri -ne ($GroupState | Get-GroupAttributes).action.bri) {
            $GroupState.Bri = $originalBri
            $GroupState | Set-LightGroupState
        }
    }
}

#endregion

#region WebSocket helpers
Function New-WsConnection {
    [CmdletBinding()]
    param(
        # Conbee API defaults to port ~443~ 80 for ws connections, but can be configured to a different port.
        # https://github.com/dresden-elektronik/deconz-rest-plugin/pull/8381 made it into release 2.32.5 and changed the
        # default port to the same as the rest api http port. I hope nobody thinks shoving a tls cert into deconz means its
        # safe to expose to the internet.
        [int]$Port = 80
    )
    Add-Type -AssemblyName System.Net.WebSockets.Client
    $uri = "ws://$($script:ConbeeHostName):$Port"
    $ws = [System.Net.WebSockets.ClientWebSocket]::new()
    $ws.ConnectAsync([Uri]$uri, [Threading.CancellationToken]::None).Wait()
    $ws
}

Function Close-WsConnection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [System.Net.WebSockets.ClientWebSocket]$ws
    )
    process {
        $ws.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, "Closing", [Threading.CancellationToken]::None).Wait()
        $ws.Dispose()
    }
}

Function Receive-WsData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [System.Net.WebSockets.ClientWebSocket]$ws
    )
    begin {
        $Buffer = [byte[]]::new(1024)
    }
    process {
        $segment = [System.ArraySegment[byte]]::new($buffer)
        $result = $ws.ReceiveAsync($segment, [Threading.CancellationToken]::None).GetAwaiter().GetResult()
        [System.Text.Encoding]::UTF8.GetString($Buffer, 0, $result.Count) | ConvertFrom-Json
    }
}
#endregion
