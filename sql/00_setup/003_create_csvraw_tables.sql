USE CsvRaw;
GO

IF OBJECT_ID('dbo.CustomersExport','U') IS NOT NULL DROP TABLE dbo.CustomersExport;
IF OBJECT_ID('dbo.VendorsExport','U') IS NOT NULL DROP TABLE dbo.VendorsExport;
GO

CREATE TABLE dbo.CustomersExport (
    LegacyCustomerNo     VARCHAR(30)    NOT NULL,
    Company              NVARCHAR(100)   NULL,

    ContactFirstName     NVARCHAR(50)    NULL,
    ContactMiddleName    NVARCHAR(100)   NULL,
    ContactLastName      NVARCHAR(50)    NULL,

    City                 NVARCHAR(50)    NULL,
    Country              NVARCHAR(50)    NULL,
    PostalCode           NVARCHAR(20)    NULL,
    Street               NVARCHAR(120)   NULL,
    Phone                NVARCHAR(50)    NULL,
    Email                NVARCHAR(150)   NULL
);

CREATE TABLE dbo.VendorsExport (
    LegacyVendorNo       VARCHAR(30)    NOT NULL,
    VendorName           NVARCHAR(100)  NULL,

    ContactFirstName     NVARCHAR(50)   NULL,
    ContactMiddleName    NVARCHAR(100)  NULL,
    ContactLastName      NVARCHAR(50)   NULL,

    City                 NVARCHAR(50)   NULL,
    Country              NVARCHAR(50)   NULL,
    PostalCode           NVARCHAR(20)   NULL,
    Street               NVARCHAR(120)  NULL,
    Phone                NVARCHAR(50)   NULL,
    Email                NVARCHAR(150)  NULL
);
GO
