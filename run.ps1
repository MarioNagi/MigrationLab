<#
.SYNOPSIS
    Run the MigrationLab pipeline end-to-end against a SQL Server instance.

.DESCRIPTION
    Executes the SQL files in dependency order:
      1. sql/00_setup/*.sql        (databases + CsvRaw load)
      2. sql/01_migrationlab/*.sql (schemas, tables, reporting views, ETL infra)
      3. sql/02_etl_procs/080_*.sql (stored-proc style, preferred)
         OR sql/02_etl_procs/100-150 (script style, pass -ScriptStyle)
      4. tests/run_all_tests.sql   (assertions; non-zero exit on failure)

    Northwind load (sql/00_setup/002_load_northwind_instructions.md) is
    manual. Apply Northwind before running this script.
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
    [switch]$SkipTests,
    [switch]$TrustServerCertificate
)

$ErrorActionPreference = 'Stop'
$repoRoot = $PSScriptRoot

function Resolve-Sqlcmd {
    foreach ($candidate in @('sqlcmd', 'sqlcmd.exe')) {
        $cmd = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
    }
    throw 'sqlcmd not found on PATH. Install SQL Server command-line tools.'
}

$sqlcmd = Resolve-Sqlcmd

function New-SqlcmdArgs {
    param(
        [string]$Database = 'master'
    )

    $args = @('-S', $ServerInstance, '-d', $Database, '-b', '-I')

    if ($UseIntegratedSecurity) {
        $args += '-E'
    } else {
        if (-not $SqlUser -or -not $SqlPassword) {
            throw '-SqlUser and -SqlPassword are required when -UseIntegratedSecurity:$false'
        }
        $args += @('-U', $SqlUser, '-P', $SqlPassword)
    }

    if ($TrustServerCertificate) {
        $args += '-C'
    }

    return $args
}

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
    $args = New-SqlcmdArgs -Database $Database
    $args += @('-i', $Path)

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

    $args = New-SqlcmdArgs -Database $Database
    $args += @('-Q', $Query)

    & $sqlcmd @args
    if ($LASTEXITCODE -ne 0) {
        throw "sqlcmd query failed: $Query"
    }
}

function Invoke-SqlPhase {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PhaseName,
        [Parameter(Mandatory = $true)]
        [string[]]$Files,
        [string]$Database = 'master'
    )

    Write-Host ''
    Write-Host "[$PhaseName]" -ForegroundColor Cyan
    foreach ($file in $Files) {
        Invoke-SqlFile -Path $file -Database $Database
    }
}

$startedAt = Get-Date
Write-Host 'MigrationLab runner' -ForegroundColor Green
Write-Host "  Server:   $ServerInstance"
Write-Host "  Auth:     $(if ($UseIntegratedSecurity) { 'Integrated' } else { "SQL ($SqlUser)" })"
Write-Host "  Style:    $(if ($ScriptStyle) { 'step-by-step scripts' } else { 'stored procedures' })"

if (-not $SkipSetup) {
    $setupFiles = @(
        "$repoRoot/sql/00_setup/001_create_databases.sql",
        "$repoRoot/sql/00_setup/003_create_csvraw_tables.sql",
        "$repoRoot/sql/00_setup/004_generate_csvraw_from_northwind.sql",
        "$repoRoot/sql/00_setup/005_generate_csvraw_netnew.sql",
        "$repoRoot/sql/00_setup/006_validate_csvraw_load.sql"
    )
    Write-Host ''
    Write-Host 'NOTE: sql/00_setup/002_load_northwind_instructions.md is manual.' -ForegroundColor Yellow
    Write-Host '      Apply Northwind (instnwnd.sql) before continuing if not already loaded.' -ForegroundColor Yellow
    Invoke-SqlPhase -PhaseName '00_setup' -Files $setupFiles
} else {
    Write-Host ''
    Write-Host '[00_setup] skipped (-SkipSetup)' -ForegroundColor DarkGray
}

$migrationLabFiles = @(
    "$repoRoot/sql/01_migrationlab/010_create_schemas.sql",
    "$repoRoot/sql/01_migrationlab/020_create_snapshot_tables.sql",
    "$repoRoot/sql/01_migrationlab/030_create_ref_tables.sql",
    "$repoRoot/sql/01_migrationlab/040_create_work_tables.sql",
    "$repoRoot/sql/01_migrationlab/050_create_target_model_tables.sql",
    "$repoRoot/sql/01_migrationlab/060_create_target_tables.sql",
    "$repoRoot/sql/01_migrationlab/075_create_etl_infra.sql",
    "$repoRoot/sql/01_migrationlab/070_create_reporting_views.sql"
)
Invoke-SqlPhase -PhaseName '01_migrationlab' -Files $migrationLabFiles -Database 'MigrationLab'

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

    Write-Host ''
    Write-Host '[etl.usp_RunAll]' -ForegroundColor Cyan
    Invoke-SqlQuery -Query 'DECLARE @b VARCHAR(50); EXEC etl.usp_RunAll @BatchID = @b OUTPUT; PRINT @b;' `
        -Database 'MigrationLab'
}

if (-not $SkipTests) {
    $testFiles = @(
        "$repoRoot/tests/010_test_reconciliation_invariant.sql",
        "$repoRoot/tests/020_test_no_orphan_crosswalk.sql",
        "$repoRoot/tests/030_test_no_duplicate_target_ids.sql",
        "$repoRoot/tests/040_test_survivor_in_target.sql",
        "$repoRoot/tests/050_test_required_fields.sql",
        "$repoRoot/tests/060_test_runlog_clean_run.sql"
    )
    if (($testFiles | Where-Object { -not (Test-Path $_) }).Count -eq 0) {
        Invoke-SqlPhase -PhaseName 'tests' -Files $testFiles -Database 'MigrationLab'
    } else {
        Write-Host ''
        Write-Host '[tests] skipped - one or more test files not found' -ForegroundColor DarkGray
    }
} else {
    Write-Host ''
    Write-Host '[tests] skipped (-SkipTests)' -ForegroundColor DarkGray
}

$elapsed = (Get-Date) - $startedAt
Write-Host ''
Write-Host ("Done in {0:n1}s." -f $elapsed.TotalSeconds) -ForegroundColor Green
