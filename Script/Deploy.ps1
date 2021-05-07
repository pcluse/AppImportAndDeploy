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
.EXAMPLE
   Deploy.ps1 -ApplicationName "TestApp v1.0" -AvailableSpecific

   Create collection Application/Tvingad/TestApp (if it don't exist) and deploys to that with available.
   Aborts if application have placeholder detection
.EXAMPLE
   Deploy.ps1 -ApplicationName "TestApp v1.0" -TestRequired

   Deploys to "Applicationstest" with required. Aborts if application have placeholder detection
#>

param (
    [string]$ApplicationName,
    [switch]$Available,
    [switch]$Required,
    [switch]$Test,
    [switch]$UpdateSupersedence,
    [switch]$Force,
    [switch]$AvailableSpecific, # HIG-Modification 
    [switch]$TestRequired       # HIG-Modification 
)

Push-Location

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
    Set-CMLocation
    # Could not use the name "Alla datorer med SCCM-klienten i PC-domänen" because of ä
    #$Global:Config | Add-Member WMINamespace "root\sms\site_$(Get-WmiObject -ComputerName (Get-Config 'SCCMSiteServer') -Namespace 'root\sms' -Class SMS_ProviderLocation | Select-Object -ExpandProperty SiteCode)"
    Global:Set-Config -key 'WMINamespace' "root\sms\site_$(Get-WmiObject -ComputerName (Get-Config 'SCCMSiteServer') -Namespace 'root\sms' -Class SMS_ProviderLocation | Select-Object -ExpandProperty SiteCode)"

    $LimitingCollectionId = Get-Config 'LimitingCollectionId'
    $CheckPlaceHolderDetection = $false

    $Parameters = @{
            Name = $ApplicationName
            UpdateSupersedence = $UpdateSupersedence.IsPresent
    }

    if ($Test.IsPresent) {
        $Parameters.Add('DeployPurpose','Available')
        $Parameters.Add('CollectionID', (Get-Config 'TestCollectionID'))
    
        $CreateCollection = $false
        $NeedRefreshSchedule = $true
    }
    elseif ($Available.IsPresent) {
        $Parameters.Add('CollectionID',(Get-Config 'AllOptionalCollectionID'))
        $Parameters.Add('DeployPurpose','Available')
        
        $CreateCollection = $false
        $CheckPlaceHolderDetection = $true
        $NeedRefreshSchedule = $true
    }
    elseif ($Required.IsPresent) {
        if (-not ($ApplicationName -match "^(.*) v\d+(\.\d+)*$")) {
            Show-Error "Application name don't match XXXX v9... structure. Deploy stopped"
            break
        }
        $CollectionName = $Matches[1]
        $CollectionSuffix = Get-Config 'RequiredCollectionSuffix'
        if (-not [string]::IsNullOrEmpty($CollectionSuffix)) {
            $CollectionName = "{0} {1}" -f $CollectionName,$CollectionSuffix
        }
        $Parameters.Add('CollectionName',$CollectionName)
        $CollectionID = (Get-CMDeviceCollection -ErrorAction SilentlyContinue -Name $CollectionName).CollectionID
        if ($CollectionID) {
            $Parameters.Add('CollectionID',$CollectionID)
        }
        $Parameters.Add('DeployPurpose','Required')
        
        $CreateCollection = $true
        $FolderPath = Get-Config 'RequiredCollectionFolder'
        $CheckPlaceHolderDetection = $true
        $NeedRefreshSchedule = $false
    }

    # HIG-Modification start
    elseif ($AvailableSpecific.IsPresent) {
        if (-not ($ApplicationName -match "^(.*) v\d+(\.\d+)*$")) {
            Show-Error "Application name don't match XXXX v9... structure. Deploy stopped"
            break
        }
        $CollectionName = $Matches[1]
        $CollectionSuffix = Get-Config 'AvailableCollectionSuffix'
        if (-not [string]::IsNullOrEmpty($CollectionSuffix)) {
            $CollectionName = "{0} {1}" -f $CollectionName,$CollectionSuffix
        }
        $Parameters.Add('CollectionName',$CollectionName)
        $CollectionID = (Get-CMDeviceCollection -ErrorAction SilentlyContinue -Name $CollectionName).CollectionID
        if ($CollectionID) {
            $Parameters.Add('CollectionID',$CollectionID)
        }		
        $Parameters.Add('DeployPurpose','Available')
        
        $CreateCollection = $true
        $FolderPath = Get-Config 'AvailableCollectionFolder'
        $CheckPlaceHolderDetection = $true
		$NeedRefreshSchedule = $false
    }
    elseif ($TestRequired.IsPresent) {
        $Parameters.Add('DeployPurpose','Required')
        $Parameters.Add('CollectionID', (Get-Config 'TestCollectionID'))
    
        $CreateCollection = $false
		$NeedRefreshSchedule = $true
    }
    # HIG-Modification end

    else {
        Show-Error "Deploy type not given -Test, -Available or -Required"
        break
    }
} Catch {
    $Error[0] | Out-Host
    Show-Error -Message $Error[0].ToString()
    break
}

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
    Remove-CMDeviceCollection -CollectionID $Parameters.CollectionID -ErrorAction SilentlyContinue
}

