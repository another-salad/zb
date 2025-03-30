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
    if ($data) {
        $params.Add("Body", ($Data | ConvertTo-Json))
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

#region ConbeeConfig
Function Get-ConbeeConfig {
    New-ConbeeApiCall -Method GET -Endpoint "config"
}
#endregion

#region SensorManagement
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
        $sensors | ConvertTo-FlatObject | Add-SensorToClixml -SensorXml (Import-SensorsToIgnore) | Export-SensorsToIgnore
    }
}

Function Add-SensorToTriggers {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSCustomObject]$Sensors
    )
    process {
        $Sensors | ConvertTo-FlatObject | ForEach-Object {
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
        $sensors | ConvertTo-FlatObject | Foreach-Object {$SensorXml = Remove-SensorsByUniqueID $SensorXml $_}
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
#endregion

#region Groups
# You'll see interactions with groups which can combine many lights, plugs, etc into single entities.
# Plugs are a little interesting in the DeConz API as you cannot (at the time of writing March 2025)
# control their state (on/off) directly. However, if they are put into a group (can be a group of one)
# then you can. I foresee many interactions with single plugs abstracted via groups.

class GroupState {
    [pscustomobject]$Group
    [hashtable]$State
}

Function New-GroupState {
    [GroupState]::new()
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

# $conf = New-GroupState 
# $conf.Group = Get-GroupByName -Name "Living Room"
# $conf.state = @{on=$True}
# $conf | Set-GroupState 
Function Set-GroupState {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSCustomObject[]]$GroupState
    )
    process {
        New-ConbeeApiCall -Method PUT -Endpoint "groups/$($GroupState.Group.id)/action" -Data $GroupState.State
    }
}

# Get-GroupByName -Name "Living Room" | Set-GroupPowerState -off
Function Set-GroupPowerState {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSCustomObject[]]$Group,
        [switch]$off
    )
    begin {
        $conf = New-GroupState
        $conf.State = @{on = ($True -ne $off)}
    }
    process {
        $Group | ForEach-Object { $conf.Group = $_ ; $conf | Set-GroupState }
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
