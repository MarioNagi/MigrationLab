USE MigrationLab;
GO

/*
File
----
sql/02_etl_procs/080_create_etl_procs.sql

Purpose
-------
Production-style stored procedures that wrap each ETL stage with:
  - @BatchID parameter for run correlation
  - etl.RunLog row per step (start + complete/fail)
  - etl.RejectLog row per dropped/merged source record (with reason code)
  - reference.SurvivorshipRules consulted per attribute in target_model build

The 100-160 scripts remain in the repo as readable, step-by-step "what does
this stage do" documentation. THIS file is what runs in CI / "production".

Recommended entry point: EXEC etl.usp_RunAll;

Prerequisites
-------------
- All schema scripts (010 - 075) executed
- Source databases (Northwind, CsvRaw) populated
*/

SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF DB_NAME() <> 'MigrationLab'
    THROW 50000, 'This script must be executed in the MigrationLab database context.', 1;
GO

/* =============================================================================
   Helper: etl.usp_LogStepStart / etl.usp_LogStepEnd
   ============================================================================= */

CREATE OR ALTER PROCEDURE etl.usp_LogStepStart
    @BatchID    VARCHAR(50),
    @ProcName   VARCHAR(100),
    @StepName   VARCHAR(200),
    @RunLogID   BIGINT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO etl.RunLog (BatchID, ProcName, StepName, Status, StartTime)
    VALUES (@BatchID, @ProcName, @StepName, 'STARTED', SYSDATETIME());
    SET @RunLogID = SCOPE_IDENTITY();
END;
GO

CREATE OR ALTER PROCEDURE etl.usp_LogStepEnd
    @RunLogID       BIGINT,
    @RowsAffected   BIGINT          = NULL,
    @Status         VARCHAR(20)     = 'COMPLETED',
    @ErrorNumber    INT             = NULL,
    @ErrorMessage   NVARCHAR(2000)  = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE etl.RunLog
       SET EndTime      = SYSDATETIME(),
           Status       = @Status,
           RowsAffected = @RowsAffected,
           ErrorNumber  = @ErrorNumber,
           ErrorMessage = @ErrorMessage
     WHERE RunLogID = @RunLogID;
END;
GO

/* =============================================================================
   etl.usp_RefreshSnapshots
   ============================================================================= */

CREATE OR ALTER PROCEDURE etl.usp_RefreshSnapshots
    @BatchID VARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @snap DATETIME2(7) = SYSDATETIME();
    DECLARE @run BIGINT, @rows BIGINT;
    DECLARE @proc VARCHAR(100) = 'usp_RefreshSnapshots';

    BEGIN TRY
        BEGIN TRANSACTION;

        EXEC etl.usp_LogStepStart @BatchID, @proc, 'Northwind.Customers -> source_northwind.Customers', @run OUTPUT;
        TRUNCATE TABLE source_northwind.Customers;
        INSERT INTO source_northwind.Customers
            (CustomerID, CompanyName, ContactName, ContactTitle, Address, City, Region,
             PostalCode, Country, Phone, Fax, snapshot_timestamp, source_system)
        SELECT CustomerID, CompanyName, ContactName, ContactTitle, Address, City, Region,
               PostalCode, Country, Phone, Fax, @snap, 'Northwind'
        FROM Northwind.dbo.Customers;
        SET @rows = @@ROWCOUNT;
        EXEC etl.usp_LogStepEnd @run, @rows;

        EXEC etl.usp_LogStepStart @BatchID, @proc, 'Northwind.Suppliers -> source_northwind.Suppliers', @run OUTPUT;
        TRUNCATE TABLE source_northwind.Suppliers;
        INSERT INTO source_northwind.Suppliers
            (SupplierID, CompanyName, ContactName, ContactTitle, Address, City, Region,
             PostalCode, Country, Phone, Fax, HomePage, snapshot_timestamp, source_system)
        SELECT SupplierID, CompanyName, ContactName, ContactTitle, Address, City, Region,
               PostalCode, Country, Phone, Fax, HomePage, @snap, 'Northwind'
        FROM Northwind.dbo.Suppliers;
        SET @rows = @@ROWCOUNT;
        EXEC etl.usp_LogStepEnd @run, @rows;

        EXEC etl.usp_LogStepStart @BatchID, @proc, 'CsvRaw.CustomersExport -> source_csv.CustomersExport', @run OUTPUT;
        TRUNCATE TABLE source_csv.CustomersExport;
        INSERT INTO source_csv.CustomersExport
            (LegacyCustomerNo, Company, ContactFirstName, ContactMiddleName, ContactLastName,
             City, Country, PostalCode, Street, Phone, Email, snapshot_timestamp, source_system)
        SELECT LegacyCustomerNo, Company, ContactFirstName, ContactMiddleName, ContactLastName,
               City, Country, PostalCode, Street, Phone, Email, @snap, 'CsvRaw'
        FROM CsvRaw.dbo.CustomersExport;
        SET @rows = @@ROWCOUNT;
        EXEC etl.usp_LogStepEnd @run, @rows;

        EXEC etl.usp_LogStepStart @BatchID, @proc, 'CsvRaw.VendorsExport -> source_csv.VendorsExport', @run OUTPUT;
        TRUNCATE TABLE source_csv.VendorsExport;
        INSERT INTO source_csv.VendorsExport
            (LegacyVendorNo, VendorName, ContactFirstName, ContactMiddleName, ContactLastName,
             City, Country, PostalCode, Street, Phone, Email, snapshot_timestamp, source_system)
        SELECT LegacyVendorNo, VendorName, ContactFirstName, ContactMiddleName, ContactLastName,
               City, Country, PostalCode, Street, Phone, Email, @snap, 'CsvRaw'
        FROM CsvRaw.dbo.VendorsExport;
        SET @rows = @@ROWCOUNT;
        EXEC etl.usp_LogStepEnd @run, @rows;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        IF @run IS NOT NULL
            EXEC etl.usp_LogStepEnd @run, NULL, 'FAILED', @ErrorNumber = ERROR_NUMBER, @ErrorMessage = ERROR_MESSAGE;
        THROW;
    END CATCH
END;
GO

/* =============================================================================
   etl.usp_BuildWorkOTC  (customers)

   This proc is the canonical implementation. The corresponding 110 script
   contains the same logic in step-by-step form for readability.
   ============================================================================= */

