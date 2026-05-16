USE MigrationLab;
GO

SET NOCOUNT ON;

/*
Test
----
The reconciliation invariant must hold for every (EntityType, SourceSystem):

    SourceRecords = LoadedRecords + MergedAwayRecords + OtherRejectedRecords

reporting.MigrationReconciliation.ReconciliationDelta is that residual.
Anything non-zero means a source record was silently lost.
*/

DECLARE @failures INT = (
    SELECT COUNT(*)
    FROM reporting.MigrationReconciliation
    WHERE ReconciliationDelta <> 0
);

IF @failures > 0
BEGIN
    SELECT *
    FROM reporting.MigrationReconciliation
    WHERE ReconciliationDelta <> 0;

    THROW 60010, 'FAIL: reconciliation invariant violated. See reporting.MigrationReconciliation.', 1;
END;

PRINT 'PASS: 010_test_reconciliation_invariant';
GO
