USE CsvRaw;
GO

/*
Purpose
-------
Generate CsvRaw exports from Northwind (OVERLAP ONLY).
- Deterministic + repeatable (no NEWID-driven randomness)
- Demonstrates reversible transformations:
    Northwind.ContactName (single string) -> First/Middle/Last + Email
- Introduces controlled "real world" mess (casing, phone formatting, company suffixes)
- Generates realistic synthetic data only (no placeholder values like "Test Company", "Dummy Vendor")

Data Quality Rules
------------------
- Email generation: Only creates emails when FirstName OR LastName exists (realistic requirement)
- Email format: firstname.lastname@company.com (or firstname@company.com / lastname@company.com if one name missing)
- 20% of records intentionally have NULL email (realistic data quality issue)
- Company names: Introduces controlled variations (Ltd, Limited, Pty, GmbH, whitespace noise)
- Phone numbers: Controlled formatting variations (spaces vs dashes, country prefix noise)
- Country codes: Normalized variations (USA/US/United States, UK/GB/United Kingdom)

IMPORTANT
---------
- This script MUST NOT generate CSV-only net-new records.
  Net-new records belong in: sql/00_setup/005_generate_csvraw_netnew.sql (next step).
- All data is derived from Northwind to guarantee overlap between source systems.
*/

SET NOCOUNT ON;

-- Safety checks
IF DB_NAME() <> 'CsvRaw'
BEGIN
    THROW 50000, 'This script must be executed in the CsvRaw database context.', 1;
END;

IF OBJECT_ID('dbo.CustomersExport','U') IS NULL
    THROW 50001, 'Missing table dbo.CustomersExport. Run 003_create_csvraw_tables.sql first.', 1;

IF OBJECT_ID('dbo.VendorsExport','U') IS NULL
    THROW 50002, 'Missing table dbo.VendorsExport. Run 003_create_csvraw_tables.sql first.', 1;

TRUNCATE TABLE dbo.CustomersExport;
TRUNCATE TABLE dbo.VendorsExport;
GO

DECLARE @overlap_pct_customers int = 70; -- percent of Northwind Customers to export into CsvRaw
DECLARE @overlap_pct_vendors   int = 70; -- percent of Northwind Suppliers to export into CsvRaw

/* =============================================================================
   CustomersExport from Northwind.dbo.Customers (OVERLAP + controlled mess)
   ============================================================================= */
