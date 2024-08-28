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
    [string]$VMName,

    [Parameter(Mandatory=$true)]
    [string]$VMOrigIP,

    [Parameter(Mandatory=$true)]
    [string]$ReIPRule,

    [Parameter(Mandatory=$true)]
    [ValidateLength(1, 2)]
    [string]$CIDR,

    [Parameter(Mandatory=$true)]
    [string]$NewGateway,

    [Parameter(Mandatory=$true)]
    [string]$PrimaryDNS,

    [Parameter(Mandatory=$false)]
    [string]$SecondaryDNS = '',

    [Parameter(Mandatory=$false)]
    $SudoRequired = 'false',

    [Parameter(Mandatory=$false)]
    $SudoPassRequired = 'true'
)

function PreReqs {
    Write-Host "`nChecking for PowerCLI installation"
    try{
        Import-Module VMware.VimAutomation.Sdk | Out-Null
        Import-Module VMware.VimAutomation.Common | Out-Null
        Import-Module VMware.VimAutomation.Cis.Core | Out-Null
        Import-Module VMware.VimAutomation.Core | Out-Null
        Write-Host "`tPowerCLI installed"
    } catch {
        Write-Error "There was an error with the PowerCLI installation"
    } 
}

function GetPSCreds ($userName, $password) {    
    $secpwd = ConvertTo-SecureString $password -AsPlainText $true
    return New-Object System.Management.Automation.PSCredential($userName, $secpwd)
}

function ConnectVI ($Server, $Credential) {
    if ($null -eq $Credential) {
        Write-Host "`tError: Cannot connect to $server as no credentials were specified."
        return
    }

    Write-Host "`nConnecting to $Server using credentials ($($Credential.UserName))."
    $Server = Connect-VIServer $Server -Credential $Credential
    if ($null -eq $Server) {
        Write-Host "`tError: A connectivity issue has occurred when connecting to the vCenter server."
    }
}

function ValidateCIDR {
    param(
        [ValidateRange(1,32)]
        [int] $CIDR
    )
    #Match CIDR to subnetmask
    switch ($CIDR) 
    {
        1 {$script:VMtarget.newMask = "128.0.0.0"; Break}  
        2 {$script:VMtarget.newMask = "192.0.0.0"; Break}
        3 {$script:VMtarget.newMask = "224.0.0.0"; Break}
        4 {$script:VMtarget.newMask = "240.0.0.0"; Break}
        5 {$script:VMtarget.newMask = "248.0.0.0"; Break}
        6 {$script:VMtarget.newMask = "252.0.0.0"; Break}
        7 {$script:VMtarget.newMask = "254.0.0.0"; Break}
        8 {$script:VMtarget.newMask = "255.0.0.0"; Break}
        9 {$script:VMtarget.newMask = "255.128.0.0"; Break}
        10 {$script:VMtarget.newMask = "255.192.0.0"; Break}
        11 {$script:VMtarget.newMask = "255.224.0.0"; Break}
        12 {$script:VMtarget.newMask = "255.240.0.0"; Break}
        13 {$script:VMtarget.newMask = "255.248.0.0"; Break}
        14 {$script:VMtarget.newMask = "255.252.0.0"; Break}
        15 {$script:VMtarget.newMask = "255.254.0.0"; Break}
        16 {$script:VMtarget.newMask = "255.255.0.0"; Break}
        17 {$script:VMtarget.newMask = "255.255.128.0"; Break}
        18 {$script:VMtarget.newMask = "255.255.192.0"; Break}
        19 {$script:VMtarget.newMask = "255.255.224.0"; Break}
        20 {$script:VMtarget.newMask = "255.255.240.0"; Break}
        21 {$script:VMtarget.newMask = "255.255.248.0"; Break}
        22 {$script:VMtarget.newMask = "255.255.252.0"; Break}
        23 {$script:VMtarget.newMask = "255.255.254.0"; Break}
        24 {$script:VMtarget.newMask = "255.255.255.0"; Break}
        25 {$script:VMtarget.newMask = "255.255.255.128"; Break}
        26 {$script:VMtarget.newMask = "255.255.255.192"; Break}
        27 {$script:VMtarget.newMask = "255.255.255.224"; Break}
        28 {$script:VMtarget.newMask = "255.255.255.240"; Break}
        29 {$script:VMtarget.newMask = "255.255.255.248"; Break}
        30 {$script:VMtarget.newMask = "255.255.255.252"; Break}
        31 {$script:VMtarget.newMask = "255.255.255.254"; Break}
        32 {$script:VMtarget.newMask = "255.255.255.255"; Break} 
        Default {Write-Error "Unable to convert CIDR to an appropriate network mask. $CIDR does not match a CIDR number of 1-32"}
    }
}

