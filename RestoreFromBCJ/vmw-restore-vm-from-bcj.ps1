param([string]$VMName) #Accept variable VM name from Orchestrator

#Alternate VM Recovery Mode - Typically used for testing should the original VM still exist in the environment
$extendedName = "_recovered" #COMMENT THIS LINE FOR RECOVERY WITH ORIGINAL VM NAME.
$recoveryVMName = $VMName + $extendedName #COMMENT THIS LINE FOR RECOVERY WITH ORIGINAL VM NAME.

#Original VM Recovery Mode
#$recoveryVMName = $VMName #UNCOMMENT THIS LINE FOR RECOVERY WITH ORIGINAL VM NAME.

Write-Host $VMName

#Please Update the .csv for your environment
$vbrCSV = "C:\VRO\CSVs\vmw-restore-from-bcj.csv" #CSV File to read from.
$hostInfo = Import-Csv $vbrCSV

#For backup copy job backup data, local repository
$job = Get-VBRBackupCopyJob -Name $hostInfo.backupcopyjobname
$backup = Get-VBRBackup | Where-Object {$_.JobId -eq $job.Id}

Write-Host "VM to restore: " $recoveryVMName

#For backup copy job restore point
$restorePoint = Get-VBRRestorePoint -Name $VMName -Backup $backup | Sort-Object -Property CreationTime -Descending | Select-Object -First 1

Write-Host "Backup Restore Point: " $restorepoint.CreationTime

$server = Get-VBRServer -Type ESXi -Name $hostInfo.host

Write-Host "ESX Host: " $server.Name

$pool = Find-VBRViResourcePool -Server $server -Name $hostInfo.pool
$store = Find-VBRViDatastore -Server $server -Name $hostInfo.datastore
$folder = Find-VBRViFolder -Server $server -Name $hostInfo.folder
$network = Get-VBRViServerNetworkInfo -Server $server | Where-Object { $_.NetworkName -eq $hostInfo.network } #Disable for networkless recovery

#Instant VM Recovery w/ Power On (Note, to use -TargetNetwork, -SourceNetwork must also be specified, however does not function. Workaround with seperate plan script to add and connect NIC and power on.)
$restore = Start-VBRInstantRecovery -RestorePoint $restorepoint -VMName $recoveryVMName -Server $server -ResourcePool $pool -Datastore $store -Folder $folder -SourceNetwork @() -TargetNetwork $network -NICsEnabled:$true -PowerUp:$false -Force

Write-Host "Restore ID: " $restore.Id

$session = Get-VBRInstantRecovery -Id $restore.Id
$migrate = Start-VBRViInstantRecoveryMigration -InstantRecovery $session -Server $server -ResourcePool $pool -Datastore $store -Folder $folder -ForceVeeamQM -RunAsync

Write-Host "VM migration ID: " $migrate.Id

# Wait loop until Migration is complete
do {
    $migrationsession = Get-VBRInstantRecoveryMigration -Id $migrate.Id
    Start-Sleep -Seconds 15
} until ($migrationsession.State -eq "Stopped")

Stop-VBRInstantRecovery -InstantRecovery $session

Write-Host "VM restored into Resource Pool: " $pool
