USE MigrationLab;
GO

/*
File
----
sql/01_migrationlab/040_create_work_tables.sql

Purpose
-------
Create working tables for business logic, deduplication, and crosswalk generation.
These tables are the core of the migration transformation layer.

Design principles
-----------------
- Work tables normalize data from multiple sources into canonical formats
- Support deduplication and match key generation
- Create crosswalk tables mapping source IDs to target IDs
- Separate schemas for OTC (Order to Cash - Customers) and PTP (Procure to Pay - Vendors)

Work schemas
-----------
- work_otc.* : Customer master data (Order to Cash process)
- work_ptp.* : Vendor master data (Procure to Pay process)

Table structure
---------------
For each process (OTC/PTP):
1. Normalized canonical table (all sources merged, normalized)
2. Match keys table (generated match keys for deduplication)
3. Match groups table (grouped duplicates)
4. Survivorship table (best record per match group)
5. Crosswalk table (source ID -> target ID mapping)

Assumptions
-----------
- Schemas already exist (created by 010_create_schemas.sql)
- Snapshot tables exist and are populated (020 + 100)
- Reference tables exist (030)
*/

SET NOCOUNT ON;

-- Safety check
IF DB_NAME() <> 'MigrationLab'
BEGIN
    THROW 50000, 'This script must be executed in the MigrationLab database context.', 1;
END;

-- Verify schemas exist
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'work_otc')
    THROW 50001, 'Missing schema work_otc. Run 010_create_schemas.sql first.', 1;

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'work_ptp')
    THROW 50002, 'Missing schema work_ptp. Run 010_create_schemas.sql first.', 1;

PRINT 'Creating work tables...';
GO

/* =============================================================================
   work_otc schema: Order to Cash (Customer Master Data)
   ============================================================================= */

-- Drop existing tables if they exist (for re-runs)
IF OBJECT_ID('work_otc.CustomersCanonical','U') IS NOT NULL DROP TABLE work_otc.CustomersCanonical;
IF OBJECT_ID('work_otc.CustomersMatchKeys','U') IS NOT NULL DROP TABLE work_otc.CustomersMatchKeys;
IF OBJECT_ID('work_otc.CustomersMatchGroups','U') IS NOT NULL DROP TABLE work_otc.CustomersMatchGroups;
IF OBJECT_ID('work_otc.CustomersSurvivorship','U') IS NOT NULL DROP TABLE work_otc.CustomersSurvivorship;
IF OBJECT_ID('work_otc.CustomersCrosswalk','U') IS NOT NULL DROP TABLE work_otc.CustomersCrosswalk;
GO

-- Canonical table: All customers from all sources, normalized
CREATE TABLE work_otc.CustomersCanonical (
    -- Surrogate key
    WorkCustomerID        BIGINT          IDENTITY(1,1) NOT NULL,
    
    -- Source identification
    SourceSystem          VARCHAR(50)     NOT NULL,  -- 'Northwind' or 'CsvRaw'
    SourceID              VARCHAR(50)     NOT NULL,  -- CustomerID or LegacyCustomerNo
    
    -- Normalized company/name fields
    CompanyName           NVARCHAR(200)   NULL,
    CompanyNameNormalized NVARCHAR(200)   NULL,  -- Normalized for matching
    
    -- Normalized contact name fields (bidirectional transformation)
    ContactNameFull       NVARCHAR(200)   NULL,  -- Full name (for Northwind sources)
    ContactFirstName      NVARCHAR(100)   NULL,
    ContactMiddleName     NVARCHAR(100)   NULL,
    ContactLastName        NVARCHAR(100)   NULL,
    
    -- Address fields
    Street                NVARCHAR(200)   NULL,
    City                  NVARCHAR(100)   NULL,
    CityNormalized        NVARCHAR(100)   NULL,  -- Normalized for matching
    Region                NVARCHAR(50)    NULL,
    PostalCode            NVARCHAR(20)    NULL,
    Country               NVARCHAR(100)   NULL,
    CountryCode           CHAR(2)          NULL,  -- Normalized from reference.CountryCodes
    
    -- Contact information
    Phone                 NVARCHAR(50)    NULL,
    PhoneNormalized       NVARCHAR(50)    NULL,  -- Digits only for matching
    Email                 NVARCHAR(200)   NULL,
    EmailNormalized       NVARCHAR(200)   NULL,  -- Lowercase, trimmed
    
    -- Data quality flags
    HasEmail              BIT             NOT NULL DEFAULT 0,
    HasPhone              BIT             NOT NULL DEFAULT 0,
    HasFullName           BIT             NOT NULL DEFAULT 0,
    HasAddress            BIT             NOT NULL DEFAULT 0,
    
    -- Audit
    CreatedTimestamp      DATETIME2(7)    NOT NULL DEFAULT SYSDATETIME(),
    
    CONSTRAINT PK_work_otc_CustomersCanonical PRIMARY KEY CLUSTERED (WorkCustomerID),
    CONSTRAINT UQ_work_otc_CustomersCanonical_Source UNIQUE (SourceSystem, SourceID)
);
GO

