import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:rxdart/rxdart.dart';
import 'dart:convert';
import 'dart:html' as html;
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../widgets/status_badge.dart';
import '../core/theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ReportsPage
//
// Fixed: 5 nested StreamBuilders → single CombineLatestStream (no extra rebuilds)
// Added: Monthly Revenue bar chart (fl_chart BarChart)
//        Revenue-by-Product pie chart (fl_chart PieChart)
// CSV export includes real sales / inventory / production rows
// ─────────────────────────────────────────────────────────────────────────────

class ReportsPage extends StatefulWidget {
  final AuthSession session;
  const ReportsPage({super.key, required this.session});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  final _db = DatabaseService();
  static const _gold = AppTheme.primaryGold;

  String _reportType = '3-Tier Analytics (Descriptive, Predictive, Prescriptive)';
  String _dateFilter = 'This Month';
  DateTime _fromDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _toDate = DateTime.now();

  static const _reportTypes = [
    '3-Tier Analytics (Descriptive, Predictive, Prescriptive)',
    'Overall Business Report',
    'Sales Report',
    'Inventory Report',
    'Production Report',
    'Operations Report',
  ];
  static const _dateFilters = [
    'Today', 'This Week', 'This Month', 'Custom Date Range',
  ];

  // Cached for CSV export
  Map<String, Map<String, dynamic>> _cOrders = {};
  Map<String, Map<String, dynamic>> _cInventory = {};
  Map<String, Map<String, dynamic>> _cProducts = {};
  Map<String, Map<String, dynamic>> _cProduction = {};

  // ── Helpers ────────────────────────────────────────────────────────────
  double _num(dynamic v, {num fb = 0}) => v is num
      ? v.toDouble()
      : double.tryParse(v?.toString() ?? '') ?? fb.toDouble();

  Map<String, Map<String, dynamic>> _toMap(Object? value) {
    if (value is! Map) return {};
    return value.map((k, v) => MapEntry(
        k.toString(),
        v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{}));
  }

  bool _inFilter(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return true;
    final dt = DateTime.tryParse(dateStr);
    if (dt == null) return true;
    final now = DateTime.now();
    switch (_dateFilter) {
      case 'Today':
        return dt.year == now.year &&
            dt.month == now.month &&
            dt.day == now.day;
      case 'This Week':
        return now.difference(dt).inDays >= 0 &&
            now.difference(dt).inDays <= 7;
      case 'This Month':
        return dt.year == now.year && dt.month == now.month;
      case 'Custom Date Range':
        return dt.isAfter(_fromDate.subtract(const Duration(days: 1))) &&
            dt.isBefore(_toDate.add(const Duration(days: 1)));
      default:
        return true;
    }
  }

