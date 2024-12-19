[CmdletBinding()]
Param(
    [Parameter(Mandatory=$true)]
    [string]$VbrCredentialsUsername,

    [Parameter(Mandatory=$true)]
    [string]$VbrCredentialsPassword,

    [Parameter(Mandatory=$true)]
    [string]$SourceVmName,

    [Parameter(Mandatory=$true)]
    [string]$LogPath,

    [Parameter(Mandatory=$true)]
    [string]$CurrentPlanState
)
$Version = "0.0.3"

### Parameter examples for manual testing (without VRO)
# $VbrCredentialsUsername = "admin" 
# $VbrCredentialsPassword = "SecurePassword" 
# $SourceVmName = "web-1"
# $LogPath = "c:\path\here"
# $CurrentPlanState = "Failover - Processing"


Function Write-Log {
    param([string]$str)      
    Write-Host $str
    $dt = (Get-Date).toString("yyyy.MM.dd HH:mm:ss")
    $str = "[$dt] <$CurrentPid> $str"
    Add-Content $LogFile -value $str
}     

$VbrHostname = "localhost"
$CurrentPid = ([System.Diagnostics.Process]::GetCurrentProcess()).Id

$LogDir = "$($LogPath)\logs"
if (-not (Test-Path -Path $LogDir)) {
    New-Item -Path $LogDir -ItemType Directory
}
$LogFile = "$LogDir\$($SourceVmName)-GetReIpRules.log"

Write-Log $("="*78)
Write-Log "{"
Write-Log "`tScript: $($MyInvocation.MyCommand.Name)"
Write-Log "`tVersion: { $($Version) }"
Write-Log "}"

