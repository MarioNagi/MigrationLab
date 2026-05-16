USE CsvRaw;
GO
/*
File
----
sql/00_setup/005_generate_csvraw_netnew.sql

Purpose
-------
Generate CsvRaw "net-new" records that DO NOT exist in Northwind.
These emulate legacy CRM/Excel exports with realistic data + controlled mess.

Design rules (locked)
---------------------
- No "Dummy", "Test", "CSV Only Customer 1" placeholders.
- Realistic human names, company names, cities/countries, phones, addresses.
- Deterministic + repeatable: no NEWID() randomness.
- This script APPENDS records (it does not truncate). Run 004 first to load overlap.

Output tables (created by 003)
------------------------------
- dbo.CustomersExport
- dbo.VendorsExport
*/

SET NOCOUNT ON;

-- Safety checks
IF DB_NAME() <> 'CsvRaw'
BEGIN
    THROW 50010, 'This script must be executed in the CsvRaw database context.', 1;
END;

IF OBJECT_ID('dbo.CustomersExport','U') IS NULL
    THROW 50011, 'Missing table dbo.CustomersExport. Run 003_create_csvraw_tables.sql first.', 1;

IF OBJECT_ID('dbo.VendorsExport','U') IS NULL
    THROW 50012, 'Missing table dbo.VendorsExport. Run 003_create_csvraw_tables.sql first.', 1;

DECLARE @netnew_customers int = 120; -- number of net-new customers to generate
DECLARE @netnew_vendors   int = 80;  -- number of net-new vendors to generate

/* =============================================================================
   Seed data (small but realistic; combined with deterministic selection)
   ============================================================================= */

DECLARE @FirstNames TABLE (Id int IDENTITY(1,1) PRIMARY KEY, Val nvarchar(50) NOT NULL);
INSERT INTO @FirstNames (Val) VALUES
(N'Ahmed'),(N'Mohamed'),(N'Omar'),(N'Youssef'),(N'Karim'),(N'Hassan'),(N'Ibrahim'),
(N'Adel'),(N'Khaled'),(N'Tarek'),(N'Sameh'),(N'Amr'),(N'Mostafa'),(N'Mina'),
(N'Kirollos'),(N'George'),(N'Peter'),(N'John'),(N'David'),(N'Daniel'),
(N'Sarah'),(N'Mariam'),(N'Fatma'),(N'Nour'),(N'Dina'),(N'Yara'),(N'Hana'),
(N'Rana'),(N'Leila'),(N'Maya'),(N'Emily'),(N'Sophia'),(N'Olivia'),(N'Emma');

DECLARE @MiddleNames TABLE (Id int IDENTITY(1,1) PRIMARY KEY, Val nvarchar(50) NOT NULL);
INSERT INTO @MiddleNames (Val) VALUES
(N''),(N''),(N''), -- increase probability of "no middle name"
(N'Ali'),(N'Mahmoud'),(N'Fathy'),(N'Said'),(N'Nabil'),(N'Essam'),
(N'Yehia'),(N'Joseph'),(N'Andrew'),(N'Paul'),(N'Michael'),(N'Rami');

DECLARE @LastNames TABLE (Id int IDENTITY(1,1) PRIMARY KEY, Val nvarchar(60) NOT NULL);
INSERT INTO @LastNames (Val) VALUES
(N'Hassan'),(N'Ibrahim'),(N'Ahmed'),(N'Mahmoud'),(N'Salem'),(N'Fouad'),(N'Fathy'),
(N'Zaki'),(N'Elmasry'),(N'Gamal'),(N'Fares'),(N'Kamel'),(N'Sorour'),(N'Mikhail'),
(N'Boutrous'),(N'Younan'),(N'Farag'),(N'Khalil'),(N'Nassar'),
(N'Johnson'),(N'Brown'),(N'Wilson'),(N'Taylor'),(N'Anderson'),
(N'Martin'),(N'Garcia'),(N'Lopez'),(N'Rossi'),(N'Bianchi'),(N'Schmidt');