CREATE OR ALTER PROCEDURE etl.usp_BuildWorkOTC
    @BatchID VARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @run BIGINT, @rows BIGINT;
    DECLARE @proc VARCHAR(100) = 'usp_BuildWorkOTC';

    BEGIN TRY
        BEGIN TRANSACTION;

        EXEC etl.usp_LogStepStart @BatchID, @proc, 'Truncate work_otc tables', @run OUTPUT;
        TRUNCATE TABLE work_otc.CustomersCrosswalk;
        TRUNCATE TABLE work_otc.CustomersSurvivorship;
        TRUNCATE TABLE work_otc.CustomersMatchGroupMembers;
        TRUNCATE TABLE work_otc.CustomersMatchGroups;
        TRUNCATE TABLE work_otc.CustomersMatchKeys;
        TRUNCATE TABLE work_otc.CustomersCanonical;
        EXEC etl.usp_LogStepEnd @run, 0;

        -- Northwind: split ContactName -> First/Middle/Last
        EXEC etl.usp_LogStepStart @BatchID, @proc, 'Load Northwind customers (canonical)', @run OUTPUT;
        INSERT INTO work_otc.CustomersCanonical (
            SourceSystem, SourceID,
            CompanyName, CompanyNameNormalized,
            ContactNameFull, ContactFirstName, ContactMiddleName, ContactLastName,
            Street, City, CityNormalized, Region, PostalCode, Country, CountryCode,
            Phone, PhoneNormalized, Email, EmailNormalized,
            HasEmail, HasPhone, HasFullName, HasAddress)
        SELECT
            'Northwind', CAST(c.CustomerID AS VARCHAR(50)),
            c.CompanyName,
            UPPER(LTRIM(RTRIM(REPLACE(REPLACE(c.CompanyName,' ',''),'-','')))),
            c.ContactName,
            CASE WHEN c.ContactName IS NULL THEN NULL
                 ELSE NULLIF(LTRIM(RTRIM(SUBSTRING(c.ContactName, 1, CHARINDEX(' ', c.ContactName + ' ') - 1))),'') END,
            CASE WHEN c.ContactName IS NULL OR CHARINDEX(' ', c.ContactName) = 0 THEN NULL
                 WHEN LEN(c.ContactName) - LEN(REPLACE(c.ContactName,' ','')) >= 2 THEN
                    NULLIF(LTRIM(RTRIM(SUBSTRING(c.ContactName,
                        CHARINDEX(' ', c.ContactName) + 1,
                        LEN(c.ContactName) - CHARINDEX(' ', REVERSE(c.ContactName)) - CHARINDEX(' ', c.ContactName)))),'')
                 ELSE NULL END,
            CASE WHEN c.ContactName IS NULL OR CHARINDEX(' ', c.ContactName) = 0 THEN NULL
                 ELSE NULLIF(LTRIM(RTRIM(REVERSE(SUBSTRING(REVERSE(c.ContactName),1,CHARINDEX(' ',REVERSE(c.ContactName))-1)))),'') END,
            c.Address, c.City,
            UPPER(LTRIM(RTRIM(REPLACE(c.City,' ','')))),
            c.Region, c.PostalCode, c.Country,
            (SELECT TOP 1 cc.CountryCode FROM reference.CountryCodes cc
              WHERE cc.CountryNameVariant = c.Country OR cc.CountryNameStandard = c.Country),
            c.Phone,
            NULLIF(LTRIM(RTRIM(
                REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(ISNULL(c.Phone,''),
                    ' ',''),'-',''),'(',''),')',''),'.',''),'+',''),'/',''),'\',''))),''),
            NULL, NULL,  -- Northwind has no email
            0,
            CASE WHEN c.Phone IS NOT NULL THEN 1 ELSE 0 END,
            CASE WHEN c.ContactName IS NOT NULL THEN 1 ELSE 0 END,
            CASE WHEN c.Address IS NOT NULL AND c.City IS NOT NULL AND c.Country IS NOT NULL THEN 1 ELSE 0 END
        FROM source_northwind.Customers c;
        SET @rows = @@ROWCOUNT;
        EXEC etl.usp_LogStepEnd @run, @rows;

        -- CSV: rebuild ContactNameFull from First/Middle/Last
        EXEC etl.usp_LogStepStart @BatchID, @proc, 'Load CsvRaw customers (canonical)', @run OUTPUT;
        INSERT INTO work_otc.CustomersCanonical (
            SourceSystem, SourceID,
            CompanyName, CompanyNameNormalized,
            ContactNameFull, ContactFirstName, ContactMiddleName, ContactLastName,
            Street, City, CityNormalized, Region, PostalCode, Country, CountryCode,
            Phone, PhoneNormalized, Email, EmailNormalized,
            HasEmail, HasPhone, HasFullName, HasAddress)
        SELECT
            'CsvRaw', c.LegacyCustomerNo,
            LTRIM(RTRIM(c.Company)),
            UPPER(LTRIM(RTRIM(REPLACE(REPLACE(c.Company,' ',''),'-','')))),
            LTRIM(RTRIM(NULLIF(CONCAT(
                NULLIF(c.ContactFirstName + ' ',''),
                NULLIF(c.ContactMiddleName + ' ',''),
                NULLIF(c.ContactLastName,'')),''))),
            c.ContactFirstName, c.ContactMiddleName, c.ContactLastName,
            c.Street, c.City,
            UPPER(LTRIM(RTRIM(REPLACE(c.City,' ','')))),
            NULL, c.PostalCode, c.Country,
            (SELECT TOP 1 cc.CountryCode FROM reference.CountryCodes cc
              WHERE cc.CountryNameVariant = c.Country OR cc.CountryNameStandard = c.Country),
            c.Phone,
            NULLIF(LTRIM(RTRIM(
                REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(ISNULL(c.Phone,''),
                    ' ',''),'-',''),'(',''),')',''),'.',''),'+',''),'/',''),'\',''))),''),
            c.Email,
            LOWER(LTRIM(RTRIM(c.Email))),
            CASE WHEN c.Email IS NOT NULL THEN 1 ELSE 0 END,
            CASE WHEN c.Phone IS NOT NULL THEN 1 ELSE 0 END,
            CASE WHEN c.ContactFirstName IS NOT NULL OR c.ContactLastName IS NOT NULL THEN 1 ELSE 0 END,
            CASE WHEN c.Street IS NOT NULL AND c.City IS NOT NULL AND c.Country IS NOT NULL THEN 1 ELSE 0 END
        FROM source_csv.CustomersExport c;
        SET @rows = @@ROWCOUNT;
        EXEC etl.usp_LogStepEnd @run, @rows;

        -- Match keys
        EXEC etl.usp_LogStepStart @BatchID, @proc, 'Generate match keys', @run OUTPUT;
        INSERT INTO work_otc.CustomersMatchKeys (WorkCustomerID, MatchKeyType, MatchKeyValue)
        SELECT WorkCustomerID, 'Email', EmailNormalized
        FROM work_otc.CustomersCanonical WHERE EmailNormalized IS NOT NULL;

        INSERT INTO work_otc.CustomersMatchKeys (WorkCustomerID, MatchKeyType, MatchKeyValue)
        SELECT WorkCustomerID, 'Phone', PhoneNormalized
        FROM work_otc.CustomersCanonical
        WHERE PhoneNormalized IS NOT NULL AND LEN(PhoneNormalized) >= 10;

        INSERT INTO work_otc.CustomersMatchKeys (WorkCustomerID, MatchKeyType, MatchKeyValue)
        SELECT WorkCustomerID, 'NameCity',
            UPPER(LTRIM(RTRIM(CONCAT(COALESCE(ContactFirstName,''),'|',
                                     COALESCE(ContactLastName,''),'|',
                                     COALESCE(CityNormalized,'')))))
        FROM work_otc.CustomersCanonical
        WHERE (ContactFirstName IS NOT NULL OR ContactLastName IS NOT NULL)
          AND CityNormalized IS NOT NULL;

        INSERT INTO work_otc.CustomersMatchKeys (WorkCustomerID, MatchKeyType, MatchKeyValue)
        SELECT WorkCustomerID, 'CompanyCity',
            UPPER(LTRIM(RTRIM(CONCAT(COALESCE(CompanyNameNormalized,''),'|',
                                     COALESCE(CityNormalized,'')))))
        FROM work_otc.CustomersCanonical
        WHERE CompanyNameNormalized IS NOT NULL AND CityNormalized IS NOT NULL;

        SELECT @rows = COUNT(*) FROM work_otc.CustomersMatchKeys;
        EXEC etl.usp_LogStepEnd @run, @rows;

        -- Match groups
        EXEC etl.usp_LogStepStart @BatchID, @proc, 'Build match groups', @run OUTPUT;
        INSERT INTO work_otc.CustomersMatchGroups (MatchKeyType, MatchKeyValue, GroupSize)
        SELECT MatchKeyType, MatchKeyValue, COUNT(*)
        FROM work_otc.CustomersMatchKeys
        GROUP BY MatchKeyType, MatchKeyValue;
        SET @rows = @@ROWCOUNT;
        EXEC etl.usp_LogStepEnd @run, @rows;

        EXEC etl.usp_LogStepStart @BatchID, @proc, 'Link records to match groups', @run OUTPUT;
        INSERT INTO work_otc.CustomersMatchGroupMembers (MatchGroupID, WorkCustomerID)
        SELECT mg.MatchGroupID, mk.WorkCustomerID
        FROM work_otc.CustomersMatchGroups mg
        INNER JOIN work_otc.CustomersMatchKeys mk
            ON mg.MatchKeyType = mk.MatchKeyType AND mg.MatchKeyValue = mk.MatchKeyValue;
        SET @rows = @@ROWCOUNT;
        EXEC etl.usp_LogStepEnd @run, @rows;

        -- Survivorship: pick survivor record per group (record-level, completeness-ranked)
        EXEC etl.usp_LogStepStart @BatchID, @proc, 'Apply record-level survivorship', @run OUTPUT;
        ;WITH Ranked AS (
            SELECT mg.MatchGroupID, c.WorkCustomerID,
                CASE
                    WHEN c.HasEmail=1 AND c.HasPhone=1 AND c.HasAddress=1 THEN 'Complete (email+phone+address)'
                    WHEN c.HasEmail=1 AND c.HasPhone=1 THEN 'Email and phone present'
                    WHEN c.HasEmail=1 THEN 'Email present'
                    WHEN c.HasPhone=1 AND c.HasAddress=1 THEN 'Phone and address present'
                    WHEN c.HasPhone=1 THEN 'Phone present'
                    WHEN c.HasAddress=1 THEN 'Address present'
                    WHEN c.CompanyName IS NOT NULL THEN 'Company name present'
                    ELSE 'First record in group' END AS Reason,
                ROW_NUMBER() OVER (PARTITION BY mg.MatchGroupID
                    ORDER BY c.HasEmail DESC, c.HasPhone DESC, c.HasAddress DESC, c.HasFullName DESC, c.WorkCustomerID) AS Rnk
            FROM work_otc.CustomersMatchGroups mg
            INNER JOIN work_otc.CustomersMatchGroupMembers mgm ON mg.MatchGroupID = mgm.MatchGroupID
            INNER JOIN work_otc.CustomersCanonical c ON mgm.WorkCustomerID = c.WorkCustomerID)
        INSERT INTO work_otc.CustomersSurvivorship (MatchGroupID, WorkCustomerID, SurvivorshipReason)
        SELECT MatchGroupID, WorkCustomerID, Reason FROM Ranked WHERE Rnk = 1;
        SET @rows = @@ROWCOUNT;
        EXEC etl.usp_LogStepEnd @run, @rows;

        -- Crosswalk
        EXEC etl.usp_LogStepStart @BatchID, @proc, 'Build crosswalk', @run OUTPUT;
        INSERT INTO work_otc.CustomersCrosswalk (SourceSystem, SourceID, WorkCustomerID)
        SELECT c.SourceSystem, c.SourceID,
               COALESCE(s.WorkCustomerID, c.WorkCustomerID)
        FROM work_otc.CustomersCanonical c
        LEFT JOIN work_otc.CustomersMatchGroupMembers mgm ON c.WorkCustomerID = mgm.WorkCustomerID
        LEFT JOIN work_otc.CustomersSurvivorship s ON mgm.MatchGroupID = s.MatchGroupID;
        SET @rows = @@ROWCOUNT;
        EXEC etl.usp_LogStepEnd @run, @rows;

        -- Reject log: every non-survivor in a multi-record group is "merged away"
        EXEC etl.usp_LogStepStart @BatchID, @proc, 'Log merged-away records', @run OUTPUT;
        INSERT INTO etl.RejectLog
            (BatchID, EntityType, SourceSystem, SourceID, Stage, ReasonCode, ReasonDetail, SurvivorWorkID)
        SELECT @BatchID, 'Customer', c.SourceSystem, c.SourceID, 'Survivorship',
               'DUPLICATE_MERGED',
               CONCAT('Merged into survivor WorkCustomerID=', s.WorkCustomerID,
                      ' via ', mg.MatchKeyType, ' match (', s.SurvivorshipReason, ')'),
               s.WorkCustomerID
        FROM work_otc.CustomersCanonical c
        INNER JOIN work_otc.CustomersMatchGroupMembers mgm ON c.WorkCustomerID = mgm.WorkCustomerID
        INNER JOIN work_otc.CustomersMatchGroups mg ON mgm.MatchGroupID = mg.MatchGroupID
        INNER JOIN work_otc.CustomersSurvivorship s ON mg.MatchGroupID = s.MatchGroupID
        WHERE mg.GroupSize > 1
          AND c.WorkCustomerID <> s.WorkCustomerID;
        SET @rows = @@ROWCOUNT;
        EXEC etl.usp_LogStepEnd @run, @rows;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        IF @run IS NOT NULL
            EXEC etl.usp_LogStepEnd @run, NULL, 'FAILED', @ErrorNumber = ERROR_NUMBER, @ErrorMessage = ERROR_MESSAGE;
        THROW;
    END CATCH
