# Third party MS
Import-Module Microsoft.PowerShell.SecretManagement
Import-Module Microsoft.PowerShell.SecretStore

$script:ConbeeVaultName = "ConbeeVault-Client"
$script:DefaultConbeeApiSecretName = "ConbeeApiToken"
$script:SensorsToIgnoreXMLPath = "$($env:HOME)/SensorsToIgnore.clixml"

## Secret vault fun
# https://learn.microsoft.com/en-us/powershell/utility-modules/secretmanagement/get-started/using-secretstore?view=ps-modules

## Vault functions start
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
## Vault functions End

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

Function New-ConbeeApiCall {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Method,
        [Parameter(Mandatory)]
        [string]$Endpoint,
        [PSCustomObject]$Data
    )
    $params = @{
        Uri = "$($script:BaseUri)/api/$($script:Token | ConvertFrom-SecureString -AsPlainText)/$endpoint/"
        Method = $method
        Headers = @{Accept = "application/json"}
    }
    if ($data) {
        # Strip out any empty strings or null values from the data object before converting and sending to the API.
        $x = [PSCustomObject]@{}
        $data.PSObject.Properties | Where-Object { $null -ne $_.Value -and $_.Value -ne "" } | ForEach-Object { $x | Add-Member -Type NoteProperty -Name $_.Name -Value $_.Value }
        $jsonData = $x | ConvertTo-Json
        $params.Add("Body", $jsonData)
        $params.Headers.Add("Content-Type", "application/json")
    }

    Invoke-RestMethod @params
}

Function Export-SensorsToIgnore {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [object]$Sensors
    )
    $Sensors | Export-Clixml -Path $script:SensorsToIgnoreXMLPath -Force
}

Function Import-SensorsToIgnore {
    Import-Clixml -Path $script:SensorsToIgnoreXMLPath
}

Function Get-SensorsFromProperties {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [object]$Sensors
    )
    process {
        $Sensors | Get-Member -MemberType NoteProperty
    }
}

Function Add-ApiIdToSensors {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [object]$Sensors
    )
    process {
        foreach ($sensor in $Sensors.PSObject.Properties) {
            $sensor.Value | Add-Member -Type NoteProperty -Name ApiId -Value $sensor.Name -Force
        }
        $Sensors
    }
}

Filter Get-SensorsByUniqueID {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]$Sensors,
        [Parameter(Mandatory)]
        [object]$SensorToCheck
    )
    process {
        $Sensors | Get-SensorsFromProperties | Where-Object { $Sensors.($_.Name).UniqueID -eq $SensorToCheck.UniqueID }
    }
}

Filter Remove-SensorsByUniqueID {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]$Sensors,
        [Parameter(Mandatory)]
        [object]$SensorToFilter
    )
    begin {
        $NewSensorObject = [PSCustomObject]@{}
    }
    process {
        $Sensors | Get-SensorsFromProperties | Where-Object { $Sensors.($_.Name).UniqueID -ne $SensorToFilter.UniqueID } | ForEach-Object { $NewSensorObject |Add-Member -Type NoteProperty -Name $_.Name -Value $sensors.($_.Name) }
        $NewSensorObject
    }
}

Function Add-SensorToIgnore {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [object[]]$Sensors
    )
    begin {
        $sensorsToIgnoreObject = Import-SensorsToIgnore
        $nextVal = [int]($sensorsToIgnoreObject | Get-SensorsFromProperties | Sort-Object { [int]$_.Name } -Descending | Select-Object -First 1 -ExpandProperty Name) + 1
        $NewExportRequired = $False
    }
    process {
        foreach ($Sensor in $Sensors) {
            if (-not [bool](Get-SensorsByUniqueID -Sensors $sensorsToIgnoreObject -SensorToCheck $Sensor)) {
                $sensorsToIgnoreObject | Add-Member -Type NoteProperty -Name $nextVal -Value $Sensor | out-null
                $nextVal += 1
                $NewExportRequired = $True
            }
        }
    }
    end {
        if ($NewExportRequired) {
            Export-SensorsToIgnore $sensorsToIgnoreObject | out-null
        }
        $sensorsToIgnoreObject
    }
}

Function Remove-SensorFromIgnore {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [object[]]$Sensors
    )
    begin {
        $sensorsToIgnoreObject = Import-SensorsToIgnore
    }
    process {
        foreach ($Sensor in $Sensors) {
            $sensorsToIgnoreObject = Remove-SensorsByUniqueID $sensorsToIgnoreObject $Sensor
        }
    }
    end {
        Export-SensorsToIgnore $sensorsToIgnoreObject | out-null
        $sensorsToIgnoreObject
    }
}

Function Format-ZBDevices {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [object]$ZBDevices
    )
    process {
        $ZBDevices | Get-SensorsFromProperties | ForEach-Object { $ZBDevices.($_.Name) }
    }
}

Filter Set-SensorFilter {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [object]$Sensors
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

# Get-AllSensorsRaw | Set-SensorFilter
Function Get-AllSensorsRaw {
    # Ok, this isn't really _raw_ anymore. I'm adding the ID of the sensor to its returned data for an easy life.
    New-ConbeeApiCall -Method GET -Endpoint "sensors" | Add-ApiIdToSensors
}

$SensorTypes = [pscustomobject]@{
    Humidity = "ZHAHumidity"
    Temperature = "ZHATemperature"
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
        [PSObject[]]$Sensors
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

Function Rename-Sensor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSObject]$Sensor,
        [Parameter(Mandatory)]
        [string]$NewName
    )
    # name has to be lower case as the API is case sensitive, fantastic.
    New-ConbeeApiCall -Method PUT -Endpoint "sensors/$($Sensor.ApiId)" -Data ([PSCustomObject]@{name = $NewName})
}
