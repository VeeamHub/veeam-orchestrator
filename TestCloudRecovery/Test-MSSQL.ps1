<#
.SYNOPSIS
  VRO custom step (Azure Run Command): verify SQL databases inside the recovered VM.

.DESCRIPTION
  - Designed to run LOCALLY inside the guest via Azure Run Command (Execute Location = In-Guest OS).
  - If SQLCredential is NOT provided -> Windows (Integrated) auth.
  - If SQLCredential IS provided -> SQL auth.
  - Supports SqlInstance='ALL' to enumerate all local instances.
  - Supports Database='ALL' to enumerate DBs on each instance.
  - Excludes system DBs by default (toggle with -IncludeSystemDatabases).

.EXIT CODES
  0 = All checks succeeded
  1 = One or more DB checks failed / no results
  3 = SQL login/connection failure (all failures are connect/login)
  4 = Unexpected error
#>

[CmdletBinding()]
param(
  # --- SQL auth (optional) ---
  [string]$SQLCredentialUsername,
  [string]$SQLCredentialPassword,

  # --- SQL scope ---
  [Parameter(Mandatory=$true)]
  [string]$SqlInstance,          # 'ALL' or e.g. 'MSSQLSERVER' or '.\INST' or 'tcp:localhost,1433'
  [Parameter(Mandatory=$true)]
  [string]$Database,             # 'ALL' or single DB name

  # --- Options ---
  [int]$SqlPort = 1433,          # used for TCP fallback
  [switch]$IncludeSystemDatabases,
  [int]$ConnectionTimeoutSec = 15
)

# ---------- helpers ----------
function _val($v, $fallback='Unknown') { if ($null -eq $v) {return $fallback}; if ($v -is [string] -and $v.Trim() -eq '') {return $fallback}; return $v }

$ErrorActionPreference = 'Stop'

# Decide SQL auth mode
$useIntegrated = $true
$sqlUser = $null
$sqlPass = $null
if ($SQLCredentialUsername) {
  $useIntegrated = $false
  $sqlUser = $SQLCredentialUsername
  $sqlPass = $SQLCredentialPassword
}

function New-Result([string]$inst,[string]$db) {
  [pscustomobject]@{
    SqlInstance   = $inst
    Database      = $db
    ServerVersion = $null
    DbState       = $null
    IsReadOnly    = $null
    RecoveryModel = $null
    RoundTripMs   = $null
    Detail        = $null
    Success       = $false
  }
}

function Get-LocalSqlInstanceNames {
  # Real instance names live under these keys as value NAMES (not properties)
  $paths = @(
    'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Microsoft SQL Server\Instance Names\SQL'
  )

  $names = @()
  foreach ($p in $paths) {
    if (Test-Path $p) {
      $key = Get-Item -Path $p
      # GetValueNames() returns only the actual value names (instance names)
      $names += $key.GetValueNames()
    }
  }

  # Fallbacks in case the key is missing or empty
  if (-not $names -or $names.Count -eq 0) {
    # Try deriving named instances from services like MSSQL$INST
    $svcNames = Get-Service -Name 'MSSQL*' -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -like 'MSSQL$*' } |
                ForEach-Object { $_.Name -replace '^MSSQL\$', '' }
    if ($svcNames) { $names = $svcNames } else { $names = @('MSSQLSERVER') }
  }

  return $names | Sort-Object -Unique
}

function Get-ServerStringsForInstance([string]$instName,[int]$port) {
  # Prefer Shared Memory (lpc) inside the VM; fallback to TCP:localhost,port
  if ($instName -eq 'MSSQLSERVER' -or $instName -eq '.' -or $instName -eq 'localhost') {
    @("lpc:.", "tcp:localhost,$port")
  } else {
    # Normalize like '.\INST' → 'lpc:.\INST'
    $normalized = ($instName -match '^[\\\.]') ? $instName : ".\$instName"
    @("lpc:$normalized", "tcp:localhost,$port")
  }
}

