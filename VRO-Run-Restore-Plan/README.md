# Veeam Recovery Orchestrator - VB Azure Enable a Policy for backup

## Author

Marty Williams (@skitch210)

## Function

This script is designed to enable and start a predefined-disabled backup policy in Veeam Backup for Azure


***NOTE:*** Before executing this script in a production environment, I strongly recommend you:

* Read the Veeam Recovery Orchestrator User Guide
* Fully understand what the script is doing
* Test the script in a lab environment
* Understand how Veeam Backup for Azure works

## Known Issues

None currently

## Requirements

* Veeam Backup & Replication v12 or later
* Veeam Recovery Orchestrator v7 or later
* Veeam Backup for Azure v6
  * Backup policy needs to already be created and in a Disabled state.
    
## Additional Information

Rename azr-enable-policy.csv.template to azr-enable-policy.csv and place in a C:\VRO\CSVs folder on Veeam Orchestrator server

Fill in for your environment - username,password,policy,baseUrl

Add a Custom Plan Step for this script

This script is best placed as a Post-Plan step after the Recovery to Azure