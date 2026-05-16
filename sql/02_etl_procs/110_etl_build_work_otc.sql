USE MigrationLab;
GO

/*
File
----
sql/02_etl_procs/110_etl_build_work_otc.sql

Purpose
-------
ETL procedure to build work_otc (Order to Cash) tables from snapshots.
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
IF OBJECT_ID('source_northwind.Customers','U') IS NULL
    THROW 50001, 'Missing source_northwind.Customers. Run 020 + 100 first.', 1;

IF OBJECT_ID('source_csv.CustomersExport','U') IS NULL
    THROW 50002, 'Missing source_csv.CustomersExport. Run 020 + 100 first.', 1;

IF OBJECT_ID('reference.CountryCodes','U') IS NULL
    THROW 50003, 'Missing reference.CountryCodes. Run 030 first.', 1;

IF OBJECT_ID('work_otc.CustomersCanonical','U') IS NULL
    THROW 50004, 'Missing work_otc.CustomersCanonical. Run 040 first.', 1;

DECLARE @rows_affected INT;
DECLARE @error_count INT = 0;

PRINT '=== Building work_otc (Customers) ===';
PRINT CONCAT('Started: ', CONVERT(varchar(23), SYSDATETIME(), 121));
PRINT '';

BEGIN TRY
    BEGIN TRANSACTION;

    /* =============================================================================
       Step 1: Clear work tables
       ============================================================================= */
    PRINT 'Step 1: Clearing work tables...';
    
    TRUNCATE TABLE work_otc.CustomersCrosswalk;
    TRUNCATE TABLE work_otc.CustomersSurvivorship;
    TRUNCATE TABLE work_otc.CustomersMatchGroupMembers;
    TRUNCATE TABLE work_otc.CustomersMatchGroups;
    TRUNCATE TABLE work_otc.CustomersMatchKeys;
    TRUNCATE TABLE work_otc.CustomersCanonical;
    
    PRINT '  Work tables cleared.';
    PRINT '';

    /* =============================================================================
       Step 2: Load canonical data from Northwind (split ContactName)
       ============================================================================= */
    PRINT 'Step 2: Loading Northwind customers (splitting ContactName)...';
    
    INSERT INTO work_otc.CustomersCanonical (
        SourceSystem, SourceID,
        CompanyName, CompanyNameNormalized,
        ContactNameFull, ContactFirstName, ContactMiddleName, ContactLastName,
        Street, City, CityNormalized, Region, PostalCode, Country, CountryCode,
        Phone, PhoneNormalized, Email, EmailNormalized,
        HasEmail, HasPhone, HasFullName, HasAddress
    )
    SELECT 
        'Northwind' AS SourceSystem,
        CAST(c.CustomerID AS VARCHAR(50)) AS SourceID,
        
        -- Company name
        c.CompanyName,
        UPPER(LTRIM(RTRIM(REPLACE(REPLACE(c.CompanyName, ' ', ''), '-', '')))) AS CompanyNameNormalized,
        
        -- Contact name: split ContactName into first/middle/last
        c.ContactName AS ContactNameFull,
        CASE 
            WHEN c.ContactName IS NULL THEN NULL
            ELSE NULLIF(LTRIM(RTRIM(SUBSTRING(c.ContactName, 1, CHARINDEX(' ', c.ContactName + ' ') - 1))), '')
        END AS ContactFirstName,
        CASE 
            WHEN c.ContactName IS NULL OR CHARINDEX(' ', c.ContactName) = 0 THEN NULL
            WHEN LEN(c.ContactName) - LEN(REPLACE(c.ContactName, ' ', '')) >= 2 THEN
                NULLIF(LTRIM(RTRIM(SUBSTRING(
                    c.ContactName, 
                    CHARINDEX(' ', c.ContactName) + 1,
                    LEN(c.ContactName) - CHARINDEX(' ', REVERSE(c.ContactName)) - CHARINDEX(' ', c.ContactName)
                ))), '')
            ELSE NULL
        END AS ContactMiddleName,
        CASE 
            WHEN c.ContactName IS NULL OR CHARINDEX(' ', c.ContactName) = 0 THEN NULL
            ELSE NULLIF(LTRIM(RTRIM(REVERSE(SUBSTRING(REVERSE(c.ContactName), 1, CHARINDEX(' ', REVERSE(c.ContactName)) - 1)))), '')
        END AS ContactLastName,
        
        -- Address
        c.Address AS Street,
        c.City,
        UPPER(LTRIM(RTRIM(REPLACE(c.City, ' ', '')))) AS CityNormalized,
        c.Region,
        c.PostalCode,
        c.Country,
        COALESCE(cc.CountryCode, 'XX') AS CountryCode,
        
        -- Phone (normalize: digits only)
        c.Phone,
        CASE 
            WHEN c.Phone IS NULL THEN NULL
            ELSE REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                c.Phone, ' ', ''), '-', ''), '(', ''), ')', ''), '.', ''), '+', ''), 'x', ''), 'X', ''), 'ext', ''), 'EXT', '')
        END AS PhoneNormalized,
        
        -- Email (not in Northwind, so NULL)
        NULL AS Email,
        NULL AS EmailNormalized,
        
        -- Data quality flags
        0 AS HasEmail,
        CASE WHEN c.Phone IS NOT NULL THEN 1 ELSE 0 END AS HasPhone,
        CASE WHEN c.ContactName IS NOT NULL THEN 1 ELSE 0 END AS HasFullName,
        CASE WHEN c.Address IS NOT NULL AND c.City IS NOT NULL AND c.Country IS NOT NULL THEN 1 ELSE 0 END AS HasAddress
        
    FROM source_northwind.Customers c
    LEFT JOIN reference.CountryCodes cc ON UPPER(LTRIM(RTRIM(c.Country))) = UPPER(LTRIM(RTRIM(cc.CountryNameVariant)))
        AND cc.IsPrimary = 1;
    
    SET @rows_affected = @@ROWCOUNT;
    PRINT CONCAT('  Loaded ', @rows_affected, ' records from Northwind.');
    PRINT '';

    /* =============================================================================
       Step 3: Load canonical data from CsvRaw (merge names into ContactNameFull)
       ============================================================================= */
    PRINT 'Step 3: Loading CsvRaw customers (merging names)...';
    
    INSERT INTO work_otc.CustomersCanonical (
        SourceSystem, SourceID,
        CompanyName, CompanyNameNormalized,
        ContactNameFull, ContactFirstName, ContactMiddleName, ContactLastName,
        Street, City, CityNormalized, Region, PostalCode, Country, CountryCode,
        Phone, PhoneNormalized, Email, EmailNormalized,
        HasEmail, HasPhone, HasFullName, HasAddress
    )
    SELECT 
        'CsvRaw' AS SourceSystem,
        c.LegacyCustomerNo AS SourceID,
        
        -- Company name
        c.Company,
        UPPER(LTRIM(RTRIM(REPLACE(REPLACE(c.Company, ' ', ''), '-', '')))) AS CompanyNameNormalized,
        
        -- Contact name: merge first/middle/last into full name
        LTRIM(RTRIM(
            NULLIF(
                CONCAT(
                    NULLIF(c.ContactFirstName + ' ', ''),
                    NULLIF(c.ContactMiddleName + ' ', ''),
                    NULLIF(c.ContactLastName, '')
                ),
                ''
            )
        )) AS ContactNameFull,
        c.ContactFirstName,
        c.ContactMiddleName,
        c.ContactLastName,
        
        -- Address
        c.Street,
        c.City,
        UPPER(LTRIM(RTRIM(REPLACE(c.City, ' ', '')))) AS CityNormalized,
        NULL AS Region,  -- Not in CSV structure
        c.PostalCode,
        c.Country,
        COALESCE(cc.CountryCode, 'XX') AS CountryCode,
        
        -- Phone (normalize: digits only)
        c.Phone,
        CASE 
            WHEN c.Phone IS NULL THEN NULL
            ELSE REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                c.Phone, ' ', ''), '-', ''), '(', ''), ')', ''), '.', ''), '+', ''), 'x', ''), 'X', ''), 'ext', ''), 'EXT', '')
        END AS PhoneNormalized,
        
        -- Email (normalize: lowercase, trimmed)
        c.Email,
        CASE 
            WHEN c.Email IS NULL THEN NULL
            ELSE LOWER(LTRIM(RTRIM(c.Email)))
        END AS EmailNormalized,
        
        -- Data quality flags
        CASE WHEN c.Email IS NOT NULL THEN 1 ELSE 0 END AS HasEmail,
        CASE WHEN c.Phone IS NOT NULL THEN 1 ELSE 0 END AS HasPhone,
        CASE WHEN c.ContactFirstName IS NOT NULL OR c.ContactLastName IS NOT NULL THEN 1 ELSE 0 END AS HasFullName,
        CASE WHEN c.Street IS NOT NULL AND c.City IS NOT NULL AND c.Country IS NOT NULL THEN 1 ELSE 0 END AS HasAddress
        
    FROM source_csv.CustomersExport c
    LEFT JOIN reference.CountryCodes cc ON UPPER(LTRIM(RTRIM(c.Country))) = UPPER(LTRIM(RTRIM(cc.CountryNameVariant)))
        AND cc.IsPrimary = 1;
    
    SET @rows_affected = @@ROWCOUNT;
    PRINT CONCAT('  Loaded ', @rows_affected, ' records from CsvRaw.');
    PRINT '';

    /* =============================================================================
       Step 4: Generate match keys
       ============================================================================= */
    PRINT 'Step 4: Generating match keys...';
    
    -- Email match keys
    INSERT INTO work_otc.CustomersMatchKeys (WorkCustomerID, MatchKeyType, MatchKeyValue)
    SELECT WorkCustomerID, 'Email', EmailNormalized
    FROM work_otc.CustomersCanonical
    WHERE EmailNormalized IS NOT NULL;
    
    SET @rows_affected = @@ROWCOUNT;
    PRINT CONCAT('  Generated ', @rows_affected, ' email match keys.');
    
    -- Phone match keys
    INSERT INTO work_otc.CustomersMatchKeys (WorkCustomerID, MatchKeyType, MatchKeyValue)
    SELECT WorkCustomerID, 'Phone', PhoneNormalized
    FROM work_otc.CustomersCanonical
    WHERE PhoneNormalized IS NOT NULL AND LEN(PhoneNormalized) >= 10;  -- Minimum phone length
    
    SET @rows_affected = @@ROWCOUNT;
    PRINT CONCAT('  Generated ', @rows_affected, ' phone match keys.');
    
    -- Name + City match keys
    INSERT INTO work_otc.CustomersMatchKeys (WorkCustomerID, MatchKeyType, MatchKeyValue)
    SELECT WorkCustomerID, 'NameCity', 
        UPPER(LTRIM(RTRIM(CONCAT(
            COALESCE(ContactFirstName, ''), '|',
            COALESCE(ContactLastName, ''), '|',
            COALESCE(CityNormalized, '')
        ))))
    FROM work_otc.CustomersCanonical
    WHERE (ContactFirstName IS NOT NULL OR ContactLastName IS NOT NULL)
        AND CityNormalized IS NOT NULL;
    
    SET @rows_affected = @@ROWCOUNT;
    PRINT CONCAT('  Generated ', @rows_affected, ' name+city match keys.');
    
    -- Company + City match keys
    INSERT INTO work_otc.CustomersMatchKeys (WorkCustomerID, MatchKeyType, MatchKeyValue)
    SELECT WorkCustomerID, 'CompanyCity', 
        UPPER(LTRIM(RTRIM(CONCAT(
            COALESCE(CompanyNameNormalized, ''), '|',
            COALESCE(CityNormalized, '')
        ))))
    FROM work_otc.CustomersCanonical
    WHERE CompanyNameNormalized IS NOT NULL
        AND CityNormalized IS NOT NULL;
    
    SET @rows_affected = @@ROWCOUNT;
    PRINT CONCAT('  Generated ', @rows_affected, ' company+city match keys.');
    PRINT '';

    /* =============================================================================
       Step 5: Create match groups
       ============================================================================= */
    PRINT 'Step 5: Creating match groups...';
    
    INSERT INTO work_otc.CustomersMatchGroups (MatchKeyType, MatchKeyValue, GroupSize)
    SELECT MatchKeyType, MatchKeyValue, COUNT(*) AS GroupSize
    FROM work_otc.CustomersMatchKeys
    GROUP BY MatchKeyType, MatchKeyValue
    HAVING COUNT(*) > 0;
    
    SET @rows_affected = @@ROWCOUNT;
    PRINT CONCAT('  Created ', @rows_affected, ' match groups.');
    PRINT '';

    /* =============================================================================
       Step 6: Link records to match groups
       ============================================================================= */
    PRINT 'Step 6: Linking records to match groups...';
    
    INSERT INTO work_otc.CustomersMatchGroupMembers (MatchGroupID, WorkCustomerID)
    SELECT mg.MatchGroupID, mk.WorkCustomerID
    FROM work_otc.CustomersMatchGroups mg
    INNER JOIN work_otc.CustomersMatchKeys mk 
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
            c.WorkCustomerID,
            CASE 
                WHEN c.HasEmail = 1 AND c.HasPhone = 1 AND c.HasAddress = 1 THEN 'Complete data (email+phone+address)'
                WHEN c.HasEmail = 1 AND c.HasPhone = 1 THEN 'Email and phone present'
                WHEN c.HasEmail = 1 THEN 'Email present'
                WHEN c.HasPhone = 1 AND c.HasAddress = 1 THEN 'Phone and address present'
                WHEN c.HasPhone = 1 THEN 'Phone present'
                WHEN c.HasAddress = 1 THEN 'Address present'
                WHEN c.CompanyName IS NOT NULL THEN 'Company name present'
                ELSE 'First record in group'
            END AS SurvivorshipReason,
            ROW_NUMBER() OVER (
                PARTITION BY mg.MatchGroupID 
                ORDER BY 
                    c.HasEmail DESC,
                    c.HasPhone DESC,
                    c.HasAddress DESC,
                    c.HasFullName DESC,
                    c.WorkCustomerID ASC  -- Tie-breaker: first record
            ) AS RowNum
        FROM work_otc.CustomersMatchGroups mg
        INNER JOIN work_otc.CustomersMatchGroupMembers mgm ON mg.MatchGroupID = mgm.MatchGroupID
        INNER JOIN work_otc.CustomersCanonical c ON mgm.WorkCustomerID = c.WorkCustomerID
    )
    INSERT INTO work_otc.CustomersSurvivorship (MatchGroupID, WorkCustomerID, SurvivorshipReason)
    SELECT MatchGroupID, WorkCustomerID, SurvivorshipReason
    FROM RankedRecords
    WHERE RowNum = 1;
    
    SET @rows_affected = @@ROWCOUNT;
    PRINT CONCAT('  Selected ', @rows_affected, ' survived records.');
    PRINT '';

    /* =============================================================================
       Step 8: Create crosswalk (source ID -> work ID mapping)
       ============================================================================= */
    PRINT 'Step 8: Creating crosswalk...';
    
    INSERT INTO work_otc.CustomersCrosswalk (SourceSystem, SourceID, WorkCustomerID)
    SELECT c.SourceSystem, c.SourceID, 
        COALESCE(s.WorkCustomerID, c.WorkCustomerID) AS WorkCustomerID
    FROM work_otc.CustomersCanonical c
    LEFT JOIN work_otc.CustomersMatchGroupMembers mgm ON c.WorkCustomerID = mgm.WorkCustomerID
    LEFT JOIN work_otc.CustomersSurvivorship s ON mgm.MatchGroupID = s.MatchGroupID
    WHERE COALESCE(s.WorkCustomerID, c.WorkCustomerID) IS NOT NULL;
    
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
    FROM work_otc.CustomersCanonical
    UNION ALL
    SELECT 
        'Match Groups' AS Metric,
        COUNT(*) AS Value
    FROM work_otc.CustomersMatchGroups
    UNION ALL
    SELECT 
        'Duplicate Groups' AS Metric,
        COUNT(*) AS Value
    FROM work_otc.CustomersMatchGroups
    WHERE GroupSize > 1
    UNION ALL
    SELECT 
        'Survived Records' AS Metric,
        COUNT(*) AS Value
    FROM work_otc.CustomersSurvivorship
    UNION ALL
    SELECT 
        'Crosswalk Mappings' AS Metric,
        COUNT(*) AS Value
    FROM work_otc.CustomersCrosswalk;

    COMMIT TRANSACTION;
    PRINT '';
    PRINT '=== work_otc build completed successfully ===';

END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;
    
    PRINT '';
    PRINT '=== work_otc build failed ===';
    PRINT CONCAT('Error Number: ', ERROR_NUMBER());
    PRINT CONCAT('Error Message: ', ERROR_MESSAGE());
    PRINT CONCAT('Error Line: ', ERROR_LINE());
    
    THROW;
END CATCH;
GO
