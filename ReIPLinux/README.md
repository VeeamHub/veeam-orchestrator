# Veeam Recovery Orchestrator - Re-IP Linux VMs using PowerCLI and Network Manager (nmcli)

## Author

Tyson Fewins (tfewins)

## Function

This script is designed to query and modify the network device settings in a Linux VM that uses Network Manager to control device configurations. This script is used as a VM step in a recovery or replication failover plan.

***NOTE:*** Before executing this script in a production environment, I strongly recommend you:

* Read the Veeam Recovery Orchestrator User Guide
* Fully understand what the script is doing
* Test the script in a lab environment
* Understand how Veeam Restore and/or Replica Failover works

## Known Issues

None currently

## Requirements

* Veeam Backup & Replication v12 or later
* Veeam Recovery Orchestrator v7 or later
* Install VMware PowerCLI on the Veeam Backup & Replication server
  * For PowerCLI install:
    Documentation:
	  https://developer.broadcom.com/powercli/installation-guide
* Network Manager installation is required in the VM Guest OS
  * New releases of RHEL and its derivatives ship with Network Manager, as well as new releases of Ubuntu.
  * Network Manager is available on other Linux OSes but may require installation and configuration
* Credentials for target vCenter and VM need to exist in the Recovery Orchestrator Credentials store

## Additional Information

In the Orchestration plan - Plan Steps
* Modify the following pre-defined parameter values
```
    Common Parameters/Retries = 1 (to limit execution time in case of failure)
    Execute Location/Default Values = Veeam Backup Server
```
* Add the following required Step Parameters
```
    Name = vCenterServer\n
    Desription = Hostname, FQDN, or IP of the vCenter Server that manages the target VM. This is used for PowerCLI connection.\n
    Type = Text\n
    Default Value = Either leave blank or put your recovery vCenter name here\n

    Name = vCenterServerCreds
    Desription = The credential used to authenticate to the "vCenterServer"
    Type = Credential
    Default Value = (Either blank or select your DR vCenter credential)

    Name = GuestOsCreds
    Desription = The credential used to authenticate in the VM guest OS
    Type = Credential
    Default Value = (Either blank or put your recovery vCenter name here)

    Name = VMName
    Desription = Name of the target VM
    Type = Text
    Default Value = %target_vm_name% (for replica plan)

    Name = VMOrigIP
    Desription = Original IP Address. Used to locate the network device to be modified. 
    Type = Text
    Default Value = %current_vm_ip%

    Name = ReIPRule
    Desription = Re-IP Rule to apply. Can use asterisk(*) to keep source IP values for an octet. Ex. 10.1.*.* or 10.0.1.* 
    Type = Text
    Default Value = 

    Name = CDIR
    Desription = CIDR number for subnet mask. Ex. 24, 28, etc.  
    Type = Text
    Default Value = 

    Name = NewGateway
    Desription = New gateway address. 
    Type = Text
    Default Value = 

    Name = PrimaryDNS
    Desription = Primary DNS address. 
    Type = Text
    Default Value = 

    Name = SecondaryDNS
    Desription = Secondary DNS address. 
    Type = Text
    Default Value = 
```
* Add the following optional Step Parameters if needed
```
    Name = SudoRequired
    Desription = Use this parameter to force the use of Sudo. 
    Type = Text
    Default Value = true (the script defaults to false unless this parameter is set to 'true')

    Name = SudoPassRequired
    Desription = Use this parameter to specify if a password is not required. The script defaults to using a password with Sudo if 'SudoRequired' is set to true. 
    Type = Text
    Default Value = false (the script defaults to true unless this parameter is set to 'false')
```
* The script is set to work for VMware VMs that have a 'Guest OS Family' of 'Linux' and a 'Guest OS Version' of "*CentOS*", "*Red Hat*", or "*Ubuntu*". If you have configured a VM with another OS Version such as "*Debian*" to use Network Manager to configure network devices, the script can be modified to enable exection for this OS Type in the "SetVMNetworkInterface" function where the OS Type is checked.
