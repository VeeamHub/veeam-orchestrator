 [CmdletBinding()]
Param(
    [Parameter(Mandatory=$true)]
    [string]$GuestOSCredsUsername,

    [Parameter(Mandatory=$true)]
    [string]$GuestOSCredsPassword,

    [Parameter(Mandatory=$true)]
    [string]$vCenterServerCredsUsername,

    [Parameter(Mandatory=$true)]
    [string]$vCenterServerCredsPassword,

    [Parameter(Mandatory=$true)]
    [string]$vCenterServer,

    [Parameter(Mandatory=$true)]
    [string]$SourceVmName,

    [Parameter(Mandatory=$true)]
    [string]$VMName,

    [Parameter(Mandatory=$true)]
    [string]$VMOrigIP,

    [Parameter(Mandatory=$false)]
    $SudoRequired = 'true',

    [Parameter(Mandatory=$false)]
    $SudoPassRequired = 'true',

    [Parameter(Mandatory=$true)]
    [string]$ScriptPath
)

### Parameter examples for manual testing (without VRO)
# $GuestOSCredsUsername = "notroot"
# $GuestOSCredsPassword = "SecurePassword"
# $vCenterServerCredsUsername = "administrator@vsphere.local"
# $vCenterServerCredsPassword = "SecurePassword"
# $vCenterServer = "vcenter_server_fqdn"
# $SourceVmName = "web-1"
# $VMName = "web-1_replica"
# $VMOrigIP = "192.168.100.150"
# $SudoRequired = 'true'
# $SudoPassRequired = 'true'
# $ScriptPath = "c:\path\here"

Function Write-Log {
    param([string]$str)      
    Write-Host $str
    $dt = (Get-Date).toString("yyyy.MM.dd HH:mm:ss")
    $str = "[$dt] <$CurrentPid> $str"
    Add-Content $LogFile -value $str
}     

function PreReqs {
    Write-Log "`nChecking for PowerCLI installation"
    try{
        Import-Module VMware.VimAutomation.Sdk | Out-Null
        Import-Module VMware.VimAutomation.Common | Out-Null
        Import-Module VMware.VimAutomation.Cis.Core | Out-Null
        Import-Module VMware.VimAutomation.Core | Out-Null
        Write-Log "`tPowerCLI installed"
    } catch {
        Write-Log "Error: There was an error with the PowerCLI installation"
    } 
}

function GetPSCreds ($userName, $password) {    
    $secpwd = ConvertTo-SecureString $password -AsPlainText $true
    return New-Object System.Management.Automation.PSCredential($userName, $secpwd)
}

function ConnectVI ($Server, $Credential) {
    if ($null -eq $Credential) {
        Write-Log "`tError: Cannot connect to $server as no credentials were specified."
        return
    }

    Write-Log "`nConnecting to $Server using credentials ($($Credential.UserName))."
    $Server = Connect-VIServer $Server -Credential $Credential
    if ($null -eq $Server) {
        Write-Log "`tError: A connectivity issue has occurred when connecting to the vCenter server."
    }
}

function ConvertNetmaskToCidr {
    param (
        [string]$Netmask
    )

    # Validate input
    if (-not $Netmask -or -not $Netmask -match '^(?:\d{1,3}\.){3}\d{1,3}$') {
        throw "Invalid netmask format. Please provide a valid netmask (e.g., 255.255.255.0)."
        Write-Log "Error: Invalid netmask format. Please provide a valid netmask (e.g., 255.255.255.0)."
    }

    # Split the netmask into octets
    $octets = $Netmask -split '\.'

    # Ensure each octet is between 0 and 255
    if ($octets | Where-Object { $_ -lt 0 -or $_ -gt 255 }) {
        Write-Log "Error: Invalid octet(s) in the netmask. Each must be between 0 and 255."
        throw "Invalid octet(s) in the netmask. Each must be between 0 and 255."
    }

    # Convert each octet to binary and concatenate
    $binaryNetmask = ($octets | ForEach-Object { 
        [Convert]::ToString([int]$_, 2).PadLeft(8, '0')
    }) -join ''

    # Count the number of 1s in the binary representation
    $cidr = ($binaryNetmask -split '1').Count - 1

    # Return the CIDR as an integer
    return $cidr

}
function ApplyReIPRule ($SourceIpAddress, $ReIPRule) { 
    Write-Log "Applying re-ip rule to determine the target ip address"   
    $TargetIp = $ReIPRule
    for($i=1;$i -le 3; $i++) {
        [regex]$pattern  = "\*"
        if ($TargetIp.Split(".")[$i] -eq "*") { 
        $TargetIp = $pattern.Replace($TargetIp,$SourceIpAddress.Split(".")[$i],1) 
        }
    }
    $script:VMtarget.newIP = $TargetIp
    if ($VMtarget.newIP -ne '') {
        Write-Log "`n`tResults of ReIP Rule:`n`t`tSource IP: $($VMtarget.origIP)`n`t`tReIP Rule: $($VMtarget.reIPRule)`n`t`tTarget IP: $($VMtarget.newIP)"
    }
    else {
        Write-Log "`tERROR: Failed to determine the target IP address from the re-ip rule"
    }
}