END;
GO

/* =============================================================================
   etl.usp_BuildWorkPTP  (vendors) — same shape as OTC
   ============================================================================= */

CREATE OR ALTER PROCEDURE etl.usp_BuildWorkPTP
    @BatchID VARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @run BIGINT, @rows BIGINT;
    DECLARE @proc VARCHAR(100) = 'usp_BuildWorkPTP';

    BEGIN TRY
        BEGIN TRANSACTION;

        EXEC etl.usp_LogStepStart @BatchID, @proc, 'Truncate work_ptp tables', @run OUTPUT;
        TRUNCATE TABLE work_ptp.VendorsCrosswalk;
        TRUNCATE TABLE work_ptp.VendorsSurvivorship;
        TRUNCATE TABLE work_ptp.VendorsMatchGroupMembers;
        TRUNCATE TABLE work_ptp.VendorsMatchGroups;
        TRUNCATE TABLE work_ptp.VendorsMatchKeys;
        TRUNCATE TABLE work_ptp.VendorsCanonical;
        EXEC etl.usp_LogStepEnd @run, 0;

        EXEC etl.usp_LogStepStart @BatchID, @proc, 'Load Northwind suppliers (canonical)', @run OUTPUT;
        INSERT INTO work_ptp.VendorsCanonical (
            SourceSystem, SourceID, VendorName, VendorNameNormalized,
            ContactNameFull, ContactFirstName, ContactMiddleName, ContactLastName,
            Street, City, CityNormalized, Region, PostalCode, Country, CountryCode,
            Phone, PhoneNormalized, Email, EmailNormalized,
            HasEmail, HasPhone, HasFullName, HasAddress)
        SELECT
            'Northwind', CAST(s.SupplierID AS VARCHAR(50)),
            s.CompanyName,
            UPPER(LTRIM(RTRIM(REPLACE(REPLACE(s.CompanyName,' ',''),'-','')))),
            s.ContactName,
            CASE WHEN s.ContactName IS NULL THEN NULL
                 ELSE NULLIF(LTRIM(RTRIM(SUBSTRING(s.ContactName,1,CHARINDEX(' ',s.ContactName+' ')-1))),'') END,
            CASE WHEN s.ContactName IS NULL OR CHARINDEX(' ',s.ContactName)=0 THEN NULL
                 WHEN LEN(s.ContactName)-LEN(REPLACE(s.ContactName,' ',''))>=2 THEN
                    NULLIF(LTRIM(RTRIM(SUBSTRING(s.ContactName,
                        CHARINDEX(' ',s.ContactName)+1,
                        LEN(s.ContactName)-CHARINDEX(' ',REVERSE(s.ContactName))-CHARINDEX(' ',s.ContactName)))),'')
                 ELSE NULL END,
            CASE WHEN s.ContactName IS NULL OR CHARINDEX(' ',s.ContactName)=0 THEN NULL
                 ELSE NULLIF(LTRIM(RTRIM(REVERSE(SUBSTRING(REVERSE(s.ContactName),1,CHARINDEX(' ',REVERSE(s.ContactName))-1)))),'') END,
            s.Address, s.City,
            UPPER(LTRIM(RTRIM(REPLACE(s.City,' ','')))),
            s.Region, s.PostalCode, s.Country,
            (SELECT TOP 1 cc.CountryCode FROM reference.CountryCodes cc
              WHERE cc.CountryNameVariant = s.Country OR cc.CountryNameStandard = s.Country),
            s.Phone,
            NULLIF(LTRIM(RTRIM(
                REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(ISNULL(s.Phone,''),
                    ' ',''),'-',''),'(',''),')',''),'.',''),'+',''),'/',''),'\',''))),''),
            NULL, NULL,
            0,
            CASE WHEN s.Phone IS NOT NULL THEN 1 ELSE 0 END,
            CASE WHEN s.ContactName IS NOT NULL THEN 1 ELSE 0 END,
            CASE WHEN s.Address IS NOT NULL AND s.City IS NOT NULL AND s.Country IS NOT NULL THEN 1 ELSE 0 END
        FROM source_northwind.Suppliers s;
        SET @rows = @@ROWCOUNT;
        EXEC etl.usp_LogStepEnd @run, @rows;

        EXEC etl.usp_LogStepStart @BatchID, @proc, 'Load CsvRaw vendors (canonical)', @run OUTPUT;
        INSERT INTO work_ptp.VendorsCanonical (
            SourceSystem, SourceID, VendorName, VendorNameNormalized,
            ContactNameFull, ContactFirstName, ContactMiddleName, ContactLastName,
            Street, City, CityNormalized, Region, PostalCode, Country, CountryCode,
            Phone, PhoneNormalized, Email, EmailNormalized,
            HasEmail, HasPhone, HasFullName, HasAddress)
        SELECT
            'CsvRaw', v.LegacyVendorNo,
            LTRIM(RTRIM(v.VendorName)),
            UPPER(LTRIM(RTRIM(REPLACE(REPLACE(v.VendorName,' ',''),'-','')))),
            LTRIM(RTRIM(NULLIF(CONCAT(
                NULLIF(v.ContactFirstName+' ',''),
                NULLIF(v.ContactMiddleName+' ',''),
                NULLIF(v.ContactLastName,'')),''))),
            v.ContactFirstName, v.ContactMiddleName, v.ContactLastName,
            v.Street, v.City,
            UPPER(LTRIM(RTRIM(REPLACE(v.City,' ','')))),
            NULL, v.PostalCode, v.Country,
            (SELECT TOP 1 cc.CountryCode FROM reference.CountryCodes cc
              WHERE cc.CountryNameVariant = v.Country OR cc.CountryNameStandard = v.Country),
            v.Phone,
            NULLIF(LTRIM(RTRIM(
                REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(ISNULL(v.Phone,''),
                    ' ',''),'-',''),'(',''),')',''),'.',''),'+',''),'/',''),'\',''))),''),
            v.Email,
            LOWER(LTRIM(RTRIM(v.Email))),
            CASE WHEN v.Email IS NOT NULL THEN 1 ELSE 0 END,
            CASE WHEN v.Phone IS NOT NULL THEN 1 ELSE 0 END,
            CASE WHEN v.ContactFirstName IS NOT NULL OR v.ContactLastName IS NOT NULL THEN 1 ELSE 0 END,
            CASE WHEN v.Street IS NOT NULL AND v.City IS NOT NULL AND v.Country IS NOT NULL THEN 1 ELSE 0 END
        FROM source_csv.VendorsExport v;
        SET @rows = @@ROWCOUNT;
        EXEC etl.usp_LogStepEnd @run, @rows;

        EXEC etl.usp_LogStepStart @BatchID, @proc, 'Generate match keys', @run OUTPUT;
        INSERT INTO work_ptp.VendorsMatchKeys (WorkVendorID, MatchKeyType, MatchKeyValue)
        SELECT WorkVendorID, 'Email', EmailNormalized
        FROM work_ptp.VendorsCanonical WHERE EmailNormalized IS NOT NULL;

        INSERT INTO work_ptp.VendorsMatchKeys (WorkVendorID, MatchKeyType, MatchKeyValue)
        SELECT WorkVendorID, 'Phone', PhoneNormalized
        FROM work_ptp.VendorsCanonical WHERE PhoneNormalized IS NOT NULL AND LEN(PhoneNormalized) >= 10;

        INSERT INTO work_ptp.VendorsMatchKeys (WorkVendorID, MatchKeyType, MatchKeyValue)
        SELECT WorkVendorID, 'NameCity',
            UPPER(LTRIM(RTRIM(CONCAT(COALESCE(ContactFirstName,''),'|',
                                     COALESCE(ContactLastName,''),'|',
                                     COALESCE(CityNormalized,'')))))
        FROM work_ptp.VendorsCanonical
        WHERE (ContactFirstName IS NOT NULL OR ContactLastName IS NOT NULL) AND CityNormalized IS NOT NULL;

        INSERT INTO work_ptp.VendorsMatchKeys (WorkVendorID, MatchKeyType, MatchKeyValue)
        SELECT WorkVendorID, 'CompanyCity',
            UPPER(LTRIM(RTRIM(CONCAT(COALESCE(VendorNameNormalized,''),'|',
                                     COALESCE(CityNormalized,'')))))
        FROM work_ptp.VendorsCanonical
        WHERE VendorNameNormalized IS NOT NULL AND CityNormalized IS NOT NULL;

        SELECT @rows = COUNT(*) FROM work_ptp.VendorsMatchKeys;
        EXEC etl.usp_LogStepEnd @run, @rows;

        EXEC etl.usp_LogStepStart @BatchID, @proc, 'Build match groups', @run OUTPUT;
        INSERT INTO work_ptp.VendorsMatchGroups (MatchKeyType, MatchKeyValue, GroupSize)
        SELECT MatchKeyType, MatchKeyValue, COUNT(*)
        FROM work_ptp.VendorsMatchKeys
        GROUP BY MatchKeyType, MatchKeyValue;
        SET @rows = @@ROWCOUNT;
        EXEC etl.usp_LogStepEnd @run, @rows;

        EXEC etl.usp_LogStepStart @BatchID, @proc, 'Link records to match groups', @run OUTPUT;
        INSERT INTO work_ptp.VendorsMatchGroupMembers (MatchGroupID, WorkVendorID)
        SELECT mg.MatchGroupID, mk.WorkVendorID
        FROM work_ptp.VendorsMatchGroups mg
        INNER JOIN work_ptp.VendorsMatchKeys mk
            ON mg.MatchKeyType = mk.MatchKeyType AND mg.MatchKeyValue = mk.MatchKeyValue;
        SET @rows = @@ROWCOUNT;
        EXEC etl.usp_LogStepEnd @run, @rows;

        EXEC etl.usp_LogStepStart @BatchID, @proc, 'Apply record-level survivorship', @run OUTPUT;
        ;WITH Ranked AS (
            SELECT mg.MatchGroupID, v.WorkVendorID,
                CASE
                    WHEN v.HasEmail=1 AND v.HasPhone=1 AND v.HasAddress=1 THEN 'Complete (email+phone+address)'
                    WHEN v.HasEmail=1 AND v.HasPhone=1 THEN 'Email and phone present'
                    WHEN v.HasEmail=1 THEN 'Email present'
                    WHEN v.HasPhone=1 AND v.HasAddress=1 THEN 'Phone and address present'
                    WHEN v.HasPhone=1 THEN 'Phone present'
                    WHEN v.HasAddress=1 THEN 'Address present'
                    WHEN v.VendorName IS NOT NULL THEN 'Vendor name present'
                    ELSE 'First record in group' END AS Reason,
                ROW_NUMBER() OVER (PARTITION BY mg.MatchGroupID
                    ORDER BY v.HasEmail DESC, v.HasPhone DESC, v.HasAddress DESC, v.HasFullName DESC, v.WorkVendorID) AS Rnk
            FROM work_ptp.VendorsMatchGroups mg
            INNER JOIN work_ptp.VendorsMatchGroupMembers mgm ON mg.MatchGroupID = mgm.MatchGroupID
            INNER JOIN work_ptp.VendorsCanonical v ON mgm.WorkVendorID = v.WorkVendorID)
        INSERT INTO work_ptp.VendorsSurvivorship (MatchGroupID, WorkVendorID, SurvivorshipReason)
        SELECT MatchGroupID, WorkVendorID, Reason FROM Ranked WHERE Rnk = 1;
        SET @rows = @@ROWCOUNT;
        EXEC etl.usp_LogStepEnd @run, @rows;

        EXEC etl.usp_LogStepStart @BatchID, @proc, 'Build crosswalk', @run OUTPUT;
        INSERT INTO work_ptp.VendorsCrosswalk (SourceSystem, SourceID, WorkVendorID)
        SELECT v.SourceSystem, v.SourceID,
               COALESCE(s.WorkVendorID, v.WorkVendorID)
        FROM work_ptp.VendorsCanonical v
        LEFT JOIN work_ptp.VendorsMatchGroupMembers mgm ON v.WorkVendorID = mgm.WorkVendorID
        LEFT JOIN work_ptp.VendorsSurvivorship s ON mgm.MatchGroupID = s.MatchGroupID;
        SET @rows = @@ROWCOUNT;
        EXEC etl.usp_LogStepEnd @run, @rows;

        EXEC etl.usp_LogStepStart @BatchID, @proc, 'Log merged-away records', @run OUTPUT;
        INSERT INTO etl.RejectLog
            (BatchID, EntityType, SourceSystem, SourceID, Stage, ReasonCode, ReasonDetail, SurvivorWorkID)
        SELECT @BatchID, 'Vendor', v.SourceSystem, v.SourceID, 'Survivorship',
               'DUPLICATE_MERGED',
               CONCAT('Merged into survivor WorkVendorID=', s.WorkVendorID,
                      ' via ', mg.MatchKeyType, ' match (', s.SurvivorshipReason, ')'),
               s.WorkVendorID
        FROM work_ptp.VendorsCanonical v
        INNER JOIN work_ptp.VendorsMatchGroupMembers mgm ON v.WorkVendorID = mgm.WorkVendorID
        INNER JOIN work_ptp.VendorsMatchGroups mg ON mgm.MatchGroupID = mg.MatchGroupID
        INNER JOIN work_ptp.VendorsSurvivorship s ON mg.MatchGroupID = s.MatchGroupID
        WHERE mg.GroupSize > 1
          AND v.WorkVendorID <> s.WorkVendorID;
        SET @rows = @@ROWCOUNT;
        EXEC etl.usp_LogStepEnd @run, @rows;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        IF @run IS NOT NULL
            EXEC etl.usp_LogStepEnd @run, NULL, 'FAILED', @ErrorNumber = ERROR_NUMBER, @ErrorMessage = ERROR_MESSAGE;
        THROW;
    END CATCH
