<#
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
        DoImport                      : True
        DeployToTestCollection        : True
        UpdateSupersedence            : False
        DeploymentUpdateSupersedence  : False
        UpdateDependencies            : False
        OnlyPlaceholderDetectionRule  : False
        UninstallPrevious             : False
        DestinationFolder             : .\Application\Test
        Name                          : MyFineTestApp
        Path                          : \\some-server\some-share\some-folder\MyFineTestApp\1.4
        AppName                       : MyFineTestApp v1.4
        InstallCommandline            : Deploy-Application.exe -DeploymentType "Install"
        UninstallCommandline          : Deploy-Application.exe -DeploymentType "Uninstall"
        TeamsPostImport               : True

    
    1) Ceates an application with name $ImportApplication.AppName and version $AppInfo.Version
        Copies LocalizedApplicationDescription, LinkText and UserDocumentation from previous version
    2) Creates a Script deployment with the name $ImportApplication $ImportApplication.AppName + " PSADT"
        Uses $ImportApplication.Path for content location
        $ImportApplication.InstallCommandline and $ImportApplication.UninstallCommandline for install/unistall commmands
    3) Detection rules (if OnlyPlaceholderDetectionRule not true )
        New rules for MSI in $AppInfo.MSI
        New rule if $AppInfo.PSADTRegistryDetection is true
        Copy rule for file version but change Between oldversion.0, oldversion.99999 to $AppInfo.Version.0,$AppInfo.Version.99999
            If AppInfo.Version is like x.x.x
        Otherwise copy rule for file version but change to $AppInfo.Version
        All other rules are copied from old version
    4) Add supersedence if older version found. Make previous version unistall if $ImportApplication.UninstallPrevious is true.
    5) Replace references to older deploymenttype if used in depency
    6) Distribute Application to Distribution Group
    7) Move the application to the folder specified in configuration
    8) Deploy it to a test collection if $ImportApplication.DeployToTestCollection is true
    9) Post the import to a teams channel if $ImportApplication.TeamsPostImport is true
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
    # TODO copy all DisplayInfo if there are more than one until then copy first one in list.
    #$info = $xml.AppMgmtDigest.ChildNodes.DisplayInfo.Info[0] GSR 2019-10-08. Funkar inte med [0]
    $xml.AppMgmtDigest.ChildNodes.DisplayInfo.Info | ForEach-Object {
        [PSCustomObject] @{
            Description = $_.Description
            InfoUrl = $_.InfoUrl
            InfoUrlText = $_.InfoUrlText
            Publisher = $_.Publisher # HIG-Modification. GSR 190906
        }
    }
}


