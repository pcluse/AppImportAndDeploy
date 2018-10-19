<#
.Synopsis
   Get name, version, vendor and product code of an PSADT installation
.DESCRIPTION
   Reads name, version and vendor from Deploy-Application.ps1
   Also checks if Add-SCCMDetectionData is used
   Uses the same method as PSADT to get NameMangled which is AppName without spaces and illegal filename chars
.EXAMPLE
   Get-PSADTInfo -Path "Adobe Reader\18.0.0.1"

   Name: Adobe Reader
   NameMangled: AdobeReader
   Version: 18.0.0.1          
   Vendor: Adobe
   RegistryDetection: false

#>
Function Global:Get-PSADTInfo {
    Param(
        [string]
        $Path
    )
    $installScriptPath = Join-Path -Path $Path -ChildPath "Deploy-Application.ps1"
    if (-not (Test-Path -Path FileSystem::$installScriptPath)) {
        return $null
    }
    $content = Get-Content "FileSystem::$installScriptPath" -Raw

    $Name = ""
    $Vendor = ""
    $Version = ""
    $RegistryDetection = $false

    If ($content -match '.*\[string\]\$appName\s*=\s*''([^'']*)''') {
        $Name = $Matches[1]
    }
    If ($content -match '.*\[string\]\$appVendor\s*=\s*''([^'']*)''') {
        $Vendor = $Matches[1]
    }
    If ($content -match '.*\[string\]\$appVersion\s*=\s*''([^'']*)''') {
        $Version = $Matches[1]
    }
    If ($content -match '.*Add-SCCMDetectionData') {
        $RegistryDetection = $true
    }

    [char[]]$invalidFileNameChars = [IO.Path]::GetInvalidFileNameChars()
    [string]$NameMangled = $Name -replace "[$invalidFileNameChars]",'' -replace ' ',''

    $Object = New-Object PSObject -Property @{            
                Name      = $Name
                NameMangled = $NameMangled                 
                Version   = $Version            
                Vendor =  $Vendor
                RegistryDetection = $RegistryDetection
            }
    Write-Output $Object
}