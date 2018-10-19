Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process
$DebugPreference = "SilentlyContinue"

## Current version
$Global:Version = "1.0.2.0"

##############################
$InstalledPath = $PSScriptRoot
Write-Debug "Running from $InstalledPath"
Get-ChildItem -File -Filter '*.ps1' -Path $InstalledPath | Where-Object { $_.Name -notin 'appimport.ps1','Deploy.ps1'} | ForEach-Object {
    Write-Debug "Loading $($_.Name)"
    & "$($_.FullName)"
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
    $syncHash.SettingsRegpath = "HKCU:\Software\PLS\AppImporter"
    $syncHash.Host = $Host
    $syncHash.LogPath = Get-Config 'LogPath'
    $syncHash.SI = 'ImportDoneEvent'
    $syncHash.AppPath = Get-Config 'AppPath'
    $syncHash.DefaultDeployToTestCollection = Get-Config 'DeployToTestCollection'
    $syncHash.DefaultUpdateSupersedence = Get-Config 'UpdateSupersedence'
    $syncHash.DefaultDetection = Get-Config 'OnlyDefaultDetectionRule'
    $syncHash.DefaultUninstallPrevious = $false
    $syncHash.WorkLog = Get-Config 'WorkLog'
    $syncHash.TODOLog = Get-Config 'TODOLog'
    # $syncHash.SiteServer = 'sccm.pc.lu.se'
    $syncHash.DistributionPointGroup = Get-Config 'DistributionPointGroup'
    $syncHash.AppTestCollection = Get-Config 'TestCollection'
    $syncHash.DefaultInstallCommandline = Get-Config 'InstallCommandline'
    $syncHash.DefaultUninstallCommandline = Get-Config 'UninstallCommandline'
    $syncHash.DryRun = Get-Config 'DryRun'
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
    $syncHash.cbShouldDeployToTestCollection.Content = "Should Deploy to '$($syncHash.AppTestCollection)'"
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
Add-Eventhandler -syncHash $syncHash -Code { $syncHash.Host.Runspace.Events.GenerateEvent($syncHash.SI, $syncHash.bImport, $null, "import") } -Element bImport -Event Click
Add-Eventhandler -syncHash $syncHash -Code {
    $syncHash.Host.Runspace.Events.GenerateEvent($syncHash.SI, $syncHash.Window, $null, "closing")
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
    $obj | Add-Member DeployToTest $syncHash.DefaultDeployToTestCollection
    $obj | Add-Member UpdateSupersedence $syncHash.DefaultUpdateSupersedence
    $obj | Add-Member SkipDetection $syncHash.DefaultDetection
    $obj | Add-Member UninstallPrevious $syncHash.DefaultUninstallPrevious
    $obj | Add-Member Name $_.Name
    $obj | Add-Member Path $_.Path
    $obj | Add-Member AppName $_.NameAndVersion
    $obj | Add-Member InstallCommandline $syncHash.DefaultInstallCommandline
    $obj | Add-Member UninstallCommandline $syncHash.DefaultUninstallCommandline

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
    
}

# cleanup
$Event | Remove-Event -ErrorAction SilentlyContinue
Unregister-Event -ErrorAction SilentlyContinue -SourceIdentifier $syncHash.SI | Out-Null

Set-Location $OldLocation

