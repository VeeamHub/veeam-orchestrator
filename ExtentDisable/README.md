# Veeam Recovery Orchestrator - Take SOBR Extent out of Maintenance Mode

## Author

Marty Williams (@skitch210)

## Function

This script is designed to take an extent out of maintenance mode after restore from capacity tier


***NOTE:*** Before executing this script in a production environment, I strongly recommend you:

* Read the Veeam Recovery Orchestrator User Guide
* Fully understand what the script is doing
* Test the script in a lab environment
* Understand how Veeam Restore to Azure and SOBR Maintenance mode works

## Known Issues

This version only works with a SOBR with 1 Performance Extent

## Requirements

* Veeam Backup & Replication v12 or later
* Veeam Recovery Orchestrator v6 or later
    
## Additional Information

Need to place vbr-info.csv.template on your Veeam BNR server in a C:\VRO\Scripts\VBR folder.
Rename to C:\VRO\Scripts\VBR\vbr-info.csv
Fill in for your environment - vbrserver,repo

In the Orchestration plan - Plan Steps
* This is best placed in a Post Plan Step after performing a recovery to Azure