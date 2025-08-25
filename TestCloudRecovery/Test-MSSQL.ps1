<# 
.SYNOPSIS
  VRO custom step: verify SQL databases on a recovered VM (Azure Cloud Plan).

.DESCRIPTION
  - Uses WinRM to run inside the guest (Execute Location = In-Guest OS).
  - If SQLCredential is NOT provided -> Windows (Integrated) auth.
  - If SQLCredential IS provided -> SQL auth.
  - Supports SqlInstance='ALL' to enumerate all local instances.
  - Supports Database='ALL' to enumerate DBs on each instance.
  - Excludes system DBs by default (toggle with -IncludeSystemDatabases).

.EXIT CODES
  0 = All checks succeeded
  1 = One or more DB checks failed / no results
  2 = Remoting/WinRM failure
  3 = SQL login/connection failure (propagated to caller)
  4 = Unexpected error
#>

[CmdletBinding()]
param(
  # --- VRO "Credential" params arrive as split username/password strings ---
  [string]$WindowsCredentialUsername,
  [string]$WindowsCredentialPassword,

  [string]$SQLCredentialUsername,
  [string]$SQLCredentialPassword,

  # --- Target host to run inside (recovered VM name/IP) ---
  [Parameter(Mandatory=$true)]
  [string]$ComputerName,

  # --- SQL scope ---
  [Parameter(Mandatory=$true)]
  [string]$SqlInstance,          # 'ALL' or e.g. 'MSSQLVM\INST' or 'tcp:10.1.2.4,1433'
  [Parameter(Mandatory=$true)]
  [string]$Database,             # 'ALL' or single DB name

  # --- Options ---
  [int]$SqlPort = 1433,          # used when instance is bare host/IP and TCP is needed
  [switch]$IncludeSystemDatabases,
  [int]$ConnectionTimeoutSec = 15
)

# ---------- helpers ----------
function _val($v, $fallback='Unknown') { if ($null -eq $v) {return $fallback}; if ($v -is [string] -and $v.Trim() -eq '') {return $fallback}; return $v }

function Get-SqlHostFromInstance {
  param([string]$Instance)
  if ($Instance -eq 'ALL') { return $ComputerName }  # when ALL, we must rely on provided ComputerName
  $clean = ($Instance -replace '^\s*(tcp:|np:|lpc:)\s*', '')
  if ($clean -match '^(?<host>[^\\,]+)') { return $matches['host'] }
  return $clean
}

$ErrorActionPreference = 'Stop'
$winPwd = ConvertTo-SecureString $WindowsCredentialPassword -AsPlainText -Force
$winCred = New-Object System.Management.Automation.PSCredential($WindowsCredentialUsername, $winPwd)

# Decide SQL auth mode
$useIntegrated = $true
$sqlUser = $null
$sqlPass = $null
if ($SQLCredentialUsername) {
  $useIntegrated = $false
  $sqlUser = $SQLCredentialUsername
  $sqlPass = $SQLCredentialPassword
}

$targetHost = Get-SqlHostFromInstance -Instance $SqlInstance

Write-Host "Starting SQL verification (Execute Location: In-Guest OS)"
Write-Host "  VM/Computer: $ComputerName"
Write-Host "  SqlInstance : $SqlInstance"
Write-Host "  Database    : $Database"
Write-Host "  Auth        : $(if($useIntegrated){'Windows (Integrated)'}else{'SQL Authentication'})"