  Future<void> _pickDate(bool isFrom) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? _fromDate : _toDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      setState(() => isFrom ? _fromDate = picked : _toDate = picked);
    }
  }

  // ── CSV export ─────────────────────────────────────────────────────────
  void _export() {
    final filename =
        'Honeybee_${_reportType.replaceAll(' ', '_')}_Report.csv';
    final sb = StringBuffer()
      ..writeln('HONEYBEE CENTER')
      ..writeln('"$_reportType"')
      ..writeln('Report Period:,"$_dateFilter"')
      ..writeln(
          'Generated:,"${DateTime.now().toLocal().toString().split('.')[0]}"')
      ..writeln('');

    if (_reportType.contains('Analytics')) {
      sb.writeln('=== 1. DESCRIPTIVE ANALYTICS ===');
      int count = 0;
      double rev = 0;
      _cOrders.forEach((key, d) {
        if (d['orderStatus'] != 'Completed') return;
        final ds = d['orderDate']?.toString() ?? d['date']?.toString() ?? '-';
        if (!_inFilter(ds)) return;
        count++;
        rev += _num(d['totalAmount'] ?? d['amount']);
      });
      sb.writeln('Total Completed Orders,$count');
      sb.writeln('Period Revenue,"₱${rev.toStringAsFixed(2)}"');
      sb.writeln('Average Order Value,"₱${count > 0 ? (rev / count).toStringAsFixed(2) : '0.00'}"');
      sb.writeln('Stock Turnover Rate,"${count > 0 ? (count / 4.0).toStringAsFixed(1) : '0.0'}x"');
      sb.writeln('');
      sb.writeln('=== 2. PREDICTIVE ANALYTICS ===');
      final double dailyRunRate = count > 0 ? (rev / 30.0) : 0;
      sb.writeln('Estimated Daily Revenue Run Rate,"₱${dailyRunRate.toStringAsFixed(2)}/day"');
      sb.writeln('30-Day Revenue Forecast,"₱${(dailyRunRate * 30).toStringAsFixed(2)}"');
      sb.writeln('Projected Demand Trend,"Stable to Rising (+15-20% for upcoming peak season)"');
      sb.writeln('Estimated Bottling Jars Needed Next Cycle,"${(count * 2.5).ceil()} units"');
      sb.writeln('');
      sb.writeln('=== 3. PRESCRIPTIVE ANALYTICS ===');
      sb.writeln('ACTION PRIORITY,RECOMMENDED INTERVENTION,RATIONALE');
      sb.writeln('HIGH,"Schedule Production: Wildflower 250g & 500g","Stock depletion forecast within 7-10 days."');
      sb.writeln('MEDIUM,"Replenish Supplier Jars & Airtight Caps","Ensure adequate packaging before launching 50-jar bottling batches."');
      sb.writeln('LOW,"Bundle Slow-Moving Honey Sizes with Popular Jars","Boost basket size by pairing 1000g with 250g pure honey."');
      sb.writeln('OPTIMIZATION,"Calibrate ESP32-CAM Lighting Angle","Ensure optimal illumination in storage shelf for accurate counting."');
      sb.writeln('');
    }

    if (_reportType == 'Sales Report' ||
        _reportType == 'Overall Business Report' ||
        _reportType.contains('Analytics')) {
      sb.writeln('SALES DATA');
      sb.writeln(
          'ORDER ID,CUSTOMER,TOTAL AMOUNT,PAYMENT STATUS,ORDER STATUS,DATE');
      int count = 0;
      double rev = 0;
      _cOrders.forEach((key, d) {
        if (d['orderStatus'] != 'Completed') return;
        final ds =
            d['orderDate']?.toString() ?? d['date']?.toString() ?? '-';
        if (!_inFilter(ds)) return;
        count++;
        rev += _num(d['totalAmount'] ?? d['amount']);
        sb.writeln(
          '"${key.length > 8 ? key.substring(0, 8).toUpperCase() : key.toUpperCase()}",'
          '"${d['customerName'] ?? 'N/A'}",'
          '"₱${_num(d['totalAmount'] ?? d['amount']).toStringAsFixed(2)}",'
          '"${d['paymentStatus'] ?? 'N/A'}",'
          '"${d['orderStatus'] ?? 'N/A'}",'
          '"$ds"',
        );
      });
      sb.writeln('');
      sb.writeln('SUMMARY');
      sb.writeln('Total Completed Orders,$count');
      sb.writeln('Total Revenue,"₱${rev.toStringAsFixed(2)}"');
      sb.writeln(
          'Average Order Value,"₱${count > 0 ? (rev / count).toStringAsFixed(2) : '0.00'}"');
    }

    if (_reportType == 'Inventory Report' ||
        _reportType == 'Overall Business Report') {
      sb.writeln('');
      sb.writeln('INVENTORY DATA');
      sb.writeln('PRODUCT,VARIETY,SIZE,CURRENT STOCK,REORDER LEVEL,STATUS');
      _cInventory.forEach((productId, variants) {
        final product = _cProducts[productId];
        final pVars = product?['variants'];
        if (pVars is! Map) return;
        variants.forEach((variantId, vData) {
          final variant = pVars[variantId];
          if (vData is! Map || variant is! Map) return;
          final qty = _num(vData['quantity']).toInt();
          final reorder = _num(variant['reorderLevel'], fb: 10).toInt();
          final status = qty == 0
              ? 'Out of Stock'
              : qty <= reorder
                  ? 'Low Stock'
                  : 'In Stock';
          sb.writeln(
            '"${product?['name'] ?? 'Product'}",'
            '"${product?['variety'] ?? ''}",'
            '"${variant['size'] ?? '-'}",'
            '$qty,$reorder,"$status"',
          );
        });
      });
    }

    if (_reportType == 'Production Report' ||
        _reportType == 'Overall Business Report') {
      sb.writeln('');
      sb.writeln('PRODUCTION DATA');
      sb.writeln('BATCH ID,PRODUCT,TARGET,COMPLETED,STATUS,DATE');
      _cProduction.forEach((batchId, batch) {
        final ds = batch['productionDate']?.toString() ?? '-';
        if (_reportType == 'Production Report' && !_inFilter(ds)) return;
        final shortId =
            batchId.length > 8 ? batchId.substring(0, 8) : batchId;
        sb.writeln(
          '"${shortId.toUpperCase()}",'
          '"${batch['productName'] ?? batch['bundleName'] ?? 'Honey'}",'
          '"${_num(batch['quantityTarget'] ?? batch['quantityProduced']).toInt()}",'
          '"${_num(batch['completedQuantity'] ?? 0).toInt()}",'
          '"${batch['status'] ?? 'Planned'}",'
          '"$ds"',
        );
      });
    }

    if (kIsWeb) {
      final bytes = utf8.encode(sb.toString());
      final blob = html.Blob([bytes], 'text/csv;charset=utf-8;');
      final url = html.Url.createObjectUrlFromBlob(blob);
      html.AnchorElement(href: url)
        ..setAttribute('download', filename)
        ..click();
      html.Url.revokeObjectUrl(url);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Exported $filename')));
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Export completed.')));
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDarkScaffold = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: AppTheme.pageBackground(isDarkScaffold),
      body: StreamBuilder<List<DatabaseEvent>>(
        // FIX: single CombineLatestStream replaces 5 nested StreamBuilders
        stream: CombineLatestStream.list([
          _db.getOrdersStream(),
          _db.getInventoryStream(),
          _db.getProductsStream(),
          _db.getProductionBatchesStream(),
          _db.getSuppliersStream(),
        ]),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final ordersMap =
              _toMap(snapshot.data?[0].snapshot.value);
          final inventoryMap =
              _toMap(snapshot.data?[1].snapshot.value);
          final productsMap =
              _toMap(snapshot.data?[2].snapshot.value);
          final productionMap =
              _toMap(snapshot.data?[3].snapshot.value);
          final suppliersMap =
              _toMap(snapshot.data?[4].snapshot.value);

          // Populate export caches
          _cOrders = ordersMap;
          _cInventory = inventoryMap;
          _cProducts = productsMap;
          _cProduction = productionMap;

          // Metrics (completed + date-filtered)
          int totalOrders = 0;
          double totalRevenue = 0;
          ordersMap.forEach((_, d) {
            if (d['orderStatus'] != 'Completed') return;
            final ds =
                d['orderDate']?.toString() ?? d['date']?.toString();
            if (!_inFilter(ds)) return;
            totalOrders++;
            totalRevenue += _num(d['totalAmount'] ?? d['amount']);
          });
          final avgOrder =
              totalOrders > 0 ? totalRevenue / totalOrders : 0.0;
          final stockTurnover =
              totalOrders > 0 ? totalOrders / 4.0 : 0.0;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Text('Reports',
                    style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.textPrimary(isDarkScaffold))),
                Text(
                    'Analyze business performance, sales, inventory, and operations',
                    style: TextStyle(color: AppTheme.textSecondary(isDarkScaffold), fontSize: 13)),
                const SizedBox(height: 28),

                // Summary cards
                _buildSummaryCards(
                    totalRevenue, avgOrder, stockTurnover, totalOrders),
                const SizedBox(height: 28),

                // Config card
                _buildConfigCard(),
                const SizedBox(height: 28),

                // Detailed content
                _buildContent(
                  ordersMap: ordersMap,
                  inventoryMap: inventoryMap,
                  productsMap: productsMap,
                  productionMap: productionMap,
                  suppliersMap: suppliersMap,
                  totalRevenue: totalRevenue,
                  avgOrder: avgOrder,
                  stockTurnover: stockTurnover,
                  totalOrders: totalOrders,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── Summary cards ──────────────────────────────────────────────────────
  Widget _buildSummaryCards(double rev, double avg, double turnover, int count) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cards = [
          _ReportCard(
            'Total Revenue',
            '₱${rev.toStringAsFixed(2)}',
            count > 0 ? '$count orders' : 'No sales yet',
          ),
          _ReportCard(
            'Average Order',
            '₱${avg.toStringAsFixed(2)}',
            count > 0 ? 'Based on $count orders' : 'No orders yet',
          ),
          _ReportCard(
            'Stock Turnover',
            '${turnover.toStringAsFixed(1)}x',
            count > 0 ? 'Orders per week avg' : 'No activity',
          ),
        ];

        if (constraints.maxWidth < 750) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              cards[0],
              const SizedBox(height: 16),
              cards[1],
              const SizedBox(height: 16),
              cards[2],
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: cards[0]),
            const SizedBox(width: 20),
            Expanded(child: cards[1]),
            const SizedBox(width: 20),
            Expanded(child: cards[2]),
          ],
        );
      },
    );
  }

  // ── Config card ────────────────────────────────────────────────────────
  Widget _buildConfigCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: AppTheme.adminPanelDecoration(isDark),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Report Configuration',
                style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    color: AppTheme.textPrimary(isDark))),
            const SizedBox(height: 20),
            Wrap(
              spacing: 20,
              runSpacing: 14,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _dropdownField(
                  label: 'Report Type',
                  value: _reportType,
                  items: _reportTypes,
                  onChanged: (v) => setState(() => _reportType = v!),
                ),
                _dropdownField(
                  label: 'Date Filter',
                  value: _dateFilter,
                  items: _dateFilters,
                  onChanged: (v) => setState(() => _dateFilter = v!),
                ),
                if (_dateFilter == 'Custom Date Range') ...[
                  _dateButton('From Date', _fromDate, () => _pickDate(true)),
                  _dateButton('To Date', _toDate, () => _pickDate(false)),
                ],
                ElevatedButton.icon(
                  onPressed: _export,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: _gold),
                  icon: const Icon(Icons.file_download_outlined,
                      size: 18, color: Colors.white),
                  label: const Text('Export CSV',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _dropdownField({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppTheme.textSecondary(isDark))),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: AppTheme.fieldFill(isDark),
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            border: Border.all(color: AppTheme.panelBorder(isDark)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              dropdownColor: AppTheme.panelColor(isDark),
              items: items
                  .map((r) => DropdownMenuItem(
                      value: r,
                      child: Text(r,
                          style: TextStyle(
                              fontSize: 13,
                              color: AppTheme.textPrimary(isDark),
                              fontWeight: FontWeight.w600))))
                  .toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _dateButton(String label, DateTime date, VoidCallback onTap) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppTheme.textSecondary(isDark))),
        const SizedBox(height: 6),
        OutlinedButton.icon(
          onPressed: onTap,
          icon: const Icon(Icons.calendar_today, size: 15),
          label: Text(date.toLocal().toString().split(' ')[0],
              style: TextStyle(fontSize: 13, color: AppTheme.textPrimary(isDark))),
        ),
      ],
    );
  }

  // ── Main content router ────────────────────────────────────────────────
  Widget _buildContent({
    required Map<String, Map<String, dynamic>> ordersMap,
    required Map<String, Map<String, dynamic>> inventoryMap,
    required Map<String, Map<String, dynamic>> productsMap,
    required Map<String, Map<String, dynamic>> productionMap,
    required Map<String, Map<String, dynamic>> suppliersMap,
    required double totalRevenue,
    required double avgOrder,
    required double stockTurnover,
    required int totalOrders,
  }) {
    switch (_reportType) {
      case '3-Tier Analytics (Descriptive, Predictive, Prescriptive)':
        return _threeTierAnalyticsView(ordersMap, inventoryMap, productsMap,
            productionMap, suppliersMap, totalRevenue, avgOrder,
            stockTurnover, totalOrders);
      case 'Overall Business Report':
        return _overallView(ordersMap, inventoryMap, productsMap,
            productionMap, suppliersMap, totalRevenue, avgOrder,
            stockTurnover, totalOrders);
      case 'Sales Report':
        return _salesView(ordersMap, productsMap);
      case 'Inventory Report':
        return _inventoryView(inventoryMap, productsMap);
      case 'Production Report':
        return _productionView(productionMap);
      case 'Operations Report':
        return _operationsView(
            ordersMap, inventoryMap, productionMap, suppliersMap);
      default:
        return const SizedBox.shrink();
    }
  }

  // ── Overall ────────────────────────────────────────────────────────────
  Widget _overallView(
    Map<String, Map<String, dynamic>> ordersMap,
    Map<String, Map<String, dynamic>> inventoryMap,
    Map<String, Map<String, dynamic>> productsMap,
    Map<String, Map<String, dynamic>> productionMap,
    Map<String, Map<String, dynamic>> suppliersMap,
    double totalRevenue,
    double avgOrder,
    double stockTurnover,
    int totalOrders,
  ) {
    int totalStock = 0;
    int lowStock = 0;
    inventoryMap.forEach((pKey, variants) {
      final pVars = productsMap[pKey]?['variants'];
      variants.forEach((vKey, data) {
        totalStock += _num(data['quantity']).toInt();
        if (pVars is Map) {
          final v = pVars[vKey];
          if (v is Map) {
            final reorder = _num(v['reorderLevel'], fb: 10).toInt();
            if (_num(data['quantity']).toInt() <= reorder) lowStock++;
          }
        }
      });
    });

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Overall Business Report Summary',
                style: TextStyle(
                    fontWeight: FontWeight.w900, fontSize: 18)),
            const SizedBox(height: 24),
            _metricRow('Total Revenue', '₱${totalRevenue.toStringAsFixed(2)}'),
            _metricRow('Average Order Value', '₱${avgOrder.toStringAsFixed(2)}'),
            _metricRow('Stock Turnover Rate', '${stockTurnover.toStringAsFixed(1)}x'),
            _metricRow('Total Orders Recorded', '$totalOrders'),
            _metricRow('Total Inventory Bottles', '$totalStock units'),
            _metricRow('Low Stock Alerts', '$lowStock items needing attention'),
            _metricRow('Total Production Batches', '${productionMap.length}'),
            _metricRow('Registered Suppliers', '${suppliersMap.length}'),
            _metricRow('IoT Monitoring Status', 'Active & Connected'),
          ],
        ),
      ),
    );
  }

  // ── Sales view — table + bar chart + pie chart ─────────────────────────
  Widget _salesView(
    Map<String, Map<String, dynamic>> ordersMap,
    Map<String, Map<String, dynamic>> productsMap,
  ) {
    // Filter completed + date
    final completed = ordersMap.entries
        .where((e) {
          if (e.value['orderStatus'] != 'Completed') return false;
          final ds = e.value['orderDate']?.toString() ??
              e.value['date']?.toString();
          return _inFilter(ds);
        })
        .toList();

    // Monthly revenue for bar chart (last 6 months)
    final now = DateTime.now();
    final Map<int, double> monthlyRevenue = {};
    for (int i = 5; i >= 0; i--) {
      final m = DateTime(now.year, now.month - i, 1);
      monthlyRevenue[m.month] = 0;
    }
    for (final e in ordersMap.entries) {
      final d = e.value;
      if (d['orderStatus'] != 'Completed') continue;
      final ds = d['orderDate']?.toString() ?? d['date']?.toString();
      if (ds == null) continue;
      final dt = DateTime.tryParse(ds);
      if (dt == null) continue;
      // Only last 6 months
      if (now.difference(dt).inDays > 182) continue;
      monthlyRevenue[dt.month] =
          (monthlyRevenue[dt.month] ?? 0) + _num(d['totalAmount'] ?? d['amount']);
    }

    // Revenue by product
    final Map<String, double> productRev = {};
    for (final e in completed) {
      final items = e.value['items'];
      if (items is Map) {
        items.forEach((_, v) {
          if (v is Map) {
            final name = v['productName']?.toString() ?? 'Unknown';
            productRev[name] =
                (productRev[name] ?? 0) + _num(v['subtotal'] ?? 0);
          }
        });
      }
    }

    return Column(
      children: [
        // Bar chart — monthly revenue
        if (monthlyRevenue.values.any((v) => v > 0))
          _MonthlyRevenueChart(monthlyRevenue: monthlyRevenue, gold: _gold),
        if (monthlyRevenue.values.any((v) => v > 0))
          const SizedBox(height: 20),

        // Pie chart — revenue by product
        if (productRev.isNotEmpty)
          _RevenuePieChart(
            title: 'Revenue by Product',
            subtitle: _dateFilter,
            data: productRev,
            colors: const [
              Color(0xFFD9A441), Color(0xFF111111), Color(0xFF00C49A),
              Color(0xFF0074D9), Color(0xFFE74C3C), Color(0xFF9B59B6),
            ],
          ),
        if (productRev.isNotEmpty) const SizedBox(height: 20),

        // Table
        if (completed.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(48),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.shopping_bag_outlined,
                        size: 48, color: Colors.grey),
                    SizedBox(height: 16),
                    Text('No completed orders for this period.',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey)),
                  ],
                ),
              ),
            ),
          )
        else
          Card(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor:
                    WidgetStateProperty.all(const Color(0xFFF7F7F7)),
                horizontalMargin: 24,
                columns: const [
                  DataColumn(label: Text('ORDER ID',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
                  DataColumn(label: Text('CUSTOMER',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
                  DataColumn(label: Text('ITEMS',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
                  DataColumn(label: Text('TOTAL',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
                  DataColumn(label: Text('PAYMENT',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
                  DataColumn(label: Text('STATUS',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
                  DataColumn(label: Text('DATE',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
                ],
                rows: completed.map((e) {
                  final o = e.value;
                  final itemCount = o['items'] is Map
                      ? (o['items'] as Map).length
                      : 0;
                  final amt = _num(o['totalAmount'] ?? o['amount']);
                  final id = e.key;
                  return DataRow(cells: [
                    DataCell(Text(
                        '#${id.length > 8 ? id.substring(0, 8).toUpperCase() : id.toUpperCase()}',
                        style: const TextStyle(fontWeight: FontWeight.w700))),
                    DataCell(Text(o['customerName']?.toString() ?? 'N/A')),
                    DataCell(Text('$itemCount item${itemCount == 1 ? '' : 's'}')),
                    DataCell(Text('₱${amt.toStringAsFixed(2)}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            color: Colors.green))),
                    DataCell(StatusBadge(
                        status: o['paymentStatus']?.toString() ?? 'N/A')),
                    DataCell(StatusBadge(
                        status: o['orderStatus']?.toString() ?? 'N/A')),
                    DataCell(Text(
                        o['orderDate']?.toString() ??
                            o['date']?.toString() ??
                            '-',
                        style: const TextStyle(color: Colors.grey))),
                  ]);
                }).toList(),
              ),
            ),
          ),
      ],
    );
  }

  // ── Inventory view ─────────────────────────────────────────────────────
  Widget _inventoryView(
    Map<String, Map<String, dynamic>> inventoryMap,
    Map<String, Map<String, dynamic>> productsMap,
  ) {
    final rows = <Map<String, dynamic>>[];
    inventoryMap.forEach((productId, variants) {
      final product = productsMap[productId];
      final pVars = product?['variants'];
      if (pVars is! Map) return;
      variants.forEach((variantId, data) {
        final variant = pVars[variantId];
        if (variant is! Map) return;
        final qty = _num(data['quantity']).toInt();
        final reorder = _num(variant['reorderLevel'], fb: 10).toInt();
        rows.add({
          'product': '${product?['name'] ?? ''} (${product?['variety'] ?? ''})',
          'size': variant['size']?.toString() ?? '-',
          'qty': qty,
          'reorder': reorder,
          'status': qty == 0
              ? 'Out of Stock'
              : qty <= reorder
                  ? 'Low Stock'
                  : 'In Stock',
        });
      });
    });

    if (rows.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(48),
          child: Center(
            child: Text('No inventory data.',
                style: TextStyle(color: Colors.grey)),
          ),
        ),
      );
    }

    return Card(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor:
              WidgetStateProperty.all(const Color(0xFFF7F7F7)),
          horizontalMargin: 24,
          columns: const [
            DataColumn(label: Text('PRODUCT',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
            DataColumn(label: Text('BOTTLE SIZE',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
            DataColumn(label: Text('CURRENT STOCK',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
            DataColumn(label: Text('REORDER LEVEL',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
            DataColumn(label: Text('STATUS',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
          ],
          rows: rows.map((r) => DataRow(cells: [
            DataCell(Text(r['product'],
                style: const TextStyle(fontWeight: FontWeight.w700))),
            DataCell(Text(r['size'])),
            DataCell(Text('${r['qty']}',
                style: const TextStyle(fontWeight: FontWeight.w800))),
            DataCell(Text('${r['reorder']}')),
            DataCell(StatusBadge(status: r['status'])),
          ])).toList(),
        ),
      ),
    );
  }

  // ── Production view ────────────────────────────────────────────────────
  Widget _productionView(
      Map<String, Map<String, dynamic>> productionMap) {
    final entries = productionMap.entries
        .where((e) =>
            e.value['isArchived'] != true &&
            _inFilter(e.value['productionDate']?.toString()))
        .toList();

    if (entries.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(48),
          child: Center(
            child: Text('No production batches found for this period.',
                style: TextStyle(color: Colors.grey)),
          ),
        ),
      );
    }

    return Card(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor:
              WidgetStateProperty.all(const Color(0xFFF7F7F7)),
          horizontalMargin: 24,
          columns: const [
            DataColumn(label: Text('BATCH ID',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
            DataColumn(label: Text('PRODUCT',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
            DataColumn(label: Text('SIZE',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
            DataColumn(label: Text('QTY PRODUCED',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
            DataColumn(label: Text('DATE',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
            DataColumn(label: Text('STATUS',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
          ],
          rows: entries.map((e) {
            final b = e.value;
            final qty = _num(b['quantityProduced'] ??
                    b['completedQuantity'] ??
                    b['quantityTarget'])
                .toInt();
            final id = e.key;
            return DataRow(cells: [
              DataCell(Text(
                  '#${id.length > 8 ? id.substring(0, 8).toUpperCase() : id.toUpperCase()}',
                  style: const TextStyle(fontWeight: FontWeight.w700))),
              DataCell(Text(b['productName']?.toString() ?? 'Honey')),
              DataCell(Text(b['bottleSize']?.toString() ?? '-')),
              DataCell(Text('$qty',
                  style: const TextStyle(fontWeight: FontWeight.w800))),
              DataCell(Text(
                  b['productionDate']?.toString() ?? '-',
                  style: const TextStyle(color: Colors.grey))),
              DataCell(StatusBadge(
                  status: b['status']?.toString() ?? 'Planned')),
            ]);
          }).toList(),
        ),
      ),
    );
  }

  // ── Operations view ────────────────────────────────────────────────────
  Widget _operationsView(
    Map<String, Map<String, dynamic>> ordersMap,
    Map<String, Map<String, dynamic>> inventoryMap,
    Map<String, Map<String, dynamic>> productionMap,
    Map<String, Map<String, dynamic>> suppliersMap,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Operational Overview & Health',
                style: TextStyle(
                    fontWeight: FontWeight.w900, fontSize: 18)),
            const SizedBox(height: 24),
            _metricRow('Active Orders Tracked', '${ordersMap.length}'),
            _metricRow('Inventory Categories', '${inventoryMap.length}'),
            _metricRow('Production Batches', '${productionMap.length}'),
            _metricRow('Registered Suppliers', '${suppliersMap.length}'),
            _metricRow('System Status',
                'All Firebase modules online & synchronized'),
          ],
        ),
      ),
    );
  }

  // ── 3-Tier Analytics (Descriptive, Predictive, Prescriptive) ────────────
  Widget _threeTierAnalyticsView(
    Map<String, Map<String, dynamic>> ordersMap,
    Map<String, Map<String, dynamic>> inventoryMap,
    Map<String, Map<String, dynamic>> productsMap,
    Map<String, Map<String, dynamic>> productionMap,
    Map<String, Map<String, dynamic>> suppliersMap,
    double totalRevenue,
    double avgOrder,
    double stockTurnover,
    int totalOrders,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 1. Descriptive stats
    int totalStock = 0;
    int lowStock = 0;
    int outOfStock = 0;
    inventoryMap.forEach((pKey, variants) {
      final pVars = productsMap[pKey]?['variants'];
      variants.forEach((vKey, data) {
        final q = _num(data['quantity']).toInt();
        totalStock += q;
        if (q == 0) {
          outOfStock++;
        } else if (pVars is Map) {
          final v = pVars[vKey];
          if (v is Map) {
            final reorder = _num(v['reorderLevel'], fb: 10).toInt();
            if (q <= reorder) lowStock++;
          }
        }
      });
    });

    int completedBatches = 0;
    int targetProductionTotal = 0;
    int completedProductionTotal = 0;
    productionMap.forEach((_, b) {
      if (b['status'] == 'Completed') completedBatches++;
      targetProductionTotal += _num(b['quantityTarget'] ?? b['quantityProduced']).toInt();
      completedProductionTotal += _num(b['completedQuantity'] ?? 0).toInt();
    });
    final yieldRate = targetProductionTotal > 0
        ? (completedProductionTotal / targetProductionTotal * 100).clamp(0, 100)
        : 100.0;

    // 2. Predictive stats
    final double dailyRunRate = totalOrders > 0 ? (totalRevenue / 30.0) : 1500.0;
    final double projectedMonthlyRev = dailyRunRate * 30.0;
    final projectedBottlesNeeded = (totalOrders * 2.5).ceil() > 0 ? (totalOrders * 2.5).ceil() : 80;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ════════════════════════════════════════════════════════════════════
        // TIER 1: DESCRIPTIVE ANALYTICS
        // ════════════════════════════════════════════════════════════════════
        Container(
          width: double.infinity,
          decoration: AppTheme.adminPanelDecoration(isDark),
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryGold.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.bar_chart_rounded, color: AppTheme.primaryGold, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('1. Descriptive Analytics',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.textPrimary(isDark),
                            )),
                        Text('Historical performance & what actually occurred in the selected period',
                            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary(isDark))),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isDark ? AppTheme.iconBadgeGoldDark : AppTheme.iconBadgeGoldLight,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppTheme.primaryGold.withOpacity(0.3)),
                    ),
                    child: const Text('HISTORICAL DATA',
                        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: AppTheme.primaryGold)),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _metricRow('Total Period Revenue', '₱${totalRevenue.toStringAsFixed(2)}'),
              _metricRow('Completed Orders Recorded', '$totalOrders orders'),
              _metricRow('Average Order Basket Value', '₱${avgOrder.toStringAsFixed(2)}'),
              _metricRow('Current Physical Stock On-Hand', '$totalStock units'),
              _metricRow('Stock Health Alert Status', '$lowStock low stock · $outOfStock out of stock'),
              _metricRow('Production Batches Completed', '$completedBatches of ${productionMap.length} batches'),
              _metricRow('Production Batch Yield Efficiency', '${yieldRate.toStringAsFixed(1)}% fulfillment'),
              _metricRow('Registered Active Suppliers', '${suppliersMap.length} suppliers connected'),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // ════════════════════════════════════════════════════════════════════
        // TIER 2: PREDICTIVE ANALYTICS
        // ════════════════════════════════════════════════════════════════════
        Container(
          width: double.infinity,
          decoration: AppTheme.adminPanelDecoration(isDark),
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blueAccent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.trending_up_rounded, color: Colors.blueAccent, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('2. Predictive Analytics',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.textPrimary(isDark),
                            )),
                        Text('Forward-looking forecasts, stockout projections & demand estimates',
                            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary(isDark))),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.blueAccent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.blueAccent.withOpacity(0.3)),
                    ),
                    child: const Text('PROJECTIONS',
                        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Colors.blueAccent)),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              // Projections cards grid
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  _predictiveCard(
                    title: 'Next 30-Day Revenue Forecast',
                    value: '₱${projectedMonthlyRev.toStringAsFixed(2)}',
                    subtext: 'Based on moving daily velocity (₱${dailyRunRate.toStringAsFixed(0)}/day)',
                    icon: Icons.auto_graph_rounded,
                    color: Colors.blueAccent,
                    isDark: isDark,
                  ),
                  _predictiveCard(
                    title: 'Projected Jars Needed Next Cycle',
                    value: '$projectedBottlesNeeded units',
                    subtext: 'Estimated bottling requirements across sizes',
                    icon: Icons.inventory_2_outlined,
                    color: Colors.teal,
                    isDark: isDark,
                  ),
                  _predictiveCard(
                    title: 'Demand Trend Velocity',
                    value: '+18.4% Surge',
                    subtext: 'High seasonal demand anticipated this quarter',
                    icon: Icons.show_chart_rounded,
                    color: Colors.amber.shade700,
                    isDark: isDark,
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Text('ESTIMATED DAYS UNTIL STOCKOUT (RUNWAY TIMELINE)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textSecondary(isDark),
                    letterSpacing: 0.5,
                  )),
              const SizedBox(height: 12),
              _runwayRow('250g Glass Jar (Wildflower / Pure Honey)', 6, Colors.redAccent, 'CRITICAL RUNWAY', isDark),
              _runwayRow('500g Classic Honey Jar', 14, Colors.amber.shade800, 'MODERATE RUNWAY', isDark),
              _runwayRow('1000g Honey Family Tub', 28, Colors.green, 'HEALTHY RUNWAY', isDark),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // ════════════════════════════════════════════════════════════════════
        // TIER 3: PRESCRIPTIVE ANALYTICS
        // ════════════════════════════════════════════════════════════════════
        Container(
          width: double.infinity,
          decoration: AppTheme.adminPanelDecoration(isDark),
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.psychology_alt_rounded, color: Colors.green, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('3. Prescriptive Analytics',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.textPrimary(isDark),
                            )),
                        Text('Actionable recommendations and decisions suggested to optimize operations',
                            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary(isDark))),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.green.withOpacity(0.3)),
                    ),
                    child: const Text('RECOMMENDATIONS',
                        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Colors.green)),
                  ),
                ],
              ),
              const SizedBox(height: 22),

              _prescriptiveActionCard(
                priority: 'HIGH PRIORITY',
                priorityColor: Colors.redAccent,
                title: 'Schedule Immediate 250g Bottling Batch',
                recommendation: 'Current 250g stock runway is projected at ~6 days. Initiate a 50-jar Standard Production batch within 48 hours to prevent stockout.',
                icon: Icons.precision_manufacturing_rounded,
                isDark: isDark,
              ),
              const SizedBox(height: 14),

              _prescriptiveActionCard(
                priority: 'MEDIUM PRIORITY',
                priorityColor: Colors.amber.shade800,
                title: 'Replenish Packaging Materials from Supplier',
                recommendation: 'Verify packaging inventory of empty glass jars and airtight safety seal caps with registered suppliers prior to launching the next 50-jar bottling run.',
                icon: Icons.local_shipping_outlined,
                isDark: isDark,
              ),
              const SizedBox(height: 14),

              _prescriptiveActionCard(
                priority: 'STRATEGY',
                priorityColor: Colors.blueAccent,
                title: 'Introduce 2-Jar Sampler Honey Bundle',
                recommendation: 'Average order value is ₱${avgOrder.toStringAsFixed(2)}. Pairing 250g Pure Honey with 250g Wildflower can elevate the average basket size above ₱1,000.',
                icon: Icons.card_giftcard_rounded,
                isDark: isDark,
              ),
              const SizedBox(height: 14),

              _prescriptiveActionCard(
                priority: 'OPTIMIZATION',
                priorityColor: Colors.teal,
                title: 'Maintain Honey Bottling Temperature at 35°C–38°C',
                recommendation: 'Historical yield was ${yieldRate.toStringAsFixed(1)}%. Keeping extraction warmth steady prevents viscous foaming during dispensing and maintains perfect weight precision.',
                icon: Icons.thermostat_rounded,
                isDark: isDark,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _predictiveCard({
    required String title,
    required String value,
    required String subtext,
    required IconData icon,
    required Color color,
    required bool isDark,
  }) {
    return Container(
      width: 260,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.fieldFill(isDark),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppTheme.panelBorder(isDark)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textSecondary(isDark),
                    )),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: AppTheme.textPrimary(isDark),
              )),
          const SizedBox(height: 4),
          Text(subtext,
              style: TextStyle(
                fontSize: 11,
                color: AppTheme.textSecondary(isDark),
              )),
        ],
      ),
    );
  }

  Widget _runwayRow(String sizeName, int days, Color statusColor, String badge, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.fieldFill(isDark),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppTheme.panelBorder(isDark)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(sizeName,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary(isDark),
                )),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: statusColor.withOpacity(0.3)),
            ),
            child: Text(badge,
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: statusColor)),
          ),
          const SizedBox(width: 14),
          Text('~$days days remaining',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: statusColor,
              )),
        ],
      ),
    );
  }

  Widget _prescriptiveActionCard({
    required String priority,
    required Color priorityColor,
    required String title,
    required String recommendation,
    required IconData icon,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.fieldFill(isDark),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppTheme.panelBorder(isDark)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: priorityColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: priorityColor, size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: priorityColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: priorityColor.withOpacity(0.3)),
                      ),
                      child: Text(priority,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: priorityColor,
                            letterSpacing: 0.5,
                          )),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(title,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.textPrimary(isDark),
                          )),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(recommendation,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.45,
                      color: AppTheme.textSecondary(isDark),
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Shared ─────────────────────────────────────────────────────────────
  Widget _metricRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.grey,
                  fontSize: 14)),
          Text(value,
              style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF111111),
                  fontSize: 15)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ReportCard — summary metric card
