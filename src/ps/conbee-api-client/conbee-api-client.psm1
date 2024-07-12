# Third party MS
Import-Module Microsoft.PowerShell.SecretManagement
Import-Module Microsoft.PowerShell.SecretStore

$script:ConbeeVaultName = "ConbeeVault-Client"
$script:DefaultConbeeApiSecretName = "ConbeeApiToken"
$script:NodesToIgnoreXMLPath = "$PSScriptRoot/nodes-to-ignore.xml"

## Secret vault fun
# https://learn.microsoft.com/en-us/powershell/utility-modules/secretmanagement/get-started/using-secretstore?view=ps-modules


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

class ConbeeConfig {
    [string]$Hostname = "127.0.0.1"
    [securestring]$Token
    [bool]$Ssl = $false
}

Function New-ConbeeConfig {
    [ConbeeConfig]::new()
}

function New-ConbeeSession {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [ConbeeConfig]$ConbeeConfig
    )
    $script:BaseUri = "$(if ($ConbeeConfig.Ssl) {'https'} else {'http'})://$($ConbeeConfig.Hostname)"
    $script:Token = if (-not $ConbeeConfig.Token) {Get-ApiTokenFromVault} else {$ConbeeConfig.Token}
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
    # TODO: TEST OUT THE BELOW
    # if ($data) {
    #     # Strip out any empty strings or null values from the data object before converting and sending to the API.
    #     $x = [PSCustomObject]@{}
    #     $data.PSObject.Properties | Where-Object { $null -ne $_.Value -and $_.Value -ne "" } | ForEach-Object { $x | Add-Member -Type NoteProperty -Name $_.Name -Value $_.Value }
    #     $jsonData = $x | ConvertTo-Json
    #     $params.Add("Body", $jsonData)
    #     $params.Headers.Add("Content-Type", "application/json")
    # }

    Invoke-RestMethod @params
}

Function New-NodeToIgnoreXML {
    [xml]$xml = “<nodes></nodes>”
    $xml.Save($script:NodesToIgnoreXMLPath)
}

Function Update-NodeToIgnoreXML {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [object]$Sensor
    )
    begin {
        if (-not (Test-Path -Path $script:NodesToIgnoreXMLPath)) {
            New-NodeToIgnoreXML
        }
        $xml = [xml](Get-Content $script:NodesToIgnoreXMLPath)
    }
    process {
        [xml]$nodeXml = [System.Management.Automation.PSSerializer]::Serialize(($Sensor | Select-Object name, uniqueid, manufacturername, modelid, etag))
        $nodes = $xml.DocumentElement
        $nodes.AppendChild($xml.ImportNode($nodeXml.Objs.obj, $true)) | out-null
    }
    end {
        $xml.Save($script:NodesToIgnoreXMLPath)
    }
}

Function Set-SensorFilter {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [object]$Sensors
    )
    begin {
        $xml = [xml](Get-Content $script:NodesToIgnoreXMLPath)
    }
    process {
        # NOTE(Another-Salad): There must be a better way of doing the below, but this is all my brain can seemingly do right now...
        $Sensors | get-member -MemberType NoteProperty | ForEach-Object { $Sensors.($_.Name) } | Where-object { $_.uniqueid -notin $xml.Nodes.Obj.MS.S."#text" }
    }
}

# Get-AllSensors | Set-SensorFilter
Function Get-AllSensors {
    New-ConbeeApiCall -Method GET -Endpoint "sensors"
}