function ApplyReIPRule ($SourceIpAddress, $ReIPRule) { 
    Write-Host "Applying re-ip rule to determine the target ip address"   
    $TargetIp = $ReIPRule
    for($i=1;$i -le 3; $i++) {
        [regex]$pattern  = "\*"
        if ($TargetIp.Split(".")[$i] -eq "*") { 
        $TargetIp = $pattern.Replace($TargetIp,$SourceIpAddress.Split(".")[$i],1) 
        }
    }
    $script:VMtarget.newIP = $TargetIp
    if ($VMtarget.newIP -ne '') {
        Write-Host "`n`tResults of ReIP Rule:`n`t`tSource IP: $($VMtarget.origIP)`n`t`tReIP Rule: $($VMtarget.reIPRule)`n`t`tTarget IP: $($VMtarget.newIP)"
    }
    else {
        Write-Error "`tFailed to determine the target IP address from the re-ip rule"
    }
}

function ParseInterfaceConfig ($vm, $netdevices, $ostype, $GuestCredential) {
    $count = 0

    #This is used to verify the updated IP on recheck after device modification
    Write-Host "`n`t`tVerification is set to: $($VMNicVerify)"

    #Retrieve device details and locate the source IP on device
    if ($ostype -eq "Linux") {
        $scripttype = "Bash"
        $devNames = $netdevices.Trim().Split("`n")
        foreach ($devName in $devNames){
            $devName = $devName.Trim()
            $scripttext = ''
            $output = ''
            if ($VMNicVerify -eq $false){
                Write-Host "`n`t`tDevice $($count + 1) = $devName"
            }
            $scripttext = "nmcli -t dev show $devName"
            if ($VMNicVerify -eq $false){
                Write-Host "`t`tRetrieving details for Device $($count + 1): `n`t`t`t$scripttext"
            }
            else {
                Write-Host "`t`tVerifying the details for $($VMNicName): `n`t`t`t$scripttext"
            }
            $output = Invoke-VMScript -VM $vm.Name -GuestCredential $GuestCredential -ScriptType $scripttype -ScriptText $scripttext
            Write-Host "`nDevice info:`n$output"
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
                Write-Host "`n`t`tUpdated IP on $($VMNicName) has been verified"
            }
            #if source IP was located on first run output the devicename
            else {
                Write-Host "`n`tMatching ip found on $($VMNicName)"
            }
        }
        #output warning if source IP was not located
        else {
            Write-Warning "`n`t`tDid not find a matching source IP"
        }
    }
    #Wrong OS
    else {
        Write-Error "Incompatible OS"
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
    Write-Host "`tChecking VM network devices"
    Write-Host "`t`tInvoking script: `n`t`t`t$($scripttext)"
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
        Write-Host "`n`t`tInvoking ncmli ReIP script"
        $output = Invoke-VMScript -VM $vm.Name -GuestCredential $GuestCredential -ScriptType $scripttype -ScriptText $scripttext
        Write-Host "`n$output"
    }

    #Skip unsupported OS types
    elseif ($ostype -eq "Linux") { 
        #do nothing 
        Write-Error "``tFailed: Virtual Machine $($vm.Name) is running an unsupported operating system $($vm.Guest.OSFullName)."
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
        Write-Error "Error: Virtual Machine $($VM.ServerName) is unavailable. Check parent server connections and permissions."
    }

    #Get the details for each network device and locate the matching source IP to a device
    ParseInterfaceConfig -vm $_vm -netdevices $VMNetDevices -ostype "Linux" -GuestCredential $GuestCredential
    
    #output the target configuration settings
    Write-Host "`n`tRe-IP settings:`n`t`tSource: $($VM.origIP)`n`t`tTarget: $($VM.newIP)`n`t`tSubnet: $($VM.newMask)`n`t`tGateway: $($VM.newGateway)"
    
    #Process the configuration if the source IP was located on a network device
    if ($VMNicName -ne ''){           
        $script:VMNicVerify = $true 
        Write-Host "`n`tProcessing: $($_vm.Name)`n`t`tinterface: $($VMNicName)`n`t`tsource: $($VMtarget.origIP)`n`t`ttarget: $($VM.newIP)"
        
        #Configure the device settings
        SetVMNetworkInterface -VM $_vm -Connection $VMNicConnection -IPAddress $VM.newIP -CIDR $VM.CIDR -Gateway $VM.newGateway -DNS $VM.primaryDNS -dns2 $VM.secondaryDNS -GuestCredential ($GuestCredential)            
        
        #Check for updated IP on selected device
        ParseInterfaceConfig -vm $_vm -netdevices $VMNicName -OSType "Linux" -guestcredential $GuestCredential        
        
        #If verification passed, output the success message
        if ($success){ 
            Write-Host "`n`tSuccess: Virtual Machine $($VM.ServerName) interface $($VMNicName) updated to $($VM.newIP)" 
        }
        #If failed, output error
        else { 
            Write-Error "Failed: $($VM.ServerName) has not been modified"
        }    
    }
    #show error if the source IP was not found
    else {
        Write-Warning "`n`tWarning: Virtual Machine $($_vm.Name) does not contain network interfaces matching $($VM.origIP)"
    }
} 

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

