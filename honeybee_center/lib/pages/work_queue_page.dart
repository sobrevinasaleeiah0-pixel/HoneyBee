import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:rxdart/rxdart.dart';

import '../core/permissions/admin_capabilities.dart';
import '../core/theme/app_theme.dart';
import '../services/auth_service.dart';
import '../services/conversation_service.dart';
import '../services/database_service.dart';
import '../services/supabase_data_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// WorkQueuePage — Co-Admin daily task summary
//
// Aggregates five categories from existing services:
//   1. Orders Awaiting Action    (Supabase — ordersStream)
//   2. Messages Awaiting Reply   (Supabase — ConversationService.fetchInbox)
//   3. Low-Stock Products        (Supabase — productsStream + inventoryStream)
//   4. Production In Progress    (Firebase — production_batches RTDB node)
//   5. Pickups Awaiting QR Scan  (Supabase — ordersStream)
//
// No new database objects are created. All data comes from existing streams
// and fetch methods. Only Co-Admins see this page (coAdminOnly flag in nav).
// ─────────────────────────────────────────────────────────────────────────────

class WorkQueuePage extends StatefulWidget {
  final AuthSession session;

  /// Called when a category card is tapped — navigates to the relevant page.
  final void Function(int tabIndex) onNavigateTab;

  const WorkQueuePage({
    super.key,
    required this.session,
    required this.onNavigateTab,
  });

  @override
  State<WorkQueuePage> createState() => _WorkQueuePageState();
}

class _WorkQueuePageState extends State<WorkQueuePage> {
  final _supabaseData = SupabaseDataService();
  final _conversationService = ConversationService();
  final _dbService = DatabaseService();

  // Messages are fetched once and refreshed manually (no realtime stream
  // on the inbox shape — the messages stream is per-conversation only).
  List<Map<String, dynamic>> _inbox = [];
  bool _inboxLoading = true;
  String? _inboxError;

  @override
  void initState() {
    super.initState();
    assert(
      RoleCapabilities.forRole(widget.session.role).canManageOrders,
      'WorkQueuePage must only be used by Co-Admin role.',
    );
    _refreshAll();
  }

  Future<void> _refreshAll() async {
    _supabaseData.refreshAll().catchError(
      (e) => debugPrint('[WorkQueue] Supabase refresh: $e'),
    );
    setState(() {
      _inboxLoading = true;
      _inboxError = null;
    });
    try {
      final inbox = await _conversationService.fetchInbox();
      if (mounted) setState(() => _inbox = inbox);
    } catch (e) {
      if (mounted) setState(() => _inboxError = e.toString());
    } finally {
      if (mounted) setState(() => _inboxLoading = false);
    }
  }

  // ── Derived counts ──────────────────────────────────────────────────────────

  List<Map<String, dynamic>> _ordersAwaiting(
      List<Map<String, dynamic>> orders) {
    return orders
        .where((o) => ['Pending', 'Confirmed', 'Preparing']
            .contains(o['orderStatus']))
        .toList();
  }

  List<Map<String, dynamic>> _pickupsAwaiting(
      List<Map<String, dynamic>> orders) {
    return orders
        .where((o) =>
            o['orderStatus'] == 'Ready for Pickup' &&
            o['pickedUpAt'] == null &&
            (o['paymentStatus'] == 'Confirmed' ||
                o['paymentStatus'] == 'Paid'))
        .toList();
  }

  List<Map<String, dynamic>> _messagesAwaiting() {
    return _inbox
        .where((entry) =>
            entry['last_sender_role'] == 'customer' &&
            (entry['unread_count'] as num? ?? 0) > 0)
        .toList();
  }

