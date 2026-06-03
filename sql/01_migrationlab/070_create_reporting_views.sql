USE MigrationLab;
GO

/*
File
----
sql/01_migrationlab/070_create_rpt_views.sql

Purpose
-------
Create reporting views for migration visibility and validation.
These views support completeness checks, duplicate resolution tracking, and data quality reporting.

Design principles
-----------------
- Read-only views (no data modification)
- Easy to screenshot for LinkedIn/GitHub
- Clear metrics and summaries
- Supports reconciliation to 100%

Reporting views
--------------
- reporting.SourceRecordCounts: Row counts by source system
- reporting.DeduplicationSummary: Match groups and survivorship stats
- reporting.DataQualitySummary: Data completeness by field
- reporting.MigrationCompleteness: Source-to-target reconciliation
- reporting.DuplicateResolution: Details of resolved duplicates

Assumptions
-----------
- Schema 'reporting' already exists (created by 010_create_schemas.sql)
- All source, work, and target tables exist
*/

SET NOCOUNT ON;

-- Safety check
IF DB_NAME() <> 'MigrationLab'
BEGIN
    THROW 50000, 'This script must be executed in the MigrationLab database context.', 1;
END;

-- Verify schema exists
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'reporting')
    THROW 50001, 'Missing schema reporting. Run 010_create_schemas.sql first.', 1;

PRINT 'Creating reporting views...';
GO

/* =============================================================================
   reporting.SourceRecordCounts: Row counts by source system and table
   ============================================================================= */

IF OBJECT_ID('reporting.SourceRecordCounts','V') IS NOT NULL DROP VIEW reporting.SourceRecordCounts;
GO

CREATE VIEW reporting.SourceRecordCounts
AS
SELECT 
    'Customers' AS EntityType,
    'Northwind' AS SourceSystem,
    COUNT(*) AS RecordCount,
    MIN(snapshot_timestamp) AS SnapshotTime
FROM source_northwind.Customers
UNION ALL
SELECT 
    'Suppliers' AS EntityType,
    'Northwind' AS SourceSystem,
    COUNT(*) AS RecordCount,
    MIN(snapshot_timestamp) AS SnapshotTime
FROM source_northwind.Suppliers
UNION ALL
SELECT 
    'Customers' AS EntityType,
    'CsvRaw' AS SourceSystem,
    COUNT(*) AS RecordCount,
    MIN(snapshot_timestamp) AS SnapshotTime
FROM source_csv.CustomersExport
UNION ALL
SELECT 
    'Vendors' AS EntityType,
    'CsvRaw' AS SourceSystem,
    COUNT(*) AS RecordCount,
    MIN(snapshot_timestamp) AS SnapshotTime
FROM source_csv.VendorsExport;
GO

/* =============================================================================
   reporting.DeduplicationSummary: Match groups and survivorship statistics
   ============================================================================= */

IF OBJECT_ID('reporting.DeduplicationSummary','V') IS NOT NULL DROP VIEW reporting.DeduplicationSummary;
GO

CREATE VIEW reporting.DeduplicationSummary
AS
SELECT 
    'Customers' AS EntityType,
    COUNT(DISTINCT c.WorkCustomerID) AS TotalCanonicalRecords,
    COUNT(DISTINCT mg.MatchGroupID) AS TotalMatchGroups,
    SUM(CASE WHEN mg.GroupSize > 1 THEN 1 ELSE 0 END) AS DuplicateGroups,
    SUM(CASE WHEN mg.GroupSize = 1 THEN 1 ELSE 0 END) AS UniqueGroups,
    SUM(mg.GroupSize) AS TotalRecordsInGroups,
    COUNT(DISTINCT s.WorkCustomerID) AS SurvivedRecords,
    SUM(mg.GroupSize) - COUNT(DISTINCT s.WorkCustomerID) AS DuplicatesResolved
