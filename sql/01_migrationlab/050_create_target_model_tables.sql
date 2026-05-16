USE MigrationLab;
GO

/*
File
----
sql/01_migrationlab/050_create_target_model_tables.sql

Purpose
-------
Create target model tables - clean, normalized structures ready for final target transformation.
These tables represent the "golden record" after deduplication and survivorship.

Design principles
-----------------
- Target model is the clean, normalized output from work layer
- One record per entity (after deduplication)
- All fields normalized and standardized
- Ready for transformation to final target format (SAP ECC)
- No source-specific fields (pure business data)

Target model tables
------------------
- target_model.Customers: Clean customer master data
- target_model.Vendors: Clean vendor master data

Assumptions
-----------
- Schema 'target_model' already exists (created by 010_create_schemas.sql)
- Work tables exist and will be populated by ETL (040 + 110/120)
*/

SET NOCOUNT ON;

-- Safety check
IF DB_NAME() <> 'MigrationLab'
BEGIN
    THROW 50000, 'This script must be executed in the MigrationLab database context.', 1;
END;

-- Verify schema exists
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'target_model')
    THROW 50001, 'Missing schema target_model. Run 010_create_schemas.sql first.', 1;

PRINT 'Creating target model tables...';
GO

/* =============================================================================
   target_model.Customers: Clean customer master data
   ============================================================================= */

IF OBJECT_ID('target_model.Customers','U') IS NOT NULL DROP TABLE target_model.Customers;
GO

CREATE TABLE target_model.Customers (
    -- Primary identifier
    CustomerID            VARCHAR(50)     NOT NULL,  -- Generated target ID
    
    -- Company information
    CompanyName           NVARCHAR(200)   NOT NULL,
    CompanyNameLegal      NVARCHAR(200)   NULL,  -- Legal name if different
    
    -- Contact information
    ContactFirstName      NVARCHAR(100)   NULL,
    ContactMiddleName     NVARCHAR(100)   NULL,
    ContactLastName       NVARCHAR(100)   NULL,
    ContactFullName       NVARCHAR(300)   NULL,  -- Computed: First + Middle + Last
    ContactTitle          NVARCHAR(100)   NULL,
    
    -- Address information
    Street                NVARCHAR(200)   NULL,
    City                  NVARCHAR(100)   NULL,
    Region                NVARCHAR(50)    NULL,
    PostalCode            NVARCHAR(20)    NULL,
    Country               NVARCHAR(100)   NULL,
    CountryCode           CHAR(2)          NULL,  -- ISO 3166-1 alpha-2
    
    -- Contact details
    Phone                 NVARCHAR(50)    NULL,
    PhoneNormalized       NVARCHAR(50)    NULL,  -- Digits only
    Fax                   NVARCHAR(50)    NULL,
    Email                 NVARCHAR(200)   NULL,
    EmailNormalized       NVARCHAR(200)   NULL,  -- Lowercase, trimmed
    
    -- Data quality indicators
    DataQualityScore      INT             NULL,  -- 0-100, higher = better
    HasCompleteAddress    BIT             NOT NULL DEFAULT 0,
    HasValidEmail         BIT             NOT NULL DEFAULT 0,
    HasValidPhone         BIT             NOT NULL DEFAULT 0,
    HasContactName        BIT             NOT NULL DEFAULT 0,
    
    -- Source tracking (for audit)
    SourceSystems         VARCHAR(200)    NULL,  -- Comma-separated: 'Northwind,CsvRaw'
    SourceRecordCount     INT             NOT NULL DEFAULT 1,  -- How many source records merged
    
    -- Audit
    CreatedTimestamp      DATETIME2(7)    NOT NULL DEFAULT SYSDATETIME(),
    LastUpdatedTimestamp  DATETIME2(7)    NOT NULL DEFAULT SYSDATETIME(),
    
    CONSTRAINT PK_target_model_Customers PRIMARY KEY CLUSTERED (CustomerID)
);
GO

-- Indexes for target_model.Customers
CREATE NONCLUSTERED INDEX IX_target_model_Customers_CompanyName 
    ON target_model.Customers(CompanyName);
GO

CREATE NONCLUSTERED INDEX IX_target_model_Customers_Email 
    ON target_model.Customers(EmailNormalized) WHERE EmailNormalized IS NOT NULL;
GO

