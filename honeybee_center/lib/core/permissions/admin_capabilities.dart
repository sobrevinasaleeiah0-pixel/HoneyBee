import '../../services/auth_service.dart';

/// Centralized, role-based permission map for the admin dashboard.
///
/// The database role strings ('main_admin', 'co_admin') are unchanged — this
/// layer only governs UI capabilities. Both roles can READ business data
/// (Supabase RLS already permits reads for any active admin); the flags below
/// control WRITE actions and the monitoring-vs-operations experience.
///
/// Account provisioning is intentionally NOT granted to either in-app role
/// ([canManageAccounts] is false for both). Provisioning is handled separately
/// (secure Edge Function) outside both dashboards.
class RoleCapabilities {
  const RoleCapabilities({
    required this.isMonitoringOnly,
    required this.canManageOrders,
    required this.canManageCatalog,
    required this.canManageSuppliers,
    required this.canAdjustStock,
    required this.canRunProduction,
    required this.canReplyMessages,
    required this.canConfirmPickup,
    required this.canManageAccounts,
  });

  /// Owner / Main Admin: oversight only, no routine operations.
  final bool isMonitoringOnly;

  /// Order status updates, payment verification, bulk-production action.
  final bool canManageOrders;

  /// Product & product-variant catalog management.
  final bool canManageCatalog;

  /// Supplier create/edit/delete.
  final bool canManageSuppliers;

  /// Inventory stock corrections (manual adjustments).
  final bool canAdjustStock;

  /// Production batch create/start/finish/archive.
  final bool canRunProduction;

  /// Reply to customer conversations / set conversation status.
  final bool canReplyMessages;

  /// Scan a QR and confirm a customer pickup.
  final bool canConfirmPickup;

  /// Administrator account provisioning. False for BOTH in-app roles.
  /// Drives the Manage Accounts route guard.
  final bool canManageAccounts;

  /// Owner / Main Admin — monitoring and oversight only.
  static const RoleCapabilities owner = RoleCapabilities(
    isMonitoringOnly: true,
    canManageOrders: false,
    canManageCatalog: false,
    canManageSuppliers: false,
    canAdjustStock: false,
    canRunProduction: false,
    canReplyMessages: false,
    canConfirmPickup: false,
    canManageAccounts: false,
  );

  /// Co-Admin / Store Manager — full daily operational control.
  static const RoleCapabilities coAdmin = RoleCapabilities(
    isMonitoringOnly: false,
    canManageOrders: true,
    canManageCatalog: true,
    canManageSuppliers: true,
    canAdjustStock: true,
    canRunProduction: true,
    canReplyMessages: true,
    canConfirmPickup: true,
    canManageAccounts: false,
  );

  /// Returns the capabilities for a resolved [UserRole].
  ///
  /// [UserRole] is validated (deny-by-default) at login via [tryParseAdminRole],
  /// so [role] is always one of the two known values when this is called.
  static RoleCapabilities forRole(UserRole role) =>
      role == UserRole.mainAdmin ? owner : coAdmin;
}
