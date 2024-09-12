param([string]$VMName)


Write-Host "VM to restore: " $VMName

# Get Nutanix cluster and proxy info from CSV file
# Please Update the nutanix-info.csv for your settings
$nutCSV = "C:\VRO\CSVs\nutanix-info.csv" #CSV File to read from.
$nutInfo =Import-Csv $nutCSV

# Set Nutanix Proxy Info
$vanIP=$nutInfo.prxIP
$vanUser=$nutInfo.prxUser
$vanPasswd=$nutInfo.prxPWD

Write-Host "Nutanix Proxy IP: " $vanIP

# Set Nutanix Cluster info

$ntnxUser=$nutInfo.clsUser
$ntnxPasswd=$nutInfo.clsPWD
$ntnxIP=$nutInfo.clsIP

Write-Host "Nutanix Cluster IP: " $ntnxIP

#
# Retrieve the first network defined by the referenced cluster ID
#
function getNetworkDefault($clusterID) {
    try {
        $ntnx_url = "https://$ntnxIP`:9440/PrismGateway/services/rest/v2.0/networks?includeOverlaySubnets=True&proxyClusterUuid=$clusterID"

        $req = Invoke-WebRequest -Uri $ntnx_url `
        -Method "Get" `
        -ContentType "application/json" `
        -UseBasicParsing `
        -Headers @{
            "Accept" = "application/json"
            "Authorization" = "Basic " + [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($ntnxUser+":"+$ntnxPasswd))
            }

        if ($req.StatusCode -eq 200) {
            $networks = ($req.Content | ConvertFrom-Json)
            foreach ($network in $networks.'entities') {
                return($network.'uuid')
            }
        }
        return $null
    }
    catch {
        write-host "Exception in getClusterDefaults: $PSItem"
        return $false
    }
}

#
# Retrieve the default storage container from the referenced cluster ID
#
function getStorageDefault($clusterID) {
    try {
        $ntnx_url = "https://$ntnxIP`:9440/PrismGateway/services/rest/v2.0/storage_containers?proxyClusterUuid=$clusterID"

        $req = Invoke-WebRequest -Uri $ntnx_url `
        -Method "Get" `
        -ContentType "application/json" `
        -UseBasicParsing `
        -Headers @{
            "Accept" = "application/json"
            "Authorization" = "Basic " + [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($ntnxUser+":"+$ntnxPasswd))
            }

        if ($req.StatusCode -eq 200) {
            $containers = ($req.Content | ConvertFrom-Json)
            foreach ($container in $containers.'entities') {
                if ($container.'name' -like "default-container-*"){
                    return($container.'storage_container_uuid')
                }

            }
        }
        return $null
    }
    catch {
        write-host "Exception in getClusterDefaults: $PSItem"
        return $false
    }
}

