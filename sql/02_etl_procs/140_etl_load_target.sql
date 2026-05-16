USE MigrationLab;
GO

/*
File
----
sql/02_etl_procs/140_etl_load_target.sql

Purpose
-------
ETL procedure to load final target tables (SAP ECC-like format) from target_model.
This procedure:
1. Transforms target_model structure to target_sap_ecc format
2. Maps fields to target system structure (Name1, Name2, etc.)
3. Sets status and control fields
4. Populates audit fields
5. Loads CustomerMaster and VendorMaster tables

Design principles
-----------------
- Full refresh (TRUNCATE + INSERT)
- Transform normalized model to target system format
- Set appropriate status flags
- Populate audit and migration tracking fields

Assumptions
-----------
- Target model tables exist and are populated (050 + 130)
- Target tables exist (060)
*/

SET NOCOUNT ON;

-- Safety check
IF DB_NAME() <> 'MigrationLab'
BEGIN
    THROW 50000, 'This script must be executed in the MigrationLab database context.', 1;
END;

-- Verify prerequisites
IF OBJECT_ID('target_model.Customers','U') IS NULL
    THROW 50001, 'Missing target_model.Customers. Run 050 + 130 first.', 1;

IF OBJECT_ID('target_model.Vendors','U') IS NULL
    THROW 50002, 'Missing target_model.Vendors. Run 050 + 130 first.', 1;

IF OBJECT_ID('target_sap_ecc.CustomerMaster','U') IS NULL
    THROW 50003, 'Missing target_sap_ecc.CustomerMaster. Run 060 first.', 1;

DECLARE @rows_affected INT;
DECLARE @migration_timestamp DATETIME2(7) = SYSDATETIME();
DECLARE @migration_batch_id VARCHAR(50) = 'BATCH-' + FORMAT(@migration_timestamp, 'yyyyMMddHHmmss');

PRINT '=== Loading target tables ===';
PRINT CONCAT('Started: ', CONVERT(varchar(23), @migration_timestamp, 121));
PRINT CONCAT('Batch ID: ', @migration_batch_id);
PRINT '';

