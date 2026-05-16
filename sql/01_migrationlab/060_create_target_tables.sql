USE MigrationLab;
GO

/*
File
----
sql/01_migrationlab/060_create_target_tables.sql

Purpose
-------
Create final target tables in SAP ECC-like format.
These tables represent the production-ready target system structure.

Design principles
-----------------
- Target structure inspired by enterprise ERP master data patterns
- Generic field naming (no vendor-specific abbreviations)
- Supports standard master data fields (name, address, contact, etc.)
- Includes audit and control fields
- Ready for production load

Target tables
-------------
- target_sap_ecc.CustomerMaster: Customer master data (inspired by KNA1 pattern)
- target_sap_ecc.VendorMaster: Vendor master data (inspired by LFA1 pattern)

Assumptions
-----------
- Schema 'target_sap_ecc' already exists (created by 010_create_schemas.sql)
- Target model tables exist and will be populated (050 + 130)
*/

SET NOCOUNT ON;

-- Safety check
IF DB_NAME() <> 'MigrationLab'
BEGIN
    THROW 50000, 'This script must be executed in the MigrationLab database context.', 1;
END;

-- Verify schema exists
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'target_sap_ecc')
    THROW 50001, 'Missing schema target_sap_ecc. Run 010_create_schemas.sql first.', 1;

PRINT 'Creating target tables...';
GO

/* =============================================================================
   target_sap_ecc.CustomerMaster: Customer master data
   ============================================================================= */

IF OBJECT_ID('target_sap_ecc.CustomerMaster','U') IS NOT NULL DROP TABLE target_sap_ecc.CustomerMaster;
GO

CREATE TABLE target_sap_ecc.CustomerMaster (
    -- Primary key
    CustomerNumber        VARCHAR(20)     NOT NULL,  -- Target system customer number
    
    -- Name and address (Name 1 = Company Name)
    Name1                 NVARCHAR(80)    NOT NULL,  -- Company name (primary)
    Name2                 NVARCHAR(80)    NULL,      -- Additional name line
    Name3                 NVARCHAR(80)    NULL,      -- Additional name line
    Name4                 NVARCHAR(80)    NULL,      -- Additional name line
    
    -- Address
    Street                NVARCHAR(60)    NULL,
    StreetNumber          NVARCHAR(10)    NULL,      -- House/building number
    City                  NVARCHAR(40)    NULL,
    Region                NVARCHAR(3)     NULL,      -- State/region code
    PostalCode            NVARCHAR(10)    NULL,
    Country               CHAR(2)         NULL,      -- ISO country code
    
    -- Contact person
    ContactPerson         NVARCHAR(80)    NULL,      -- Full contact name
    ContactTitle          NVARCHAR(40)    NULL,      -- Job title
    
    -- Communication
    Telephone             NVARCHAR(30)    NULL,
    TelephoneExtension    NVARCHAR(10)    NULL,
    Mobile                NVARCHAR(30)    NULL,
    Fax                   NVARCHAR(30)    NULL,
    Email                 NVARCHAR(241)   NULL,      -- Standard email length
    
    -- Account group and classification
    AccountGroup          VARCHAR(4)      NULL,      -- Customer account group
    CustomerType          VARCHAR(2)      NULL,      -- Customer type classification
    
    -- Status and control
    Status                CHAR(1)         NOT NULL DEFAULT 'A',  -- A=Active, B=Blocked, D=Deleted
    DeletionFlag          CHAR(1)         NOT NULL DEFAULT ' ',   -- Space=Active, X=Marked for deletion
    
    -- Audit and control
    CreatedBy             VARCHAR(12)     NULL,
    CreatedDate           DATE            NULL,
    CreatedTime           TIME            NULL,
    LastChangedBy         VARCHAR(12)     NULL,
    LastChangedDate       DATE            NULL,
    LastChangedTime       TIME            NULL,
    
    -- Migration tracking
    MigrationSource       VARCHAR(50)     NULL,      -- Source system(s)
    MigrationTimestamp    DATETIME2(7)    NULL,
    MigrationBatchID      VARCHAR(50)     NULL,
    
    CONSTRAINT PK_target_sap_ecc_CustomerMaster PRIMARY KEY CLUSTERED (CustomerNumber)
);
GO

-- Indexes for target_sap_ecc.CustomerMaster
CREATE NONCLUSTERED INDEX IX_target_sap_ecc_CustomerMaster_Name1 
    ON target_sap_ecc.CustomerMaster(Name1);
GO

CREATE NONCLUSTERED INDEX IX_target_sap_ecc_CustomerMaster_Email 
    ON target_sap_ecc.CustomerMaster(Email) WHERE Email IS NOT NULL;
GO

CREATE NONCLUSTERED INDEX IX_target_sap_ecc_CustomerMaster_Country 
    ON target_sap_ecc.CustomerMaster(Country);
