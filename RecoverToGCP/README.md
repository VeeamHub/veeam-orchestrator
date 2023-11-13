# Veeam Recovery Orchestrator - Recover to GCP

## Author

Marty Williams (@skitch210)

## Function

This script is designed to help automate the recovery of VMs in a backup job and Recovery Orchestrator Plan to GCP


***NOTE:*** Before executing this script in a production environment, I strongly recommend you:

* Read the GCP Hardware and OS compatability for recovery
* Fully understand what the script is doing
* Test the script in a lab environment
* Understand how Veeam Restore to GCP works

## Known Issues

* Some OS versions are not supported on GCP, make sure systems you are restoring are supported
* VM IP addresses are not adjusted for running in GCP
    * The last step in the strip creates a CSV file with server name and IP address that can be used for mass DNS updates
      You can use this to update your DNS entries


## Requirements

* Veeam Backup & Replication v11a or later
* Veeam Recovery Orchestrator v5 or later
* Install gcloud (Google Cloud Platform CLI) = On the VBR server
  * https://cloud.google.com/sdk/docs/install
  * Configure gcloud cli to run via scripting
    * Edit Environment Variables - 
        Path settings:
          %path of install%\google-cloud-sdk\bin
          %path of install%\google-cloud-sdk.staging\bin

        PathExt:
          Add ;.PY

        Environment Variables:
          Add CLOUDSDK_CONFIG and value of a directory to store config file database in (needs to be accesible IIS VRO app)

## Additional Information

Rename gcp-info.csv.template to gcp-info.csv and place in a C:\VRO\Scripts folder on Veeam BNR server

Fill in for your environment - 
  account - GCP account name in VBR
  region - GCP region you want to recover into
  zone - GPC zone in that region
  VPC - GPC VPC to recover into
  subnet - GPC subnet in that VPC
  prx - GPC instance type to use as the Veeam Proxy instance
  vbgpc - Veeam Backup for GPC Instance (if already built for preotecting restored VMs in GPC)

In the Orchestration plan - Plan Steps
* Add a Step Parameter
    Name has to be VMName
    Text type with Default value = %source_vm_name%
    Adjust the Timeout value to allow for long recovery into GCP - I set mine for 1 hour
    Change the retry number to 0 to prevent partial restores from repeating


A tag is added to the GCP VM for auto backup by VB-GCP
  Key=backup
  Value=recover
