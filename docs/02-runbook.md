# Runbook

This runbook lists the recommended execution order and what to validate at each stage.

## 0) Prerequisites
- SQL Server with permission to create databases
- Northwind database installed (see `sql/00_setup/002_load_northwind_instructions.md`)

## 1) Setup CsvRaw
1. Create databases:
   - `sql/00_setup/001_create_databases.sql`
2. Create CsvRaw tables:
   - `sql/00_setup/003_create_csvraw_tables.sql`
3. Generate overlap data from Northwind:
   - `sql/00_setup/004_generate_csvraw_from_northwind.sql`
4. Generate realistic net-new records:
   - `sql/00_setup/005_generate_csvraw_netnew.sql`
5. Validate CsvRaw load:
   - `sql/00_setup/006_validate_csvraw_load.sql`

## 2) Build MigrationLab schema and tables
Run in order:
- `sql/01_migrationlab/010_create_schemas.sql`
- `sql/01_migrationlab/020_create_snapshot_tables.sql`
- `sql/01_migrationlab/030_create_ref_tables.sql`
- `sql/01_migrationlab/040_create_work_tables.sql`
- `sql/01_migrationlab/050_create_target_model_tables.sql`
- `sql/01_migrationlab/060_create_target_tables.sql`
- `sql/01_migrationlab/070_create_reporting_views.sql`

## 3) Execute ETL
Run in order:
- `sql/02_etl_procs/100_etl_refresh_snapshots.sql`
- `sql/02_etl_procs/110_etl_build_work_otc.sql`
- `sql/02_etl_procs/120_etl_build_work_ptp.sql`
- `sql/02_etl_procs/130_etl_build_target_model.sql`
- `sql/02_etl_procs/140_etl_load_target.sql`
- `sql/02_etl_procs/150_etl_snapshot_target.sql`

## 4) Validate & export
- Use `reporting.*` views for reconciliation and screenshots
- Export query results from SSMS as CSV to `sample_output/`
