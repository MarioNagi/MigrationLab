USE MigrationLab;
GO

/*
File
----
sql/02_etl_procs/130_etl_build_target_model.sql

Purpose
-------
ETL procedure to build target_model tables from work tables.
This procedure:
1. Selects survived records (one per match group)
2. Generates target IDs
3. Computes derived fields (ContactFullName, data quality scores)
4. Aggregates source system information
5. Loads clean, normalized target model tables

Design principles
-----------------
- Full refresh (TRUNCATE + INSERT)
- One record per entity (after deduplication)
- Generate sequential target IDs
- Calculate data quality scores
- Track source systems and merge counts

Assumptions
-----------
- Work tables exist and are populated (040 + 110/120)
- Target model tables exist (050)
*/

SET NOCOUNT ON;

-- Safety check
IF DB_NAME() <> 'MigrationLab'
BEGIN
    THROW 50000, 'This script must be executed in the MigrationLab database context.', 1;
END;

-- Verify prerequisites
IF OBJECT_ID('work_otc.CustomersSurvivorship','U') IS NULL
    THROW 50001, 'Missing work_otc.CustomersSurvivorship. Run 110 first.', 1;

IF OBJECT_ID('work_ptp.VendorsSurvivorship','U') IS NULL
    THROW 50002, 'Missing work_ptp.VendorsSurvivorship. Run 120 first.', 1;

IF OBJECT_ID('target_model.Customers','U') IS NULL
    THROW 50003, 'Missing target_model.Customers. Run 050 first.', 1;

DECLARE @rows_affected INT;
DECLARE @customer_id_counter INT = 1;
DECLARE @vendor_id_counter INT = 1;

PRINT '=== Building target_model ===';
PRINT CONCAT('Started: ', CONVERT(varchar(23), SYSDATETIME(), 121));
PRINT '';

