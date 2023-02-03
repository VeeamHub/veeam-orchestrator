# Veeam Recovery Orchestrator - Recover to AWS 

## Author

Marty Williams (@skitch210)

## Function

This script is designed to help automate the recovery of VMs in a backup job and Recovery Orchestrator Plan to AWS


***NOTE:*** Before executing this script in a production environment, I strongly recommend you:

* Read the AWS Hardware compatability for recovery
* Fully understand what the script is doing
* Test the script in a lab environment
* Understand how Veeam Restore to AWS works

## Known Issues

* Linux GPT disks are not supported on AWS, neeed to convert to MPR
* VM IP addresses are not adjusted for running in AWS
    * The last step in the strip creates a CSV file with server name and IP address that can be used for mass DNS updates
      You can use this to update your DNS entries


## Requirements

* Veeam Backup & Replication v11a or later
* Veeam Recovery Orchestrator v5 or later
* Install AWS CLI
  * Configure AWS CLI

  AWS CLI needs to be installed on Veeam BNR server
  * For AWS Recovery need AWS CLI:
    Documentation:
	  https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html

	  Download:
	  https://awscli.amazonaws.com/AWSCLIV2.msi

	  Run installer on command line:
	  msiexec.exe /i https://awscli.amazonaws.com/AWSCLIV2.msi

    Create IAM role in AWS Console:
	  https://docs.aws.amazon.com/cli/latest/userguide/getting-started-prereqs.html

    Run - aws configure - command to set default perimeters:
	  Access key
	  Secret key
	  Default region
	  Default Output format
      Run the aws configure as the Orchestrator service account


## Additional Information

Rename aws-info.csv.template to aws-info.csv and place in a C:\VRO\Scripts folder on Veeam BNR server

Fill in for your environment - accessKey, secretKey,region, so on

In the Orchestration plan - Plan Steps
* Add a Step Parameter
    Name has to be VMName
    Text type with Default value = %source_vm_name%
    Adjust the Timeout value to allow for long recoveryinto AWS - I set mine for 1 hour
    Change the retry number to 0 to prevent partial restores from repeating


A tag is added to the EC2 instance for auto backup by VB-AWS
  Key=backup
  Value=recover
