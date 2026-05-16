# Architecture Decision Records

Short ADRs for the load-bearing decisions in this lab. Each one explains
*why* a particular path was chosen and what alternatives were rejected, so
that a reader (or future me) can tell intentional design from accidental
shape.

---

## ADR-001 — SQL-first, set-based pipeline (no Python/orchestrator)

**Status:** Accepted

**Context.** The pipeline manipulates two source datasets that already live
in SQL Server. The transformations are joins, ranks, group-bys, and
unpivots — all natively set-based.

**Decision.** Implement the entire pipeline in T-SQL: stored procedures,
views, and reference tables. No Python, no Airflow, no dbt.

**Why.**
- Business analysts and data stewards can read every transformation in the
  same dialect they already use to validate the result.
- Set-based logic on the database engine is materially faster than
  row-by-row processing in an external runtime, and removes a network hop
  for every batch.
- Any SQL Server shop can run this lab end-to-end without provisioning a
  vendor account, a Python environment, or an orchestrator.

**Consequences / trade-offs.**
- T-SQL is a poor language for unit testing; we compensate with the
  `tests/` assertion scripts and `etl.RunLog` rather than xUnit-style tests.
- Cross-database orchestration of arbitrary external systems would be
  awkward; if the next iteration needs to call REST APIs or read Parquet
  on object storage, an external orchestrator becomes the right choice.

---

## ADR-002 — Split the work layer by business process (OTC vs PTP)

**Status:** Accepted

**Context.** Customers and Vendors share most of the same transformation
shape (canonical → match → survivorship → crosswalk). A single shared
`work` schema would have been smaller.

**Decision.** Two separate schemas: `work_otc` for Customers
(Order-to-Cash) and `work_ptp` for Vendors (Procure-to-Pay). Each carries
its own canonical, match-group, survivorship, and crosswalk tables.

**Why.**
- This is how SAP-shaped enterprises organise their master-data teams.
  OTC and PTP have different stewards, different rules, and different
  release cycles. A shared schema hides that.
- Per-attribute survivorship rules diverge (`CompanyName` vs `VendorName`,
  CRM-owns-customer-email vs procurement-owns-vendor-email) — keeping the
  pipelines parallel makes the divergence visible in the schema rather
  than buried inside a CASE statement.

**Consequences / trade-offs.**
- Two near-identical procedures (`usp_BuildWorkOTC`, `usp_BuildWorkPTP`).
  The duplication is intentional: it keeps the OTC and PTP pipelines
  independently evolvable.

---

## ADR-003 — Full-refresh ETL, not incremental

**Status:** Accepted (with known limitation)

**Context.** A production migration eventually needs incremental loads,
idempotent re-runs, and delta detection.

**Decision.** Every run truncates and rebuilds the work, target_model, and
target_sap_ecc layers from the snapshot tables. No watermarks, no change
data capture, no upserts.

**Why.**
- Migrations to a new target system are usually a one-shot cutover or a
  small number of mock loads — not a continuously-running pipeline. The
  full-refresh model matches the actual operational reality of a cutover
  weekend.
- Full-refresh makes survivorship and reconciliation trivially
  deterministic: the same input always produces the same output, so
  diffs between runs are purely a function of source-data changes.
- It removes a whole class of bugs (partial state, half-applied changes,
  stale crosswalk rows) that are expensive to test for.

**Consequences / trade-offs.**
- Will not scale to billion-row tables without partitioning and chunked
  loads. Documented in `docs/05-known-limitations.md`.
- Idempotent incremental runs are listed as a deliberate non-goal.

---

## ADR-004 — Hybrid survivorship: record-level grouping + per-attribute selection

**Status:** Accepted

**Context.** Two common survivorship strategies:
1. **Record-level:** pick one whole "best" record per match group (simple,
   but loses good data on the losers).
2. **Per-attribute:** pick the best value for each attribute independently
   (high quality, but harder to explain and audit).

**Decision.** Use both. The work layer ranks records inside a match group
and stores a survivor (`SurvivorshipReason`) — that gives every group a
canonical anchor. The target_model layer then *re-selects each attribute*
across the group using `reference.SurvivorshipRules` (per-attribute,
per-source priority, versioned).

**Why.**
- The record-level survivor is a stable identity for crosswalk and
  reporting (every match group has exactly one survivor row).
- Per-attribute selection means the final target row gets the
  finance-validated phone from the ERP and the sales-maintained email from
  the CRM — even when those values came from different physical records.
- `reference.SurvivorshipRules` is versioned (`RuleVersion`, `IsActive`),
  so an in-flight cutover can be pinned to a known rule set without
  blocking new development.

**Consequences / trade-offs.**
- Two passes of survivorship logic to understand. The rationale column on
  every rule (`reference.SurvivorshipRules.Rationale`) is the
  documentation budget for that complexity.
- A reject row (`ReasonCode = 'MISSING_REQUIRED_FIELD'`) is written when
  the per-attribute pass produces a NULL on a required field — surfacing
  rule gaps explicitly instead of silently dropping records.

---

## ADR-005 — Sources are never joined directly; the work layer is the only meeting point

**Status:** Accepted

**Context.** It would be technically possible to write a single SELECT
that joins `source_northwind.Customers` directly to
`source_csv.CustomersExport` on email or phone.

**Decision.** Sources are read only into snapshot tables
(`source_northwind.*`, `source_csv.*`). All matching, deduplication, and
survivorship happens inside `work_otc` / `work_ptp`. The two sources never
appear together in a JOIN outside the work layer.

**Why.**
- Snapshots are point-in-time and reproducible; live source joins are
  not. A migration that "passed" against a moving source is meaningless.
- Every match group, every survivor decision, and every reject reason is
  recorded against canonical IDs in the work layer — making the pipeline
  auditable. Cross-source joins would scatter that lineage.
- Adding a third source (a second CRM, a regional ERP) becomes a matter
  of writing a new canonical loader. The matching, survivorship, and
  target-build logic does not change.

**Consequences / trade-offs.**
- More tables, more storage, more steps. The cost is paid once per run;
  the auditability is paid forward on every reconciliation.

---

## How to add a new ADR

1. Create the next `ADR-NNN` heading in this file.
2. Include **Status** (Proposed / Accepted / Superseded by ADR-MMM),
   **Context**, **Decision**, **Why**, and **Consequences**.
3. Keep it short — an ADR that takes longer to read than the code change
   it describes is too long.
