USE MigrationLab;
GO

/*
File
----
sql/01_migrationlab/030_create_ref_tables.sql

Purpose
-------
Create reference/lookup tables used throughout the migration process.
These tables support data normalization, matching, and quality rules.

Design principles
-----------------
- Reference data is static (manually maintained or seeded once)
- Used for normalization (country codes, data quality rules)
- Supports match key generation and deduplication logic
- Small, fast lookup tables with indexes

Reference tables
----------------
- reference.CountryCodes: Normalize country name variations to standard codes
- reference.MatchRules: Configuration for match key generation strategies

Assumptions
-----------
- Schema 'reference' already exists (created by 010_create_schemas.sql)
*/

SET NOCOUNT ON;

-- Safety check
IF DB_NAME() <> 'MigrationLab'
BEGIN
    THROW 50000, 'This script must be executed in the MigrationLab database context.', 1;
END;

-- Verify schema exists
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'reference')
    THROW 50001, 'Missing schema reference. Run 010_create_schemas.sql first.', 1;

PRINT 'Creating reference tables...';
GO

/* =============================================================================
   reference.CountryCodes: Normalize country name variations
   ============================================================================= */

IF OBJECT_ID('reference.CountryCodes','U') IS NOT NULL DROP TABLE reference.CountryCodes;
GO

CREATE TABLE reference.CountryCodes (
    CountryCode        CHAR(2)         NOT NULL,  -- ISO 3166-1 alpha-2 (e.g., 'US', 'GB', 'DE')
    CountryNameStandard NVARCHAR(100)  NOT NULL,  -- Standardized country name
    CountryNameVariant  NVARCHAR(100)  NOT NULL,  -- Variant name found in source data
    IsPrimary           BIT             NOT NULL DEFAULT 0,  -- 1 = primary mapping, 0 = alias
    
    CONSTRAINT PK_reference_CountryCodes PRIMARY KEY CLUSTERED (CountryCode, CountryNameVariant)
);
GO

