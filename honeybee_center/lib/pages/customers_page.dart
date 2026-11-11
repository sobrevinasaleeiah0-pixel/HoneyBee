import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:honeybee_center/services/auth_service.dart';
import 'package:honeybee_center/services/supabase_data_service.dart';
import 'package:honeybee_center/widgets/status_badge.dart';
import 'package:honeybee_center/core/theme/app_theme.dart';
import 'package:honeybee_center/core/permissions/admin_capabilities.dart';

class CustomersPage extends StatefulWidget {
  final AuthSession session;
  const CustomersPage({super.key, required this.session});

  @override
  State<CustomersPage> createState() => _CustomersPageState();
}

class _CustomersPageState extends State<CustomersPage> {
  final _supabaseData = SupabaseDataService();

  // Tab Management: 0 = All Customers, 1 = Payment Verification
  int _activeTab = 0;
  String _customerSearch = '';
  String _paymentFilter =
      'Pending Verification'; // All | Pending Verification | Confirmed | Rejected
  late Future<List<Map<String, dynamic>>> _customersFuture;
  late Future<List<Map<String, dynamic>>> _ordersFuture;

  bool get _canManageOrders =>
      RoleCapabilities.forRole(widget.session.role).canManageOrders;

  @override
  void initState() {
    super.initState();
    _ordersFuture = _supabaseData.fetchOrders();
    _customersFuture = _loadSupabaseCustomers();
  }

