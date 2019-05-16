function Get-SCCMCollectionInfo {
    param(
        $SiteServer,
        $Namespace,
        $CollectionID,
        $CollectionName
    )
    if (-not ([string]::IsNullOrEmpty($CollectionID))) {
        $Filter = "CollectionID = '$CollectionID'"
    }
    else {
        $Filter = "Name = '$CollectionName'"
    }
    Get-WmiObject -ComputerName $SiteServer -Namespace $Namespace -Class 'SMS_Collection' -Filter $Filter
}