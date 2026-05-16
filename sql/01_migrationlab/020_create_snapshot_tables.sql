USE MigrationLab;
GO

/*
File
----
sql/01_migrationlab/020_create_snapshot_tables.sql

Purpose
-------
Create snapshot tables in MigrationLab that capture point-in-time copies of source data.
These tables serve as read-only reference points for the migration process.

Design principles
-----------------
- Snapshot tables mirror source table structures exactly
- Add metadata columns for audit/traceability (snapshot_timestamp, source_system)
- No data transformation at snapshot stage (raw copy)
- Tables are refreshed by ETL procedures (see 02_etl_procs/100_etl_refresh_snapshots.sql)

Source systems
--------------
- source_northwind.* : Snapshots from Northwind database (Customers, Suppliers)
- source_csv.*       : Snapshots from CsvRaw database (CustomersExport, VendorsExport)

Assumptions
-----------
- Schemas already exist (created by 010_create_schemas.sql)
- Source databases (Northwind, CsvRaw) exist and contain data
*/

SET NOCOUNT ON;

-- Safety check
IF DB_NAME() <> 'MigrationLab'
BEGIN
    THROW 50000, 'This script must be executed in the MigrationLab database context.', 1;
END;

-- Verify schemas exist
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'source_northwind')
    THROW 50001, 'Missing schema source_northwind. Run 010_create_schemas.sql first.', 1;

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'source_csv')
    THROW 50002, 'Missing schema source_csv. Run 010_create_schemas.sql first.', 1;

PRINT 'Creating snapshot tables...';
GO

/* =============================================================================
   source_northwind schema: Snapshots from Northwind database
   ============================================================================= */

-- Drop existing tables if they exist (for re-runs)
IF OBJECT_ID('source_northwind.Customers','U') IS NOT NULL DROP TABLE source_northwind.Customers;
IF OBJECT_ID('source_northwind.Suppliers','U') IS NOT NULL DROP TABLE source_northwind.Suppliers;
GO

-- Snapshot: Northwind Customers
CREATE TABLE source_northwind.Customers (
    -- Source columns (mirror Northwind.dbo.Customers exactly)
    CustomerID      NCHAR(5)        NOT NULL,
    CompanyName     NVARCHAR(40)    NOT NULL,
    ContactName     NVARCHAR(30)    NULL,
    ContactTitle    NVARCHAR(30)    NULL,
    Address         NVARCHAR(60)   NULL,
    City            NVARCHAR(15)    NULL,
    Region          NVARCHAR(15)    NULL,
    PostalCode      NVARCHAR(10)    NULL,
    Country         NVARCHAR(15)    NULL,
    Phone           NVARCHAR(24)    NULL,
    Fax             NVARCHAR(24)    NULL,
    
    -- Snapshot metadata
    snapshot_timestamp  DATETIME2(7)    NOT NULL DEFAULT SYSDATETIME(),
    source_system       VARCHAR(50)     NOT NULL DEFAULT 'Northwind',
    
    CONSTRAINT PK_source_northwind_Customers PRIMARY KEY CLUSTERED (CustomerID)
);
GO

-- Snapshot: Northwind Suppliers
CREATE TABLE source_northwind.Suppliers (
    -- Source columns (mirror Northwind.dbo.Suppliers exactly)
    SupplierID      INT             NOT NULL,
    CompanyName     NVARCHAR(40)    NOT NULL,
    ContactName     NVARCHAR(30)    NULL,
    ContactTitle    NVARCHAR(30)    NULL,
    Address         NVARCHAR(60)    NULL,
    City            NVARCHAR(15)    NULL,
    Region          NVARCHAR(15)    NULL,
    PostalCode      NVARCHAR(10)    NULL,
    Country         NVARCHAR(15)    NULL,
    Phone           NVARCHAR(24)    NULL,
    Fax             NVARCHAR(24)    NULL,
    HomePage        NTEXT           NULL,
    
    -- Snapshot metadata
    snapshot_timestamp  DATETIME2(7)    NOT NULL DEFAULT SYSDATETIME(),
    source_system       VARCHAR(50)     NOT NULL DEFAULT 'Northwind',
    
    CONSTRAINT PK_source_northwind_Suppliers PRIMARY KEY CLUSTERED (SupplierID)
);
GO

/* =============================================================================
   source_csv schema: Snapshots from CsvRaw database
   ============================================================================= */

-- Drop existing tables if they exist (for re-runs)
IF OBJECT_ID('source_csv.CustomersExport','U') IS NOT NULL DROP TABLE source_csv.CustomersExport;
IF OBJECT_ID('source_csv.VendorsExport','U') IS NOT NULL DROP TABLE source_csv.VendorsExport;
GO

