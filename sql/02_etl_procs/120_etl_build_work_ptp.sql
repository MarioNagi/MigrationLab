USE MigrationLab;
GO

/*
File
----
sql/02_etl_procs/120_etl_build_work_ptp.sql

Purpose
-------
ETL procedure to build work_ptp (Procure to Pay) tables from snapshots.
This procedure:
1. Loads canonical data from all sources (Northwind + CsvRaw)
2. Normalizes fields (country codes, phone, email, names)
3. Handles bidirectional transformation (split/merge contact names)
4. Generates match keys for deduplication
5. Creates match groups
6. Applies survivorship rules
7. Creates crosswalk mappings

Design principles
-----------------
- Full refresh (TRUNCATE + INSERT) for simplicity
- Bidirectional transformation: Northwind ContactName -> split, CSV names -> merge
- Match key generation based on reference.MatchRules
- Survivorship: prefer records with more complete data

Assumptions
-----------
- Snapshot tables exist and are populated (020 + 100)
- Reference tables exist (030)
- Work tables exist (040)
*/

SET NOCOUNT ON;

-- Safety check
IF DB_NAME() <> 'MigrationLab'
BEGIN
    THROW 50000, 'This script must be executed in the MigrationLab database context.', 1;
END;

-- Verify prerequisites
IF OBJECT_ID('source_northwind.Suppliers','U') IS NULL
    THROW 50001, 'Missing source_northwind.Suppliers. Run 020 + 100 first.', 1;

IF OBJECT_ID('source_csv.VendorsExport','U') IS NULL
    THROW 50002, 'Missing source_csv.VendorsExport. Run 020 + 100 first.', 1;

IF OBJECT_ID('reference.CountryCodes','U') IS NULL
    THROW 50003, 'Missing reference.CountryCodes. Run 030 first.', 1;

IF OBJECT_ID('work_ptp.VendorsCanonical','U') IS NULL
    THROW 50004, 'Missing work_ptp.VendorsCanonical. Run 040 first.', 1;

DECLARE @rows_affected INT;
DECLARE @error_count INT = 0;

PRINT '=== Building work_ptp (Vendors) ===';
PRINT CONCAT('Started: ', CONVERT(varchar(23), SYSDATETIME(), 121));
PRINT '';

