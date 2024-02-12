# Veeam Recovery Orchestrator - Add a Tag and Value to recovered VM in Azure

## Author

Marty Williams (@skitch210)

## Function

This script is designed to add a tag and value to a recovered VM in Azure that was recovered with the normal VRO Azure recovery


***NOTE:*** Before executing this script in a production environment, I strongly recommend you:

* Read the Veeam Recovery Orchestrator User Guide
* Fully understand what the script is doing
* Test the script in a lab environment
* Understand how Veeam Restore to Azure works

## Known Issues

None currently

## Requirements

* Veeam Backup & Replication v12 or later
* Veeam Recovery Orchestrator v6 or later
* Install Azure CLI
  Azure CLI needs to be installed on Veeam BNR server
  * For Azure CLI install:
    Documentation:
	  https://learn.microsoft.com/en-us/cli/azure/install-azure-cli-windows?tabs=azure-cli

    ***NOTE:*** You will need to reboot after install in order for the Azure CLI to be in the system Path

	  
    If not already setup - create a Service Principal with a Secret Key:
	  https://learn.microsoft.com/en-us/entra/identity-platform/howto-create-service-principal-portal

## Additional Information

Rename azure-info.csv.template to azure-info.csv and place in a C:\VRO\Scripts\Azure folder on Veeam BNR server

Fill in for your environment - resourceGroup,applicationID,secretValue,tenatID,vbAzureVM

In the Orchestration plan - Plan Steps
* Add a Step Parameter
    Name has to be VMName
    Text type with Default value = %source_vm_name%
    Change the retry number to 0 to prevent partial restores from repeating
    Add this Step to your Cloud Recovery plan - this will add it to each VM that is in the plan to restore to Azure

A tag is added to the Azure VM instance
  Key=backup
  Value=yes
