param([string]$VMName) #Accept variable VM name from Orchestrator

#Alternate VM Recovery Mode - Typically used for testing should the original VM still exist in the environment
$extendedName = "_recovered" #COMMENT THIS LINE FOR RECOVERY WITH ORIGINAL VM NAME.
$recoveryVMName = $VMName + $extendedName #COMMENT THIS LINE FOR RECOVERY WITH ORIGINAL VM NAME.

#Original VM Recovery Mode
#$recoveryVMName = $VMName #UNCOMMENT THIS LINE FOR RECOVERY WITH ORIGINAL VM NAME.

#Please Update the vbr-info.csv for your settings
$vmwCSV = "C:\VRO\CSVs\vmw-poweron-vm.csv" #CSV File to read from.
$vmwInfo =Import-Csv $vmwCSV

#Connect to vCenter Server
Write-Host "Connecting to VMware vCenter Server: " $vmwInfo.server
Set-PowerCLIConfiguration -Scope User -ParticipateInCEIP $False -InvalidCertificateAction Ignore -Confirm:$False
$vmwConn = Connect-VIServer -Server $vmwInfo.server -Protocol https -User $vmwInfo.user -Password $vmwInfo.passwd

Write-Host "Connected to: " $vmwConn.Name "-" $vmwConn.Port

$recoveredVM = Get-VM -Name $recoveryVMName

#Check stats of VM and power on if not running
if ($recoveredVM.PowerState -eq "PoweredOff") {
    Start-VM -VM $recoveryVMName
    Write-Host "VM $($recoveryVMName) is $($recoveredVM.PowerState)"
    
    # Wait loop until VM is Powered On
    do {
        $recoveredVM = Get-VM -Name $recoveryVMName
        Start-Sleep -Seconds 15
    } until ($recoveredVM.PowerState -eq "PoweredOn")
    
    Write-Host "VM $($recoveredVM.Name) is $($recoveredVM.PowerState)"
} else {
    Write-Host "VM $($recoveredVM.Name) is already powered on."
}

Write-Host "`nDisconnecting from servers"
Disconnect-VIServer -Server $vmwInfo.server -Confirm:$False