#Check plan state and execute code only during failover, restore or test 
if  (($CurrentPlanState -like "Failover*") -or $CurrentPlanState -like "Test*" -or $CurrentPlanState -like "Restore*") {


    # create VBR PS credential
    Write-Log "Credentials for: $($VbrCredentialsUsername)"
    [secureString]$VbrPassword = ConvertTo-SecureString $VbrCredentialsPassword -AsPlainText -Force
    [pscredential]$VbrCredentials = New-Object System.Management.Automation.PSCredential ($VbrCredentialsUsername, $VbrPassword)

    # Connect to VBR
    try {
        Write-Log "Connecting to VBR Server $($VbrHostname)"
        Connect-VBRServer -Server $VbrHostname -Credential $VbrCredentials
    }
    catch {
        throw "Error: An error occurred when conencting to $($VbrHostname). $($_.Exception.InnerException.Message)"
        Write-Log "Error: An error occurred when conencting to $($VbrHostname). $($_.Exception.InnerException.Message)" 
        Write-Log $_
        exit
    }

    $VmFoundInJob = $false

    # Look for VM in replication jobs
    $replicationjobs = Get-VBRJob | Where {$_.IsSnapOrCdpReplica}
    if ($replicationjobs -and -not $VmFoundInJob) { 
        Write-Log "Found replication jobs: $($replicationjobs.Name)"
        
        # search for the job of the VM and  extract re-IP rules 
        foreach ($j in $replicationjobs) {
                $reiprules = @()
                $roijs = $j | Get-VBRJobObject | Where {$_.Type -ne "Exclude"}
                foreach ($o in $roijs) {
                # check tags - does not check Exclusions
                if ($o.TypeDisplayName -eq "Tag") {
                    Write-Log "Found tag $($o.Name) in job $($j.Name)"
                    $tagPath = "*" + $o.Name + "*"
                    $tagVms = Find-VBRViEntity -Tags | Where-Object { ($_.Type -eq "Vm") -And ($_.Path -like $tagPath) }
                    Write-Log " ...tagged VMs in the job: $($tagVms.Name)"
                    foreach ($v in $tagVms) {
                        if ($v.Name -like $SourceVmName) {
                                Write-Log "Processing VM $($SourceVmName) in job $($j.Name)"
                                foreach($rule in $j.Options.ReIPRulesOptions.RulesIPv4) {
                                    $r = @{
                                        'SourceIp'=$rule.Source.Ipaddress
                                        'SourceSubnet'=$rule.Source.SubnetMask
                                        'TargetIp'=$rule.Target.Ipaddress
                                        'TargetSubnet'=$rule.Target.SubnetMask
                                        'TargetGateway'=$rule.Target.DefaultGateway
                                        'TargetDNS'=[string]::Join(",",$rule.Target.DNSAddresses)
                                        'TargetWINS'=[string]::Join(",",$rule.Target.WINSAddresses)
                                        'Description'=[string]::Join(",",$rule.Description)
                                    }
                                    $reiprules += New-Object -TypeName PSObject -Prop $r
                                }
                                $VmFoundInJob = $true
                                break
                        }                    
                    }

                } else {
                    # check VM is in Job
                    if ($o.Name -like $SourceVmName) {
                            Write-Log "Processing VM $($SourceVmName) in job $($j.Name)"
                            foreach($rule in $j.Options.ReIPRulesOptions.RulesIPv4) {
                                $r = @{
                                    'SourceIp'=$rule.Source.Ipaddress
                                    'SourceSubnet'=$rule.Source.SubnetMask
                                    'TargetIp'=$rule.Target.Ipaddress
                                    'TargetSubnet'=$rule.Target.SubnetMask
                                    'TargetGateway'=$rule.Target.DefaultGateway
                                    'TargetDNS'=[string]::Join(",",$rule.Target.DNSAddresses)
                                    'TargetWINS'=[string]::Join(",",$rule.Target.WINSAddresses)
                                    'Description'=[string]::Join(",",$rule.Description)
                                }
                                $reiprules += New-Object -TypeName PSObject -Prop $r
                            }
                            $VmFoundInJob = $true
                            break
                    }
            
                }

                }
                if ($reiprules) { 
                foreach ($r in $reiprules) {
                    $ruleDescription = $r.Description.ToLower() + "*"
                    if ($CurrentPlanState.ToLower() -like $ruleDescription) {
                        Write-Log "Found ReIP Rules for $($SourceVmName)"
                        Write-Log $r
                        # create file with reIpRules object
                        $VarFileName = "$LogDir\ReIpRules-$($SourceVmName).json"
                        $r | ConvertTo-Json | Out-File -FilePath $VarFileName
                    } 
                }
                break
                }
        }

    }

    # Look for VM in CDP policies
    $cdppolicies = Get-VBRCDPPolicy
    if ($cdppolicies -and -not $VmFoundInJob) { 

        Write-Log "Found cdp policies: $($cdppolicies.Name)" 

        # search for the policy of the VM and extract re-IP rules - check if VMs are in exclude list
        foreach ($p in $cdppolicies) {
                $reiprules = @()
                $roijs = $p | Get-VBRJobObject | Where {$_.Type -ne "Exclude"}
                foreach ($o in $roijs) {
                if ($o.TypeDisplayName -eq "Tag") {
                    Write-Log "Found tag $($o.Name) in job $($p.Name)"
                    $tagPath = "*" + $o.Name + "*"
                    $tagVms = Find-VBRViEntity -Tags | Where-Object { ($_.Type -eq "Vm") -And ($_.Path -like $tagPath) }
                    Write-Log " ...tagged VMs in the job: $($tagVms.Name)"
                    foreach ($v in $tagVms) {
                        if ($v.Name -like $SourceVmName) {
                                Write-Log "Processing VM $($SourceVmName) in job $($p.Name)"
                                foreach($rule in $p.ReIPRule) {
                                    $r = @{
                                        'SourceIp'=$rule.SourceIp
                                        'SourceSubnet'=$rule.SourceMask
                                        'TargetIp'=$rule.TargetIp
                                        'TargetSubnet'=$rule.TargetMask
                                        'TargetGateway'=$rule.TargetGateway
                                        'TargetDNS'=[string]::Join(",",$rule.DNS)
                                        'TargetWINS'=[string]::Join(",",$rule.WINS)
                                        'Description'=$rule.Description
                                    }
                                    $reiprules += New-Object -TypeName PSObject -Prop $r
                                }  
                                $VmFoundInJob = $true
                                break
                        }
                    }
                } else {
                    if ($o.Name -like $SourceVmName) {
                            Write-Log "Processing VM $($SourceVmName) in job $($p.Name)"
                            foreach($rule in $p.ReIPRule) {
                                $r = @{
                                    'SourceIp'=$rule.SourceIp
                                    'SourceSubnet'=$rule.SourceMask
                                    'TargetIp'=$rule.TargetIp
                                    'TargetSubnet'=$rule.TargetMask
                                    'TargetGateway'=$rule.TargetGateway
                                    'TargetDNS'=[string]::Join(",",$rule.DNS)
                                    'TargetWINS'=[string]::Join(",",$rule.WINS)
                                    'Description'=$rule.Description
                                }
                                $reiprules += New-Object -TypeName PSObject -Prop $r
                            }
                            $VmFoundInJob = $true
                            break
                    }
            
                } 

                }
                if ($reiprules) { 
                foreach ($r in $reiprules) {
                    $ruleDescription = $r.Description.ToLower() + "*"
                    if ($CurrentPlanState.ToLower() -like $ruleDescription) {
                        Write-Log "Found ReIP Rules for $($SourceVmName)"
                        Write-Log $r
                        # create file with reIpRules object
                        $VarFileName = "$LogDir\ReIpRules-$($SourceVmName).json"
                        $r | ConvertTo-Json | Out-File -FilePath $VarFileName
                    } 
                }
                break
                }
        }


    }
} else {
    Write-Log "[WARN] Plan state is: $($CurrentPlanState). ReIP rules are processed during failover, testing and restore"
    exit
}

Disconnect-VBRServer