function ParseInterfaceConfig ($vm, $netdevices, $ostype, $GuestCredential) {
    $count = 0

    #This is used to verify the updated IP on recheck after device modification
    Write-Log "`n`t`tVerification is set to: $($VMNicVerify)"

    #Retrieve device details and locate the source IP on device
    if ($ostype -eq "Linux") {
        $scripttype = "Bash"
        $devNames = $netdevices.Trim().Split("`n")
        foreach ($devName in $devNames){
            $devName = $devName.Trim()
            $scripttext = ''
            $output = ''
            if ($VMNicVerify -eq $false){
                Write-Log "`n`t`tDevice $($count + 1) = $devName"
            }
            $scripttext = "nmcli -t dev show $devName"
            if ($VMNicVerify -eq $false){
                Write-Log "`t`tRetrieving details for Device $($count + 1): `n`t`t`t$scripttext"
            }
            else {
                Write-Log "`t`tVerifying the details for $($VMNicName): `n`t`t`t$scripttext"
            }
            $output = Invoke-VMScript -VM $vm.Name -GuestCredential $GuestCredential -ScriptType $scripttype -ScriptText $scripttext
            Write-Log "`nDevice info:`n$output"
            $devProperties = $output.Split("`n")
            foreach ($property in $devProperties){
                $column = $property.Split(":")

                #iterate through properties and locate the device connection name
                if ($column[0].Trim() -like "*GENERAL.CONNECTION*"){
                    $connection = $column[1].Trim()
                }

                #iterate through properties and locate the device IPv4 address
                if ($column[0].Trim() -like "*IP4.ADDRESS*"){
                    $ip = ($column[1].Trim() -split ("/"))[0].Trim()
                    if ($VMNicVerify -eq $false){

                        #if source IP match is found, save the device name and connection name 
                        if ($ip -like $VMtarget.origIP){
                            $script:VMNicName = $devName
                            $script:VMNicConnection = $connection
                        }
                    }

                    #if verification succeeds on recheck, mark as success
                    else {
                        if ($ip -like $VMtarget.newIP){
                            $script:success = $true
                        }
                    }
                }
            }
            $count++
        }
        if($VMNicName -ne ''){
            #if target IP was verified on the recheck, output succes
            if ($success){
                Write-Log "`n`t`tUpdated IP on $($VMNicName) has been verified"
            }
            #if source IP was located on first run output the devicename
            else {
                Write-Log "`n`tMatching ip found on $($VMNicName)"
            }
        }
        #output warning if source IP was not located
        else {
            Write-Warning "`n`t`tDid not find a matching source IP"
        }
    }
    #Wrong OS
    else {
        Write-Log "Error: Incompatible OS"
    }
}

function GetVMNetworkInterface ($vm, $GuestCredential) {   
    $scripttype = ""
    $scripttext = ""
    
    $ostype = "Linux" 
    $vm_os = $vm.Guest.OSFullName
    if ($vm_os -like "*Windows*") { $ostype = "Windows" }
    
    if ($ostype -eq "Linux") { 
        $scripttype = "Bash"
        $scripttext = "nmcli -t -f device dev status"
    }

    #Get the list of network devices
    Write-Log "`tChecking VM network devices"
    Write-Log "`t`tInvoking script: `n`t`t`t$($scripttext)"
    $output = Invoke-VMScript -VM $vm.Name -GuestCredential $GuestCredential -ScriptType $scripttype -ScriptText $scripttext
    if ($null -ne $output) {
        if ($output -like "*Error*") {
            throw "Error: Unable to run Network Manager on this machine"
        }
        else {
            $script:VMNetDevices = $output
        }
    } 
}

