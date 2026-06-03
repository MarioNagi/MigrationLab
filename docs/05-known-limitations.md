# Known Limitations (by design)

This is a learning lab, not a production migration platform. The gaps below are intentional and documented so the difference between "portfolio lab" and "production system" is explicit.

## Entity Resolution

- **No transitive closure of match groups.**
  Each `(MatchKeyType, MatchKeyValue)` produces an independent match group. If record A and B match on Email, and B and C match on Phone, the lab does not merge all three into one connected component.
  *Production fix:* add a union-find / graph connected-components pass over the match graph before survivorship.

- **Name splitting is intentionally simple.**
  The work layer uses deterministic SQL string logic for `ContactName` parsing. It will not correctly handle every culture-specific name pattern or compound surname.
  *Production fix:* use a vetted parser, reference rules, or explicit manual review for ambiguous names.

## Survivorship

- **Hybrid survivorship, not full rule-engine survivorship.**
  The work layer picks a record-level survivor per match group. The target-model procedure then applies per-attribute source priority from `reference.SurvivorshipRules` for core fields such as Email, Phone, Name, Street, City, PostalCode, and Country.
  *Production fix:* add rule effective dates, rule-set approvals, source freshness scoring, and attribute-level lineage columns.

- **No manual review queue for ambiguous matches.**
  All match groups are resolved deterministically.
  *Production fix:* send low-confidence or conflicting groups to a review workflow before target load.

## Operations

- **Full-refresh ETL only.**
  The stored procedures rebuild the snapshots, work layer, target model, and target load each run. This makes the lab easy to rerun and test, but it is not incremental.
  *Production fix:* add CDC or watermark-based delta processing and idempotent retry windows.

- **No partitioning or batching.**
  The lab is designed for public sample data, not billion-row ERP tables.
  *Production fix:* partition snapshots and work tables by entity/date/range, then orchestrate batches independently.

- **No production security controls.**
  The data is synthetic, so there is no PII masking, encryption-at-rest design, row-level security, or retention policy.
  *Production fix:* add data classification, masking, audit retention, and least-privilege access.

## Platform Scope

- **No external orchestration service.**
  The production-shaped path uses SQL stored procedures and `run.ps1`, not SSIS, ADF, Airflow, or Fabric pipelines.
  *Production fix:* wrap the stored procedures in an orchestrator with alerts, retries, and deployment promotion.

- **No semantic model or dashboard.**
  Reporting is SQL-view based and screenshot-friendly.
  *Production fix:* publish a Power BI/Fabric semantic model over reconciliation, reject, and quality views.
