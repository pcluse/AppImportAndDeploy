function Global:Get-AppSettings {
    param(
        $RegPath
    )
    $SkipDetection = Get-ItemProperty -ErrorAction SilentlyContinue -Path $RegPath -Name SkipDetection | Select-Object -ExpandProperty SkipDetection
    if (-not $SkipDetection) { $SkipDetection = $true }
    $DeployToTest = Get-ItemProperty -ErrorAction SilentlyContinue -Path $RegPath -Name DeployToTest | Select-Object -ExpandProperty DeployToTest
    if (-not $DeployToTest -or $DeployToTest.Length -eq 0) { $DeployToTest = $true }
    $LogPath = Get-ItemProperty -ErrorAction SilentlyContinue -Path $RegPath -Name DeployToTest | Select-Object -ExpandProperty DeployToTest
    if (-not $LogPath -or $LogPath.Length -eq 0) { $LogPath = 'C:\Windows\Logs\PLS' }

    New-Object PSObject -Property @{
        SkipDetection = $SkipDetection
        DeployToTest = $DeployToTest
        LogPath = $LogPath
    }
}

function Set-AppSettings {
    param(
        [PSObject]$Settings,
        $RegPath
    )
    if (-not (Get-item -ErrorAction SilentlyContinue -Path $Regpath)) {
        New-Item -ItemType Container -Path $RegPath | Out-Null
    }
    $Settings | Get-Member -MemberType NoteProperty | % {
        ($Settings."$($_.Name)") #| gm
        Set-ItemProperty -Path $RegPath -Name $_.Name -Value $($Settings."$($_.Name)") -Force
    }
}