#Define VM parameters
$VMtarget = [pscustomobject]@{
    ServerName = $VMName;
    origIP = $VMOrigIP;
    reIPRule = $ReIPRule;
    newIP = '';
    CIDR = [int]$CIDR;
    newMask = '';
    newGateway = $NewGateway;
    primaryDNS = $PrimaryDNS;
    secondaryDNS = $SecondaryDNS
}

#start script
Write-Host "`nThis script utilizes PowerCLI to connect to vCenter and inject scripts into the Linux guest VM (nmcli) to perform the re-ip actions."

#Check prereqs
try {
    PreReqs
}
catch {
    throw "There was an error with the prerequisites"
}

#Credentials
Write-Host "`nImporting credentials"
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
Write-Host "`nSetting PowerCLI configuration"
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
        Write-Error "`tConnection to vCenter $vCenterServer failed, exiting..`n"
        exit
    } else {
        Write-Host "`tConnection to vCenter $vCenterServer succeeded"
    }
} 
catch {
    throw "There was an error connecting to the vCenter server using PowerCLI"
}

#Validate the CIDR and match the netmask value
try {
    ValidateCIDR -CIDR $VMtarget.CIDR
}
catch {
    throw "There was an error validating the CIDR number"
}

#Process ReIPRule to determine target IP
try {
    ApplyReIPRule -SourceIpAddress $VMtarget.origIP -ReIpRule $VMtarget.reIPRule
} 
catch {
    throw "Failed to update the target IP based on the ReIP Rule"
}

# Update VM network configuration
Write-Host "`nProcessing $($VMtarget.ServerName)"
try {
    if ($sudotext -ne '') {
        Write-Host "`tSudo = True"
        if ($SudoPassRequired -eq 'false') {
            Write-Host "`tSudo Password is not required"
        }
    }
    else {
        Write-Host "`tSudo = False"
    }
    UpdateVMIPAddresses $VMtarget $VMUser
}
catch {
    throw "There was an error with the Re-IP function"
}

#Disconnect from VMware Server session
Write-Host "Disconnecting from $vCenterServer"
try {
    Disconnect-VIServer -Confirm:$false 
}
catch {
    throw "There was an error attempting to disconnect from $vCenterServer"
} 
