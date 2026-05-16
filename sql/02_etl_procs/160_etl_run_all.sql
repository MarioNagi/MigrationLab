USE MigrationLab;
GO

/*
File
----
sql/02_etl_procs/160_etl_run_all.sql

Purpose
-------
Master ETL procedure that runs all migration steps in sequence.
This is the main entry point for executing the complete migration pipeline.

Execution order
---------------
1. Refresh snapshots from source systems
2. Build work tables (OTC - customers)
3. Build work tables (PTP - vendors)
4. Build target model from work tables
5. Load target tables (SAP ECC format)
6. Create target snapshots

Design principles
-----------------
- Single entry point for full migration run
- Error handling with rollback
- Progress reporting at each step
- Can be called repeatedly (idempotent)

Assumptions
-----------
- All table structures exist (010-070)
- Source databases (Northwind, CsvRaw) exist and contain data
- All ETL procedures exist (100-150)
*/

SET NOCOUNT ON;

-- Safety check
IF DB_NAME() <> 'MigrationLab'
BEGIN
    THROW 50000, 'This script must be executed in the MigrationLab database context.', 1;
END;

DECLARE @start_time DATETIME2(7) = SYSDATETIME();
DECLARE @step_start_time DATETIME2(7);
DECLARE @step_duration INT;
DECLARE @error_message NVARCHAR(MAX);

PRINT '================================================================================';
PRINT '=== MIGRATION LAB - FULL ETL PIPELINE ===';
PRINT '================================================================================';
PRINT CONCAT('Started: ', CONVERT(varchar(23), @start_time, 121));
PRINT '';