DECLARE @CompanyStems TABLE (Id int IDENTITY(1,1) PRIMARY KEY, Val nvarchar(80) NOT NULL);
INSERT INTO @CompanyStems (Val) VALUES
(N'Blue Nile'),(N'Cedars Group'),(N'Atlas Systems'),(N'Green Horizon'),
(N'Nova Telecom'),(N'Prime Logistics'),(N'Everest Trading'),(N'Coral Labs'),
(N'Phoenix Supplies'),(N'Orbit Networks'),(N'Helios Industries'),(N'Summit Services'),
(N'Sahara Solutions'),(N'Delta Partners'),(N'Capital Dynamics'),(N'Golden Gate Imports'),
(N'Riverstone Manufacturing'),(N'Oceanic Foods'),(N'Aurora Retail'),(N'Silverline Engineering');

DECLARE @CompanySuffixes TABLE (Id int IDENTITY(1,1) PRIMARY KEY, Val nvarchar(30) NOT NULL);
INSERT INTO @CompanySuffixes (Val) VALUES
(N'LLC'),(N'Ltd'),(N'Limited'),(N'Co.'),(N'Group'),(N'S.A.'),(N'FZ-LLC');

DECLARE @StreetNames TABLE (Id int IDENTITY(1,1) PRIMARY KEY, Val nvarchar(80) NOT NULL);
INSERT INTO @StreetNames (Val) VALUES
(N'El Tahrir'),(N'Corniche'),(N'Ramses'),(N'El Geish'),(N'Abu Bakr St'),
(N'King Faisal'),(N'Sheikh Zayed Rd'),(N'Hamdan St'),(N'Al Salam St'),
(N'Olaya St'),(N'Madinah Rd'),(N'King Abdullah Rd'),
(N'Oxford St'),(N'Baker St'),(N'Rue de Rivoli'),(N'Unter den Linden'),
(N'Gran Via'),(N'Via Roma'),(N'George St'),(N'Collins St');

DECLARE @Cities TABLE (Id int IDENTITY(1,1) PRIMARY KEY, City nvarchar(80) NOT NULL, Country nvarchar(80) NOT NULL, PhonePrefix nvarchar(10) NOT NULL);
INSERT INTO @Cities (City, Country, PhonePrefix) VALUES
(N'Cairo',        N'Egypt',          N'+20'),
(N'Alexandria',   N'Egypt',          N'+20'),
(N'Giza',         N'Egypt',          N'+20'),
(N'Abu Dhabi',    N'United Arab Emirates', N'+971'),
(N'Dubai',        N'United Arab Emirates', N'+971'),
(N'Riyadh',       N'Saudi Arabia',   N'+966'),
(N'Jeddah',       N'Saudi Arabia',   N'+966'),
(N'Amman',        N'Jordan',         N'+962'),
(N'Beirut',       N'Lebanon',        N'+961'),
(N'Istanbul',     N'Turkey',         N'+90'),
(N'Athens',       N'Greece',         N'+30'),
(N'Rome',         N'Italy',          N'+39'),
(N'Milan',        N'Italy',          N'+39'),
(N'Paris',        N'France',         N'+33'),
(N'Berlin',       N'Germany',        N'+49'),
(N'London',       N'United Kingdom', N'+44'),
(N'Dublin',       N'Ireland',        N'+353'),
(N'Madrid',       N'Spain',          N'+34'),
(N'Casablanca',   N'Morocco',        N'+212'),
(N'Sydney',       N'Australia',      N'+61'),
(N'Melbourne',    N'Australia',      N'+61'),
(N'Perth',        N'Australia',      N'+61'),
(N'Toronto',      N'Canada',         N'+1'),
(N'New York',     N'United States',  N'+1');

