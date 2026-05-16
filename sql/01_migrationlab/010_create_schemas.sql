USE MigrationLab;
GO

-- Core schemas
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'source_northwind') EXEC('CREATE SCHEMA source_northwind');
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'source_csv')       EXEC('CREATE SCHEMA source_csv');

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'work_otc')         EXEC('CREATE SCHEMA work_otc');
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'work_ptp')         EXEC('CREATE SCHEMA work_ptp');

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'target_model')     EXEC('CREATE SCHEMA target_model');

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'target_sap_ecc')   EXEC('CREATE SCHEMA target_sap_ecc');
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'target_snapshot_sap_ecc') EXEC('CREATE SCHEMA target_snapshot_sap_ecc');

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'reporting')        EXEC('CREATE SCHEMA reporting');
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'reference')        EXEC('CREATE SCHEMA reference');
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'etl')              EXEC('CREATE SCHEMA etl');
GO