;WITH base AS (
    SELECT
        c.CustomerID,
        c.CompanyName AS CompanyBase,
        LTRIM(RTRIM(ISNULL(c.ContactName,''))) AS ContactNameRaw,
        c.Address, c.City, c.Country, c.PostalCode, c.Phone,
        ABS(CHECKSUM(CONCAT('CUST|', c.CustomerID))) AS H  -- deterministic "random"
    FROM Northwind.dbo.Customers c
),
filtered AS (
    SELECT *
    FROM base
    WHERE (H % 100) < @overlap_pct_customers
),
cleaned AS (
    SELECT
        f.*,
        -- Normalize whitespace, remove a few separators that commonly appear in names
        NULLIF(LTRIM(RTRIM(
            REPLACE(REPLACE(REPLACE(REPLACE(f.ContactNameRaw, CHAR(9),' '), CHAR(10),' '), CHAR(13),' '), '  ',' ')
        )), '') AS ContactNameClean
    FROM filtered f
),
tokenized AS (
    SELECT
        c.*,
        -- Split ContactName into tokens while preserving order (XML trick, deterministic)
        TRY_CAST(
            '<i>' + REPLACE(
                REPLACE(
                    REPLACE(
                        REPLACE(c.ContactNameClean, '&', '&amp;'),
                    '<',''),
                '>',''),
            ' ', '</i><i>') + '</i>' AS XML
        ) AS NameXml
    FROM cleaned c
),
names AS (
    SELECT
        t.*,
        CASE
            WHEN t.ContactNameClean IS NULL THEN NULL
            WHEN t.NameXml IS NULL THEN t.ContactNameClean
            ELSE NULLIF(t.NameXml.value('(/i[1])[1]','nvarchar(100)'), '')
        END AS FirstName,

        CASE
            WHEN t.ContactNameClean IS NULL THEN NULL
            WHEN t.NameXml IS NULL THEN NULL
            WHEN t.NameXml.exist('/i[2]') = 0 THEN NULL
            ELSE NULLIF(t.NameXml.value('(/i[last()])[1]','nvarchar(100)'), '')
        END AS LastName,

        CASE
            WHEN t.ContactNameClean IS NULL THEN NULL
            WHEN t.NameXml IS NULL THEN NULL
            WHEN t.NameXml.exist('/i[3]') = 0 THEN NULL -- only 1 or 2 tokens -> no middle name
            ELSE NULLIF(
                STUFF((
                    SELECT ' ' + x.n.value('.','nvarchar(100)')
                    FROM t.NameXml.nodes('/i[position() > 1 and position() < last()]') AS x(n)
                    FOR XML PATH(''), TYPE
                ).value('.','nvarchar(max)'), 1, 1, ''), ''
            )
        END AS MiddleName
    FROM tokenized t
)
INSERT INTO dbo.CustomersExport (
    LegacyCustomerNo,
    Company,
    ContactFirstName,
    ContactMiddleName,
    ContactLastName,
    City,
    Country,
    PostalCode,
    Street,
    Phone,
    Email
)
SELECT
    -- Stable legacy key derived from source key (repeatable)
    CONCAT('CUST-', RIGHT(CONCAT('000000', CAST(n.H % 1000000 AS varchar(6))), 6)) AS LegacyCustomerNo,

    -- Display company name (controlled mess); keep CompanyBase for email domain stability
    CASE (n.H % 3)
        WHEN 0 THEN CONCAT(' ', n.CompanyBase, '  ')
        WHEN 1 THEN CONCAT(n.CompanyBase, ' Ltd')
        ELSE      CONCAT(n.CompanyBase, ' Limited')
    END AS Company,

    n.FirstName  AS ContactFirstName,
    n.MiddleName AS ContactMiddleName,
    n.LastName   AS ContactLastName,

    -- City casing noise
    CASE WHEN (n.H % 2) = 0 THEN UPPER(ISNULL(n.City,'')) ELSE ISNULL(n.City,'') END AS City,

    -- Country variants noise
    CASE
        WHEN n.Country IN ('USA','United States') AND (n.H % 3) = 0 THEN 'US'
        WHEN n.Country IN ('USA','United States') AND (n.H % 3) = 1 THEN 'USA'
        WHEN n.Country IN ('UK','United Kingdom') AND (n.H % 2) = 0 THEN 'GB'
        ELSE ISNULL(n.Country,'')
    END AS Country,

    ISNULL(n.PostalCode,'') AS PostalCode,
    ISNULL(n.Address,'')    AS Street,

    -- Phone noise (deterministic)
    CASE
        WHEN (n.H % 2) = 0 THEN REPLACE(REPLACE(ISNULL(n.Phone,''),'-',' '),'(', '')
        ELSE CONCAT('(+)', ISNULL(n.Phone,''))
    END AS Phone,

    -- Email: sometimes missing; otherwise firstname.lastname@company.com (domain from CompanyBase)
    -- Only generate email if we have at least FirstName or LastName (realistic requirement)
    CASE
        WHEN (n.H % 5) = 0 THEN NULL
        WHEN n.FirstName IS NULL AND n.LastName IS NULL THEN NULL
        WHEN n.CompanyBase IS NULL OR LTRIM(RTRIM(n.CompanyBase)) = '' THEN NULL
        ELSE LOWER(
            -- local part: firstname.lastname (or just firstname/lastname if one is missing)
            CASE
                WHEN n.FirstName IS NOT NULL AND n.LastName IS NOT NULL THEN
                    REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(n.FirstName,' ',''),'.',''),',',''),'''',''),'/',''), '\\','')
                    + '.' + REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(n.LastName,' ',''),'.',''),',',''),'''',''),'/',''), '\\','')
                WHEN n.FirstName IS NOT NULL THEN
                    REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(n.FirstName,' ',''),'.',''),',',''),'''',''),'/',''), '\\','')
                ELSE
                    REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(n.LastName,' ',''),'.',''),',',''),'''',''),'/',''), '\\','')
            END
            + '@'
            -- domain: normalized company base name
            + REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(LOWER(LTRIM(RTRIM(n.CompanyBase))),' ',''),'.',''),',',''),'&','and'),'''',''),'/','')
            + '.com'
        )
    END AS Email
FROM names n
ORDER BY n.H; -- stable ordering for repeatability

/* =============================================================================
   VendorsExport from Northwind.dbo.Suppliers (OVERLAP + controlled mess)
   ============================================================================= */
;WITH base AS (
    SELECT
        s.SupplierID,
        s.CompanyName AS CompanyBase,
        LTRIM(RTRIM(ISNULL(s.ContactName,''))) AS ContactNameRaw,
        s.Address, s.City, s.Country, s.PostalCode, s.Phone,
        ABS(CHECKSUM(CONCAT('VEND|', s.SupplierID))) AS H
    FROM Northwind.dbo.Suppliers s
),
filtered AS (
    SELECT *
    FROM base
    WHERE (H % 100) < @overlap_pct_vendors
),
cleaned AS (
    SELECT
        f.*,
        NULLIF(LTRIM(RTRIM(
            REPLACE(REPLACE(REPLACE(REPLACE(f.ContactNameRaw, CHAR(9),' '), CHAR(10),' '), CHAR(13),' '), '  ',' ')
        )), '') AS ContactNameClean
    FROM filtered f
),
tokenized AS (
    SELECT
        c.*,
        TRY_CAST(
            '<i>' + REPLACE(
                REPLACE(
                    REPLACE(
                        REPLACE(c.ContactNameClean, '&', '&amp;'),
                    '<',''),
                '>',''),
            ' ', '</i><i>') + '</i>' AS XML
        ) AS NameXml
    FROM cleaned c
),
names AS (
    SELECT
        t.*,
        CASE
            WHEN t.ContactNameClean IS NULL THEN NULL
            WHEN t.NameXml IS NULL THEN t.ContactNameClean
            ELSE NULLIF(t.NameXml.value('(/i[1])[1]','nvarchar(100)'), '')
        END AS FirstName,

        CASE
            WHEN t.ContactNameClean IS NULL THEN NULL
            WHEN t.NameXml IS NULL THEN NULL
            WHEN t.NameXml.exist('/i[2]') = 0 THEN NULL
            ELSE NULLIF(t.NameXml.value('(/i[last()])[1]','nvarchar(100)'), '')
        END AS LastName,

        CASE
            WHEN t.ContactNameClean IS NULL THEN NULL
            WHEN t.NameXml IS NULL THEN NULL
            WHEN t.NameXml.exist('/i[3]') = 0 THEN NULL
            ELSE NULLIF(
                STUFF((
                    SELECT ' ' + x.n.value('.','nvarchar(100)')
                    FROM t.NameXml.nodes('/i[position() > 1 and position() < last()]') AS x(n)
                    FOR XML PATH(''), TYPE
                ).value('.','nvarchar(max)'), 1, 1, ''), ''
            )
        END AS MiddleName
    FROM tokenized t
)
INSERT INTO dbo.VendorsExport (
    LegacyVendorNo,
    VendorName,
    ContactFirstName,
    ContactMiddleName,
    ContactLastName,
    City,
    Country,
    PostalCode,
    Street,
    Phone,
    Email
)
SELECT
    CONCAT('VEND-', RIGHT(CONCAT('000000', CAST(n.H % 1000000 AS varchar(6))), 6)) AS LegacyVendorNo,

    CASE (n.H % 3)
        WHEN 0 THEN CONCAT(' ', n.CompanyBase, ' ')
        WHEN 1 THEN CONCAT(n.CompanyBase, ' Pty')
        ELSE      CONCAT(n.CompanyBase, ' GmbH')
    END AS VendorName,

    n.FirstName  AS ContactFirstName,
    n.MiddleName AS ContactMiddleName,
    n.LastName   AS ContactLastName,

    CASE WHEN (n.H % 2) = 0 THEN UPPER(ISNULL(n.City,'')) ELSE ISNULL(n.City,'') END AS City,

    CASE
        WHEN n.Country IN ('USA','United States') AND (n.H % 3) = 0 THEN 'US'
        WHEN n.Country IN ('USA','United States') AND (n.H % 3) = 1 THEN 'USA'
        WHEN n.Country IN ('UK','United Kingdom') AND (n.H % 2) = 0 THEN 'GB'
        ELSE ISNULL(n.Country,'')
    END AS Country,

    ISNULL(n.PostalCode,'') AS PostalCode,
    ISNULL(n.Address,'')    AS Street,

    CASE
        WHEN (n.H % 2) = 0 THEN REPLACE(REPLACE(ISNULL(n.Phone,''),'-',' '),'(', '')
        ELSE CONCAT('(+)', ISNULL(n.Phone,''))
    END AS Phone,

    -- Email: sometimes missing; otherwise firstname.lastname@company.com (domain from CompanyBase)
    -- Only generate email if we have at least FirstName or LastName (realistic requirement)
    CASE
        WHEN (n.H % 5) = 0 THEN NULL
        WHEN n.FirstName IS NULL AND n.LastName IS NULL THEN NULL
        WHEN n.CompanyBase IS NULL OR LTRIM(RTRIM(n.CompanyBase)) = '' THEN NULL
        ELSE LOWER(
            -- local part: firstname.lastname (or just firstname/lastname if one is missing)
            CASE
                WHEN n.FirstName IS NOT NULL AND n.LastName IS NOT NULL THEN
                    REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(n.FirstName,' ',''),'.',''),',',''),'''',''),'/',''), '\\','')
                    + '.' + REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(n.LastName,' ',''),'.',''),',',''),'''',''),'/',''), '\\','')
                WHEN n.FirstName IS NOT NULL THEN
                    REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(n.FirstName,' ',''),'.',''),',',''),'''',''),'/',''), '\\','')
                ELSE
                    REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(n.LastName,' ',''),'.',''),',',''),'''',''),'/',''), '\\','')
            END
            + '@'
            -- domain: normalized company base name
            + REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(LOWER(LTRIM(RTRIM(n.CompanyBase))),' ',''),'.',''),',',''),'&','and'),'''',''),'/','')
            + '.com'
        )
    END AS Email
FROM names n
ORDER BY n.H;
GO

/*
Next step (do not implement here):
---------------------------------
Create net-new CSV-only entities in:
- sql/00_setup/005_generate_csvraw_netnew.sql
*/
