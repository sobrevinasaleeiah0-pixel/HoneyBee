# HoneyBee StockTrack Admin Dashboard Implementation Plan

This plan outlines the steps to transform the existing HoneyBee StockTrack Flutter Web project into a comprehensive Admin Web Dashboard with sidebar navigation and multiple functional modules integrated with Firebase Realtime Database.

## User Review Required

> [!IMPORTANT]
> The implementation will use Firebase Realtime Database (RTDB) as requested. No Firestore will be used.
> Co-Admin account creation will be implemented as a client-side simulation for the prototype, as a full backend Admin SDK implementation requires a secure server environment or Cloud Functions.

## Proposed Changes

### [Component Name] Data Layer & Services

#### [NEW] [database_service.dart](file:///C:/Users/DeLL/Desktop/honeybee_center/lib/services/database_service.dart)
Create a service to handle all Realtime Database operations (Products, Production, Inventory, Orders, Sales, Suppliers, etc.).

### [Component Name] UI Layer - Main Navigation

#### [MODIFY] [main.dart](file:///C:/Users/DeLL/Desktop/honeybee_center/lib/main.dart)
Update theme to be consistent with the new dashboard design.

#### [MODIFY] [login_page.dart](file:///C:/Users/DeLL/Desktop/honeybee_center/lib/pages/login_page.dart)
Update redirection logic to use the new `MainDashboardPage`.

#### [NEW] [main_dashboard.dart](file:///C:/Users/DeLL/Desktop/honeybee_center/lib/pages/main_dashboard.dart)
Create the main container with the sidebar navigation as specified.

### [Component Name] Dashboard Modules

#### [NEW] [dashboard_page.dart](file:///C:/Users/DeLL/Desktop/honeybee_center/lib/pages/dashboard_page.dart)
Summary cards and activity overview.

#### [NEW] [products_page.dart](file:///C:/Users/DeLL/Desktop/honeybee_center/lib/pages/products_page.dart)
Manage honey varieties, bottle sizes, and pricing.

#### [NEW] [production_page.dart](file:///C:/Users/DeLL/Desktop/honeybee_center/lib/pages/production_page.dart)
Record and monitor manual bottling production.

#### [NEW] [inventory_page.dart](file:///C:/Users/DeLL/Desktop/honeybee_center/lib/pages/inventory_page.dart)
Comprehensive inventory management with sub-tabs (Overview, Scan, Results, History, Bottle Sizes).

#### [NEW] [orders_page.dart](file:///C:/Users/DeLL/Desktop/honeybee_center/lib/pages/orders_page.dart)
Customer order management and status tracking.

#### [NEW] [sales_page.dart](file:///C:/Users/DeLL/Desktop/honeybee_center/lib/pages/sales_page.dart)
Sales history and statistics.

#### [NEW] [suppliers_page.dart](file:///C:/Users/DeLL/Desktop/honeybee_center/lib/pages/suppliers_page.dart)
Supplier information and delivery records.

#### [NEW] [reports_page.dart](file:///C:/Users/DeLL/Desktop/honeybee_center/lib/pages/reports_page.dart)
Various business reports with filtering.

#### [MODIFY] [manage_co_admin_page.dart](file:///C:/Users/DeLL/Desktop/honeybee_center/lib/pages/manage_co_admin_page.dart)
Refactor to fit within the new dashboard structure and use the `AuthService` consistently.

#### [NEW] [settings_page.dart](file:///C:/Users/DeLL/Desktop/honeybee_center/lib/pages/settings_page.dart)
Admin profile and system settings.

## Verification Plan

### Automated Tests
- Run `flutter analyze` to ensure no syntax errors.
- Run `flutter test` (if applicable) to verify core logic.

### Manual Verification
1.  **Login**: Verify that Admin and Co-Admin are redirected to the new `MainDashboardPage`.
2.  **Navigation**: Test all sidebar tabs and ensure role-based access control (Manage Accounts hidden for Co-Admins).
3.  **Inventory Scan**: Simulate an inventory scan and verify that RTDB is updated and low-stock alerts are generated.
4.  **Data Management**: Add/Edit products, production records, and suppliers to verify database persistence.
5.  **Reports**: Check that reports accurately reflect the data in RTDB.