  List<_LowStockItem> _lowStockItems(
    Map<String, dynamic> productsMap,
    Map<String, dynamic> inventoryMap,
  ) {
    final items = <_LowStockItem>[];
    productsMap.forEach((pId, pData) {
      if (pData is! Map) return;
      if (pData['isActive'] == false) return;
      final variants = pData['variants'] as Map? ?? {};
      variants.forEach((vId, vData) {
        if (vData is! Map) return;
        if (vData['isActive'] == false) return;
        final qty =
            (inventoryMap[pId] as Map? ?? {})[vId] is Map
                ? ((inventoryMap[pId] as Map)[vId]['quantity'] as num? ?? 0)
                    .toInt()
                : 0;
        final reorder = (vData['reorderLevel'] as num? ?? 10).toInt();
        if (qty <= reorder) {
          items.add(_LowStockItem(
            label: '${pData['variety'] ?? pData['name'] ?? 'Honey'} '
                '(${vData['size'] ?? '-'})',
            currentQty: qty,
            reorderLevel: reorder,
          ));
        }
      });
    });
    // Worst first (smallest qty / reorder ratio)
    items.sort((a, b) => a.currentQty.compareTo(b.currentQty));
    return items;
  }

  List<Map<String, dynamic>> _productionActive(
      List<Map<String, dynamic>> batches) {
    return batches
        .where((b) =>
            !((b['isArchived'] == true)) &&
            (b['status'] == 'In Progress' || b['status'] == 'Planned'))
        .toList();
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = AppTheme.textPrimary(isDark);
    final subColor = AppTheme.textSecondary(isDark);

    return Scaffold(
      backgroundColor: AppTheme.pageBackground(isDark),
      body: StreamBuilder<List<dynamic>>(
        stream: CombineLatestStream.list([
          _supabaseData.ordersStream,
          _supabaseData.productsStream,
          _supabaseData.inventoryStream,
          _dbService.getProductionBatchesStream(),
        ]),
        builder: (context, snap) {
          // Parse orders
          final orders = (snap.data?.isNotEmpty == true &&
                  snap.data![0] is List)
              ? (snap.data![0] as List).whereType<Map<String, dynamic>>().toList()
              : <Map<String, dynamic>>[];

          // Parse products + inventory
          final productsMap = snap.data != null && snap.data!.length > 1
              ? (snap.data![1] is Map
                  ? snap.data![1] as Map<String, dynamic>
                  : _supabaseData.currentProducts)
              : _supabaseData.currentProducts;
          final inventoryMap = snap.data != null && snap.data!.length > 2
              ? (snap.data![2] is Map
                  ? snap.data![2] as Map<String, dynamic>
                  : _supabaseData.currentInventory)
              : _supabaseData.currentInventory;

          // Parse production batches from Firebase event
          final batchesRaw = snap.data != null && snap.data!.length > 3
              ? (snap.data![3] as DatabaseEvent?)?.snapshot.value
              : null;
          final batches = <Map<String, dynamic>>[];
          if (batchesRaw is Map) {
            batchesRaw.forEach((k, v) {
              if (v is Map) {
                final b = Map<String, dynamic>.from(v);
                b['id'] = k.toString();
                batches.add(b);
              }
            });
          }

          final ordersAwaiting = _ordersAwaiting(orders);
          final pickupsAwaiting = _pickupsAwaiting(orders);
          final messagesAwaiting = _messagesAwaiting();
          final lowStock = _lowStockItems(productsMap, inventoryMap);
          final productionActive = _productionActive(batches);

          final totalTasks = ordersAwaiting.length +
              pickupsAwaiting.length +
              messagesAwaiting.length +
              lowStock.length +
              productionActive.length;

          return CustomScrollView(
            slivers: [
              // ── Header ───────────────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(32, 24, 32, 20),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Work Queue',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                color: textColor,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Your tasks for today — tap any category to act.',
                              style: TextStyle(
                                  fontSize: 13, color: subColor),
                            ),
                          ],
                        ),
                      ),
                      // Total tasks badge
                      if (totalTasks > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: isDark
                                ? AppTheme.badgeRedBgDark
                                : AppTheme.badgeRedBgLight,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isDark
                                  ? AppTheme.badgeRedBorderDark
                                  : AppTheme.badgeRedBorderLight,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.pending_actions_rounded,
                                  size: 15, color: AppTheme.error),
                              const SizedBox(width: 6),
                              Text(
                                '$totalTasks task${totalTasks == 1 ? '' : 's'} pending',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.error,
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(width: 10),
                      IconButton(
                        icon: Icon(Icons.refresh_rounded,
                            color: textColor, size: 20),
                        tooltip: 'Refresh',
                        onPressed: _refreshAll,
                      ),
                    ],
                  ),
                ),
              ),

              // ── Cards grid ───────────────────────────────────────────────
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
                sliver: SliverGrid(
                  gridDelegate:
                      const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 480,
                    mainAxisSpacing: 18,
                    crossAxisSpacing: 18,
                    childAspectRatio: 1.45,
                  ),
                  delegate: SliverChildListDelegate([
                    // 1. Orders
                    _QueueCard(
                      isDark: isDark,
                      icon: Icons.shopping_bag_outlined,
                      accentColor: AppTheme.accentGold,
                      title: 'Orders Awaiting Action',
                      count: ordersAwaiting.length,
                      emptyLabel: 'All orders are up to date',
                      items: ordersAwaiting
                          .take(5)
                          .map((o) => _QueueItem(
                                primary: o['orderReference']
                                        ?.toString()
                                        .isNotEmpty ==
                                    true
                                    ? '#${o['orderReference']}'
                                    : '#${o['id'].toString().substring(0, 6).toUpperCase()}',
                                secondary:
                                    '${o['customerName']}  •  ${o['orderStatus']}',
                                trailing:
                                    '₱${(o['totalAmount'] as num? ?? 0).toStringAsFixed(0)}',
                              ))
                          .toList(),
                      onTap: () => widget.onNavigateTab(1), // Orders page
                    ),

                    // 2. Pickups
                    _QueueCard(
                      isDark: isDark,
                      icon: Icons.qr_code_scanner_outlined,
                      accentColor: AppTheme.accentGreen,
                      title: 'Pickups Awaiting Scan',
                      count: pickupsAwaiting.length,
                      emptyLabel: 'No pickups awaiting confirmation',
                      items: pickupsAwaiting
                          .take(5)
                          .map((o) => _QueueItem(
                                primary: o['orderReference']
                                        ?.toString()
                                        .isNotEmpty ==
                                    true
                                    ? '#${o['orderReference']}'
                                    : '#${o['id'].toString().substring(0, 6).toUpperCase()}',
                                secondary: o['customerName'] ?? 'Customer',
                                trailing: 'Ready',
                              ))
                          .toList(),
                      onTap: () =>
                          widget.onNavigateTab(12), // Pickup QR Scanner
                    ),

                    // 3. Messages
                    _QueueCard(
                      isDark: isDark,
                      icon: Icons.message_outlined,
                      accentColor: AppTheme.accentBlue,
                      title: 'Messages Awaiting Reply',
                      count: messagesAwaiting.length,
                      emptyLabel: 'No unread customer messages',
                      isLoading: _inboxLoading,
                      errorMessage: _inboxError,
                      items: messagesAwaiting
                          .take(5)
                          .map((entry) => _QueueItem(
                                primary: entry['customer_name']?.toString() ??
                                    'Customer',
                                secondary:
                                    entry['last_message']?.toString() ?? '',
                                trailing:
                                    '${(entry['unread_count'] as num? ?? 0).toInt()} unread',
                              ))
                          .toList(),
                      onTap: () =>
                          widget.onNavigateTab(6), // Messages page
                    ),

                    // 4. Low Stock
                    _QueueCard(
                      isDark: isDark,
                      icon: Icons.warning_amber_rounded,
                      accentColor: AppTheme.warning,
                      title: 'Low-Stock Products',
                      count: lowStock.length,
                      emptyLabel: 'All products are sufficiently stocked',
                      items: lowStock
                          .take(5)
                          .map((item) => _QueueItem(
                                primary: item.label,
                                secondary:
                                    'Stock: ${item.currentQty}  •  Reorder: ${item.reorderLevel}',
                                trailing: item.currentQty == 0
                                    ? 'OUT'
                                    : '${item.currentQty}',
                                trailingIsWarning: true,
                              ))
                          .toList(),
                      onTap: () =>
                          widget.onNavigateTab(2), // Inventory page
                    ),

                    // 5. Production
                    _QueueCard(
                      isDark: isDark,
                      icon: Icons.factory_outlined,
                      accentColor: AppTheme.accentPurple,
                      title: 'Production In Progress',
                      count: productionActive.length,
                      emptyLabel: 'No active production batches',
                      items: productionActive
                          .take(5)
                          .map((b) {
                            final target =
                                (b['quantityTarget'] ?? b['quantityProduced'] ?? 0)
                                    as num;
                            final done =
                                (b['completedQuantity'] ?? 0) as num;
                            final pct = target > 0
                                ? (done / target * 100).round()
                                : 0;
                            return _QueueItem(
                              primary:
                                  '${b['productName'] ?? 'Batch'} (${b['bottleSize'] ?? '-'})',
                              secondary:
                                  '${b['status']}  •  Due: ${b['targetCompletionDate'] ?? b['productionDate'] ?? '-'}',
                              trailing: '$pct%',
                            );
                          })
                          .toList(),
                      onTap: () =>
                          widget.onNavigateTab(4), // Production page
                    ),
                  ]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _LowStockItem — simple value type
// ─────────────────────────────────────────────────────────────────────────────

class _LowStockItem {
  const _LowStockItem({
    required this.label,
    required this.currentQty,
    required this.reorderLevel,
  });
  final String label;
  final int currentQty;
  final int reorderLevel;
}

// ─────────────────────────────────────────────────────────────────────────────
// _QueueCard — single Work Queue category card
// ─────────────────────────────────────────────────────────────────────────────

class _QueueCard extends StatelessWidget {
  const _QueueCard({
    required this.isDark,
    required this.icon,
    required this.accentColor,
    required this.title,
    required this.count,
    required this.emptyLabel,
    required this.items,
    required this.onTap,
    this.isLoading = false,
    this.errorMessage,
  });

  final bool isDark;
  final IconData icon;
  final Color accentColor;
  final String title;
  final int count;
  final String emptyLabel;
  final List<_QueueItem> items;
  final VoidCallback onTap;
  final bool isLoading;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    final borderColor = AppTheme.panelBorder(isDark);
    final cardBg = isDark ? AppTheme.surfaceDark : Colors.white;
    final textColor = AppTheme.textPrimary(isDark);
    final subColor = AppTheme.textSecondary(isDark);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
          border: Border.all(
            color: count > 0
                ? accentColor.withValues(alpha: 0.45)
                : borderColor,
            width: count > 0 ? 1.4 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.05),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: accentColor, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: textColor,
                        letterSpacing: -0.1,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // Count badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: count > 0
                          ? accentColor.withValues(alpha: 0.15)
                          : borderColor.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$count',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: count > 0 ? accentColor : subColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Body
              Expanded(
                child: isLoading
                    ? const Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : errorMessage != null
                        ? Text(
                            'Could not load',
                            style: TextStyle(
                                fontSize: 11,
                                color: AppTheme.error),
                          )
                        : items.isEmpty
                            ? Row(
                                children: [
                                  Icon(Icons.check_circle_outline_rounded,
                                      size: 14,
                                      color: AppTheme.accentGreen),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      emptyLabel,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: subColor,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : Column(
                                mainAxisSize: MainAxisSize.min,
                                children: items
                                    .map((item) => _QueueRow(
                                          item: item,
                                          isDark: isDark,
                                          accentColor: accentColor,
                                        ))
                                    .toList(),
                              ),
              ),

              // Footer: tap hint
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    'View all →',
                    style: TextStyle(
                      fontSize: 11,
                      color: accentColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _QueueItem + _QueueRow — row within a card
// ─────────────────────────────────────────────────────────────────────────────

class _QueueItem {
  const _QueueItem({
    required this.primary,
    required this.secondary,
    required this.trailing,
    this.trailingIsWarning = false,
  });
  final String primary;
  final String secondary;
  final String trailing;
  final bool trailingIsWarning;
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({
    required this.item,
    required this.isDark,
    required this.accentColor,
  });
  final _QueueItem item;
  final bool isDark;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final subColor = AppTheme.textSecondary(isDark);
    final textColor = AppTheme.textPrimary(isDark);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 4,
            height: 4,
            margin: const EdgeInsets.only(top: 6, right: 8),
            decoration: BoxDecoration(
              color: accentColor,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.primary,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (item.secondary.isNotEmpty)
                  Text(
                    item.secondary,
                    style: TextStyle(fontSize: 10.5, color: subColor),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            item.trailing,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: item.trailingIsWarning ? AppTheme.error : accentColor,
            ),
          ),
        ],
      ),
    );
  }
}