-- Match keys table: Generated match keys for deduplication
CREATE TABLE work_otc.CustomersMatchKeys (
    WorkCustomerID        BIGINT          NOT NULL,
    MatchKeyType          VARCHAR(50)     NOT NULL,  -- 'Email', 'Phone', 'NameCity', 'CompanyCity'
    MatchKeyValue         NVARCHAR(500)   NOT NULL,  -- Normalized match key value
    
    CONSTRAINT PK_work_otc_CustomersMatchKeys PRIMARY KEY CLUSTERED (WorkCustomerID, MatchKeyType, MatchKeyValue),
    CONSTRAINT FK_work_otc_CustomersMatchKeys_Canonical 
        FOREIGN KEY (WorkCustomerID) REFERENCES work_otc.CustomersCanonical(WorkCustomerID)
);
GO

-- Match groups table: Groups of records that match (duplicates)
CREATE TABLE work_otc.CustomersMatchGroups (
    MatchGroupID          BIGINT          IDENTITY(1,1) NOT NULL,
    MatchKeyType          VARCHAR(50)     NOT NULL,  -- Which match rule created this group
    MatchKeyValue         NVARCHAR(500)   NOT NULL,  -- The match key value
    GroupSize             INT             NOT NULL DEFAULT 0,  -- Number of records in group
    
    CONSTRAINT PK_work_otc_CustomersMatchGroups PRIMARY KEY CLUSTERED (MatchGroupID),
    CONSTRAINT UQ_work_otc_CustomersMatchGroups_Key UNIQUE (MatchKeyType, MatchKeyValue)
);
GO

-- Match group members: Links canonical records to match groups
CREATE TABLE work_otc.CustomersMatchGroupMembers (
    MatchGroupID          BIGINT          NOT NULL,
    WorkCustomerID        BIGINT          NOT NULL,
    
    CONSTRAINT PK_work_otc_CustomersMatchGroupMembers PRIMARY KEY CLUSTERED (MatchGroupID, WorkCustomerID),
    CONSTRAINT FK_work_otc_CustomersMatchGroupMembers_Group 
        FOREIGN KEY (MatchGroupID) REFERENCES work_otc.CustomersMatchGroups(MatchGroupID),
    CONSTRAINT FK_work_otc_CustomersMatchGroupMembers_Canonical 
        FOREIGN KEY (WorkCustomerID) REFERENCES work_otc.CustomersCanonical(WorkCustomerID)
);
GO

