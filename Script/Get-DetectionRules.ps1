<#
.Synopsis
    Get detection rules for an application
.DESCRIPTION
    Returns the detection rules for an application with one deploymenttype
    They are returned as PSObjects with the same arguments as used by
    New-CMDetectionClauseXXXX. Which XXXX to be used is in the field Type
    which should be removed before splatting.

    If the parsing fails or it encounters some not yet implemented function
    will it throw an exception
.EXAMPLE
    Get-DetectionRules -ApplicationName "MinFinaMSIApp v18.5"

    Name                           Value
    ----                           -----
    Value                          True
    ProductCode                    {23170f69-40c1-2702-1805-000001000000}
    ExpressionOperator             IsEquals
    Type                           WindowsInstaller
    ExpectedValue                  18.05.00.0
    PropertyType                   ProductVersion

    Is64Bit                        False
    ExpressionOperator             IsEquals
    ExpectedValue                  10.5.1.7333
    FileName                       ArcCatalog.exe
    Type                           File
    Value                          True
    Path                           %ProgramFiles(x86)%\ArcGIS\Desktop10.5\bin
    PropertyType                   Version
#>

function Global:Get-DetectionRules {

    param(
        $ApplicationName
    )

    [System.Collections.ArrayList]$detectionRules = @()

    $dt = Get-CMDeploymentType -ApplicationName $ApplicationName

    $dtCount = ($dt | Measure-Object).Count
    if ($dtCount -ne 1) {
        # Hmmm??? Throw exception, use the first one or just ignore
        throw "Wrong number of deployment types = $dtCount"           
    }

    If ($dt.SDMPackageXML -eq '') {
        # Hmmm??? W3D3 Excel 2013 Addin v5.3.1 had this one empty
        throw "Not a script installer"
    }

    $xmlDeploymentType = [xml]$dt.SDMPackageXML
    # Get it with named attribute instead
    $xmlString = ($xmlDeploymentType.AppMgmtDigest.ChildNodes.Installer.DetectAction.Args.SelectNodes("*[@Name='MethodBody']").'#text')
    $xml = [xml]$xmlString

    

    Function Get-Setting($settingName) {
        Write-Debug "Setting: $settingName"
        $xml.EnhancedDetectionMethod.Settings.SelectNodes("*[@LogicalName='$settingName']")
    }

    Function Get-ExpectedValue($expression) {
        if ($expression.Operator -in "Between","OneOf","NoneOf") {
            $expression.Operands.ConstantValueList.ConstantValue.Value
        }
        else {
            $expression.Operands.ConstantValue.Value
        }
    }

    Function Convert-HiveName($HiveName) {
        switch ($HiveName) {
            "HKEY_LOCAL_MACHINE" { $Hive = "LocalMachine" }
            default { throw "Unimplemented Hive $HiveName" }
        }
        return $Hive
    }

    Function Convert-Operator($OperatorName) {
        # Stupid really all but Equals is called the same :/
        If ($OperatorName -eq "Equals" ) {
            "IsEquals"
        }
        else {
            $OperatorName
        }
    }

    Function Convert-ExpressionRegistry($expression) {
        Write-Debug "Expression Registry"
        $settingName = $expression.Operands.SettingReference.SettingLogicalName
        $setting = Get-Setting $settingName

        $Hive = Convert-HiveName $setting.RegistryDiscoverySource.Hive
        

        $KeyName = $setting.RegistryDiscoverySource.Key
        $ValueName =  $setting.RegistryDiscoverySource.ValueName
        # To specify default value must New-CMDetectionClauseRegistryKeyValue use -ValueName $null
        if ($ValueName -eq '') {
            $ValueName = $null
        }
        $Is64Bit = $setting.RegistryDiscoverySource.Is64Bit -eq 'true'
        $PropertyType = $expression.Operands.SettingReference.DataType

        if ( $expression.Operands.SettingReference.PropertyPath -eq 'RegistryValueExists' ) {
            # Existence
            # Strange. PropertyType is boolean but on the commandline for New-CMDetectionClauseRegistryKeyValue
            # can you only put Version, Integer, String so I just fake it and put String here
            $detectionRules.Add([psobject]@{
                Type = "RegistryKeyValue"
                Hive = $Hive
                Is64Bit = $Is64Bit
                KeyName = $KeyName
                PropertyType = "String"
                ValueName = $ValueName
                Existence = $true
            }) | Out-Null
        }
        else {
            $detectionRules.Add([psobject]@{
                Type = "RegistryKeyValue"
                ExpressionOperator = Convert-Operator $expression.Operator
                Hive = $Hive
                Is64Bit = $Is64Bit
                KeyName = $KeyName
                PropertyType = $PropertyType
                ValueName = $ValueName
                ExpectedValue = Get-ExpectedValue $expression
                Value = $true
            }) | Out-Null
        }
    }

    Function Convert-ExpressionRegistryKey($expression) {
        Write-Debug "Expression RegistryKey"
        $settingName = $expression.Operands.SettingReference.SettingLogicalName
        $setting = Get-Setting $settingName

        $Hive = Convert-HiveName $setting.Hive
        
        $detectionRules.Add([psobject]@{
            Type = "RegistryKey"
            Existence = $true
            Hive = $Hive
            Is64Bit = $setting.Is64Bit -eq 'true'
            KeyName = $setting.RegistryDiscoverySource.Key
        }) | Out-Null

    }

    Function Convert-ExpressionFile($expression) {
        Write-Debug "Expression File"
        $settingName = $expression.Operands.SettingReference.SettingLogicalName
        $setting = Get-Setting $settingName

        $Path = $setting.Path
        $FileName = $setting.Filter
        $Is64Bit = $setting.Is64Bit -eq 'true'
       
        If ($expression.Operands.SettingReference.Method -eq 'Count') {
            # Existence
            $detectionRules.Add([psobject]@{
                Type = "File"
                FileName = $FileName
                Is64Bit = $Is64Bit
                Path = $Path
                Existence = $true
            }) | Out-Null
        }
        else {
            $detectionRules.Add([psobject]@{
                Type = "File"
                FileName = $FileName
                PropertyType = $expression.Operands.SettingReference.PropertyPath
                ExpectedValue = Get-ExpectedValue $expression
                ExpressionOperator = Convert-Operator $expression.Operator
                Is64Bit = $Is64Bit
                Path = $Path
                Value = $true
            }) | Out-Null
        }
    }

    

    Function Convert-ExpressionFolder($expression) {
        Write-Debug "Expression Folder"
        $settingName = $expression.Operands.SettingReference.SettingLogicalName
        $setting = Get-Setting $settingName

        $Path = $setting.Path
        $FileName = $setting.Filter
        $Is64Bit = $setting.Is64Bit -eq 'true'
       
        If ($expression.Operands.SettingReference.Method -eq 'Count') {
            # Existence
            $detectionRules.Add([psobject]@{
                Type = "Directory"
                FileName = $FileName
                Is64Bit = $Is64Bit
                Path = $Path
                Existence = $true
            }) | Out-Null
        }
        else {
            $detectionRules.Add([psobject]@{
                Type = "Directory"
                FileName = $FileName
                PropertyType = $expression.Operands.SettingReference.PropertyPath
                ExpectedValue = Get-ExpectedValue $expression
                ExpressionOperator = Convert-Operator $expression.Operator
                Is64Bit = $Is64Bit
                Path = $Path
                Value = $true
            }) | Out-Null
        }
    }

    Function Convert-ExpressionMSI($expression) {
        Write-Debug "Expression MSI"
        $settingName = $expression.Operands.SettingReference.SettingLogicalName
        $setting = Get-Setting $settingName
        $ProductCode = $setting.ProductCode

        If ($expression.Operands.SettingReference.Method -eq 'Count') {
            # Existence
            $detectionRules.Add([psobject]@{
                Type = "WindowsInstaller"
                ProductCode = $ProductCode
                Existence = $true
            }) | Out-Null
        }
        else {
            # value
            $detectionRules.Add([psobject]@{
                Type = "WindowsInstaller"
                ExpectedValue = $expression.Operands.ConstantValue.Value
                ExpressionOperator = Convert-Operator $expression.Operator
                ProductCode = $ProductCode
                PropertyType = $expression.Operands.SettingReference.PropertyPath
                Value = $true
            }) | Out-Null
        }
    }

    Function Convert-Expression($expression) {
        switch ($expression.Operands.SettingReference.SettingSourceType) {
            'Registry' { Convert-ExpressionRegistry $expression }
            'RegistryKey' { Convert-ExpressionRegistryKey $expression }
            'File' { Convert-ExpressionFile $expression }
            'Folder' { Convert-ExpressionFolder $expression }
            'MSI' { Convert-ExpressionMSI $expression }
            default { throw "Unknown SettingSourceType $($expression.Operands.SettingReference.SettingSourceType)" }
        }
    }



    $expression = $xml.EnhancedDetectionMethod.Rule.Expression
    if ($expression.Operator -eq 'Or') {
        throw "Cannot handle OR operator"
    }
    if ($expression.Operator -eq 'And') {
          $expression.Operands.Expression | Foreach-Object { Convert-Expression $_ }
    }
    else {
        Convert-Expression $expression
    }

    return $detectionRules
}
