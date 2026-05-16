USE MigrationLab;
GO

/*
File
----
sql/01_migrationlab/075_create_etl_infra.sql

Purpose
-------
ETL infrastructure tables that the stored procedures (080) read and write.

- etl.RunLog               : one row per ETL step execution (observability)
- etl.RejectLog            : one row per source record dropped, with reason code
- reference.SurvivorshipRules : per-attribute source priority for target_model build

These are the tables that turn the project from "scripts that run" into
"a pipeline that you can audit, reconcile to 100%, and reason about
when it goes wrong."

Assumptions
-----------
- Schemas etl and reference exist (010_create_schemas.sql)
*/

SET NOCOUNT ON;

IF DB_NAME() <> 'MigrationLab'
    THROW 50000, 'This script must be executed in the MigrationLab database context.', 1;

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'etl')
    THROW 50001, 'Missing schema etl. Run 010_create_schemas.sql first.', 1;

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'reference')
    THROW 50002, 'Missing schema reference. Run 010_create_schemas.sql first.', 1;

PRINT 'Creating ETL infrastructure tables...';
GO

/* =============================================================================
   etl.RunLog : every ETL step writes a start row and an end row here.
   ============================================================================= */

IF OBJECT_ID('etl.RunLog','U') IS NOT NULL DROP TABLE etl.RunLog;
GO

CREATE TABLE etl.RunLog (
    RunLogID        BIGINT          IDENTITY(1,1) NOT NULL,
    BatchID         VARCHAR(50)     NOT NULL,
    ProcName        VARCHAR(100)    NOT NULL,
    StepName        VARCHAR(200)    NOT NULL,
    Status          VARCHAR(20)     NOT NULL,  -- 'STARTED' | 'COMPLETED' | 'FAILED'
    RowsAffected    BIGINT          NULL,
    StartTime       DATETIME2(7)    NOT NULL DEFAULT SYSDATETIME(),
    EndTime         DATETIME2(7)    NULL,
    DurationMs      AS DATEDIFF(MILLISECOND, StartTime, EndTime),
    ErrorNumber     INT             NULL,
    ErrorMessage    NVARCHAR(2000)  NULL,

    CONSTRAINT PK_etl_RunLog PRIMARY KEY CLUSTERED (RunLogID)
);
GO

CREATE NONCLUSTERED INDEX IX_etl_RunLog_BatchID ON etl.RunLog(BatchID, StartTime);
GO

/* =============================================================================
   etl.RejectLog : every source record dropped (or merged-away) gets a row.

   The reconciliation invariant we want to be able to assert is:
       SourceRecords = LoadedRecords + RejectedRecords + MergedAwayRecords

   ReasonCode taxonomy (extend as new rules are added):
     - DUPLICATE_MERGED        : record was a duplicate; survivor lives in target_model
     - MISSING_REQUIRED_FIELD  : e.g. CompanyName / VendorName NULL
     - INVALID_COUNTRY         : country could not be normalized to ISO-2
     - MALFORMED_EMAIL         : email present but obviously broken
     - UNMAPPED_SURVIVOR       : survivorship pointed at a record that did not load
   ============================================================================= */

IF OBJECT_ID('etl.RejectLog','U') IS NOT NULL DROP TABLE etl.RejectLog;
GO

CREATE TABLE etl.RejectLog (
    RejectID         BIGINT          IDENTITY(1,1) NOT NULL,
    BatchID          VARCHAR(50)     NOT NULL,
    EntityType       VARCHAR(20)     NOT NULL,  -- 'Customer' | 'Vendor'
    SourceSystem     VARCHAR(50)     NOT NULL,
    SourceID         VARCHAR(50)     NOT NULL,
    Stage            VARCHAR(50)     NOT NULL,  -- 'Canonical' | 'Survivorship' | 'TargetModel' | 'TargetLoad'
    ReasonCode       VARCHAR(50)     NOT NULL,
    ReasonDetail     NVARCHAR(500)   NULL,
    SurvivorWorkID   BIGINT          NULL,      -- populated when ReasonCode = DUPLICATE_MERGED
    RejectedAt       DATETIME2(7)    NOT NULL DEFAULT SYSDATETIME(),

    CONSTRAINT PK_etl_RejectLog PRIMARY KEY CLUSTERED (RejectID)
);
GO

CREATE NONCLUSTERED INDEX IX_etl_RejectLog_BatchID
    ON etl.RejectLog(BatchID, EntityType, SourceSystem);
GO

CREATE NONCLUSTERED INDEX IX_etl_RejectLog_Reason
    ON etl.RejectLog(ReasonCode, EntityType);
GO

/* =============================================================================
   reference.SurvivorshipRules : per-attribute source priority.

   Read by 130 (target_model build). Lower Priority wins.
   Versioned so an in-flight migration can be pinned to a known rule set.

   Example: Email — prefer CRM (CSV) because sales team maintains it.
            Phone — prefer ERP (Northwind) because finance validates it for invoicing.
   ============================================================================= */

