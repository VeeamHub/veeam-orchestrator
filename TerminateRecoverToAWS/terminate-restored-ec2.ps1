#Please Update the vbaws-info.csv for your settings
$awsCSV = "C:\VRO\Scripts\aws-info.csv" #CSV File to read from.
$awsInfo =Import-Csv $awsCSV

$Env:AWS_ACCESS_KEY_ID=$awsInfo.accessKey
$Env:AWS_SECRET_ACCESS_KEY=$awsInfo.secretKey
$Env:AWS_DEFAULT_REGION=$awsInfo.region

#Import CSV file to set parameters
Write-Host "Capturing data for recovery"
$FileCSV = "C:\VRO\Scripts\dnsinfo.csv" #CSV File to read from.
$VMinfo=Import-Csv $FileCSV
Write-Host "Terminating" $VMinfo.Count "VM(s)..."

# Get the recovered EC2 instances from the dnsInfo created from restore-to-aws script
for ($i = 0; $i -lt $VMinfo.Count; $i++)
{
    #Pick VM/EC2 from csv file
    $vmName = $VMinfo[$i].Server
    Write-Host $VMinfo[$i].Server 

    
    write-host "Get the EC2 Instance ID to Terminate"
    $command = "C:\Program Files\Amazon\AWSCLIV2\aws.exe"
    $params = "ec2 describe-instances --filters Name=tag-value,Values=$vmName"
    $params = $params.Split(" ")
    $ec2Instance = & "$command" $params | ConvertFrom-Json
    $ec2ID = $ec2Instance.Reservations.Instances.InstanceId

    write-host "EC2 Instance to Terminate: " $ec2ID

    write-host "Call AWS to Terminate Instance"
    $params1 = "ec2 terminate-instances --instance-ids $ec2ID"
    $params1 = $params1.Split(" ")
    $ec2Term = & "$command" $params1 | ConvertFrom-Json

    write-host "EC2 Terminate Status: " $ec2Term.TerminatingInstances.CurrentState.Name
}