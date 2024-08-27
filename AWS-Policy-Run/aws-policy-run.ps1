Write-Host "Set AWS Info"

# Please Update the vb-aws-info.csv for your settings
$vbawsCSV = "C:\VRO\CSVs\vb-aws-info.csv" #CSV File to read from.
$vbawsInfo = Import-Csv $vbawsCSV

$Env:AWS_ACCESS_KEY_ID=$vbawsInfo.accessKey
$Env:AWS_SECRET_ACCESS_KEY=$vbawsInfo.secretKey
$Env:AWS_DEFAULT_REGION=$vbawsInfo.region

# Name of VB AWS Appliance in AWS
$name = $vbawsInfo.vbawsName

# Get Public IP address of VB AWS Appliance
$vbAwsInstance = aws ec2 describe-instances --filters "Name=tag-value,Values=$name" | ConvertFrom-Json
$url = $vbAwsInstance.Reservations.Instances.PublicIpAddress

# Set the URL and token URL
$base = "https://" + $url + ":11005/api/v1/"
$url1 = $base + "token"

$creds = @{
 "grant_type" = "password"
 "username" = $vbawsInfo.username
 "password" = $vbawsInfo.password
}

# Set Headers for Token URL 
$headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$headers.Add("x-api-version", "1.5-rev1")
$headers.Add("Content-Type", "application/x-www-form-urlencoded")
$headers.Add("Accept", "application/json")

# Setup the Rest API Bearer token
 $key = Invoke-RestMethod -Method 'Post' -Uri $url1 -Body $creds -Headers $headers
 $bear = "Bearer"
 $key1 = $key[0].access_token
 $auth = $bear + " " + $key1

 # Set Header with Bearer token
$headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$headers.Add("x-api-version", "1.5-rev1")
$headers.Add("Content-Type", "application/x-www-form-urlencoded")
$headers.Add("Accept", "application/json")
$headers.Add("Authorization",$auth)


Write-Host "Connect to VB-AWS Rest API"

# Get the Policy ID from the selected policy
$urlPolGet = $base + "virtualMachines/policies?SearchPattern=" + $vbawsInfo.policy
$urlPolicy = Invoke-RestMethod $urlPolGet -Method 'GET' -Headers $headers

Write-Host "Policy ID: " $urlPolicy.results.id 

# Start the selected policy
$urlPolStart = $base + "virtualMachines/policies/" + $urlPolicy.results.id + "/start"
$urlPolicyStart = Invoke-RestMethod $urlPolStart -Method 'POST' -Headers $headers

Write-Host "Policy Session: " $urlPolicyStart.sessionId

# Get the policy Status to verify last run time
$urlPolSts = $base + "sessions/" + $urlPolicyStart.sessionId
$urlPolicyStatus = Invoke-RestMethod $urlPolSts -Method 'GET' -Headers $headers

Write-Host "Policy is currently: " $urlPolicyStatus.status
Write-Host "Policy execution time: " $urlPolicyStatus.executionStartTime