IF OBJECT_ID('reference.SurvivorshipRules','U') IS NOT NULL DROP TABLE reference.SurvivorshipRules;
GO

CREATE TABLE reference.SurvivorshipRules (
    RuleID           INT             IDENTITY(1,1) NOT NULL,
    EntityType       VARCHAR(20)     NOT NULL,  -- 'Customer' | 'Vendor'
    AttributeName    VARCHAR(50)     NOT NULL,  -- 'Email' | 'Phone' | 'Street' | 'CompanyName' | ...
    SourceSystem     VARCHAR(50)     NOT NULL,  -- 'Northwind' | 'CsvRaw'
    Priority         INT             NOT NULL,  -- lower = preferred
    Rationale        NVARCHAR(500)   NULL,
    RuleVersion      INT             NOT NULL DEFAULT 1,
    IsActive         BIT             NOT NULL DEFAULT 1,

    CONSTRAINT PK_reference_SurvivorshipRules PRIMARY KEY CLUSTERED (RuleID),
    CONSTRAINT UQ_reference_SurvivorshipRules UNIQUE (EntityType, AttributeName, SourceSystem, RuleVersion)
);
GO

INSERT INTO reference.SurvivorshipRules (EntityType, AttributeName, SourceSystem, Priority, Rationale)
VALUES
    -- Customer: CRM (CSV) wins for contact channels; ERP wins for company / address
    ('Customer','Email',       'CsvRaw',    1, 'CRM is the system of record for customer email; sales team maintains it.'),
    ('Customer','Email',       'Northwind', 2, 'Fallback when CRM email is missing.'),
    ('Customer','Phone',       'Northwind', 1, 'ERP phone is finance-validated for invoicing/dunning.'),
    ('Customer','Phone',       'CsvRaw',    2, 'Fallback when ERP phone is missing.'),
    ('Customer','CompanyName', 'Northwind', 1, 'ERP carries the legal/billing name; CSV may have casual variants.'),
    ('Customer','CompanyName', 'CsvRaw',    2, 'Fallback only.'),
    ('Customer','Street',      'Northwind', 1, 'ERP address is used for shipping in the source system.'),
    ('Customer','Street',      'CsvRaw',    2, 'Fallback only.'),
    ('Customer','City',        'Northwind', 1, 'ERP city is finance-validated.'),
    ('Customer','City',        'CsvRaw',    2, 'Fallback only.'),
    ('Customer','PostalCode',  'Northwind', 1, 'ERP is finance-validated.'),
    ('Customer','PostalCode',  'CsvRaw',    2, 'Fallback only.'),
    ('Customer','Country',     'Northwind', 1, 'ERP country drives tax determination.'),
    ('Customer','Country',     'CsvRaw',    2, 'Fallback only.'),

    -- Vendor: same shape, different rationale
    ('Vendor',  'Email',       'CsvRaw',    1, 'Procurement maintains vendor contact email in CRM/CSV exports.'),
    ('Vendor',  'Email',       'Northwind', 2, 'Fallback only.'),
    ('Vendor',  'Phone',       'Northwind', 1, 'ERP phone is AP-validated.'),
    ('Vendor',  'Phone',       'CsvRaw',    2, 'Fallback only.'),
    ('Vendor',  'VendorName',  'Northwind', 1, 'ERP carries the legal/payment name.'),
    ('Vendor',  'VendorName',  'CsvRaw',    2, 'Fallback only.'),
    ('Vendor',  'Street',      'Northwind', 1, 'ERP address is used for remittance.'),
    ('Vendor',  'Street',      'CsvRaw',    2, 'Fallback only.'),
    ('Vendor',  'City',        'Northwind', 1, 'ERP is AP-validated.'),
    ('Vendor',  'City',        'CsvRaw',    2, 'Fallback only.'),
    ('Vendor',  'PostalCode',  'Northwind', 1, 'ERP is AP-validated.'),
    ('Vendor',  'PostalCode',  'CsvRaw',    2, 'Fallback only.'),
    ('Vendor',  'Country',     'Northwind', 1, 'ERP country drives withholding/tax.'),
    ('Vendor',  'Country',     'CsvRaw',    2, 'Fallback only.');
GO

CREATE NONCLUSTERED INDEX IX_reference_SurvivorshipRules_Lookup
    ON reference.SurvivorshipRules(EntityType, AttributeName, IsActive, Priority);
GO

PRINT 'ETL infrastructure tables created successfully.';
PRINT '';
PRINT 'Created:';
PRINT '  - etl.RunLog                   (one row per step start/end)';
PRINT '  - etl.RejectLog                (per-record rejects with reason codes)';
PRINT '  - reference.SurvivorshipRules  (per-attribute source priority, versioned)';
GO