-- Seed country code normalization data
-- Handles common variations: USA/US/United States, UK/GB/United Kingdom, etc.
INSERT INTO reference.CountryCodes (CountryCode, CountryNameStandard, CountryNameVariant, IsPrimary)
VALUES
    -- United States
    ('US', 'United States', 'United States', 1),
    ('US', 'United States', 'USA', 0),
    ('US', 'United States', 'US', 0),
    ('US', 'United States', 'U.S.A.', 0),
    ('US', 'United States', 'U.S.', 0),
    
    -- United Kingdom
    ('GB', 'United Kingdom', 'United Kingdom', 1),
    ('GB', 'United Kingdom', 'UK', 0),
    ('GB', 'United Kingdom', 'GB', 0),
    ('GB', 'United Kingdom', 'U.K.', 0),
    ('GB', 'United Kingdom', 'Great Britain', 0),
    
    -- Germany
    ('DE', 'Germany', 'Germany', 1),
    ('DE', 'Germany', 'DE', 0),
    ('DE', 'Germany', 'Deutschland', 0),
    
    -- France
    ('FR', 'France', 'France', 1),
    ('FR', 'France', 'FR', 0),
    
    -- Canada
    ('CA', 'Canada', 'Canada', 1),
    ('CA', 'Canada', 'CA', 0),
    
    -- Australia
    ('AU', 'Australia', 'Australia', 1),
    ('AU', 'Australia', 'AU', 0),
    
    -- Brazil
    ('BR', 'Brazil', 'Brazil', 1),
    ('BR', 'Brazil', 'BR', 0),
    ('BR', 'Brazil', 'Brasil', 0),
    
    -- Mexico
    ('MX', 'Mexico', 'Mexico', 1),
    ('MX', 'Mexico', 'MX', 0),
    
    -- Spain
    ('ES', 'Spain', 'Spain', 1),
    ('ES', 'Spain', 'ES', 0),
    ('ES', 'Spain', 'España', 0),
    
    -- Italy
    ('IT', 'Italy', 'Italy', 1),
    ('IT', 'Italy', 'IT', 0),
    ('IT', 'Italy', 'Italia', 0),
    
    -- Netherlands
    ('NL', 'Netherlands', 'Netherlands', 1),
    ('NL', 'Netherlands', 'NL', 0),
    ('NL', 'Netherlands', 'Holland', 0),
    
    -- Belgium
    ('BE', 'Belgium', 'Belgium', 1),
    ('BE', 'Belgium', 'BE', 0),
    
    -- Switzerland
    ('CH', 'Switzerland', 'Switzerland', 1),
    ('CH', 'Switzerland', 'CH', 0),
    ('CH', 'Switzerland', 'Schweiz', 0),
    
    -- Sweden
    ('SE', 'Sweden', 'Sweden', 1),
    ('SE', 'Sweden', 'SE', 0),
    
    -- Norway
    ('NO', 'Norway', 'Norway', 1),
    ('NO', 'Norway', 'NO', 0),
    
    -- Denmark
    ('DK', 'Denmark', 'Denmark', 1),
    ('DK', 'Denmark', 'DK', 0),
    
    -- Finland
    ('FI', 'Finland', 'Finland', 1),
    ('FI', 'Finland', 'FI', 0),
    
    -- Poland
    ('PL', 'Poland', 'Poland', 1),
    ('PL', 'Poland', 'PL', 0),
    
    -- Japan
    ('JP', 'Japan', 'Japan', 1),
    ('JP', 'Japan', 'JP', 0),
    
    -- China
    ('CN', 'China', 'China', 1),
    ('CN', 'China', 'CN', 0),
    ('CN', 'China', 'People''s Republic of China', 0),
    
    -- India
    ('IN', 'India', 'India', 1),
    ('IN', 'India', 'IN', 0),
    
    -- Argentina
    ('AR', 'Argentina', 'Argentina', 1),
    ('AR', 'Argentina', 'AR', 0),
    
    -- Chile
    ('CL', 'Chile', 'Chile', 1),
    ('CL', 'Chile', 'CL', 0),
    
    -- South Africa
    ('ZA', 'South Africa', 'South Africa', 1),
    ('ZA', 'South Africa', 'ZA', 0),
    
    -- New Zealand
    ('NZ', 'New Zealand', 'New Zealand', 1),
    ('NZ', 'New Zealand', 'NZ', 0),
    
    -- Ireland
    ('IE', 'Ireland', 'Ireland', 1),
    ('IE', 'Ireland', 'IE', 0),
    
    -- Portugal
    ('PT', 'Portugal', 'Portugal', 1),
    ('PT', 'Portugal', 'PT', 0),
    
    -- Greece
    ('GR', 'Greece', 'Greece', 1),
    ('GR', 'Greece', 'GR', 0),
    
    -- Turkey
    ('TR', 'Turkey', 'Turkey', 1),
    ('TR', 'Turkey', 'TR', 0),
    
    -- Russia
    ('RU', 'Russia', 'Russia', 1),
    ('RU', 'Russia', 'RU', 0),
    ('RU', 'Russia', 'Russian Federation', 0),
    
    -- South Korea
    ('KR', 'South Korea', 'South Korea', 1),
    ('KR', 'South Korea', 'KR', 0),
    ('KR', 'South Korea', 'Korea', 0),
    
    -- Singapore
    ('SG', 'Singapore', 'Singapore', 1),
    ('SG', 'Singapore', 'SG', 0),
    
    -- Hong Kong
    ('HK', 'Hong Kong', 'Hong Kong', 1),
    ('HK', 'Hong Kong', 'HK', 0),
    
    -- Taiwan
    ('TW', 'Taiwan', 'Taiwan', 1),
    ('TW', 'Taiwan', 'TW', 0),
    
    -- Thailand
    ('TH', 'Thailand', 'Thailand', 1),
    ('TH', 'Thailand', 'TH', 0),
    
    -- Indonesia
    ('ID', 'Indonesia', 'Indonesia', 1),
    ('ID', 'Indonesia', 'ID', 0),
    
    -- Malaysia
    ('MY', 'Malaysia', 'Malaysia', 1),
    ('MY', 'Malaysia', 'MY', 0),
    
    -- Philippines
    ('PH', 'Philippines', 'Philippines', 1),
    ('PH', 'Philippines', 'PH', 0),
    
    -- Vietnam
    ('VN', 'Vietnam', 'Vietnam', 1),
    ('VN', 'Vietnam', 'VN', 0),
    
    -- Egypt
    ('EG', 'Egypt', 'Egypt', 1),
    ('EG', 'Egypt', 'EG', 0),
    
    -- Saudi Arabia
    ('SA', 'Saudi Arabia', 'Saudi Arabia', 1),
    ('SA', 'Saudi Arabia', 'SA', 0),
    
    -- UAE
    ('AE', 'United Arab Emirates', 'United Arab Emirates', 1),
    ('AE', 'United Arab Emirates', 'UAE', 0),
    ('AE', 'United Arab Emirates', 'AE', 0),
    
    -- Israel
    ('IL', 'Israel', 'Israel', 1),
    ('IL', 'Israel', 'IL', 0),
    
    -- Czech Republic
    ('CZ', 'Czech Republic', 'Czech Republic', 1),
    ('CZ', 'Czech Republic', 'CZ', 0),
    
    -- Hungary
    ('HU', 'Hungary', 'Hungary', 1),
    ('HU', 'Hungary', 'HU', 0),
    
    -- Romania
    ('RO', 'Romania', 'Romania', 1),
    ('RO', 'Romania', 'RO', 0),
    
    -- Default/Unknown (for unmapped countries)
    ('XX', 'Unknown', 'Unknown', 1),
    ('XX', 'Unknown', '', 0),
    ('XX', 'Unknown', NULL, 0);