BEGIN TRY
    BEGIN TRANSACTION;

    /* =============================================================================
       Step 1: Clear target model tables
       ============================================================================= */
    PRINT 'Step 1: Clearing target model tables...';
    
    TRUNCATE TABLE target_model.Customers;
    TRUNCATE TABLE target_model.Vendors;
    
    PRINT '  Target model tables cleared.';
    PRINT '';

    /* =============================================================================
       Step 2: Build target_model.Customers from work_otc
       ============================================================================= */
    PRINT 'Step 2: Building target_model.Customers...';
    
    ;WITH SurvivedCustomers AS (
        SELECT 
            s.WorkCustomerID,
            c.CompanyName,
            c.ContactFirstName,
            c.ContactMiddleName,
            c.ContactLastName,
            c.Street,
            c.City,
            c.Region,
            c.PostalCode,
            c.Country,
            c.CountryCode,
            c.Phone,
            c.PhoneNormalized,
            c.Email,
            c.EmailNormalized,
            c.HasEmail,
            c.HasPhone,
            c.HasFullName,
            c.HasAddress,
            -- Aggregate source systems
            STRING_AGG(DISTINCT c.SourceSystem, ',') WITHIN GROUP (ORDER BY c.SourceSystem) AS SourceSystems,
            COUNT(DISTINCT c.SourceSystem) AS SourceSystemCount,
            COUNT(*) AS SourceRecordCount
        FROM work_otc.CustomersSurvivorship s
        INNER JOIN work_otc.CustomersCanonical c ON s.WorkCustomerID = c.WorkCustomerID
        GROUP BY 
            s.WorkCustomerID,
            c.CompanyName,
            c.ContactFirstName,
            c.ContactMiddleName,
            c.ContactLastName,
            c.Street,
            c.City,
            c.Region,
            c.PostalCode,
            c.Country,
            c.CountryCode,
            c.Phone,
            c.PhoneNormalized,
            c.Email,
            c.EmailNormalized,
            c.HasEmail,
            c.HasPhone,
            c.HasFullName,
            c.HasAddress
    ),
    CustomersWithIDs AS (
        SELECT 
            'CUST' + RIGHT('000000' + CAST(ROW_NUMBER() OVER (ORDER BY WorkCustomerID) AS VARCHAR), 6) AS CustomerID,
            *
        FROM SurvivedCustomers
    )
    INSERT INTO target_model.Customers (
        CustomerID,
        CompanyName,
        CompanyNameLegal,
        ContactFirstName,
        ContactMiddleName,
        ContactLastName,
        ContactFullName,
        ContactTitle,
        Street,
        City,
        Region,
        PostalCode,
        Country,
        CountryCode,
        Phone,
        PhoneNormalized,
        Fax,
        Email,
        EmailNormalized,
        DataQualityScore,
        HasCompleteAddress,
        HasValidEmail,
        HasValidPhone,
        HasContactName,
        SourceSystems,
        SourceRecordCount
    )
    SELECT 
        CustomerID,
        CompanyName,
        NULL AS CompanyNameLegal,  -- Not available in source
        ContactFirstName,
        ContactMiddleName,
        ContactLastName,
        -- Compute ContactFullName
        LTRIM(RTRIM(
            NULLIF(
                CONCAT(
                    NULLIF(ContactFirstName + ' ', ''),
                    NULLIF(ContactMiddleName + ' ', ''),
                    NULLIF(ContactLastName, '')
                ),
                ''
            )
        )) AS ContactFullName,
        NULL AS ContactTitle,  -- Not consistently available
        Street,
        City,
        Region,
        PostalCode,
        Country,
        CountryCode,
        Phone,
        PhoneNormalized,
        NULL AS Fax,  -- Not consistently available
        Email,
        EmailNormalized,
        -- Calculate data quality score (0-100)
        (
            CASE WHEN CompanyName IS NOT NULL THEN 20 ELSE 0 END +
            CASE WHEN HasEmail = 1 THEN 25 ELSE 0 END +
            CASE WHEN HasPhone = 1 THEN 25 ELSE 0 END +
            CASE WHEN HasAddress = 1 THEN 20 ELSE 0 END +
            CASE WHEN HasFullName = 1 THEN 10 ELSE 0 END
        ) AS DataQualityScore,
        HasAddress AS HasCompleteAddress,
        HasEmail AS HasValidEmail,
        HasPhone AS HasValidPhone,
        HasFullName AS HasContactName,
        SourceSystems,
        SourceRecordCount
    FROM CustomersWithIDs;
    
    SET @rows_affected = @@ROWCOUNT;
    PRINT CONCAT('  Loaded ', @rows_affected, ' customer records into target_model.');
    PRINT '';

    /* =============================================================================
       Step 3: Build target_model.Vendors from work_ptp
       ============================================================================= */
    PRINT 'Step 3: Building target_model.Vendors...';
    
    ;WITH SurvivedVendors AS (
        SELECT 
            s.WorkVendorID,
            v.VendorName,
            v.ContactFirstName,
            v.ContactMiddleName,
            v.ContactLastName,
            v.Street,
            v.City,
            v.Region,
            v.PostalCode,
            v.Country,
            v.CountryCode,
            v.Phone,
            v.PhoneNormalized,
            v.Email,
            v.EmailNormalized,
            v.HasEmail,
            v.HasPhone,
            v.HasFullName,
            v.HasAddress,
            -- Aggregate source systems
            STRING_AGG(DISTINCT v.SourceSystem, ',') WITHIN GROUP (ORDER BY v.SourceSystem) AS SourceSystems,
            COUNT(DISTINCT v.SourceSystem) AS SourceSystemCount,
            COUNT(*) AS SourceRecordCount
        FROM work_ptp.VendorsSurvivorship s
        INNER JOIN work_ptp.VendorsCanonical v ON s.WorkVendorID = v.WorkVendorID
        GROUP BY 
            s.WorkVendorID,
            v.VendorName,
            v.ContactFirstName,
            v.ContactMiddleName,
            v.ContactLastName,
            v.Street,
            v.City,
            v.Region,
            v.PostalCode,
            v.Country,
            v.CountryCode,
            v.Phone,
            v.PhoneNormalized,
            v.Email,
            v.EmailNormalized,
            v.HasEmail,
            v.HasPhone,
            v.HasFullName,
            v.HasAddress
    ),
    VendorsWithIDs AS (
        SELECT 
            'VEND' + RIGHT('000000' + CAST(ROW_NUMBER() OVER (ORDER BY WorkVendorID) AS VARCHAR), 6) AS VendorID,
            *
        FROM SurvivedVendors
    )
    INSERT INTO target_model.Vendors (
        VendorID,
        VendorName,
        VendorNameLegal,
        ContactFirstName,
        ContactMiddleName,
        ContactLastName,
        ContactFullName,
        ContactTitle,
        Street,
        City,
        Region,
        PostalCode,
        Country,
        CountryCode,
        Phone,
        PhoneNormalized,
        Fax,
        Email,
        EmailNormalized,
        HomePage,
        DataQualityScore,
        HasCompleteAddress,
        HasValidEmail,
        HasValidPhone,
        HasContactName,
        SourceSystems,
        SourceRecordCount
    )
    SELECT 
        VendorID,
        VendorName,
        NULL AS VendorNameLegal,  -- Not available in source
        ContactFirstName,
        ContactMiddleName,
        ContactLastName,
        -- Compute ContactFullName
        LTRIM(RTRIM(
            NULLIF(
                CONCAT(
                    NULLIF(ContactFirstName + ' ', ''),
                    NULLIF(ContactMiddleName + ' ', ''),
                    NULLIF(ContactLastName, '')
                ),
                ''
            )
        )) AS ContactFullName,
        NULL AS ContactTitle,  -- Not consistently available
        Street,
        City,
        Region,
        PostalCode,
        Country,
        CountryCode,
        Phone,
        PhoneNormalized,
        NULL AS Fax,  -- Not consistently available
        Email,
        EmailNormalized,
        NULL AS HomePage,  -- Not consistently available
        -- Calculate data quality score (0-100)
        (
            CASE WHEN VendorName IS NOT NULL THEN 20 ELSE 0 END +
            CASE WHEN HasEmail = 1 THEN 25 ELSE 0 END +
            CASE WHEN HasPhone = 1 THEN 25 ELSE 0 END +
            CASE WHEN HasAddress = 1 THEN 20 ELSE 0 END +
            CASE WHEN HasFullName = 1 THEN 10 ELSE 0 END
        ) AS DataQualityScore,
        HasAddress AS HasCompleteAddress,
        HasEmail AS HasValidEmail,
        HasPhone AS HasValidPhone,
        HasFullName AS HasContactName,
        SourceSystems,
        SourceRecordCount
    FROM VendorsWithIDs;
    
    SET @rows_affected = @@ROWCOUNT;
    PRINT CONCAT('  Loaded ', @rows_affected, ' vendor records into target_model.');
    PRINT '';

    /* =============================================================================
       Step 4: Update crosswalk tables with target IDs
       ============================================================================= */
    PRINT 'Step 4: Updating crosswalk tables with target IDs...';
    
    -- Update customer crosswalk
    UPDATE cw
    SET cw.TargetCustomerID = tm.CustomerID
    FROM work_otc.CustomersCrosswalk cw
    INNER JOIN work_otc.CustomersSurvivorship s ON cw.WorkCustomerID = s.WorkCustomerID
    INNER JOIN target_model.Customers tm ON s.WorkCustomerID = 
        (SELECT TOP 1 WorkCustomerID 
         FROM work_otc.CustomersCanonical 
         WHERE CompanyName = tm.CompanyName 
           AND (EmailNormalized = tm.EmailNormalized OR (EmailNormalized IS NULL AND tm.EmailNormalized IS NULL))
         ORDER BY WorkCustomerID);
    
    -- Simpler approach: match by WorkCustomerID through survivorship
    UPDATE cw
    SET cw.TargetCustomerID = tm.CustomerID
    FROM work_otc.CustomersCrosswalk cw
    INNER JOIN work_otc.CustomersSurvivorship s ON cw.WorkCustomerID = s.WorkCustomerID
    INNER JOIN work_otc.CustomersCanonical cc ON s.WorkCustomerID = cc.WorkCustomerID
    INNER JOIN target_model.Customers tm 
        ON cc.CompanyName = tm.CompanyName
        AND (cc.EmailNormalized = tm.EmailNormalized OR (cc.EmailNormalized IS NULL AND tm.EmailNormalized IS NULL))
        AND (cc.PhoneNormalized = tm.PhoneNormalized OR (cc.PhoneNormalized IS NULL AND tm.PhoneNormalized IS NULL));
    
    SET @rows_affected = @@ROWCOUNT;
    PRINT CONCAT('  Updated ', @rows_affected, ' customer crosswalk records.');
    
    -- Update vendor crosswalk
    UPDATE cw
    SET cw.TargetVendorID = tm.VendorID
    FROM work_ptp.VendorsCrosswalk cw
    INNER JOIN work_ptp.VendorsSurvivorship s ON cw.WorkVendorID = s.WorkVendorID
    INNER JOIN work_ptp.VendorsCanonical vc ON s.WorkVendorID = vc.WorkVendorID
    INNER JOIN target_model.Vendors tm 
        ON vc.VendorName = tm.VendorName
        AND (vc.EmailNormalized = tm.EmailNormalized OR (vc.EmailNormalized IS NULL AND tm.EmailNormalized IS NULL))
        AND (vc.PhoneNormalized = tm.PhoneNormalized OR (vc.PhoneNormalized IS NULL AND tm.PhoneNormalized IS NULL));
    
    SET @rows_affected = @@ROWCOUNT;
    PRINT CONCAT('  Updated ', @rows_affected, ' vendor crosswalk records.');
    PRINT '';

    /* =============================================================================
       Summary
       ============================================================================= */
    PRINT '=== Summary ===';
    SELECT 
        'target_model.Customers' AS TableName,
        COUNT(*) AS RecordCount,
        AVG(CAST(DataQualityScore AS FLOAT)) AS AvgDataQualityScore,
        SUM(CASE WHEN SourceRecordCount > 1 THEN 1 ELSE 0 END) AS MergedRecords
    FROM target_model.Customers
    UNION ALL
    SELECT 
        'target_model.Vendors' AS TableName,
        COUNT(*) AS RecordCount,
        AVG(CAST(DataQualityScore AS FLOAT)) AS AvgDataQualityScore,
        SUM(CASE WHEN SourceRecordCount > 1 THEN 1 ELSE 0 END) AS MergedRecords
    FROM target_model.Vendors;

    COMMIT TRANSACTION;
    PRINT '';
    PRINT '=== target_model build completed successfully ===';

END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;
    
    PRINT '';
    PRINT '=== target_model build failed ===';
    PRINT CONCAT('Error Number: ', ERROR_NUMBER());
    PRINT CONCAT('Error Message: ', ERROR_MESSAGE());
    PRINT CONCAT('Error Line: ', ERROR_LINE());
    
    THROW;
END CATCH;
GO
