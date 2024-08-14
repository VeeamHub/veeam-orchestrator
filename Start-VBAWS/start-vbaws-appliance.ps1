Write-Host "Set AWS Info"

#Please Update the vbaws-info.csv for your settings
$awsCSV = "C:\VRO\CSVs\aws-info.csv" #CSV File to read from.
$awsInfo =Import-Csv $awsCSV

$Env:AWS_ACCESS_KEY_ID=$awsInfo.accessKey
$Env:AWS_SECRET_ACCESS_KEY=$awsInfo.secretKey
$Env:AWS_DEFAULT_REGION=$awsInfo.region

$instName = $awsInfo.vbawsName

write-host "Get the EC2 Instance ID for VBAWS"
$command = "C:\Program Files\Amazon\AWSCLIV2\aws.exe"
$params = "ec2 describe-instances --filters Name=tag-value,Values=$instName"
$params = $params.Split(" ")
$ec2Instance1 = & "$command" $params | ConvertFrom-Json


$ec2ID = $ec2Instance1.Reservations.Instances.InstanceId

write-host "EC2 Instance: " $ec2ID


write-host "Call AWS to start VBAWS Appliance Instance"
$command1 = "C:\Program Files\Amazon\AWSCLIV2\aws.exe"
$params1 = "ec2 start-instances --instance-ids $ec2ID"
$params1 = $params1.Split(" ")
$ec2Start = & "$command1" $params1 | ConvertFrom-Json

write-host "EC2 start Status: " $ec2Start.StartingInstances.CurrentState.Name

# Wait loop until instance is Running
do {
    $ec2Sts = aws ec2 describe-instance-status --include-all-instances --instance-ids $ec2ID | ConvertFrom-Json
    Start-Sleep -Seconds 15
} until ($ec2Sts.InstanceStatuses.InstanceState.Name -eq 'running')

write-host $instName 'is now' $ec2Sts.InstanceStatuses.InstanceState.Name