  Future<List<Map<String, dynamic>>> _loadSupabaseCustomers() async {
    final client = Supabase.instance.client;
    final customerRows = await client
        .from('customers')
        .select('id, auth_uid, name, email, phone, status, created_at')
        .order('created_at', ascending: false);
    final orders = await _ordersFuture;

    return (customerRows as List).whereType<Map>().map((row) {
      final customer = Map<String, dynamic>.from(row);
      final customerId = customer['id']?.toString() ?? '';
      final mapped = <String, dynamic>{
        ...customer,
        'uid': customer['auth_uid']?.toString() ?? customerId,
        'contact': customer['phone'] ?? '',
      };
      final customerOrders = orders
          .where((order) => _matchesCustomer(mapped, customerId, order))
          .toList();
      mapped['orders'] = customerOrders;
      mapped['totalOrders'] = customerOrders.length;
      mapped['lastOrderDate'] = customerOrders.isEmpty
          ? 'No orders'
          : customerOrders.first['orderDate'];
      return mapped;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDarkScaffold = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDarkScaffold
          ? AppTheme.backgroundDark
          : AppTheme.backgroundLight,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          _buildTabsHeader(),
          Expanded(child: _buildActiveTabContent()),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Builder(
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final textColor = isDark ? AppTheme.textDark : AppTheme.textLight;
        final subColor = isDark
            ? AppTheme.subtitleDark(isDark)
            : AppTheme.subtitleLight(isDark);
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            AppTheme.adminPagePadding,
            24,
            AppTheme.adminPagePadding,
            16,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Customer Management',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'View and manage registered customers, account status, and GCash / Maya payment verification',
                style: TextStyle(color: subColor, fontSize: 13),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTabsHeader() {
    return Builder(
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final textColor = isDark ? AppTheme.textDark : AppTheme.textLight;
        final subColor = isDark
            ? AppTheme.subtitleDark(isDark)
            : AppTheme.subtitleLight(isDark);
        final borderColor = isDark ? AppTheme.borderDark : AppTheme.borderLight;
        final tabs = ['All Customers', 'Payment Verification'];
        return Container(
          margin: const EdgeInsets.symmetric(
            horizontal: AppTheme.adminPagePadding,
          ),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: borderColor)),
          ),
          child: Row(
            children: List.generate(tabs.length, (index) {
              final isSelected = _activeTab == index;
              return Padding(
                padding: const EdgeInsets.only(right: 32.0),
                child: InkWell(
                  onTap: () => setState(() => _activeTab = index),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: isSelected
                              ? AppTheme.primaryGold
                              : Colors.transparent,
                          width: 3,
                        ),
                      ),
                    ),
                    child: Text(
                      tabs[index],
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.w600,
                        color: isSelected ? textColor : subColor,
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        );
      },
    );
  }

  Widget _buildActiveTabContent() {
    switch (_activeTab) {
      case 0:
        return _buildCustomersTab();
      case 1:
        return _buildPaymentVerificationTab();
      default:
        return _buildCustomersTab();
    }
  }

  // ================= TAB 1: ALL CUSTOMERS =================
  Widget _buildCustomersTab() {
    return Column(
      children: [
        const SizedBox(height: 16),
        _buildSearchBar(),
        Expanded(child: _buildLiveCustomerTable()),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Builder(
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final subColor = isDark
            ? AppTheme.subtitleDark(isDark)
            : AppTheme.subtitleLight(isDark);
        final fill = isDark ? AppTheme.backgroundDarkAlt : Colors.white;
        final border = isDark
            ? AppTheme.borderDarkAlt
            : AppTheme.borderLightAlt;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 8.0),
          child: TextField(
            onChanged: (v) => setState(() => _customerSearch = v),
            style: TextStyle(
              color: isDark ? AppTheme.textDark : AppTheme.textLight,
            ),
            decoration: InputDecoration(
              hintText: 'Search customers by name, email, or contact number...',
              hintStyle: TextStyle(color: subColor),
              prefixIcon: Icon(Icons.search, color: AppTheme.primaryGold),
              fillColor: fill,
              filled: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                borderSide: BorderSide(color: border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                borderSide: BorderSide(color: border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                borderSide: const BorderSide(
                  color: AppTheme.primaryGold,
                  width: 1.6,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLiveCustomerTable() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _customersFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFFD9A441)),
          );
        }

        final customersList = snapshot.data ?? <Map<String, dynamic>>[];
        final filtered = customersList.where((c) {
          final search = _customerSearch.toLowerCase().trim();
          if (search.isEmpty) return true;

          final name = (c['name'] ?? '').toString().toLowerCase();
          final email = (c['email'] ?? '').toString().toLowerCase();
          final contact =
              (c['contact'] ??
                      c['phone'] ??
                      c['customerPhone'] ??
                      c['phoneNumber'] ??
                      '')
                  .toString()
                  .toLowerCase();

          return name.contains(search) ||
              email.contains(search) ||
              contact.contains(search);
        }).toList();

        final isDark = Theme.of(context).brightness == Brightness.dark;
        final subColor2 = isDark
            ? AppTheme.subtitleDark(isDark)
            : AppTheme.subtitleLight(isDark);
        final headerBg2 = isDark
            ? AppTheme.backgroundDarkAlt
            : AppTheme.backgroundLightAlt;
        final cardBg2 = isDark ? AppTheme.surfaceDark : Colors.white;
        final cardBorder2 = isDark
            ? AppTheme.borderDarkAlt
            : AppTheme.borderLightAlt;
        final warnBg = isDark
            ? AppTheme.badgeGoldBgDark
            : AppTheme.badgeGoldBgLight;
        final warnBorder = isDark
            ? AppTheme.badgeGoldBorderDark
            : AppTheme.badgeGoldBorderLight;
        final warnText = isDark ? AppTheme.textDark : AppTheme.textLight;
        return Column(
          children: [
            if (snapshot.hasError)
              Container(
                margin: const EdgeInsets.fromLTRB(32, 8, 32, 0),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: warnBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: warnBorder),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: AppTheme.primaryGold,
                      size: 20,
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Could not load customers from Supabase: ${snapshot.error}',
                        style: TextStyle(
                          color: warnText,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Retry loading customers',
                      onPressed: () {
                        setState(() {
                          _customersFuture = _loadSupabaseCustomers();
                        });
                      },
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
              ),
            if (!snapshot.hasError && filtered.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 24),
                child: Text('No registered customers found in Supabase.'),
              ),
            Expanded(
              child: Container(
                margin: const EdgeInsets.fromLTRB(32, 12, 32, 24),
                decoration: BoxDecoration(
                  color: cardBg2,
                  borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                  border: Border.all(color: cardBorder2),
                ),
                child: SingleChildScrollView(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      headingRowColor: WidgetStateProperty.all(headerBg2),
                      horizontalMargin: 20,
                      columnSpacing: 16,
                      columns: [
                        DataColumn(
                          label: Text(
                            'CUSTOMER NAME',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 11,
                              color: subColor2,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                        DataColumn(
                          label: Text(
                            'EMAIL',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 11,
                              color: subColor2,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                        DataColumn(
                          label: Text(
                            'CONTACT',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 11,
                              color: subColor2,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                        DataColumn(
                          label: Text(
                            'ACCOUNT STATUS',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 11,
                              color: subColor2,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                        DataColumn(
                          label: Text(
                            'TOTAL ORDERS',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 11,
                              color: subColor2,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                        DataColumn(
                          label: Text(
                            'LAST ORDER',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 11,
                              color: subColor2,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                        DataColumn(
                          label: Text(
                            'ACTION',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 11,
                              color: subColor2,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                      ],
                      rows: filtered.map((c) {
                        final contact =
                            c['contact'] ??
                            c['phone'] ??
                            c['customerPhone'] ??
                            c['phoneNumber'] ??
                            'N/A';
                        final rawStatus = c['status'] ?? c['accountStatus'];
                        final statusText = _formatStatus(rawStatus);
                        final totalOrders = c['totalOrders'] ?? 0;
                        final lastOrder = c['lastOrderDate'] ?? 'No orders';
                        final rowText = isDark
                            ? AppTheme.textDark
                            : Color(0xFF111111);
                        final rowSub = isDark
                            ? AppTheme.textDarkSoft
                            : Colors.grey;
                        return DataRow(
                          cells: [
                            DataCell(
                              Text(
                                c['name'] ?? 'N/A',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                  color: rowText,
                                ),
                              ),
                            ),
                            DataCell(
                              Text(
                                c['email'] ?? 'N/A',
                                style: TextStyle(fontSize: 12, color: rowSub),
                              ),
                            ),
                            DataCell(
                              Text(
                                contact.toString(),
                                style: TextStyle(fontSize: 12, color: rowSub),
                              ),
                            ),
                            DataCell(StatusBadge(status: statusText)),
                            DataCell(
                              Text(
                                '$totalOrders',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                  color: rowText,
                                ),
                              ),
                            ),
                            DataCell(
                              Text(
                                lastOrder.toString(),
                                style: TextStyle(fontSize: 12, color: rowSub),
                              ),
                            ),
                            DataCell(
                              TextButton(
                                style: TextButton.styleFrom(
                                  foregroundColor: AppTheme.primaryGold,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 6,
                                  ),
                                ),
                                onPressed: () => _showCustomerDetails(c),
                                child: Text(
                                  'View Activity',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ================= TAB 2: PAYMENT VERIFICATION =================
  Widget _buildPaymentVerificationTab() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _ordersFuture,
      builder: (context, ordersSnapshot) {
        if (ordersSnapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Unable to load payment orders: ${ordersSnapshot.error}',
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        if (!ordersSnapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: _supabaseData.ordersStream,
          initialData: ordersSnapshot.data,
          builder: (context, snapshot) {
            final ordersList = snapshot.data ?? ordersSnapshot.data!;
            final paymentOrders = ordersList
                .where(SupabaseDataService.isPaymentVerificationOrder)
                .toList();

            final filteredPayments =
                paymentOrders.where((order) {
                  if (_paymentFilter == 'All') return true;
                  return SupabaseDataService.paymentVerificationStatus(
                        order,
                      ).toLowerCase() ==
                      _paymentFilter.toLowerCase();
                }).toList()..sort(
                  (a, b) => (b['paymentSubmittedAt'] ?? b['orderDate'] ?? '')
                      .toString()
                      .compareTo(
                        (a['paymentSubmittedAt'] ?? a['orderDate'] ?? '')
                            .toString(),
                      ),
                );

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(32, 16, 32, 8),
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      const Text(
                        'Filter Payments:',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                      ...[
                        'All',
                        'Pending Verification',
                        'Confirmed',
                        'Rejected',
                      ].map((f) {
                        final isSelected = _paymentFilter == f;
                        final chipIsDark =
                            Theme.of(context).brightness ==
                            Brightness.dark;
                        return ChoiceChip(
                          label: Text(
                            f,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: isSelected
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                            ),
                          ),
                          selected: isSelected,
                          selectedColor: chipIsDark
                              ? AppTheme.iconBadgeGoldDark
                              : AppTheme.iconBadgeGoldLight,
                          onSelected: (selected) {
                            if (selected) {
                              setState(() => _paymentFilter = f);
                            }
                          },
                        );
                      }),
                    ],
                  ),
                ),
                Expanded(
                  child: Card(
                    margin: const EdgeInsets.all(32),
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: SingleChildScrollView(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          headingRowColor: WidgetStateProperty.all(
                            const Color(0xFFF9F9F9),
                          ),
                          horizontalMargin: 20,
                          columnSpacing: 16,
                          columns: const [
                            DataColumn(
                              label: Text(
                                'ORDER ID',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            DataColumn(
                              label: Text(
                                'CUSTOMER',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            DataColumn(
                              label: Text(
                                'PAYMENT METHOD',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            DataColumn(
                              label: Text(
                                'AMOUNT',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            DataColumn(
                              label: Text(
                                'REFERENCE NUMBER',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            DataColumn(
                              label: Text(
                                'DATE SUBMITTED',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            DataColumn(
                              label: Text(
                                'PAYMENT STATUS',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            DataColumn(
                              label: Text(
                                'ACTION',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                          rows: filteredPayments.map((order) {
                            final orderId = order['id']?.toString() ?? 'N/A';
                            final shortId = orderId.length > 8
                                ? orderId.substring(0, 8).toUpperCase()
                                : orderId.toUpperCase();
                            final customer = order['customerName'] ?? 'N/A';
                            final method = order['paymentMethod'] ?? 'GCash';
                            final amount = _number(
                              order['totalAmount'] ?? order['amount'],
                            );
                            final refNum =
                                order['paymentReferenceNumber'] ?? 'N/A';
                            final dateSub =
                                order['paymentSubmittedAt'] ??
                                order['orderDate'] ??
                                'N/A';
                            final payStatus =
                                SupabaseDataService.paymentVerificationStatus(
                                  order,
                                );

                            return DataRow(
                              cells: [
                                DataCell(
                                  Text(
                                    '#$shortId',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    customer,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    method,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12,
                                      color: Color(0xFFD9A441),
                                    ),
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    '₱${amount.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    refNum.toString(),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    dateSub.toString(),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ),
                                DataCell(StatusBadge(status: payStatus)),
                                DataCell(
                                  TextButton(
                                    style: TextButton.styleFrom(
                                      foregroundColor: const Color(0xFFD9A441),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 6,
                                      ),
                                    ),
                                    onPressed: () =>
                                        _showReviewPaymentDialog(order),
                                    child: const Text(
                                      'Review Payment',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ================= DIALOGS =================
  void _showReviewPaymentDialog(Map<String, dynamic> order) {
    final orderId = order['id']?.toString() ?? 'N/A';
    final shortId = orderId.length > 8
        ? orderId.substring(0, 8).toUpperCase()
        : orderId.toUpperCase();
    final customer = order['customerName'] ?? 'N/A';
    final method = order['paymentMethod'] ?? 'GCash';
    final amount = _number(order['totalAmount'] ?? order['amount']);
    final refNum = order['paymentReferenceNumber'] ?? 'N/A';
    final subDate = order['paymentSubmittedAt'] ?? order['orderDate'] ?? 'N/A';
    final proofUrl = order['paymentProofUrl'] ?? order['paymentProof'];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Review Payment Proof — Order #$shortId'),
        content: SizedBox(
          width: 550,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _infoItem('Customer Name', customer),
                _infoItem('Order ID', '#$shortId'),
                _infoItem('Payment Method', method),
                _infoItem('Amount', '₱${amount.toStringAsFixed(2)}'),
                _infoItem('Reference Number', refNum.toString()),
                _infoItem('Date/Time Submitted', subDate.toString()),
                const Divider(height: 24),
                const Text(
                  'Uploaded Payment Screenshot / Proof:',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                ),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Payment Proof Screenshot'),
                        content: Container(
                          width: 450,
                          height: 380,
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: proofUrl != null
                              ? Image.network(
                                  proofUrl,
                                  fit: BoxFit.contain,
                                  errorBuilder: (c, e, s) => const Center(
                                    child: Text(
                                      'Unable to load payment proof image.',
                                    ),
                                  ),
                                )
                              : Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(
                                        Icons.receipt_long_rounded,
                                        size: 64,
                                        color: Color(0xFFD9A441),
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        '$method Payment Receipt',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Ref: $refNum',
                                        style: const TextStyle(
                                          color: Colors.grey,
                                          fontSize: 13,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Amount: ₱${amount.toStringAsFixed(2)}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w900,
                                          color: Color(0xFFD9A441),
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
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
                    height: 180,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: const Color(0xFFD9A441),
                        width: 1.5,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: proofUrl != null
                          ? Image.network(
                              proofUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (c, e, s) =>
                                  const Center(child: Text('Receipt Preview')),
                            )
                          : Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.image_search_rounded,
                                    size: 40,
                                    color: Color(0xFFD9A441),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Tap to Inspect Uploaded $method Receipt',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Ref: $refNum | ₱${amount.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          // Payment actions — Co-Admin only; Owner can view but not act.
          if (_canManageOrders) ...[
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              String? reason;
              await showDialog(
                context: context,
                builder: (ctx) {
                  final reasonController = TextEditingController();
                  return AlertDialog(
                    title: const Text('Reject Payment Proof'),
                    content: TextField(
                      controller: reasonController,
                      decoration: const InputDecoration(
                        labelText:
                            'Rejection Reason (e.g. Invalid Reference #)',
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

              if (reason == null) return;
              try {
                await _supabaseData.updatePaymentStatus(
                  orderId,
                  'Rejected',
                  rejectionReason: reason ?? 'Invalid payment proof',
                );
              } catch (error) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Could not reject payment: $error')),
                );
                return;
              }
              if (!context.mounted) return;
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Payment rejected successfully.')),
              );
            },
            child: const Text(
              'Reject Payment',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              try {
                await _supabaseData.updatePaymentStatus(orderId, 'Confirmed');
              } catch (error) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Could not confirm payment: $error')),
                );
                return;
              }
              if (!context.mounted) return;
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Payment confirmed successfully!'),
                ),
              );
            },
            child: const Text(
              'Confirm Payment',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          ], // end if (_canManageOrders)
        ],
      ),
    );
  }

  bool _matchesCustomer(
    Map<String, dynamic> customer,
    String customerKey,
    Map<String, dynamic> order,
  ) {
    final orderCustomerId = order['customerId']?.toString();
    if (orderCustomerId != null && orderCustomerId.isNotEmpty) {
      if (orderCustomerId == customerKey) return true;
    }

    final customerEmail = (customer['email'] ?? '')
        .toString()
        .toLowerCase()
        .trim();
    final orderEmail = (order['customerEmail'] ?? '')
        .toString()
        .toLowerCase()
        .trim();
    if (customerEmail.isNotEmpty &&
        orderEmail.isNotEmpty &&
        customerEmail == orderEmail) {
      return true;
    }

    final customerName = (customer['name'] ?? '')
        .toString()
        .toLowerCase()
        .trim();
    final orderName = (order['customerName'] ?? '')
        .toString()
        .toLowerCase()
        .trim();
    if (customerName.isNotEmpty &&
        orderName.isNotEmpty &&
        customerName == orderName) {
      return true;
    }

    return false;
  }

  String _formatStatus(dynamic rawStatus) {
    if (rawStatus == null) return 'Unknown';
    final s = rawStatus.toString().toLowerCase().trim();
    if (s == 'active') return 'Active';
    if (s == 'inactive') return 'Inactive';
    if (s == 'disabled') return 'Disabled';
    if (s.isEmpty) return 'Unknown';
    return s[0].toUpperCase() + s.substring(1);
  }

  String _formatDate(dynamic timestamp) {
    if (timestamp == null) return 'N/A';
    if (timestamp is int) {
      try {
        final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
        return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      } catch (_) {}
    }
    return timestamp.toString();
  }

  void _showCustomerDetails(Map<String, dynamic> customer) {
    final name = customer['name'] ?? 'Customer Details';
    final email = customer['email'] ?? 'N/A';
    final contact =
        customer['contact'] ??
        customer['phone'] ??
        customer['customerPhone'] ??
        customer['phoneNumber'] ??
        'N/A';
    final rawStatus = customer['status'] ?? customer['accountStatus'];
    final statusText = _formatStatus(rawStatus);
    final regDate = _formatDate(
      customer['createdAt'] ?? customer['registeredAt'] ?? customer['date'],
    );
    final orders = (customer['orders'] as List?) ?? [];
    final totalOrders = orders.length;
    final lastOrder = totalOrders > 0
        ? (orders.first['orderDate'] ?? orders.first['date'] ?? 'N/A')
        : 'No orders yet';
    final recentStatus = totalOrders > 0
        ? (orders.first['orderStatus'] ?? orders.first['status'] ?? 'Pending')
        : 'N/A';

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: 700,
          constraints: const BoxConstraints(maxHeight: 700),
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF111111),
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Customer Activity & Order History',
                          style: TextStyle(color: Colors.grey, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(height: 32),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Section 1: Customer Information Card
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF9F9F9),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFEEEEEE)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Customer Information',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(child: _infoItem('Email', email)),
                                Expanded(
                                  child: _infoItem(
                                    'Contact Number',
                                    contact.toString(),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: _infoItem(
                                    'Registration Date',
                                    regDate,
                                  ),
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Account Status',
                                        style: TextStyle(
                                          color: Colors.grey,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      StatusBadge(status: statusText),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Section 2: Order Summary Card
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF9F9F9),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFEEEEEE)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Order Summary',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: _infoItem(
                                    'Total Orders',
                                    '$totalOrders',
                                  ),
                                ),
                                Expanded(
                                  child: _infoItem(
                                    'Last Order Date',
                                    lastOrder.toString(),
                                  ),
                                ),
                                Expanded(
                                  child: _infoItem(
                                    'Recent Status',
                                    recentStatus.toString(),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Section: Payment Activity (GCash / Maya Verification)
                      const Text(
                        'Payment Activity',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Builder(
                        builder: (context) {
                          final paymentOrders = orders
                              .where(
                                (order) =>
                                    SupabaseDataService.isPaymentVerificationOrder(
                                      order,
                                    ),
                              )
                              .toList();
                          if (paymentOrders.isEmpty) {
                            return Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(0xFFEEEEEE),
                                ),
                              ),
                              child: const Center(
                                child: Text(
                                  'No payment activity yet.',
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            );
                          }
                          return Column(
                            children: paymentOrders.map((order) {
                              final orderId = order['id']?.toString() ?? 'N/A';
                              final shortId = orderId.length > 8
                                  ? orderId.substring(0, 8).toUpperCase()
                                  : orderId.toUpperCase();
                              final method =
                                  order['paymentMethod'] ?? 'GCash / Maya';
                              final amount = _number(
                                order['totalAmount'] ?? order['amount'],
                              );
                              final payStatus =
                                  SupabaseDataService.paymentVerificationStatus(
                                    order,
                                  );
                              final refNum =
                                  order['paymentReferenceNumber'] ?? 'N/A';
                              final subDate =
                                  order['paymentSubmittedAt'] != null
                                  ? _formatDate(order['paymentSubmittedAt'])
                                  : (order['orderDate'] ?? 'N/A');

                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: const Color(0xFFEEEEEE),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          'Payment Method: $method',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 13,
                                          ),
                                        ),
                                        StatusBadge(status: payStatus),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    _infoItem(
                                      'Amount',
                                      '₱${amount.toStringAsFixed(2)}',
                                    ),
                                    _infoItem(
                                      'Reference Number',
                                      refNum.toString(),
                                    ),
                                    _infoItem('Related Order ID', '#$shortId'),
                                    _infoItem(
                                      'Date Submitted',
                                      subDate.toString(),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          );
                        },
                      ),
                      const SizedBox(height: 24),

                      // Section 3: Order History List
                      const Text(
                        'Order History',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (orders.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(32),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFEEEEEE)),
                          ),
                          child: const Center(
                            child: Text(
                              'No orders yet.',
                              style: TextStyle(
                                color: Colors.grey,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        )
                      else
                        ...orders.map((order) {
                          final orderId = order['id']?.toString() ?? 'N/A';
                          final shortId = orderId.length > 8
                              ? orderId.substring(0, 8).toUpperCase()
                              : orderId.toUpperCase();
                          final date =
                              order['orderDate'] ?? order['date'] ?? 'N/A';
                          final status =
                              order['orderStatus'] ??
                              order['status'] ??
                              'Pending';
                          final total = _number(
                            order['totalAmount'] ?? order['amount'],
                          );
                          final items = order['items'];

                          List<Widget> itemWidgets = [];
                          if (items is Map) {
                            itemWidgets = items.entries.map((ie) {
                              final itm = Map<String, dynamic>.from(
                                ie.value as Map? ?? {},
                              );
                              final prod =
                                  itm['product'] ??
                                  itm['productName'] ??
                                  itm['name'] ??
                                  'Honey';
                              final size = itm['size'] ?? '-';
                              final qty = itm['quantity'] ?? 1;
                              final price = _number(itm['price'] ?? 0);
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 4.0),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      '• $prod ($size) x$qty',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                      ),
                                    ),
                                    Text(
                                      '₱${price.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList();
                          } else if (items is List) {
                            itemWidgets = items.map((ie) {
                              final itm = Map<String, dynamic>.from(
                                ie as Map? ?? {},
                              );
                              final prod =
                                  itm['product'] ??
                                  itm['productName'] ??
                                  itm['name'] ??
                                  'Honey';
                              final size = itm['size'] ?? '-';
                              final qty = itm['quantity'] ?? 1;
                              final price = _number(itm['price'] ?? 0);
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 4.0),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      '• $prod ($size) x$qty',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                      ),
                                    ),
                                    Text(
                                      '₱${price.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList();
                          }

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFFEEEEEE),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Order #$shortId',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 13,
                                      ),
                                    ),
                                    StatusBadge(status: status),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Date: $date',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                      ),
                                    ),
                                    Text(
                                      'Total: ₱${total.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 13,
                                        color: Color(0xFFD9A441),
                                      ),
                                    ),
                                  ],
                                ),
                                if (itemWidgets.isNotEmpty) ...[
                                  const Divider(height: 16),
                                  ...itemWidgets,
                                ],
                              ],
                            ),
                          );
                        }),
                    ],
                  ),
                ),
              ),
              const Divider(height: 32),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD9A441),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Close',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.grey,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 13,
            color: Color(0xFF111111),
          ),
        ),
      ],
    );
  }

  double _number(Object? value, {num fallback = 0}) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '') ?? fallback.toDouble();
}