$CMCollection = Get-CMDeviceCollection -CollectionID $Parameters.CollectionID -ErrorAction SilentlyContinue
If (-not $CMCollection) {
    If ($CreateCollection) {
        try {
            if ($NeedRefreshSchedule) {
                $RefreshSchedule = New-CMSchedule -Start ([DateTime]::Now) -RecurInterval Days -RecurCount 7
                $CMCollection = New-CMDeviceCollection -LimitingCollectionId $LimitingCollectionId -Name $Parameters.CollectionName -RefreshSchedule $RefreshSchedule -RefreshType Both
            } else {
                $CMCollection = New-CMDeviceCollection -LimitingCollectionId $LimitingCollectionId -Name $Parameters.CollectionName -RefreshType None
            }
            if ($Parameters.ContainsKey('CollectionID')) {
                $Parameters['CollectionID'] = (Get-CMDeviceCollection -ErrorAction Stop -Name $Parameters.CollectionName).CollectionID
            }
            else {
                $Parameters.Add('CollectionID',(Get-CMDeviceCollection -ErrorAction Stop -Name $Parameters.CollectionName).CollectionID) 
            }
            
            Move-CMObject -FolderPath $FolderPath -InputObject $CMCollection
        }
        catch {
            Show-Error $Error[0].ToString()
            break
        }
    }
    Else {
        Show-Error "Collection $($Parameters.CollectionID) don't exist. Deploy stopped"
        break 
    }
}
else {
    if (-not ($Parameters.ContainsKey('CollectionName'))) {
        $Parameters.Add('CollectionName',$CMCollection.Name)
    }
}

try {
    $twoHoursAgo = ([DateTime]::Now).AddHours('-2')
    $DeployParameters = $Parameters.Clone()
    $DeployParameters.Remove('CollectionName')
    $NewAppDeployment = New-CMApplicationDeployment @DeployParameters `
        -DeployAction Install -UserNotification DisplayAll `
        -TimeBaseOn LocalTime -AvailableDateTime $twoHoursAgo

    
    if ($NewAppDeployment -and $UpdateSupersedence.IsPresent) {
        # HIG-modification GSR 191015 Bug correction. Paranthesis missing (Get-config 'WMINamespace')
        Get-WmiObject -Namespace (Get-config 'WMINamespace') -ComputerName $Global:Config.SCCMSiteServer -Class SMS_ApplicationAssignment -Filter "ApplicationName = '$ApplicationName'" | % {
            $_.UpdateDeadline = $twoHoursAgo.AddSeconds('50').ToString("yyyyMMddHHmmss.000000+***")
            $_.Put()
        }
    }
}
catch {
    Show-Error $Error[0].ToString()
    break
}

if ($Parameters.CollectionID -ne (Get-Config 'TestCollectionID')) {
    $TestCollectionName = Get-CMDeviceCollection -CollectionID (Get-Config 'TestCollectionID') |Select-Object -ExpandProperty Name
    Get-CMDeployment -CollectionName $TestCollectionName -FeatureType Application -SoftwareName $Parameters.Name | Remove-CMDeployment -Force
}

$Message = "$ApplicationName deployed as $($Parameters['DeployPurpose']) to $($Parameters['CollectionName'])"
If ($CMCollection.MemberCount -eq 0) {
    $Message += "`n`nNotice: Collection has no members"
}
Show-Information -Message $Message
Pop-Location