END;
GO

/* =============================================================================
   etl.usp_BuildTargetModel — applies PER-ATTRIBUTE survivorship.

   For each surviving cluster:
     - For each attribute (Email, Phone, CompanyName/VendorName, Street, City,
       PostalCode, Country/CountryCode), pick the value from the source whose
       reference.SurvivorshipRules.Priority is lowest, breaking ties by
       non-null preference and then by the cluster's surviving WorkID.
     - Reject the target row (write to etl.RejectLog) if a required attribute
       (CompanyName / VendorName) is still NULL after survivorship.
   ============================================================================= */

CREATE OR ALTER PROCEDURE etl.usp_BuildTargetModel
    @BatchID VARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @run BIGINT, @rows BIGINT;
    DECLARE @proc VARCHAR(100) = 'usp_BuildTargetModel';

    BEGIN TRY
        BEGIN TRANSACTION;

        EXEC etl.usp_LogStepStart @BatchID, @proc, 'Truncate target_model', @run OUTPUT;
        TRUNCATE TABLE target_model.Customers;
        TRUNCATE TABLE target_model.Vendors;
        EXEC etl.usp_LogStepEnd @run, 0;

        /* ------------ Customers ------------ */
        EXEC etl.usp_LogStepStart @BatchID, @proc, 'Build target_model.Customers (per-attribute survivorship)', @run OUTPUT;

        ;WITH Cluster AS (
            -- ClusterID = MatchGroupID for grouped records, -WorkCustomerID for singletons
            SELECT
                COALESCE(mgm.MatchGroupID, -c.WorkCustomerID) AS ClusterID,
                c.WorkCustomerID, c.SourceSystem,
                c.CompanyName, c.Email, c.EmailNormalized, c.Phone, c.PhoneNormalized,
                c.Street, c.City, c.Region, c.PostalCode, c.Country, c.CountryCode,
                c.ContactFirstName, c.ContactMiddleName, c.ContactLastName,
                c.HasEmail, c.HasPhone, c.HasFullName, c.HasAddress
            FROM work_otc.CustomersCanonical c
            LEFT JOIN work_otc.CustomersMatchGroupMembers mgm ON c.WorkCustomerID = mgm.WorkCustomerID
        ),
        SurvivorOnly AS (
            -- Cluster -> the surviving WorkCustomerID (used for fallback attrs like names/region)
            SELECT DISTINCT
                COALESCE(s.MatchGroupID, -c.WorkCustomerID) AS ClusterID,
                COALESCE(s.WorkCustomerID, c.WorkCustomerID) AS SurvivorWorkID
            FROM work_otc.CustomersCanonical c
            LEFT JOIN work_otc.CustomersMatchGroupMembers mgm ON c.WorkCustomerID = mgm.WorkCustomerID
            LEFT JOIN work_otc.CustomersSurvivorship s ON mgm.MatchGroupID = s.MatchGroupID
        ),
        Pick AS (
            -- For each attribute, rank candidates per cluster by survivorship rule priority
            SELECT cl.ClusterID, attr.AttributeName, attr.Val,
                ROW_NUMBER() OVER (PARTITION BY cl.ClusterID, attr.AttributeName
                    ORDER BY
                        CASE WHEN attr.Val IS NULL THEN 1 ELSE 0 END,
                        COALESCE(r.Priority, 99),
                        cl.WorkCustomerID) AS Rnk
            FROM Cluster cl
            CROSS APPLY (VALUES
                ('Email',       cl.Email),
                ('Phone',       cl.Phone),
                ('CompanyName', cl.CompanyName),
                ('Street',      cl.Street),
                ('City',        cl.City),
                ('PostalCode',  cl.PostalCode),
                ('Country',     cl.Country)
            ) attr(AttributeName, Val)
            LEFT JOIN reference.SurvivorshipRules r
                ON r.EntityType = 'Customer'
               AND r.AttributeName = attr.AttributeName
               AND r.SourceSystem  = cl.SourceSystem
               AND r.IsActive = 1
        ),
        Picked AS (
            SELECT ClusterID, AttributeName, Val FROM Pick WHERE Rnk = 1
        ),
        ClusterAttrs AS (
            SELECT
                so.ClusterID,
                so.SurvivorWorkID,
                MAX(CASE WHEN p.AttributeName='Email'       THEN p.Val END) AS Email,
                MAX(CASE WHEN p.AttributeName='Phone'       THEN p.Val END) AS Phone,
                MAX(CASE WHEN p.AttributeName='CompanyName' THEN p.Val END) AS CompanyName,
                MAX(CASE WHEN p.AttributeName='Street'      THEN p.Val END) AS Street,
                MAX(CASE WHEN p.AttributeName='City'        THEN p.Val END) AS City,
                MAX(CASE WHEN p.AttributeName='PostalCode'  THEN p.Val END) AS PostalCode,
                MAX(CASE WHEN p.AttributeName='Country'     THEN p.Val END) AS Country
            FROM SurvivorOnly so
            LEFT JOIN Picked p ON p.ClusterID = so.ClusterID
            GROUP BY so.ClusterID, so.SurvivorWorkID
        ),
        Final AS (
            SELECT
                ca.ClusterID, ca.SurvivorWorkID,
                ca.CompanyName, ca.Email, ca.Phone,
                ca.Street, ca.City, ca.PostalCode, ca.Country,
                LOWER(LTRIM(RTRIM(ca.Email))) AS EmailNormalized,
                NULLIF(LTRIM(RTRIM(
                    REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(ISNULL(ca.Phone,''),
                        ' ',''),'-',''),'(',''),')',''),'.',''),'+',''),'/',''),'\',''))),'') AS PhoneNormalized,
                (SELECT TOP 1 cc.CountryCode FROM reference.CountryCodes cc
                  WHERE cc.CountryNameVariant = ca.Country OR cc.CountryNameStandard = ca.Country) AS CountryCode,
                surv.ContactFirstName, surv.ContactMiddleName, surv.ContactLastName, surv.Region,
                CASE WHEN ca.Email IS NOT NULL THEN 1 ELSE 0 END AS HasEmail,
                CASE WHEN ca.Phone IS NOT NULL THEN 1 ELSE 0 END AS HasPhone,
                CASE WHEN surv.ContactFirstName IS NOT NULL OR surv.ContactLastName IS NOT NULL THEN 1 ELSE 0 END AS HasFullName,
                CASE WHEN ca.Street IS NOT NULL AND ca.City IS NOT NULL AND ca.Country IS NOT NULL THEN 1 ELSE 0 END AS HasAddress,
                clu.SourceSystems, clu.SourceRecordCount
            FROM ClusterAttrs ca
            INNER JOIN work_otc.CustomersCanonical surv ON surv.WorkCustomerID = ca.SurvivorWorkID
            CROSS APPLY (
                SELECT
                    STRING_AGG(DISTINCT c2.SourceSystem, ',') WITHIN GROUP (ORDER BY c2.SourceSystem) AS SourceSystems,
                    COUNT(*) AS SourceRecordCount
                FROM work_otc.CustomersCanonical c2
                LEFT JOIN work_otc.CustomersMatchGroupMembers mgm2 ON c2.WorkCustomerID = mgm2.WorkCustomerID
                WHERE COALESCE(mgm2.MatchGroupID, -c2.WorkCustomerID) = ca.ClusterID
            ) clu
        )
        INSERT INTO target_model.Customers (
            CustomerID, CompanyName, CompanyNameLegal,
            ContactFirstName, ContactMiddleName, ContactLastName, ContactFullName, ContactTitle,
            Street, City, Region, PostalCode, Country, CountryCode,
            Phone, PhoneNormalized, Fax, Email, EmailNormalized,
            DataQualityScore, HasCompleteAddress, HasValidEmail, HasValidPhone, HasContactName,
            SourceSystems, SourceRecordCount)
        SELECT
            'CUST' + RIGHT('000000' + CAST(ROW_NUMBER() OVER (ORDER BY SurvivorWorkID) AS VARCHAR(6)), 6),
            CompanyName, NULL,
            ContactFirstName, ContactMiddleName, ContactLastName,
            LTRIM(RTRIM(NULLIF(CONCAT(
                NULLIF(ContactFirstName + ' ', ''),
                NULLIF(ContactMiddleName + ' ', ''),
                NULLIF(ContactLastName, '')), ''))),
            NULL,
            Street, City, Region, PostalCode, Country, CountryCode,
            Phone, PhoneNormalized, NULL, Email, EmailNormalized,
            (CASE WHEN CompanyName IS NOT NULL THEN 20 ELSE 0 END +
             CASE WHEN HasEmail=1 THEN 25 ELSE 0 END +
             CASE WHEN HasPhone=1 THEN 25 ELSE 0 END +
             CASE WHEN HasAddress=1 THEN 20 ELSE 0 END +
             CASE WHEN HasFullName=1 THEN 10 ELSE 0 END),
            HasAddress, HasEmail, HasPhone, HasFullName,
            SourceSystems, SourceRecordCount
        FROM Final
        WHERE CompanyName IS NOT NULL;  -- required-field filter

        SET @rows = @@ROWCOUNT;
        EXEC etl.usp_LogStepEnd @run, @rows;

        -- Reject: any cluster whose survivor's CompanyName ended up NULL
        EXEC etl.usp_LogStepStart @BatchID, @proc, 'Log customers rejected for missing required fields', @run OUTPUT;
        INSERT INTO etl.RejectLog
            (BatchID, EntityType, SourceSystem, SourceID, Stage, ReasonCode, ReasonDetail)
        SELECT @BatchID, 'Customer', c.SourceSystem, c.SourceID, 'TargetModel',
               'MISSING_REQUIRED_FIELD',
               'CompanyName is NULL after per-attribute survivorship.'
        FROM work_otc.CustomersCanonical c
        INNER JOIN work_otc.CustomersSurvivorship s ON s.WorkCustomerID = c.WorkCustomerID
        WHERE c.CompanyName IS NULL;
        SET @rows = @@ROWCOUNT;
        EXEC etl.usp_LogStepEnd @run, @rows;

        /* ------------ Vendors ------------ */
        EXEC etl.usp_LogStepStart @BatchID, @proc, 'Build target_model.Vendors (per-attribute survivorship)', @run OUTPUT;

        ;WITH Cluster AS (
            SELECT
                COALESCE(mgm.MatchGroupID, -v.WorkVendorID) AS ClusterID,
                v.WorkVendorID, v.SourceSystem,
                v.VendorName, v.Email, v.EmailNormalized, v.Phone, v.PhoneNormalized,
                v.Street, v.City, v.Region, v.PostalCode, v.Country, v.CountryCode,
                v.ContactFirstName, v.ContactMiddleName, v.ContactLastName,
                v.HasEmail, v.HasPhone, v.HasFullName, v.HasAddress
            FROM work_ptp.VendorsCanonical v
            LEFT JOIN work_ptp.VendorsMatchGroupMembers mgm ON v.WorkVendorID = mgm.WorkVendorID
        ),
        SurvivorOnly AS (
            SELECT DISTINCT
                COALESCE(s.MatchGroupID, -v.WorkVendorID) AS ClusterID,
                COALESCE(s.WorkVendorID, v.WorkVendorID) AS SurvivorWorkID
            FROM work_ptp.VendorsCanonical v
            LEFT JOIN work_ptp.VendorsMatchGroupMembers mgm ON v.WorkVendorID = mgm.WorkVendorID
            LEFT JOIN work_ptp.VendorsSurvivorship s ON mgm.MatchGroupID = s.MatchGroupID
        ),
        Pick AS (
            SELECT cl.ClusterID, attr.AttributeName, attr.Val,
                ROW_NUMBER() OVER (PARTITION BY cl.ClusterID, attr.AttributeName
                    ORDER BY
                        CASE WHEN attr.Val IS NULL THEN 1 ELSE 0 END,
                        COALESCE(r.Priority, 99),
                        cl.WorkVendorID) AS Rnk
            FROM Cluster cl
            CROSS APPLY (VALUES
                ('Email',      cl.Email),
                ('Phone',      cl.Phone),
                ('VendorName', cl.VendorName),
                ('Street',     cl.Street),
                ('City',       cl.City),
                ('PostalCode', cl.PostalCode),
                ('Country',    cl.Country)
            ) attr(AttributeName, Val)
            LEFT JOIN reference.SurvivorshipRules r
                ON r.EntityType = 'Vendor'
               AND r.AttributeName = attr.AttributeName
               AND r.SourceSystem  = cl.SourceSystem
               AND r.IsActive = 1
        ),
        Picked AS (SELECT ClusterID, AttributeName, Val FROM Pick WHERE Rnk = 1),
        ClusterAttrs AS (
            SELECT
                so.ClusterID, so.SurvivorWorkID,
                MAX(CASE WHEN p.AttributeName='Email'      THEN p.Val END) AS Email,
                MAX(CASE WHEN p.AttributeName='Phone'      THEN p.Val END) AS Phone,
                MAX(CASE WHEN p.AttributeName='VendorName' THEN p.Val END) AS VendorName,
                MAX(CASE WHEN p.AttributeName='Street'     THEN p.Val END) AS Street,
                MAX(CASE WHEN p.AttributeName='City'       THEN p.Val END) AS City,
                MAX(CASE WHEN p.AttributeName='PostalCode' THEN p.Val END) AS PostalCode,
                MAX(CASE WHEN p.AttributeName='Country'    THEN p.Val END) AS Country
            FROM SurvivorOnly so
            LEFT JOIN Picked p ON p.ClusterID = so.ClusterID
            GROUP BY so.ClusterID, so.SurvivorWorkID
        ),
        Final AS (
            SELECT
                ca.ClusterID, ca.SurvivorWorkID,
                ca.VendorName, ca.Email, ca.Phone,
                ca.Street, ca.City, ca.PostalCode, ca.Country,
                LOWER(LTRIM(RTRIM(ca.Email))) AS EmailNormalized,
                NULLIF(LTRIM(RTRIM(
                    REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(ISNULL(ca.Phone,''),
                        ' ',''),'-',''),'(',''),')',''),'.',''),'+',''),'/',''),'\',''))),'') AS PhoneNormalized,
                (SELECT TOP 1 cc.CountryCode FROM reference.CountryCodes cc
                  WHERE cc.CountryNameVariant = ca.Country OR cc.CountryNameStandard = ca.Country) AS CountryCode,
                surv.ContactFirstName, surv.ContactMiddleName, surv.ContactLastName, surv.Region,
                CASE WHEN ca.Email IS NOT NULL THEN 1 ELSE 0 END AS HasEmail,
                CASE WHEN ca.Phone IS NOT NULL THEN 1 ELSE 0 END AS HasPhone,
                CASE WHEN surv.ContactFirstName IS NOT NULL OR surv.ContactLastName IS NOT NULL THEN 1 ELSE 0 END AS HasFullName,
                CASE WHEN ca.Street IS NOT NULL AND ca.City IS NOT NULL AND ca.Country IS NOT NULL THEN 1 ELSE 0 END AS HasAddress,
                clu.SourceSystems, clu.SourceRecordCount
            FROM ClusterAttrs ca
            INNER JOIN work_ptp.VendorsCanonical surv ON surv.WorkVendorID = ca.SurvivorWorkID
            CROSS APPLY (
                SELECT
                    STRING_AGG(DISTINCT v2.SourceSystem, ',') WITHIN GROUP (ORDER BY v2.SourceSystem) AS SourceSystems,
                    COUNT(*) AS SourceRecordCount
                FROM work_ptp.VendorsCanonical v2
                LEFT JOIN work_ptp.VendorsMatchGroupMembers mgm2 ON v2.WorkVendorID = mgm2.WorkVendorID
                WHERE COALESCE(mgm2.MatchGroupID, -v2.WorkVendorID) = ca.ClusterID
            ) clu
        )
        INSERT INTO target_model.Vendors (
            VendorID, VendorName, VendorNameLegal,
            ContactFirstName, ContactMiddleName, ContactLastName, ContactFullName, ContactTitle,
            Street, City, Region, PostalCode, Country, CountryCode,
            Phone, PhoneNormalized, Fax, Email, EmailNormalized, HomePage,
            DataQualityScore, HasCompleteAddress, HasValidEmail, HasValidPhone, HasContactName,
            SourceSystems, SourceRecordCount)
        SELECT
            'VEND' + RIGHT('000000' + CAST(ROW_NUMBER() OVER (ORDER BY SurvivorWorkID) AS VARCHAR(6)), 6),
            VendorName, NULL,
            ContactFirstName, ContactMiddleName, ContactLastName,
            LTRIM(RTRIM(NULLIF(CONCAT(
                NULLIF(ContactFirstName + ' ', ''),
                NULLIF(ContactMiddleName + ' ', ''),
                NULLIF(ContactLastName, '')), ''))),
            NULL,
            Street, City, Region, PostalCode, Country, CountryCode,
            Phone, PhoneNormalized, NULL, Email, EmailNormalized, NULL,
            (CASE WHEN VendorName IS NOT NULL THEN 20 ELSE 0 END +
             CASE WHEN HasEmail=1 THEN 25 ELSE 0 END +
             CASE WHEN HasPhone=1 THEN 25 ELSE 0 END +
             CASE WHEN HasAddress=1 THEN 20 ELSE 0 END +
             CASE WHEN HasFullName=1 THEN 10 ELSE 0 END),
            HasAddress, HasEmail, HasPhone, HasFullName,
            SourceSystems, SourceRecordCount
        FROM Final
        WHERE VendorName IS NOT NULL;

        SET @rows = @@ROWCOUNT;
        EXEC etl.usp_LogStepEnd @run, @rows;

        EXEC etl.usp_LogStepStart @BatchID, @proc, 'Log vendors rejected for missing required fields', @run OUTPUT;
        INSERT INTO etl.RejectLog
            (BatchID, EntityType, SourceSystem, SourceID, Stage, ReasonCode, ReasonDetail)
        SELECT @BatchID, 'Vendor', v.SourceSystem, v.SourceID, 'TargetModel',
               'MISSING_REQUIRED_FIELD',
               'VendorName is NULL after per-attribute survivorship.'
        FROM work_ptp.VendorsCanonical v
        INNER JOIN work_ptp.VendorsSurvivorship s ON s.WorkVendorID = v.WorkVendorID
        WHERE v.VendorName IS NULL;
        SET @rows = @@ROWCOUNT;
        EXEC etl.usp_LogStepEnd @run, @rows;

        /* ------------ Crosswalk update ------------ */
        EXEC etl.usp_LogStepStart @BatchID, @proc, 'Update customer crosswalk with TargetCustomerID', @run OUTPUT;
        UPDATE cw
           SET cw.TargetCustomerID = tm.CustomerID
        FROM work_otc.CustomersCrosswalk cw
        INNER JOIN work_otc.CustomersCanonical surv ON surv.WorkCustomerID = cw.WorkCustomerID
        INNER JOIN target_model.Customers tm
            ON tm.CompanyName = surv.CompanyName
           AND ISNULL(tm.EmailNormalized,'') = ISNULL(surv.EmailNormalized,'')
           AND ISNULL(tm.PhoneNormalized,'') = ISNULL(surv.PhoneNormalized,'');
        SET @rows = @@ROWCOUNT;
        EXEC etl.usp_LogStepEnd @run, @rows;

        EXEC etl.usp_LogStepStart @BatchID, @proc, 'Update vendor crosswalk with TargetVendorID', @run OUTPUT;
        UPDATE cw
           SET cw.TargetVendorID = tm.VendorID
        FROM work_ptp.VendorsCrosswalk cw
        INNER JOIN work_ptp.VendorsCanonical surv ON surv.WorkVendorID = cw.WorkVendorID
        INNER JOIN target_model.Vendors tm
            ON tm.VendorName = surv.VendorName
           AND ISNULL(tm.EmailNormalized,'') = ISNULL(surv.EmailNormalized,'')
           AND ISNULL(tm.PhoneNormalized,'') = ISNULL(surv.PhoneNormalized,'');
        SET @rows = @@ROWCOUNT;
        EXEC etl.usp_LogStepEnd @run, @rows;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        IF @run IS NOT NULL
            EXEC etl.usp_LogStepEnd @run, NULL, 'FAILED', @ErrorNumber = ERROR_NUMBER, @ErrorMessage = ERROR_MESSAGE;
        THROW;
    END CATCH
