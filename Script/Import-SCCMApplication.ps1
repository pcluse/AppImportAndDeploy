﻿<#
    Import-SCCMApplication this does the import of the application

    It uses two datastructures then importing


    $AppInfo
        Name                   : My Fine TestApp
        Version                : 1.4
        Path                   : \\some-server\some-share\some-folder\MinFinaTestApp\1.4
        ParentPath             : \\some-server\some-share\some-folder\MinFinaTestApp
        IconPath               : \\some-server\some-share\some-folder\MinFinaTestApp\icon.png
        IsPSADT                : True
        VersionCheck           : False
        PSADTName              : My Fine TestApp
        PSADTNameMangled       : MyFineTestApp
        PSADTVersion           : 1.4
        PSADTVendor            : My Company
        PSADTRegistryDetection : True
        MSIInfo                :

    $ImportApplication
        DoImport             : True
        DeployToTest         : True
        UpdateSupersedence   : False
        SkipDetection        : False
        UninstallPrevious    : False
        Name                 : MyFineTestApp
        Path                 : \\some-server\some-share\some-folder\MyFineTestApp\1.4
        AppName              : MyFineTestApp v1.4
        InstallCommandline   : Deploy-Application.exe -DeploymentType "Install"
        UninstallCommandline : Deploy-Application.exe -DeploymentType "Uninstall"

    
    1) Ceates an application with name $ImportApplication.AppName and version $AppInfo.Version
        Copies LocalizedApplicationDescription, LinkText and UserDocumentation from previous version
    2) Creates a Script deployment with the name $ImportApplication $ImportApplication.AppName + " PSADT"
        Uses $ImportApplication.Path for content location
        $ImportApplication.InstallCommandline and $ImportApplication.UninstallCommandline for install/unistall commmands
    3) Detection rules (if SkipDetection not true )
        New rules for MSI in $AppInfo.MSI
        New rule if $AppInfo.PSADTRegistryDetection is true
        Copy rule for file version but change Between oldversion.0, oldversion.99999 to $AppInfo.Version.0,$AppInfo.Version.99999
            If AppInfo.Version is like x.x.x
        Otherwise copy rule for file version but change to $AppInfo.Version
        All other rules are copied from old version
    4) Add supersedence if older version found. Make previous version unistall if $ImportApplication.UninstallPrevious is true.
    5) Distribute Application to Distribution Group
    6) Deploy it to a test collection if $ImportApplication is true
#>



function Global:Convert-PSObjectToHashTable {
    param (
        [Parameter(Mandatory=$true,
        Position=0)]
        $Object
    )
    $h = @{}
    $Object.Keys | ForEach-Object { $h[$_] = $Object[$_] }
    $h
}

function Global:CheckAndWarnIfVersion($syncHash, $AppName, $DetectionRule) {
    $VersionExpression = '[0-9]\.[0-9]'

    if ($DetectionRule.Path -match $VersionExpression) {
        Write-Todolog -syncHash $syncHash -Text "$($AppName): Detection rule: Path $($DetectionRule.Path) may contain version specific number. Check it"
    }
    if ($DetectionRule.FileName -match $VersionExpression) {
        Write-Todolog -syncHash $syncHash -Text "$($AppName): Detection rule: FileName $($DetectionRule.FileName) may contain version specific number. Check it"
    }
    if ($DetectionRule.KeyName -match $VersionExpression) {
        Write-Todolog -syncHash $syncHash -Text "$($AppName): Detection rule: KeyName $($DetectionRule.KeyName) may contain version specific number. Check it"
    }
    if ($DetectionRule.ValueName -match $VersionExpression) {
        Write-Todolog -syncHash $syncHash -Text "$($AppName): Detection rule: ValueName $($DetectionRule.ValueName) may contain version specific number. Check it"
    }
    if ($DetectionRule.ExpectedValue -is [array]) {
        foreach ($value in $DetectionRule.ExpectedValue) {
            if ($value -match $VersionExpression) {
                Write-Todolog -syncHash $syncHash -Text "$($AppName): Detection rule: ExpectedValue $($value) may contain version specific number. Check it"
            } 
        }
    }
    elseif ($DetectionRule.ExpectedValue -match $VersionExpression) {
        Write-Todolog -syncHash $syncHash -Text "$($AppName): Detection rule: ExpectedValue $($DetectionRule.ExpectedValue) may contain version specific number. Check it"
    } 
}

