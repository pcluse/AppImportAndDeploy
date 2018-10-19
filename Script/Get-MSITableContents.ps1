function Global:Get-MSITableContents {
    param(
        [ValidateScript({Test-Path -Path "FileSystem::$_"})]
        [ValidateNotNullOrEmpty()]
        [string]$Path,
        [ValidateNotNullOrEmpty()]
        [string]$Query = "SELECT * FROM Property"
    )
    begin {
        try {
            $comWI = New-Object -ComObject WindowsInstaller.Installer 
        } catch { throw "Failed to init WindowsInstaller-object." }
    }
    process {
        try {
            $MSIDatabase = $comWI.GetType().InvokeMember(
                "OpenDatabase",
                "InvokeMethod",
                $null,
                $comWI,
                @($Path,0)
            )
        } catch {throw "Failed to open database."}
        $MSIView = $MSIDatabase.GetType().InvokeMember(
            "OpenView",
            "InvokeMethod",
            $null,
            $MSIDatabase,
            ($Query)
        )
        
        $MSIView.GetType().InvokeMember("Execute", "InvokeMethod", $Null, $MSIView, $Null) 
        $msi_props = New-Object PSObject
        while(($record = $MSIView.GetType().InvokeMember( 
                "Fetch", 
                "InvokeMethod", 
                $Null, 
                $MSIView, 
                $Null 
        ))) {
            $prop_name = $record.GetType().InvokeMember("StringData", "GetProperty", $Null, $record, 1) 
            $prop_value = $record.GetType().InvokeMember("StringData", "GetProperty", $Null, $record, 2)
            if (-not $prop_value) {
                $msi_props | Add-Member -MemberType NoteProperty 'Value' $prop_name
            }
            else {
                $msi_props | Add-Member -MemberType NoteProperty $prop_name $prop_value
            }
        }
    }
    end {
        $MSIView.Close()
        $msi_props
    }
}