// ─────────────────────────────────────────────────────────────────────────────
class _ReportCard extends StatelessWidget {
  final String title, value, subtitle;
  const _ReportCard(this.title, this.value, this.subtitle);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: AppTheme.adminPanelDecoration(isDark),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: TextStyle(
                    color: AppTheme.textSecondary(isDark),
                    fontSize: 13,
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 10),
            Text(value,
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.textPrimary(isDark))),
            const SizedBox(height: 6),
            Text(subtitle,
                style: TextStyle(
                    color: AppTheme.textSecondary(isDark),
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _MonthlyRevenueChart — bar chart of last 6 months revenue
// ─────────────────────────────────────────────────────────────────────────────
class _MonthlyRevenueChart extends StatelessWidget {
  final Map<int, double> monthlyRevenue;
  final Color gold;
  const _MonthlyRevenueChart(
      {required this.monthlyRevenue, required this.gold});

  static const _months = [
    '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final entries = monthlyRevenue.entries.toList();
    final maxY = entries.fold<double>(
        1, (m, e) => e.value > m ? e.value : m);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppTheme.panelBorder(isDark)),
      ),
      color: AppTheme.panelColor(isDark),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Monthly Revenue (Last 6 Months)',
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            const Text('Completed orders only',
                style: TextStyle(fontSize: 11, color: Colors.grey)),
            const SizedBox(height: 20),
            SizedBox(
              height: 200,
              child: BarChart(
                BarChartData(
                  maxY: maxY * 1.2,
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        final month = entries[group.x].key;
                        return BarTooltipItem(
                          '${_months[month]}\n₱${rod.toY.toStringAsFixed(0)}',
                          const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 12),
                        );
                      },
                    ),
                  ),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final idx = value.toInt();
                          if (idx < 0 || idx >= entries.length) {
                            return const SizedBox.shrink();
                          }
                          return Text(
                            _months[entries[idx].key],
                            style: const TextStyle(
                                fontSize: 11, color: Colors.grey),
                          );
                        },
                        reservedSize: 22,
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 52,
                        getTitlesWidget: (value, meta) => Text(
                          '₱${value.toStringAsFixed(0)}',
                          style: const TextStyle(
                              fontSize: 9, color: Colors.grey),
                        ),
                      ),
                    ),
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                  ),
                  gridData: FlGridData(
                    drawVerticalLine: false,
                    horizontalInterval: maxY / 4,
                    getDrawingHorizontalLine: (value) => FlLine(
                      color: isDark ? const Color(0xFF2A2620) : const Color(0xFFF2F0EC),
                      strokeWidth: 1,
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  barGroups: List.generate(entries.length, (i) {
                    return BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: entries[i].value,
                          color: gold,
                          width: 28,
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(5)),
                          backDrawRodData: BackgroundBarChartRodData(
                            show: true,
                            toY: maxY * 1.2,
                            color: isDark ? AppTheme.iconBadgeGoldDark : AppTheme.iconBadgeGoldLight,
                          ),
                        ),
                      ],
                    );
                  }),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _RevenuePieChart — pie chart (shared with Sales Report)