BEGIN TRY
    BEGIN TRANSACTION;

    /* =============================================================================
       Step 1: Clear target tables
       ============================================================================= */
    PRINT 'Step 1: Clearing target tables...';
    
    TRUNCATE TABLE target_sap_ecc.CustomerMaster;
    TRUNCATE TABLE target_sap_ecc.VendorMaster;
    
    PRINT '  Target tables cleared.';
    PRINT '';

    /* =============================================================================
       Step 2: Load target_sap_ecc.CustomerMaster from target_model.Customers
       ============================================================================= */
    PRINT 'Step 2: Loading CustomerMaster...';
    
    INSERT INTO target_sap_ecc.CustomerMaster (
        CustomerNumber,
        Name1, Name2, Name3, Name4,
        Street, StreetNumber, City, Region, PostalCode, Country,
        ContactPerson, ContactTitle,
        Telephone, TelephoneExtension, Mobile, Fax, Email,
        AccountGroup, CustomerType,
        Status, DeletionFlag,
        CreatedBy, CreatedDate, CreatedTime,
        LastChangedBy, LastChangedDate, LastChangedTime,
        MigrationSource, MigrationTimestamp, MigrationBatchID
    )
    SELECT 
        CustomerID AS CustomerNumber,
        
        -- Name fields (Name1 = primary company name)
        CompanyName AS Name1,
        NULL AS Name2,  -- Additional name line (not in source)
        NULL AS Name3,
        NULL AS Name4,
        
        -- Address
        Street,
        NULL AS StreetNumber,  -- Not separated in source
        City,
        Region,
        PostalCode,
        CountryCode AS Country,
        
        -- Contact person
        ContactFullName AS ContactPerson,
        NULL AS ContactTitle,  -- Not consistently available
        
        -- Communication
        Phone AS Telephone,
        NULL AS TelephoneExtension,
        NULL AS Mobile,
        NULL AS Fax,  -- target_model.Customers does not carry Fax (Northwind-only attribute)
        Email,

        -- Account group and type (defaults)
        '0001' AS AccountGroup,  -- Default account group
        '01' AS CustomerType,     -- Default customer type
        
        -- Status and control
        'A' AS Status,            -- Active
        ' ' AS DeletionFlag,      -- Not deleted
        
        -- Audit
        'MIGRATION' AS CreatedBy,
        CAST(@migration_timestamp AS DATE) AS CreatedDate,
        CAST(@migration_timestamp AS TIME) AS CreatedTime,
        'MIGRATION' AS LastChangedBy,
        CAST(@migration_timestamp AS DATE) AS LastChangedDate,
        CAST(@migration_timestamp AS TIME) AS LastChangedTime,
        
        -- Migration tracking
        SourceSystems AS MigrationSource,
        @migration_timestamp AS MigrationTimestamp,
        @migration_batch_id AS MigrationBatchID
        
    FROM target_model.Customers;
    
    SET @rows_affected = @@ROWCOUNT;
    PRINT CONCAT('  Loaded ', @rows_affected, ' customer records.');
    PRINT '';

    /* =============================================================================
       Step 3: Load target_sap_ecc.VendorMaster from target_model.Vendors
       ============================================================================= */
    PRINT 'Step 3: Loading VendorMaster...';
    
    INSERT INTO target_sap_ecc.VendorMaster (
        VendorNumber,
        Name1, Name2, Name3, Name4,
        Street, StreetNumber, City, Region, PostalCode, Country,
        ContactPerson, ContactTitle,
        Telephone, TelephoneExtension, Mobile, Fax, Email, Website,
        AccountGroup, VendorType,
        Status, DeletionFlag,
        CreatedBy, CreatedDate, CreatedTime,
        LastChangedBy, LastChangedDate, LastChangedTime,
        MigrationSource, MigrationTimestamp, MigrationBatchID
    )
    SELECT 
        VendorID AS VendorNumber,
        
        -- Name fields (Name1 = primary vendor name)
        VendorName AS Name1,
        NULL AS Name2,  -- Additional name line (not in source)
        NULL AS Name3,
        NULL AS Name4,
        
        -- Address
        Street,
        NULL AS StreetNumber,  -- Not separated in source
        City,
        Region,
        PostalCode,
        CountryCode AS Country,
        
        -- Contact person
        ContactFullName AS ContactPerson,
        NULL AS ContactTitle,  -- Not consistently available
        
        -- Communication
        Phone AS Telephone,
        NULL AS TelephoneExtension,
        NULL AS Mobile,
        Fax,
        Email,
        HomePage AS Website,
        
        -- Account group and type (defaults)
        '0001' AS AccountGroup,  -- Default account group
        '01' AS VendorType,      -- Default vendor type
        
        -- Status and control
        'A' AS Status,           -- Active
        ' ' AS DeletionFlag,     -- Not deleted
        
        -- Audit
        'MIGRATION' AS CreatedBy,
        CAST(@migration_timestamp AS DATE) AS CreatedDate,
        CAST(@migration_timestamp AS TIME) AS CreatedTime,
        'MIGRATION' AS LastChangedBy,
        CAST(@migration_timestamp AS DATE) AS LastChangedDate,
        CAST(@migration_timestamp AS TIME) AS LastChangedTime,
        
        -- Migration tracking
        SourceSystems AS MigrationSource,
        @migration_timestamp AS MigrationTimestamp,
        @migration_batch_id AS MigrationBatchID
        
    FROM target_model.Vendors;
    
    SET @rows_affected = @@ROWCOUNT;
    PRINT CONCAT('  Loaded ', @rows_affected, ' vendor records.');
    PRINT '';

    /* =============================================================================
       Summary
       ============================================================================= */
    PRINT '=== Summary ===';
    SELECT 
        'target_sap_ecc.CustomerMaster' AS TableName,
        COUNT(*) AS RecordCount,
        SUM(CASE WHEN Status = 'A' THEN 1 ELSE 0 END) AS ActiveRecords,
        SUM(CASE WHEN MigrationSource LIKE '%Northwind%' THEN 1 ELSE 0 END) AS FromNorthwind,
        SUM(CASE WHEN MigrationSource LIKE '%CsvRaw%' THEN 1 ELSE 0 END) AS FromCsvRaw,
        SUM(CASE WHEN MigrationSource LIKE '%,%' THEN 1 ELSE 0 END) AS FromMultipleSources
    FROM target_sap_ecc.CustomerMaster
    UNION ALL
    SELECT 
        'target_sap_ecc.VendorMaster' AS TableName,
        COUNT(*) AS RecordCount,
        SUM(CASE WHEN Status = 'A' THEN 1 ELSE 0 END) AS ActiveRecords,
        SUM(CASE WHEN MigrationSource LIKE '%Northwind%' THEN 1 ELSE 0 END) AS FromNorthwind,
        SUM(CASE WHEN MigrationSource LIKE '%CsvRaw%' THEN 1 ELSE 0 END) AS FromCsvRaw,
        SUM(CASE WHEN MigrationSource LIKE '%,%' THEN 1 ELSE 0 END) AS FromMultipleSources
    FROM target_sap_ecc.VendorMaster;

    COMMIT TRANSACTION;
    PRINT '';
    PRINT '=== Target load completed successfully ===';
    PRINT CONCAT('Batch ID: ', @migration_batch_id);

END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;
    
    PRINT '';
    PRINT '=== Target load failed ===';
    PRINT CONCAT('Error Number: ', ERROR_NUMBER());
    PRINT CONCAT('Error Message: ', ERROR_MESSAGE());
    PRINT CONCAT('Error Line: ', ERROR_LINE());
    
    THROW;
END CATCH;
GO
