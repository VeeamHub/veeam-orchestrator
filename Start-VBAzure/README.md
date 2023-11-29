# Veeam Recovery Orchestrator - Start Veeam Backup for Azure VM

## Author

Marty Williams (@skitch210)

## Function

This script is designed to power on a previsely deployed Veeam Backup for Azure VM


***NOTE:*** Before executing this script in a production environment, I strongly recommend you:

* Read the Veeam Recovery Orchestrator User Guide
* Fully understand what the script is doing
* Test the script in a lab environment
* Understand how Veeam Backup for Azure works

## Known Issues

Veeam Backup for Azure needs to be configured and in a powered off status. A backup policy needs to be created to backup VMs with a policy to protect systems with the tag that was added by the AddTag script

## Requirements

* Veeam Backup & Replication v12 or later
* Veeam Recovery Orchestrator v6 or later
* Veeam Backup for Azure VM deployed in Azure Account and configured
* Install Azure CLI
  * Azure CLI needs to be installed on Veeam Orchestrator server
  * For Azure CLI install:
    Documentation:
	  https://learn.microsoft.com/en-us/cli/azure/install-azure-cli-windows?tabs=azure-cli

    ***NOTE:*** You will need to reboot after install in order for the Azure CLI to be in the system Path

	  
    If not already setup - create a Service Principal with a Secret Key:
	  https://learn.microsoft.com/en-us/entra/identity-platform/howto-create-service-principal-portal

    
## Additional Information

Need to place azure-info.csv.template on your Veeam Orchestrator server in a C:\VRO\Scripts\Azure folder.
Rename to C:\VRO\Scripts\Azure\azure-info.csv
Fill in for your environment - resourceGroup,applicationID,secretValue,tenatID,vbAzureVM

In the Orchestration plan - Plan Steps
* This is best placed in a Post Plan Step after performing a recovery to Azure