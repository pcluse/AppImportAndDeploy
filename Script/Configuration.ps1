$ConfigFilePath = "C:\temp\config.xml"

function Get-DefaultConfiguration {
    $DefaultConfig = New-Object psobject
    $DefaultConfig | add-member 'SCCMSiteServer' ''
    $DefaultConfig | add-member 'AppPath' ''
    $DefaultConfig | Add-Member 'DefaultInstallCommandLine' 'Deploy-Application.exe -DeploymentType "Install"'
    $DefaultConfig | Add-Member 'DefaultUninstallCommandLine' 'Deploy-Application.exe -DeploymentType "Uninstall"'
    $DefaultConfig | Add-Member 'LogPath' $env:TEMP
    $DefaultConfig | Add-Member 'WorkLog' "AppImport-Work.log"
    $DefaultConfig | Add-Member 'TodoLog' "AppImport-todo.log"
    # Get list of DP Groups and if present, select the one from this setting
    $DefaultConfig | Add-Member 'DistributionpointGroup' "Alla distributionspunkter"
    $DefaultConfig | Add-Member 'TestCollectionID' "CCM00000"
    $DefaultConfig | Add-Member 'AllOptionalCollectionID' "CCM00000"
    $DefaultConfig | Add-Member 'LimitingCollectionID' "CCM000000"
    $DefaultConfig | Add-Member 'RequiredCollectionFolder' ".\DeviceCollection\Applikation\Tvingad"
    $DefaultConfig | Add-Member 'DeployToTestCollection' $true
    $DefaultConfig | Add-Member 'UpdateSupersedence' $true
    $DefaultConfig | Add-Member 'UpdateDependencies' $false
    $DefaultConfig | Add-Member 'OnlyDefaultDetectionRule' $false
    $DefaultConfig | Add-Member 'DryRun' $false
    $DefaultConfig
}

function Read-XML {
    param(
        $Path
    )
    Write-Host "Read $Path"
    $Data = ([xml](Get-Content -ErrorAction Stop -Path $Path -Raw)).Objects[0]
    # The following does not work, should be the same as above?
    #$Data = [xml](Get-Content -ErrorAction Stop -Path $Path -Raw) | Select-Object -ExpandProperty Objects | Select-Object -First 1 | Select-Object -ExpandProperty object
    $Data
}

function Get-DefaultConfigurationFromXML {
    $DefaultPath = Join-Path -Path $PSScriptRoot -ChildPath "config\DefaultConfiguration.xml"
    Read-XML -Path $DefaultPath
}

function Read-ConfigurationData {
    param(
        $Path
    )
    try {
        Read-XML -Path $Path
    } catch {
        Write-host "Failed to read config: $_"
        Write-Host "Using default configuration."
        Get-DefaultConfigurationFromXML
    }
}

function Save-ConfigurationData {
    param(
        $Path,
        $Configuration
    )
    $Configuration | ConvertTo-Xml -As String | Out-File $Path
}

$Config = Read-ConfigurationData -Path $ConfigFilePath
$Config
Save-ConfigurationData -Path $ConfigFilePath -Configuration $Config