-- Survivorship table: Best record selected from each match group
CREATE TABLE work_otc.CustomersSurvivorship (
    MatchGroupID          BIGINT          NOT NULL,
    WorkCustomerID        BIGINT          NOT NULL,  -- Selected "best" record
    SurvivorshipReason    NVARCHAR(500)   NULL,  -- Why this record was chosen
    
    CONSTRAINT PK_work_otc_CustomersSurvivorship PRIMARY KEY CLUSTERED (MatchGroupID),
    CONSTRAINT FK_work_otc_CustomersSurvivorship_Group 
        FOREIGN KEY (MatchGroupID) REFERENCES work_otc.CustomersMatchGroups(MatchGroupID),
    CONSTRAINT FK_work_otc_CustomersSurvivorship_Canonical 
        FOREIGN KEY (WorkCustomerID) REFERENCES work_otc.CustomersCanonical(WorkCustomerID)
);
GO

-- Crosswalk table: Maps source IDs to target IDs (final mapping)
CREATE TABLE work_otc.CustomersCrosswalk (
    SourceSystem          VARCHAR(50)     NOT NULL,
    SourceID             VARCHAR(50)     NOT NULL,
    WorkCustomerID       BIGINT          NOT NULL,  -- Canonical ID
    TargetCustomerID     VARCHAR(50)     NULL,  -- Will be populated when target is created
    
    CONSTRAINT PK_work_otc_CustomersCrosswalk PRIMARY KEY CLUSTERED (SourceSystem, SourceID),
    CONSTRAINT FK_work_otc_CustomersCrosswalk_Canonical 
        FOREIGN KEY (WorkCustomerID) REFERENCES work_otc.CustomersCanonical(WorkCustomerID)
);
GO

-- Indexes for work_otc tables
CREATE NONCLUSTERED INDEX IX_work_otc_CustomersCanonical_Email 
    ON work_otc.CustomersCanonical(EmailNormalized) WHERE EmailNormalized IS NOT NULL;
GO

CREATE NONCLUSTERED INDEX IX_work_otc_CustomersCanonical_Phone 
    ON work_otc.CustomersCanonical(PhoneNormalized) WHERE PhoneNormalized IS NOT NULL;
GO

CREATE NONCLUSTERED INDEX IX_work_otc_CustomersCanonical_CompanyCity 
    ON work_otc.CustomersCanonical(CompanyNameNormalized, CityNormalized) 
    WHERE CompanyNameNormalized IS NOT NULL AND CityNormalized IS NOT NULL;
GO

CREATE NONCLUSTERED INDEX IX_work_otc_CustomersMatchKeys_Value 
    ON work_otc.CustomersMatchKeys(MatchKeyType, MatchKeyValue);
GO

CREATE NONCLUSTERED INDEX IX_work_otc_CustomersMatchGroupMembers_Customer 
    ON work_otc.CustomersMatchGroupMembers(WorkCustomerID);
GO

/* =============================================================================
   work_ptp schema: Procure to Pay (Vendor Master Data)
   ============================================================================= */

-- Drop existing tables if they exist (for re-runs)
IF OBJECT_ID('work_ptp.VendorsCanonical','U') IS NOT NULL DROP TABLE work_ptp.VendorsCanonical;
IF OBJECT_ID('work_ptp.VendorsMatchKeys','U') IS NOT NULL DROP TABLE work_ptp.VendorsMatchKeys;
IF OBJECT_ID('work_ptp.VendorsMatchGroups','U') IS NOT NULL DROP TABLE work_ptp.VendorsMatchGroups;
IF OBJECT_ID('work_ptp.VendorsMatchGroupMembers','U') IS NOT NULL DROP TABLE work_ptp.VendorsMatchGroupMembers;
IF OBJECT_ID('work_ptp.VendorsSurvivorship','U') IS NOT NULL DROP TABLE work_ptp.VendorsSurvivorship;
IF OBJECT_ID('work_ptp.VendorsCrosswalk','U') IS NOT NULL DROP TABLE work_ptp.VendorsCrosswalk;
GO

