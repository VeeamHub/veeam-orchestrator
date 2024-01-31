param([string]$VMName) #Accept variable VM name from Orchestrator

#Alternate VM Recovery Mode - Typically used for testing should the original VM still exist in the environment
$extendedName = "_recovered" #COMMENT THIS LINE FOR RECOVERY WITH ORIGINAL VM NAME.
$recoveryVMName = $VMName + $extendedName #COMMENT THIS LINE FOR RECOVERY WITH ORIGINAL VM NAME.

#Original VM Recovery Mode
#$recoveryVMName = $VMName #UNCOMMENT THIS LINE FOR RECOVERY WITH ORIGINAL VM NAME.

Write-Host $recoveryVMName

#Please Update the vbr-info.csv for your settings
$vmwCSV = "C:\VRO\CSVs\vmw-add-vm-network.csv" #CSV File to read from.
$vmwInfo =Import-Csv $vmwCSV

#Connect to vCenter Server
Write-Host "Connecting to VMware vCenter Server: " $vmwInfo.server
Set-PowerCLIConfiguration -Scope User -ParticipateInCEIP $False -InvalidCertificateAction Ignore -Confirm:$False
$vmwConn = Connect-VIServer -Server $vmwInfo.server -Protocol https -User $vmwInfo.user -Password $vmwInfo.passwd

Write-Host "Connected to: " $vmwConn.Name "-" $vmwConn.Port

#Set the network to attach - This uses Virtual Port Group you may need to use another method
#$portGrp = Get-VirtualPortgroup -Name $vmwInfo.network #Cmdlet being deprecated
$portGrp = Get-VDPortgroup -Name $vmwInfo.network


Write-Host "Network to connect: " $portGrp.Name "VlanID: " $portGrp.VLanId

#Add a NIC and attach - use VMNet3 type based on Info.csv
$networkAdd = New-NetworkAdapter -VM $recoveryVMName -Type $vmwInfo.nType -Portgroup $portGrp[0] -StartConnected

Write-Host "NIC: " $networkAdd.Name "type: " $networkAdd.Type

Write-Host "`nDisconnecting from servers"
Disconnect-VIServer -Server $vmwInfo.server -Confirm:$False