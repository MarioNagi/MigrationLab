# Known Limitations (by design)

This is a **learning lab**, not a production migration platform. The gaps below are intentional — listed here so reviewers and recruiters can see what would change at production scale.

## Entity resolution

- **No transitive closure of match groups.**
  Each `(MatchKeyType, MatchKeyValue)` produces an independent match group. If record A and B match on Email, and B and C match on Phone, the lab keeps two separate groups instead of merging them into one cluster of {A, B, C}.
  *Production fix:* union-find / connected-components pass over the match graph before survivorship.

- **Name splitting in the work layer is simple.**
  The work layer splits `ContactName` using `CHARINDEX`-based first/last/middle logic. It will not correctly handle compound surnames (`de la Cruz`, `van der Berg`) or culture-specific name orders.
  *Production fix:* a name-parsing reference table or a vetted parser library.

## Survivorship

- **Record-level survivorship only.**
  The lab picks one whole "best" record per match group, ranked by data completeness flags (`HasEmail` > `HasPhone` > `HasAddress` > `HasFullName`). It does **not** apply per-attribute survivorship (e.g. "prefer Email from CRM, prefer Phone from ERP").
  *Production fix:* a rules table (attribute, source priority, tie-breaker) consumed by the target-model build step.

- **No survivorship-rule versioning.**
  Rules are hard-coded in the procs. A production system would version rules and pin in-flight migrations to a specific rule set.

## Reconciliation

- **Reconciliation is presentational.**
  `reporting.MigrationCompleteness` shows source vs. target counts, but the lab does not produce a per-record reject log with reason codes. Every source record either lands in the target or is silently merged into a survivor.
  *Production fix:* explicit reject queue with reason codes (`DUPLICATE_OF`, `MISSING_REQUIRED_FIELD`, `INVALID_COUNTRY`, etc.).

## Operations

- **Full-refresh ETL only.** Each run truncates and rebuilds. No incremental delta detection, no idempotent re-runs after a partial failure.
- **No partitioning or batching.** Designed for the small Northwind dataset; would not scale to billion-row tables without partitioned snapshots and chunked loads.
- **No automated test suite.** Validation script `006_validate_csvraw_load.sql` is the closest thing.
- **No PII masking, encryption at rest, or row-level security.** All data is synthetic, so it isn't needed here — but a real ERP migration would.