-- Canonical table: All vendors from all sources, normalized
CREATE TABLE work_ptp.VendorsCanonical (
    -- Surrogate key
    WorkVendorID          BIGINT          IDENTITY(1,1) NOT NULL,
    
    -- Source identification
    SourceSystem          VARCHAR(50)     NOT NULL,  -- 'Northwind' or 'CsvRaw'
    SourceID              VARCHAR(50)     NOT NULL,  -- SupplierID or LegacyVendorNo
    
    -- Normalized vendor/company name fields
    VendorName            NVARCHAR(200)   NULL,
    VendorNameNormalized  NVARCHAR(200)   NULL,  -- Normalized for matching
    
    -- Normalized contact name fields (bidirectional transformation)
    ContactNameFull       NVARCHAR(200)   NULL,  -- Full name (for Northwind sources)
    ContactFirstName      NVARCHAR(100)   NULL,
    ContactMiddleName     NVARCHAR(100)   NULL,
    ContactLastName        NVARCHAR(100)   NULL,
    
    -- Address fields
    Street                NVARCHAR(200)   NULL,
    City                  NVARCHAR(100)   NULL,
    CityNormalized        NVARCHAR(100)   NULL,  -- Normalized for matching
    Region                NVARCHAR(50)    NULL,
    PostalCode            NVARCHAR(20)    NULL,
    Country               NVARCHAR(100)   NULL,
    CountryCode           CHAR(2)          NULL,  -- Normalized from reference.CountryCodes
    
    -- Contact information
    Phone                 NVARCHAR(50)    NULL,
    PhoneNormalized       NVARCHAR(50)    NULL,  -- Digits only for matching
    Email                 NVARCHAR(200)   NULL,
    EmailNormalized       NVARCHAR(200)   NULL,  -- Lowercase, trimmed
    
    -- Data quality flags
    HasEmail              BIT             NOT NULL DEFAULT 0,
    HasPhone              BIT             NOT NULL DEFAULT 0,
    HasFullName           BIT             NOT NULL DEFAULT 0,
    HasAddress            BIT             NOT NULL DEFAULT 0,
    
    -- Audit
    CreatedTimestamp      DATETIME2(7)    NOT NULL DEFAULT SYSDATETIME(),
    
    CONSTRAINT PK_work_ptp_VendorsCanonical PRIMARY KEY CLUSTERED (WorkVendorID),
    CONSTRAINT UQ_work_ptp_VendorsCanonical_Source UNIQUE (SourceSystem, SourceID)
);
GO

-- Match keys table: Generated match keys for deduplication
CREATE TABLE work_ptp.VendorsMatchKeys (
    WorkVendorID          BIGINT          NOT NULL,
    MatchKeyType          VARCHAR(50)     NOT NULL,  -- 'Email', 'Phone', 'NameCity', 'CompanyCity'
    MatchKeyValue         NVARCHAR(500)   NOT NULL,  -- Normalized match key value
    
    CONSTRAINT PK_work_ptp_VendorsMatchKeys PRIMARY KEY CLUSTERED (WorkVendorID, MatchKeyType, MatchKeyValue),
    CONSTRAINT FK_work_ptp_VendorsMatchKeys_Canonical 
        FOREIGN KEY (WorkVendorID) REFERENCES work_ptp.VendorsCanonical(WorkVendorID)
);
GO

-- Match groups table: Groups of records that match (duplicates)
CREATE TABLE work_ptp.VendorsMatchGroups (
    MatchGroupID          BIGINT          IDENTITY(1,1) NOT NULL,
    MatchKeyType          VARCHAR(50)     NOT NULL,  -- Which match rule created this group
    MatchKeyValue         NVARCHAR(500)   NOT NULL,  -- The match key value
    GroupSize             INT             NOT NULL DEFAULT 0,  -- Number of records in group
    
    CONSTRAINT PK_work_ptp_VendorsMatchGroups PRIMARY KEY CLUSTERED (MatchGroupID),
    CONSTRAINT UQ_work_ptp_VendorsMatchGroups_Key UNIQUE (MatchKeyType, MatchKeyValue)
);
GO