# ---------- remote script that runs INSIDE the VM ----------
$remoteCheck = {
  param(
    [string]$ScopeSqlInstance,     # 'ALL' or single literal
    [string]$ScopeDatabase,        # 'ALL' or single literal
    [int]   $RmtSqlPort,
    [bool]  $UseIntegrated,
    [string]$SqlUser,
    [string]$SqlPassword,
    [bool]  $IncludeSystemDbs,
    [int]   $TimeoutSec
  )

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
    if ($instName -eq 'MSSQLSERVER') {
      @("lpc:.", "tcp:localhost,$port")
    } else {
      @("lpc:.\$instName", "tcp:localhost,$port")
    }
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
      if ($UseIntegrated) {
        $connStr = "Server=$server;Database=master;Integrated Security=SSPI;Encrypt=True;TrustServerCertificate=True;Connection Timeout=$TimeoutSec"
      } else {
        $connStr = "Server=$server;Database=master;User ID=$SqlUser;Password=$SqlPassword;Encrypt=True;TrustServerCertificate=True;Connection Timeout=$TimeoutSec"
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

  $results = New-Object System.Collections.Generic.List[object]

  # Determine which instances to check
  $instanceNames = @()
  if ($ScopeSqlInstance -eq 'ALL') {
    $instanceNames = Get-LocalSqlInstanceNames
  } else {
    # If user passed lpc:/tcp:/named syntax, treat it as a standalone server string
    $instanceNames = @($ScopeSqlInstance)
  }

  foreach ($inst in $instanceNames) {
    # Build a list of server strings to try for this instance
    $serverStrings = @()
    if ($ScopeSqlInstance -eq 'ALL') {
      # Local, by instance name
      $serverStrings = Get-ServerStringsForInstance -instName $inst -port $RmtSqlPort
    } else {
      # Respect user's explicit instance string
      $serverStrings = @($inst)
    }

    # For Database scope
    $dbList = @()
    if ($ScopeDatabase -eq 'ALL') {
      # Try to fetch DB names using the first working server string
      $dbList = $null
      foreach ($sv in $serverStrings) {
        $dbList = Get-UserDatabases -server $sv -UseIntegrated:$UseIntegrated -SqlUser $SqlUser -SqlPassword $SqlPassword -TimeoutSec $TimeoutSec -includeSystem:$IncludeSystemDbs
        if ($dbList -and $dbList.Count -gt 0) { break }
      }
      if (-not $dbList) { $dbList = @() }  # none found, still proceed to surface connection errors in per-DB checks
    } else {
      $dbList = @($ScopeDatabase)
    }

    if (-not $dbList -or $dbList.Count -eq 0) {
      # No DBs were enumerated; still try a generic connection to surface useful errors
      foreach ($sv in $serverStrings) {
        $r = Invoke-DbSingleCheck -server $sv -db $ScopeDatabase -UseIntegrated:$UseIntegrated -SqlUser $SqlUser -SqlPassword $SqlPassword -TimeoutSec $TimeoutSec
        $results.Add($r)
        break
      }
      continue
    }

    foreach ($db in $dbList) {
      $checked = $false
      foreach ($sv in $serverStrings) {
        $r = Invoke-DbSingleCheck -server $sv -db $db -UseIntegrated:$UseIntegrated -SqlUser $SqlUser -SqlPassword $SqlPassword -TimeoutSec $TimeoutSec
        $results.Add($r)
        $checked = $true
        break  # we tried first server string; good enough if it connected
      }
      if (-not $checked) {
        $results.Add((New-Result -inst ($serverStrings -join ' | ') -db $db | ForEach-Object { $_.Detail='No usable server endpoint'; $_.Success=$false; $_ }))
      }
    }
  }

  return ,$results  # ensure array is returned even with one item
}

# ---------- invoke inside guest ----------
try {
  try {
    $out = Invoke-Command -ComputerName $ComputerName -Credential $winCred `
           -ScriptBlock $remoteCheck `
           -ArgumentList @($SqlInstance,$Database,$SqlPort,[bool]$useIntegrated,$sqlUser,$sqlPass,[bool]$IncludeSystemDatabases,$ConnectionTimeoutSec) `
           -ErrorAction Stop
  }
  catch {
    Write-Host "HTTP WinRM failed, attempting HTTPS (UseSSL)..."
    $out = Invoke-Command -ComputerName $ComputerName -UseSSL -Credential $winCred `
           -ScriptBlock $remoteCheck `
           -ArgumentList @($SqlInstance,$Database,$SqlPort,[bool]$useIntegrated,$sqlUser,$sqlPass,[bool]$IncludeSystemDatabases,$ConnectionTimeoutSec) `
           -ErrorAction Stop
  }

  if ($null -eq $out -or $out.Count -eq 0) {
    Write-Host "No results returned from in-guest verification."
    exit 1
  }

  # ---------- pretty print ----------
  $failCount = 0
  foreach ($row in $out) {
    Write-Host "SQL Verification Result:"
    Write-Host (" Instance      : {0}" -f (_val $row.SqlInstance))
    Write-Host (" Database      : {0}" -f (_val $row.Database))
    Write-Host (" ServerVersion : {0}" -f (_val $row.ServerVersion))
    Write-Host (" State         : {0}" -f (_val $row.DbState))
    Write-Host (" ReadOnly      : {0}" -f (_val $row.IsReadOnly))
    Write-Host (" RecoveryModel : {0}" -f (_val $row.RecoveryModel))
    Write-Host (" RoundTripMs   : {0}" -f (_val $row.RoundTripMs 'N/A'))
    Write-Host (" Detail        : {0}" -f (_val $row.Detail ''))
    if (-not $row.Success) { $failCount++ ; Write-Host "❌ FAILED" } else { Write-Host "✅ OK" }
    Write-Host ""
  }

  if ($failCount -eq 0) {
    Write-Host "✅ All SQL checks succeeded."
    exit 0
  } else {
    Write-Host "❌ $failCount check(s) failed."
    exit 1
  }
}
catch [System.Management.Automation.Remoting.PSRemotingTransportException] {
  Write-Host "❌ Remoting/WinRM failure to '$ComputerName': $($_.Exception.Message)"
  exit 2
}
catch {
  $msg = $_.Exception.Message
  if ($msg -like 'SQL connect failed*') {
    Write-Host "❌ SQL login/connection failure: $msg"
    exit 3
  } else {
    Write-Host "❌ Unexpected error: $msg"
    exit 4
  }
}