function Global:Set-ActiveTab {
    param(
        $syncHash,
        $SelectedTabIndex
    )
    $syncHash.tcTabs.Dispatcher.Invoke([action]{$syncHash.tcTabs.SelectedIndex = $SelectedTabIndex},"Normal")
}


function Global:Add-Eventhandler {
    param(
        $syncHash,
        $Code,
        $Element,
        $Event
    )
    $syncHash."$Element".Dispatcher.Invoke([action]{$syncHash."$Element"."Add_$Event"($Code)},"Normal")
}

function Global:Enable-ImportButton {
    $syncHash.bImport.Dispatcher.Invoke([action]{ $syncHash.bImport.IsEnabled = $true },"Normal")
}

function Global:Disable-ImportButton {
    $syncHash.bImport.Dispatcher.Invoke([action]{ $syncHash.bImport.IsEnabled = $false },"Normal")
}

function Global:Add-ApplicationToList {
    param(
        $syncHash,
        $Object
    )
    $syncHash.lvSelectedApps.Dispatcher.Invoke([action]{$syncHash.appsToImport.Add($Object)},"Normal")
}

function Global:Remove-ApplicationFromList {
    param(
        $syncHash,
        $Object
    )
    $syncHash.lvSelectedApps.Dispatcher.Invoke([action]{$syncHash.appsToImport.Remove($Object)},"Normal")
}

function Global:Set-SelectedAppInList {
    param(
        $syncHash,
        $SelectedIndex=0
    )
    $syncHash.lvSelectedApps.Dispatcher.Invoke([action]{$syncHash.lvSelectedApps.SelectedIndex = $SelectedIndex},"Normal")
}

function Global:Write-Worklog {
    param(
        $syncHash,
        $Text
    )
    $syncHash.lbWorklog.Dispatcher.Invoke([action]{
        $syncHash.lbWorklog.Items.Add($Text)
        if ($syncHash.lbWorklog.Items.Count -ge 1) {
            $syncHash.lbWorklog.ScrollIntoView($syncHash.lbWorklog.Items.GetItemAt($syncHash.lbWorklog.Items.Count-1))
        }
    },"Normal")
    Write-Debug "WORK: $Text"
    Write-CMLogEntry -LogPath $syncHash.LogPath -Severity 1 -Value $Text -FileName $syncHash.WorkLog
}

function Global:Write-Todolog {
    param(
        $syncHash,
        $Text
    )
    $syncHash.lbTodolog.Dispatcher.Invoke([action]{$syncHash.lbTodolog.Items.Add($Text)},"Normal")
    Write-Debug "TODO: $Text"
    Write-CMLogEntry -LogPath $syncHash.LogPath -Severity 1 -Value $Text -FileName $syncHash.TODOLog
}

function Global:Set-WindowTaskbarInfo {
    param(
        $syncHash,
        $Progress
    )
    if ($Progress -lt 100.0 -and $Progress -gt 0.0) {
        $syncHash.Window.Dispatcher.Invoke([action]{$syncHash.Window.TaskbarItemInfo.ProgressState = 'Normal' },"Normal")
    }
    else {
        $syncHash.Window.Dispatcher.Invoke([action]{$syncHash.Window.TaskbarItemInfo.ProgressState = 'None' },"Normal")
    }
    $syncHash.Window.Dispatcher.Invoke([action]{$syncHash.Window.TaskbarItemInfo.ProgressValue = $Progress },"Normal")
}


function Global:Start-Progress {
    param(
        $syncHash
    )
    $syncHash.Window.Dispatcher.Invoke([action]{
            $syncHash.pbProgress.IsIndeterminate = $true
    },"Normal")
}

function Global:Stop-Progress {
    param(
        $syncHash
    )
    $syncHash.Window.Dispatcher.Invoke([action]{$syncHash.pbProgress.IsIndeterminate = $false; $syncHash.pbProgress.Value = 0},"Normal")
}