function SetVMNetworkInterface ($vm, $connection, $ipaddress, $cidr, $gateway, $dns, $dns2, $GuestCredential) {
    $scripttype = ""
    $scripttext = ""
    $ostype = "Linux"
    
    #Check OS Type 
    $vm_os = $vm.Guest.OSFullName 
    if ($vm_os -like "*CentOS*") { $ostype = "CentOS" }
    if ($vm_os -like "*Red Hat*") { $ostype = "RedHat" }
    if ($vm_os -like "*Ubuntu*") { $ostype = "Ubuntu" }
    if ($vm_os -like "*Windows*") { $ostype = "Windows" }

    <#
        Checking the OS of the VM as designated in vSphere
        ** This can be modified if other Linux OS types have been configured to utilize Network Manager to manage network devices **
            Ex. add "-or ($ostype -like "*Debian*")" to the "if" statement
    #>
    if (($ostype -eq "CentOS") -or ($ostype -eq "RedHat") -or ($ostype -eq "Ubuntu")) { 
        $scripttype = "Bash"

        #Modify netowrk device settings
        $scripttext += "$($sudotext)nmcli con mod '$($connection)' ipv4.gateway $gateway "
        $scripttext += "&& $($sudotext)nmcli con mod '$($connection)' ipv4.address $($ipaddress)/$($cidr) "
        $scripttext += "&& $($sudotext)nmcli con mod '$($connection)' ipv4.method manual "
        $scripttext += "&& $($sudotext)nmcli con mod '$($connection)' ipv4.dns $dns "
        if ($dns2 -ne '') {
            $scripttext += "&& $($sudotext)nmcli con mod '$($connection)' +ipv4.dns $($VMtarget.secondaryDNS) "
        }

        #Restart device to apply changes
        $scripttext += "&& $($sudotext)nmcli con down '$($connection)' "
        $scripttext += "&& $($sudotext)nmcli con up '$($connection)'"
        Write-Log "`n`t`tInvoking ncmli ReIP script"
        $output = Invoke-VMScript -VM $vm.Name -GuestCredential $GuestCredential -ScriptType $scripttype -ScriptText $scripttext
        Write-Log "`n$output"
    }

    #Skip unsupported OS types
    elseif ($ostype -eq "Linux") { 
        #do nothing 
        Write-Log "``tERROR: Virtual Machine $($vm.Name) is running an unsupported operating system $($vm.Guest.OSFullName)."
    }
    elseif ($ostype -eq "Windows") { 
        #do nothing 
        Write-Warning "`tSkipped: Virtual Machine $($vm.Name) is running Windows and Re-IP can be processed by Veeam Backup & Replication."
    }
}

function UpdateVMIPAddresses ($VM, $GuestCredential){
    #Get the vSphere VM
    $_vm = Get-VM -Name $VM.ServerName
    
    #Get the list of network devices on the VM if it is accessible
    if ($null -ne $_vm) {
        GetVMNetworkInterface -VM $_vm -GuestCredential $GuestCredential
    }
    #If the VM is not accessible output an error
    else {
        Write-Log "Error: Virtual Machine $($VM.ServerName) is unavailable. Check parent server connections and permissions."
    }

    #Get the details for each network device and locate the matching source IP to a device
    ParseInterfaceConfig -vm $_vm -netdevices $VMNetDevices -ostype "Linux" -GuestCredential $GuestCredential
    
    #output the target configuration settings
    Write-Log "`n`tRe-IP settings:`n`t`tSource: $($VM.origIP)`n`t`tTarget: $($VM.newIP)`n`t`tSubnet: $($VM.newMask)`n`t`tGateway: $($VM.newGateway)"
    
    #Process the configuration if the source IP was located on a network device
    if ($VMNicName -ne ''){           
        $script:VMNicVerify = $true 
        Write-Log "`n`tProcessing: $($_vm.Name)`n`t`tinterface: $($VMNicName)`n`t`tsource: $($VMtarget.origIP)`n`t`ttarget: $($VM.newIP)"
        
        #Configure the device settings
        SetVMNetworkInterface -VM $_vm -Connection $VMNicConnection -IPAddress $VM.newIP -CIDR $VM.CIDR -Gateway $VM.newGateway -DNS $VM.primaryDNS -dns2 $VM.secondaryDNS -GuestCredential ($GuestCredential)            
        
        #Check for updated IP on selected device
        ParseInterfaceConfig -vm $_vm -netdevices $VMNicName -OSType "Linux" -guestcredential $GuestCredential        
        
        #If verification passed, output the success message
        if ($success){ 
            Write-Log "`n`tSuccess: Virtual Machine $($VM.ServerName) interface $($VMNicName) updated to $($VM.newIP)" 
        }
        #If failed, output error
        else { 
            Write-Log "Error: $($VM.ServerName) has not been modified"
        }    
    }
    #show error if the source IP was not found
    else {
        Write-Warning "`n`tWarning: Virtual Machine $($_vm.Name) does not contain network interfaces matching $($VM.origIP)"
    }
} 


