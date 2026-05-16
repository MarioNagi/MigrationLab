USE MigrationLab;
GO

/*
File
----
sql/02_etl_procs/100_etl_refresh_snapshots.sql

Purpose
-------
ETL procedure to refresh snapshot tables from source systems.
This is the first step in the migration pipeline - capturing point-in-time copies
of source data before any transformation or deduplication.

Design principles
----------------
- Full refresh (TRUNCATE + INSERT) - simple, repeatable, no incremental complexity
- No data transformation at snapshot stage (raw copy)
- Preserves all source data exactly as-is
- Updates snapshot_timestamp to reflect refresh time
- Idempotent (safe to run multiple times)

Source systems
--------------
- Northwind database: Customers, Suppliers
- CsvRaw database: CustomersExport, VendorsExport

Target tables
-------------
- source_northwind.Customers
- source_northwind.Suppliers
- source_csv.CustomersExport
- source_csv.VendorsExport

Assumptions
-----------
- Snapshot tables exist (created by 020_create_snapshot_tables.sql)
- Source databases (Northwind, CsvRaw) exist and are accessible
- Cross-database queries are enabled
*/

SET NOCOUNT ON;

-- Safety check
IF DB_NAME() <> 'MigrationLab'
BEGIN
    THROW 50000, 'This script must be executed in the MigrationLab database context.', 1;
END;

-- Verify snapshot tables exist
IF OBJECT_ID('source_northwind.Customers','U') IS NULL
    THROW 50001, 'Missing source_northwind.Customers. Run 020_create_snapshot_tables.sql first.', 1;

IF OBJECT_ID('source_northwind.Suppliers','U') IS NULL
    THROW 50002, 'Missing source_northwind.Suppliers. Run 020_create_snapshot_tables.sql first.', 1;

IF OBJECT_ID('source_csv.CustomersExport','U') IS NULL
    THROW 50003, 'Missing source_csv.CustomersExport. Run 020_create_snapshot_tables.sql first.', 1;

IF OBJECT_ID('source_csv.VendorsExport','U') IS NULL
    THROW 50004, 'Missing source_csv.VendorsExport. Run 020_create_snapshot_tables.sql first.', 1;

-- Verify source databases exist
IF DB_ID('Northwind') IS NULL
    THROW 50005, 'Source database Northwind does not exist.', 1;

IF DB_ID('CsvRaw') IS NULL
    THROW 50006, 'Source database CsvRaw does not exist.', 1;

DECLARE @snapshot_time DATETIME2(7) = SYSDATETIME();
DECLARE @rows_affected INT;
DECLARE @error_count INT = 0;

PRINT '=== Snapshot Refresh Started ===';
PRINT CONCAT('Snapshot timestamp: ', CONVERT(varchar(23), @snapshot_time, 121));
PRINT '';

