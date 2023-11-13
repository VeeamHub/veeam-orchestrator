
Write-Host "Set Azure Info"

#Please Update the azure-info.csv for your settings
$azureCSV = "C:\VRO\Scripts\Azure\azure-info.csv" #CSV File to read from.
$azureInfo =Import-Csv $azureCSV

# Connect to Azure account
$azConn = az login --service-principal -u $azureInfo.applicationID -p $azureInfo.secretValue --tenant $azureInfo.tenantID | ConvertFrom-Json

Write-Host "Azure Sub Name: " $azConn.name

# Start pre-deployed Veeam Backup for Azure Appliance
$vmStart = az vm start -g $azureInfo.resourceGroup -n $azureInfo.vbAzureVM


# Verify VB Azure VM is powered on
$vmSTS = az vm show -g $azureInfo.resourceGroup -n $azureInfo.vbAzureVM -d --query powerState

Write-Host "Veeam VM: " $azureInfo.vbAzureVM "is" $vmSTS
