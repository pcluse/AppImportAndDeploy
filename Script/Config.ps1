#######################################
#### AppImort and Deploy settings #####
#######################################
<#
    JSON was chosen to store settings because of the code needed to save and restore the configuration.
#>

function Read-ConfigurationData {
    $UserPath = "$($env:APPDATA)\PLS\AppImporter\config.json"
    if (-not (Test-Path -ErrorAction SilentlyContinue -Path $UserPath)) {
        $Path = "$PSScriptRoot\config.json"
    }
    else {
        $Path = $UserPath
    }
    Get-Content -ErrorAction Stop -Path $Path -Raw | ConvertFrom-Json
}

function Save-ConfigurationData {
    param(
        [Parameter(Mandatory=$true,
                   ValueFromPipeline=$true)]
        $ConfigurationData
    )
    
    $Parameters = @{
        Encoding = 'UTF8'
        ErrorAction = 'Stop'
        FilePath = "$($env:APPDATA)\PLS\AppImporter\config.json"
        Force = $true
    }

    $Parameters
    
    if (-not (Test-Path -Path $Parameters.FilePath)) {
        New-Item -ItemType Container -Path (Split-Path -Path $Parameters.FilePath -Parent) | Out-Null
    }

<<<<<<< HEAD
    $ConfigurationData | ConvertTo-Json -Depth 10 | Out-File @Parameters
=======
    ## Should program just do a dry-run and not really import the applications
    ## Used only for testing purposes
    DryRun = $false

    ## Should info on imported applications be posted on teams
    TeamsPostImport = $true
    TeamsChannelName = "Name of teams channel"
    TeamsChannelUrl = 'https://outlook.office.com/webhook/..........and more'
    
>>>>>>> origin/master
}

function Global:Get-Config {
    param(
        [ValidateNotNullOrEmpty()]
        [string]$key
    )
    # Write-Debug -Message "$key exist $($Config.ContainsKey($key))"
    If (-not ($Config | Get-Member -Name $key)) {
        Throw "Config $key not found in Config.ps1, check your configuration"
    }
    $Config.$key
}