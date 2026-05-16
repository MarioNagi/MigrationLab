# Mapping – Vendor (LFA1-style)

This document describes how vendor/supplier-related source attributes map into the lab target model.

> Note: We avoid vendor-specific naming in schemas/table names. The “LFA1” label is used only as a conceptual reference.

## Sources

### Northwind (`source_northwind.Suppliers`)
- `SupplierID` (natural key)
- `CompanyName`
- `ContactName` (single string)
- `Address`, `City`, `Region`, `PostalCode`, `Country`, `Phone`, `Fax`, `HomePage`

### CsvRaw (`source_csv.VendorsExport`)
- `LegacyVendorNo`
- `VendorName`
- `ContactFirstName`, `ContactMiddleName`, `ContactLastName`
- `Street`, `City`, `PostalCode`, `Country`, `Phone`, `Email`

## Target model

### `target_model.Vendor`
Canonical, deduplicated vendor record.

Recommended canonical fields (example):
- `VendorNaturalKey` (generated)
- `VendorName`
- `ContactFullName`
- `Email`
- `Phone`
- `Street`, `City`, `PostalCode`, `Country`
- `SourceLineage`

## Matching keys (work layer)
- Email
- Phone
- Normalized vendor name + city/country

## Survivorship examples
- Prefer Email from CSV when available
- Prefer VendorName from Northwind when CSV name is missing
- Keep HomePage when available (Northwind-only attribute)

## Crosswalk
Work layer should produce a crosswalk of source identifiers → canonical vendor key.
