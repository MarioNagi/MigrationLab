/*
File
----
sql/00_setup/006_validate_csvraw_load.sql

Purpose
-------
Post-load validation checks for CsvRaw exports produced by:
- 004_generate_csvraw_from_northwind.sql  (overlap set)
- 005_generate_csvraw_netnew.sql          (net-new set)

Design goals
------------
- SQL-first, repeatable checks
- Easy to screenshot in SSMS for LinkedIn/GitHub
- No destructive operations (read-only checks)

Assumptions
-----------
CsvRaw tables exist (created by 003):
- dbo.CustomersExport
- dbo.VendorsExport

Notes
-----
- Net-new keys are expected to use prefixes:
    Customers: LegacyCustomerNo like 'CUSTX-%'
    Vendors:   LegacyVendorNo   like 'VENDX-%'
- Overlap keys (from 004) may use different prefixes (commonly 'CUST-%' / 'VEND-%').
*/

USE CsvRaw;
GO
SET NOCOUNT ON;

PRINT '=== CsvRaw Validation Started ===';
PRINT CONCAT('Database: ', DB_NAME(), ' | Time: ', CONVERT(varchar(19), SYSDATETIME(), 120));

/* =============================================================================
   0) Safety checks
   ============================================================================= */
IF DB_NAME() <> 'CsvRaw'
    THROW 50100, 'Run this validation in the CsvRaw database context.', 1;

IF OBJECT_ID('dbo.CustomersExport','U') IS NULL
    THROW 50101, 'Missing dbo.CustomersExport. Run 003 + 004/005 first.', 1;

IF OBJECT_ID('dbo.VendorsExport','U') IS NULL
    THROW 50102, 'Missing dbo.VendorsExport. Run 003 + 004/005 first.', 1;

/* =============================================================================
   1) Row counts (total + by source prefix)
   ============================================================================= */
PRINT '--- Row counts ---';

SELECT
    'CustomersExport' AS TableName,
    COUNT(*)          AS TotalRows,
    SUM(CASE WHEN LegacyCustomerNo LIKE 'CUSTX-%' THEN 1 ELSE 0 END) AS NetNewRows,
    SUM(CASE WHEN LegacyCustomerNo NOT LIKE 'CUSTX-%' THEN 1 ELSE 0 END) AS OverlapOrOtherRows
FROM dbo.CustomersExport;

SELECT
    'VendorsExport' AS TableName,
    COUNT(*)        AS TotalRows,
    SUM(CASE WHEN LegacyVendorNo LIKE 'VENDX-%' THEN 1 ELSE 0 END) AS NetNewRows,
    SUM(CASE WHEN LegacyVendorNo NOT LIKE 'VENDX-%' THEN 1 ELSE 0 END) AS OverlapOrOtherRows
FROM dbo.VendorsExport;

/* =============================================================================
   2) Key uniqueness (must be unique)
   ============================================================================= */
PRINT '--- Key uniqueness checks (expect 0 rows) ---';

SELECT TOP (50)
    'CustomersExport' AS TableName,
    LegacyCustomerNo,
    COUNT(*) AS Cnt
FROM dbo.CustomersExport
GROUP BY LegacyCustomerNo
HAVING COUNT(*) > 1
ORDER BY Cnt DESC, LegacyCustomerNo;

SELECT TOP (50)
    'VendorsExport' AS TableName,
    LegacyVendorNo,
    COUNT(*) AS Cnt
FROM dbo.VendorsExport
GROUP BY LegacyVendorNo
HAVING COUNT(*) > 1
ORDER BY Cnt DESC, LegacyVendorNo;

/* =============================================================================
   3) Mandatory fields completeness (NULL/blank checks)
   ============================================================================= */
PRINT '--- Mandatory field completeness ---';

-- Customers
SELECT
    'CustomersExport' AS TableName,
    SUM(CASE WHEN NULLIF(LTRIM(RTRIM(LegacyCustomerNo)), '') IS NULL THEN 1 ELSE 0 END) AS NullOrBlank_LegacyCustomerNo,
    SUM(CASE WHEN NULLIF(LTRIM(RTRIM(Company)), '') IS NULL THEN 1 ELSE 0 END)          AS NullOrBlank_Company,
    SUM(CASE WHEN NULLIF(LTRIM(RTRIM(ContactFirstName)), '') IS NULL THEN 1 ELSE 0 END) AS NullOrBlank_FirstName,
    SUM(CASE WHEN NULLIF(LTRIM(RTRIM(ContactLastName)), '') IS NULL THEN 1 ELSE 0 END)  AS NullOrBlank_LastName,
    SUM(CASE WHEN NULLIF(LTRIM(RTRIM(City)), '') IS NULL THEN 1 ELSE 0 END)             AS NullOrBlank_City,
    SUM(CASE WHEN NULLIF(LTRIM(RTRIM(Country)), '') IS NULL THEN 1 ELSE 0 END)          AS NullOrBlank_Country,
    SUM(CASE WHEN NULLIF(LTRIM(RTRIM(Phone)), '') IS NULL THEN 1 ELSE 0 END)            AS NullOrBlank_Phone
FROM dbo.CustomersExport;