CREATE NONCLUSTERED INDEX IX_target_model_Customers_Phone 
    ON target_model.Customers(PhoneNormalized) WHERE PhoneNormalized IS NOT NULL;
GO

CREATE NONCLUSTERED INDEX IX_target_model_Customers_Country 
    ON target_model.Customers(CountryCode);
GO

CREATE NONCLUSTERED INDEX IX_target_model_Customers_City 
    ON target_model.Customers(City);
GO

/* =============================================================================
   target_model.Vendors: Clean vendor master data
   ============================================================================= */

IF OBJECT_ID('target_model.Vendors','U') IS NOT NULL DROP TABLE target_model.Vendors;
GO

CREATE TABLE target_model.Vendors (
    -- Primary identifier
    VendorID              VARCHAR(50)     NOT NULL,  -- Generated target ID
    
    -- Vendor information
    VendorName            NVARCHAR(200)   NOT NULL,
    VendorNameLegal       NVARCHAR(200)   NULL,  -- Legal name if different
    
    -- Contact information
    ContactFirstName      NVARCHAR(100)   NULL,
    ContactMiddleName     NVARCHAR(100)   NULL,
    ContactLastName       NVARCHAR(100)   NULL,
    ContactFullName       NVARCHAR(300)   NULL,  -- Computed: First + Middle + Last
    ContactTitle          NVARCHAR(100)   NULL,
    
    -- Address information
    Street                NVARCHAR(200)   NULL,
    City                  NVARCHAR(100)   NULL,
    Region                NVARCHAR(50)    NULL,
    PostalCode            NVARCHAR(20)    NULL,
    Country               NVARCHAR(100)   NULL,
    CountryCode           CHAR(2)          NULL,  -- ISO 3166-1 alpha-2
    
    -- Contact details
    Phone                 NVARCHAR(50)    NULL,
    PhoneNormalized       NVARCHAR(50)    NULL,  -- Digits only
    Fax                   NVARCHAR(50)    NULL,
    Email                 NVARCHAR(200)   NULL,
    EmailNormalized       NVARCHAR(200)   NULL,  -- Lowercase, trimmed
    HomePage              NVARCHAR(500)   NULL,  -- Website URL
    
    -- Data quality indicators
    DataQualityScore      INT             NULL,  -- 0-100, higher = better
    HasCompleteAddress    BIT             NOT NULL DEFAULT 0,
    HasValidEmail         BIT             NOT NULL DEFAULT 0,
    HasValidPhone         BIT             NOT NULL DEFAULT 0,
    HasContactName        BIT             NOT NULL DEFAULT 0,
    
    -- Source tracking (for audit)
    SourceSystems         VARCHAR(200)    NULL,  -- Comma-separated: 'Northwind,CsvRaw'
    SourceRecordCount     INT             NOT NULL DEFAULT 1,  -- How many source records merged
    
    -- Audit
    CreatedTimestamp      DATETIME2(7)    NOT NULL DEFAULT SYSDATETIME(),
    LastUpdatedTimestamp  DATETIME2(7)    NOT NULL DEFAULT SYSDATETIME(),
    
    CONSTRAINT PK_target_model_Vendors PRIMARY KEY CLUSTERED (VendorID)
);
GO

-- Indexes for target_model.Vendors
CREATE NONCLUSTERED INDEX IX_target_model_Vendors_VendorName 
    ON target_model.Vendors(VendorName);
GO

CREATE NONCLUSTERED INDEX IX_target_model_Vendors_Email 
    ON target_model.Vendors(EmailNormalized) WHERE EmailNormalized IS NOT NULL;
GO

CREATE NONCLUSTERED INDEX IX_target_model_Vendors_Phone 
    ON target_model.Vendors(PhoneNormalized) WHERE PhoneNormalized IS NOT NULL;
GO

CREATE NONCLUSTERED INDEX IX_target_model_Vendors_Country 
    ON target_model.Vendors(CountryCode);
GO

CREATE NONCLUSTERED INDEX IX_target_model_Vendors_City 
    ON target_model.Vendors(City);
GO

PRINT 'Target model tables created successfully.';
PRINT '';
PRINT 'Summary:';
PRINT '  - target_model.Customers: Clean customer master data';
PRINT '  - target_model.Vendors: Clean vendor master data';
PRINT '';
PRINT 'Next step: Run ETL procedure 130_etl_build_target_model.sql to populate from work tables.';
GO
