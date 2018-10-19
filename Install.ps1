# Kopiera innehållet 'AdminConsole XML' till 'C:\Program Files (x86)\Microsoft Configuration Manager\AdminConsole'
Copy-Item -Path "$PSScriptRoot\AdminConsole XML\*" -Destination "${env:ProgramFiles(x86)}\Microsoft Configuration Manager\AdminConsole" -Recurse -Force

# Kopiera innehållet i 'Script' till 'C:\Program Files\SCCMExt'
$folder = "${env:ProgramFiles}\PLS\AppImportAndDeploy"
If (-not (Test-Path $folder)) {
    New-Item -Path $folder -ItemType Directory
}
Copy-Item -Path "$PSScriptRoot\Script\*" -Destination $folder -Recurse -Force