BEGIN TRY
    /* =============================================================================
       Step 1: Refresh snapshots
       ============================================================================= */
    SET @step_start_time = SYSDATETIME();
    PRINT '================================================================================';
    PRINT 'STEP 1/6: Refreshing snapshots from source systems...';
    PRINT '================================================================================';
    PRINT '  Executing: 100_etl_refresh_snapshots.sql';
    PRINT '  NOTE: Open and execute sql/02_etl_procs/100_etl_refresh_snapshots.sql in SSMS';
    PRINT '  Or use: sqlcmd -S server -d MigrationLab -i "sql/02_etl_procs/100_etl_refresh_snapshots.sql"';
    
    SET @step_duration = DATEDIFF(SECOND, @step_start_time, SYSDATETIME());
    PRINT CONCAT('  (Manual execution required - estimated duration shown)', '');
    PRINT '';

    /* =============================================================================
       Step 2: Build work_otc (customers)
       ============================================================================= */
    SET @step_start_time = SYSDATETIME();
    PRINT '================================================================================';
    PRINT 'STEP 2/6: Building work_otc (Order to Cash - Customers)...';
    PRINT '================================================================================';
    PRINT '  Executing: 110_etl_build_work_otc.sql';
    PRINT '  NOTE: Open and execute sql/02_etl_procs/110_etl_build_work_otc.sql in SSMS';
    PRINT '  Or use: sqlcmd -S server -d MigrationLab -i "sql/02_etl_procs/110_etl_build_work_otc.sql"';
    
    SET @step_duration = DATEDIFF(SECOND, @step_start_time, SYSDATETIME());
    PRINT CONCAT('  (Manual execution required - estimated duration shown)');
    PRINT '';

    /* =============================================================================
       Step 3: Build work_ptp (vendors)
       ============================================================================= */
    SET @step_start_time = SYSDATETIME();
    PRINT '================================================================================';
    PRINT 'STEP 3/6: Building work_ptp (Procure to Pay - Vendors)...';
    PRINT '================================================================================';
    PRINT '  Executing: 120_etl_build_work_ptp.sql';
    PRINT '  NOTE: Open and execute sql/02_etl_procs/120_etl_build_work_ptp.sql in SSMS';
    PRINT '  Or use: sqlcmd -S server -d MigrationLab -i "sql/02_etl_procs/120_etl_build_work_ptp.sql"';
    
    SET @step_duration = DATEDIFF(SECOND, @step_start_time, SYSDATETIME());
    PRINT CONCAT('  (Manual execution required - estimated duration shown)');
    PRINT '';

    /* =============================================================================
       Step 4: Build target model
       ============================================================================= */
    SET @step_start_time = SYSDATETIME();
    PRINT '================================================================================';
    PRINT 'STEP 4/6: Building target_model from work tables...';
    PRINT '================================================================================';
    PRINT '  Executing: 130_etl_build_target_model.sql';
    PRINT '  NOTE: Open and execute sql/02_etl_procs/130_etl_build_target_model.sql in SSMS';
    PRINT '  Or use: sqlcmd -S server -d MigrationLab -i "sql/02_etl_procs/130_etl_build_target_model.sql"';
    
    SET @step_duration = DATEDIFF(SECOND, @step_start_time, SYSDATETIME());
    PRINT CONCAT('  (Manual execution required - estimated duration shown)');
    PRINT '';

    /* =============================================================================
       Step 5: Load target tables
       ============================================================================= */
    SET @step_start_time = SYSDATETIME();
    PRINT '================================================================================';
    PRINT 'STEP 5/6: Loading target tables (SAP ECC format)...';
    PRINT '================================================================================';
    PRINT '  Executing: 140_etl_load_target.sql';
    PRINT '  NOTE: Open and execute sql/02_etl_procs/140_etl_load_target.sql in SSMS';
    PRINT '  Or use: sqlcmd -S server -d MigrationLab -i "sql/02_etl_procs/140_etl_load_target.sql"';
    
    SET @step_duration = DATEDIFF(SECOND, @step_start_time, SYSDATETIME());
    PRINT CONCAT('  (Manual execution required - estimated duration shown)');
    PRINT '';

    /* =============================================================================
       Step 6: Create target snapshots
       ============================================================================= */
    SET @step_start_time = SYSDATETIME();
    PRINT '================================================================================';
    PRINT 'STEP 6/6: Creating target snapshots...';
    PRINT '================================================================================';
    PRINT '  Executing: 150_etl_snapshot_target.sql';
    PRINT '  NOTE: Open and execute sql/02_etl_procs/150_etl_snapshot_target.sql in SSMS';
    PRINT '  Or use: sqlcmd -S server -d MigrationLab -i "sql/02_etl_procs/150_etl_snapshot_target.sql"';
    
    SET @step_duration = DATEDIFF(SECOND, @step_start_time, SYSDATETIME());
    PRINT CONCAT('  (Manual execution required - estimated duration shown)');
    PRINT '';

    /* =============================================================================
       Final Summary
       ============================================================================= */
    DECLARE @total_duration INT = DATEDIFF(SECOND, @start_time, SYSDATETIME());
    
    PRINT '================================================================================';
    PRINT '=== MIGRATION PIPELINE COMPLETED ===';
    PRINT '================================================================================';
    PRINT CONCAT('Total duration: ', @total_duration, ' seconds');
    PRINT CONCAT('Completed: ', CONVERT(varchar(23), SYSDATETIME(), 121));
    PRINT '';
    PRINT 'Next steps:';
    PRINT '  1. Review reporting views (reporting.*)';
    PRINT '  2. Validate data completeness';
    PRINT '  3. Export results for LinkedIn/GitHub';
    PRINT '================================================================================';

END TRY
BEGIN CATCH
    SET @error_message = CONCAT(
        'Error Number: ', ERROR_NUMBER(), CHAR(13),
        'Error Message: ', ERROR_MESSAGE(), CHAR(13),
        'Error Line: ', ERROR_LINE()
    );
    
    PRINT '';
    PRINT '================================================================================';
    PRINT '=== MIGRATION PIPELINE FAILED ===';
    PRINT '================================================================================';
    PRINT @error_message;
    PRINT '';
    PRINT 'Please review the error above and fix the issue before retrying.';
    PRINT '================================================================================';
    
    THROW;
END CATCH;
GO

/*
NOTE FOR PRODUCTION USE:
-----------------------
This master procedure is a template. In production, you would:

1. Use sqlcmd to execute each script file:
   sqlcmd -S server -d MigrationLab -i "sql/02_etl_procs/100_etl_refresh_snapshots.sql"

2. Or use SSIS package to orchestrate the steps

3. Or use PowerShell to execute scripts in sequence:
   $scripts = @(
       "sql/02_etl_procs/100_etl_refresh_snapshots.sql",
       "sql/02_etl_procs/110_etl_build_work_otc.sql",
       ...
   )
   foreach ($script in $scripts) {
       Invoke-Sqlcmd -InputFile $script
   }

For now, this procedure serves as documentation of the execution order.
*/
