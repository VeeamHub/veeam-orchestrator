#Please Update the vbr-info.csv for your settings
$vbrCSV = "C:\VRO\Scripts\VBR\vbr-info.csv" #CSV File to read from.
$vbrInfo =Import-Csv $vbrCSV 

# Connect to VBR server defined in csv file
$connVBR = Connect-VBRServer -Server $vbrInfo.vbrserver
Write-Host "SOBR selected: $($vbrInfo.repo)"

# Get the SOBR defined in csv file
$scaleoutrepository = Get-VBRBackupRepository -Scaleout -Name $vbrInfo.repo

If ($null -eq $scaleoutrepository) {throw "no repository found. Please double-check vbr-info.csv"}

Write-Host "Capacity tier selected: $($scaleoutrepository.CapacityExtent.Repository.Name)"

# Get the Performance Extents from the SOBR
$extent = Get-VBRRepositoryExtent -Repository $scaleoutrepository

Write-Host "Number of Perfomance Extents: $($extent.Count)"

# Loop through the extents and write back current status
foreach($perfExt in $extent) {
   Write-Host "Checking Extent: " $perfExt.Name
   Write-Host "Extent Status: " $perfExt.Status
 
   $extentMM = Enable-VBRRepositoryExtentMaintenanceMode -Extent $perfExt
 
   Write-Output "Enable maintenance mode: " $extentMM.Result
 }

# Get status of Extents
$extentSts = Get-VBRRepositoryExtent -Repository $scaleoutrepository

# Loop through Extents and write back current status
foreach($perfsts in $extentsts) {
   Write-Host "Checking Extent: " $perfsts.Name
   Write-Host "Extent Status: " $perfsts.Status
 }

# Disconnect from Backup server
Disconnect-VBRServer