-- Match group members: Links canonical records to match groups
CREATE TABLE work_ptp.VendorsMatchGroupMembers (
    MatchGroupID          BIGINT          NOT NULL,
    WorkVendorID          BIGINT          NOT NULL,
    
    CONSTRAINT PK_work_ptp_VendorsMatchGroupMembers PRIMARY KEY CLUSTERED (MatchGroupID, WorkVendorID),
    CONSTRAINT FK_work_ptp_VendorsMatchGroupMembers_Group 
        FOREIGN KEY (MatchGroupID) REFERENCES work_ptp.VendorsMatchGroups(MatchGroupID),
    CONSTRAINT FK_work_ptp_VendorsMatchGroupMembers_Canonical 
        FOREIGN KEY (WorkVendorID) REFERENCES work_ptp.VendorsCanonical(WorkVendorID)
);
GO

-- Survivorship table: Best record selected from each match group
CREATE TABLE work_ptp.VendorsSurvivorship (
    MatchGroupID          BIGINT          NOT NULL,
    WorkVendorID          BIGINT          NOT NULL,  -- Selected "best" record
    SurvivorshipReason    NVARCHAR(500)   NULL,  -- Why this record was chosen
    
    CONSTRAINT PK_work_ptp_VendorsSurvivorship PRIMARY KEY CLUSTERED (MatchGroupID),
    CONSTRAINT FK_work_ptp_VendorsSurvivorship_Group 
        FOREIGN KEY (MatchGroupID) REFERENCES work_ptp.VendorsMatchGroups(MatchGroupID),
    CONSTRAINT FK_work_ptp_VendorsSurvivorship_Canonical 
        FOREIGN KEY (WorkVendorID) REFERENCES work_ptp.VendorsCanonical(WorkVendorID)
);
GO

-- Crosswalk table: Maps source IDs to target IDs (final mapping)
CREATE TABLE work_ptp.VendorsCrosswalk (
    SourceSystem          VARCHAR(50)     NOT NULL,
    SourceID             VARCHAR(50)     NOT NULL,
    WorkVendorID          BIGINT          NOT NULL,  -- Canonical ID
    TargetVendorID        VARCHAR(50)     NULL,  -- Will be populated when target is created
    
    CONSTRAINT PK_work_ptp_VendorsCrosswalk PRIMARY KEY CLUSTERED (SourceSystem, SourceID),
    CONSTRAINT FK_work_ptp_VendorsCrosswalk_Canonical 
        FOREIGN KEY (WorkVendorID) REFERENCES work_ptp.VendorsCanonical(WorkVendorID)
);
GO

-- Indexes for work_ptp tables
CREATE NONCLUSTERED INDEX IX_work_ptp_VendorsCanonical_Email 
    ON work_ptp.VendorsCanonical(EmailNormalized) WHERE EmailNormalized IS NOT NULL;
GO

CREATE NONCLUSTERED INDEX IX_work_ptp_VendorsCanonical_Phone 
    ON work_ptp.VendorsCanonical(PhoneNormalized) WHERE PhoneNormalized IS NOT NULL;
GO

CREATE NONCLUSTERED INDEX IX_work_ptp_VendorsCanonical_VendorCity 
    ON work_ptp.VendorsCanonical(VendorNameNormalized, CityNormalized) 
    WHERE VendorNameNormalized IS NOT NULL AND CityNormalized IS NOT NULL;
GO

CREATE NONCLUSTERED INDEX IX_work_ptp_VendorsMatchKeys_Value 
    ON work_ptp.VendorsMatchKeys(MatchKeyType, MatchKeyValue);
GO

CREATE NONCLUSTERED INDEX IX_work_ptp_VendorsMatchGroupMembers_Vendor 
    ON work_ptp.VendorsMatchGroupMembers(WorkVendorID);
GO

PRINT 'Work tables created successfully.';
PRINT '';
PRINT 'Summary:';
PRINT '  - work_otc.* : Customer master data tables (6 tables)';
PRINT '  - work_ptp.* : Vendor master data tables (6 tables)';
PRINT '';
PRINT 'Next step: Run ETL procedures to populate work tables:';
PRINT '  - 110_etl_build_work_otc.sql';
PRINT '  - 120_etl_build_work_ptp.sql';
GO