BEGIN TRY
    BEGIN TRANSACTION;

    /* =============================================================================
       Step 1: Clear work tables
       ============================================================================= */
    PRINT 'Step 1: Clearing work tables...';
    
    TRUNCATE TABLE work_ptp.VendorsCrosswalk;
    TRUNCATE TABLE work_ptp.VendorsSurvivorship;
    TRUNCATE TABLE work_ptp.VendorsMatchGroupMembers;
    TRUNCATE TABLE work_ptp.VendorsMatchGroups;
    TRUNCATE TABLE work_ptp.VendorsMatchKeys;
    TRUNCATE TABLE work_ptp.VendorsCanonical;
    
    PRINT '  Work tables cleared.';
    PRINT '';

    /* =============================================================================
       Step 2: Load canonical data from Northwind (split ContactName)
       ============================================================================= */
    PRINT 'Step 2: Loading Northwind suppliers (splitting ContactName)...';
    
    INSERT INTO work_ptp.VendorsCanonical (
        SourceSystem, SourceID,
        VendorName, VendorNameNormalized,
        ContactNameFull, ContactFirstName, ContactMiddleName, ContactLastName,
        Street, City, CityNormalized, Region, PostalCode, Country, CountryCode,
        Phone, PhoneNormalized, Email, EmailNormalized,
        HasEmail, HasPhone, HasFullName, HasAddress
    )
    SELECT 
        'Northwind' AS SourceSystem,
        CAST(s.SupplierID AS VARCHAR(50)) AS SourceID,
        
        -- Vendor name
        s.CompanyName AS VendorName,
        UPPER(LTRIM(RTRIM(REPLACE(REPLACE(s.CompanyName, ' ', ''), '-', '')))) AS VendorNameNormalized,
        
        -- Contact name: split ContactName into first/middle/last
        s.ContactName AS ContactNameFull,
        CASE 
            WHEN s.ContactName IS NULL THEN NULL
            ELSE NULLIF(LTRIM(RTRIM(SUBSTRING(s.ContactName, 1, CHARINDEX(' ', s.ContactName + ' ') - 1))), '')
        END AS ContactFirstName,
        CASE 
            WHEN s.ContactName IS NULL OR CHARINDEX(' ', s.ContactName) = 0 THEN NULL
            WHEN LEN(s.ContactName) - LEN(REPLACE(s.ContactName, ' ', '')) >= 2 THEN
                NULLIF(LTRIM(RTRIM(SUBSTRING(
                    s.ContactName, 
                    CHARINDEX(' ', s.ContactName) + 1,
                    LEN(s.ContactName) - CHARINDEX(' ', REVERSE(s.ContactName)) - CHARINDEX(' ', s.ContactName)
                ))), '')
            ELSE NULL
        END AS ContactMiddleName,
        CASE 
            WHEN s.ContactName IS NULL OR CHARINDEX(' ', s.ContactName) = 0 THEN NULL
            ELSE NULLIF(LTRIM(RTRIM(REVERSE(SUBSTRING(REVERSE(s.ContactName), 1, CHARINDEX(' ', REVERSE(s.ContactName)) - 1)))), '')
        END AS ContactLastName,
        
        -- Address
        s.Address AS Street,
        s.City,
        UPPER(LTRIM(RTRIM(REPLACE(s.City, ' ', '')))) AS CityNormalized,
        s.Region,
        s.PostalCode,
        s.Country,
        COALESCE(cc.CountryCode, 'XX') AS CountryCode,
        
        -- Phone (normalize: digits only)
        s.Phone,
        CASE 
            WHEN s.Phone IS NULL THEN NULL
            ELSE REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                s.Phone, ' ', ''), '-', ''), '(', ''), ')', ''), '.', ''), '+', ''), 'x', ''), 'X', ''), 'ext', ''), 'EXT', '')
        END AS PhoneNormalized,
        
        -- Email (not in Northwind, so NULL)
        NULL AS Email,
        NULL AS EmailNormalized,
        
        -- Data quality flags
        0 AS HasEmail,
        CASE WHEN s.Phone IS NOT NULL THEN 1 ELSE 0 END AS HasPhone,
        CASE WHEN s.ContactName IS NOT NULL THEN 1 ELSE 0 END AS HasFullName,
        CASE WHEN s.Address IS NOT NULL AND s.City IS NOT NULL AND s.Country IS NOT NULL THEN 1 ELSE 0 END AS HasAddress
        
    FROM source_northwind.Suppliers s
    LEFT JOIN reference.CountryCodes cc ON UPPER(LTRIM(RTRIM(s.Country))) = UPPER(LTRIM(RTRIM(cc.CountryNameVariant)))
        AND cc.IsPrimary = 1;
    
    SET @rows_affected = @@ROWCOUNT;
    PRINT CONCAT('  Loaded ', @rows_affected, ' records from Northwind.');
    PRINT '';

    /* =============================================================================
       Step 3: Load canonical data from CsvRaw (merge names into ContactNameFull)
       ============================================================================= */
    PRINT 'Step 3: Loading CsvRaw vendors (merging names)...';
    
    INSERT INTO work_ptp.VendorsCanonical (
        SourceSystem, SourceID,
        VendorName, VendorNameNormalized,
        ContactNameFull, ContactFirstName, ContactMiddleName, ContactLastName,
        Street, City, CityNormalized, Region, PostalCode, Country, CountryCode,
        Phone, PhoneNormalized, Email, EmailNormalized,
        HasEmail, HasPhone, HasFullName, HasAddress
    )
    SELECT 
        'CsvRaw' AS SourceSystem,
        v.LegacyVendorNo AS SourceID,
        
        -- Vendor name
        v.VendorName,
        UPPER(LTRIM(RTRIM(REPLACE(REPLACE(v.VendorName, ' ', ''), '-', '')))) AS VendorNameNormalized,
        
        -- Contact name: merge first/middle/last into full name
        LTRIM(RTRIM(
            NULLIF(
                CONCAT(
                    NULLIF(v.ContactFirstName + ' ', ''),
                    NULLIF(v.ContactMiddleName + ' ', ''),
                    NULLIF(v.ContactLastName, '')
                ),
                ''
            )
        )) AS ContactNameFull,
        v.ContactFirstName,
        v.ContactMiddleName,
        v.ContactLastName,
        
        -- Address
        v.Street,
        v.City,
        UPPER(LTRIM(RTRIM(REPLACE(v.City, ' ', '')))) AS CityNormalized,
        NULL AS Region,  -- Not in CSV structure
        v.PostalCode,
        v.Country,
        COALESCE(cc.CountryCode, 'XX') AS CountryCode,
        
        -- Phone (normalize: digits only)
        v.Phone,
        CASE 
            WHEN v.Phone IS NULL THEN NULL
            ELSE REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                v.Phone, ' ', ''), '-', ''), '(', ''), ')', ''), '.', ''), '+', ''), 'x', ''), 'X', ''), 'ext', ''), 'EXT', '')
        END AS PhoneNormalized,
        
        -- Email (normalize: lowercase, trimmed)
        v.Email,
        CASE 
            WHEN v.Email IS NULL THEN NULL
            ELSE LOWER(LTRIM(RTRIM(v.Email)))
        END AS EmailNormalized,
        
        -- Data quality flags
        CASE WHEN v.Email IS NOT NULL THEN 1 ELSE 0 END AS HasEmail,
        CASE WHEN v.Phone IS NOT NULL THEN 1 ELSE 0 END AS HasPhone,
        CASE WHEN v.ContactFirstName IS NOT NULL OR v.ContactLastName IS NOT NULL THEN 1 ELSE 0 END AS HasFullName,
        CASE WHEN v.Street IS NOT NULL AND v.City IS NOT NULL AND v.Country IS NOT NULL THEN 1 ELSE 0 END AS HasAddress
        
    FROM source_csv.VendorsExport v
    LEFT JOIN reference.CountryCodes cc ON UPPER(LTRIM(RTRIM(v.Country))) = UPPER(LTRIM(RTRIM(cc.CountryNameVariant)))
        AND cc.IsPrimary = 1;
    
    SET @rows_affected = @@ROWCOUNT;
    PRINT CONCAT('  Loaded ', @rows_affected, ' records from CsvRaw.');
    PRINT '';

    /* =============================================================================
       Step 4: Generate match keys
       ============================================================================= */
    PRINT 'Step 4: Generating match keys...';
    
    -- Email match keys
    INSERT INTO work_ptp.VendorsMatchKeys (WorkVendorID, MatchKeyType, MatchKeyValue)
    SELECT WorkVendorID, 'Email', EmailNormalized
    FROM work_ptp.VendorsCanonical
    WHERE EmailNormalized IS NOT NULL;
    
    SET @rows_affected = @@ROWCOUNT;
    PRINT CONCAT('  Generated ', @rows_affected, ' email match keys.');
    
    -- Phone match keys
    INSERT INTO work_ptp.VendorsMatchKeys (WorkVendorID, MatchKeyType, MatchKeyValue)
    SELECT WorkVendorID, 'Phone', PhoneNormalized
    FROM work_ptp.VendorsCanonical
    WHERE PhoneNormalized IS NOT NULL AND LEN(PhoneNormalized) >= 10;  -- Minimum phone length
    
    SET @rows_affected = @@ROWCOUNT;
    PRINT CONCAT('  Generated ', @rows_affected, ' phone match keys.');
    
    -- Name + City match keys
    INSERT INTO work_ptp.VendorsMatchKeys (WorkVendorID, MatchKeyType, MatchKeyValue)
    SELECT WorkVendorID, 'NameCity', 
        UPPER(LTRIM(RTRIM(CONCAT(
            COALESCE(ContactFirstName, ''), '|',
            COALESCE(ContactLastName, ''), '|',
            COALESCE(CityNormalized, '')
        ))))
    FROM work_ptp.VendorsCanonical
    WHERE (ContactFirstName IS NOT NULL OR ContactLastName IS NOT NULL)
        AND CityNormalized IS NOT NULL;
    
    SET @rows_affected = @@ROWCOUNT;
    PRINT CONCAT('  Generated ', @rows_affected, ' name+city match keys.');
    
    -- Vendor + City match keys
    INSERT INTO work_ptp.VendorsMatchKeys (WorkVendorID, MatchKeyType, MatchKeyValue)
    SELECT WorkVendorID, 'CompanyCity', 
        UPPER(LTRIM(RTRIM(CONCAT(
            COALESCE(VendorNameNormalized, ''), '|',
            COALESCE(CityNormalized, '')
        ))))
    FROM work_ptp.VendorsCanonical
    WHERE VendorNameNormalized IS NOT NULL
        AND CityNormalized IS NOT NULL;
    
    SET @rows_affected = @@ROWCOUNT;
    PRINT CONCAT('  Generated ', @rows_affected, ' vendor+city match keys.');
    PRINT '';

    /* =============================================================================
       Step 5: Create match groups
       ============================================================================= */
    PRINT 'Step 5: Creating match groups...';
    
    INSERT INTO work_ptp.VendorsMatchGroups (MatchKeyType, MatchKeyValue, GroupSize)
    SELECT MatchKeyType, MatchKeyValue, COUNT(*) AS GroupSize
    FROM work_ptp.VendorsMatchKeys
    GROUP BY MatchKeyType, MatchKeyValue
    HAVING COUNT(*) > 0;
    
    SET @rows_affected = @@ROWCOUNT;
    PRINT CONCAT('  Created ', @rows_affected, ' match groups.');
    PRINT '';

    /* =============================================================================
       Step 6: Link records to match groups
       ============================================================================= */
    PRINT 'Step 6: Linking records to match groups...';
    
    INSERT INTO work_ptp.VendorsMatchGroupMembers (MatchGroupID, WorkVendorID)
    SELECT mg.MatchGroupID, mk.WorkVendorID
    FROM work_ptp.VendorsMatchGroups mg
    INNER JOIN work_ptp.VendorsMatchKeys mk 
        ON mg.MatchKeyType = mk.MatchKeyType 
        AND mg.MatchKeyValue = mk.MatchKeyValue;
    
    SET @rows_affected = @@ROWCOUNT;
    PRINT CONCAT('  Linked ', @rows_affected, ' records to match groups.');
    PRINT '';

    /* =============================================================================
       Step 7: Apply survivorship rules (select best record per group)
       ============================================================================= */
    PRINT 'Step 7: Applying survivorship rules...';
    
    ;WITH RankedRecords AS (
        SELECT 
            mg.MatchGroupID,
            v.WorkVendorID,
            CASE 
                WHEN v.HasEmail = 1 AND v.HasPhone = 1 AND v.HasAddress = 1 THEN 'Complete data (email+phone+address)'
                WHEN v.HasEmail = 1 AND v.HasPhone = 1 THEN 'Email and phone present'
                WHEN v.HasEmail = 1 THEN 'Email present'
                WHEN v.HasPhone = 1 AND v.HasAddress = 1 THEN 'Phone and address present'
                WHEN v.HasPhone = 1 THEN 'Phone present'
                WHEN v.HasAddress = 1 THEN 'Address present'
                WHEN v.VendorName IS NOT NULL THEN 'Vendor name present'
                ELSE 'First record in group'
            END AS SurvivorshipReason,
            ROW_NUMBER() OVER (
                PARTITION BY mg.MatchGroupID 
                ORDER BY 
                    v.HasEmail DESC,
                    v.HasPhone DESC,
                    v.HasAddress DESC,
                    v.HasFullName DESC,
                    v.WorkVendorID ASC  -- Tie-breaker: first record
            ) AS RowNum
        FROM work_ptp.VendorsMatchGroups mg
        INNER JOIN work_ptp.VendorsMatchGroupMembers mgm ON mg.MatchGroupID = mgm.MatchGroupID
        INNER JOIN work_ptp.VendorsCanonical v ON mgm.WorkVendorID = v.WorkVendorID
    )
    INSERT INTO work_ptp.VendorsSurvivorship (MatchGroupID, WorkVendorID, SurvivorshipReason)
    SELECT MatchGroupID, WorkVendorID, SurvivorshipReason
    FROM RankedRecords
    WHERE RowNum = 1;
    
    SET @rows_affected = @@ROWCOUNT;
    PRINT CONCAT('  Selected ', @rows_affected, ' survived records.');
    PRINT '';

    /* =============================================================================
       Step 8: Create crosswalk (source ID -> work ID mapping)
       ============================================================================= */
    PRINT 'Step 8: Creating crosswalk...';
    
    INSERT INTO work_ptp.VendorsCrosswalk (SourceSystem, SourceID, WorkVendorID)
    SELECT v.SourceSystem, v.SourceID, 
        COALESCE(s.WorkVendorID, v.WorkVendorID) AS WorkVendorID
    FROM work_ptp.VendorsCanonical v
    LEFT JOIN work_ptp.VendorsMatchGroupMembers mgm ON v.WorkVendorID = mgm.WorkVendorID
    LEFT JOIN work_ptp.VendorsSurvivorship s ON mgm.MatchGroupID = s.MatchGroupID
    WHERE COALESCE(s.WorkVendorID, v.WorkVendorID) IS NOT NULL;
    
    SET @rows_affected = @@ROWCOUNT;
    PRINT CONCAT('  Created ', @rows_affected, ' crosswalk mappings.');
    PRINT '';

    /* =============================================================================
       Summary
       ============================================================================= */
    PRINT '=== Summary ===';
    SELECT 
        'Canonical Records' AS Metric,
        COUNT(*) AS Value
    FROM work_ptp.VendorsCanonical
    UNION ALL
    SELECT 
        'Match Groups' AS Metric,
        COUNT(*) AS Value
    FROM work_ptp.VendorsMatchGroups
    UNION ALL
    SELECT 
        'Duplicate Groups' AS Metric,
        COUNT(*) AS Value
    FROM work_ptp.VendorsMatchGroups
    WHERE GroupSize > 1
    UNION ALL
    SELECT 
        'Survived Records' AS Metric,
        COUNT(*) AS Value
    FROM work_ptp.VendorsSurvivorship
    UNION ALL
    SELECT 
        'Crosswalk Mappings' AS Metric,
        COUNT(*) AS Value
    FROM work_ptp.VendorsCrosswalk;

    COMMIT TRANSACTION;
    PRINT '';
    PRINT '=== work_ptp build completed successfully ===';

END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;
    
    PRINT '';
    PRINT '=== work_ptp build failed ===';
    PRINT CONCAT('Error Number: ', ERROR_NUMBER());
    PRINT CONCAT('Error Message: ', ERROR_MESSAGE());
    PRINT CONCAT('Error Line: ', ERROR_LINE());
    
    THROW;
END CATCH;
GO
