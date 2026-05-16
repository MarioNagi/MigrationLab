USE MigrationLab;
GO

SET NOCOUNT ON;

/*
Test
----
Every crosswalk row must point at a canonical record that actually exists.
An orphan crosswalk row would mean we promised a source-to-target mapping
that the pipeline cannot honour.
*/

DECLARE @failures INT = 0;

DECLARE @cust_orphans INT = (
    SELECT COUNT(*)
    FROM work_otc.CustomersCrosswalk x
    LEFT JOIN work_otc.CustomersCanonical c ON x.WorkCustomerID = c.WorkCustomerID
    WHERE c.WorkCustomerID IS NULL
);

DECLARE @vend_orphans INT = (
    SELECT COUNT(*)
    FROM work_ptp.VendorsCrosswalk x
    LEFT JOIN work_ptp.VendorsCanonical v ON x.WorkVendorID = v.WorkVendorID
    WHERE v.WorkVendorID IS NULL
);

SET @failures = @cust_orphans + @vend_orphans;

IF @failures > 0
BEGIN
    PRINT CONCAT('Customer crosswalk orphans: ', @cust_orphans);
    PRINT CONCAT('Vendor   crosswalk orphans: ', @vend_orphans);
    THROW 60020, 'FAIL: orphan crosswalk rows detected.', 1;
END;

PRINT 'PASS: 020_test_no_orphan_crosswalk';
GO
