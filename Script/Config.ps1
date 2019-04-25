#######################################
#### AppImort and Deploy settings #####
#######################################

$Global:Config = @{
    # This will be set first in the script
    WMINamespace = ''
    # Used to do stuff that the cmdlets wont let you, once the cmdlets work this should not be needed
    SCCMSiteServer = 'server.domain.domain'
    ## Path where applications are stored
    ## This should contain folders with the name of the application
    ## and subfolders with version numbers
    AppPath = '\\server.domain.domain\share$\applicationfolder'

    ## Default install and uninstall command line
    InstallCommandline = 'Deploy-Application.exe -DeploymentType "Install"'
    UninstallCommandline = 'Deploy-Application.exe -DeploymentType "Uninstall"'

    ## Location of log-files
    LogPath = "$($env:LOCALAPPDATA)\Temp"
    ## Name of log for work progression
    WorkLog = 'AppImport-worklog.log'
    ## Name of log for things todo
    TODOLog = 'AppImport-todolog.log'

    ## Distribution Point Group
    DistributionPointGroup = 'Alla distributionspunkter'

    ## Device Collection used for testing applications
    TestCollection = 'Applikationstest'
    ## Device Collection used for optional applications in Software Center
    AllOptionalCollection = 'Alla valfria applikationer'
    ## Path to folder for collection for required applications
    RequiredCollectionFolder = '.\DeviceCollection\Applikation\Tvingad'
    ## CollectionID for limiting collection for new collections created by deploy required
    LimitingCollectionId = 'PLS00016'

    ## Should imported applications by default be imported to TestCollection
    DeployToTestCollection = $true

    ## Should imported applications by default update applications in TestCollection
    UpdateSupersedence = $false

    ## Should imported applications by default just make a default detection rule
    ## Checking if file "C:\Program Files\XXX exists
    ## @TODO change name for this
    OnlyDefaultDetectionRule = $false

    ## Should program just do a dry-run and not really import the applications
    ## Used only for testing purposes
    DryRun = $false

    ## Should info on imported applications be posted on teams
    TeamsPostImport = $true
    TeamsChannelName = "Name of teams channel"
    TeamsChannelUrl = 'https://outlook.office.com/webhook/..........and more'
    
}

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