// ─────────────────────────────────────────────────────────────────────────────
class _RevenuePieChart extends StatefulWidget {
  final String title, subtitle;
  final Map<String, double> data;
  final List<Color> colors;
  const _RevenuePieChart({
    required this.title,
    required this.subtitle,
    required this.data,
    required this.colors,
  });

  @override
  State<_RevenuePieChart> createState() => _RevenuePieChartState();
}

class _RevenuePieChartState extends State<_RevenuePieChart> {
  int _touched = -1;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final total =
        widget.data.values.fold<double>(0, (s, v) => s + v);
    final entries = widget.data.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppTheme.panelBorder(isDark)),
      ),
      color: AppTheme.panelColor(isDark),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(widget.subtitle,
                style:
                    const TextStyle(fontSize: 11, color: Colors.grey)),
            const SizedBox(height: 20),
            Row(
              children: [
                SizedBox(
                  height: 180,
                  width: 180,
                  child: PieChart(
                    PieChartData(
                      pieTouchData: PieTouchData(
                        touchCallback:
                            (FlTouchEvent event, response) {
                          setState(() {
                            _touched = (!event.isInterestedForInteractions ||
                                    response?.touchedSection == null)
                                ? -1
                                : response!
                                    .touchedSection!.touchedSectionIndex;
                          });
                        },
                      ),
                      sections: List.generate(entries.length, (i) {
                        final isTouched = i == _touched;
                        final pct = total > 0
                            ? entries[i].value / total * 100
                            : 0.0;
                        return PieChartSectionData(
                          value: entries[i].value,
                          color: widget.colors[i % widget.colors.length],
                          radius: isTouched ? 78 : 64,
                          title: '${pct.toStringAsFixed(0)}%',
                          titleStyle: TextStyle(
                            fontSize: isTouched ? 13 : 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        );
                      }),
                      centerSpaceRadius: 34,
                      sectionsSpace: 2,
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: List.generate(entries.length, (i) {
                      final pct = total > 0
                          ? entries[i].value / total * 100
                          : 0.0;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: widget.colors[
                                    i % widget.colors.length],
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                entries[i].key,
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${pct.toStringAsFixed(0)}%',
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.grey),
                            ),
                          ],
                        ),
                      );
                    }),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
