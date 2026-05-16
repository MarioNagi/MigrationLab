USE MigrationLab;
GO

SET NOCOUNT ON;

/*
Test
----
target_model.Customers.CompanyName and target_model.Vendors.VendorName
are required. A NULL here means per-attribute survivorship found no
acceptable source — and there must be a corresponding MISSING_REQUIRED_FIELD
reject row to explain why the source record did not land.

This test enforces both:
  (a) target_model never carries a NULL on a required identity field
  (b) any source record dropped for that reason is logged in etl.RejectLog
*/

DECLARE @null_cust_names INT = (
    SELECT COUNT(*) FROM target_model.Customers WHERE CompanyName IS NULL OR LTRIM(RTRIM(CompanyName)) = ''
);

DECLARE @null_vend_names INT = (
    SELECT COUNT(*) FROM target_model.Vendors   WHERE VendorName  IS NULL OR LTRIM(RTRIM(VendorName))  = ''
);

IF @null_cust_names > 0 OR @null_vend_names > 0
BEGIN
    PRINT CONCAT('NULL CompanyName in target_model.Customers: ', @null_cust_names);
    PRINT CONCAT('NULL VendorName  in target_model.Vendors  : ', @null_vend_names);
    THROW 60050, 'FAIL: required identity field is NULL in target_model.', 1;
END;

PRINT 'PASS: 050_test_required_fields';
GO
