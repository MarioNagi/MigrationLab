USE MigrationLab;
GO

/*
File
----
sample_output/_export_sample_output.sql

Purpose
-------
Run this in SSMS with "Results To File" enabled (Query → Results To → File)
to refresh the CSV samples committed under sample_output/.

Each SELECT writes one CSV-shaped output. SSMS prompts for a destination
per result set — name them to match the existing files:

  01_source_record_counts.csv
  02_migration_completeness.csv
  03_migration_reconciliation.csv
  04_reject_summary.csv
  05_deduplication_summary.csv
  06_data_quality_summary.csv
  07_etl_run_summary.csv

Tip: in SSMS, Tools → Options → Query Results → SQL Server → Results to
Text → Output format = "Comma delimited", and check
"Include column headers in the result set".
*/

SELECT * FROM reporting.SourceRecordCounts      ORDER BY EntityType, SourceSystem;
SELECT * FROM reporting.MigrationCompleteness   ORDER BY EntityType, SourceSystem;
SELECT * FROM reporting.MigrationReconciliation ORDER BY EntityType, SourceSystem;
SELECT * FROM reporting.RejectSummary           ORDER BY EntityType, SourceSystem, ReasonCode;
SELECT * FROM reporting.DeduplicationSummary    ORDER BY EntityType;
SELECT * FROM reporting.DataQualitySummary      ORDER BY EntityType, Stage;
SELECT * FROM reporting.EtlRunSummary           ORDER BY BatchStart DESC;
GO
