param([string]$VMName)
# Accept variable VM name from Orchestrator

Write-Host $VMName

Write-Host "Set Azure Info"

#Please Update the azure-info.csv for your settings
$azureCSV = "C:\VRO\Scripts\Azure\azure-info.csv" #CSV File to read from.
$azureInfo =Import-Csv $azureCSV

# Connect to Azure account
$azConn = az login --service-principal -u $azureInfo.applicationID -p $azureInfo.secretValue --tenant $azureInfo.tenantID | ConvertFrom-Json

Write-Host "Azure Sub Name: " $azConn.name

# Add tag to restored VM in Azure
$addTag = az resource tag --tags backup=yes -g $azureInfo.resourceGroup -n $VMName --resource-type "Microsoft.Compute/virtualMachines"

# Retrieve VM details to verify tag added
$vmDetails = az vm show -g $azureInfo.resourceGroup -n $VMName | ConvertFrom-Json

Write-Host "Tag added to VM: " $vmDetails.tags

# Verify restored VM is powered on
$vmSTS = az vm show -g $azureInfo.resourceGroup -n $VMName -d --query powerState

Write-Host "Restored VM Status: " $vmSTS
