USE MigrationLab;
GO

SET NOCOUNT ON;

/*
Test
----
The most recent batch in etl.RunLog must have:
  - zero FAILED steps
  - StepsStarted = StepsCompleted (no half-finished steps)

If etl.RunLog is empty, the test is skipped (the script-style runner does
not write to RunLog). The stored-proc orchestrator (etl.usp_RunAll) does.
*/

IF NOT EXISTS (SELECT 1 FROM etl.RunLog)
BEGIN
    PRINT 'SKIP: 060_test_runlog_clean_run (etl.RunLog is empty — script-style run?)';
    RETURN;
END;

DECLARE @latest_batch VARCHAR(50) = (
    SELECT TOP 1 BatchID
    FROM etl.RunLog
    ORDER BY StartTime DESC
);

DECLARE @started INT, @completed INT, @failed INT;

SELECT
    @started   = SUM(CASE WHEN Status = 'STARTED'   THEN 1 ELSE 0 END),
    @completed = SUM(CASE WHEN Status = 'COMPLETED' THEN 1 ELSE 0 END),
    @failed    = SUM(CASE WHEN Status = 'FAILED'    THEN 1 ELSE 0 END)
FROM etl.RunLog
WHERE BatchID = @latest_batch;

PRINT CONCAT('Latest batch: ', @latest_batch);
PRINT CONCAT('  STARTED  : ', @started);
PRINT CONCAT('  COMPLETED: ', @completed);
PRINT CONCAT('  FAILED   : ', @failed);

IF @failed > 0
    THROW 60060, 'FAIL: latest batch has FAILED steps.', 1;

IF @started <> @completed
    THROW 60061, 'FAIL: latest batch has half-finished steps (STARTED <> COMPLETED).', 1;

PRINT 'PASS: 060_test_runlog_clean_run';
GO
