Write-Host "Set VRO Info"

#Please Update the vro-run-restore-plan.csv for your settings
$vroCSV = "C:\VRO\CSVs\vro-run-restore-plan.csv" #CSV File to read from.
$vroInfo = Import-Csv $vroCSV

[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Set the URL and token URL
$base = $vroInfo.baseUrl
$url = $base + "/api/token"

$creds = @{
 "grant_type" = "password"
 "username" = $vroInfo.username
 "password" = $vroInfo.password
}

# Setup the Rest API Bearer token
 $key = Invoke-RestMethod -Method 'Post' -Uri $url -Body $creds -Headers $headers
 $bear = "Bearer"
 $key1 = $key[0].access_token
 $auth = $bear + " " + $key1

 $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
 $headers.Add("Content-Type", "application/json")
 $headers.Add("Authorization",$auth)

Write-Host "Connect to VRO Rest API"

# Get the Plan ID for the selected plan
$urlPlanGet = $base + '/api/v7.1/Plans?filter=[{"property":"name","operator":"==","value": "' + $vroInfo.plan + '"}]'
$urlPlan = Invoke-RestMethod $urlPlanGet -Method 'GET' -Headers $headers

Write-Host "Plan ID: " $urlPlan.data.id 
Write-Host "Recovery Location: " $urlPlan.data.recoveryLocationName

# Build Body for API call - Restore ID Info
$bodyJ = '"' + $urlPlan.data.recoveryLocationId + '"'
$body = @"
{
  `"restoreLocationId`": $bodyJ,
  `"virusScan`": false,
  `"yaraScan`": false

}
"@

# Post API call to Run the Recovery Plan
$urlRunPost = $base + '/api/v7.1/Plans/' + $urlPlan.data.id + '/Restore'
$urlRun = Invoke-RestMethod $urlRunPost -Method 'Post' -Headers $headers -Body $body
 