-- Snapshot: CsvRaw CustomersExport
CREATE TABLE source_csv.CustomersExport (
    -- Source columns (mirror CsvRaw.dbo.CustomersExport exactly)
    LegacyCustomerNo    VARCHAR(30)     NOT NULL,
    Company             NVARCHAR(100)   NULL,
    ContactFirstName    NVARCHAR(50)    NULL,
    ContactMiddleName   NVARCHAR(100)   NULL,
    ContactLastName     NVARCHAR(50)    NULL,
    City                NVARCHAR(50)    NULL,
    Country             NVARCHAR(50)    NULL,
    PostalCode          NVARCHAR(20)    NULL,
    Street              NVARCHAR(120)   NULL,
    Phone               NVARCHAR(50)    NULL,
    Email               NVARCHAR(150)   NULL,
    
    -- Snapshot metadata
    snapshot_timestamp  DATETIME2(7)    NOT NULL DEFAULT SYSDATETIME(),
    source_system       VARCHAR(50)     NOT NULL DEFAULT 'CsvRaw',
    
    CONSTRAINT PK_source_csv_CustomersExport PRIMARY KEY CLUSTERED (LegacyCustomerNo)
);
GO

-- Snapshot: CsvRaw VendorsExport
CREATE TABLE source_csv.VendorsExport (
    -- Source columns (mirror CsvRaw.dbo.VendorsExport exactly)
    LegacyVendorNo      VARCHAR(30)     NOT NULL,
    VendorName          NVARCHAR(100)   NULL,
    ContactFirstName    NVARCHAR(50)    NULL,
    ContactMiddleName   NVARCHAR(100)   NULL,
    ContactLastName     NVARCHAR(50)    NULL,
    City                NVARCHAR(50)    NULL,
    Country             NVARCHAR(50)    NULL,
    PostalCode          NVARCHAR(20)    NULL,
    Street              NVARCHAR(120)   NULL,
    Phone               NVARCHAR(50)    NULL,
    Email               NVARCHAR(150)   NULL,
    
    -- Snapshot metadata
    snapshot_timestamp  DATETIME2(7)    NOT NULL DEFAULT SYSDATETIME(),
    source_system       VARCHAR(50)     NOT NULL DEFAULT 'CsvRaw',
    
    CONSTRAINT PK_source_csv_VendorsExport PRIMARY KEY CLUSTERED (LegacyVendorNo)
);
GO

/* =============================================================================
   Create indexes for common query patterns
   ============================================================================= */

-- Indexes on source_northwind.Customers
CREATE NONCLUSTERED INDEX IX_source_northwind_Customers_CompanyName 
    ON source_northwind.Customers(CompanyName);
GO

CREATE NONCLUSTERED INDEX IX_source_northwind_Customers_City 
    ON source_northwind.Customers(City);
GO

CREATE NONCLUSTERED INDEX IX_source_northwind_Customers_Country 
    ON source_northwind.Customers(Country);
GO

-- Indexes on source_northwind.Suppliers
CREATE NONCLUSTERED INDEX IX_source_northwind_Suppliers_CompanyName 
    ON source_northwind.Suppliers(CompanyName);
GO

CREATE NONCLUSTERED INDEX IX_source_northwind_Suppliers_Country 
    ON source_northwind.Suppliers(Country);
GO

-- Indexes on source_csv.CustomersExport
CREATE NONCLUSTERED INDEX IX_source_csv_CustomersExport_Company 
    ON source_csv.CustomersExport(Company);
GO

CREATE NONCLUSTERED INDEX IX_source_csv_CustomersExport_Email 
    ON source_csv.CustomersExport(Email) WHERE Email IS NOT NULL;
GO

CREATE NONCLUSTERED INDEX IX_source_csv_CustomersExport_Country 
    ON source_csv.CustomersExport(Country);
GO

-- Indexes on source_csv.VendorsExport
CREATE NONCLUSTERED INDEX IX_source_csv_VendorsExport_VendorName 
    ON source_csv.VendorsExport(VendorName);
GO

CREATE NONCLUSTERED INDEX IX_source_csv_VendorsExport_Email 
    ON source_csv.VendorsExport(Email) WHERE Email IS NOT NULL;
GO

CREATE NONCLUSTERED INDEX IX_source_csv_VendorsExport_Country 
    ON source_csv.VendorsExport(Country);
GO

PRINT 'Snapshot tables created successfully.';
PRINT 'Next step: Run 100_etl_refresh_snapshots.sql to populate these tables.';
GO