BEGIN TRY
    BEGIN TRANSACTION;

    /* =============================================================================
       Refresh source_northwind.Customers from Northwind.dbo.Customers
       ============================================================================= */
    PRINT 'Refreshing source_northwind.Customers...';
    
    TRUNCATE TABLE source_northwind.Customers;
    
    INSERT INTO source_northwind.Customers (
        CustomerID, CompanyName, ContactName, ContactTitle,
        Address, City, Region, PostalCode, Country, Phone, Fax,
        snapshot_timestamp, source_system
    )
    SELECT 
        CustomerID, CompanyName, ContactName, ContactTitle,
        Address, City, Region, PostalCode, Country, Phone, Fax,
        @snapshot_time, 'Northwind'
    FROM Northwind.dbo.Customers;
    
    SET @rows_affected = @@ROWCOUNT;
    PRINT CONCAT('  Loaded ', @rows_affected, ' customer records from Northwind.');
    
    IF @rows_affected = 0
    BEGIN
        PRINT '  WARNING: No rows loaded from Northwind.dbo.Customers.';
        SET @error_count = @error_count + 1;
    END;

    /* =============================================================================
       Refresh source_northwind.Suppliers from Northwind.dbo.Suppliers
       ============================================================================= */
    PRINT 'Refreshing source_northwind.Suppliers...';
    
    TRUNCATE TABLE source_northwind.Suppliers;
    
    INSERT INTO source_northwind.Suppliers (
        SupplierID, CompanyName, ContactName, ContactTitle,
        Address, City, Region, PostalCode, Country, Phone, Fax, HomePage,
        snapshot_timestamp, source_system
    )
    SELECT 
        SupplierID, CompanyName, ContactName, ContactTitle,
        Address, City, Region, PostalCode, Country, Phone, Fax, HomePage,
        @snapshot_time, 'Northwind'
    FROM Northwind.dbo.Suppliers;
    
    SET @rows_affected = @@ROWCOUNT;
    PRINT CONCAT('  Loaded ', @rows_affected, ' supplier records from Northwind.');
    
    IF @rows_affected = 0
    BEGIN
        PRINT '  WARNING: No rows loaded from Northwind.dbo.Suppliers.';
        SET @error_count = @error_count + 1;
    END;

    /* =============================================================================
       Refresh source_csv.CustomersExport from CsvRaw.dbo.CustomersExport
       ============================================================================= */
    PRINT 'Refreshing source_csv.CustomersExport...';
    
    TRUNCATE TABLE source_csv.CustomersExport;
    
    INSERT INTO source_csv.CustomersExport (
        LegacyCustomerNo, Company, ContactFirstName, ContactMiddleName, ContactLastName,
        City, Country, PostalCode, Street, Phone, Email,
        snapshot_timestamp, source_system
    )
    SELECT 
        LegacyCustomerNo, Company, ContactFirstName, ContactMiddleName, ContactLastName,
        City, Country, PostalCode, Street, Phone, Email,
        @snapshot_time, 'CsvRaw'
    FROM CsvRaw.dbo.CustomersExport;
    
    SET @rows_affected = @@ROWCOUNT;
    PRINT CONCAT('  Loaded ', @rows_affected, ' customer records from CsvRaw.');
    
    IF @rows_affected = 0
    BEGIN
        PRINT '  WARNING: No rows loaded from CsvRaw.dbo.CustomersExport.';
        SET @error_count = @error_count + 1;
    END;

    /* =============================================================================
       Refresh source_csv.VendorsExport from CsvRaw.dbo.VendorsExport
       ============================================================================= */
    PRINT 'Refreshing source_csv.VendorsExport...';
    
    TRUNCATE TABLE source_csv.VendorsExport;
    
    INSERT INTO source_csv.VendorsExport (
        LegacyVendorNo, VendorName, ContactFirstName, ContactMiddleName, ContactLastName,
        City, Country, PostalCode, Street, Phone, Email,
        snapshot_timestamp, source_system
    )
    SELECT 
        LegacyVendorNo, VendorName, ContactFirstName, ContactMiddleName, ContactLastName,
        City, Country, PostalCode, Street, Phone, Email,
        @snapshot_time, 'CsvRaw'
    FROM CsvRaw.dbo.VendorsExport;
    
    SET @rows_affected = @@ROWCOUNT;
    PRINT CONCAT('  Loaded ', @rows_affected, ' vendor records from CsvRaw.');
    
    IF @rows_affected = 0
    BEGIN
        PRINT '  WARNING: No rows loaded from CsvRaw.dbo.VendorsExport.';
        SET @error_count = @error_count + 1;
    END;

    /* =============================================================================
       Validation summary
       ============================================================================= */
    PRINT '';
    PRINT '=== Snapshot Refresh Summary ===';
    
    SELECT 
        'source_northwind.Customers' AS TableName,
        COUNT(*) AS RowCount,
        MIN(snapshot_timestamp) AS SnapshotTime
    FROM source_northwind.Customers
    UNION ALL
    SELECT 
        'source_northwind.Suppliers' AS TableName,
        COUNT(*) AS RowCount,
        MIN(snapshot_timestamp) AS SnapshotTime
    FROM source_northwind.Suppliers
    UNION ALL
    SELECT 
        'source_csv.CustomersExport' AS TableName,
        COUNT(*) AS RowCount,
        MIN(snapshot_timestamp) AS SnapshotTime
    FROM source_csv.CustomersExport
    UNION ALL
    SELECT 
        'source_csv.VendorsExport' AS TableName,
        COUNT(*) AS RowCount,
        MIN(snapshot_timestamp) AS SnapshotTime
    FROM source_csv.VendorsExport
    ORDER BY TableName;

    IF @error_count > 0
    BEGIN
        PRINT '';
        PRINT CONCAT('WARNING: ', @error_count, ' table(s) had zero rows loaded.');
    END
    ELSE
    BEGIN
        PRINT '';
        PRINT 'All snapshots refreshed successfully.';
    END;

    COMMIT TRANSACTION;
    PRINT '';
    PRINT '=== Snapshot Refresh Completed ===';

END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;
    
    PRINT '';
    PRINT '=== Snapshot Refresh Failed ===';
    PRINT CONCAT('Error Number: ', ERROR_NUMBER());
    PRINT CONCAT('Error Message: ', ERROR_MESSAGE());
    PRINT CONCAT('Error Line: ', ERROR_LINE());
    
    THROW;
END CATCH;
GO
