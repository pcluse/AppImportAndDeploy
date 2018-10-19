
function Global:Get-Version($item) {
    $Version = ($_.Name -Split '-')[0]
    try {
        [System.Version]$Version
    }
    catch {
        $Version
    }
}

# Set-CMLocation

function Global:Get-NotImporteredApplications {
    param(
        $ApplicationFolder
    )
    $CurrentApplications = @{}

    Get-CMApplication -Fast | ForEach-Object {
        $CurrentApplications[$_.LocalizedDisplayName] = $true
    }

    Get-ChildItem -Path FileSystem::$ApplicationFolder -Directory | ForEach-Object {
        $AppName = $_.Name
        $Path = $_.FullName
        Get-ChildItem -Path FileSystem::$Path -Directory | ForEach-Object {

            $Version = ($_.Name -split '-')[0]
            $NameAndVersion = "$AppName v$Version"
            If ( -not $CurrentApplications[$NameAndVersion] ) {
                New-Object psobject -Property @{
                    Name = $AppName
                    Version = $Version
                    NameAndVersion = $NameAndVersion
                    Path = $_.FullName
                }
            }
        }
    }
}

# $ApplicationFolder = '\\src.pc.lu.se\file$\Applikationer'

# Get-NotImporteredApplications $ApplicationFolder