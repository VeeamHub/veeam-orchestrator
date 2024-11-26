# Veeam Recovery Orchestrator - Execute the running of a restore plan

## Author

Marty Williams (@skitch210)

## Function

This script is designed to run a restore plan in VRO from a VBR server via Powershell


***NOTE:*** Before executing this script in a production environment, I strongly recommend you:

* Read the Veeam Recovery Orchestrator User Guide
* Fully understand what the script is doing
* Test the script in a lab environment
* Understand how Veeam Recovery Orchestrator Restore plan works

## Known Issues

VMs restore in the Powered On state - if not your desired result, you need to script a Power Off of the restored VMs
Restore Plan is left in an "In-Use" state - Need to reset and re-Enable in order to use plan again 

## Requirements

* Veeam Backup & Replication v12 or later
  * Backup job and Restore Plan should have same VMs in them for consistency
* Veeam Recovery Orchestrator v7 or later
  * If using 1 vCenter to manage Production and DR, recommend to modify Restore VM step-Restored VM Name to append to the VM name to not confuse with Production VM after restore completes

    
## Additional Information

Rename vro-run-restore-plan.csv.template to vro-run-restore-plan.csv and place in a C:\VRO\CSVs folder on Veeam Backup server

Fill in for your environment - username,password,plan,baseUrl

If planning to run after the backup job finishes, place script on VBR server and place in the job under Storage-Advanced-Scripts after the job section