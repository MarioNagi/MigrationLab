# sample_output/

Representative CSV exports of the `reporting.*` views from a clean run of
the lab against the standard Northwind dataset. These are committed so a
reviewer can see the shape of the output without running the pipeline.

The numbers are illustrative — they reflect a single canonical run and
will differ slightly if the CSV-generation seed in
`sql/00_setup/004_generate_csvraw_from_northwind.sql` is changed.

| File | View | What it shows |
|------|------|---------------|
| `01_source_record_counts.csv` | `reporting.SourceRecordCounts` | Row counts per source system / entity. |
| `02_migration_completeness.csv` | `reporting.MigrationCompleteness` | Source → target completion percentage per source/entity. |
| `03_migration_reconciliation.csv` | `reporting.MigrationReconciliation` | The 100% invariant: `Source = Loaded + MergedAway + OtherRejected`. `ReconciliationDelta` must be 0. |
| `04_reject_summary.csv` | `reporting.RejectSummary` | Rejected source records grouped by reason code. |
| `05_deduplication_summary.csv` | `reporting.DeduplicationSummary` | Match groups, duplicates resolved, survivors. |
| `06_data_quality_summary.csv` | `reporting.DataQualitySummary` | Field-level completeness at canonical and target_model stages. |
| `07_etl_run_summary.csv` | `reporting.EtlRunSummary` | Per-batch run timing and step status from `etl.RunLog`. |

## Regenerating

After running the pipeline, export each view via `sqlcmd` or SSMS. A simple
export script is included as `_export_sample_output.sql` (run from
SSMS → Results to File). Replace these CSVs and commit.