# Try to convert a string to first a version x.x.x.x
# If it fails try to convert it to an int and if what also
# fails it just return it as is
function Global:Get-Version($s) {
    $Version = ($s -Split '-')[0]
    try {
        [System.Version]$Version
    }
    catch {
        try {
            [int]$Version
        }
        catch {
            $Version
        }
    }
}

function Global:Get-ImageSize($imageFile) {   
    $image = New-Object System.Drawing.Bitmap $imageFile
    $imageWidth = $image.Width
    $imageHeight = $image.Height
    $image.Dispose()
    return $imageWidth,$imageHeight
}

function Global:Get-ApplicationDisplayInfo {
    param($Application)

    $xml = [xml]$Application.SDMPackageXML
    $info = $xml.AppMgmtDigest.ChildNodes.DisplayInfo.Info

    return New-Object PSObject @{
        Description = $info.Description
        InfoUrl = $info.InfoUrl
        InfoUrlText = $info.InfoUrlText
    }
}


function Global:Import-SCCMApplication {
    param(
        # Param1 help description
        [Parameter(Mandatory=$true,
                   ValueFromPipeline=$true)]

        $ImportApplication,
        $syncHash
        
    )

    $isNewApplication = $true
    
    Write-Worklog -syncHash $syncHash -Text "$($ImportApplication.AppName): Start import"

    $ImportApplication | Out-Host

    $AppInfo = Get-ApplicationInformationFromSourceDirectory -Path $ImportApplication.Path
    If ($AppInfo -eq $null) {
        Write-Worklog -syncHash $syncHash -Text "$($ImportApplication.AppName): Could not read app info from $($ImportApplication.Path)"
        Write-Worklog -syncHash $syncHash -Text "$($ImportApplication.AppName): Imported aborted"
        return $false
    }

    $AppInfo | Out-Host

    # Sanity checks
    If (-not (Test-Path -Path "FileSystem::$($AppInfo.IconPath)")) {
        Write-Todolog -syncHash $syncHash -Text "$($ImportApplication.AppName): Icon file not found"
        $AppInfo.IconPath = $null
    }
    Else {
        $w,$h = Get-ImageSize $AppInfo.IconPath
        If ($w -gt 512 -or $h -gt 512) {
            Write-Todolog -syncHash $syncHash -Text "$($ImportApplication.AppName): Icon file too large $($w)x$($h) (max is 512x512)"
            $AppInfo.IconPath = $null
        }
    }

    If ($AppInfo.PSADTRegistryDetection) {
        $shouldReturn = $false
        If ($AppInfo.PSADTName -eq '') {
            Write-Todolog -syncHash $syncHash -Text "$($ImportApplication.AppName): Add-SCCMDetection but `$appName not set"
            $shouldReturn = $true
        }
        If ($AppInfo.PSADTVersion -eq '') {
            Write-Todolog -syncHash $syncHash -Text "$($ImportApplication.AppName): Add-SCCMDetection but `$appVersion not set"
            $shouldReturn = $true
        }
        if ($shouldReturn) {
            Write-Worklog -syncHash $syncHash -Text "$($ImportApplication.AppName): Imported aborted"
            return $false
        }
    }

    $ImportedApplicationVersion = Get-Version $AppInfo.Version
    $CMImportedApplications = Get-CMApplication -Name "$($ImportApplication.Name) v*"

    If ($CMImportedApplications) {
        $CMPreviousApplication = $CMImportedApplications | Where-Object {
            (Get-Version $_.SoftwareVersion) -lt $ImportedApplicationVersion
        } | Sort-Object -Property @{Expression={Get-Version $_.SoftwareVersion}} | Select-Object -Last 1

        $CMNextApplication = $CMImportedApplications | Where-Object {
            (Get-Version $_.SoftwareVersion) -gt $ImportedApplicationVersion
        } | Sort-Object -Property @{Expression={Get-Version $_.SoftwareVersion}} | Select-Object -First 1
    }
    Else {
        $CMPreviousApplication = $null
        $CMNextApplication = $null
    }
    
    If ($CMPreviousApplication) {
        $isNewApplication = $false
        Write-Worklog -syncHash $syncHash -Text "$($ImportApplication.AppName): Found previous version $($CMPreviousApplication.LocalizedDisplayName)"
    }
    If ($CMNextApplication) {
        Write-Todolog -syncHash $syncHash -Text "$($ImportApplication.AppName): Found NEWER version $($CMNextApplication.LocalizedDisplayName). Update it's supersedence"
    }

    Write-Worklog -syncHash $syncHash -Text "$($ImportApplication.AppName): Creating application"
    if (-not $syncHash.DryRun) {
        $Args = @{
            Name             = $ImportApplication.AppName
            SoftwareVersion  = $AppInfo.Version
            AutoInstall      = $true
            LocalizedName    = $ImportApplication.Name
        }
        If ($AppInfo.IconPath -ne $null) {
            $Args['IconLocationFile'] = $AppInfo.IconPath
        }

        # Copy Application Catalog info from previous version
        if (-not $isNewApplication) {
            $DisplayInfo = Get-ApplicationDisplayInfo -Application $CMPreviousApplication
            
            if (-not [string]::IsNullOrEmpty($DisplayInfo.InfoUrlText)) { $Args['LinkText'] = $DisplayInfo.InfoUrlText }
            if (-not [string]::IsNullOrEmpty($DisplayInfo.Description)) { $Args['LocalizedApplicationDescription'] = $DisplayInfo.Description }
            if (-not [string]::IsNullOrEmpty($DisplayInfo.InfoUrl)) { $Args['UserDocumentation'] = $DisplayInfo.InfoUrl }
        }
        $Args | Out-Host
        try {
            $NewCMApplication = New-CMApplication @Args
        }
        catch {
            $Error[0] | Out-Host
            Write-Worklog -syncHash $syncHash -Text "$($ImportApplication.AppName): Error creating application"
            return $false
        }
        
    }
    # TODO get description from previous version

    $DeploymentTypeName = "$($ImportApplication.AppName) PSADT"

    # Make a script deployment. Could not add detection rules here
    Write-Worklog -syncHash $syncHash -Text "$($ImportApplication.AppName): Added Scriptdeploymenttype $DeploymentTypeName"
    if (-not $syncHash.DryRun) {
        try {
            $NewCMApplication | Add-CMScriptDeploymentType -DeploymentTypeName $DeploymentTypeName `
                -ContentLocation $ImportApplication.Path `
                -ScriptLanguage PowerShell `
                -ScriptText "#" `
                -InstallCommand $ImportApplication.InstallCommandline `
                -UninstallCommand $ImportApplication.UninstallCommandline `
                -InstallationBehaviorType InstallForSystem `
                -LogonRequirementType WhetherOrNotUserLoggedOn `
                -EstimatedRuntimeMins 10 `
                -MaximumRuntimeMins 120 `
                -RebootBehavior BasedOnExitCode ` | Out-Null
        }
        catch {
            $Error[0] | Out-Host
            Write-Worklog -syncHash $syncHash -Text "$($ImportApplication.AppName): Error creating Scriptdeploymenttype"
            return $true
        }
    }


    # Create detection clauses
    
    [System.Collections.ArrayList]$DetectionClauses = @()

    # Detection
    if (-not $ImportApplication.SkipDetection) {
        if ($AppInfo.PSADTRegistryDetection) {
            Write-Worklog -syncHash $syncHash -Text "Added SCCMDetection detection rule"
            $DetectionClause = New-CMDetectionClauseRegistryKeyValue -Hive LocalMachine -KeyName "Software\PLS\$($AppInfo.PSADTNameMangled)" `
                -Value -ValueName $null -ExpectedValue $AppInfo.PSADTVersion -PropertyType String -ExpressionOperator IsEquals
            $DetectionClauses.Add($DetectionClause) | Out-Null
        }
        if ($AppInfo.MSIInfo -ne $null) { 
            $AppInfo.MSIInfo | ForEach-Object {
                Write-Worklog -syncHash $syncHash -Text "$($ImportApplication.AppName): Added MSI detection rule $($_.Productcode) has version $($_.ProductVersion)"
                $DetectionClause = New-CMDetectionClauseWindowsInstaller -ProductCode $_.ProductCode `
                    -Value -PropertyType ProductVersion -ExpressionOperator IsEquals -ExpectedValue $_.ProductVersion 
                $DetectionClauses.Add($DetectionClause) | Out-Null
            }  
        }
        If (-not $isNewApplication) {

            try {
                $PreviousRules = Get-DetectionRules -ApplicationName $CMPreviousApplication.LocalizedDisplayName
            } catch {
                Write-Todolog -syncHash $syncHash -Text "$($ImportApplication.AppName): Could not get detection from previous version: $($Error[0])"
                $PreviousRules = @()
            }
            foreach ($PreviousRule in $PreviousRules) {
                # Can´t use foreach-object and $_ here because $_ is changed inside switch statement :(
                $PreviousRule | Out-Host
                $DetectionClause = $null
                # Convert PSObject to hashtable which can be used as argument to New-CMDetectionClauseXXXXX
                # Remove Type because it isn't an argument
                $Args = Convert-PSObjectToHashTable $PreviousRule
                $Args.Remove('Type')
                # Write-Host @Args
                switch ($PreviousRule.Type) {
                    'RegistryKeyValue' {
                            if ( $PreviousRule.KeyName -ne "Software\PLS\$($AppInfo.PSADTNameMangled)") {
                                $DetectionClause = New-CMDetectionClauseRegistryKeyValue @Args
                                Write-Worklog -syncHash $syncHash -Text "$($ImportApplication.AppName): Added RegistryKeyValue detection rule"
                                CheckAndWarnIfVersion -syncHash $syncHash -AppName $ImportApplication.AppName -DetectionRule $Args
                            }
                        }
                    'RegistryKey' {
                            $DetectionClause = New-CMDetectionClauseRegistryKey @Args
                            Write-Worklog -syncHash $syncHash -Text "$($ImportApplication.AppName): Added Registrykey detection rule"
                            CheckAndWarnIfVersion -syncHash $syncHash -AppName $ImportApplication.AppName -DetectionRule $Args
                        }
                    'File' {
                            if ($PreviousRule.PropertyType -eq 'Version' -and $PreviousRule.ExpressionOperator -eq 'Between' `
                            -and $AppInfo.Version -match '\d+\.\d+\.\d+') {
                                $Args['ExpectedValue'] = "$($AppInfo.Version).0","$($AppInfo.Version).99999"
                            }
                            elseif ($PreviousRule.PropertyType -eq 'Version' -and $AppInfo.Version -ne '') {
                                $Args['ExpectedValue'] = $AppInfo.Version
                            }
                            $DetectionClause = New-CMDetectionClauseFile @Args
                            Write-Worklog -syncHash $syncHash -Text "$($ImportApplication.AppName): Added File detection rule"
                            CheckAndWarnIfVersion -syncHash $syncHash -AppName $ImportApplication.AppName -DetectionRule $Args
                        }
                    'Directory' { 
                            $DetectionClause = New-CMDetectionClauseDirectory @Args
                            Write-Worklog -syncHash $syncHash -Text "$($ImportApplication.AppName): Added Directory detection rule"
                            CheckAndWarnIfVersion -syncHash $syncHash -AppName $ImportApplication.AppName -DetectionRule $Args
                        }
                    'WindowsInstaller' { <# Just ignore #> }
                } # Switch
                if ($DetectionClause -ne $null) {
                    $DetectionClauses.Add($DetectionClause) | Out-Null
                }
            } # foreach
        } # -not isNewApplication
    } # -not Skipdetection

    

    # Add the detectionrules to the deployment type
    if (-not $syncHash.DryRun) {
        # Add a placeholder if no detection found. Where must always be one detection rules otherwise
        # will config manager tilt 
        if ($DetectionClauses.Count -eq 0) {
            Write-Todolog -syncHash $syncHash -Text "$($ImportApplication.AppName): Added placeholder detection rule"
            $DetectionClause = New-CMDetectionClauseFile -Path "C:\Program Files" -FileName "XXX" -Existence
            $DetectionClauses.Add($DetectionClause) | Out-Null
        }
        try {
            Set-CMScriptDeploymentType -ApplicationName $ImportApplication.AppName `
                -DeploymentTypeName $DeploymentTypeName `
                -AddDetectionClause $DetectionClauses
        }
        catch {
            $Error[0] | Out-Host
            Write-Worklog -syncHash $syncHash -Text "$($ImportApplication.AppName): Error adding detection rules"
            return $true
        }       
    }

    # Dependencies
    If (-not $isNewApplication) {
        try {
            Get-CMDeploymentType -ApplicationName $CMPreviousApplication.LocalizedDisplayName | Get-CMDeploymentTypeDependencyGroup | ForEach-Object {
                $group = $_
                $newGroup = Get-CMDeploymentType -ApplicationName $ImportApplication.AppName -DeploymentTypeName $DeploymentTypeName `
                     | New-CMDeploymentTypeDependencyGroup -GroupName $group.GroupName
                Write-Worklog -syncHash $syncHash -Text "$($ImportApplication.AppName): adding dependency group $($group.GroupName)"
                $group | Get-CMDeploymentTypeDependency | ForEach-Object {
                   
                    $newGroup | Add-CMDeploymentTypeDependency -DeploymentTypeDependency $_ -IsAutoInstall $true
                    Write-Worklog -syncHash $syncHash -Text "$($ImportApplication.AppName): adding dependency on $($_.LocalizedDisplayName)"
                }

            }
        } catch {
            Write-Todolog -syncHash $syncHash -Text "$($ImportApplication.AppName): Could not copy depencencies from old version: $($Error[0])"
        }
    }

    # Add supersedence
    if (-not $isNewApplication) {
        if ($syncHash.DryRun) {
            Write-Worklog -syncHash $syncHash -Text "$($ImportApplication.AppName): Supersede $($CMPreviousApplication.LocalizedDisplayName) PSADT with $($ImportApplication.AppName) PSADT"
        }
        else {
            $oldCMDeploymentType = Get-CMDeploymentType -ApplicationName $CMPreviousApplication.LocalizedDisplayName
            $newCMDeploymentType = Get-CMDeploymentType -ApplicationName $ImportApplication.AppName
            try {
                Add-CMDeploymentTypeSupersedence `
                    -SupersedingDeploymentType $newCMDeploymentType `
                    -SupersededDeploymentType $oldCMDeploymentType `
                    -IsUninstall $ImportApplication.UninstallPrevious | Out-Null
            }
            catch {
                $Error[0] | Out-Host
                Write-Worklog -syncHash $syncHash -Text "$($ImportApplication.AppName): Error adding supersedence"
                return $true
            }
            Write-Worklog -syncHash $syncHash -Text "Supersede $($oldCMDeploymentType.LocalizedDisplayName) with $($newCMDeploymentType.LocalizedDisplayName)"
        }   
    }
    
    # Distribute
    Write-Worklog -syncHash $syncHash -Text "$($ImportApplication.AppName): Distribute content to '$($syncHash.DistributionPointGroup)'"
    if (-not $syncHash.DryRun) {
        try {
            Start-CMContentDistribution -DistributionPointGroupName $syncHash.DistributionPointGroup -ApplicationName $ImportApplication.AppName
        }
        catch {
            $Error[0] | Out-Host
            Write-Worklog -syncHash $syncHash -Text "$($ImportApplication.AppName): Error distributing content"
            return $true
        }
    }

    # Deploy
    if ($ImportApplication.DeployToTest) {      
        Write-Worklog -syncHash $syncHash -Text "$($ImportApplication.AppName): Deployed to '$($syncHash.AppTestCollection)'"
        if (-not $syncHash.DryRun) {
            try {
            
                New-CMApplicationDeployment -Name $ImportApplication.AppName -CollectionName $syncHash.AppTestCollection `
                    -DeployAction Install -DeployPurpose Available -UserNotification DisplayAll `
                    -UpdateSupersedence $ImportApplication.UpdateSupersedence `
                    -TimeBaseOn LocalTime -AvailableDateTime (Get-Date) | Out-Null
            }
            catch {
                $Error[0] | Out-Host
                Write-Worklog -syncHash $syncHash -Text "$($ImportApplication.AppName): Error deploying to $($syncHash.AppTestCollection)"
                return $true
            }
        }
    }
    return $true # Success
}