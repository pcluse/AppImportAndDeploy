function Global:Set-CMLocation {
    param(
        $SiteCode = $(Get-ItemProperty -ErrorAction SilentlyContinue -Path "Registry::HKEY_CURRENT_USER\Software\Microsoft\ConfigMgr10\AdminUI\MRU\1" -Name SiteCode | Select-Object -ExpandProperty SiteCode),
        $ProviderMachineName = $(Get-ItemProperty -ErrorAction SilentlyContinue -Path "Registry::HKEY_CURRENT_USER\Software\Microsoft\ConfigMgr10\AdminUI\MRU\1" -Name ServerName | Select-Object -ExpandProperty ServerName)
    )
    #Write-CMLogEntry -Severity 1 -Value "Set-CMLocation Start"
    # Customizations
    $initParams = @{}
    #$initParams.Add("Verbose", $true) # Uncomment this line to enable verbose logging
    $initParams.Add("ErrorAction", "Stop") # Uncomment this line to stop the script on any errors

    # Do not change anything below this line

    # Import the ConfigurationManager.psd1 module 
    if((Get-Module ConfigurationManager) -eq $null) {
        #Write-CMLogEntry -Severity 1 -Value "Import-Module $($ENV:SMS_ADMIN_UI_PATH)\..\ConfigurationManager.psd1"
        Import-Module -Scope Global "$($ENV:SMS_ADMIN_UI_PATH)\..\ConfigurationManager.psd1" -ErrorAction Ignore
    }

    # Connect to the site's drive if it is not already present
    if((Get-PSDrive -Name $SiteCode -PSProvider CMSite -ErrorAction SilentlyContinue) -eq $null) {
        #Write-CMLogEntry -Severity 1 -Value "Creating PSDrive"
        New-PSDrive -Name $SiteCode -PSProvider CMSite -Root $ProviderMachineName @initParams
    }

    # Set the current location to be the site code.
    #Write-CMLogEntry -Severity 1 -Value "Set-CMLocation to $($SiteCode):\"
    Set-Location "$($SiteCode):\" @initParams
    #Write-CMLogEntry -Severity 1 -Value "Set-CMLocation End"
}
