Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process
$DebugPreference = "SilentlyContinue"

## Current version
$Global:Version = "1.0.3.0"

##############################
$InstalledPath = $PSScriptRoot
Write-Debug "Running from $InstalledPath"
Get-ChildItem -File -Filter '*.ps1' -Path $InstalledPath | Where-Object { $_.Name -notin 'appimport.ps1','Deploy.ps1'} | ForEach-Object {
    Write-Debug "Loading $($_.Name)"
    . "$($_.FullName)"
}

Add-Type –assemblyName PresentationFramework
Add-Type –assemblyName PresentationCore
Add-Type –assemblyName WindowsBase
# System.Drawing is used for detecting icon size
Add-Type -AssemblyName System.Drawing

[System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms") | Out-Null

Function Global:Show-Error($Message) {
    Write-Debug -Message "PLS AppImport Error $Message"
    [System.Windows.Forms.MessageBox]::Show($Message,"PLS AppImport Error",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error)
}

# A variable synchash is used to communicate between the main thread and
# the thread the GUI is running on
$syncHash = [hashtable]::Synchronized(@{})
$newRunspace =[runspacefactory]::CreateRunspace()
$newRunspace.ApartmentState = "STA"
$newRunspace.ThreadOptions = "ReuseThread"         
$newRunspace.Open()
$newRunspace.SessionStateProxy.SetVariable("syncHash",$syncHash)

try { 
    $syncHash.appsToImport = New-Object System.Collections.ObjectModel.ObservableCollection[System.Object]
    $syncHash.XamlPath = "$PSScriptRoot\AppImport.xaml"
    #$syncHash.SettingsRegpath = "HKCU:\Software\PLS\AppImporter"
    $syncHash.Host = $Host
    $syncHash.LogPath = ([Environment]::ExpandEnvironmentVariables((Get-Config 'LogPath')))
    $syncHash.SI = 'ImportDoneEvent'
    $syncHash.AppPath = Get-Config 'AppPath'
    $syncHash.DefaultDeployToTestCollection = [bool]::parse((Get-Config 'DefaultDeployToTestCollection'))
    $syncHash.DefaultUpdateSupersedence = [bool]::parse((Get-Config 'DefaultUpdateSupersedence'))
    $syncHash.DefaultOnlyPlaceholderDetectionRule = [bool]::parse((Get-Config 'DefaultOnlyPlaceholderDetectionRule'))
    $syncHash.DefaultUninstallPrevious = [bool]::parse((Get-Config 'DefaultUninstallPrevious'))
    $syncHash.WorkLog = Get-Config 'WorkLog'
    $syncHash.TODOLog = Get-Config 'TODOLog'
    $syncHash.SCCMSiteServer = 'sccm.pc.lu.se'
    $syncHash.DistributionPointGroup = Get-Config 'DistributionPointGroup'
    $syncHash.AppTestCollectionID = Get-Config 'TestCollectionID'
    $syncHash.DefaultInstallCommandline = Get-Config 'DefaultInstallCommandline'
    $syncHash.DefaultUninstallCommandline = Get-Config 'DefaultUninstallCommandline'
    $syncHash.TeamsChannelName = Get-Config 'TeamsChannelName'
    $syncHash.TeamsChannelUrl = Get-Config 'TeamsChannelUrl'
    $syncHash.DefaultTeamsPostImport = [bool]::parse((Get-Config 'DefaultTeamsPostImport'))
    $syncHash.DryRun = [bool]::parse((Get-Config 'DryRun'))
    $syncHash.Version = $Version
} catch {
    $Error[0] | Out-Host
    Show-Error -Message $Error[0].ToString()
    Return
}

$psCmd = [PowerShell]::Create().AddScript({
    $WindowXAMLString = Get-Content $syncHash.XamlPath
    [xml]$WindowXAML = $WindowXAMLString -replace 'mc:Ignorable="d"','' -replace "x:N",'N' -replace 'x:Class="[a-zA-Z0-9\.]+"',''
    
    $reader=(New-Object System.Xml.XmlNodeReader ($WindowXAML))
    $syncHash.Window=[Windows.Markup.XamlReader]::Load( $reader )
    # Source: https://github.com/jeffreyw98/PowerShell/blob/d63991833b23739d11b7eed2b3dbd9c71850f0e3/Create-WPFWindow.ps1
    $WindowXAML.SelectNodes("//*[@*[contains(translate(name(.),'n','N'),'Name')]]") | ForEach-Object{

        #Find all of the form types and add them as members to the Window
        $syncHash.Add($_.Name,$syncHash.Window.FindName($_.Name) )

    }
    
    $syncHash.Window.Title = "AppImport v$($syncHash.Version)"
    $syncHash.cbShouldDeployToTestCollection.Content = "Should Deploy to '$($syncHash.AppTestCollectionID)'"
    $syncHash.lTeamsChannelName.Content = $syncHash.TeamsChannelName

    # Populate settings
    $syncHash.cbDefaultDeployToTestCollection.IsChecked = $syncHash.DefaultDeployToTestCollection
    $syncHash.tbAppPath.Text = $syncHash.AppPath
    $syncHash.tbSCCMSiteServer.Text = $syncHash.SCCMSiteServer
    $syncHash.cbDefaultUpdateSupersedence.IsChecked = $syncHash.DefaultUpdateSupersedence
    $syncHash.cbDefaultOnlyPlaceholderDetectionRule.IsChecked = $syncHash.DefaultOnlyPlaceholderDetectionRule
    $syncHash.cbDefaultUninstallPrevious.IsChecked = $syncHash.DefaultUninstallPrevious
    $syncHash.tbDistributionPointGroup.Text = $syncHash.DistributionPointGroup
    $syncHash.tbAppTestCollectionID.Text = $syncHash.AppTestCollectionID
    $syncHash.tbDefaultInstallCommandline.Text = $syncHash.DefaultInstallCommandline
    $syncHash.tbDefaultUninstallCommandline.Text = $syncHash.DefaultUninstallCommandline
    $syncHash.tbTeamsChannelName.Text = $syncHash.TeamsChannelName
    $syncHash.tbTeamsChannelUrl.Text = $syncHash.TeamsChannelUrl
    $syncHash.cbDefaultTeamsPostImport.IsChecked = $syncHash.DefaultTeamsPostImport
    $syncHash.cbDryRun.IsChecked = $syncHash.DryRun

    # Set source of list
    $syncHash.lvSelectedApps.ItemsSource = $syncHash.appsToImport

    $syncHash.Window.ShowDialog() | Out-Null
    $syncHash.Error = $Error
})

$psCmd.Runspace = $newRunspace
$psCmd.BeginInvoke()

While (-not $syncHash.Window.IsVisible) { Start-Sleep -Milliseconds 500 }

# Cleanup old eventstuff when testing
Get-Event -ErrorAction SilentlyContinue -SourceIdentifier $syncHash.SI | Remove-Event
Unregister-Event -ErrorAction SilentlyContinue -SourceIdentifier $syncHash.SI

# Disable button to prevent working while generating applist
Disable-ImportButton
# Register eventhandlers on elements
Add-Eventhandler -syncHash $syncHash -Code { $syncHash.Host.Runspace.Events.GenerateEvent($syncHash.SI, $syncHash.cbDefaultDeployToTestCollection, $null, @{type='cb';SettingName="DefaultDeployToTestCollection";}) } -Element cbDefaultDeployToTestCollection -Event Click
Add-Eventhandler -syncHash $syncHash -Code { $syncHash.Host.Runspace.Events.GenerateEvent($syncHash.SI, $syncHash.cbDefaultTeamsPostImport, $null, @{type='cb';SettingName="DefaultTeamsPostImport"}) } -Element cbDefaultTeamsPostImport -Event Click
Add-Eventhandler -syncHash $syncHash -Code { $syncHash.Host.Runspace.Events.GenerateEvent($syncHash.SI, $syncHash.cbDefaultOnlyPlaceholderDetectionRule, $null, @{type='cb';SettingName="DefaultOnlyPlaceholderDetectionRule"}) } -Element cbDefaultOnlyPlaceholderDetectionRule -Event Click
Add-Eventhandler -syncHash $syncHash -Code { $syncHash.Host.Runspace.Events.GenerateEvent($syncHash.SI, $syncHash.cbDefaultUpdateDependencies, $null, @{type='cb';SettingName="DefaultUpdateDependencies"}) } -Element cbDefaultUpdateDependencies -Event Click
Add-Eventhandler -syncHash $syncHash -Code { $syncHash.Host.Runspace.Events.GenerateEvent($syncHash.SI, $syncHash.cbDefaultUpdateSupersedence, $null, @{type='cb';SettingName="DefaultUpdateSupersedence"}) } -Element cbDefaultUpdateSupersedence -Event Click
Add-Eventhandler -syncHash $syncHash -Code { $syncHash.Host.Runspace.Events.GenerateEvent($syncHash.SI, $syncHash.cbDefaultUninstallPrevious, $null, @{type='cb';SettingName="DefaultUninstallPrevious"}) } -Element cbDefaultUninstallPrevious -Event Click
Add-Eventhandler -syncHash $syncHash -Code { $syncHash.Host.Runspace.Events.GenerateEvent($syncHash.SI, $syncHash.cbDryRun, $null, @{type='cb';SettingName="DryRun"}) } -Element cbDryRun -Event Click
Add-Eventhandler -syncHash $syncHash -Code { $syncHash.Host.Runspace.Events.GenerateEvent($syncHash.SI, $syncHash.tbTeamsChannelUrl, $null, @{type='tb';SettingName="TeamsChannelUrl"}) } -Element tbTeamsChannelUrl -Event KeyUp
Add-Eventhandler -syncHash $syncHash -Code { $syncHash.Host.Runspace.Events.GenerateEvent($syncHash.SI, $syncHash.tbSCCMSiteServer, $null, @{type='tb';SettingName="SCCMSiteServer"}) } -Element tbSCCMSiteServer -Event KeyUp
Add-Eventhandler -syncHash $syncHash -Code { $syncHash.Host.Runspace.Events.GenerateEvent($syncHash.SI, $syncHash.tbAppPath, $null, @{type='tb';SettingName="AppPath"}) } -Element tbAppPath -Event KeyUp
Add-Eventhandler -syncHash $syncHash -Code { $syncHash.Host.Runspace.Events.GenerateEvent($syncHash.SI, $syncHash.tbTeamsChannelName, $null, @{type='tb';SettingName="TeamsChannelName"}) } -Element tbTeamsChannelName -Event KeyUp
Add-Eventhandler -syncHash $syncHash -Code { $syncHash.Host.Runspace.Events.GenerateEvent($syncHash.SI, $syncHash.tbDefaultUninstallCommandline, $null, @{type='tb';SettingName="DefaultUninstallCommandline"}) } -Element tbDefaultUninstallCommandline -Event KeyUp
Add-Eventhandler -syncHash $syncHash -Code { $syncHash.Host.Runspace.Events.GenerateEvent($syncHash.SI, $syncHash.tbDefaultInstallCommandline, $null, @{type='tb';SettingName="DefaultInstallCommandline"}) } -Element tbDefaultInstallCommandline -Event KeyUp
Add-Eventhandler -syncHash $syncHash -Code { $syncHash.Host.Runspace.Events.GenerateEvent($syncHash.SI, $syncHash.tbAppTestCollectionID, $null, @{type='tb';SettingName="AppTestCollectionID"}) } -Element tbAppTestCollectionID -Event KeyUp
Add-Eventhandler -syncHash $syncHash -Code { $syncHash.Host.Runspace.Events.GenerateEvent($syncHash.SI, $syncHash.tbDistributionPointGroup, $null, @{type='tb';SettingName="DistributionPointGroup"}) } -Element tbDistributionPointGroup -Event KeyUp
Add-Eventhandler -syncHash $syncHash -Code { $syncHash.Host.Runspace.Events.GenerateEvent($syncHash.SI, $syncHash.bImport, $null, @{type="import"}) } -Element bImport -Event Click
Add-Eventhandler -syncHash $syncHash -Code {
    $syncHash.Host.Runspace.Events.GenerateEvent($syncHash.SI, $syncHash.Window, $null, @{type="closing"})
} -Element Window -Event Closing

# Register eventsubscriver
#Register-EngineEvent -MaxTriggerCount 1 -SourceIdentifier $syncHash.SI -Forward

# Set first app as selected
Set-SelectedAppInList -syncHash $syncHash

$OldLocation = Get-Location
Set-CMLocation

Start-Progress -syncHash $syncHash

# Add applications to list
Get-NotImporteredApplications -ApplicationFolder $syncHash.AppPath | ForEach-Object {
    if (-not $syncHash.Window.IsVisible) {
        Write-CMLogEntry -LogPath $syncHash.LogPath -FileName $syncHash.WorkLog -Severity 3 -Value 'Window closed in the middle of adding applications'
        break
    }

    $obj = New-Object PSObject
    $obj | Add-Member DoImport $false
    $obj | Add-Member DeployToTestCollection $syncHash.DefaultDeployToTestCollection
    $obj | Add-Member UpdateSupersedence $syncHash.DefaultUpdateSupersedence
    $obj | Add-Member UpdateDependencies $syncHash.DefaultUpdateDependencies
    $obj | Add-Member OnlyPlaceholderDetectionRule $syncHash.DefaultOnlyPlaceholderDetectionRule
    $obj | Add-Member UninstallPrevious $syncHash.DefaultUninstallPrevious
    $obj | Add-Member Name $_.Name
    $obj | Add-Member Path $_.Path
    $obj | Add-Member AppName $_.NameAndVersion
    $obj | Add-Member InstallCommandline $syncHash.DefaultInstallCommandline
    $obj | Add-Member UninstallCommandline $syncHash.DefaultUninstallCommandline
    $obj | Add-Member TeamsPostImport $syncHash.DefaultTeamsPostImport

    Add-ApplicationToList -syncHash $syncHash -Object $obj
}

Stop-Progress -syncHash $syncHash

# Enable button, we need our eventgenerator
# Write-Worklog -syncHash $syncHash -Text "Activating importbutton"
Enable-ImportButton

# Wait for event while window exist
While ($syncHash.Window.IsVisible) {
    $Event = Wait-Event -SourceIdentifier $syncHash.SI -Timeout 5
    $Event | Remove-Event -ErrorAction SilentlyContinue
    if ($Event.MessageData -eq 'import') {
        $AppsToImport = $syncHash.appsToImport | Where-Object { $_.DoImport }
        if ($AppsToImport -ne $null) {
            Set-ActiveTab -syncHash $syncHash -SelectedTabIndex 1
            Disable-ImportButton
            Start-Progress -syncHash $syncHash
            $AppsToImport | ForEach-Object {
                $Success = Import-SCCMApplication -syncHash $syncHash -ImportApplication $_
                If ($Success) {
                    Remove-ApplicationFromList -syncHash $syncHash -Object $_
                }
            }
            Stop-Progress -syncHash $syncHash
            Write-Worklog -syncHash $syncHash -Text "--- Import finished for all ---"
            Enable-ImportButton
        }
    }
    elseif ($Event.MessageData.type -eq 'cb') {
        $NewValue = ([bool](1 -bxor [bool]::Parse((Global:Get-Config -key $Event.MessageData.SettingName))))
        Global:Set-Config -key $Event.MessageData.SettingName $NewValue
        #$IsChecked = $syncHash.cbDefaultDeployToTest.Dispatcher.Invoke([action]{$syncHash.cbDefaultDeployToTest.IsChecked},"Normal")
        #Write-Host ($syncHash.Window.DefaultDeployToTestCollection)
        #Global:Set-Config -key DefaultDeployToTestCollection -Value $syncHash.Window.DefaultDeployToTestCollection
        #Global:Set-Config -key 'DeployToTestCollection' -Value $syncHash.cbDefaultDeployToTest
        Write-Worklog -syncHash $syncHash -Text (Global:Get-Config -key $Event.MessageData.SettingName)
        if ($Event.MessageData.SettingName -match 'Default') {
            $syncHash.appsToImport | ForEach-Object {
                $_."$($Event.MessageData.SettingName -replace 'Default')" = $NewValue
            }
            Set-SelectedAppInList -syncHash $syncHash -SelectedIndex $syncHash.lvSelectedApps.SelectedIndex
        }
        else {
            $syncHash."$($Event.MessageData.SettingName)" = $NewValue
        }
        Write-Worklog -syncHash $syncHash -Text "Should save settings"
    }
    elseif ($Event.MessageData.type -eq 'tb') {
        $NewValue = ($syncHash."tb$($Event.MessageData.SettingName)" -replace 'System.Windows.Controls.TextBox: ')
        Global:Set-Config -key $Event.MessageData.SettingName -Value $NewValue
        if ($Event.MessageData.SettingName -match 'Default') {
            $syncHash.appsToImport | ForEach-Object {
                $_."$($Event.MessageData.SettingName -replace 'Default')" = $NewValue
            }
            Set-SelectedAppInList -syncHash $syncHash -SelectedIndex $syncHash.lvSelectedApps.SelectedIndex
        }
        else {
            $syncHash."$($Event.MessageData.SettingName)" = $NewValue
        }
        
    }
    #elseif ($Event.MessageData -eq 'closing') {
    #    Save-ConfigurationData
    #}
}

# cleanup
$Event | Remove-Event -ErrorAction SilentlyContinue
Unregister-Event -ErrorAction SilentlyContinue -SourceIdentifier $syncHash.SI | Out-Null

Set-Location $OldLocation

