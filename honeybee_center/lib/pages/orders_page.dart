import 'package:flutter/material.dart';
import 'package:honeybee_center/services/auth_service.dart';
import 'package:honeybee_center/services/supabase_data_service.dart';
import 'package:honeybee_center/widgets/status_badge.dart';
import '../core/theme/app_theme.dart';
import '../core/permissions/admin_capabilities.dart';

class OrdersPage extends StatefulWidget {
  final AuthSession session;
  const OrdersPage({super.key, required this.session});

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> {
  final _supabaseDataService = SupabaseDataService();
  String _searchQuery = '';
  String _filterStatus = 'All';

  final List<String> _statuses = [
    'All',
    'Pending',
    'Confirmed',
    'Preparing',
    'Ready for Pickup',
    'Completed',
    'Cancelled',
  ];

  @override
  void initState() {
    super.initState();
    _supabaseDataService.fetchOrders().catchError((e) {
      debugPrint('[OrdersPage] Error initial fetchOrders: $e');
      return <Map<String, dynamic>>[];
    });
  }

  // Normalize order status to match dropdown filters
  String _normalizeStatus(String status) {
    switch (status.toLowerCase()) {
      case 'waitingpaymentverification':
      case 'pending':
        return 'Pending';
      case 'confirmed':
        return 'Confirmed';
      case 'preparing':
        return 'Preparing';
      case 'readyforpickup':
      case 'ready for pickup':
        return 'Ready for Pickup';
      case 'completed':
        return 'Completed';
      case 'cancelled':
        return 'Cancelled';
      default:
        return status.isNotEmpty ? status : 'Pending';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: AppTheme.pageBackground(isDark),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          _buildFilters(),
          Expanded(child: _buildOrderTable()),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = AppTheme.textPrimary(isDark);
    final subColor = AppTheme.textSecondary(isDark);
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Orders',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: textColor,
            ),
          ),
          Text(
            'Manage customer transactions and fulfillment',
            style: TextStyle(
              color: subColor,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 0, 32, 4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 600;
          if (isNarrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  onChanged: (v) => setState(() => _searchQuery = v),
                  style: TextStyle(
                    color: AppTheme.textPrimary(isDark),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: AppTheme.searchInputDecoration(
                    isDark,
                    hintText: 'Search by customer name...',
                  ),
                ),
                const SizedBox(height: 12),
                _buildDropdown(
                  _filterStatus,
                  _statuses,
                  (v) => setState(() => _filterStatus = v!),
                ),
              ],
            );
          }
          return Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: (v) => setState(() => _searchQuery = v),
                  style: TextStyle(
                    color: AppTheme.textPrimary(isDark),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: AppTheme.searchInputDecoration(
                    isDark,
                    hintText: 'Search by customer name...',
                  ),
                ),
              ),
              const SizedBox(width: 16),
              _buildDropdown(
                _filterStatus,
                _statuses,
                (v) => setState(() => _filterStatus = v!),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDropdown(
    String value,
    List<String> items,
    ValueChanged<String?> onChanged,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = AppTheme.textPrimary(isDark);
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: AppTheme.fieldDecoration(isDark),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          dropdownColor: AppTheme.panelColor(isDark),
          icon: Icon(
            Icons.keyboard_arrow_down_rounded,
            color: AppTheme.textSecondary(isDark),
          ),
          items: items
              .map(
                (s) => DropdownMenuItem(
                  value: s,
                  child: Text(
                    s,
                    style: TextStyle(fontSize: 14, color: textColor),
                  ),
                ),
              )
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildOrderTable() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final subColor = AppTheme.textSecondary(isDark);
    final textColor = AppTheme.textPrimary(isDark);
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _supabaseDataService.ordersStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final list = snapshot.data ?? [];
        if (list.isEmpty) {
          return Center(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 28),
              decoration: AppTheme.emptyStateDecoration(isDark),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.shopping_bag_outlined,
                    size: 46,
                    color: AppTheme.primaryGold,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'No orders found',
                    style: TextStyle(
                      color: textColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Customer purchases will appear here.',
                    style: TextStyle(color: subColor, fontSize: 12),
                  ),
                ],
              ),
            ),
          );
        }

        // Apply filters
        final filtered = list.where((o) {
          final displayStatus = _normalizeStatus(
            o['orderStatus'] as String? ?? 'Pending',
          );
          final matchesStatus =
              _filterStatus == 'All' || displayStatus == _filterStatus;
          final search = _searchQuery.toLowerCase();
          final customerMatch = (o['customerName'] ?? '')
              .toString()
              .toLowerCase()
              .contains(search);
          final refMatch = (o['orderReference'] ?? '')
              .toString()
              .toLowerCase()
              .contains(search);
          final idMatch = (o['id'] ?? '').toString().toLowerCase().contains(
            search,
          );
          return matchesStatus && (customerMatch || refMatch || idMatch);
        }).toList();

        if (filtered.isEmpty) {
          return Center(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 28),
              margin: const EdgeInsets.all(32),
              decoration: AppTheme.emptyStateDecoration(isDark),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.search_off_rounded,
                    size: 44,
                    color: AppTheme.primaryGold,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'No matching orders',
                    style: TextStyle(
                      color: textColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Try adjusting your search query or filter status.',
                    style: TextStyle(color: subColor, fontSize: 12),
                  ),
                ],
              ),
            ),
          );
        }

        return Container(
          margin: const EdgeInsets.all(32),
          decoration: AppTheme.adminPanelDecoration(isDark),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(
                AppTheme.tableHeader(isDark),
              ),
              horizontalMargin: 24,
              columns: [
                DataColumn(
                  label: Text(
                    'ORDER ID',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 11.5,
                      color: subColor,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'CUSTOMER',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 11.5,
                      color: subColor,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'TOTAL',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 11.5,
                      color: subColor,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'STATUS',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 11.5,
                      color: subColor,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'ACTION',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 11.5,
                      color: subColor,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ],
              rows: filtered.map((o) {
                // Pickup reminder rule:
                // status == "Ready for Pickup" AND readyForPickupAt <= 24h ago
                // AND pickupReminderSent != true
                final isReadyForPickup = o['orderStatus'] == 'Ready for Pickup';
                final reminderSent = o['pickupReminderSent'] == true;
                final readyAt = o['readyForPickupAt'] as int?;
                final overdue =
                    readyAt != null &&
                    DateTime.now()
                            .difference(
                              DateTime.fromMillisecondsSinceEpoch(readyAt),
                            )
                            .inHours >=
                        24;
                final needsReminder =
                    isReadyForPickup && overdue && !reminderSent;

                final orderRef = o['orderReference']?.toString();
                final orderIdDisplay = (orderRef != null && orderRef.isNotEmpty && !orderRef.startsWith('UUID'))
                    ? (orderRef.startsWith('#') ? orderRef : '#$orderRef')
                    : '#ORD-${o['id'].toString().replaceAll('-', '').substring(0, 6).toUpperCase()}';

                return DataRow(
                  cells: [
                    DataCell(
                      Text(
                        orderIdDisplay,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: textColor,
                        ),
                      ),
                    ),
                    DataCell(
                      Text(
                        o['customerName'] ?? 'N/A',
                        style: TextStyle(color: textColor),
                      ),
                    ),
                    DataCell(
                      Text(
                        '₱${o['totalAmount']}',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: textColor,
                        ),
                      ),
                    ),
                    DataCell(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          StatusBadge(status: o['orderStatus'] ?? 'Pending'),
                          if (needsReminder) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? AppTheme.badgeGoldBgDark
                                    : AppTheme.badgeGoldBgLight,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: isDark
                                      ? AppTheme.badgeGoldBorderDark
                                      : AppTheme.badgeGoldBorderLight,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.access_time_rounded,
                                    size: 11,
                                    color: AppTheme.primaryGold,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    'Pickup Reminder',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.primaryGold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    DataCell(
                      TextButton(
                        onPressed: () => _showOrderDetails(o),
                        child: const Text('View Details'),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  void _showOrderDetails(Map<String, dynamic> order) {
    showDialog(
      context: context,
      builder: (context) => _OrderDetailsDialog(
        order: order,
        session: widget.session,
        onStatusUpdate: (status) => _onStatusUpdate(order['id'], status),
      ),
    );
  }

  Future<void> _onStatusUpdate(String orderId, String status) async {
    try {
      if (status == 'Completed') {
        await _supabaseDataService.completeOrder(orderId);
      } else {
        await _supabaseDataService.updateOrderStatus(orderId, status);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Order status updated to $status.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update order status: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }
}

class _OrderDetailsDialog extends StatelessWidget {
  final Map<String, dynamic> order;
  final AuthSession session;
  final Function(String) onStatusUpdate;
  const _OrderDetailsDialog({
    required this.order,
    required this.session,
    required this.onStatusUpdate,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = AppTheme.textPrimary(isDark);
    final subColor = AppTheme.textSecondary(isDark);
    final payProofBg = isDark
        ? AppTheme.backgroundDarkAlt
        : AppTheme.backgroundLightAlt;
    final payProofBorder = isDark
        ? AppTheme.borderDarkAlt
        : AppTheme.borderLightAlt;
    final items = order['items'] as Map? ?? {};
    final isDeducted = order['inventoryDeducted'] == true;

    return AlertDialog(
      backgroundColor: AppTheme.panelColor(isDark),
      title: Text(
        'Order #${order['id'].toString().substring(0, 8).toUpperCase()}',
        style: TextStyle(color: textColor),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Customer: ${order['customerName']}',
              style: TextStyle(color: textColor),
            ),
            Text(
              'Date: ${order['orderDate']}',
              style: TextStyle(color: textColor),
            ),
            const Divider(height: 32),
            Text(
              'Items:',
              style: TextStyle(fontWeight: FontWeight.bold, color: textColor),
            ),
            ...items.entries.map((e) {
              final item = Map<String, dynamic>.from(e.value);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${item['productName']} (${item['bottleSize']})',
                            style: TextStyle(color: textColor, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '₱${item['unitPrice']} x ${item['quantity']}',
                            style: TextStyle(color: subColor, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '₱${item['subtotal']}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                  ],
                ),
              );
            }),
            // Send to Bulk Production Quick Action
            if (RoleCapabilities.forRole(session.role).canManageOrders) ...[
              const Divider(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final orderId = order['id'];
                    final orderData = order;
                    final itemsMap = Map<String, dynamic>.from(
                      orderData['items'] ?? {},
                    );

                    // Check empty bottles supply inventory from SupabaseDataService
                    final inventoryMap = SupabaseDataService().currentInventory;

                    int totalTargetQty = 0;
                    final Map<String, dynamic> prodItems = {};
                    final Map<String, dynamic> requirements = {};
                    bool hasShortage = false;

                    int index = 0;
                    itemsMap.forEach((k, v) {
                      final itm = Map<String, dynamic>.from(v);
                      int qtyNeeded = itm['quantity'] ?? 10;
                      totalTargetQty += qtyNeeded;

                      String pId = itm['productId'] ?? 'prod_mellifera';
                      String vId = itm['variantId'] ?? 'v_mel_250g';
                      String size = itm['size'] ?? '250g';
                      String prodName =
                          itm['productName'] ?? itm['product'] ?? 'Honey';

                      prodItems['item_$index'] = {
                        'productId': pId,
                        'variantId': vId,
                        'productName': prodName,
                        'bottleSize': size,
                        'targetQuantity': qtyNeeded,
                        'completedQuantity': 0,
                        'status': 'Pending',
                      };

                      int availableSupply = 100;
                      if (inventoryMap.containsKey(pId)) {
                        final pInv = Map<String, dynamic>.from(
                          inventoryMap[pId],
                        );
                        if (pInv.containsKey(vId)) {
                          final vInv = Map<String, dynamic>.from(pInv[vId]);
                          availableSupply = vInv['quantity'] ?? 50;
                        }
                      }

                      int shortage = (qtyNeeded - availableSupply).clamp(
                        0,
                        qtyNeeded,
                      );
                      if (shortage > 0) hasShortage = true;

                      requirements['req_$index'] = {
                        'supplyName': '$prodName ($size Empty Bottles)',
                        'required': qtyNeeded,
                        'available': availableSupply,
                        'shortage': shortage,
                      };

                      index++;
                    });

                    String initialStatus = hasShortage
                        ? 'Preparing'
                        : 'Ready for Production';

                    // Build items array for Supabase RPC
                    final itemsArray = <Map<String, dynamic>>[];
                    prodItems.forEach((_, v) {
                      final itm = Map<String, dynamic>.from(v);
                      itemsArray.add({
                        'product_external_id': itm['productId'],
                        'variant_external_id': itm['variantId'],
                        'product_name':        itm['productName'] ?? 'Honey',
                        'bottle_size':         itm['bottleSize'] ?? '-',
                        'qty_target':          itm['targetQuantity'] ?? 0,
                      });
                    });

                    await SupabaseDataService().createBulkProductionBatch(
                      orderId:              orderId,
                      customerName:         orderData['customerName'] ?? 'Customer',
                      bundleName:           'Wholesale Order #${orderId.substring(0, 6).toUpperCase()}',
                      qtyTarget:            totalTargetQty,
                      initialStatus:        initialStatus,
                      itemsSummary:         '${itemsMap.length} product line(s)',
                      startDate:            DateTime.now().toString().split(' ')[0],
                      targetCompletionDate: orderData['targetDate'] ?? DateTime.now().add(const Duration(days: 7)).toString().split(' ')[0],
                      items:                itemsArray,
                    );

                    if (!context.mounted) return;
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Bulk production plan created from Order #${orderId.substring(0, 8).toUpperCase()}! Status: $initialStatus',
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.inventory_2_outlined, size: 18),
                  label: const Text(
                    'Send to Bulk Production',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryGold,
                    foregroundColor: isDark
                        ? AppTheme.primaryDark
                        : const Color(0xFF1A1300),
                  ),
                ),
              ),
            ],
            const Divider(height: 32),
            Text(
              'Payment Verification (GCash / Maya)',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 13,
                color: textColor,
              ),
            ),
            const SizedBox(height: 8),
            _infoRow(
              context,
              'Payment Method',
              order['paymentMethod'] ?? 'Cash / Unspecified',
            ),
            _infoRow(
              context,
              'Payment Status',
              order['paymentStatus'] ?? 'Pending',
            ),
            if (order['paymentReferenceNumber'] != null)
              _infoRow(
                context,
                'Reference Number',
                order['paymentReferenceNumber'].toString(),
              ),
            if (order['paymentSubmittedAt'] != null)
              _infoRow(
                context,
                'Date Submitted',
                order['paymentSubmittedAt'].toString(),
              ),
            if (order['paymentProofUrl'] != null ||
                order['paymentProof'] != null) ...[
              const SizedBox(height: 8),
              Text(
                'Payment Proof Screenshot:',
                style: TextStyle(fontSize: 12, color: subColor),
              ),
              const SizedBox(height: 4),
              InkWell(
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text(
                        'Payment Proof',
                        style: TextStyle(color: textColor),
                      ),
                      content: Image.network(
                        order['paymentProofUrl'] ?? order['paymentProof'],
                        errorBuilder: (c, e, s) =>
                            const Text('Unable to load payment proof image.'),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Close'),
                        ),
                      ],
                    ),
                  );
                },
                child: Container(
                  height: 90,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: payProofBg,
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    border: Border.all(color: payProofBorder),
                  ),
                  child: Center(
                    child: Text(
                      'View Uploaded Payment Proof (Tap to Enlarge)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.info,
                      ),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (RoleCapabilities.forRole(session.role).canManageOrders) ...[
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.success,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () async {
                        try {
                          await SupabaseDataService().updatePaymentStatus(
                            order['id'],
                            'Confirmed',
                          );
                          if (context.mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Payment confirmed successfully!',
                                ),
                              ),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Failed to confirm payment: $e'),
                                backgroundColor: Colors.redAccent,
                              ),
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.check_circle, size: 16),
                      label: const Text('Confirm Payment'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.error,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () async {
                        String? reason;
                        await showDialog(
                          context: context,
                          builder: (ctx) {
                            final reasonController = TextEditingController();
                            return AlertDialog(
                              title: Text(
                                'Reject Payment Proof',
                                style: TextStyle(color: textColor),
                              ),
                              content: TextField(
                                controller: reasonController,
                                decoration: const InputDecoration(
                                  labelText:
                                      'Rejection Reason (e.g. Invalid ref #)',
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  child: const Text('Cancel'),
                                ),
                                ElevatedButton(
                                  onPressed: () {
                                    reason = reasonController.text;
                                    Navigator.pop(ctx);
                                  },
                                  child: const Text('Reject'),
                                ),
                              ],
                            );
                          },
                        );

                        try {
                          await SupabaseDataService().updatePaymentStatus(
                            order['id'],
                            'Rejected',
                            rejectionReason: reason ?? 'Invalid payment proof',
                          );
                          if (context.mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Payment rejected.'),
                              ),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Failed to reject payment: $e'),
                                backgroundColor: Colors.redAccent,
                              ),
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.cancel, size: 16),
                      label: const Text('Reject Payment'),
                    ),
                  ),
                ],
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF2A2620)
                      : const Color(0xFFF5F3EF),
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                ),
                child: Row(
                  children: [
                    Icon(Icons.lock_outline, size: 16, color: subColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Owner is in monitoring mode. Payment verification requires Co-Admin.',
                        style: TextStyle(
                          fontSize: 12,
                          color: subColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const Divider(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Total Amount:',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: textColor,
                  ),
                ),
                Text(
                  '₱${order['totalAmount']}',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: AppTheme.primaryGold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (!isDeducted) ...[
              Text(
                'Update Status:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 6),
              if (RoleCapabilities.forRole(session.role).canManageOrders)
                Wrap(
                  spacing: 8,
                  children:
                      [
                        'Confirmed',
                        'Preparing',
                        'Ready for Pickup',
                        'Completed',
                        'Cancelled',
                      ].map((s) {
                        return ChoiceChip(
                          label: Text(s, style: const TextStyle(fontSize: 12)),
                          selected: order['orderStatus'] == s,
                          onSelected: (selected) {
                            if (selected) {
                              onStatusUpdate(s);
                              Navigator.pop(context);
                            }
                          },
                        );
                      }).toList(),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF2A2620)
                        : const Color(0xFFF5F3EF),
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.visibility_outlined,
                        size: 16,
                        color: subColor,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Owner is in monitoring mode. Status updates require Co-Admin.',
                          style: TextStyle(
                            fontSize: 12,
                            color: subColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (order['orderStatus'] == 'Ready for Pickup') ...[
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                if (order['pickupReminderSent'] == true)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppTheme.badgeGreenBgDark
                          : AppTheme.badgeGreenBgLight,
                      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                      border: Border.all(
                        color: isDark
                            ? AppTheme.badgeGreenBorderDark
                            : AppTheme.badgeGreenBorderLight,
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.check_circle_outline,
                          size: 16,
                          color: AppTheme.success,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Pickup reminder marked as sent on '
                            '${order['pickupReminderSentAt'] != null ? DateTime.fromMillisecondsSinceEpoch(order['pickupReminderSentAt']).toLocal().toString().split('.')[0] : 'N/A'}.',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.success,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Text(
                    'An automatic pickup follow-up will be sent after the '
                    'configured 24-hour waiting period if the order remains '
                    'uncollected.',
                    style: TextStyle(fontSize: 12, color: subColor),
                  ),
              ],
            ] else
              Center(
                child: Text(
                  'Inventory already processed for this order.',
                  style: TextStyle(
                    color: AppTheme.success,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _infoRow(BuildContext context, String label, String value) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppTheme.textDark : AppTheme.textLight;
    final subColor = isDark ? AppTheme.subtitleDark(isDark) : AppTheme.subtitleLight(isDark);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: subColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 12,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}
