# Automated Veeam Orchestrator Power on VB-AWS Appliance 

## Author

Marty Williams (@skitch210)

## Function

This script is designed to help automate the power on of a Veeam Backup for AWS Appliance after DR Recovery of workloads to EC2


***NOTE:*** Before executing this script in a production environment, I strongly recommend you:

* Read look over the Veeam Backup for AWS documentation
* Fully understand what the script is doing
* Test the script in a lab environment
* You need to have previously deployed the VBAWS Appliance into your VPC and have configured policies
    * This is internded to be a part of an overall DR/Migration strategy and pre-planning is key

## Known Issues

* None currently


## Requirements

* Veeam Backup & Replication 11a or later
* Veeam Backup for AWS Appliance deployed
* Install AWS CLI
  * Configure AWS CLI

  AWS CLI needs to be installed on Veeam VRO server
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

Rename aws-info.csv.template to aws-info.csv and place in a C:\VRO\CSVs folder on Veeam VRO server

Fill in for your environment - accessKey, secretKey,region, so on

In the Orchestration plan - Plan Steps
* This is best placed in a Post Plan Step after performing a recovery to AWS