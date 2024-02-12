Write-Host "Set Azure Info"

#Please Update the azr-enable-policy.csv for your settings
$azrCSV = "C:\VRO\CSVs\azr-enable-policy.csv" #CSV File to read from.
$azrInfo = Import-Csv $azrCSV

[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Set the URL and token URL
$base = $azrInfo.baseUrl
$url = $base + "/api/oauth2/token"

$creds = @{
 "grant_type" = "password"
 "username" = $azrInfo.username
 "password" = $azrInfo.password
}

# Setup the Rest API Bearer token
 $key = Invoke-RestMethod -Method 'Post' -Uri $url -Body $creds -Headers $headers
 $bear = "Bearer"
 $key1 = $key[0].access_token
 $auth = $bear + " " + $key1

 $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
 $headers.Add("Accept", "application/json")
 $headers.Add("Authorization",$auth)


Write-Host "Connect to VB-Azure Rest API"

# Get the Policy ID from the selected policy
$urlPolGet = $base + "/api/v6/policies/virtualMachines?PolicyName=" + $azrInfo.policy
$urlPolicy = Invoke-RestMethod $urlPolGet -Method 'GET' -Headers $headers

Write-Host "Policy ID: " $urlPolicy.results.id 
Write-Host "Policy is Enabled: " $urlPolicy.results.isEnabled

# Enable the selected policy
$urlPolEn = $base + "/api/v6/policies/virtualMachines/" + $urlPolicy.results.id + "/enable"
$urlPolicyEnable = Invoke-RestMethod $urlPolEn -Method 'POST' -Headers $headers

Write-Host "Set policy to be Enabled"

# Get policy info to verify it is now Enabled
$urlPolicy = Invoke-RestMethod $urlPolGet -Method 'GET' -Headers $headers

Write-Host "Policy is Enabled: " $urlPolicy.results.isEnabled
Write-Host "Start policy for current backup"

# Start the policy to get current backup
$urlPolRun = $base + "/api/v6/policies/virtualMachines/" + $urlPolicy.results.id + "/start"
$urlPolicyRun = Invoke-RestMethod $urlPolRun -Method 'POST' -Headers $headers

Write-Host "Policy is currently: " $urlPolicyRun.status