END;
GO

/* =============================================================================
   etl.usp_LoadTarget — target_model -> target_sap_ecc
   ============================================================================= */

CREATE OR ALTER PROCEDURE etl.usp_LoadTarget
    @BatchID VARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @run BIGINT, @rows BIGINT, @ts DATETIME2(7) = SYSDATETIME();
    DECLARE @proc VARCHAR(100) = 'usp_LoadTarget';

    BEGIN TRY
        BEGIN TRANSACTION;

        EXEC etl.usp_LogStepStart @BatchID, @proc, 'Truncate target_sap_ecc tables', @run OUTPUT;
        TRUNCATE TABLE target_sap_ecc.CustomerMaster;
        TRUNCATE TABLE target_sap_ecc.VendorMaster;
        EXEC etl.usp_LogStepEnd @run, 0;

        EXEC etl.usp_LogStepStart @BatchID, @proc, 'Load CustomerMaster', @run OUTPUT;
        INSERT INTO target_sap_ecc.CustomerMaster (
            CustomerNumber, Name1, Name2, Name3, Name4,
            Street, StreetNumber, City, Region, PostalCode, Country,
            ContactPerson, ContactTitle, Telephone, TelephoneExtension, Mobile, Fax, Email,
            AccountGroup, CustomerType, Status, DeletionFlag,
            CreatedBy, CreatedDate, CreatedTime, LastChangedBy, LastChangedDate, LastChangedTime,
            MigrationSource, MigrationTimestamp, MigrationBatchID)
        SELECT
            CustomerID, CompanyName, NULL, NULL, NULL,
            Street, NULL, City, Region, PostalCode, CountryCode,
            ContactFullName, NULL, Phone, NULL, NULL, NULL, Email,
            '0001', '01', 'A', ' ',
            'MIGRATION', CAST(@ts AS DATE), CAST(@ts AS TIME),
            'MIGRATION', CAST(@ts AS DATE), CAST(@ts AS TIME),
            SourceSystems, @ts, @BatchID
        FROM target_model.Customers;
        SET @rows = @@ROWCOUNT;
        EXEC etl.usp_LogStepEnd @run, @rows;

        EXEC etl.usp_LogStepStart @BatchID, @proc, 'Load VendorMaster', @run OUTPUT;
        INSERT INTO target_sap_ecc.VendorMaster (
            VendorNumber, Name1, Name2, Name3, Name4,
            Street, StreetNumber, City, Region, PostalCode, Country,
            ContactPerson, ContactTitle, Telephone, TelephoneExtension, Mobile, Fax, Email, Website,
            AccountGroup, VendorType, Status, DeletionFlag,
            CreatedBy, CreatedDate, CreatedTime, LastChangedBy, LastChangedDate, LastChangedTime,
            MigrationSource, MigrationTimestamp, MigrationBatchID)
        SELECT
            VendorID, VendorName, NULL, NULL, NULL,
            Street, NULL, City, Region, PostalCode, CountryCode,
            ContactFullName, NULL, Phone, NULL, NULL, Fax, Email, HomePage,
            '0001', '01', 'A', ' ',
            'MIGRATION', CAST(@ts AS DATE), CAST(@ts AS TIME),
            'MIGRATION', CAST(@ts AS DATE), CAST(@ts AS TIME),
            SourceSystems, @ts, @BatchID
        FROM target_model.Vendors;
        SET @rows = @@ROWCOUNT;
        EXEC etl.usp_LogStepEnd @run, @rows;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        IF @run IS NOT NULL
            EXEC etl.usp_LogStepEnd @run, NULL, 'FAILED', @ErrorNumber = ERROR_NUMBER, @ErrorMessage = ERROR_MESSAGE;
        THROW;
    END CATCH
