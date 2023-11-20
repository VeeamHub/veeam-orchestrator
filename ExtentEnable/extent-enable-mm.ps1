#Please Update the vbr-info.csv for your settings
$vbrCSV = "C:\VRO\Scripts\VBR\vbr-info.csv" #CSV File to read from.
$vbrInfo =Import-Csv $vbrCSV

$connVBR = Connect-VBRServer -Server $vbrInfo.vbrserver
Write-Output "SOBR selected: " $vbrInfo.repo

$scaleoutrepository = Get-VBRBackupRepository -Scaleout -Name $vbrInfo.repo

Write-Output "Capacity tier selected: " $scaleoutrepository.CapacityExtent.Repository.Name

$extent = Get-VBRRepositoryExtent -Repository $scaleoutrepository

Write-Output "Extent Status: " $extent[0].Status

$extentMM = Enable-VBRRepositoryExtentMaintenanceMode -Extent $extent[0]

Write-Output "Enable maintenance mode: " $extentMM.Result

$extent = Get-VBRRepositoryExtent -Repository $scaleoutrepository

Write-Output "Extent Status: " $extent[0].Status

Disconnect-VBRServer