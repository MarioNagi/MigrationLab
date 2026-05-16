# Methodology

This project simulates an enterprise ERP-style migration using a **repeatable SQL-first approach**.

## Why this approach

In real migrations, most risk is not “moving rows”. It is:
- Understanding business meaning
- Resolving duplicates and conflicting attributes across sources
- Proving completeness and accuracy
- Keeping the process auditable and rerunnable

This lab is designed to show those concerns with a safe public dataset.

## End-to-end flow

1. **Sources**
   - `Northwind` (ERP-like, read-only)
   - `CsvRaw` (CRM / exports; overlap + net-new + messy formatting)

2. **Migration platform (MigrationLab)**
   - **Snapshots** (`source_*`): point-in-time copies of each source
   - **Working layer** (`work_*`): normalization + match keys + grouping + survivorship
   - **Target model** (`target_model`): canonical “to-be” entities
   - **Target load** (`target_*`): target-shaped tables
   - **Reporting** (`reporting.*`): reconciliation and rule visibility

3. **Rules and auditability**
   - Match keys are explicit (email / phone / normalized name + location)
   - Dedupe is explainable (match groups)
   - Survivorship is deterministic (priority rules)
   - Reporting provides “show your work” evidence

## Key design choice: reversible transformation

We intentionally show bidirectional logic:
- In `CsvRaw` generation: split `ContactName` into First/Middle/Last and generate email
- In the working layer: also rebuild `ContactName` from First/Middle/Last for CSV records

This demonstrates real-world transformation thinking, not just copy-paste ETL.