#
# Select the first non-Prism Central cluster ID and subsequently retrieve that cluster's
# first network and default storage container ID's
#
function getNTNXDefaults() {
    try {
        $ntnx_url = "https://$ntnxIP`:9440/PrismGateway/services/rest/v2.0/clusters/"

        $req = Invoke-WebRequest -Uri $ntnx_url `
        -Method "Get" `
        -ContentType "application/json" `
        -UseBasicParsing `
        -Headers @{
            "Accept" = "application/json"
            "Authorization" = "Basic " + [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($ntnxUser+":"+$ntnxPasswd))

        } `
        #-Body ($payload | ConvertTo-Json)

        if ($req.StatusCode -eq 200) {
            #find first non-Prism Central cluster to set as restore target
            $clusters = ($req.Content | ConvertFrom-Json)
            foreach ($cluster in $clusters.'entities') {
                $clusterID = $cluster.'uuid'
                if (($netDefault = getNetworkDefault($clusterID)) -ne $null) {
                    if (($storageDefault = getStorageDefault($clusterID)) -ne $null) {
                        return((@{"targetClusterID" = $clusterID; "targetNetworkID" = $netDefault; "targetContainerID"=$storageDefault}) )
                    }
                }
            }
        }
        return $null
    }
    catch {
        write-host "Exception in getNTNXDefaults: $PSItem"
        return $null
    }
}


# Skip SSL errors. We work with localhost only here, so not that critical.
# You may want to get thumbprint and specify it for a request for the security reasons.

add-type @"
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : ICertificatePolicy {
    public bool CheckValidationResult(
        ServicePoint srvPoint, X509Certificate certificate,
        WebRequest request, int certificateProblem) {
        return true;
    }
}
"@
$AllProtocols = [System.Net.SecurityProtocolType]'Ssl3,Tls,Tls11,Tls12'
[System.Net.ServicePointManager]::SecurityProtocol = $AllProtocols
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy

# Run proxy RestAPI login

$vanIn_url = "https://$vanIP/api/oauth2/token"
$vanIn = Invoke-WebRequest -Uri $vanIn_url `
-Method "Post" `
-ContentType "application/x-www-form-urlencoded" `
-UseBasicParsing `
-Headers @{
    "Accept" = "application/json"
} `
-Body "grantType=Password&userName=$vanUser&password=$vanPasswd&refreshToken=&updaterToken=&longLivedRefreshToken=false"

$loginInfo = $vanIn.Content | ConvertFrom-Json

Write-Host "Logged into Nutanix Proxy"

$proxyToken = $loginInfo[0].'accessToken'

# Retrieve JWT token for db provider authentication

$thumbprint = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Veeam\AHV").Thumbprint
$VeeamAuthPath = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Veeam\Veeam Backup and Replication\Plugins\12.0.0\Console\AHV").InstallationPath.replace('Console', 'Service') + "VeeamAuth.exe"

$result = &"$VeeamAuthPath" "/purpose:DATA" "/clientCertificateThumbprint:$thumbprint" "/platformId:{799A5A3E-AE1E-4EAF-86EB-8A9ACC2670E2}"
$jwt_token = ($result -match "JWT=.*").Substring(4).Replace('\r\n','')


# Filter available restore points per specified VM name returning the last == most point

$rtnPoint = Get-VBRRestorePoint -Name $vmName | Sort-Object -Property CreationTime | Select-Object -Last 1

Write-Host "Restore Point ID: " $rtnPoint.Id

$point = $rtnPoint.Id

# Retrieve the required VM ID from the db provider restore point data

$rtnPoint_uri = "https://localhost:6172/api/vmRestorePoints/$point"
$rtnPoint_req = Invoke-WebRequest -Uri $rtnPoint_uri `
        -Method "GET" `
        -ContentType "application/json" `
        -UseBasicParsing `
        -Headers @{
            "authorization" = "Bearer $jwt_token";
            "x-api-version" = "1.0-rev41"
        }
            $vmInfo = $rtnPoint_req.Content | ConvertFrom-Json

$vmID = $vmInfo[0].objectTag.value
#
# Retrieve the required VM metadata from the db provider
#
        $vmData_uri = "https://localhost:6172/api/vmRestorePoints/$point/metadata"
        $vmData_req = Invoke-WebRequest -Uri $vmData_uri `
        -Method "GET" `
        -ContentType "application/json" `
        -UseBasicParsing `
        -Headers @{
            "authorization" = "Bearer $jwt_token";
            "x-api-version" = "1.0-rev41"
        }
            $vmData = $vmData_req.Content | ConvertFrom-Json

# Get Nutanix Defaults
if (($ntnxDefaults = getNTNXDefaults) -ne $null) {
    $clusterID = $ntnxDefaults.'targetClusterID'
    $tgtNetID = $ntnxDefaults.'targetNetworkID'
    $tgtSTGID = $ntnxDefaults.'targetContainerID'
    Write-Host "Nutanix defaults retrieved: `n"
    Write-Host "Cluster: $clusterID"
    Write-Host "Network: $tgtNetID"
    Write-HOST "Storage: $tgtSTGID"
} else {
    throw "AHV proxy login failed"
}

#
# Launch restore-to AHV operation
#

$p = @"
{"sourceVmId":"$($vmID)","sourceVmName":"$($vmName)","targetVmClusterId":"$($clusterID)","targetVmName":"$($vmName)","restorePointId":"$($point)","storageContainerId":"","vmMetadata":{"disks":[
"@

# Populating disks
$disks = $vmData.'disks'.'members'
$diskCount = $disks.count
for($i=0; $i -lt $diskCount; $i++) {
    $p += @"
{"busType":"$($disks[$i].'bustype')","id":"$($disks[$i].'filename')",
"@
    if (0 -ne $disks[$i].'diskIndexOnBus') {
        $p += @"
        "index": $($disks[$i].'diskIndexOnBus'),
"@
    }
    $p += @"
"diskLabel":"","isCdrom":false,"isVolumeGroup":false,"size":$($disks[$i].'capacity'),"storageContainerId":"$($tgtStgID)","storageContainerName":""}
"@
    if (($i+1) -ne $diskCount) { $p += "," }
}

$p += @"
],"networkAdapters":[],"networks":[],"vmCreationConfig":"{\"boot\":{\"boot_device_type\":null,\"disk_address\":{\"device_bus\":\"$($disks[0].'bustype')\",\"device_index\":0,\"ndfs_filepath\":null,\"vmdisk_uuid\":null,\"volume_group_uuid\":null,\"disk_label\":null,\"device_uuid\":null,\"is_cdrom\":false},\"mac_addr\":null,\"boot_device_order\":null,\"hardware_virtualization\":false,\"secure_boot\":false,\"uefi_boot\":false},\"uuid\":null,\"description\":null,\"memory_mb\":$(([long]($vmData.'totalMemoryBytes')/1MB)),\"name\":\"$($vmName)\",\"machine_type\":null,\"num_cores_per_vcpu\":$($vmData.'coresPerCpuCount'),\"num_vcpus\":$($vmData.'cpuSocketsCount'),\"vm_disks\":[
"@

# Populating vm_disks
for($i=0; $i -lt $diskCount; $i++) {
    $p += @"
{\"disk_address\":{\"device_bus\":\"$($disks[0].'bustype')\",\"device_index\":$($disks[$i].'diskIndexOnBus'),\"ndfs_filepath\":null,\"vmdisk_uuid\":null,\"volume_group_uuid\":null,\"disk_label\":null,\"device_uuid\":null,\"is_cdrom\":false},\"is_cdrom\":false,\"is_empty\":false,\"is_scsi_passthrough\":true,\"is_thin_provisioned\":false,\"flash_mode_enabled\":false,\"vm_disk_clone\":null,\"vm_disk_create\":null,\"size\":$($disks[$i].'capacity'),\"storage_container_uuid\":\"$($tgtStgID)\",\"vm_disk_clone_external\":null,\"vm_disk_passthru_external\":null,\"datasource_uuid\":null,\"is_hot_remove_enabled\":false,\"shared\":false,\"source_disk_address\":null}
"@
    if (($i+1) -ne $diskCount) { $p += "," }
}

$p += @"
],\"vm_nics\":[{\"adapter_type\":\"E1000\",\"mac_address\":null,\"model\":null,\"network_uuid\":\"$($tgtNetID)\",\"ip_address\":null,\"request_ip\":null,\"requested_ip_address\":null,\"ip_addresses\":null,\"is_connected\":true,\"nic_uuid\":null,\"port_id\":null,\"vlan_mode\":null}],\"vm_customization_config\":null,\"affinity\":null,\"vm_features\":null}"},"networkAdapters":[],"powerOnVmAfterRestore":false,"disconnectNetworksAfterRestore":false,"reason":"","initiator":"Veeam Skunkworks automation"}
"@

            #$payload = ($p | ConvertTo-Json -Depth 5)
            $payload = $p

            $restoreURL = "https://$vanIP/api/v6/restorePoints/anyToAhvRestore"

            $restore_req = Invoke-WebRequest -Uri $restoreURL `
                -Method "Post" `
                -ContentType "application/json" `
                -UseBasicParsing `
                -Headers @{
                    "authorization" = "Bearer $proxyToken";
                    "Accept" = "*/*"
                } `
                -Body $payload

            if ($restore_req.StatusCode -eq 202) {
                Write-Host "RestoreTo AHV started"
                $restore1 = $restore_req | ConvertFrom-Json
                Write-Host "Restore session ID: " $restore1
            }
            else {
                Write-Host "RestoreTo AHV failed - " $restore_req.StatusCode
            }

$res1 = $restore_req | ConvertFrom-Json
$sessID = $res1.sessionId
            
$sess_URL = "https://$vanIP/api/v5/sessions/$sessID"
            
do {
    $sess_req = Invoke-WebRequest -Uri $sess_URL `
                -Method "Get" `
                -Headers @{
                            "authorization" = "Bearer $proxyToken";
                        }
            
    $sess1 = $sess_req | ConvertFrom-Json
    Start-Sleep -Seconds 15
} until ($sess1.status -eq 'Success')
            
Write-Host "Restore session result: " $sess1.result 
            
            