-- Vendors
SELECT
    'VendorsExport' AS TableName,
    SUM(CASE WHEN NULLIF(LTRIM(RTRIM(LegacyVendorNo)), '') IS NULL THEN 1 ELSE 0 END) AS NullOrBlank_LegacyVendorNo,
    SUM(CASE WHEN NULLIF(LTRIM(RTRIM(VendorName)), '') IS NULL THEN 1 ELSE 0 END)     AS NullOrBlank_VendorName,
    SUM(CASE WHEN NULLIF(LTRIM(RTRIM(ContactFirstName)), '') IS NULL THEN 1 ELSE 0 END) AS NullOrBlank_FirstName,
    SUM(CASE WHEN NULLIF(LTRIM(RTRIM(ContactLastName)), '') IS NULL THEN 1 ELSE 0 END)  AS NullOrBlank_LastName,
    SUM(CASE WHEN NULLIF(LTRIM(RTRIM(City)), '') IS NULL THEN 1 ELSE 0 END)             AS NullOrBlank_City,
    SUM(CASE WHEN NULLIF(LTRIM(RTRIM(Country)), '') IS NULL THEN 1 ELSE 0 END)          AS NullOrBlank_Country,
    SUM(CASE WHEN NULLIF(LTRIM(RTRIM(Phone)), '') IS NULL THEN 1 ELSE 0 END)            AS NullOrBlank_Phone
FROM dbo.VendorsExport;

/* =============================================================================
   4) Email quality checks (not mandatory, but should be reasonable)
   ============================================================================= */
PRINT '--- Email quality checks ---';
PRINT 'Emails are allowed to be NULL sometimes (realistic). The checks below flag malformed values.';

-- Customers: malformed emails (contains spaces, missing @, missing dot after @)
SELECT TOP (50)
    'CustomersExport' AS TableName,
    LegacyCustomerNo,
    Company,
    Email
FROM dbo.CustomersExport
WHERE Email IS NOT NULL
  AND (
        Email LIKE '% %' OR
        CHARINDEX('@', Email) = 0 OR
        CHARINDEX('.', Email, CHARINDEX('@', Email) + 1) = 0
      )
ORDER BY LegacyCustomerNo;

-- Vendors: malformed emails
SELECT TOP (50)
    'VendorsExport' AS TableName,
    LegacyVendorNo,
    VendorName,
    Email
FROM dbo.VendorsExport
WHERE Email IS NOT NULL
  AND (
        Email LIKE '% %' OR
        CHARINDEX('@', Email) = 0 OR
        CHARINDEX('.', Email, CHARINDEX('@', Email) + 1) = 0
      )
ORDER BY LegacyVendorNo;

-- Email duplicates (not always wrong in real life, but worth visibility)
PRINT '--- Email duplicates (visibility; duplicates may be valid in real life) ---';

SELECT TOP (50)
    'CustomersExport' AS TableName,
    Email,
    COUNT(*) AS Cnt
FROM dbo.CustomersExport
WHERE Email IS NOT NULL
GROUP BY Email
HAVING COUNT(*) > 1
ORDER BY Cnt DESC, Email;

SELECT TOP (50)
    'VendorsExport' AS TableName,
    Email,
    COUNT(*) AS Cnt
FROM dbo.VendorsExport
WHERE Email IS NOT NULL
GROUP BY Email
HAVING COUNT(*) > 1
ORDER BY Cnt DESC, Email;

/* =============================================================================
   5) Legacy key format checks
   ============================================================================= */
PRINT '--- Legacy key format checks (expect 0 rows) ---';

-- Customers: net-new keys should match CUSTX-###### (6 digits)
SELECT TOP (50)
    LegacyCustomerNo
FROM dbo.CustomersExport
WHERE LegacyCustomerNo LIKE 'CUSTX-%'
  AND (
        LEN(LegacyCustomerNo) <> LEN('CUSTX-000000')
        OR TRY_CONVERT(int, RIGHT(LegacyCustomerNo, 6)) IS NULL
      )
ORDER BY LegacyCustomerNo;

-- Vendors: net-new keys should match VENDX-###### (6 digits)
SELECT TOP (50)
    LegacyVendorNo
FROM dbo.VendorsExport
WHERE LegacyVendorNo LIKE 'VENDX-%'
  AND (
        LEN(LegacyVendorNo) <> LEN('VENDX-000000')
        OR TRY_CONVERT(int, RIGHT(LegacyVendorNo, 6)) IS NULL
      )
ORDER BY LegacyVendorNo;

/* =============================================================================
   6) Quick sample rows (for eyeballing)
   ============================================================================= */
PRINT '--- Quick samples (top 10 each) ---';

SELECT TOP (10) *
FROM dbo.CustomersExport
ORDER BY CASE WHEN LegacyCustomerNo LIKE 'CUSTX-%' THEN 1 ELSE 0 END DESC, LegacyCustomerNo;

SELECT TOP (10) *
FROM dbo.VendorsExport
ORDER BY CASE WHEN LegacyVendorNo LIKE 'VENDX-%' THEN 1 ELSE 0 END DESC, LegacyVendorNo;

PRINT '=== CsvRaw Validation Completed ===';
