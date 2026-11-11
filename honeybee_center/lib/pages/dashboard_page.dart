import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../services/supabase_data_service.dart';
import '../core/theme/app_theme.dart';
import '../widgets/status_badge.dart';
import '../core/permissions/admin_capabilities.dart';

import 'package:rxdart/rxdart.dart';

class _DashboardScanResults {
  const _DashboardScanResults({required this.values, this.error});

  final Map<String, dynamic> values;
  final Object? error;
}

class DashboardPage extends StatefulWidget {
  final AuthSession session;

  const DashboardPage({super.key, required this.session});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final _supabaseData = SupabaseDataService();
  String _revenueFilter = '7 Days';
  String? _dashboardLoadError;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    try {
      await _supabaseData.refreshAll();
      if (_dashboardLoadError != null && mounted) {
        setState(() => _dashboardLoadError = null);
      }
    } catch (e) {
      debugPrint('[DashboardPage] Failed to load Supabase dashboard data: $e');
      if (mounted) setState(() => _dashboardLoadError = e.toString());
    }
  }

  Map<String, dynamic> _ordersById(List<Map<String, dynamic>> orders) => {
    for (final order in orders) order['id'].toString(): order,
  };

  Stream<_DashboardScanResults> get _scanResultsStream => DatabaseService()
      .getScanResultsStream()
      .map((event) {
        final value = event.snapshot.value;
        return _DashboardScanResults(
          values: value is Map
              ? Map<String, dynamic>.from(value)
              : <String, dynamic>{},
        );
      })
      .onErrorReturnWith((error, stackTrace) {
        debugPrint('[DashboardPage] Firebase scan results unavailable: $error');
        return _DashboardScanResults(values: const {}, error: error);
      });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(32, 24, 32, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            _buildLiveSummaryCards(),
            if (_dashboardLoadError != null) ...[
              const SizedBox(height: 12),
              _buildDashboardLoadError(_dashboardLoadError!),
            ],
            const SizedBox(height: 28),
            _buildResponsiveTwoColumns(
              left: _buildSalesOverview(context),
              right: _buildLowStockPanel(context),
              leftFlex: 13,
              rightFlex: 7,
            ),
            const SizedBox(height: 28),
            _buildRevenueTrendSection(),
            const SizedBox(height: 28),
            _buildResponsiveTwoColumns(
              left: _buildOrderCompletionRate(),
              right: _buildCustomerOverview(),
              leftFlex: 7,
              rightFlex: 6,
            ),
            const SizedBox(height: 28),
            _buildOperationalAlerts(),
            const SizedBox(height: 28),
            _buildQuickActions(),
            const SizedBox(height: 28),
            _buildResponsiveTwoColumns(
              left: _buildTopSellingProducts(),
              right: _buildTopCustomers(),
              leftFlex: 6,
              rightFlex: 7,
            ),
            const SizedBox(height: 28),
            _buildRecentActivityPanel(context),
          ],
        ),
      ),
    );
  }

  Widget _buildResponsiveTwoColumns({
    required Widget left,
    required Widget right,
    int leftFlex = 1,
    int rightFlex = 1,
    double gap = 20,
    double breakpoint = 980,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < breakpoint) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              left,
              SizedBox(height: gap),
              right,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: leftFlex, child: left),
            SizedBox(width: gap),
            Expanded(flex: rightFlex, child: right),
          ],
        );
      },
    );
  }

  Widget _buildDashboardLoadError(String details) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.errorContainer,
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: colors.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Dashboard data failed to load: $details',
                style: TextStyle(color: colors.onErrorContainer),
              ),
            ),
            TextButton(
              onPressed: _loadDashboardData,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveSummaryCards() {
    return StreamBuilder<List<dynamic>>(
      stream: CombineLatestStream.list([
        _supabaseData.productsStream,
        _supabaseData.ordersStream,
        _supabaseData.inventoryStream,
      ]),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'Error loading stats: ${snapshot.error}',
                style: const TextStyle(color: Colors.red),
              ),
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(20.0),
              child: CircularProgressIndicator(),
            ),
          );
        }

        if (!snapshot.hasData ||
            snapshot.data == null ||
            snapshot.data!.length < 3) {
          return const Center(child: Text('Connecting to services...'));
        }

        final products = Map<String, dynamic>.from(snapshot.data![0] as Map);
        final orders = _ordersById(
          (snapshot.data![1] as List).cast<Map<String, dynamic>>(),
        );
        final inventory = Map<String, dynamic>.from(snapshot.data![2] as Map);

        int totalProducts = 0;
        products.forEach((k, v) {
          final variants = v['variants'] as Map? ?? {};
          totalProducts += variants.length;
        });

        int pendingOrders = 0;
        int todayOrders = 0;
        double totalSales = 0;
        double todaySales = 0;
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);

        orders.forEach((k, v) {
          if (v['orderStatus'] == 'Pending') pendingOrders++;
          if (v['orderStatus'] == 'Completed') {
            totalSales += (v['totalAmount'] ?? 0).toDouble();
            final orderDate = _parseDate(v['orderDate'] ?? v['date']);
            if (orderDate != null && orderDate.isAtSameMomentAs(today)) {
              todaySales += (v['totalAmount'] ?? 0).toDouble();
              todayOrders++;
            }
          }
        });

        int lowStockItems = 0;
        int outOfStockItems = 0;
        inventory.forEach((pId, pInv) {
          final variants = pInv as Map? ?? {};
          variants.forEach((vId, vData) {
            final qty = (vData['quantity'] as num?)?.toInt() ?? 0;
            final pData = products[pId];
            if (pData != null) {
              final vMeta = (pData['variants'] as Map? ?? {})[vId];
              if (vMeta != null) {
                final reorder = (vMeta['reorderLevel'] as num?)?.toInt() ?? 10;
                if (qty == 0) {
                  outOfStockItems++;
                } else if (qty <= reorder) {
                  lowStockItems++;
                }
              }
            }
          });
        });

        int totalLowStock = lowStockItems + outOfStockItems;

        final cards = [
          _StatCard(
            label: 'Total Orders',
            value: orders.length.toString(),
            change: 'Today: $todayOrders',
            isPositive: true,
            accentColor: AppTheme.accentGold,
            icon: Icons.shopping_bag_outlined,
          ),
          _StatCard(
            label: 'Pending Orders',
            value: pendingOrders.toString(),
            change: '0%',
            isPositive: false,
            accentColor: AppTheme.accentBlue,
            icon: Icons.schedule_outlined,
          ),
          _StatCard(
            label: 'Revenue',
            value: '₱${totalSales.toStringAsFixed(2)}',
            change: 'Today: ₱${todaySales.toStringAsFixed(0)}',
            isPositive: true,
            accentColor: AppTheme.accentRose,
            icon: Icons.paid_outlined,
          ),
          _StatCard(
            label: 'Active Variants',
            value: totalProducts.toString(),
            change: 'Total variants',
            isPositive: true,
            accentColor: AppTheme.accentGreen,
            icon: Icons.eco_outlined,
          ),
          _StatCard(
            label: 'Low Stock',
            value: totalLowStock.toString(),
            change: outOfStockItems > 0
                ? '$outOfStockItems out of stock'
                : 'Stock normal',
            isPositive: totalLowStock == 0,
            accentColor: AppTheme.accentPurple,
            icon: Icons.inventory_2_outlined,
            isWarning: totalLowStock > 0,
          ),
        ];

        return LayoutBuilder(
          builder: (context, constraints) {
            // Keep 6 cards per row on wide desktop (min 170px per card
            // + 18px gaps). Wrap to 2+ rows on narrower viewports so
            // RenderFlex overflow never breaks downstream layout
            // alignment (Recent Orders / Low Stock top edges).
            const double gap = 18;
            const double minCardWidth = 170;
            final maxWidth = constraints.maxWidth;
            final cardsPerRow = maxWidth <= 0
                ? cards.length
                : ((maxWidth + gap) / (minCardWidth + gap)).floor().clamp(
                    1,
                    cards.length,
                  );
            final cardWidth =
                ((maxWidth - (cardsPerRow - 1) * gap) / cardsPerRow).clamp(
                  minCardWidth,
                  double.infinity,
                );

            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: cards
                  .map((c) => SizedBox(width: cardWidth, child: c))
                  .toList(),
            );
          },
        );
      },
    );
  }

  DateTime? _parseDate(dynamic dateValue) {
    if (dateValue == null) return null;
    if (dateValue is DateTime) return dateValue;
    if (dateValue is int) return DateTime.fromMillisecondsSinceEpoch(dateValue);
    if (dateValue is String) return DateTime.tryParse(dateValue);
    return null;
  }

  Widget _buildSalesOverview(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppTheme.textDark : AppTheme.textLight;
    final subColor = isDark ? AppTheme.subtitleDark(isDark) : AppTheme.subtitleLight(isDark);
    final softBorder = isDark
        ? AppTheme.borderDarkAlt
        : AppTheme.borderLightAlt;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: softBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppTheme.iconBadgeGoldDark
                        : AppTheme.iconBadgeGoldLight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.receipt_long_rounded,
                    color: AppTheme.accentGold,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Recent Orders',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                      color: textColor,
                      letterSpacing: -0.1,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () {},
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'View All',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.primaryGold,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 12,
                        color: AppTheme.primaryGold,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            StreamBuilder<List<Map<String, dynamic>>>(
              stream: _supabaseData.ordersStream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Text(
                    'Unable to load recent orders: ${snapshot.error}',
                  );
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  Widget emptyState;
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    emptyState = const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 60),
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: AppTheme.primaryGold,
                          ),
                        ),
                      ),
                    );
                  } else {
                    emptyState = Column(
                      children: [
                        SizedBox(
                          width: 120,
                          height: 90,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Positioned(
                                bottom: 0,
                                child: Container(
                                  width: 100,
                                  height: 14,
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? AppTheme.iconBadgeGoldDark
                                        : AppTheme.iconBadgeGoldLight,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                ),
                              ),
                              const Icon(
                                Icons.hive_rounded,
                                size: 52,
                                color: Color(0xFFD9A441),
                              ),
                              Positioned(
                                top: 4,
                                right: 14,
                                child: Icon(
                                  Icons.local_florist_outlined,
                                  size: 20,
                                  color: isDark
                                      ? Color(0xFFE2B04A)
                                      : Color(0xFFC79A38),
                                ),
                              ),
                              Positioned(
                                top: 18,
                                left: 18,
                                child: Icon(
                                  Icons.pets_outlined,
                                  size: 18,
                                  color: isDark
                                      ? Color(0xFFF7F2E7)
                                      : Color(0xFF2B2210),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No orders yet',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: textColor,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Orders will appear here once customers place a purchase.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: subColor,
                            height: 1.4,
                          ),
                        ),
                      ],
                    );
                  }

                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      vertical: 48,
                      horizontal: 24,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppTheme.backgroundDarkAlt
                          : const Color(0xFFFFFBF1),
                      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    ),
                    child: emptyState,
                  );
                }

                final recent = snapshot.data!.take(5).toList();

                return Table(
                  columnWidths: const {
                    0: FlexColumnWidth(2.2),
                    1: FlexColumnWidth(3.2),
                    2: FlexColumnWidth(2.6),
                    3: FlexColumnWidth(2.4),
                    4: FlexColumnWidth(2.2),
                  },
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  children: [
                    TableRow(
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10, top: 4),
                          child: Text(
                            'ORDER #',
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 11.5,
                              color: subColor,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10, top: 4),
                          child: Text(
                            'CUSTOMER',
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 11.5,
                              color: subColor,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10, top: 4),
                          child: Text(
                            'DATE',
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 11.5,
                              color: subColor,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10, top: 4),
                          child: Text(
                            'STATUS',
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 11.5,
                              color: subColor,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10, top: 4),
                          child: Text(
                            'TOTAL',
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 11.5,
                              color: subColor,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                    ...recent.map((val) {
                      final orderId = val['id']?.toString() ?? '';
                      final rawDate = val['orderDate']?.toString() ?? '';
                      String displayDate = '';
                      if (rawDate.isNotEmpty) {
                        try {
                          final dt = DateTime.tryParse(rawDate);
                          if (dt != null) {
                            displayDate =
                                '${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')}/${dt.year}';
                          } else {
                            displayDate = rawDate.length > 10
                                ? rawDate.substring(0, 10)
                                : rawDate;
                          }
                        } catch (_) {
                          displayDate = rawDate.length > 10
                              ? rawDate.substring(0, 10)
                              : rawDate;
                        }
                      }
                      return TableRow(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              '#${orderId.length > 5 ? orderId.substring(0, 5).toUpperCase() : orderId.toUpperCase()}',
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                                color: textColor,
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              val['customerName'] ?? 'N/A',
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                color: textColor,
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              displayDate.isEmpty ? '—' : displayDate,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                color: subColor,
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: StatusBadge(
                                status: val['orderStatus'] ?? 'Pending',
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              '₱${val['totalAmount']}',
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                                color: textColor,
                              ),
                            ),
                          ),
                        ],
                      );
                    }),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLowStockPanel(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppTheme.textDark : AppTheme.textLight;
    final subColor = isDark ? AppTheme.subtitleDark(isDark) : AppTheme.subtitleLight(isDark);
    final warnBg = isDark
        ? AppTheme.backgroundDarkAlt
        : const Color(0xFFFFFBF1);
    final softBorder = isDark
        ? AppTheme.borderDarkAlt
        : AppTheme.borderLightAlt;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: softBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppTheme.iconBadgeAmberDark
                        : AppTheme.iconBadgeAmberLight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.warning_amber_rounded,
                    color: AppTheme.warning,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Low Stock Variants',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                      color: textColor,
                      letterSpacing: -0.1,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () {},
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'View All',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.primaryGold,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 12,
                        color: AppTheme.primaryGold,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            StreamBuilder<List<dynamic>>(
              stream: CombineLatestStream.list([
                _supabaseData.productsStream,
                _supabaseData.inventoryStream,
              ]),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Text('Unable to load stock levels: ${snapshot.error}');
                }
                Map<String, dynamic> products = {};
                Map<String, dynamic> inventory = {};
                bool waiting =
                    snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData;

                if (snapshot.hasData &&
                    snapshot.data != null &&
                    snapshot.data!.length >= 2) {
                  products = Map<String, dynamic>.from(
                    snapshot.data![0] as Map,
                  );
                  inventory = Map<String, dynamic>.from(
                    snapshot.data![1] as Map,
                  );
                }

                List<Widget> alerts = [];
                inventory.forEach((pId, pInv) {
                  (pInv as Map).forEach((vId, vData) {
                    final qty = vData['quantity'] ?? 0;
                    final pMeta = products[pId];
                    if (pMeta != null) {
                      final vMeta = (pMeta['variants'] as Map? ?? {})[vId];
                      if (vMeta != null &&
                          qty <= (vMeta['reorderLevel'] ?? 10)) {
                        final price = (vMeta['price'] ?? 0).toDouble();
                        alerts.add(
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: warnBg,
                                borderRadius: BorderRadius.circular(
                                  AppTheme.radiusMd,
                                ),
                                border: Border.all(
                                  color: isDark
                                      ? AppTheme.borderDark
                                      : AppTheme.borderLight,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? AppTheme.iconBadgeGoldDark
                                          : AppTheme.iconBadgeGoldLight,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: isDark
                                            ? AppTheme.badgeGoldBorderDark
                                            : AppTheme.badgeGoldBorderLight,
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.breakfast_dining_rounded,
                                      color: Color(0xFFD9A441),
                                      size: 22,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${pMeta['variety'] ?? 'Honey'} ${vMeta['size'] ?? ''}',
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w800,
                                            color: textColor,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '₱${price.toStringAsFixed(2)}',
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: subColor,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? AppTheme.badgeRedBgDark
                                          : AppTheme.badgeRedBgLight,
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      '$qty',
                                      style: TextStyle(
                                        color: AppTheme.error,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }
                    }
                  });
                });

                if (waiting || alerts.isEmpty) {
                  Widget inner;
                  if (waiting) {
                    inner = const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 60),
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: AppTheme.primaryGold,
                          ),
                        ),
                      ),
                    );
                  } else {
                    inner = Column(
                      children: [
                        const SizedBox(height: 10),
                        Icon(
                          Icons.verified_outlined,
                          size: 48,
                          color: AppTheme.success,
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'All stock levels normal.',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: textColor,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'You will be notified when any variant hits its reorder level.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: subColor,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                    );
                  }
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      vertical: 48,
                      horizontal: 24,
                    ),
                    decoration: BoxDecoration(
                      color: warnBg,
                      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    ),
                    child: inner,
                  );
                }
                return ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 360),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(right: 6),
                    child: Column(children: alerts),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentActivityPanel(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppTheme.textDark : AppTheme.textLight;
    final subColor = isDark ? AppTheme.subtitleDark(isDark) : AppTheme.subtitleLight(isDark);
    final softBorder = isDark
        ? AppTheme.borderDarkAlt
        : AppTheme.borderLightAlt;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: softBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppTheme.iconBadgeGreenDark
                        : AppTheme.iconBadgeGreenLight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.timeline_rounded,
                    color: AppTheme.accentGreen,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Recent Inventory Activity',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                      color: textColor,
                      letterSpacing: -0.1,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            StreamBuilder<List<Map<String, dynamic>>>(
              stream: _supabaseData.inventoryMovementsStream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Text(
                    'Unable to load inventory activity: ${snapshot.error}',
                    style: TextStyle(color: subColor),
                  );
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Text(
                      'No activity log.',
                      style: TextStyle(color: subColor),
                    ),
                  );
                }

                return Column(
                  children: snapshot.data!.take(5).map((m) {
                    final change = (m['quantity_change'] as num?)?.toInt() ?? 0;
                    final isAdd = change > 0;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: isAdd
                                  ? (isDark
                                        ? AppTheme.iconBadgeGreenDark
                                        : AppTheme.iconBadgeGreenLight)
                                  : (isDark
                                        ? AppTheme.badgeRedBgDark
                                        : AppTheme.badgeRedBgLight),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              isAdd ? Icons.add_rounded : Icons.remove_rounded,
                              color: isAdd ? AppTheme.success : AppTheme.error,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${m['movement_type'].toString().replaceAll('_', ' ').toUpperCase()} - ${isAdd ? '+' : ''}$change bottles',
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                    color: textColor,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Ref: ${m['reference_id'] ?? '—'}',
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: subColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            (m['new_quantity'] ?? 0).toString(),
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                              color: textColor,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── Revenue Trend Chart ───────────────────────────────────────────────
  Widget _buildRevenueTrendSection() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppTheme.textDark : AppTheme.textLight;
    final subColor = isDark ? AppTheme.subtitleDark(isDark) : AppTheme.subtitleLight(isDark);
    final softBorder = isDark
        ? AppTheme.borderDarkAlt
        : AppTheme.borderLightAlt;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: softBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppTheme.iconBadgeGoldDark
                        : AppTheme.iconBadgeGoldLight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.show_chart_rounded,
                    color: AppTheme.accentGold,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Revenue Trend',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                      color: textColor,
                      letterSpacing: -0.1,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Row(
                  children: [
                    _filterChip('7 Days', _revenueFilter == '7 Days'),
                    const SizedBox(width: 8),
                    _filterChip('30 Days', _revenueFilter == '30 Days'),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 200,
              child: StreamBuilder<List<Map<String, dynamic>>>(
                stream: _supabaseData.ordersStream,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        'Unable to load sales data: ${snapshot.error}',
                        style: TextStyle(color: subColor),
                      ),
                    );
                  }
                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return Center(
                      child: Text(
                        'No sales data yet',
                        style: TextStyle(color: subColor),
                      ),
                    );
                  }

                  final ordersMap = _ordersById(snapshot.data!);

                  final days = _revenueFilter == '7 Days' ? 7 : 30;
                  final revenueData = _calculateRevenueByDay(ordersMap, days);

                  if (revenueData.isEmpty) {
                    return Center(
                      child: Text(
                        'No sales data for selected period',
                        style: TextStyle(color: subColor),
                      ),
                    );
                  }

                  return LineChart(
                    LineChartData(
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval:
                            _calculateMaxRevenue(revenueData) / 4,
                        getDrawingHorizontalLine: (value) => FlLine(
                          color: isDark
                              ? AppTheme.borderDark
                              : AppTheme.borderLight,
                          strokeWidth: 1,
                        ),
                      ),
                      titlesData: FlTitlesData(
                        show: true,
                        rightTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        topTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (value, meta) {
                              final index = value.toInt();
                              if (index < 0 || index >= revenueData.length) {
                                return const SizedBox();
                              }
                              final date = revenueData[index]['date'] as String;
                              return Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  date,
                                  style: TextStyle(
                                    color: subColor,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              );
                            },
                            reservedSize: 30,
                          ),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 50,
                            getTitlesWidget: (value, meta) {
                              return Text(
                                '₱${value.toInt()}',
                                style: TextStyle(
                                  color: subColor,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      lineBarsData: [
                        LineChartBarData(
                          spots: revenueData.asMap().entries.map((entry) {
                            return FlSpot(
                              entry.key.toDouble(),
                              (entry.value['revenue'] as num).toDouble(),
                            );
                          }).toList(),
                          isCurved: true,
                          color: AppTheme.accentGold,
                          barWidth: 3,
                          isStrokeCapRound: true,
                          dotData: FlDotData(
                            show: true,
                            getDotPainter: (spot, percent, barData, index) {
                              return FlDotCirclePainter(
                                radius: 4,
                                color: AppTheme.accentGold,
                                strokeWidth: 2,
                                strokeColor: isDark
                                    ? AppTheme.surfaceDark
                                    : Colors.white,
                              );
                            },
                          ),
                          belowBarData: BarAreaData(
                            show: true,
                            color: AppTheme.accentGold.withValues(alpha: 0.1),
                          ),
                        ),
                      ],
                      minX: 0,
                      maxX: (revenueData.length - 1).toDouble(),
                      minY: 0,
                      maxY: _calculateMaxRevenue(revenueData),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(String label, bool isSelected) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final subColor = isDark ? AppTheme.subtitleDark(isDark) : AppTheme.subtitleLight(isDark);
    return GestureDetector(
      onTap: () {
        setState(() => _revenueFilter = label);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.accentGold
              : (isDark ? AppTheme.backgroundDarkAlt : const Color(0xFFFFFBF1)),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: isSelected ? Colors.white : subColor,
          ),
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _calculateRevenueByDay(
    Map<String, dynamic> orders,
    int days,
  ) {
    final now = DateTime.now();
    final Map<String, double> dailyRevenue = {};

    for (int i = days - 1; i >= 0; i--) {
      final date = now.subtract(Duration(days: i));
      final dateKey = '${date.month}/${date.day}';
      dailyRevenue[dateKey] = 0.0;
    }

    orders.forEach((k, v) {
      if (v['orderStatus'] == 'Completed') {
        final orderDate = _parseDate(v['orderDate'] ?? v['date']);
        if (orderDate != null) {
          final diff = now.difference(orderDate).inDays;
          if (diff >= 0 && diff < days) {
            final dateKey = '${orderDate.month}/${orderDate.day}';
            final amount = (v['totalAmount'] ?? 0).toDouble();
            dailyRevenue[dateKey] = (dailyRevenue[dateKey] ?? 0) + amount;
          }
        }
      }
    });

    return dailyRevenue.entries.map((e) {
      return {'date': e.key, 'revenue': e.value};
    }).toList();
  }

  double _calculateMaxRevenue(List<Map<String, dynamic>> data) {
    if (data.isEmpty) return 100;
    final maxRevenue = data
        .map((e) => (e['revenue'] as num).toDouble())
        .reduce((a, b) => a > b ? a : b);
    return maxRevenue > 0 ? maxRevenue * 1.1 : 100;
  }

  // ── Order Completion Rate ─────────────────────────────────────────────
  Widget _buildOrderCompletionRate() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppTheme.textDark : AppTheme.textLight;
    final subColor = isDark ? AppTheme.subtitleDark(isDark) : AppTheme.subtitleLight(isDark);
    final softBorder = isDark
        ? AppTheme.borderDarkAlt
        : AppTheme.borderLightAlt;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: softBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppTheme.iconBadgeGreenDark
                        : AppTheme.iconBadgeGreenLight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.check_circle_outline,
                    color: AppTheme.accentGreen,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Order Completion Rate',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                      color: textColor,
                      letterSpacing: -0.1,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            StreamBuilder<List<Map<String, dynamic>>>(
              stream: _supabaseData.ordersStream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Text(
                    'Unable to load order completion data: ${snapshot.error}',
                    style: TextStyle(color: subColor),
                  );
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return Center(
                    child: Text(
                      'No orders yet',
                      style: TextStyle(color: subColor),
                    ),
                  );
                }

                final ordersMap = _ordersById(snapshot.data!);

                int completed = 0;
                int pending = 0;
                int total = ordersMap.length;

                ordersMap.forEach((k, v) {
                  final status = v['orderStatus'] as String? ?? '';
                  if (status == 'Completed') {
                    completed++;
                  } else if (status == 'Pending' ||
                      status == 'Processing' ||
                      status == 'Confirmed') {
                    pending++;
                  }
                });

                final rate = total > 0 ? (completed / total * 100) : 0.0;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${rate.toStringAsFixed(0)}%',
                          style: TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.w900,
                            color: AppTheme.accentGreen,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$completed completed',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: textColor,
                                ),
                              ),
                              Text(
                                '$pending remaining',
                                style: TextStyle(fontSize: 12, color: subColor),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                      child: LinearProgressIndicator(
                        value: rate / 100,
                        backgroundColor: isDark
                            ? AppTheme.backgroundDarkAlt
                            : AppTheme.backgroundLightAlt,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          AppTheme.accentGreen,
                        ),
                        minHeight: 10,
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── Customer Overview ───────────────────────────────────────────────────
  Widget _buildCustomerOverview() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppTheme.textDark : AppTheme.textLight;
    final subColor = isDark ? AppTheme.subtitleDark(isDark) : AppTheme.subtitleLight(isDark);
    final softBorder = isDark
        ? AppTheme.borderDarkAlt
        : AppTheme.borderLightAlt;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: softBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppTheme.iconBadgeBlueDark
                        : AppTheme.iconBadgeBlueLight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.people_outline,
                    color: AppTheme.accentBlue,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Customer Summary',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                      color: textColor,
                      letterSpacing: -0.1,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            StreamBuilder<List<dynamic>>(
              stream: CombineLatestStream.list([
                _supabaseData.customersStream,
                _supabaseData.ordersStream,
              ]),
              builder: (context, snapshot) {
                List<Map<String, dynamic>> customers = [];
                Map<String, dynamic> ordersMap = {};

                if (snapshot.hasData &&
                    snapshot.data != null &&
                    snapshot.data!.length >= 2) {
                  customers = (snapshot.data![0] as List)
                      .cast<Map<String, dynamic>>();
                  ordersMap = _ordersById(
                    (snapshot.data![1] as List).cast<Map<String, dynamic>>(),
                  );
                }

                final totalCustomers = customers.length;
                final now = DateTime.now();
                final monthAgo = now.subtract(const Duration(days: 30));

                int newCustomers = 0;
                for (final customer in customers) {
                  final createdAt = customer['created_at'];
                  if (createdAt != null) {
                    final createdDate = DateTime.tryParse(createdAt.toString());
                    if (createdDate != null && createdDate.isAfter(monthAgo)) {
                      newCustomers++;
                    }
                  }
                }

                final customerOrders = <String, int>{};
                ordersMap.forEach((k, v) {
                  final customerEmail = v['customerEmail'] as String?;
                  if (customerEmail != null) {
                    customerOrders[customerEmail] =
                        (customerOrders[customerEmail] ?? 0) + 1;
                  }
                });

                final returningCustomers = customerOrders.values
                    .where((count) => count > 1)
                    .length;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _customerMetric(
                      'Total Customers',
                      totalCustomers.toString(),
                      textColor,
                      subColor,
                      isDark,
                    ),
                    const SizedBox(height: 10),
                    _customerMetric(
                      'New Customers (30d)',
                      newCustomers.toString(),
                      textColor,
                      subColor,
                      isDark,
                    ),
                    const SizedBox(height: 10),
                    _customerMetric(
                      'Returning Customers',
                      returningCustomers.toString(),
                      textColor,
                      subColor,
                      isDark,
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _customerMetric(
    String label,
    String value,
    Color textColor,
    Color subColor,
    bool isDark,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.backgroundDarkAlt : AppTheme.backgroundLightAlt,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: subColor,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: isDark ? AppTheme.surfaceDark : Colors.white,
              borderRadius: BorderRadius.circular(AppTheme.radiusPill),
            ),
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: textColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Operational Alerts ─────────────────────────────────────────────────
  Widget _buildOperationalAlerts() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppTheme.textDark : AppTheme.textLight;
    final subColor = isDark ? AppTheme.subtitleDark(isDark) : AppTheme.subtitleLight(isDark);
    final softBorder = isDark
        ? AppTheme.borderDarkAlt
        : AppTheme.borderLightAlt;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: softBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppTheme.iconBadgeAmberDark
                        : AppTheme.iconBadgeAmberLight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.notifications_active_outlined,
                    color: AppTheme.warning,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Operational Alerts',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                      color: textColor,
                      letterSpacing: -0.1,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            StreamBuilder<List<dynamic>>(
              stream: CombineLatestStream.list([
                _supabaseData.productsStream,
                _supabaseData.inventoryStream,
                _supabaseData.ordersStream,
                _scanResultsStream,
              ]),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Text(
                    'Unable to load operational alerts: ${snapshot.error}',
                    style: TextStyle(color: subColor),
                  );
                }
                if (!snapshot.hasData ||
                    snapshot.data == null ||
                    snapshot.data!.length < 4) {
                  return Center(
                    child: Text(
                      'Loading alerts...',
                      style: TextStyle(color: subColor),
                    ),
                  );
                }

                final products = Map<String, dynamic>.from(
                  snapshot.data![0] as Map,
                );
                final inventory = Map<String, dynamic>.from(
                  snapshot.data![1] as Map,
                );
                final orders = _ordersById(
                  (snapshot.data![2] as List).cast<Map<String, dynamic>>(),
                );
                final scanState = snapshot.data![3] as _DashboardScanResults;
                final scanResults = scanState.values;

                final alerts = <Widget>[];

                // Critical: Out of stock
                int outOfStockCount = 0;
                inventory.forEach((pId, pInv) {
                  (pInv as Map).forEach((vId, vData) {
                    final qty = vData['quantity'] ?? 0;
                    if (qty == 0) {
                      final pData = products[pId];
                      if (pData != null) {
                        final vMeta = (pData['variants'] as Map? ?? {})[vId];
                        if (vMeta != null && outOfStockCount < 3) {
                          final variety = pData['variety'] ?? 'Honey';
                          final size = vMeta['size'] ?? '';
                          alerts.add(
                            _alertItem(
                              'CRITICAL',
                              '$variety — $size — Out of Stock',
                              Colors.red,
                              Icons.error_outline,
                            ),
                          );
                          outOfStockCount++;
                        }
                      }
                    }
                  });
                });

                // Pending payments
                int pendingPayments = 0;
                orders.forEach((k, v) {
                  final paymentStatus = v['paymentStatus'] as String? ?? '';
                  if (paymentStatus == 'Pending Verification') {
                    pendingPayments++;
                  }
                });
                if (pendingPayments > 0) {
                  alerts.add(
                    _alertItem(
                      'PAYMENT',
                      '$pendingPayments payments waiting for verification',
                      AppTheme.warning,
                      Icons.payment_outlined,
                    ),
                  );
                }

                // IoT scan mismatches
                int scanMismatches = 0;
                scanResults.forEach((k, v) {
                  final status = v['status'] as String? ?? '';
                  final isAcknowledged = v['isAcknowledged'] as bool? ?? false;
                  if (status == 'MISMATCH' && !isAcknowledged) {
                    scanMismatches++;
                  }
                });
                if (scanMismatches > 0) {
                  alerts.add(
                    _alertItem(
                      'IOT',
                      '$scanMismatches inventory scan mismatches require review',
                      AppTheme.warning,
                      Icons.camera_alt_outlined,
                    ),
                  );
                }
                if (scanState.error != null) {
                  alerts.add(
                    _alertItem(
                      'IOT',
                      'IoT scan status is unavailable; Firebase access was denied.',
                      AppTheme.warning,
                      Icons.camera_alt_outlined,
                    ),
                  );
                }

                if (alerts.isEmpty) {
                  return Container(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Row(
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          color: AppTheme.success,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'All systems operational',
                          style: TextStyle(
                            color: AppTheme.success,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return Column(children: alerts.take(5).toList());
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _alertItem(
    String category,
    String message,
    Color color,
    IconData icon,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppTheme.textDark : AppTheme.textLight;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    category,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: color,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    message,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Quick Actions ───────────────────────────────────────────────────────
  Widget _buildQuickActions() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppTheme.textDark : AppTheme.textLight;
    final softBorder = isDark
        ? AppTheme.borderDarkAlt
        : AppTheme.borderLightAlt;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: softBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppTheme.iconBadgeGoldDark
                        : AppTheme.iconBadgeGoldLight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.flash_on_outlined,
                    color: AppTheme.accentGold,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Quick Actions',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                      color: textColor,
                      letterSpacing: -0.1,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                // Write-leading operational actions — Co-Admin only.
                if (RoleCapabilities.forRole(widget.session.role).canRunProduction)
                  _quickActionButton(
                    'Create Production',
                    Icons.factory_outlined,
                    () => _navigateToProduction(),
                  ),
                if (RoleCapabilities.forRole(widget.session.role).canAdjustStock)
                  _quickActionButton(
                    'Initiate IoT Scan',
                    Icons.camera_alt_outlined,
                    () => _navigateToInventory(),
                  ),
                if (RoleCapabilities.forRole(widget.session.role).canManageOrders)
                  _quickActionButton(
                    'Verify Payments',
                    Icons.payment_outlined,
                    () => _navigateToCustomers(),
                  ),
                // Read-only navigation — visible to all roles.
                _quickActionButton(
                  'View Orders',
                  Icons.shopping_bag_outlined,
                  () => _navigateToOrders(),
                ),
                _quickActionButton(
                  'Generate Report',
                  Icons.bar_chart_outlined,
                  () => _navigateToReports(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickActionButton(String label, IconData icon, VoidCallback onTap) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppTheme.textDark : AppTheme.textLight;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.backgroundDarkAlt : const Color(0xFFFFFBF1),
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          border: Border.all(
            color: isDark ? AppTheme.borderDark : AppTheme.borderLight,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: AppTheme.accentGold),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToProduction() {
    // Navigate to production page - shows message for now
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Navigate to Production page')),
    );
  }

  void _navigateToInventory() {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Navigate to Inventory page')));
  }

  void _navigateToCustomers() {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Navigate to Customers page')));
  }

  void _navigateToOrders() {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Navigate to Orders page')));
  }

  void _navigateToReports() {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Navigate to Reports page')));
  }

  // ── Top Selling Products ───────────────────────────────────────────────
  Widget _buildTopSellingProducts() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppTheme.textDark : AppTheme.textLight;
    final subColor = isDark ? AppTheme.subtitleDark(isDark) : AppTheme.subtitleLight(isDark);
    final softBorder = isDark
        ? AppTheme.borderDarkAlt
        : AppTheme.borderLightAlt;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: softBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppTheme.iconBadgeGoldDark
                        : AppTheme.iconBadgeGoldLight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.star_outline,
                    color: AppTheme.accentGold,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Top Selling Products',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                      color: textColor,
                      letterSpacing: -0.1,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            StreamBuilder<List<dynamic>>(
              stream: CombineLatestStream.list([
                _supabaseData.ordersStream,
                _supabaseData.productsStream,
              ]),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Text(
                    'Unable to load top-selling products: ${snapshot.error}',
                    style: TextStyle(color: subColor),
                  );
                }
                if (!snapshot.hasData ||
                    snapshot.data == null ||
                    snapshot.data!.length < 2) {
                  return Center(
                    child: Text(
                      'Loading...',
                      style: TextStyle(color: subColor),
                    ),
                  );
                }

                final ordersMap = _ordersById(
                  (snapshot.data![0] as List).cast<Map<String, dynamic>>(),
                );
                final productsMap = Map<String, dynamic>.from(
                  snapshot.data![1] as Map,
                );
                final productsByUuid = {
                  for (final product in productsMap.values)
                    if (product['uuid'] != null)
                      product['uuid'].toString(): product,
                };

                final productSales = <String, Map<String, dynamic>>{};

                ordersMap.forEach((orderId, order) {
                  if (order['orderStatus'] == 'Completed') {
                    final items = order['items'];
                    if (items is Map) {
                      items.forEach((itemId, item) {
                        final productId = item['productId'] as String?;
                        final variantId = item['variantId'] as String?;
                        final quantity = item['quantity'] as int? ?? 0;
                        final price = item['unitPrice'] as num? ?? 0;

                        if (productId != null && variantId != null) {
                          final key = '$productId-$variantId';
                          if (!productSales.containsKey(key)) {
                            final pData = productsByUuid[productId];
                            final variants = pData?['variants'] as Map? ?? {};
                            Map? vData;
                            for (final variant in variants.values) {
                              if (variant is Map &&
                                  variant['uuid']?.toString() == variantId) {
                                vData = variant;
                                break;
                              }
                            }
                            productSales[key] = {
                              'productId': productId,
                              'variantId': variantId,
                              'variety': pData?['variety'] ?? 'Honey',
                              'size': vData?['size'] ?? '',
                              'quantity': 0,
                              'revenue': 0.0,
                            };
                          }
                          productSales[key]!['quantity'] =
                              (productSales[key]!['quantity'] as int) +
                              quantity;
                          productSales[key]!['revenue'] =
                              (productSales[key]!['revenue'] as num) +
                              (quantity * price);
                        }
                      });
                    }
                  }
                });

                final sorted = productSales.values.toList()
                  ..sort(
                    (a, b) =>
                        (b['quantity'] as int).compareTo(a['quantity'] as int),
                  );

                if (sorted.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Text(
                        'No sales data yet',
                        style: TextStyle(color: subColor),
                      ),
                    ),
                  );
                }

                return Column(
                  children: sorted.take(5).map((product) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: isDark
                                  ? AppTheme.iconBadgeGoldDark
                                  : AppTheme.iconBadgeGoldLight,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.breakfast_dining_rounded,
                              color: AppTheme.accentGold,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${product['variety']} | ${product['size']}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: textColor,
                                  ),
                                ),
                                Text(
                                  '${product['quantity']} sold',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: subColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '₱${(product['revenue'] as num).toStringAsFixed(0)}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: textColor,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── Top Customers ───────────────────────────────────────────────────────
  Widget _buildTopCustomers() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppTheme.textDark : AppTheme.textLight;
    final subColor = isDark ? AppTheme.subtitleDark(isDark) : AppTheme.subtitleLight(isDark);
    final softBorder = isDark
        ? AppTheme.borderDarkAlt
        : AppTheme.borderLightAlt;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: softBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppTheme.iconBadgeBlueDark
                        : AppTheme.iconBadgeBlueLight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.person_outline,
                    color: AppTheme.accentBlue,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Top Customers',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                      color: textColor,
                      letterSpacing: -0.1,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            StreamBuilder<List<Map<String, dynamic>>>(
              stream: _supabaseData.ordersStream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Text(
                    'Unable to load top customers: ${snapshot.error}',
                    style: TextStyle(color: subColor),
                  );
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return Center(
                    child: Text(
                      'Loading...',
                      style: TextStyle(color: subColor),
                    ),
                  );
                }

                final ordersMap = _ordersById(snapshot.data!);

                final customerStats = <String, Map<String, dynamic>>{};

                ordersMap.forEach((orderId, order) {
                  if (order['orderStatus'] == 'Completed') {
                    final customerEmail = order['customerEmail'] as String?;
                    final customerName =
                        order['customerName'] as String? ?? 'Unknown';
                    final amount =
                        (order['totalAmount'] as num?)?.toDouble() ?? 0.0;

                    if (customerEmail != null) {
                      if (!customerStats.containsKey(customerEmail)) {
                        customerStats[customerEmail] = {
                          'name': customerName,
                          'email': customerEmail,
                          'orderCount': 0,
                          'totalSpending': 0.0,
                        };
                      }
                      customerStats[customerEmail]!['orderCount'] =
                          (customerStats[customerEmail]!['orderCount'] as int) +
                          1;
                      customerStats[customerEmail]!['totalSpending'] =
                          (customerStats[customerEmail]!['totalSpending']
                              as double) +
                          amount;
                    }
                  }
                });

                final sorted = customerStats.values.toList()
                  ..sort(
                    (a, b) => (b['totalSpending'] as double).compareTo(
                      a['totalSpending'] as double,
                    ),
                  );

                if (sorted.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Text(
                        'No customer data yet',
                        style: TextStyle(color: subColor),
                      ),
                    ),
                  );
                }

                return Column(
                  children: sorted.take(5).map((customer) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: isDark
                                  ? AppTheme.iconBadgeBlueDark
                                  : AppTheme.iconBadgeBlueLight,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              Icons.person_outline,
                              color: AppTheme.accentBlue,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  customer['name'] as String,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: textColor,
                                  ),
                                ),
                                Text(
                                  '${customer['orderCount']} orders',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: subColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '₱${(customer['totalSpending'] as double).toStringAsFixed(0)}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: textColor,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String change;
  final bool isPositive;
  final Color accentColor;
  final IconData icon;
  final bool isWarning;

  const _StatCard({
    required this.label,
    required this.value,
    required this.change,
    required this.isPositive,
    required this.accentColor,
    required this.icon,
    this.isWarning = false,
  });

  Color _badgeBg(bool isDark) {
    if (accentColor == AppTheme.accentGold) {
      return isDark ? AppTheme.iconBadgeGoldDark : AppTheme.iconBadgeGoldLight;
    }
    if (accentColor == AppTheme.accentBlue) {
      return isDark ? AppTheme.iconBadgeBlueDark : AppTheme.iconBadgeBlueLight;
    }
    if (accentColor == AppTheme.accentGreen) {
      return isDark
          ? AppTheme.iconBadgeGreenDark
          : AppTheme.iconBadgeGreenLight;
    }
    if (accentColor == AppTheme.accentPurple) {
      return isDark
          ? AppTheme.iconBadgePurpleDark
          : AppTheme.iconBadgePurpleLight;
    }
    if (accentColor == AppTheme.accentRose) {
      return isDark ? AppTheme.iconBadgeRoseDark : AppTheme.iconBadgeRoseLight;
    }
    return isDark ? AppTheme.iconBadgeGoldDark : AppTheme.iconBadgeGoldLight;
  }

  Color _trendBg(bool isDark) {
    if (isPositive) {
      return isDark ? AppTheme.badgeGreenBgDark : AppTheme.badgeGreenBgLight;
    }
    return isDark ? AppTheme.badgeRedBgDark : AppTheme.badgeRedBgLight;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final valueColor = isWarning
        ? AppTheme.warning
        : isDark
        ? AppTheme.textDark
        : AppTheme.textLight;
    final subColor = isDark ? AppTheme.subtitleDark(isDark) : AppTheme.subtitleLight(isDark);
    final chevronColor = isDark
        ? const Color(0xFF6B6357)
        : const Color(0xFF9A9080);
    final trendColor = isPositive ? AppTheme.success : AppTheme.error;
    final arrow = isPositive ? Icons.north_rounded : Icons.south_rounded;
    final baseBorder = isDark
        ? AppTheme.borderDarkAlt
        : AppTheme.borderLightAlt;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(
          color: baseBorder,
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? const Color(0xFF080705).withValues(alpha: 0.4)
                : const Color(0xFFEADFC8).withValues(alpha: 0.45),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        child: Stack(
          children: [
            // Subtle accent gradient at top/edge
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 3,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      accentColor.withValues(alpha: 0.7),
                      accentColor.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: _badgeBg(isDark),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: accentColor.withValues(alpha: 0.2),
                            width: 1,
                          ),
                        ),
                        child: Icon(icon, color: accentColor, size: 21),
                      ),
                      const Spacer(),
                      Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: isDark
                              ? AppTheme.backgroundDarkAlt.withValues(alpha: 0.5)
                              : AppTheme.backgroundLightAlt.withValues(alpha: 0.8),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 11,
                          color: chevronColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    label,
                    style: TextStyle(
                      color: subColor,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 25,
                      fontWeight: FontWeight.w900,
                      color: valueColor,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3.5,
                    ),
                    decoration: BoxDecoration(
                      color: _trendBg(isDark),
                      borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                      border: Border.all(
                        color: trendColor.withValues(alpha: 0.2),
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(arrow, size: 11, color: trendColor),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            change,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            style: TextStyle(
                              color: trendColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
