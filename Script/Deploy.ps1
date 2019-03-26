<#
.Synopsis
   Deploy an application to Alla valfria applikationer, Applikationstest eller en collection med samma namn som applikationen
.DESCRIPTION
   Some longer description
.EXAMPLE
   Deploy.ps1 -ApplicationName "TestApp v1.0" -Available

   Deploys to "Alla valfria applikationer" with available
.EXAMPLE
   Deploy.ps1 -ApplicationName "TestApp v1.0" -Test

   Deploys to "Applicationstest" with available. Aborts if application have placeholder detection
.EXAMPLE
   Deploy.ps1 -ApplicationName "TestApp v1.0" -Required

   Create collection Application/Tvingad/TestApp (if it don't exist) and deploys to that with required.
   Aborts if application have placeholder detection
#>

param (
    [string]$ApplicationName,
    [switch]$Available,
    [switch]$Required,
    [switch]$Test,
    [switch]$UpdateSupersedence,
    [switch]$Force
)

[System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms") | Out-Null

Function Show-Error($Message) {
    Write-Debug -Message "PLS Deploy Error $Message"
    [System.Windows.Forms.MessageBox]::Show($Message,"PLS Deploy Error",[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Error)
}

Function Show-Information($Message) {
    Write-Debug -Message "PLS Deploy Information $Message"
    [System.Windows.Forms.MessageBox]::Show($Message,"PLS Deploy Information",[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Information)
}

$DebugPreference = "Continue"

. $PSScriptRoot\Config.ps1
. $PSScriptRoot\Set-CMLocation.ps1
. $PSScriptRoot\Get-DetectionRules.ps1

try {
    # Could not use the name "Alla datorer med SCCM-klienten i PC-domänen" because of ä
    $Global:Config.WMINamespace = "root\sms\site_$(Get-WmiObject -ComputerName (Get-Config 'SCCMSiteServer') -Namespace 'root\sms' -Class SMS_ProviderLocation | Select-Object -ExpandProperty SiteCode)"

    $LimitingCollectionId = Get-Config 'LimitingCollectionId'
    $CheckPlaceHolderDetection = $false

    $Parameters = @{
            Name = $ApplicationName
            UpdateSupersedence = $UpdateSupersedence.IsPresent
    }

    if ($Test.IsPresent) {
        $Parameters.Add('DeployPurpose','Available')
        $Parameters.Add('CollectionName', (Get-Config 'TestCollection'))
    
        $CreateCollection = $false
    }
    elseif ($Available.IsPresent) {
        $Parameters.Add('CollectionName',(Get-Config 'AllOptionalCollection'))
        $Parameters.Add('DeployPurpose','Available')
        
        $CreateCollection = $false
        $CheckPlaceHolderDetection = $true
    }
    elseif ($Required.IsPresent) {
        if (-not ($ApplicationName -match "^(.*) v\d+(\.\d+)*$")) {
            Show-Error "Application name don't match XXXX v9... structure. Deploy stopped"
            break
        }
        $Parameters.Add('CollectionName',$Matches[1])
        $Parameters.Add('DeployPurpose','Required')
        
        $CreateCollection = $true
        $FolderPath = Get-Config 'RequiredCollectionFolder'
        $CheckPlaceHolderDetection = $true
    }
    else {
        Show-Error "Deploy type not given -Test, -Available or -Required"
        break
    }
} Catch {
    $Error[0] | Out-Host
    Show-Error -Message $Error[0].ToString()
    break
}

Set-CMLocation

If ($CheckPlaceHolderDetection) {
    #$HasPlaceHolderRule = $false
    try {
        Get-DetectionRules -ApplicationName $ApplicationName | ForEach-Object {
            If ($_.Type -eq "File" -and $_.Path -eq "C:\Program Files" -and $_.FileName -eq "XXX") {
                Show-Error "Placeholder rule detected. Deploy stopped"
                break
            }
        }
    }
    catch {
        # Just ignore this or...
    }
}

# Check if collection exists and create it if must
if ($Force.IsPresent) {
    Remove-CMDeviceCollection -Name $Parameters.CollectionName -ErrorAction SilentlyContinue
}

$CMCollection = Get-CMDeviceCollection -Name $Parameters.CollectionName -ErrorAction SilentlyContinue
If (-not $CMCollection) {
    If ($CreateCollection) {
        try {
            $RefreshSchedule = New-CMSchedule -Start ([DateTime]::Now) -RecurInterval Days -RecurCount 7
            $CMCollection = New-CMDeviceCollection -LimitingCollectionId $LimitingCollectionId -Name $Parameters.CollectionName -RefreshSchedule $RefreshSchedule -RefreshType Both
            Move-CMObject -FolderPath $FolderPath -InputObject $CMCollection
        }
        catch {
            Show-Error $Error[0].ToString()
            break
        }
    }
    Else {
        Show-Error "Collection $CollectionName don't exist. Deploy stopped"
        break 
    }
}

try {
    $twoHoursAgo = ([DateTime]::Now).AddHours('-2')
    $NewAppDeployment = New-CMApplicationDeployment @Parameters `
        -DeployAction Install -UserNotification DisplayAll `
        -TimeBaseOn LocalTime -AvailableDateTime $twoHoursAgo

    
    if ($NewAppDeployment -and $UpdateSupersedence.IsPresent) {
        Get-WmiObject -Namespace $Global:Config.WMINamespace -ComputerName $Global:Config.SCCMSiteServer -Class SMS_ApplicationAssignment -Filter "ApplicationName = '$ApplicationName'" | % {
            $_.UpdateDeadline = $twoHoursAgo.AddSeconds('50').ToString("yyyyMMddHHmmss.000000+***")
            $_.Put()
        }
    }
}
catch {
    Show-Error $Error[0].ToString()
    break
}

if ($Parameters.CollectionName -ne (Get-Config 'TestCollection')) {
    Get-CMDeployment -CollectionName (Get-Config 'TestCollection')  -FeatureType Application -SoftwareName $Parameters.Name | Remove-CMDeployment -Force
}

$Message = "$ApplicationName deployed as $($Parameters['DeployPurpose']) to $($Parameters['CollectionName'])"
If ($CMCollection.MemberCount -eq 0) {
    $Message += "`n`nNotice: Collection has no members"
}
Show-Information -Message $Message
