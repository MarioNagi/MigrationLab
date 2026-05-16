USE MigrationLab;
GO

/*
File
----
sql/02_etl_procs/150_etl_snapshot_target.sql

Purpose
-------
ETL procedure to create point-in-time snapshots of target tables.
These snapshots support audit trails and historical tracking.

Design principles
-----------------
- Full refresh (DROP + CREATE) for snapshot tables
- Mirror target table structures exactly
- Add snapshot metadata (timestamp, batch ID)
- Preserve all target data for historical reference

Snapshot tables
--------------
- target_snapshot_sap_ecc.CustomerMaster: Snapshot of target_sap_ecc.CustomerMaster
- target_snapshot_sap_ecc.VendorMaster: Snapshot of target_sap_ecc.VendorMaster

Assumptions
-----------
- Schema 'target_snapshot_sap_ecc' already exists (created by 010_create_schemas.sql)
- Target tables exist and are populated (060 + 140)
*/

SET NOCOUNT ON;

-- Safety check
IF DB_NAME() <> 'MigrationLab'
BEGIN
    THROW 50000, 'This script must be executed in the MigrationLab database context.', 1;
END;

-- Verify prerequisites
IF OBJECT_ID('target_sap_ecc.CustomerMaster','U') IS NULL
    THROW 50001, 'Missing target_sap_ecc.CustomerMaster. Run 060 + 140 first.', 1;

IF OBJECT_ID('target_sap_ecc.VendorMaster','U') IS NULL
    THROW 50002, 'Missing target_sap_ecc.VendorMaster. Run 060 + 140 first.', 1;

DECLARE @snapshot_timestamp DATETIME2(7) = SYSDATETIME();
DECLARE @rows_affected INT;

PRINT '=== Creating target snapshots ===';
PRINT CONCAT('Snapshot timestamp: ', CONVERT(varchar(23), @snapshot_timestamp, 121));
PRINT '';

BEGIN TRY
    BEGIN TRANSACTION;

    /* =============================================================================
       Step 1: Create snapshot of CustomerMaster
       ============================================================================= */
    PRINT 'Step 1: Creating CustomerMaster snapshot...';
    
    -- Drop existing snapshot table
    IF OBJECT_ID('target_snapshot_sap_ecc.CustomerMaster','U') IS NOT NULL 
        DROP TABLE target_snapshot_sap_ecc.CustomerMaster;
    
    -- Create snapshot table with same structure + metadata
    SELECT 
        CustomerNumber,
        Name1, Name2, Name3, Name4,
        Street, StreetNumber, City, Region, PostalCode, Country,
        ContactPerson, ContactTitle,
        Telephone, TelephoneExtension, Mobile, Fax, Email,
        AccountGroup, CustomerType,
        Status, DeletionFlag,
        CreatedBy, CreatedDate, CreatedTime,
        LastChangedBy, LastChangedDate, LastChangedTime,
        MigrationSource, MigrationTimestamp, MigrationBatchID,
        -- Snapshot metadata
        @snapshot_timestamp AS SnapshotTimestamp,
        'SNAPSHOT' AS SnapshotType
    INTO target_snapshot_sap_ecc.CustomerMaster
    FROM target_sap_ecc.CustomerMaster;
    
    -- Add primary key
    ALTER TABLE target_snapshot_sap_ecc.CustomerMaster
    ADD CONSTRAINT PK_target_snapshot_sap_ecc_CustomerMaster 
        PRIMARY KEY CLUSTERED (CustomerNumber, SnapshotTimestamp);
    
    SET @rows_affected = @@ROWCOUNT;
    PRINT CONCAT('  Snapshot created with ', @rows_affected, ' customer records.');
    PRINT '';

    /* =============================================================================
       Step 2: Create snapshot of VendorMaster
       ============================================================================= */
    PRINT 'Step 2: Creating VendorMaster snapshot...';
    
    -- Drop existing snapshot table
    IF OBJECT_ID('target_snapshot_sap_ecc.VendorMaster','U') IS NOT NULL 
        DROP TABLE target_snapshot_sap_ecc.VendorMaster;
    
    -- Create snapshot table with same structure + metadata
    SELECT 
        VendorNumber,
        Name1, Name2, Name3, Name4,
        Street, StreetNumber, City, Region, PostalCode, Country,
        ContactPerson, ContactTitle,
        Telephone, TelephoneExtension, Mobile, Fax, Email, Website,
        AccountGroup, VendorType,
        Status, DeletionFlag,
        CreatedBy, CreatedDate, CreatedTime,
        LastChangedBy, LastChangedDate, LastChangedTime,
        MigrationSource, MigrationTimestamp, MigrationBatchID,
        -- Snapshot metadata
        @snapshot_timestamp AS SnapshotTimestamp,
        'SNAPSHOT' AS SnapshotType
    INTO target_snapshot_sap_ecc.VendorMaster
    FROM target_sap_ecc.VendorMaster;
    
    -- Add primary key
    ALTER TABLE target_snapshot_sap_ecc.VendorMaster
    ADD CONSTRAINT PK_target_snapshot_sap_ecc_VendorMaster 
        PRIMARY KEY CLUSTERED (VendorNumber, SnapshotTimestamp);
    
    SET @rows_affected = @@ROWCOUNT;
    PRINT CONCAT('  Snapshot created with ', @rows_affected, ' vendor records.');
    PRINT '';

    /* =============================================================================
       Summary
       ============================================================================= */
    PRINT '=== Summary ===';
    SELECT 
        'target_snapshot_sap_ecc.CustomerMaster' AS TableName,
        COUNT(*) AS RecordCount,
        MIN(SnapshotTimestamp) AS SnapshotTime
    FROM target_snapshot_sap_ecc.CustomerMaster
    UNION ALL
    SELECT 
        'target_snapshot_sap_ecc.VendorMaster' AS TableName,
        COUNT(*) AS RecordCount,
        MIN(SnapshotTimestamp) AS SnapshotTime
    FROM target_snapshot_sap_ecc.VendorMaster;

    COMMIT TRANSACTION;
    PRINT '';
    PRINT '=== Target snapshot completed successfully ===';

END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;
    
    PRINT '';
    PRINT '=== Target snapshot failed ===';
    PRINT CONCAT('Error Number: ', ERROR_NUMBER());
    PRINT CONCAT('Error Message: ', ERROR_MESSAGE());
    PRINT CONCAT('Error Line: ', ERROR_LINE());
    
    THROW;
END CATCH;
GO