function Global:Get-AppDeploymentTypeInteraction {
# HIG-Modification GSR 1900909. Copy previous deploymenttype info (UserInteraction). 
# https://www.reddit.com/r/SCCM/comments/a34v0l/powershell_getcmdeploymenttype/
# Kanske ska denna skapa ett object som Get-ApplicationDisplayInfo ovan. Samtidigt tror jag bara det var interaction som var intressant.

    param($Application)

    $DeploymentTypeName = "$($Application.LocalizedDisplayName) PSADT"
    [xml]$xml = ($Application | Get-CMDeploymentType -DeploymentTypeName $DeploymentTypeName | Select-Object SDMPackageXML).SDMPackageXML
    $deployTypeArgs =  $xml.ChildNodes.DeploymentType.Installer.InstallAction.Args.Arg
    $UserInteraction =  ($deployTypeArgs| Where-Object {$_.name -eq "RequiresUserInteraction"}).'#text'
    return $UserInteraction
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


<# HIG-Modification GSR 2019-10-08
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
#>

    if ($AppInfo.RunAsAdmin) {
        $RegHive = "HKEY_LOCAL_MACHINE"
    }
    else {
        $RegHive = "HKEY_CURRENT_USER"
    }
    # HIG-Modification GSR 2019-10-08
    $RegistryDetection = New-Object PSObject @{
        Key    = "Registry::$RegHive\" + (Get-Config -key 'RegDetectionKeyPath') + $appinfo.Name
        SubKey = (Get-Config -key 'RegDetectionKeyPath') + $appinfo.Name
        ValueName  = (Get-Config -key 'RegDetectionValueName')
        ValueData = $appinfo.Version
        ImportDate = (get-date).tostring("yyyy-MM-dd HH:mm:ss")
    }
    #Write-Worklog -syncHash $syncHash -Text "$($ImportApplication.AppName): Created registry detection object"

    If ($AppInfo.PSADTRegistryDetection) {
        # Must be in FileSystem location to crete file
        Push-Location -Path "C:"   
        $RegistryDetectionFile = $AppInfo.Path + "\RegistryDetectionData.json"
        $RegistryDetection |  ConvertTo-Json -Depth 10 | Out-File $RegistryDetectionFile -Force
        Pop-Location
        Write-Worklog -syncHash $syncHash -Text "$($ImportApplication.AppName): Add-SCCMDetection: Created registry detection json File in source folder"
    }


    $ImportedApplicationVersion = Get-Version $AppInfo.Version
    if ((Get-Config -key 'SkipExpired')) {
        $CMImportedApplications = Get-CMApplication -Name "$($ImportApplication.Name) v*" | Where-Object { -not $_.IsExpired }
    }
    else {
        $CMImportedApplications = Get-CMApplication -Name "$($ImportApplication.Name) v*"
    }
    
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
        if ($CMPreviousApplication.IsExpired) {
            Write-Todolog -syncHash $syncHash -Text "$($ImportApplication.AppName): Previous version is retired, need to manually set/fix supersedence!"
        }
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
            ReleaseDate      = Get-Date  # HIG-Modification. GSR 190906
        }
        If ($AppInfo.IconPath -ne $null) {
            $Args['IconLocationFile'] = $AppInfo.IconPath
        }

        # Copy Application Catalog info from previous version
        if (-not $isNewApplication) {
            <#
            $DisplayInfo = Get-ApplicationDisplayInfo -Application $CMPreviousApplication
            
            if (-not [string]::IsNullOrEmpty($DisplayInfo.InfoUrlText)) { $Args['LinkText'] = $DisplayInfo.InfoUrlText }
            if (-not [string]::IsNullOrEmpty($DisplayInfo.Description)) { $Args['LocalizedApplicationDescription'] = $DisplayInfo.Description }
            if (-not [string]::IsNullOrEmpty($DisplayInfo.InfoUrl)) { $Args['UserDocumentation'] = $DisplayInfo.InfoUrl }
            if (-not [string]::IsNullOrEmpty($DisplayInfo.Publisher)) { $Args['Publisher'] = $DisplayInfo.Publisher }     # HIG-Modification. GSR 190906
            #>

            # This solves the issue which prevented copying of multiple displayinfo

            $NewCMApplication = ($CMPreviousApplication | ConvertTo-CMApplication).Copy()
            $NewCMApplication.SoftwareVersion = $AppInfo.Version
            $NewCMApplication.Title = $ImportApplication.AppName
            $NewCMApplication.Name = $NewCMApplication.CreateNewId().Name
            $NewCMApplication.Contacts[0].Id = $env:USERNAME
            $NewCMApplication.Owners[0].Id = $env:USERNAME
            $NewCMApplication.ReleaseDate = (Get-Date)
            # TODO Change paths and ID of deploymenttype instead of making a new one
            $NewCMApplication.DeploymentTypes.RemoveAt(0)
            $NewCMApplication = $NewCMApplication | ConvertFrom-CMApplication
            $NewCMApplication.Put()
            # Make sure the new information is saved before reading it again
            Start-Sleep -Seconds 1
            $NewCMApplication = Get-CMApplication -Name $ImportApplication.AppName
            <#
            
            The following would also copy deploymenttype settings

            $newapp.DeploymentTypes | ForEach-Object { 
                $_.Name = $_.CreateNewId().Name
                $_.Title = $_.Title -replace $CMPreviousApplication.SoftwareVersion, $AppInfo.Version
                if (-not [string]::IsNullOrEmpty($ImportApplication.InstallCommandline)) {
                    $_.Installer.InstallCommandline = $ImportApplication.InstallCommandline
                }
                if (-not [string]::IsNullOrEmpty($ImportApplication.UninstallCommandline)) {
                    $_.Installer.UninstallCommandline = $ImportApplication.UninstallCommandline
                }
                $_.installer.Contents | ForEach-Object {
                    $_.ChangeId()
                }
            }
            #>
        }
        else {
            try {
                $Args | Out-Host
                $NewCMApplication = New-CMApplication @Args
            }
            catch {
                $Error[0] | Out-Host
                Write-Worklog -syncHash $syncHash -Text "$($ImportApplication.AppName): Error creating application"
                return $false
            }
        }
        
    }
    # TODO get description from previous version


    # Copy previous deploymenttype UserInteraction. HIG-Modification GSR 1900909
    $UserInteraction = "false"
    if (-not $isNewApplication) {
        $UserInteraction = Get-AppDeploymentTypeInteraction -Application $CMPreviousApplication
    }


    $DeploymentTypeName = "$($ImportApplication.AppName) PSADT"

    # Make a script deployment. Could not add detection rules here
    Write-Worklog -syncHash $syncHash -Text "$($ImportApplication.AppName): Added Scriptdeploymenttype $DeploymentTypeName"
    if (-not $syncHash.DryRun) {
        try {
            $AddCMScriptDeploymentTypeParameters = @{
                DeploymentTypeName = $DeploymentTypeName
                ContentLocation = $ImportApplication.Path
                ScriptLanguage = 'Powershell'
                ScriptText = "#"
                InstallationBehaviorType = 'InstallForSystem'
                LogonRequirementType = 'WhetherOrNotUserLoggedOn'
                EstimatedRuntimeMins = 10
                MaximumRuntimeMins = 120
                RebootBehavior = 'BasedOnExitCode'
            }

            if (-not ([string]::IsNullOrEmpty($ImportApplication.InstallCommandline))) {
                $AddCMScriptDeploymentTypeParameters.Add('InstallCommand',$ImportApplication.InstallCommandline)
            }
            if (-not ([string]::IsNullOrEmpty($ImportApplication.UninstallCommandline))) {
                $AddCMScriptDeploymentTypeParameters.Add('UninstallCommand',$ImportApplication.UninstallCommandline)
            }
            <#
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
            #>
            $NewCMApplication | Add-CMScriptDeploymentType @AddCMScriptDeploymentTypeParameters | Out-Null

            if (-not ([string]::IsNullOrEmpty($ImportApplication.RepairCommandline))) {
                # This is what we want to run but the cmdlet does not have this option yet
                #$AddCMScriptDeploymentTypeParameters.Add('RepairCommand',$ImportApplication.RepairCommandline)
                # This is what we run instead
                Write-Worklog -syncHash $syncHash -Text "$($ImportApplication.AppName): Set repaircommandline"
                $TempApplication = Get-CMApplication -Name $ImportApplication.AppName | Convert-CMApplication
                $TempApplication.DeploymentTypes[0].Installer.RepairCommandLine = $ImportApplication.RepairCommandline
                $TempApplication = $TempApplication | ConvertFrom-CMApplication
                $TempApplication.Put()
                $NewCMApplication = Get-CMApplication -Name $ImportApplication.AppName
            }

            # HIG-modification. GSR 190917. -RequireUserInteraction switch with add-cmscriptdeploymenttype, boolean with set-cmscriptdeploymenttype
            if ($UserInteraction -eq "true") {
                Write-Worklog -syncHash $syncHash -Text "$($ImportApplication.AppName): Set allow user interaction true"
                Set-CMscriptDeploymentType -Application $NewCMApplication -DeploymentTypeName $DeploymentTypeName -RequireUserInteraction $true
            }
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
    if (-not $ImportApplication.OnlyPlaceholderDetectionRule) {

<#        
        if ($AppInfo.PSADTRegistryDetection) {
            Write-Worklog -syncHash $syncHash -Text "Added SCCMDetection detection rule"
            $DetectionClause = New-CMDetectionClauseRegistryKeyValue -Hive LocalMachine -KeyName "Software\PLS\$($AppInfo.PSADTNameMangled)" `
                -Value -ValueName $null -ExpectedValue $AppInfo.PSADTVersion -PropertyType String -ExpressionOperator IsEquals
            $DetectionClauses.Add($DetectionClause) | Out-Null
        }
#>
        # HIG-Modification GSR 2019-10-08
        if ($AppInfo.PSADTRegistryDetection) {
            Write-Worklog -syncHash $syncHash -Text "$($ImportApplication.AppName): Added SCCMDetection detection rule"
            $DetectionClause = New-CMDetectionClauseRegistryKeyValue -Hive LocalMachine -KeyName "$($RegistryDetection.SubKey)" `
                -Value -ValueName $($RegistryDetection.ValueName) -ExpectedValue $($RegistryDetection.ValueData) -PropertyType String -ExpressionOperator IsEquals
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

                switch ($PreviousRule.Type) {
                    # GSR 2019-10-10 TOTO. Måste anapassas till nya Add-SCCM-detectionData
                    'RegistryKeyValue' {
                            #if ( $PreviousRule.KeyName -ne "Software\PLS\$($AppInfo.PSADTNameMangled)") {  # HIG-Modification GSR 2019-10-10
                            if ( $PreviousRule.KeyName -ne $($RegistryDetection.SubKey)) {
                                $Args['ExpectedValue'] = $Args['ExpectedValue'] -replace $CMPreviousApplication.SoftwareVersion,$AppInfo.Version
                                $DetectionClause = New-CMDetectionClauseRegistryKeyValue @Args
                                Write-Worklog -syncHash $syncHash -Text "$($ImportApplication.AppName): Added RegistryKeyValue detection rule with new ExpectedValue set to $($AppInfo.Version)"
                                #CheckAndWarnIfVersion -syncHash $syncHash -AppName $ImportApplication.AppName -DetectionRule $Args
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
    } # -not OnlyPlaceholderDetectionRule

    

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
    if (-not $isNewApplication -and $ImportApplication.UpdateSupersedence) {
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

    # Update references (dependency)
    if (-not $isNewApplication -and $ImportApplication.UpdateDependencies) {
        $CMDependentOnThisApp = $oldCMDeploymentType | Select-Object -ExpandProperty NumberOfDependentDTs
        if ($CMDependentOnThisApp) {
            Write-Worklog -syncHash $syncHash -Text "$($ImportApplication.AppName): There are $($CMDependentOnThisApp) app(s) which depend on the dploymenttype '$($oldCMDeploymentType.LocalizedDisplayName)'!"
            # Get all application relationships where this deploymenttype is the target (Applications dependent of this deploymenttype)
            Get-WmiObject -ComputerName (Get-Config -key 'SCCMSiteServer') -Namespace (Get-Config -key 'WMINamespace') -Query "SELECT * FROM SMS_AppDependenceRelation INNER JOIN SMS_ApplicationLatest ON SMS_AppDependenceRelation.FromApplicationCIID = SMS_ApplicationLatest.CI_ID WHERE SMS_AppDependenceRelation.ToDeploymentTypeCIID = '$($oldCMDeploymentType.CI_ID)'" | ForEach-Object -Begin { $i = 1 } -Process {
                $DependentAppName = $_.SMS_ApplicationLatest.LocalizedDisplayName

                # Get the name of the application to be able to fetch the deploymenttype
                #Write-Worklog -syncHash $syncHash -Text "$($ImportApplication.AppName) Dependency #$($i-1): '$DependentAppName'"

                # Get the deploymenttype
                $DependentDT = Get-CMDeploymentType -ApplicationName $DependentAppName

                # Get the dependency matching the name of the old application
                $DependentDT | Get-CMDeploymentTypeDependencyGroup | Where-Object { $_.GroupName -eq "$($AppInfo.Name)-autodep" } | ForEach-Object {
                    #Write-Worklog -syncHash $syncHash -Text "Fetching list of matching dependencies in depdencygroup '$($AppInfo.Name)-autodep'"
                    $DepGroup = $_
                    
                    Write-Worklog -syncHash $syncHash -Text "$($ImportApplication.AppName) Dependency #$($i-1): Adding dependency to '$DependentAppName'"
                    # Add the dependency
                    $DepGroup | Add-CMDeploymentTypeDependency -DeploymentTypeDependency (Get-CMDeploymentType -ApplicationName $ImportApplication.AppName) -IsAutoInstall $true

                    # Remove the old dependency of the old deploymenttype, if this is the last dependency in the group the group will also be removed
                    $DepGroup | Get-CMDeploymentTypeDependency | Where-Object { $_.LocalizedDisplayName -eq $oldCMDeploymentType.LocalizedDisplayName} | ForEach-Object {
                        Write-Worklog -syncHash $syncHash -Text "$($ImportApplication.AppName) Dependency #$($i-1): Removing '$($_.LocalizedDisplayName)' from '$($AppInfo.Name)-autodep'"
                        Remove-CMDeploymentTypeDependency -DeploymentTypeDependency $_ -InputObject $DepGroup -Force
                    }
                }
                $i++
            }
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

    # Handle Folder 
    if ($ImportApplication.DestinationFolder -ne '.\Application') {
        Write-Worklog -syncHash $syncHash -Text "$($ImportApplication.AppName): Moving application to folder $($ImportApplication.DestinationFolder)"
        $NewCMApplication | Move-CMObject -FolderPath $ImportApplication.DestinationFolder
    }

    # Deploy
    if ($ImportApplication.DeployToTestCollection) {      
        Write-Worklog -syncHash $syncHash -Text "$($ImportApplication.AppName): Deployed to '$($syncHash.AppTestCollectionName)'"
        if (-not $syncHash.DryRun) {
            try {
            
                New-CMApplicationDeployment -Name $ImportApplication.AppName -CollectionID $syncHash.AppTestCollectionID `
                    -DeployAction Install -DeployPurpose Available -UserNotification DisplayAll `
                    -UpdateSupersedence $ImportApplication.DeploymentUpdateSupersedence `
                    -TimeBaseOn LocalTime -AvailableDateTime (Get-Date) | Out-Null
            }
            catch {
                $Error[0] | Out-Host
                Write-Worklog -syncHash $syncHash -Text "$($ImportApplication.AppName): Error deploying to $($syncHash.AppTestCollectionID)"
                return $true
            }
        }
    }

    # Post on teams
    If ($ImportApplication.TeamsPostImport) {
        If ($CMPreviousApplication) {
            $SuperseededApplication = $CMPreviousApplication.LocalizedDisplayName
        }
        Else {
            $SuperseededApplication = "--"
        }

        $body = ConvertTo-Json -Depth 4 @{
            title = "$($ImportApplication.AppName) imported"
            text = "A new application was imported"
            sections = @(
                @{
                    title = 'Details'
                    facts = @(
                        @{
                        name = 'Superseeds'
                        value = $SuperseededApplication
                        },
                        @{
                        name = 'Who'
                        value = "$($env:USERDOMAIN)\$($env:USERNAME)"
                        }
                    )
                }
            )
        }
        try {
            Invoke-RestMethod -uri (Get-Config 'TeamsChannelUrl') -Method Post -body $body -ContentType 'application/json'
            Write-Worklog -syncHash $syncHash -Text "$($ImportApplication.AppName): Posted on Teams channel $($syncHash.TeamsChannelName)"
        }
        catch {
            Write-Todolog -syncHash $syncHash -Text "$($ImportApplication.AppName): Couldn't post on Teams channel $($syncHash.TeamsChannelName)"
        }
    }

    return $true # Success
}