DECLARE
    @fn_cnt int = (SELECT COUNT(*) FROM @FirstNames),
    @mn_cnt int = (SELECT COUNT(*) FROM @MiddleNames),
    @ln_cnt int = (SELECT COUNT(*) FROM @LastNames),
    @cs_cnt int = (SELECT COUNT(*) FROM @CompanyStems),
    @cx_cnt int = (SELECT COUNT(*) FROM @CompanySuffixes),
    @st_cnt int = (SELECT COUNT(*) FROM @StreetNames),
    @ct_cnt int = (SELECT COUNT(*) FROM @Cities);

/* =============================================================================
   Net-new Customers
   ============================================================================= */
;WITH tally AS (
    SELECT TOP (@netnew_customers)
           ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
    FROM sys.all_objects a
    CROSS JOIN sys.all_objects b
),
gen AS (
    SELECT
        t.n,
        ABS(CHECKSUM(CONCAT('NETNEW|CUST|', t.n))) AS H
    FROM tally t
),
pick AS (
    SELECT
        g.*,
        fn.Val AS FirstName,
        mn.Val AS MiddleName,
        ln.Val AS LastName,
        cs.Val AS CompanyStem,
        cx.Val AS CompanySuffix,
        ct.City,
        ct.Country,
        ct.PhonePrefix,
        st.Val AS StreetName
    FROM gen g
    JOIN @FirstNames fn ON fn.Id = (g.H % @fn_cnt) + 1
    JOIN @MiddleNames mn ON mn.Id = ((g.H / 7) % @mn_cnt) + 1
    JOIN @LastNames  ln ON ln.Id = ((g.H / 13) % @ln_cnt) + 1
    JOIN @CompanyStems cs ON cs.Id = ((g.H / 19) % @cs_cnt) + 1
    JOIN @CompanySuffixes cx ON cx.Id = ((g.H / 23) % @cx_cnt) + 1
    JOIN @Cities ct ON ct.Id = ((g.H / 29) % @ct_cnt) + 1
    JOIN @StreetNames st ON st.Id = ((g.H / 31) % @st_cnt) + 1
),
final AS (
    SELECT
        -- Use a non-overlapping number range to avoid collisions with 004 (which uses CUST-000000..)
        CONCAT('CUSTX-', RIGHT(CONCAT('000000', CAST(700000 + (p.H % 200000) AS varchar(6))), 6)) AS LegacyCustomerNo,

        -- Company name with controlled casing noise
        CASE (p.H % 3)
            WHEN 0 THEN CONCAT(p.CompanyStem, ' ', p.CompanySuffix)
            WHEN 1 THEN CONCAT(UPPER(p.CompanyStem), ' ', p.CompanySuffix)
            ELSE      CONCAT(p.CompanyStem, ' ', p.CompanySuffix, '  ')
        END AS Company,

        -- Names with controlled whitespace/casing noise
        CASE WHEN (p.H % 4) = 0 THEN UPPER(p.FirstName) ELSE p.FirstName END AS ContactFirstName,
        NULLIF(LTRIM(RTRIM(
            CASE
                WHEN (p.H % 5) = 0 THEN ''                 -- sometimes missing middle name
                WHEN (p.H % 5) = 1 THEN CONCAT(' ', p.MiddleName, ' ') -- padded
                ELSE p.MiddleName
            END
        )), '') AS ContactMiddleName,
        CASE WHEN (p.H % 6) = 0 THEN LOWER(p.LastName) ELSE p.LastName END AS ContactLastName,

        -- City/country
        CASE WHEN (p.H % 2) = 0 THEN p.City ELSE UPPER(p.City) END AS City,
        p.Country AS Country,

        -- Postal code (plausible: 4-6 digits depending on country, deterministic)
        CASE
            WHEN p.Country = 'Egypt' THEN RIGHT(CONCAT('00000', CAST(10000 + (p.H % 89999) AS varchar(5))), 5)
            WHEN p.Country = 'Australia' THEN RIGHT(CONCAT('0000',  CAST(2000  + (p.H % 6999)  AS varchar(4))), 4)
            WHEN p.Country IN ('United States','Canada') THEN RIGHT(CONCAT('00000', CAST(10000 + (p.H % 89999) AS varchar(5))), 5)
            ELSE RIGHT(CONCAT('00000', CAST(10000 + (p.H % 89999) AS varchar(5))), 5)
        END AS PostalCode,

        -- Street
        CONCAT(CAST(1 + (p.H % 320) AS varchar(3)), ' ', p.StreetName, ' ',
               CASE (p.H % 4) WHEN 0 THEN 'St' WHEN 1 THEN 'Rd' WHEN 2 THEN 'Ave' ELSE 'Blvd' END) AS Street,

        -- Phone (deterministic, with occasional formatting noise)
        CASE
            WHEN (p.H % 4) = 0 THEN CONCAT(p.PhonePrefix, ' ', CAST(5000000 + (p.H % 4999999) AS varchar(10)))
            WHEN (p.H % 4) = 1 THEN CONCAT(p.PhonePrefix, '-', CAST(5000000 + (p.H % 4999999) AS varchar(10)))
            ELSE CONCAT(p.PhonePrefix, CAST(5000000 + (p.H % 4999999) AS varchar(10)))
        END AS Phone,

        -- Email (sometimes missing or slightly messy)
        CASE
            WHEN (p.H % 20) = 0 THEN NULL -- missing email (realistic)
            WHEN (p.H % 20) = 1 THEN CONCAT(LOWER(p.FirstName), '.', LOWER(p.LastName), '@', REPLACE(LOWER(p.CompanyStem), ' ', ''), '.com ')
            ELSE CONCAT(LOWER(p.FirstName), '.', LOWER(p.LastName), '@', REPLACE(LOWER(p.CompanyStem), ' ', ''), '.com')
        END AS Email
    FROM pick p
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
    f.LegacyCustomerNo,
    f.Company,
    f.ContactFirstName,
    f.ContactMiddleName,
    f.ContactLastName,
    f.City,
    f.Country,
    f.PostalCode,
    f.Street,
    f.Phone,
    f.Email
FROM final f
WHERE NOT EXISTS (SELECT 1 FROM dbo.CustomersExport x WHERE x.LegacyCustomerNo = f.LegacyCustomerNo);
-- (no GO here; keep variables/table variables in scope)

/* =============================================================================
   Net-new Vendors
   ============================================================================= */
;WITH tally AS (
    SELECT TOP (@netnew_vendors)
           ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
    FROM sys.all_objects a
    CROSS JOIN sys.all_objects b
),
gen AS (
    SELECT
        t.n,
        ABS(CHECKSUM(CONCAT('NETNEW|VEND|', t.n))) AS H
    FROM tally t
),
pick AS (
    SELECT
        g.*,
        fn.Val AS FirstName,
        mn.Val AS MiddleName,
        ln.Val AS LastName,
        cs.Val AS CompanyStem,
        cx.Val AS CompanySuffix,
        ct.City,
        ct.Country,
        ct.PhonePrefix,
        st.Val AS StreetName
    FROM gen g
    JOIN @FirstNames fn ON fn.Id = (g.H % @fn_cnt) + 1
    JOIN @MiddleNames mn ON mn.Id = ((g.H / 5) % @mn_cnt) + 1
    JOIN @LastNames  ln ON ln.Id = ((g.H / 11) % @ln_cnt) + 1
    JOIN @CompanyStems cs ON cs.Id = ((g.H / 17) % @cs_cnt) + 1
    JOIN @CompanySuffixes cx ON cx.Id = ((g.H / 19) % @cx_cnt) + 1
    JOIN @Cities ct ON ct.Id = ((g.H / 23) % @ct_cnt) + 1
    JOIN @StreetNames st ON st.Id = ((g.H / 29) % @st_cnt) + 1
),
final AS (
    SELECT
        CONCAT('VENDX-', RIGHT(CONCAT('000000', CAST(800000 + (p.H % 150000) AS varchar(6))), 6)) AS LegacyVendorNo,

        CASE (p.H % 3)
            WHEN 0 THEN CONCAT(p.CompanyStem, ' ', p.CompanySuffix)
            WHEN 1 THEN CONCAT(p.CompanyStem, ' Supplies ', p.CompanySuffix)
            ELSE      CONCAT(p.CompanyStem, ' Trading ', p.CompanySuffix)
        END AS VendorName,

        CASE WHEN (p.H % 4) = 0 THEN UPPER(p.FirstName) ELSE p.FirstName END AS ContactFirstName,
        NULLIF(LTRIM(RTRIM(
            CASE
                WHEN (p.H % 6) = 0 THEN '' 
                ELSE p.MiddleName
            END
        )), '') AS ContactMiddleName,
        CASE WHEN (p.H % 6) = 0 THEN LOWER(p.LastName) ELSE p.LastName END AS ContactLastName,

        CASE WHEN (p.H % 2) = 0 THEN p.City ELSE UPPER(p.City) END AS City,
        p.Country AS Country,

        CASE
            WHEN p.Country = 'Egypt' THEN RIGHT(CONCAT('00000', CAST(10000 + (p.H % 89999) AS varchar(5))), 5)
            WHEN p.Country = 'Australia' THEN RIGHT(CONCAT('0000',  CAST(2000  + (p.H % 6999)  AS varchar(4))), 4)
            WHEN p.Country IN ('United States','Canada') THEN RIGHT(CONCAT('00000', CAST(10000 + (p.H % 89999) AS varchar(5))), 5)
            ELSE RIGHT(CONCAT('00000', CAST(10000 + (p.H % 89999) AS varchar(5))), 5)
        END AS PostalCode,

        CONCAT(CAST(1 + (p.H % 520) AS varchar(3)), ' ', p.StreetName, ' ',
               CASE (p.H % 4) WHEN 0 THEN 'St' WHEN 1 THEN 'Rd' WHEN 2 THEN 'Ave' ELSE 'Blvd' END) AS Street,

        CASE
            WHEN (p.H % 4) = 0 THEN CONCAT(p.PhonePrefix, ' ', CAST(6000000 + (p.H % 3999999) AS varchar(10)))
            WHEN (p.H % 4) = 1 THEN CONCAT(p.PhonePrefix, '-', CAST(6000000 + (p.H % 3999999) AS varchar(10)))
            ELSE CONCAT(p.PhonePrefix, CAST(6000000 + (p.H % 3999999) AS varchar(10)))
        END AS Phone,

        CASE
            WHEN (p.H % 25) = 0 THEN NULL
            WHEN (p.H % 25) = 1 THEN CONCAT(LOWER(p.FirstName), '.', LOWER(p.LastName), '@', REPLACE(LOWER(p.CompanyStem), ' ', ''), '.net ')
            ELSE CONCAT(LOWER(p.FirstName), '.', LOWER(p.LastName), '@', REPLACE(LOWER(p.CompanyStem), ' ', ''), '.net')
        END AS Email
    FROM pick p
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
    f.LegacyVendorNo,
    f.VendorName,
    f.ContactFirstName,
    f.ContactMiddleName,
    f.ContactLastName,
    f.City,
    f.Country,
    f.PostalCode,
    f.Street,
    f.Phone,
    f.Email
FROM final f
WHERE NOT EXISTS (SELECT 1 FROM dbo.VendorsExport x WHERE x.LegacyVendorNo = f.LegacyVendorNo);
-- (no GO here; keep variables/table variables in scope)

PRINT CONCAT('005 complete. Inserted net-new Customers: ', @netnew_customers, ', net-new Vendors: ', @netnew_vendors, '.');