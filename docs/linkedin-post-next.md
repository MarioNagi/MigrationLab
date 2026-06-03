# LinkedIn Post - MigrationLab End-to-End Verification

## Post

I did not want this data migration lab to be another "here is a nice architecture diagram" project.

So I spent time hardening it until it could prove its own result.

The project simulates an ERP-style migration:

- Northwind as the ERP-like source
- A generated CRM/CSV export with overlap, messy formatting, and net-new records
- A SQL Server migration platform with snapshots, work tables, match keys, survivorship, target shaping, reject logging, and reconciliation views

The part I focused on most was not moving rows.

It was this question:

**Can every source record be accounted for?**

After the latest run, the answer is yes:

```text
Customers / Northwind: 91 source records  = 42 loaded + 49 merged away + 0 rejected
Customers / CsvRaw:    185 source records = 73 loaded + 112 merged away + 0 rejected
Vendors / Northwind:   29 source records  = 5 loaded + 24 merged away + 0 rejected
Vendors / CsvRaw:      109 source records = 71 loaded + 38 merged away + 0 rejected
```

Every row reconciles to 100%.

I also added a production-shaped execution path:

- Stored procedures with a shared `BatchID`
- `etl.RunLog` for step-level observability
- `etl.RejectLog` for duplicate/reject reason codes
- Per-attribute survivorship rules in `reference.SurvivorshipRules`
- Target-field shaping before loading the SAP-style target tables
- SQL assertion tests that fail the run if reconciliation breaks

The latest run completed:

```text
Batch: BATCH-20260603125441
Steps completed: 33
Failed steps: 0
Rows affected: 8109
Tests passed: 6/6
```

The most useful lesson from this project:

**A migration is not successful because the target table has rows.**

It is successful when the team can explain:

- what loaded
- what merged
- what was rejected
- why it happened
- and how to rerun it without guessing

That is the difference between ETL and migration engineering.

I kept the repo honest with a `DECISIONS.md` file and a known-limitations document. There are still deliberate gaps: no transitive match closure, no incremental CDC, no partitioning, and no external orchestration service.

But the core migration discipline is there:

snapshot -> normalize -> match -> survive -> load -> reconcile -> test.

Next step: I am applying the same thinking to a Microsoft Fabric modernization scenario: SQL Server + SSIS on-prem moving toward Lakehouse/Warehouse pipelines and a gold semantic layer.

## Suggested first comment

```text
Repo: <github-url>
Run command: ./run.ps1 -ServerInstance localhost
Key views: reporting.MigrationReconciliation, reporting.EtlRunSummary, reporting.RejectSummary
```

## Suggested screenshots

- `reporting.MigrationReconciliation` showing `ReconciliationDelta = 0`
- `reporting.EtlRunSummary` showing `StepsCompleted = 33`, `StepsFailed = 0`
- test output showing all six PASS lines
- a short SQL snippet from `reference.SurvivorshipRules`