function Resolve-ExplicitServerStrings([string]$input,[int]$port) {
  # If user already provided a protocol, respect it
  if ($input -match '^(lpc:|tcp:|np:)') { return @($input) }

  # Named instance possibly including host: "HOST\INST" or ".\INST"
  if ($input -match '^[^\\]+\\([^,]+)$' -or $input -match '^[\\\.]+\\([^,]+)$') {
    $inst = $input.Split('\')[-1]
    return @("lpc:.\$inst", "tcp:localhost,$port")
  }

  # Default instance keywords
  if ($input -in @('MSSQLSERVER','.','localhost')) {
    return @("lpc:.", "tcp:localhost,$port")
  }

  # Bare instance name "INST"
  if ($input -match '^[^\\,]+$') {
    return @("lpc:.\$input", "tcp:localhost,$port")
  }

  # Fallback: treat as given, plus TCP localhost
  return @($input, "tcp:localhost,$port")
}

function Invoke-DbSingleCheck([string]$server,[string]$db,[bool]$UseIntegrated,[string]$SqlUser,[string]$SqlPassword,[int]$TimeoutSec) {
  $res = New-Result -inst $server -db $db
  try {
    Add-Type -AssemblyName System.Data
    if ($UseIntegrated) {
      $connStr = "Server=$server;Database=$db;Integrated Security=SSPI;Encrypt=True;TrustServerCertificate=True;Connection Timeout=$TimeoutSec"
    } else {
      $connStr = "Server=$server;Database=$db;User ID=$SqlUser;Password=$SqlPassword;Encrypt=True;TrustServerCertificate=True;Connection Timeout=$TimeoutSec"
    }
    $sw   = [System.Diagnostics.Stopwatch]::StartNew()
    $conn = New-Object System.Data.SqlClient.SqlConnection $connStr
    try { $conn.Open() } catch { throw "SQL connect failed: $($_.Exception.Message)" }

    # Server version
    $cmd = $conn.CreateCommand()
    $cmd.CommandText = "SELECT CONVERT(nvarchar(128), SERVERPROPERTY('ProductVersion'))"
    $res.ServerVersion = $cmd.ExecuteScalar()

    # DB state
    $cmd = $conn.CreateCommand()
    $cmd.CommandText = @"
SELECT TOP(1) name, state_desc, is_read_only, recovery_model_desc
FROM sys.databases
WHERE name = @db
"@
    $null = $cmd.Parameters.Add("@db",[System.Data.SqlDbType]::NVarChar,128)
    $cmd.Parameters["@db"].Value = $db
    $rdr = $cmd.ExecuteReader()
    if (-not $rdr.Read()) { $rdr.Close(); throw "Database '$db' not found." }
    $res.DbState       = $rdr["state_desc"]
    $res.IsReadOnly    = [bool]$rdr["is_read_only"]
    $res.RecoveryModel = $rdr["recovery_model_desc"]
    $rdr.Close()

    # Sanity query
    $cmd = $conn.CreateCommand()
    $cmd.CommandText = "SELECT 1"
    $null = $cmd.ExecuteScalar()

    $sw.Stop()
    $res.RoundTripMs = [int]$sw.ElapsedMilliseconds
    if ($res.DbState -eq 'ONLINE') { $res.Detail="Database is ONLINE and queryable."; $res.Success=$true }
    else                           { $res.Detail="Database state is '$($res.DbState)'; expected 'ONLINE'."; $res.Success=$false }

    $conn.Close()
  }
  catch [System.Data.SqlClient.SqlException] {
    $err = $_.Exception
    $states = @(); foreach ($e in $err.Errors) { $states += "Number=$($e.Number) State=$($e.State)" }
    $res.Detail  = "SQL connect failed: $($err.Message) [$($states -join '; ')]"
    $res.Success = $false
  }
  catch {
    $res.Detail  = "Verification failed: $($_.Exception.Message)"
    $res.Success = $false
  }
  return $res
}

function Get-UserDatabases([string]$server,[bool]$UseIntegrated,[string]$SqlUser,[string]$SqlPassword,[int]$TimeoutSec,[bool]$includeSystem) {
  $dbs = @()
  try {
    Add-Type -AssemblyName System.Data
    $connStr = if ($UseIntegrated) {
      "Server=$server;Database=master;Integrated Security=SSPI;Encrypt=True;TrustServerCertificate=True;Connection Timeout=$TimeoutSec"
    } else {
      "Server=$server;Database=master;User ID=$SqlUser;Password=$SqlPassword;Encrypt=True;TrustServerCertificate=True;Connection Timeout=$TimeoutSec"
    }
    $conn = New-Object System.Data.SqlClient.SqlConnection $connStr
    $conn.Open()
    $cmd = $conn.CreateCommand()
    if ($includeSystem) {
      $cmd.CommandText = "SELECT name FROM sys.databases"
    } else {
      $cmd.CommandText = @"
SELECT name
FROM sys.databases
WHERE name NOT IN ('master','model','msdb','tempdb')
"@
    }
    $rdr = $cmd.ExecuteReader()
    while ($rdr.Read()) { $dbs += [string]$rdr["name"] }
    $rdr.Close(); $conn.Close()
  } catch {}
  return $dbs
}

try {
  Write-Host "Starting SQL verification (Execute Location: In-Guest OS via Azure Run Command)"
  Write-Host "  SqlInstance : $SqlInstance"
  Write-Host "  Database    : $Database"
  Write-Host "  Auth        : $(if($useIntegrated){'Windows (Integrated)'}else{'SQL Authentication'})"

  # Determine which instances to check
  $instanceInputs = @()
  if ($SqlInstance -eq 'ALL') {
    $instanceInputs = Get-LocalSqlInstanceNames
  } else {
    $instanceInputs = @($SqlInstance)
  }

  $results = New-Object System.Collections.Generic.List[object]

  foreach ($inst in $instanceInputs) {
    # Build server strings to try for this instance
    $serverStrings = if ($SqlInstance -eq 'ALL') {
      Get-ServerStringsForInstance -instName $inst -port $SqlPort
    } else {
      Resolve-ExplicitServerStrings -input $inst -port $SqlPort
    }

    # Determine DB scope
    $dbList = @()
    if ($Database -eq 'ALL') {
      # Enumerate DBs using the first working server string
      $dbList = $null
      foreach ($sv in $serverStrings) {
        $dbList = Get-UserDatabases -server $sv -UseIntegrated:$useIntegrated -SqlUser $sqlUser -SqlPassword $sqlPass `
                  -TimeoutSec $ConnectionTimeoutSec -includeSystem:$IncludeSystemDatabases
        if ($dbList -and $dbList.Count -gt 0) { break }
      }
      if (-not $dbList) { $dbList = @() }
    } else {
      $dbList = @($Database)
    }

    if (-not $dbList -or $dbList.Count -eq 0) {
      # No DBs enumerated; try to surface useful error by attempting a single check
      foreach ($sv in $serverStrings) {
        $results.Add( (Invoke-DbSingleCheck -server $sv -db $Database -UseIntegrated:$useIntegrated -SqlUser $sqlUser -SqlPassword $sqlPass -TimeoutSec $ConnectionTimeoutSec) )
        break
      }
      continue
    }

    foreach ($db in $dbList) {
      # Try first server string (lpc preferred)
      $sv = $serverStrings[0]
      $results.Add( (Invoke-DbSingleCheck -server $sv -db $db -UseIntegrated:$useIntegrated -SqlUser $sqlUser -SqlPassword $sqlPass -TimeoutSec $ConnectionTimeoutSec) )
    }
  }

  if ($null -eq $results -or $results.Count -eq 0) {
    Write-Host "No results returned from in-guest verification."
    exit 1
  }

  # ---------- pretty print & exit code ----------
  $failCount = 0; $sqlFailures = 0
  foreach ($row in $results) {
    Write-Host "SQL Verification Result:"
    Write-Host (" Instance      : {0}" -f (_val $row.SqlInstance))
    Write-Host (" Database      : {0}" -f (_val $row.Database))
    Write-Host (" ServerVersion : {0}" -f (_val $row.ServerVersion))
    Write-Host (" State         : {0}" -f (_val $row.DbState))
    Write-Host (" ReadOnly      : {0}" -f (_val $row.IsReadOnly))
    Write-Host (" RecoveryModel : {0}" -f (_val $row.RecoveryModel))
    Write-Host (" RoundTripMs   : {0}" -f (_val $row.RoundTripMs 'N/A'))
    Write-Host (" Detail        : {0}" -f (_val $row.Detail ''))
    if (-not $row.Success) {
      $failCount++
      if ($row.Detail -like 'SQL connect failed*') { $sqlFailures++ }
      Write-Host " FAILED"
    } else { Write-Host " OK" }
    Write-Host ""
  }

  if ($failCount -eq 0) {
    Write-Host " All SQL checks succeeded."
    exit 0
  } elseif ($sqlFailures -gt 0 -and $sqlFailures -eq $failCount) {
    exit 3   # all failures are SQL login/connect
  } else {
    exit 1   # one or more DB checks failed
  }
}
catch {
  Write-Host " Unexpected error: $($_.Exception.Message)"
  exit 4
}