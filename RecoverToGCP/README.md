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
* Install gcloud (Google Cloud Platform CLI)
  * Configure gcloud cli to run via scripting

  GCP CLI needs to be installed on Veeam BNR server
  * 


## Additional Information

Rename gcp-info.csv.template to gcp-info.csv and place in a C:\VRO\Scripts folder on Veeam BNR server

Fill in for your environment - account,region,zone,VPC,subnet,prx

In the Orchestration plan - Plan Steps
* Add a Step Parameter
    Name has to be VMName
    Text type with Default value = %source_vm_name%
    Adjust the Timeout value to allow for long recovery into GCP - I set mine for 1 hour
    Change the retry number to 0 to prevent partial restores from repeating


A tag is added to the GCP VM for auto backup by VB-GCP
  Key=backup
  Value=recover
