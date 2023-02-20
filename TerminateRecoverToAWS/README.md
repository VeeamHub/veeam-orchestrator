# Veeam Recovery Orchestrator - Terminate Recover to AWS VMs 

## Author

Marty Williams (@skitch210)

## Function

This script is designed to help automate the termination of recovered VMs recvoered from a Recovery Orchestrator Plan to AWS
This should be used as a Post Plan step when testing - like Datalab execution but skipped if a real DR situation


***NOTE:*** Before executing this script in a production environment, I strongly recommend you:

* Fully understand what the script is doing
* Test the script in a lab environment
* Have executed the restore-to-aws script to populate the dnsinfo.csv file

## Known Issues

* Requires the dnsinfo.csv created by the restore-to-aws script

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
* Add to Post Plan Steps of the Recovery plan
    * Set to not Execute if an actual DR and not a test