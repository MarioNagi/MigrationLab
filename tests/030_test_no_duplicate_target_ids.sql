USE MigrationLab;
GO

SET NOCOUNT ON;

/*
Test
----
Final target IDs must be unique. A duplicate CustomerNumber or
VendorNumber means survivorship leaked the same canonical record twice.
*/

DECLARE @cust_dupes INT = (
    SELECT COUNT(*) FROM (
        SELECT CustomerNumber
        FROM target_sap_ecc.CustomerMaster
        GROUP BY CustomerNumber
        HAVING COUNT(*) > 1
    ) d
);

DECLARE @vend_dupes INT = (
    SELECT COUNT(*) FROM (
        SELECT VendorNumber
        FROM target_sap_ecc.VendorMaster
        GROUP BY VendorNumber
        HAVING COUNT(*) > 1
    ) d
);

IF @cust_dupes > 0 OR @vend_dupes > 0
BEGIN
    PRINT CONCAT('Duplicate CustomerNumber count: ', @cust_dupes);
    PRINT CONCAT('Duplicate VendorNumber   count: ', @vend_dupes);
    THROW 60030, 'FAIL: duplicate IDs in target_sap_ecc.', 1;
END;

PRINT 'PASS: 030_test_no_duplicate_target_ids';
GO
