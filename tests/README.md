# tests/

T-SQL assertion scripts. Each script raises with `THROW` on failure so
that `sqlcmd -b` exits non-zero — that's how the runner (`run.ps1`) and
CI (`.github/workflows/ci.yml`) detect a regression.

## Files

| File | Asserts |
|------|---------|
| `010_test_reconciliation_invariant.sql` | `reporting.MigrationReconciliation.ReconciliationDelta = 0` for every (EntityType, SourceSystem). |
| `020_test_no_orphan_crosswalk.sql` | Every `work_otc.CustomersCrosswalk` / `work_ptp.VendorsCrosswalk` row points at an existing canonical record. |
| `030_test_no_duplicate_target_ids.sql` | `target_sap_ecc.CustomerMaster.CustomerNumber` and `VendorMaster.VendorNumber` are unique. |
| `040_test_survivor_in_target.sql` | Every match-group survivor lands in `target_model` (i.e. survivorship is wired through to the target build). |
| `050_test_required_fields.sql` | `target_model.Customers.CompanyName` and `target_model.Vendors.VendorName` are NEVER NULL (and rejects exist for the corresponding source rows). |
| `060_test_runlog_clean_run.sql` | The latest batch in `etl.RunLog` has zero `FAILED` rows and `StepsStarted = StepsCompleted`. |
| `run_all_tests.sql` | Runs every test in order. |

## Running

```powershell
./run.ps1 -ServerInstance localhost            # runs tests by default
./run.ps1 -ServerInstance localhost -SkipTests # opt out
```

Or directly:

```bash
sqlcmd -S localhost -E -d MigrationLab -i tests/run_all_tests.sql -b
```

## Adding a test

1. Create `tests/NNN_test_<what>.sql`.
2. Inside, write a SELECT that returns the count of *failing* rows.
3. If that count is non-zero, `THROW` with a descriptive message.
4. Add `:r tests/NNN_test_<what>.sql` to `run_all_tests.sql`.

Pattern:

```sql
DECLARE @failures INT = (SELECT COUNT(*) FROM ... WHERE <broken condition>);
IF @failures > 0
    THROW 60001, 'reconciliation invariant violated; see reporting.MigrationReconciliation', 1;
PRINT 'PASS: <what>';
```
