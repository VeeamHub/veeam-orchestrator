param([string]$VMName)

Write-Host $VMName

$cTime = "CreationTime"
#Pick latest restore point and VM from backup job
$RestorePoint = Get-VbrRestorePoint -Name $VMName | Sort-Object -Property $cTime -Descending | Select-Object -First 1
Write-Host "RestorePoint:" $RestorePoint.Info.CommonInfo.CreationTimeUtc.Value "UTC"


$VMcpu = $RestorePoint.AuxData.NumCpus
Write-Host "VM CPU Cores:" $VMcpu "Cores"

$VMram = $RestorePoint.AuxData.MemSizeMb.InMegabytes
Write-Host "VM RAM:" $VMram "MB"

#Set the disk type based on vm disk
$VMdisk = Get-VBRFilesInRestorePoint -RestorePoint $RestorePoint | Where FileName -Like "*flat.vmdk*"
foreach ($disk in $VMdisk){
    [array]$VolumeConfig += New-VBRGoogleCloudComputeDiskConfiguration -DiskName $disk.FileName -DiskType StandardPersistent
}
Write-Host "VolumeInfo:" $VolumeConfig.DiskName "is of type:" $VolumeConfig.DiskType


Write-Host "Set GCP Info"
#Please Update the gcp-info.csv for your settings
$gcpCSV = "C:\VRO\Scripts\gcp-info.csv" #CSV File to read from.
$gcpInfo =Import-Csv $gcpCSV

#Set GPC Information
$account = Get-VBRGoogleCloudComputeAccount -Name $gcpInfo.account
$computeregion = Get-VBRGoogleCloudComputeRegion -Account $account -Name $gcpInfo.region
$computezone = Get-VBRGoogleCloudComputeZone -Region $computeregion -Name $gcpInfo.zone
$vpc = Get-VBRGoogleCloudComputeVPC -Account $account -Name $gcpInfo.VPC
$subnet = Get-VBRGoogleCloudComputeSubnet -Region $computeregion -VPC $vpc -Name $gcpInfo.subnet


Write-Host "Account:" $account.Name
Write-Host "Zone:" $computezone
Write-Host "VPC:" $vpc
Write-Host "Subnet:" $subnet


Write-Host "Matching equivelant compute machine type"

$machine = gcloud compute machine-types list --filter=guestCpus=$VMcpu, memoryMb=$VMram, zone=$computezone, isSharedCpu=true --format="json"

$machType = $machine | ConvertFrom-Json


$instancetype = Get-VBRGoogleCloudComputeInstanceType -Zone $computezone -Name $machType[0].name

Write-Host "Instance Type :" $instancetype

$label = New-VBRGoogleCloudComputeLabel -Key "backup" -Value "restore"


#Set Proxy Appliance Config
$ProxySize = Get-VBRGoogleCloudComputeInstanceType -Zone $computezone -Name $gcpInfo.prx
$ProxyConfig = New-VBRGoogleCloudComputeProxyAppliance -InstanceType $ProxySize -Subnet $subnet -RedirectorPort 443
Write-Host "ProxyConfig: " $ProxyConfig.InstanceType.Name

$restore = Start-VBRVMRestoreToGoogleCloud -RestorePoint $restorepoint -Zone $computezone -InstanceType $instancetype `
-VMName $VMname -DiskConfiguration $VolumeConfig -Subnet $subnet -Reason "Data recovery" `
-ProxyAppliance $ProxyConfig -GoogleCloudLabel $label

Write-Host "Recovering" $VMName

Write-Host "Restore Session ID: " $restore.Id

# Wait loop until restore is complete
$ErrorActionPreference = 'SilentlyContinue'
do {
    # Write-Host "checking for Instance"
    $instRecovered = gcloud compute instances list --filter="name=$VMname"
        Start-Sleep -Seconds 15
} until ($instRecovered -ne $null)
$ErrorActionPreference = 'Continue'


# Wait loop until Instance is Running
do {
    Write-Host "checking state"
    $instStatus = gcloud compute instances describe $VMname --format="json"
    $instState = $instStatus | ConvertFrom-Json
    Start-Sleep -Seconds 15
} until ($instState.status -eq "RUNNING")


Write-Host "IP: " $instState.networkInterfaces.networkIP

$dnsFile = "C:\VRO\Scripts\gpc-dnsinfo.csv" #CSV File to write server and IP into.

# Build aray to create CSV file entries for DNS updates
$dnsInfo = @(
    [pscustomobject]@{Server=$VMName;IP=[string]$instState.networkInterfaces.networkIP}
)

$dnsInfo | Export-Csv -Path $dnsFile -Append -NoTypeInformation

Write-Host "Data written to C:\VRO\Scripts\dnsinfo.csv"