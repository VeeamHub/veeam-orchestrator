# Veeam Recovery Orchestrator - Recover to Nutanix AHV

## Author

Marty Williams (@skitch210)

## Function

This script is designed to help automate the recovery of VMs in a backup job and Recovery Orchestrator Plan to Nutanix AHV


***NOTE:*** Before executing this script in a production environment, I strongly recommend you:

* Fully understand what the script is doing
* Test the script in a lab environment
* Understand how Veeam for Nutanix AHV works

## Known Issues

* VMs can only have 1 type of storage controller
* VM IP addresses are not adjusted

## Requirements

* Veeam Backup & Replication v12.2a or later
* Veeam Recovery Orchestrator v7 or later
* Veeam Backup for Nutanix v6

## Additional Information

Rename nutanix-info.csv.template to nutanix-info.csv and place in a C:\VRO\CSVs folder on Veeam BNR server

Fill in for your environment - proxy IP,proxy user,proxy user password,cluster IP,cluster user,cluster user password

In the Orchestration plan - Plan Steps
* Add a Step Parameter
    Name has to be VMName
    Text type with Default value = %source_vm_name%
    Adjust the Timeout value to allow for long recovery into AHV - I set mine for 15 minutes
    Change the retry number to 0 to prevent partial restores from repeating