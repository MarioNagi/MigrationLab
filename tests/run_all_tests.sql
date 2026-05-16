USE MigrationLab;
GO

SET NOCOUNT ON;

PRINT '==============================================';
PRINT '  MigrationLab test suite';
PRINT '==============================================';
PRINT '';

:r 010_test_reconciliation_invariant.sql
:r 020_test_no_orphan_crosswalk.sql
:r 030_test_no_duplicate_target_ids.sql
:r 040_test_survivor_in_target.sql
:r 050_test_required_fields.sql
:r 060_test_runlog_clean_run.sql

PRINT '';
PRINT '==============================================';
PRINT '  All tests passed.';
PRINT '==============================================';
GO