#Log file
$Version = "0.0.1"

$LogDir = "$($scriptPath)\logs"
if (-not (Test-Path -Path $LogDir)) {
    New-Item -Path $LogDir -ItemType Directory
}
$LogFile = "$LogDir\$($SourceVmName)-UpdateIp.log"

Write-Log $("="*78)
Write-Log "{"
Write-Log "`tScript: $($MyInvocation.MyCommand.Name)"
Write-Log "`tVersion: { $($Version) }"
Write-Log "}"

#Script parameters for processing across functions
$VMNicName = ''
$VMNicConnection = ''
$VMNicVerify = $false
$VMNetDevices = ''
$success = $false
if ($SudoRequired -eq 'true') {
    if ($SudoPassRequired -eq 'true') {
        $sudotext = "echo $GuestOSCredsPassword | sudo -S "
    }
    else {
        $sudotext = "sudo "
    }
}
else {
    $sudotext = ''
}

#Read ReIP rules from json file
$VarFileName = "$($scriptPath)\logs\ReIpRules-$($SourceVmName).json"
$reiprules = Get-Content -Raw $VarFileName | ConvertFrom-Json



#Define VM parameters
$VMtarget = [pscustomobject]@{
    ServerName = $VMName;
    origIP = $VMOrigIP;
    reIPRule = $reiprules.TargetIp;
    newIP = '';
    CIDR = ConvertNetmaskToCidr -Netmask $reiprules.TargetSubnet;
    newMask = '';
    newGateway = $reiprules.TargetGateway;
    primaryDNS = $reiprules.TargetDNS.Split(",")[0];
    secondaryDNS = $reiprules.TargetDNS.Split(",")[1]
}

#start script
Write-Log "`nThis script utilizes PowerCLI to connect to vCenter and inject scripts into the Linux guest VM (nmcli) to perform the re-ip actions."

#Check prereqs
try {
    PreReqs
}
catch {
    throw "There was an error with the prerequisites"
}

#Credentials
Write-Log "`nImporting credentials"
try{
    $VMwareCred = GetPSCreds $vCenterServerCredsUsername $vCenterServerCredsPassword
    $VMUser = GetPSCreds $GuestOSCredsUsername $GuestOSCredsPassword
} 
catch {
    throw "There was an error with the credentials import" 
}

<#
    Do not participate and ignore VC certificate warnings

    ** This can be removed or modified to fit the desired outcome **
#>
Write-Log "`nSetting PowerCLI configuration"
try{
    Set-PowerCLIConfiguration -Scope User -ParticipateInCeip $false -Confirm:$false | Out-Null
    Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false | Out-Null
} 
catch {
    throw "There was an error setting the PowerCLI configuration"
}

# Connecting to vCenter
try{
    ConnectVI $vCenterServer $VMwareCred

    #Ensure you are connected to the correct vCenter
    if(!$DefaultVIServer -or $DefaultVIServer.Name -ne $vCenterServer) {
        Write-Log "`tERROR: Connection to vCenter $vCenterServer failed, exiting..`n"
        exit
    } else {
        Write-Log "`tConnection to vCenter $vCenterServer succeeded"
    }
} 
catch {
    throw "There was an error connecting to the vCenter server using PowerCLI"
}

#Process ReIPRule to determine target IP
try {
    ApplyReIPRule -SourceIpAddress $VMtarget.origIP -ReIpRule $VMtarget.reIPRule
} 
catch {
    throw "Failed to update the target IP based on the ReIP Rule"
}

# Update VM network configuration
Write-Log "`nProcessing $($VMtarget.ServerName)"
try {
    if ($sudotext -ne '') {
        Write-Log "`tSudo = True"
        if ($SudoPassRequired -eq 'false') {
            Write-Log "`tSudo Password is not required"
        }
    }
    else {
        Write-Log "`tSudo = False"
    }
    UpdateVMIPAddresses $VMtarget $VMUser
}
catch {
    throw "There was an error with the Re-IP function"
}

#Disconnect from VMware Server session
Write-Log "Disconnecting from $vCenterServer"
try {
    Disconnect-VIServer -Confirm:$false 
}
catch {
    throw "There was an error attempting to disconnect from $vCenterServer"
} 
