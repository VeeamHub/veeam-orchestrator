# Veeam Recovery Orchestrator - Recover a VM from Backup Copy Job Data into VMware

## Author

Sam Fawaz (@fawazh224)

## Function

This script is designed to recover a VM from backup copy job data. Can be used to recover VMs from any platform into VMware.


***NOTE:*** Before executing this script in a production environment, we strongly recommend you:

* Read the Veeam Recovery Orchestrator User Guide
* Fully understand what the script is doing
* Test the script in a lab environment
* Understand how Veeam Instant Recovery works
* Unserstand how the Instant Recovery migration process works

## Known Issues

The Start-VBRInstantRecovery PowerShell command with the -TargetNetwork parameter in it's current state fails to attach a NIC to the VMware VM after the completion of a conversion during an Instant Recovery. Conversions occur when recovering from non-VMware platforms such as Azure during an Instant VM Recovery. The workaround is to use another Veeam Orchestrator Plan Step to attach the NIC and a another plan step to power on. See GitHub for "VMW - Add Network to VM" and "VMW - Power On VM" scripts.

The Orchestrator Plan will execute successfully and will log "PowerShell script execution has been completed." as a WARNING. This is due to a data sovereignty violoation on the VBR server. The error found on the VBR server is as follows:

* Potential data sovereignty violation: original and target computer locations do not match.

This may have a occured because the source data tested with this script was from an Azure External Repository. Location Tags cannot be set on External Repositories.

## Requirements

* Veeam Backup & Replication v12.1 or later
* Veeam Backup Copy Job backup set must be available
* Veeam Recovery Orchestrator v7 or later
* VMware vSphere v7
    
## Additional Information

Script references the vmw-restore-from-bcj.csv file for VMware target restore details. The following information is required in the CSV file:

* host,pool,datastore,folder,network,backupcopyjobname

Create copy of the template CSV file and remove .template from the name. Replace 2nd line with appropriate information and store in "C:\VRO\CSVs".

In the Orchestration Plan Steps
* Add a Step Parameter
    Name: VMName
    Type: Text
    Default Value: %source_vm_name%

    Change the retry number to 0 to prevent partial restores from repeating
    Add this as a Veeam Orchestrator Group Plan step - this will add it to each VM that is in the group plan to restore to VMware

Note: that the script default is to run in "Alternate VM Recovery Mode" whereby the restore uses an alternate VM name adding "_recovered" to the original name. Comment and uncomment lines in the script to change this behavior.