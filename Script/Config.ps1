#######################################
#### AppImort and Deploy settings #####
#######################################
<#
    JSON was chosen to store settings because of the code needed to save and restore the configuration.
#>

function Read-ConfigurationData {
    param(
        [switch]$SkipUserConfig
    )
    $UserPath = "$($env:APPDATA)\PLS\AppImporter\config.json"
    if ($SkipUserConfig.IsPresent -or (-not (Test-Path -ErrorAction SilentlyContinue -Path $UserPath))) {
        $Path = "$PSScriptRoot\config.json"
    }
    else {
        $Path = $UserPath
    }
    Get-Content -ErrorAction Stop -Path $Path -Raw | ConvertFrom-Json
}

function Save-ConfigurationData {
    
    $Parameters = @{
        Encoding = 'UTF8'
        ErrorAction = 'Stop'
        FilePath = "$($env:APPDATA)\PLS\AppImporter\config.json"
        Force = $true
    }
    
    if (-not (Test-Path -Path $Parameters.FilePath)) {
        New-Item -ErrorAction Ignore -ItemType Container -Path (Split-Path -Path $Parameters.FilePath -Parent) | Out-Null
    }

    $Config | ConvertTo-Json -Depth 10 | Out-File @Parameters
}

function Global:Set-Config {
    param(
        [ValidateNotNullOrEmpty()]
        [string]$key,
        [ValidateNotNullOrEmpty()]
        [string]$value
    )
    If (($Config | Get-Member -Name $key)) {
        $Config."$key" = $value
    }
    else {
        $Config | Add-Member $key $value
    }
    Save-ConfigurationData
}

function Global:Get-Config {
    param(
        [ValidateNotNullOrEmpty()]
        [string]$key
    )
    # Check if config contains the key
    If (-not ($Config | Get-Member -Name $key)) {
        # The config did not contain the key, check if the deployed config contains it
        $DeployedConfig = Read-ConfigurationData -SkipUserConfig
        If (-not ($DeployedConfig | Get-Member -Name $key)) {
            Throw "Config $key not found in user configuration or the deployed configuration, check your configuration files."
        }
        else {
            # We found the key in the deployed config, set it in the user config
            Global:Set-Config -key $key -value $DeployedConfig.$key
            return $DeployedConfig.$key
        }
    }
    $Config.$key
}

$Config = Read-ConfigurationData