GO

-- Index for fast lookup by variant name
CREATE NONCLUSTERED INDEX IX_reference_CountryCodes_Variant 
    ON reference.CountryCodes(CountryNameVariant);
GO

-- Index for lookup by standard code
CREATE NONCLUSTERED INDEX IX_reference_CountryCodes_Code 
    ON reference.CountryCodes(CountryCode) 
    WHERE IsPrimary = 1;
GO

/* =============================================================================
   reference.MatchRules: Configuration for match key generation
   ============================================================================= */

IF OBJECT_ID('reference.MatchRules','U') IS NOT NULL DROP TABLE reference.MatchRules;
GO

CREATE TABLE reference.MatchRules (
    RuleID             INT             IDENTITY(1,1) NOT NULL,
    RuleName           VARCHAR(100)    NOT NULL,
    RuleDescription    NVARCHAR(500)    NULL,
    MatchKeyType       VARCHAR(50)     NOT NULL,  -- 'Email', 'Phone', 'NameCity', 'CompanyCity'
    IsActive           BIT             NOT NULL DEFAULT 1,
    Priority           INT             NOT NULL DEFAULT 0,  -- Lower number = higher priority
    
    CONSTRAINT PK_reference_MatchRules PRIMARY KEY CLUSTERED (RuleID),
    CONSTRAINT UQ_reference_MatchRules_Name UNIQUE (RuleName)
);
GO

-- Seed match rules configuration
INSERT INTO reference.MatchRules (RuleName, RuleDescription, MatchKeyType, IsActive, Priority)
VALUES
    ('Email Match', 'Match on email address (highest confidence)', 'Email', 1, 1),
    ('Phone Match', 'Match on normalized phone number', 'Phone', 1, 2),
    ('Name + City Match', 'Match on contact name + city (for customers)', 'NameCity', 1, 3),
    ('Company + City Match', 'Match on company name + city', 'CompanyCity', 1, 4);
GO

-- Index for active rules ordered by priority
CREATE NONCLUSTERED INDEX IX_reference_MatchRules_ActivePriority 
    ON reference.MatchRules(IsActive, Priority) 
    WHERE IsActive = 1;
GO

PRINT 'Reference tables created successfully.';
PRINT '';
PRINT 'Summary:';
SELECT 
    'reference.CountryCodes' AS TableName,
    COUNT(*) AS RowCount
FROM reference.CountryCodes
UNION ALL
SELECT 
    'reference.MatchRules' AS TableName,
    COUNT(*) AS RowCount
FROM reference.MatchRules;
GO
