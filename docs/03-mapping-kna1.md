# Mapping – Customer (KNA1-style)

This document describes how customer-related source attributes map into the lab target model.

> Note: We avoid vendor-specific naming in schemas/table names. The “KNA1” label is used only as a conceptual reference.

## Sources

### Northwind (`source_northwind.Customers`)
- `CustomerID` (natural key)
- `CompanyName`
- `ContactName` (single string)
- `Address`, `City`, `Region`, `PostalCode`, `Country`, `Phone`, `Fax`

### CsvRaw (`source_csv.CustomersExport`)
- `LegacyCustomerNo`
- `Company`
- `ContactFirstName`, `ContactMiddleName`, `ContactLastName`
- `Street`, `City`, `PostalCode`, `Country`, `Phone`, `Email`

## Target model

### `target_model.Customer`
Canonical, deduplicated customer record.

Recommended canonical fields (example):
- `CustomerNaturalKey` (generated)
- `CompanyName`
- `ContactFullName`
- `ContactFirstName`, `ContactMiddleName`, `ContactLastName`
- `Email`
- `Phone`
- `Street`, `City`, `PostalCode`, `Country`
- `SourceLineage` (e.g., `northwind|csv|both`)

## Key transformation logic

### Name handling (reversible)
- Northwind → split `ContactName` into first/middle/last
- CSV → rebuild `ContactFullName` from first/middle/last

### Matching keys (work layer)
- Email
- Phone
- Normalized name + city

### Survivorship examples
- Prefer Email from CSV when available
- Prefer CompanyName from Northwind when CSV company is missing or noisy
- Prefer most complete address

## Crosswalk
The work layer should produce a crosswalk of source identifiers → canonical customer key.