FROM work_otc.CustomersCanonical c
LEFT JOIN work_otc.CustomersMatchGroupMembers mgm ON c.WorkCustomerID = mgm.WorkCustomerID
LEFT JOIN work_otc.CustomersMatchGroups mg ON mgm.MatchGroupID = mg.MatchGroupID
LEFT JOIN work_otc.CustomersSurvivorship s ON mg.MatchGroupID = s.MatchGroupID
UNION ALL
SELECT 
    'Vendors' AS EntityType,
    COUNT(DISTINCT v.WorkVendorID) AS TotalCanonicalRecords,
    COUNT(DISTINCT mg.MatchGroupID) AS TotalMatchGroups,
    SUM(CASE WHEN mg.GroupSize > 1 THEN 1 ELSE 0 END) AS DuplicateGroups,
    SUM(CASE WHEN mg.GroupSize = 1 THEN 1 ELSE 0 END) AS UniqueGroups,
    SUM(mg.GroupSize) AS TotalRecordsInGroups,
    COUNT(DISTINCT s.WorkVendorID) AS SurvivedRecords,
    SUM(mg.GroupSize) - COUNT(DISTINCT s.WorkVendorID) AS DuplicatesResolved
FROM work_ptp.VendorsCanonical v
LEFT JOIN work_ptp.VendorsMatchGroupMembers mgm ON v.WorkVendorID = mgm.WorkVendorID
LEFT JOIN work_ptp.VendorsMatchGroups mg ON mgm.MatchGroupID = mg.MatchGroupID
LEFT JOIN work_ptp.VendorsSurvivorship s ON mg.MatchGroupID = s.MatchGroupID;
GO

/* =============================================================================
   reporting.DataQualitySummary: Data completeness by field
   ============================================================================= */

IF OBJECT_ID('reporting.DataQualitySummary','V') IS NOT NULL DROP VIEW reporting.DataQualitySummary;
GO

