# Can then be exported as clixml
Function New-TriggerConfig {
    [pscustomobject]@{
        PsTypeName = "TriggerConfig"
        HostName = ""
        MaximumLightBrightness = 255
        ModulesToImport = @()
        OnOffOnlyGroups = @()
    }
}