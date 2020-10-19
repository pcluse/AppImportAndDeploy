<#
.Synopsis
   Get information about an PSADT application folder
.DESCRIPTION
   Long description
.EXAMPLE
    Get-ApplicationInformationFromSourceDirectory -Path '\\src.pc.lu.se\file$\Applikationer\Notepad++ 32-bit\7.5.4\'

    Name                   : Notepad++ 32-bit
    Version                : 7.5.4
    Path                   : \\src.pc.lu.se\file$\Applikationer\Notepad++ 32-bit\7.5.4\
    ParentPath             : \\src.pc.lu.se\file$\Applikationer\Notepad++ 32-bit
    IconPath               : \\src.pc.lu.se\file$\Applikationer\Notepad++ 32-bit\icon.png
    IsPSADT                : True
    VersionCheck           : False
    PSADTName              : Notepad++
    PSADTVersion           : 7.5.4
    PSADTVendor            : Notepad++
    PSADTRegistryDetection : False
    MSIInfo                :

.EXAMPLE

    Get-ApplicationInformationFromSourceDirectory -Path '\\src.pc.lu.se\file$\Applikationer\MinFinaMSIApp\18.5\'


    Name                   : MinFinaMSIApp
    Version                : 18.5
    Path                   : \\src.pc.lu.se\file$\Applikationer\MinFinaMSIApp\18.5\
    ParentPath             : \\src.pc.lu.se\file$\Applikationer\MinFinaMSIApp
    IconPath               : \\src.pc.lu.se\file$\Applikationer\MinFinaMSIApp\icon.png
    IsPSADT                : True
    VersionCheck           : False
    PSADTName              :
    PSADTVersion           :
    PSADTVendor            :
    PSADTRegistryDetection : False
    MSIInfo                : @{ProductCode={23170F69-40C1-2702-1805-000001000000}; ProductVersion=18.05.00.0}

#>

function Global:Get-ApplicationInformationFromSourceDirectory {
    param(
        $Path
    )
    $ParentPath = Split-Path -Path FileSystem::$Path -Parent
    try {      
        $AppInfo = New-Object PSObject
        $AppInfo | Add-Member 'Name'         (Split-Path -Path $ParentPath -Leaf)
        $AppInfo | Add-Member 'Version'      (Split-Path -Path $Path -Leaf) # TODO Handle revisons
        $AppInfo | Add-Member 'Path'         $Path
        $AppInfo | Add-Member 'ParentPath'   (Split-Path -Path $ParentPath -NoQualifier) # To remove FileSystem::
        $IconPath = Get-ChildItem -Path "$ParentPath\icon.*" -include *.png,*.jpg,*.ico | Select-Object -Last 1 -ExpandProperty FullName
        $AppInfo | Add-Member 'IconPath'     $IconPath
        $AppInfo | Add-Member 'IsPSADT'      (Test-Path -ErrorAction SilentlyContinue -Path "FileSystem::$Path\Deploy-Application.exe")
        $AppInfo | Add-Member 'VersionCheck' $false
        if ($AppInfo.IsPSADT) {
            #$AppInfo | Add-Member 'InstallCommandline' 'Deploy-Application.exe -DeploymentType "Install"'
            #$AppInfo | Add-Member 'UninstallCommandline' 'Deploy-Application.exe -DeploymentType "Uninstall"'
            $PSADTInfo = Get-PSADTInfo -Path $Path
            $AppInfo | Add-Member 'PSADTName'    $PSADTInfo.Name
            $AppInfo | Add-Member 'PSADTNameMangled'    $PSADTInfo.NameMangled
            $AppInfo | Add-Member 'PSADTVersion' $PSADTInfo.Version
            $AppInfo | Add-Member 'PSADTVendor'  $PSADTInfo.Vendor
            $AppInfo | Add-Member 'PSADTRegistryDetection' $PSADTInfo.RegistryDetection
            $AppInfo | Add-Member 'RunAsAdmin' $PSADTInfo.RunAsAdmin
        }
        else {
            #$AppInfo | Add-Member 'InstallCommandline' 'Need to change this'
            #$AppInfo | Add-Member 'UninstallCommandline' 'Need to change this'
            $AppInfo | Add-Member 'PSADTName'    ''
            $AppInfo | Add-Member 'PSADTVersion' ''
            $AppInfo | Add-Member 'PSADTVendor'  ''
            $AppInfo | Add-Member 'PSADTRegistryDetection' $false
            $AppInfo | Add-Member 'RunAsAdmin' $false
        }

        $AppInfo | Add-Member 'MSIInfo' (Get-ChildItem -ErrorAction SilentlyContinue -LiteralPath "FileSystem::$Path\Files" -Filter '*.msi' | ForEach-Object {
         <#Write-Debug $_; #>Get-MsiTableContents -Path $_.FullName | Select-Object 'ProductCode','ProductVersion'
        })

        if ((Get-ChildItem -Path $ParentPath -Filter 'VersionCheck.xml')) {
            $AppInfo.VersionCheck = $true
        }
        $AppInfo
    
    } catch {
        Write-Debug "Error: $($Error[0])"
       return $null
    }
}