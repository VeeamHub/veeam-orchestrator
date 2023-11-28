#Please Update the vbr-info.csv for your settings
$vbrCSV = "C:\VRO\Scripts\VBR\vbr-info.csv" #CSV File to read from.
$vbrInfo =Import-Csv $vbrCSV

# Connect to VBR server defined in csv file
$connVBR = Connect-VBRServer -Server $vbrInfo.vbrserver
Write-Host "SOBR selected: $($vbrInfo.repo)"

# Get the SOBR defined in csv file
$scaleoutrepository = Get-VBRBackupRepository -Scaleout -Name $vbrInfo.repo

Write-Host "Capacity tier selected: $($scaleoutrepository.CapacityExtent.Repository.Name)"

# Get the Performance Extents from the SOBR
$extent = Get-VBRRepositoryExtent -Repository $scaleoutrepository

Write-Host "Extent Status: $($extent[0].Status)"

# Loop through the extents and write back current status
for ($i=0; $i -lt $extent.Length; $i++)
{
   Write-Host "Extent: $($extent.Name) is $($extent[$i].Status)"
}

# Loop through Extents and remove Maintenance Mode
for ($a=0; $a -lt $extent.Length; $a++)
{
    $extentMM = Disable-VBRRepositoryExtentMaintenanceMode -Extent $extent[$a]
}

# Get status of Extents
$extentSts = Get-VBRRepositoryExtent -Repository $scaleoutrepository

# Loop through Extents and write back current status
for ($b=0; $b -lt $extent.Length; $b++)
{
   Write-Host "Extent: $($extent.Name) is $($extentSts[$b].Status)"
}

# Disconnect from Backup server
Disconnect-VBRServer