CREATE VIEW reporting.DataQualitySummary
AS
SELECT 
    'Customers' AS EntityType,
    'Canonical' AS Stage,
    COUNT(*) AS TotalRecords,
    SUM(CASE WHEN CompanyName IS NOT NULL THEN 1 ELSE 0 END) AS HasCompanyName,
    SUM(CASE WHEN ContactFirstName IS NOT NULL OR ContactLastName IS NOT NULL THEN 1 ELSE 0 END) AS HasContactName,
    SUM(CASE WHEN EmailNormalized IS NOT NULL THEN 1 ELSE 0 END) AS HasEmail,
    SUM(CASE WHEN PhoneNormalized IS NOT NULL THEN 1 ELSE 0 END) AS HasPhone,
    SUM(CASE WHEN Street IS NOT NULL AND City IS NOT NULL AND CountryCode IS NOT NULL THEN 1 ELSE 0 END) AS HasCompleteAddress,
    CAST(SUM(CASE WHEN CompanyName IS NOT NULL THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS DECIMAL(5,2)) AS CompanyNamePct,
    CAST(SUM(CASE WHEN EmailNormalized IS NOT NULL THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS DECIMAL(5,2)) AS EmailPct,
    CAST(SUM(CASE WHEN PhoneNormalized IS NOT NULL THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS DECIMAL(5,2)) AS PhonePct
FROM work_otc.CustomersCanonical
UNION ALL
SELECT 
    'Customers' AS EntityType,
    'Target Model' AS Stage,
    COUNT(*) AS TotalRecords,
    SUM(CASE WHEN CompanyName IS NOT NULL THEN 1 ELSE 0 END) AS HasCompanyName,
    SUM(CASE WHEN ContactFirstName IS NOT NULL OR ContactLastName IS NOT NULL THEN 1 ELSE 0 END) AS HasContactName,
    SUM(CASE WHEN EmailNormalized IS NOT NULL THEN 1 ELSE 0 END) AS HasEmail,
    SUM(CASE WHEN PhoneNormalized IS NOT NULL THEN 1 ELSE 0 END) AS HasPhone,
    SUM(CASE WHEN Street IS NOT NULL AND City IS NOT NULL AND CountryCode IS NOT NULL THEN 1 ELSE 0 END) AS HasCompleteAddress,
    CAST(SUM(CASE WHEN CompanyName IS NOT NULL THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS DECIMAL(5,2)) AS CompanyNamePct,
    CAST(SUM(CASE WHEN EmailNormalized IS NOT NULL THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS DECIMAL(5,2)) AS EmailPct,
    CAST(SUM(CASE WHEN PhoneNormalized IS NOT NULL THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS DECIMAL(5,2)) AS PhonePct
FROM target_model.Customers
UNION ALL
SELECT 
    'Vendors' AS EntityType,
    'Canonical' AS Stage,
    COUNT(*) AS TotalRecords,
    SUM(CASE WHEN VendorName IS NOT NULL THEN 1 ELSE 0 END) AS HasCompanyName,
    SUM(CASE WHEN ContactFirstName IS NOT NULL OR ContactLastName IS NOT NULL THEN 1 ELSE 0 END) AS HasContactName,
    SUM(CASE WHEN EmailNormalized IS NOT NULL THEN 1 ELSE 0 END) AS HasEmail,
    SUM(CASE WHEN PhoneNormalized IS NOT NULL THEN 1 ELSE 0 END) AS HasPhone,
    SUM(CASE WHEN Street IS NOT NULL AND City IS NOT NULL AND CountryCode IS NOT NULL THEN 1 ELSE 0 END) AS HasCompleteAddress,
    CAST(SUM(CASE WHEN VendorName IS NOT NULL THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS DECIMAL(5,2)) AS CompanyNamePct,
    CAST(SUM(CASE WHEN EmailNormalized IS NOT NULL THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS DECIMAL(5,2)) AS EmailPct,
    CAST(SUM(CASE WHEN PhoneNormalized IS NOT NULL THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS DECIMAL(5,2)) AS PhonePct
FROM work_ptp.VendorsCanonical
UNION ALL
SELECT 
    'Vendors' AS EntityType,
    'Target Model' AS Stage,
    COUNT(*) AS TotalRecords,
    SUM(CASE WHEN VendorName IS NOT NULL THEN 1 ELSE 0 END) AS HasCompanyName,
    SUM(CASE WHEN ContactFirstName IS NOT NULL OR ContactLastName IS NOT NULL THEN 1 ELSE 0 END) AS HasContactName,
    SUM(CASE WHEN EmailNormalized IS NOT NULL THEN 1 ELSE 0 END) AS HasEmail,
    SUM(CASE WHEN PhoneNormalized IS NOT NULL THEN 1 ELSE 0 END) AS HasPhone,
    SUM(CASE WHEN Street IS NOT NULL AND City IS NOT NULL AND CountryCode IS NOT NULL THEN 1 ELSE 0 END) AS HasCompleteAddress,
    CAST(SUM(CASE WHEN VendorName IS NOT NULL THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS DECIMAL(5,2)) AS CompanyNamePct,
    CAST(SUM(CASE WHEN EmailNormalized IS NOT NULL THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS DECIMAL(5,2)) AS EmailPct,
    CAST(SUM(CASE WHEN PhoneNormalized IS NOT NULL THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS DECIMAL(5,2)) AS PhonePct
FROM target_model.Vendors;
GO

/* =============================================================================
   reporting.MigrationCompleteness: Source-to-target reconciliation
   ============================================================================= */

IF OBJECT_ID('reporting.MigrationCompleteness','V') IS NOT NULL DROP VIEW reporting.MigrationCompleteness;
GO

CREATE VIEW reporting.MigrationCompleteness
AS
SELECT 
    'Customers' AS EntityType,
    'Northwind' AS SourceSystem,
    (SELECT COUNT(*) FROM source_northwind.Customers) AS SourceRecords,
    (SELECT COUNT(*) FROM work_otc.CustomersCanonical WHERE SourceSystem = 'Northwind') AS CanonicalRecords,
    (SELECT COUNT(*) FROM work_otc.CustomersCrosswalk WHERE SourceSystem = 'Northwind') AS CrosswalkRecords,
    (SELECT COUNT(*) FROM target_model.Customers WHERE SourceSystems LIKE '%Northwind%') AS TargetModelRecords,
    (SELECT COUNT(*) FROM target_sap_ecc.CustomerMaster WHERE MigrationSource LIKE '%Northwind%') AS TargetRecords,
    CASE 
        WHEN (SELECT COUNT(*) FROM source_northwind.Customers) > 0 
        THEN CAST((SELECT COUNT(*) FROM target_sap_ecc.CustomerMaster WHERE MigrationSource LIKE '%Northwind%') * 100.0 / 
                  (SELECT COUNT(*) FROM source_northwind.Customers) AS DECIMAL(5,2))
        ELSE 0 
    END AS CompletionPct
UNION ALL
SELECT 
    'Customers' AS EntityType,
    'CsvRaw' AS SourceSystem,
    (SELECT COUNT(*) FROM source_csv.CustomersExport) AS SourceRecords,
    (SELECT COUNT(*) FROM work_otc.CustomersCanonical WHERE SourceSystem = 'CsvRaw') AS CanonicalRecords,
    (SELECT COUNT(*) FROM work_otc.CustomersCrosswalk WHERE SourceSystem = 'CsvRaw') AS CrosswalkRecords,
    (SELECT COUNT(*) FROM target_model.Customers WHERE SourceSystems LIKE '%CsvRaw%') AS TargetModelRecords,
    (SELECT COUNT(*) FROM target_sap_ecc.CustomerMaster WHERE MigrationSource LIKE '%CsvRaw%') AS TargetRecords,
    CASE 
        WHEN (SELECT COUNT(*) FROM source_csv.CustomersExport) > 0 
        THEN CAST((SELECT COUNT(*) FROM target_sap_ecc.CustomerMaster WHERE MigrationSource LIKE '%CsvRaw%') * 100.0 / 
                  (SELECT COUNT(*) FROM source_csv.CustomersExport) AS DECIMAL(5,2))
        ELSE 0 
    END AS CompletionPct
UNION ALL
SELECT 
    'Vendors' AS EntityType,
    'Northwind' AS SourceSystem,
    (SELECT COUNT(*) FROM source_northwind.Suppliers) AS SourceRecords,
    (SELECT COUNT(*) FROM work_ptp.VendorsCanonical WHERE SourceSystem = 'Northwind') AS CanonicalRecords,
    (SELECT COUNT(*) FROM work_ptp.VendorsCrosswalk WHERE SourceSystem = 'Northwind') AS CrosswalkRecords,
    (SELECT COUNT(*) FROM target_model.Vendors WHERE SourceSystems LIKE '%Northwind%') AS TargetModelRecords,
    (SELECT COUNT(*) FROM target_sap_ecc.VendorMaster WHERE MigrationSource LIKE '%Northwind%') AS TargetRecords,
    CASE 
        WHEN (SELECT COUNT(*) FROM source_northwind.Suppliers) > 0 
        THEN CAST((SELECT COUNT(*) FROM target_sap_ecc.VendorMaster WHERE MigrationSource LIKE '%Northwind%') * 100.0 / 
                  (SELECT COUNT(*) FROM source_northwind.Suppliers) AS DECIMAL(5,2))
        ELSE 0 
    END AS CompletionPct
UNION ALL
SELECT 
    'Vendors' AS EntityType,
    'CsvRaw' AS SourceSystem,
    (SELECT COUNT(*) FROM source_csv.VendorsExport) AS SourceRecords,
    (SELECT COUNT(*) FROM work_ptp.VendorsCanonical WHERE SourceSystem = 'CsvRaw') AS CanonicalRecords,
    (SELECT COUNT(*) FROM work_ptp.VendorsCrosswalk WHERE SourceSystem = 'CsvRaw') AS CrosswalkRecords,
    (SELECT COUNT(*) FROM target_model.Vendors WHERE SourceSystems LIKE '%CsvRaw%') AS TargetModelRecords,
    (SELECT COUNT(*) FROM target_sap_ecc.VendorMaster WHERE MigrationSource LIKE '%CsvRaw%') AS TargetRecords,
    CASE 
        WHEN (SELECT COUNT(*) FROM source_csv.VendorsExport) > 0 
        THEN CAST((SELECT COUNT(*) FROM target_sap_ecc.VendorMaster WHERE MigrationSource LIKE '%CsvRaw%') * 100.0 / 
                  (SELECT COUNT(*) FROM source_csv.VendorsExport) AS DECIMAL(5,2))
        ELSE 0 
    END AS CompletionPct;
GO

/* =============================================================================
   reporting.DuplicateResolution: Details of resolved duplicates
   ============================================================================= */

IF OBJECT_ID('reporting.DuplicateResolution','V') IS NOT NULL DROP VIEW reporting.DuplicateResolution;
GO

CREATE VIEW reporting.DuplicateResolution
AS
SELECT 
    'Customers' AS EntityType,
    mg.MatchGroupID,
    mg.MatchKeyType,
    mg.MatchKeyValue,
    mg.GroupSize,
    s.WorkCustomerID AS SurvivedRecordID,
    s.SurvivorshipReason,
    STRING_AGG(CONCAT(c.SourceSystem, ':', c.SourceID), ', ') WITHIN GROUP (ORDER BY c.SourceSystem, c.SourceID) AS SourceRecords
FROM work_otc.CustomersMatchGroups mg
INNER JOIN work_otc.CustomersMatchGroupMembers mgm ON mg.MatchGroupID = mgm.MatchGroupID
INNER JOIN work_otc.CustomersCanonical c ON mgm.WorkCustomerID = c.WorkCustomerID
LEFT JOIN work_otc.CustomersSurvivorship s ON mg.MatchGroupID = s.MatchGroupID
WHERE mg.GroupSize > 1  -- Only show actual duplicates
GROUP BY mg.MatchGroupID, mg.MatchKeyType, mg.MatchKeyValue, mg.GroupSize, s.WorkCustomerID, s.SurvivorshipReason
UNION ALL
SELECT 
    'Vendors' AS EntityType,
    mg.MatchGroupID,
    mg.MatchKeyType,
    mg.MatchKeyValue,
    mg.GroupSize,
    s.WorkVendorID AS SurvivedRecordID,
    s.SurvivorshipReason,
    STRING_AGG(CONCAT(v.SourceSystem, ':', v.SourceID), ', ') WITHIN GROUP (ORDER BY v.SourceSystem, v.SourceID) AS SourceRecords
FROM work_ptp.VendorsMatchGroups mg
INNER JOIN work_ptp.VendorsMatchGroupMembers mgm ON mg.MatchGroupID = mgm.MatchGroupID
INNER JOIN work_ptp.VendorsCanonical v ON mgm.WorkVendorID = v.WorkVendorID
LEFT JOIN work_ptp.VendorsSurvivorship s ON mg.MatchGroupID = s.MatchGroupID
WHERE mg.GroupSize > 1  -- Only show actual duplicates
GROUP BY mg.MatchGroupID, mg.MatchKeyType, mg.MatchKeyValue, mg.GroupSize, s.WorkVendorID, s.SurvivorshipReason;
GO

/* =============================================================================
   reporting.RejectSummary : counts of rejected source records by reason code.

   Depends on etl.RejectLog (075_create_etl_infra.sql).
   ============================================================================= */

IF OBJECT_ID('reporting.RejectSummary','V') IS NOT NULL DROP VIEW reporting.RejectSummary;
GO

CREATE VIEW reporting.RejectSummary
AS
SELECT
    EntityType,
    SourceSystem,
    Stage,
    ReasonCode,
    COUNT(*)            AS RejectCount,
    MIN(RejectedAt)     AS FirstRejectedAt,
    MAX(RejectedAt)     AS LastRejectedAt,
    MAX(BatchID)        AS LastBatchID
FROM etl.RejectLog
GROUP BY EntityType, SourceSystem, Stage, ReasonCode;
GO

/* =============================================================================
   reporting.MigrationReconciliation : the 100% invariant.

       SourceRecords = LoadedRecords + MergedAwayRecords + OtherRejectedRecords

   Per (EntityType, SourceSystem). MergedAway = duplicate that lost survivorship
   (ReasonCode = DUPLICATE_MERGED). OtherRejected = every other reject reason
   (MISSING_REQUIRED_FIELD, INVALID_COUNTRY, ...).

   ReconciliationDelta should always be 0. Anything non-zero is a bug.
   ============================================================================= */

IF OBJECT_ID('reporting.MigrationReconciliation','V') IS NOT NULL DROP VIEW reporting.MigrationReconciliation;
GO

CREATE VIEW reporting.MigrationReconciliation
AS
WITH source_counts AS (
    SELECT 'Customers' AS EntityType, 'Northwind' AS SourceSystem,
           (SELECT COUNT(*) FROM source_northwind.Customers)    AS SourceRecords
    UNION ALL
    SELECT 'Customers', 'CsvRaw',
           (SELECT COUNT(*) FROM source_csv.CustomersExport)
    UNION ALL
    SELECT 'Vendors',   'Northwind',
           (SELECT COUNT(*) FROM source_northwind.Suppliers)
    UNION ALL
    SELECT 'Vendors',   'CsvRaw',
           (SELECT COUNT(*) FROM source_csv.VendorsExport)
),
loaded_counts AS (
    SELECT 'Customers' AS EntityType, 'Northwind' AS SourceSystem,
           (SELECT COUNT(*)
            FROM work_otc.CustomersCrosswalk cw
            WHERE cw.SourceSystem = 'Northwind'
              AND cw.TargetCustomerID IS NOT NULL
              AND NOT EXISTS (
                  SELECT 1 FROM etl.RejectLog r
                  WHERE r.EntityType = 'Customer'
                    AND r.SourceSystem = cw.SourceSystem
                    AND r.SourceID = cw.SourceID
              )) AS LoadedRecords
    UNION ALL
    SELECT 'Customers', 'CsvRaw',
           (SELECT COUNT(*)
            FROM work_otc.CustomersCrosswalk cw
            WHERE cw.SourceSystem = 'CsvRaw'
              AND cw.TargetCustomerID IS NOT NULL
              AND NOT EXISTS (
                  SELECT 1 FROM etl.RejectLog r
                  WHERE r.EntityType = 'Customer'
                    AND r.SourceSystem = cw.SourceSystem
                    AND r.SourceID = cw.SourceID
              ))
    UNION ALL
    SELECT 'Vendors', 'Northwind',
           (SELECT COUNT(*)
            FROM work_ptp.VendorsCrosswalk cw
            WHERE cw.SourceSystem = 'Northwind'
              AND cw.TargetVendorID IS NOT NULL
              AND NOT EXISTS (
                  SELECT 1 FROM etl.RejectLog r
                  WHERE r.EntityType = 'Vendor'
                    AND r.SourceSystem = cw.SourceSystem
                    AND r.SourceID = cw.SourceID
              ))
    UNION ALL
    SELECT 'Vendors', 'CsvRaw',
           (SELECT COUNT(*)
            FROM work_ptp.VendorsCrosswalk cw
            WHERE cw.SourceSystem = 'CsvRaw'
              AND cw.TargetVendorID IS NOT NULL
              AND NOT EXISTS (
                  SELECT 1 FROM etl.RejectLog r
                  WHERE r.EntityType = 'Vendor'
                    AND r.SourceSystem = cw.SourceSystem
                    AND r.SourceID = cw.SourceID
              ))
),
reject_counts AS (
    SELECT
        CASE EntityType
            WHEN 'Customer' THEN 'Customers'
            WHEN 'Vendor' THEN 'Vendors'
            ELSE EntityType
        END AS EntityType,
        SourceSystem,
        SUM(CASE WHEN ReasonCode = 'DUPLICATE_MERGED' THEN 1 ELSE 0 END) AS MergedAwayRecords,
        SUM(CASE WHEN ReasonCode <> 'DUPLICATE_MERGED' THEN 1 ELSE 0 END) AS OtherRejectedRecords
    FROM etl.RejectLog
    GROUP BY CASE EntityType
            WHEN 'Customer' THEN 'Customers'
            WHEN 'Vendor' THEN 'Vendors'
            ELSE EntityType
        END,
        SourceSystem
)
SELECT
    s.EntityType,
    s.SourceSystem,
    s.SourceRecords,
    ISNULL(l.LoadedRecords, 0)                              AS LoadedRecords,
    ISNULL(r.MergedAwayRecords, 0)                          AS MergedAwayRecords,
    ISNULL(r.OtherRejectedRecords, 0)                       AS OtherRejectedRecords,
    s.SourceRecords
        - ISNULL(l.LoadedRecords, 0)
        - ISNULL(r.MergedAwayRecords, 0)
        - ISNULL(r.OtherRejectedRecords, 0)                 AS ReconciliationDelta,
    CASE
        WHEN s.SourceRecords = 0 THEN 100.00
        ELSE CAST(
            (ISNULL(l.LoadedRecords,0) + ISNULL(r.MergedAwayRecords,0) + ISNULL(r.OtherRejectedRecords,0))
            * 100.0 / s.SourceRecords AS DECIMAL(6,2))
    END                                                     AS AccountedForPct
FROM source_counts s
LEFT JOIN loaded_counts l
    ON s.EntityType = l.EntityType AND s.SourceSystem = l.SourceSystem
LEFT JOIN reject_counts r
    ON s.EntityType = r.EntityType AND s.SourceSystem = r.SourceSystem;
GO

/* =============================================================================
   reporting.EtlRunSummary : per-batch ETL execution overview.

   Depends on etl.RunLog (075_create_etl_infra.sql).
   ============================================================================= */

IF OBJECT_ID('reporting.EtlRunSummary','V') IS NOT NULL DROP VIEW reporting.EtlRunSummary;
GO

CREATE VIEW reporting.EtlRunSummary
AS
SELECT
    BatchID,
    MIN(StartTime)                                                      AS BatchStart,
    MAX(ISNULL(EndTime, StartTime))                                     AS BatchEnd,
    DATEDIFF(MILLISECOND, MIN(StartTime), MAX(ISNULL(EndTime, StartTime))) AS BatchDurationMs,
    SUM(CASE WHEN Status = 'STARTED'   THEN 1 ELSE 0 END)               AS StepsStarted,
    SUM(CASE WHEN Status = 'COMPLETED' THEN 1 ELSE 0 END)               AS StepsCompleted,
    SUM(CASE WHEN Status = 'FAILED'    THEN 1 ELSE 0 END)               AS StepsFailed,
    SUM(ISNULL(RowsAffected, 0))                                        AS TotalRowsAffected,
    CASE
        WHEN SUM(CASE WHEN Status = 'FAILED' THEN 1 ELSE 0 END) > 0 THEN 'FAILED'
        WHEN SUM(CASE WHEN Status = 'STARTED'   THEN 1 ELSE 0 END)
           > SUM(CASE WHEN Status = 'COMPLETED' THEN 1 ELSE 0 END)      THEN 'IN_PROGRESS'
        ELSE 'COMPLETED'
    END                                                                 AS BatchStatus
FROM etl.RunLog
GROUP BY BatchID;
GO

PRINT 'Reporting views created successfully.';
PRINT '';
PRINT 'Summary:';
PRINT '  - reporting.SourceRecordCounts      : Row counts by source system';
PRINT '  - reporting.DeduplicationSummary    : Match groups and survivorship stats';
PRINT '  - reporting.DataQualitySummary      : Data completeness by field';
PRINT '  - reporting.MigrationCompleteness   : Source-to-target completion percentage';
PRINT '  - reporting.DuplicateResolution     : Details of resolved duplicates';
PRINT '  - reporting.RejectSummary           : Reject counts by reason code (etl.RejectLog)';
PRINT '  - reporting.MigrationReconciliation : Source = Loaded + MergedAway + OtherRejected';
PRINT '  - reporting.EtlRunSummary           : Per-batch run status (etl.RunLog)';
PRINT '';
PRINT 'These views can be used for:';
PRINT '  - Completeness checks (MigrationCompleteness)';
PRINT '  - Reconciliation invariant (MigrationReconciliation: ReconciliationDelta must be 0)';
PRINT '  - Duplicate resolution tracking';
PRINT '  - Data quality reporting';
PRINT '  - ETL run observability (EtlRunSummary)';
PRINT '  - Screenshots for LinkedIn/GitHub';
GO
