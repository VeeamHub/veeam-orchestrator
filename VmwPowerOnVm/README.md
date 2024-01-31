# Veeam Recovery Orchestrator - Add a NIC to a VM in VMware and Connect to Network

## Author

Sam Fawaz (@fawazh224)

## Function

This script is designed to power on a VMware VM if it is off, designed for use as an Orchestrator Plan Step.


***NOTE:*** Before executing this script in a production environment, we recommend you:

* Understand VMware Vsphere

## Known Issues

No known issues at this time.

## Requirements

* VMware vSphere v7
    
## Additional Information

Script references the vmw-poweron-vm.csv file for VM details. The following information is required in the CSV file:

* vcenter-user,Password,vcenter-fqdn

In the Orchestration plan - Plan Steps
* Add a Step Parameter
    Name has to be VMName
    Text type with Default value = %source_vm_name%
    Change the retry number to 0
    Add this as a Veeam Orchestrator Group Plan step - this will add it to each VM that is in the group plan to restore to VMware