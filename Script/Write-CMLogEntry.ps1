function Global:Write-CMLogEntry {
    # Original author Nikolaj Andersen 
	param(
		[parameter(Mandatory=$true, HelpMessage="Value added to the log file.")]
		[ValidateNotNullOrEmpty()]
		[string]$Value,
		[parameter(Mandatory=$true, HelpMessage="Severity for the log entry. 1 for Informational, 2 for Warning and 3 for Error.")]
		[ValidateNotNullOrEmpty()]
        [ValidateSet("1", "2", "3")]
		[string]$Severity,
		[parameter(Mandatory=$false, HelpMessage="Component for the log entry.")]
		[ValidateNotNullOrEmpty()]
		[string]$Component,
		[parameter(Mandatory=$false, HelpMessage="Component for the log entry.")]
		[ValidateNotNullOrEmpty()]
		[string]$LogPath = (Split-Path -Path $MyInvocation.ScriptName -Leaf),
		[parameter(Mandatory=$false, HelpMessage="Name of the log file that the entry will written to.")]
		[ValidateNotNullOrEmpty()]
		[string]$FileName = ($LogPath -replace '.ps1$','.log')
	)

	# Determine log file location
    if (Get-Variable -Name 'TSEnvironment' -Scope 'Script' -ErrorAction SilentlyContinue) {
        $LogFilePath = Join-Path -Path $Script:TSEnvironment.Value("_SMSTSLogPath") -ChildPath $FileName
    }
    else {
        <#
        try {
            $LogFilePath = Join-Path -Path "$env:SystemRoot\Logs\PLS" -ChildPath $FileName
            # Ensure parent folder exists
            $ParentFolder = Split-Path -Path $LogFilePath -Parent
            If (-not (Test-Path -Path $ParentFolder)) {
                New-Item -ErrorAction Stop -ItemType Directory -Path $ParentFolder -Force | Out-Null
            }
        } catch {
        #>
            $LogFilePath = Join-Path -Path $LogPath -ChildPath $FileName
            # Ensure parent folder exists
            $ParentFolder = Split-Path -Path $LogFilePath -Parent
            If (-not (Test-Path -Path $ParentFolder)) {
                New-Item -ErrorAction Stop -ItemType Directory -Path $ParentFolder -Force | Out-Null
            }
        #}
    }
    #Write-Debug $LogFilePath

    # Construct time stamp for log entry
    $Time = -join @((Get-Date -Format "HH:mm:ss.fff"), "+", (Get-WmiObject -Class Win32_TimeZone | Select-Object -ExpandProperty Bias))

    # Construct date for log entry
    $Date = (Get-Date -Format "MM-dd-yyyy")

    # Construct context for log entry
    $Context = $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)

    # Construct final log entry
    $LogText = "<![LOG[$($Value)]LOG]!><time=""$($Time)"" date=""$($Date)"" component=""$Component"" context=""$($Context)"" type=""$($Severity)"" thread=""$($PID)"" file="""">"

	# Add value to log file
    try {
        #Write-Debug "[$Time][$Component][$Severity] $Value"
	    Add-Content -Value $LogText -LiteralPath $LogFilePath -ErrorAction Stop
    }
    catch [System.Exception] {
        Write-Warning -Message "Unable to append log entry to '$LogFilePath' file"
    }
}