GO

CREATE NONCLUSTERED INDEX IX_target_sap_ecc_CustomerMaster_City 
    ON target_sap_ecc.CustomerMaster(City);
GO

CREATE NONCLUSTERED INDEX IX_target_sap_ecc_CustomerMaster_Status 
    ON target_sap_ecc.CustomerMaster(Status, DeletionFlag);
GO

/* =============================================================================
   target_sap_ecc.VendorMaster: Vendor master data
   ============================================================================= */

IF OBJECT_ID('target_sap_ecc.VendorMaster','U') IS NOT NULL DROP TABLE target_sap_ecc.VendorMaster;
GO

CREATE TABLE target_sap_ecc.VendorMaster (
    -- Primary key
    VendorNumber          VARCHAR(20)     NOT NULL,  -- Target system vendor number
    
    -- Name and address (Name 1 = Vendor Name)
    Name1                 NVARCHAR(80)    NOT NULL,  -- Vendor name (primary)
    Name2                 NVARCHAR(80)    NULL,      -- Additional name line
    Name3                 NVARCHAR(80)    NULL,      -- Additional name line
    Name4                 NVARCHAR(80)    NULL,      -- Additional name line
    
    -- Address
    Street                NVARCHAR(60)    NULL,
    StreetNumber          NVARCHAR(10)    NULL,      -- House/building number
    City                  NVARCHAR(40)    NULL,
    Region                NVARCHAR(3)     NULL,      -- State/region code
    PostalCode            NVARCHAR(10)    NULL,
    Country               CHAR(2)         NULL,      -- ISO country code
    
    -- Contact person
    ContactPerson         NVARCHAR(80)    NULL,      -- Full contact name
    ContactTitle          NVARCHAR(40)    NULL,      -- Job title
    
    -- Communication
    Telephone             NVARCHAR(30)    NULL,
    TelephoneExtension    NVARCHAR(10)    NULL,
    Mobile                NVARCHAR(30)    NULL,
    Fax                   NVARCHAR(30)    NULL,
    Email                 NVARCHAR(241)   NULL,      -- Standard email length
    Website               NVARCHAR(132)   NULL,      -- Homepage URL
    
    -- Account group and classification
    AccountGroup          VARCHAR(4)      NULL,      -- Vendor account group
    VendorType            VARCHAR(2)      NULL,      -- Vendor type classification
    
    -- Status and control
    Status                CHAR(1)         NOT NULL DEFAULT 'A',  -- A=Active, B=Blocked, D=Deleted
    DeletionFlag          CHAR(1)         NOT NULL DEFAULT ' ',   -- Space=Active, X=Marked for deletion
    
    -- Audit and control
    CreatedBy             VARCHAR(12)     NULL,
    CreatedDate           DATE            NULL,
    CreatedTime           TIME            NULL,
    LastChangedBy         VARCHAR(12)     NULL,
    LastChangedDate       DATE            NULL,
    LastChangedTime       TIME            NULL,
    
    -- Migration tracking
    MigrationSource       VARCHAR(50)     NULL,      -- Source system(s)
    MigrationTimestamp    DATETIME2(7)    NULL,
    MigrationBatchID      VARCHAR(50)     NULL,
    
    CONSTRAINT PK_target_sap_ecc_VendorMaster PRIMARY KEY CLUSTERED (VendorNumber)
);
GO

-- Indexes for target_sap_ecc.VendorMaster
CREATE NONCLUSTERED INDEX IX_target_sap_ecc_VendorMaster_Name1 
    ON target_sap_ecc.VendorMaster(Name1);
GO

CREATE NONCLUSTERED INDEX IX_target_sap_ecc_VendorMaster_Email 
    ON target_sap_ecc.VendorMaster(Email) WHERE Email IS NOT NULL;
GO

CREATE NONCLUSTERED INDEX IX_target_sap_ecc_VendorMaster_Country 
    ON target_sap_ecc.VendorMaster(Country);
GO

CREATE NONCLUSTERED INDEX IX_target_sap_ecc_VendorMaster_City 
    ON target_sap_ecc.VendorMaster(City);
GO

CREATE NONCLUSTERED INDEX IX_target_sap_ecc_VendorMaster_Status 
    ON target_sap_ecc.VendorMaster(Status, DeletionFlag);
GO

PRINT 'Target tables created successfully.';
PRINT '';
PRINT 'Summary:';
PRINT '  - target_sap_ecc.CustomerMaster: Customer master data (SAP ECC-like structure)';
PRINT '  - target_sap_ecc.VendorMaster: Vendor master data (SAP ECC-like structure)';
PRINT '';
PRINT 'Next step: Run ETL procedure 140_etl_load_target.sql to populate from target_model.';
GO
