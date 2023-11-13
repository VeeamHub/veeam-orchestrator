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

None currrently

## Requirements

* Veeam Backup & Replication v12 or later
* Veeam Recovery Orchestrator v6 or later
* Veeam Backup for Azure VM deployed in Azure Account and configured
* Install Azure CLI
  * Azure CLI needs to be installed on Veeam BNR server
  * For Azure CLI install:
    Documentation:
	  https://learn.microsoft.com/en-us/cli/azure/install-azure-cli-windows?tabs=azure-cli

    ***NOTE:*** You will need to reboot after install in order for the Azure CLI to be in the system Path

	  
    If not already setup - create a Service Principal with a Secret Key:
	  https://learn.microsoft.com/en-us/entra/identity-platform/howto-create-service-principal-portal

    
## Additional Information

Fill in for your environment - resourceGroup,applicationID,secretValue,tenatID,vbAzureVM

In the Orchestration plan - Plan Steps
* This is best placed in a Post Plan Step after performing a recovery to Azure