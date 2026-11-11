# Bulk / Large Order Bundle Production Implementation Plan

Add a dedicated **Bulk / Large Order Bundle Production** feature to the Production module to manage wholesale and large customer orders.

## User Review Required

> [!IMPORTANT]
> This plan introduces a dual view in the Production tab: **Standard Batches** (individual bottle sizes) and **Bulk / Large Order Bundles** (grouped wholesale/corporate orders with custom item breakdowns).

## Proposed Changes

### [Production Module]
#### [MODIFY] [production_page.dart](file:///C:/Users/DeLL/Desktop/honeybee_center/lib/pages/production_page.dart)
- Add a view toggle between **Standard Batches** and **Bulk / Large Order Bundles**.
- Add an **Add Bulk / Bundle Order** dialog allowing production managers to record wholesale/bundle orders with:
  - Customer / Wholesale Buyer Name
  - Bundle / Package Title
  - Items & Breakdown (e.g. `50x 250g Pukyutan + 50x 500g Mellifera`)
  - Total Quantity
  - Target Production Date
- Update the production data table to display bulk bundle orders with status badges and customer details.

## Verification Plan

### Automated Tests
- Run `flutter analyze` to ensure zero compilation or syntax errors.

### Manual Verification
- Verify switching between Standard Batches and Bulk / Large Order Bundles.
- Verify scheduling a new bundle order and confirming it saves correctly to Firebase RTDB.
