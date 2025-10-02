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

Function Add-ApiIdToSensors {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSCustomObject]$Sensors
    )
    process {
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
Function ConvertTo-FlatSensors {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSCustomObject]$Sensors
    )
    process {
        if ($Sensors.PSObject.Properties.Name -contains "uniqueid") {
            # Already flattened, use as-is
            $Sensors
        } else {
            $Sensors | ConvertTo-FlatObject
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
        $sensors | ConvertTo-FlatSensors | Add-SensorToClixml -SensorXml (Import-SensorsToIgnore) | Export-SensorsToIgnore
    }
}

Function Add-SensorToTriggers {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSCustomObject]$Sensors
    )
    process {
        $Sensors | ConvertTo-FlatSensors | ForEach-Object {
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
        $Sensors | ConvertTo-FlatSensors | Foreach-Object {$SensorXml = Remove-SensorsByUniqueID $SensorXml $_}
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
    New-ConbeeApiCall -Method GET -Endpoint "sensors" | Add-ApiIdToSensors
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
class LightGroupState {
    # Other than the Group, these properties are ingested into the API if they are not $null.
    [Parameter(Mandatory)]
    [pscustomobject]$Group
    [bool]$On
    [Nullable[int]]$Bri
    [Nullable[int]]$Hue
    [Nullable[int]]$Sat
    [Nullable[int]]$Transitiontime

    LightGroupState($Group, $On, $Bri, $Hue, $sat, $transitiontime) {
        $this.Group = $Group
        $this.On = $On
        if (!$On -and $bri) {
            Write-Warning "Invalid state, Conbee API will ignore on/off state if a Brightness value (Bri) is provided. Ignoring brightness value."
            $this.Bri = $null
        } else {
            $this.Bri = Test-NullableParamWithinRange $Bri -Min 0 -Max 254
        }
        $this.Hue = Test-NullableParamWithinRange $Hue -Min 0 -Max 65535
        $this.Sat = Test-NullableParamWithinRange $Sat -Min 0 -Max 254
        $this.Transitiontime = Test-NullableParamWithinRange $Transitiontime -Min 1 -Max 10
    }
}

# "hue": 0,
# "on": false,
# "sat": 128,
Function New-LightGroupState {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateScript({$_.type -eq "LightGroup"})]
        [pscustomobject]$Group,
        # If you are providing a brightness value (i.e. Bri this is ignored by the Conbee API)
        [switch]$Off,
        # If these aren't explicitly defaulted to $null they'll be a 0, which is a valid value for the API.
        # $null means "don't set this value".
        [Nullable[int]]$Brightness     = $null,
        [Nullable[int]]$Hue            = $null,
        [Nullable[int]]$Saturation     = $null,
        [Nullable[int]]$Transitiontime = $null
    )
    [LightGroupState]::new($Group, (!$Off), $Brightness, $Hue, $Saturation, $Transitiontime)
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
# $conf | Set-GroupState 
Function Set-GroupState {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        $GroupState  # Keeping this generic as we might have other settable groups in future.
    )
    process {
        $data = @{}
        Foreach ($prop in $GroupState.PSObject.Properties) {
            if ($prop.Name -ne "Group" -and $null -ne $prop.Value) {
                $data.Add($prop.Name.ToLower(), $prop.Value)
            }
        }
        New-ConbeeApiCall -Method PUT -Endpoint "groups/$($GroupState.Group.id)/action" -Data $data
    }
}
#endregion

#region LightGroup Helpers
Function Set-DimLightCycle {
    # Useful if you want to acknowledge something like a button event when the lights are on.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [LightGroupState]$GroupState,
        [int]$FlickerCount = 1
    )
    process {
        for ($i = 0; $i -lt $FlickerCount; $i++) {
            $GroupState.Bri = $GroupState.Bri / 2
            $GroupState | Set-GroupState
            sleep ([int]$GroupState.Transitiontime)
            $GroupState.Bri = $GroupState.Bri * 2
            $GroupState | Set-GroupState
            sleep ([int]$GroupState.Transitiontime)
        }
    }
}

#endregion

#region WebSocket helpers
Function New-WsConnection {
    [CmdletBinding()]
    param(
        # Conbee API defaults to port 443 for ws connections, but can be configured to a different port.
        [int]$Port = 443
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
