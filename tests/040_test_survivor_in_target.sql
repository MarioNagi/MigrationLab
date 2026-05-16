USE MigrationLab;
GO

SET NOCOUNT ON;

/*
Test
----
Every match-group survivor in the work layer must produce exactly one
target_model row. A missing survivor means survivorship was computed but
the target build dropped it.
*/

DECLARE @cust_missing INT = (
    SELECT COUNT(*)
    FROM work_otc.CustomersSurvivorship s
    LEFT JOIN target_model.Customers t
        ON t.CustomerID = CONCAT('CUST-', s.WorkCustomerID)
    WHERE t.CustomerID IS NULL
);

DECLARE @vend_missing INT = (
    SELECT COUNT(*)
    FROM work_ptp.VendorsSurvivorship s
    LEFT JOIN target_model.Vendors t
        ON t.VendorID = CONCAT('VEND-', s.WorkVendorID)
    WHERE t.VendorID IS NULL
);

/*
Note: this test assumes the target_model build keys on the survivor's
WorkCustomerID / WorkVendorID with a 'CUST-' / 'VEND-' prefix. If the
target_model build proc changes its ID convention, update the JOIN above
or re-key this test off the crosswalk table.
*/

IF @cust_missing > 0 OR @vend_missing > 0
BEGIN
    PRINT CONCAT('Customer survivors missing from target_model: ', @cust_missing);
    PRINT CONCAT('Vendor   survivors missing from target_model: ', @vend_missing);
    THROW 60040, 'FAIL: match-group survivors did not reach target_model.', 1;
END;

PRINT 'PASS: 040_test_survivor_in_target';
GO
