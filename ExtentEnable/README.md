# Veeam Recovery Orchestrator - Place SOBR Performance Extent into Maintenance Mode

## Author

Marty Williams (@skitch210)

## Function

This script is designed to place SOBR Performance Extent into Maintenance Mode in order for the Azure restore to pull from Capacity Tier


***NOTE:*** Before executing this script in a production environment, I strongly recommend you:

* Read the Veeam Recovery Orchestrator User Guide
* Fully understand what the script is doing
* Test the script in a lab environment
* Understand how Veeam Restore to Azure and Veeam SOBR repositories work.

## Known Issues

This version is not writing all of the Write Host out to VRO for documentation

## Requirements

* Veeam Backup & Replication v12 or later
* Veeam Recovery Orchestrator v6 or later
    
## Additional Information

Need to place vbr-info.csv.template on your Veeam Orchestrator server in a C:\VRO\Scripts\VBR folder.
Rename to C:\VRO\Scripts\VBR\vbr-info.csv
Fill in for your environment - vbrserver,repo

In the Orchestration plan - Plan Steps
* This is best placed in a Pre Plan Step after performing a recovery to Azure