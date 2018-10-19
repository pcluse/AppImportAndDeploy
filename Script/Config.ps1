#######################################
#### AppImort and Deploy settings #####
#######################################

$Global:Config = @{}

## Path where applications are stored
## This should contain folders with the name of the application
## and subfolders with version numbers
$Config['AppPath'] = '\\src.pc.lu.se\file$\Applikationer'

## Default install and uninstall command line
$Config['InstallCommandline']  = 'Deploy-Application.exe -DeploymentType "Install"'
$Config['UninstallCommandline'] = 'Deploy-Application.exe -DeploymentType "Uninstall"'

## Location of log-files
$Config['LogPath'] = "$($env:LOCALAPPDATA)\Temp"
## Name of log for work progression
$Config['WorkLog'] = 'AppImport-worklog.log'
## Name of log for things todo
$Config['TODOLog'] = 'AppImport-todolog.log'

## Distribution Point Group
$Config['DistributionPointGroup'] = 'Alla distributionspunkter'

## Device Collection used for testing applications
$Config['TestCollection'] = 'Applikationstest'
## Device Collection used for optional applications in Software Center
$Config['AllOptionalCollection'] = 'Alla valfria applikationer'
## Path to folder for collection for required applications
$Config['RequiredCollectionFolder'] = '.\DeviceCollection\Applikation\Tvingad'
## CollectionID for limiting collection for new collections created by deploy required
$Config['LimitingCollectionId'] = 'PLS00016'

## Should imported applications by default be imported to TestCollection
$Config['DeployToTestCollection'] = $true

## Should imported applications by default update applications in TestCollection
$Config['UpdateSupersedence'] = $false

## Should imported applications by default just make a default detection rule
## Checking if file "C:\Program Files\XXX exists
## @TODO change name for this
$Config['OnlyDefaultDetectionRule'] = $false

## Should program just do a dry-run and not really import the applications
## Used only for testing purposes
$Config['DryRun'] = $false


## Function to get a configuration by key or throw if it don't exist
function Global:Get-Config {
    param(
        [ValidateNotNullOrEmpty()]
        [string]$key
    )
    # Write-Debug -Message "$key exist $($Config.ContainsKey($key))"
    If (-not $Config.ContainsKey($key)) {
        Throw "Config $key not found in Config.ps1, check your configuration"
    }
    $Config[$key]
}