END;
GO

/* =============================================================================
   etl.usp_RunAll — orchestrator
   ============================================================================= */

CREATE OR ALTER PROCEDURE etl.usp_RunAll
    @BatchID VARCHAR(50) = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    IF @BatchID IS NULL
        SET @BatchID = 'BATCH-' + FORMAT(SYSDATETIME(), 'yyyyMMddHHmmss');

    DECLARE @overall BIGINT;
    EXEC etl.usp_LogStepStart @BatchID, 'usp_RunAll', 'Pipeline started', @overall OUTPUT;

    BEGIN TRY
        EXEC etl.usp_RefreshSnapshots  @BatchID;
        EXEC etl.usp_BuildWorkOTC      @BatchID;
        EXEC etl.usp_BuildWorkPTP      @BatchID;
        EXEC etl.usp_BuildTargetModel  @BatchID;
        EXEC etl.usp_LoadTarget        @BatchID;

        EXEC etl.usp_LogStepEnd @overall, NULL, 'COMPLETED';
    END TRY
    BEGIN CATCH
        EXEC etl.usp_LogStepEnd @overall, NULL, 'FAILED',
            @ErrorNumber = ERROR_NUMBER, @ErrorMessage = ERROR_MESSAGE;
        THROW;
    END CATCH
END;
GO

PRINT 'ETL stored procedures created.';
PRINT '';
PRINT 'Run with: EXEC etl.usp_RunAll;';
GO
