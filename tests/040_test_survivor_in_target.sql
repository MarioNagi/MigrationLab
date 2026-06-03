USE MigrationLab;
GO

SET NOCOUNT ON;

/*
Test
----
Every non-rejected source record in the crosswalk must resolve to an
existing target_model row. Duplicate source records that lost survivorship
are allowed to be absent from the loaded-record count only when they have
an etl.RejectLog row.
*/

DECLARE @cust_missing INT = (
    SELECT COUNT(*)
    FROM work_otc.CustomersCrosswalk cw
    LEFT JOIN target_model.Customers t ON t.CustomerID = cw.TargetCustomerID
    WHERE NOT EXISTS (
        SELECT 1
        FROM etl.RejectLog r
        WHERE r.EntityType = 'Customer'
          AND r.SourceSystem = cw.SourceSystem
          AND r.SourceID = cw.SourceID
    )
      AND (cw.TargetCustomerID IS NULL OR t.CustomerID IS NULL)
);

DECLARE @vend_missing INT = (
    SELECT COUNT(*)
    FROM work_ptp.VendorsCrosswalk cw
    LEFT JOIN target_model.Vendors t ON t.VendorID = cw.TargetVendorID
    WHERE NOT EXISTS (
        SELECT 1
        FROM etl.RejectLog r
        WHERE r.EntityType = 'Vendor'
          AND r.SourceSystem = cw.SourceSystem
          AND r.SourceID = cw.SourceID
    )
      AND (cw.TargetVendorID IS NULL OR t.VendorID IS NULL)
);

IF @cust_missing > 0 OR @vend_missing > 0
BEGIN
    PRINT CONCAT('Customer non-rejected crosswalk rows missing target_model row: ', @cust_missing);
    PRINT CONCAT('Vendor   non-rejected crosswalk rows missing target_model row: ', @vend_missing);
    THROW 60040, 'FAIL: non-rejected crosswalk rows did not reach target_model.', 1;
END;

PRINT 'PASS: 040_test_survivor_in_target';
GO
