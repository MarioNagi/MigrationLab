<#
.SYNOPSIS
    Run the MigrationLab pipeline end-to-end against a SQL Server instance.

.DESCRIPTION
    Executes every SQL file in the lab in dependency order:
      1. sql/00_setup/*.sql        (databases + CsvRaw load)
      2. sql/01_migrationlab/*.sql (schemas, tables, reporting views, ETL infra)
      3. sql/02_etl_procs/080_*.sql (stored-proc style — preferred)
         OR all sql/02_etl_procs/*.sql (script style — pass -ScriptStyle)
      4. tests/run_all_tests.sql   (assertions; non-zero exit on failure)

    Northwind load (sql/00_setup/002_load_northwind_instructions.md) is
    manual — instnwnd.sql must be applied before running this script. The
    runner will skip the setup phase if -SkipSetup is passed.

.PARAMETER ServerInstance
    SQL Server instance, e.g. "localhost", "(local)\SQLEXPRESS", or
    "tcp:myserver,1433".

.PARAMETER UseIntegratedSecurity
    Use Windows authentication. Default is $true.

.PARAMETER SqlUser
    SQL login. Required when -UseIntegratedSecurity:$false.

.PARAMETER SqlPassword
    SQL password. Required when -UseIntegratedSecurity:$false.

.PARAMETER SkipSetup
    Skip sql/00_setup (use this on subsequent runs after the databases
    and CsvRaw data already exist).

.PARAMETER ScriptStyle
    Run the educational step-by-step scripts (110, 120, 130, 140, 150)
    instead of the stored-procedure orchestrator (080 + EXEC usp_RunAll).
    Default is the stored-proc style.

.PARAMETER SkipTests
    Skip the tests/ phase.

.EXAMPLE
    ./run.ps1 -ServerInstance "localhost"

.EXAMPLE
    ./run.ps1 -ServerInstance "(local)\SQLEXPRESS" -SkipSetup

.EXAMPLE
    ./run.ps1 -ServerInstance "tcp:db,1433" -UseIntegratedSecurity:$false -SqlUser sa -SqlPassword $env:SA_PASSWORD
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ServerInstance,

    [bool]$UseIntegratedSecurity = $true,
    [string]$SqlUser,
    [string]$SqlPassword,

    [switch]$SkipSetup,
    [switch]$ScriptStyle,
    [switch]$SkipTests
)

$ErrorActionPreference = 'Stop'
$repoRoot = $PSScriptRoot

function Resolve-Sqlcmd {
    $candidates = @('sqlcmd', 'sqlcmd.exe')
    foreach ($c in $candidates) {
        $cmd = Get-Command $c -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
    }
    throw "sqlcmd not found on PATH. Install SQL Server command-line tools: https://learn.microsoft.com/sql/tools/sqlcmd/sqlcmd-utility"
}

$sqlcmd = Resolve-Sqlcmd

function Invoke-SqlFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [string]$Database = 'master'
    )

    if (-not (Test-Path $Path)) {
        throw "SQL file not found: $Path"
    }

    Write-Host "  -> $($Path.Substring($repoRoot.Length + 1))" -ForegroundColor DarkGray

    $args = @(
        '-S', $ServerInstance,
        '-d', $Database,
        '-i', $Path,
        '-b'                    # exit non-zero on T-SQL error
    )

    if ($UseIntegratedSecurity) {
        $args += '-E'
    } else {
        if (-not $SqlUser -or -not $SqlPassword) {
            throw '-SqlUser and -SqlPassword are required when -UseIntegratedSecurity:$false'
        }
        $args += @('-U', $SqlUser, '-P', $SqlPassword)
    }

    & $sqlcmd @args
    if ($LASTEXITCODE -ne 0) {
        throw "sqlcmd failed (exit $LASTEXITCODE) on $Path"
    }
}

function Invoke-SqlQuery {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Query,
        [string]$Database = 'MigrationLab'
    )

    $args = @('-S', $ServerInstance, '-d', $Database, '-Q', $Query, '-b')
    if ($UseIntegratedSecurity) { $args += '-E' }
    else { $args += @('-U', $SqlUser, '-P', $SqlPassword) }

    & $sqlcmd @args
    if ($LASTEXITCODE -ne 0) { throw "sqlcmd query failed: $Query" }
}

function Invoke-SqlPhase {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PhaseName,
        [Parameter(Mandatory = $true)]
        [string[]]$Files,
        [string]$Database = 'master'
    )

    Write-Host ""
    Write-Host "[$PhaseName]" -ForegroundColor Cyan
    foreach ($f in $Files) {
        Invoke-SqlFile -Path $f -Database $Database
    }
}

$startedAt = Get-Date
Write-Host "MigrationLab runner" -ForegroundColor Green
Write-Host "  Server:   $ServerInstance"
Write-Host "  Auth:     $(if ($UseIntegratedSecurity) { 'Integrated' } else { "SQL ($SqlUser)" })"
Write-Host "  Style:    $(if ($ScriptStyle) { 'step-by-step scripts' } else { 'stored procedures' })"

# -------------------- 00_setup --------------------
if (-not $SkipSetup) {
    $setupFiles = @(
        "$repoRoot/sql/00_setup/001_create_databases.sql",
        "$repoRoot/sql/00_setup/003_create_csvraw_tables.sql",
        "$repoRoot/sql/00_setup/004_generate_csvraw_from_northwind.sql",
        "$repoRoot/sql/00_setup/005_generate_csvraw_netnew.sql",
        "$repoRoot/sql/00_setup/006_validate_csvraw_load.sql"
    )
    Write-Host ""
    Write-Host "NOTE: sql/00_setup/002_load_northwind_instructions.md is manual." -ForegroundColor Yellow
    Write-Host "      Apply Northwind (instnwnd.sql) before continuing if not already loaded." -ForegroundColor Yellow

    Invoke-SqlPhase -PhaseName '00_setup' -Files $setupFiles
} else {
    Write-Host ""
    Write-Host "[00_setup] skipped (-SkipSetup)" -ForegroundColor DarkGray
}

# -------------------- 01_migrationlab --------------------
$mlFiles = @(
    "$repoRoot/sql/01_migrationlab/010_create_schemas.sql",
    "$repoRoot/sql/01_migrationlab/020_create_snapshot_tables.sql",
    "$repoRoot/sql/01_migrationlab/030_create_ref_tables.sql",
    "$repoRoot/sql/01_migrationlab/040_create_work_tables.sql",
    "$repoRoot/sql/01_migrationlab/050_create_target_model_tables.sql",
    "$repoRoot/sql/01_migrationlab/060_create_target_tables.sql",
    "$repoRoot/sql/01_migrationlab/070_create_reporting_views.sql",
    "$repoRoot/sql/01_migrationlab/075_create_etl_infra.sql"
)
Invoke-SqlPhase -PhaseName '01_migrationlab' -Files $mlFiles -Database 'MigrationLab'

# -------------------- 02_etl_procs --------------------
if ($ScriptStyle) {
    $etlFiles = @(
        "$repoRoot/sql/02_etl_procs/100_etl_refresh_snapshots.sql",
        "$repoRoot/sql/02_etl_procs/110_etl_build_work_otc.sql",
        "$repoRoot/sql/02_etl_procs/120_etl_build_work_ptp.sql",
        "$repoRoot/sql/02_etl_procs/130_etl_build_target_model.sql",
        "$repoRoot/sql/02_etl_procs/140_etl_load_target.sql",
        "$repoRoot/sql/02_etl_procs/150_etl_snapshot_target.sql"
    )
    Invoke-SqlPhase -PhaseName '02_etl_procs (script style)' -Files $etlFiles -Database 'MigrationLab'
} else {
    Invoke-SqlPhase -PhaseName '02_etl_procs (stored procs)' `
        -Files @("$repoRoot/sql/02_etl_procs/080_create_etl_procs.sql") `
        -Database 'MigrationLab'

    Write-Host ""
    Write-Host "[etl.usp_RunAll]" -ForegroundColor Cyan
    Invoke-SqlQuery -Query 'DECLARE @b VARCHAR(50); EXEC etl.usp_RunAll @BatchID = @b OUTPUT; PRINT @b;' `
        -Database 'MigrationLab'
}

# -------------------- tests --------------------
if (-not $SkipTests) {
    $testRunner = "$repoRoot/tests/run_all_tests.sql"
    if (Test-Path $testRunner) {
        Invoke-SqlPhase -PhaseName 'tests' -Files @($testRunner) -Database 'MigrationLab'
    } else {
        Write-Host ""
        Write-Host "[tests] skipped — $testRunner not found" -ForegroundColor DarkGray
    }
} else {
    Write-Host ""
    Write-Host "[tests] skipped (-SkipTests)" -ForegroundColor DarkGray
}

$elapsed = (Get-Date) - $startedAt
Write-Host ""
Write-Host ("Done in {0:n1}s." -f $elapsed.TotalSeconds) -ForegroundColor Green
