import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:rxdart/rxdart.dart';
import '../services/auth_service.dart';
import '../services/supabase_data_service.dart';
import '../widgets/status_badge.dart';
import '../core/theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SalesPage
//
// Data source : orders/ filtered to orderStatus == 'Completed'
//               inventory/ for stock totals
// All analytics computed client-side — zero new Firebase nodes.
//
// Sections (in order):
//   1. Period filter bar
//   2. Summary cards with trend vs previous period
//   3. Monthly Revenue bar chart (last 6 months)  |  Payment method pie
//   4. Sales Trend indicator + 3-month mini bars
//   5. Top Selling Products table
//   6. Demand Forecast (3-week moving average)
//   7. Sales History table
// ─────────────────────────────────────────────────────────────────────────────

class SalesPage extends StatefulWidget {
  final AuthSession session;
  const SalesPage({super.key, required this.session});

  @override
  State<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends State<SalesPage> {
  final _supabaseData = SupabaseDataService();

  // ── Constants ─────────────────────────────────────────────────────────
  static const _filters = ['Today', 'This Week', 'This Month', 'All'];

  String _filter = 'All';

  // ── Numeric helpers ───────────────────────────────────────────────────
  double _n(dynamic v) =>
      v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;
  int _i(dynamic v) =>
      v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? 0;

  // ── Date helpers ──────────────────────────────────────────────────────
  DateTime _weekStart(DateTime d) {
    final p = DateTime(d.year, d.month, d.day);
    return p.subtract(Duration(days: p.weekday - 1));
  }

  DateTime? _parseDate(Map<String, dynamic> o) {
    // Primary: orderDate field (string 'YYYY-MM-DD') — present in both Firebase and Supabase mapped orders
    final s = o['orderDate']?.toString() ?? o['date']?.toString() ?? o['createdAt']?.toString();
    if (s != null) {
      final dt = DateTime.tryParse(s);
      if (dt != null) return dt;
    }
    // Fallback: paymentVerifiedAt (int ms in Firebase legacy, ISO string in Supabase)
    final ts = o['paymentVerifiedAt'];
    if (ts is int) return DateTime.fromMillisecondsSinceEpoch(ts);
    if (ts is String) {
      final dt = DateTime.tryParse(ts);
      if (dt != null) return dt;
    }
    return null;
  }

  // ── Filter helper (applies the selected period to a list) ─────────────
  bool _inFilter(DateTime? dt, String filter) {
    if (dt == null) return filter == 'All';
    final now = DateTime.now();
    final d = DateTime(dt.year, dt.month, dt.day);
    final today = DateTime(now.year, now.month, now.day);
    switch (filter) {
      case 'Today':
        return d == today;
      case 'This Week':
        return !d.isBefore(_weekStart(now));
      case 'This Month':
        return d.year == now.year && d.month == now.month;
      default:
        return true;
    }
  }

  // ── Trend calculation ─────────────────────────────────────────────────
  /// Returns percentage change from [prev] to [curr].
  /// Returns null if comparison is not meaningful (prev == 0 and curr == 0).
  double? _pct(double curr, double prev) {
    if (prev == 0 && curr == 0) return null; // both zero → neutral
    if (prev == 0) return null; // new sales, can't compute %
    return (curr - prev) / prev * 100;
  }

  // ── Item extraction helper ────────────────────────────────────────────
  /// Safely iterates over order items regardless of whether stored as Map or List.
  void _eachItem(dynamic items, void Function(Map<String, dynamic>) fn) {
    if (items is Map) {
      items.forEach((_, v) {
        if (v is Map) fn(Map<String, dynamic>.from(v));
      });
    } else if (items is List) {
      for (final v in items) {
        if (v is Map) fn(Map<String, dynamic>.from(v));
      }
    }
  }

  // ── Forecast computation ──────────────────────────────────────────────
  _ForecastResult _forecast(List<Map<String, dynamic>> all) {
    final now = DateTime.now();
    final Map<DateTime, int> wb = {};
    for (final o in all) {
      final dt = _parseDate(o);
      if (dt == null) continue;
      final ws = _weekStart(dt);
      int bottles = 0;
      _eachItem(o['items'], (item) => bottles += _i(item['quantity']));
      wb[ws] = (wb[ws] ?? 0) + bottles;
    }
    final thisWS = _weekStart(now);
    final recent = List.generate(
        4, (i) => thisWS.subtract(Duration(days: (4 - i) * 7)));
    final counts = recent.map((w) => wb[w] ?? 0).toList();
    final thisCount = wb[thisWS] ?? 0;
    final last3 = counts.length >= 3 ? counts.sublist(counts.length - 3) : counts;
    final fc = last3.isEmpty
        ? 0
        : (last3.reduce((a, b) => a + b) / last3.length).round();
    return _ForecastResult(
      weekLabels: recent.map((w) => '${w.month}/${w.day}').toList(),
      weekCounts: counts,
      thisWeekCount: thisCount,
      nextWeekForecast: fc,
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDarkScaffold = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: AppTheme.pageBackground(isDarkScaffold),
      body: StreamBuilder<List<dynamic>>(
        stream: CombineLatestStream.list([
          _supabaseData.ordersStream,
          _supabaseData.inventoryStream,
        ]),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          // ── Parse orders (Supabase-mapped camelCase) ──────────────
          final ordersList = snap.data?.isNotEmpty == true && snap.data![0] is List
              ? (snap.data![0] as List).whereType<Map<String, dynamic>>().toList()
              : <Map<String, dynamic>>[];

          // Only completed orders count as sales
          final List<Map<String, dynamic>> allCompleted = ordersList
              .where((o) => o['orderStatus'] == 'Completed')
              .toList()
              ..sort((a, b) =>
                  (_parseDate(b) ?? DateTime(0))
                      .compareTo(_parseDate(a) ?? DateTime(0)));

          // ── Apply period filter ───────────────────────────────────
          final filtered = allCompleted
              .where((o) => _inFilter(_parseDate(o), _filter))
              .toList();

          // ── Inventory totals (Supabase nested map) ────────────────
          int totalStock = 0;
          final invMap = snap.data != null && snap.data!.length > 1
              ? (snap.data![1] is Map ? snap.data![1] as Map<String, dynamic> : _supabaseData.currentInventory)
              : _supabaseData.currentInventory;
          invMap.forEach((_, variants) {
            if (variants is Map) {
              variants.forEach((_, vd) {
                if (vd is Map) totalStock += _i(vd['quantity']);
              });
            }
          });

          // ── Revenue metrics ───────────────────────────────────────
          final now = DateTime.now();
          final todayD = DateTime(now.year, now.month, now.day);
          final yesterdayD = todayD.subtract(const Duration(days: 1));
          final thisMonday = _weekStart(now);
          final lastMonday = thisMonday.subtract(const Duration(days: 7));
          final lastMonthStart = DateTime(now.year, now.month - 1, 1);
          final lastMonthEnd = DateTime(now.year, now.month, 0); // last day of prev month
          final dayOfWeek = now.weekday; // 1=Mon..7=Sun
          final equivLastWeekEnd = lastMonday.add(Duration(days: dayOfWeek - 1));

          double todayRev = 0, yestRev = 0;
          double thisWeekRev = 0, lastWeekEquivRev = 0;
          double thisMonthRev = 0, lastMonthRev = 0;
          double totalRev = 0;

          for (final o in allCompleted) {
            final amt = _n(o['totalAmount'] ?? o['amount']);
            final dt = _parseDate(o);
            totalRev += amt;
            if (dt == null) continue;
            final d = DateTime(dt.year, dt.month, dt.day);

            // Today / yesterday
            if (d == todayD) todayRev += amt;
            if (d == yesterdayD) yestRev += amt;

            // This week / last week equivalent
            if (!d.isBefore(thisMonday)) thisWeekRev += amt;
            if (!d.isBefore(lastMonday) &&
                !d.isAfter(equivLastWeekEnd)) lastWeekEquivRev += amt;

            // This month / last month
            if (d.year == now.year && d.month == now.month) thisMonthRev += amt;
            if (!d.isBefore(lastMonthStart) && !d.isAfter(lastMonthEnd)) {
              lastMonthRev += amt;
            }
          }

          // ── Payment method breakdown ──────────────────────────────
          final Map<String, double> paymentRev = {};
          for (final o in filtered) {
            final method = (o['paymentMethod']?.toString() ?? 'Other').trim();
            paymentRev[method] = (paymentRev[method] ?? 0) +
                _n(o['totalAmount'] ?? o['amount']);
          }

          // ── Monthly revenue for bar chart (last 6 calendar months) ─
          final Map<String, double> monthlyRev = {};
          final monthKeys = <String>[];
          for (int i = 5; i >= 0; i--) {
            final m = DateTime(now.year, now.month - i, 1);
            final key = '${m.year}-${m.month.toString().padLeft(2, '0')}';
            monthKeys.add(key);
            monthlyRev[key] = 0;
          }
          for (final o in allCompleted) {
            final dt = _parseDate(o);
            if (dt == null) continue;
            final key = '${dt.year}-${dt.month.toString().padLeft(2, '0')}';
            if (monthlyRev.containsKey(key)) {
              monthlyRev[key] =
                  (monthlyRev[key] ?? 0) + _n(o['totalAmount'] ?? o['amount']);
            }
          }

          // ── 3-month mini trend (for trend card) ───────────────────
          final last3MonthKeys = monthKeys.length >= 3
              ? monthKeys.sublist(monthKeys.length - 3)
              : monthKeys;
          final last3Rev =
              last3MonthKeys.map((k) => monthlyRev[k] ?? 0.0).toList();

          // ── Top selling products (from filtered) ──────────────────
          final Map<String, _ProductStat> productStats = {};
          double filteredTotalRev = 0;
          for (final o in filtered) {
            filteredTotalRev += _n(o['totalAmount'] ?? o['amount']);
            _eachItem(o['items'], (item) {
              final name = item['productName']?.toString() ?? 'Unknown';
              final size = item['bottleSize']?.toString() ?? '';
              final label = size.isNotEmpty ? '$name ($size)' : name;
              final qty = _i(item['quantity']);
              final rev = _n(item['subtotal'] ??
                  (_n(item['unitPrice']) * qty));
              productStats[label] = _ProductStat(
                name: label,
                bottles: (productStats[label]?.bottles ?? 0) + qty,
                revenue: (productStats[label]?.revenue ?? 0) + rev,
              );
            });
          }
          final topProducts = productStats.values.toList()
            ..sort((a, b) => b.bottles.compareTo(a.bottles));

          // ── Forecast (always from all completed) ───────────────────
          final fc = _forecast(allCompleted);

          // ── Build UI ──────────────────────────────────────────────
          return SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header + filter ──────────────────────────────
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isNarrow = constraints.maxWidth < 650;
                    final title = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Sales',
                            style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                color: AppTheme.textPrimary(isDarkScaffold))),
                        Text(
                            'Completed transactions, revenue & forecasting',
                            style: TextStyle(
                                color: AppTheme.textSecondary(isDarkScaffold), fontSize: 13)),
                      ],
                    );
                    final filterBar = _FilterBar(
                      selected: _filter,
                      options: _filters,
                      onChanged: (v) => setState(() => _filter = v),
                    );

                    if (isNarrow) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          title,
                          const SizedBox(height: 14),
                          filterBar,
                        ],
                      );
                    }

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: title),
                        const SizedBox(width: 16),
                        filterBar,
                      ],
                    );
                  },
                ),
                const SizedBox(height: 24),

                // ── Summary cards ─────────────────────────────────
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    _SummaryCard(
                      label: "Today's Revenue",
                      value: todayRev,
                      sub: '${ _countWhere(allCompleted, (o) { final dt = _parseDate(o); return dt != null && DateTime(dt.year,dt.month,dt.day) == todayD; })} order${_countWhere(allCompleted, (o) { final dt = _parseDate(o); return dt != null && DateTime(dt.year,dt.month,dt.day) == todayD; }) == 1 ? '' : 's'} today',
                      pct: _pct(todayRev, yestRev),
                      prevLabel: 'vs yesterday',
                      prevIsZero: yestRev == 0 && todayRev > 0,
                      icon: Icons.today_outlined,
                    ),
                    _SummaryCard(
                      label: 'This Week',
                      value: thisWeekRev,
                      sub: 'Since Monday',
                      pct: _pct(thisWeekRev, lastWeekEquivRev),
                      prevLabel: 'vs same days last week',
                      prevIsZero: lastWeekEquivRev == 0 && thisWeekRev > 0,
                      icon: Icons.date_range_outlined,
                    ),
                    _SummaryCard(
                      label: 'This Month',
                      value: thisMonthRev,
                      sub: '${now.month == 1 ? 'Jan' : now.month == 2 ? 'Feb' : now.month == 3 ? 'Mar' : now.month == 4 ? 'Apr' : now.month == 5 ? 'May' : now.month == 6 ? 'Jun' : now.month == 7 ? 'Jul' : now.month == 8 ? 'Aug' : now.month == 9 ? 'Sep' : now.month == 10 ? 'Oct' : now.month == 11 ? 'Nov' : 'Dec'} ${now.year}',
                      pct: _pct(thisMonthRev, lastMonthRev),
                      prevLabel: 'vs last month',
                      prevIsZero: lastMonthRev == 0 && thisMonthRev > 0,
                      icon: Icons.calendar_month_outlined,
                    ),
                    _SummaryCard(
                      label: 'Total Revenue',
                      value: totalRev,
                      sub: '${allCompleted.length} completed order${allCompleted.length == 1 ? '' : 's'}',
                      pct: null,
                      prevLabel: 'All time',
                      prevIsZero: false,
                      icon: Icons.monetization_on_outlined,
                      isTotal: true,
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // ── Charts row ────────────────────────────────────
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isNarrow = constraints.maxWidth < 900;
                    final barChart = _MonthlyBarChart(
                      monthKeys: monthKeys,
                      monthlyRev: monthlyRev,
                      currentMonthKey: monthKeys.isNotEmpty
                          ? monthKeys.last
                          : '',
                    );
                    final pieChart = _PaymentPieCard(data: paymentRev);

                    if (isNarrow) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          barChart,
                          const SizedBox(height: 20),
                          pieChart,
                        ],
                      );
                    }

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 3, child: barChart),
                        const SizedBox(width: 16),
                        Expanded(flex: 2, child: pieChart),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 24),

                // ── Sales trend indicator ─────────────────────────
                _TrendCard(
                  thisMonthRev: thisMonthRev,
                  lastMonthRev: lastMonthRev,
                  last3MonthKeys: last3MonthKeys,
                  last3Rev: last3Rev,
                  now: now,
                ),
                const SizedBox(height: 24),

                // ── Top selling products ──────────────────────────
                _TopProductsTable(
                  products: topProducts,
                  totalRev: filteredTotalRev,
                  filter: _filter,
                ),
                const SizedBox(height: 24),

                // ── Demand forecast ───────────────────────────────
                _ForecastCard(
                  forecast: fc,
                  currentStock: totalStock,
                ),
                const SizedBox(height: 24),

                // ── Sales history ─────────────────────────────────
                _SalesHistoryTable(
                  orders: filtered,
                  filter: _filter,
                  numFn: _n,
                  intFn: _i,
                  eachItem: _eachItem,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  int _countWhere(List<Map<String, dynamic>> list,
      bool Function(Map<String, dynamic>) test) {
    return list.where(test).length;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Data models
// ─────────────────────────────────────────────────────────────────────────────
class _ForecastResult {
  final List<String> weekLabels;
  final List<int> weekCounts;
  final int thisWeekCount;
  final int nextWeekForecast;
  const _ForecastResult({
    required this.weekLabels,
    required this.weekCounts,
    required this.thisWeekCount,
    required this.nextWeekForecast,
  });
}

class _ProductStat {
  final String name;
  final int bottles;
  final double revenue;
  const _ProductStat(
      {required this.name, required this.bottles, required this.revenue});
}

// ─────────────────────────────────────────────────────────────────────────────
// 1. Period filter bar
// ─────────────────────────────────────────────────────────────────────────────
class _FilterBar extends StatelessWidget {
  final String selected;
  final List<String> options;
  final ValueChanged<String> onChanged;
  const _FilterBar(
      {required this.selected,
      required this.options,
      required this.onChanged});

  static const _gold = Color(0xFFD9A441);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTheme.mutedPanel(isDark),
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        border: Border.all(color: AppTheme.panelBorder(isDark)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: options.map((opt) {
          final active = opt == selected;
          return GestureDetector(
            onTap: () => onChanged(opt),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: active ? (isDark ? AppTheme.iconBadgeGoldDark : AppTheme.iconBadgeGoldLight) : Colors.transparent,
                borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                boxShadow: active
                    ? [
                        BoxShadow(
                            color: isDark ? const Color(0xFF0B0A08) : const Color(0xFFEFE6D2),
                            blurRadius: 4,
                            offset: const Offset(0, 1))
                      ]
                    : [],
              ),
              child: Text(
                opt,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: active ? _gold : AppTheme.textSecondary(isDark),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 2. Summary card with trend indicator
// ─────────────────────────────────────────────────────────────────────────────
class _SummaryCard extends StatelessWidget {
  final String label;
  final double value;
  final String sub;
  final double? pct;       // null = no comparison
  final String prevLabel;
  final bool prevIsZero;   // curr > 0 but prev == 0  → "New sales"
  final IconData icon;
  final bool isTotal;

  const _SummaryCard({
    required this.label,
    required this.value,
    required this.sub,
    required this.pct,
    required this.prevLabel,
    required this.prevIsZero,
    required this.icon,
    this.isTotal = false,
  });

  static const _gold = Color(0xFFD9A441);
  static const _green = Color(0xFF22C55E);
  static const _red = Color(0xFFEF4444);
  static const _grey = Color(0xFF94A3B8);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Determine trend display
    String trendLabel;
    Color trendColor;
    IconData trendIcon;

    if (isTotal) {
      trendLabel = 'All time';
      trendColor = _grey;
      trendIcon = Icons.remove_rounded;
    } else if (prevIsZero) {
      trendLabel = 'New sales';
      trendColor = _green;
      trendIcon = Icons.fiber_new_rounded;
    } else if (pct == null) {
      trendLabel = 'No prior data';
      trendColor = _grey;
      trendIcon = Icons.remove_rounded;
    } else if (pct! > 0) {
      trendLabel = '+${pct!.toStringAsFixed(1)}%';
      trendColor = _green;
      trendIcon = Icons.arrow_upward_rounded;
    } else if (pct! < 0) {
      trendLabel = '${pct!.toStringAsFixed(1)}%';
      trendColor = _red;
      trendIcon = Icons.arrow_downward_rounded;
    } else {
      trendLabel = '0%';
      trendColor = _grey;
      trendIcon = Icons.trending_flat_rounded;
    }

    return Container(
      width: 210,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.panelColor(isDark),
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: AppTheme.panelBorder(isDark)),
        boxShadow: AppTheme.softShadow(isDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.iconBadgeGoldDark : AppTheme.iconBadgeGoldLight,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: _gold, size: 16),
              ),
              const Spacer(),
              if (!isTotal)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: isDark
                        ? (trendColor == _green ? AppTheme.iconBadgeGreenDark
                            : trendColor == _red ? AppTheme.iconBadgeRoseDark
                            : const Color(0xFF2A2620))
                        : (trendColor == _green ? AppTheme.iconBadgeGreenLight
                            : trendColor == _red ? AppTheme.iconBadgeRoseLight
                            : const Color(0xFFF2F0EC)),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(trendIcon, size: 11, color: trendColor),
                      const SizedBox(width: 3),
                      Text(
                        trendLabel,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: trendColor,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(label,
              style: TextStyle(
                  color: AppTheme.textSecondary(isDark),
                  fontSize: 12,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Text(
            '₱${value.toStringAsFixed(2)}',
            style: const TextStyle(
                fontSize: 20, fontWeight: FontWeight.w900, color: _gold),
          ),
          const SizedBox(height: 4),
          Text(
            isTotal ? sub : '$sub · $prevLabel',
            style: TextStyle(fontSize: 10, color: AppTheme.textSecondary(isDark)),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 3a. Monthly Revenue Bar Chart (last 6 months)
// ─────────────────────────────────────────────────────────────────────────────
class _MonthlyBarChart extends StatefulWidget {
  final List<String> monthKeys;     // e.g. ['2026-04', '2026-05', ...]
  final Map<String, double> monthlyRev;
  final String currentMonthKey;

  const _MonthlyBarChart({
    required this.monthKeys,
    required this.monthlyRev,
    required this.currentMonthKey,
  });

  @override
  State<_MonthlyBarChart> createState() => _MonthlyBarChartState();
}

class _MonthlyBarChartState extends State<_MonthlyBarChart> {
  int _touched = -1;

  static const _gold = Color(0xFFD9A441);
  static const _monthAbbr = [
    '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _label(String key) {
    final parts = key.split('-');
    if (parts.length < 2) return key;
    final month = int.tryParse(parts[1]) ?? 0;
    return month > 0 && month <= 12 ? _monthAbbr[month] : key;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final entries = widget.monthKeys
        .map((k) => MapEntry(k, widget.monthlyRev[k] ?? 0.0))
        .toList();
    final maxY =
        entries.fold<double>(1, (m, e) => e.value > m ? e.value : m);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        side: BorderSide(color: AppTheme.panelBorder(isDark)),
      ),
      color: AppTheme.panelColor(isDark),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Monthly Revenue',
                style:
                    TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            const Text('Last 6 months · Completed orders only',
                style: TextStyle(fontSize: 11, color: Colors.grey)),
            const SizedBox(height: 20),
            SizedBox(
              height: 200,
              child: entries.every((e) => e.value == 0)
                  ? const Center(
                      child: Text('No revenue data yet.',
                          style: TextStyle(color: Colors.grey)))
                  : BarChart(
                      BarChartData(
                        maxY: maxY * 1.2,
                        barTouchData: BarTouchData(
                          touchCallback: (event, response) {
                            setState(() {
                              _touched = (!event.isInterestedForInteractions ||
                                      response?.spot == null)
                                  ? -1
                                  : response!.spot!.touchedBarGroupIndex;
                            });
                          },
                          touchTooltipData: BarTouchTooltipData(
                            getTooltipItem: (group, _, rod, __) =>
                                BarTooltipItem(
                              '${_label(entries[group.x].key)}\n₱${rod.toY.toStringAsFixed(0)}',
                              const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12),
                            ),
                          ),
                        ),
                        titlesData: FlTitlesData(
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 22,
                              getTitlesWidget: (v, _) {
                                final idx = v.toInt();
                                if (idx < 0 || idx >= entries.length) {
                                  return const SizedBox.shrink();
                                }
                                final isCurrentMonth =
                                    entries[idx].key ==
                                        widget.currentMonthKey;
                                return Text(
                                  _label(entries[idx].key),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isCurrentMonth
                                        ? _gold
                                        : Colors.grey,
                                    fontWeight: isCurrentMonth
                                        ? FontWeight.w700
                                        : FontWeight.w400,
                                  ),
                                );
                              },
                            ),
                          ),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 58,
                              getTitlesWidget: (v, _) => Text(
                                v >= 1000
                                    ? '₱${(v / 1000).toStringAsFixed(0)}k'
                                    : '₱${v.toStringAsFixed(0)}',
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
                          getDrawingHorizontalLine: (v) => FlLine(
                            color: isDark ? const Color(0xFF2A2620) : const Color(0xFFF2F0EC),
                            strokeWidth: 1,
                          ),
                        ),
                        borderData: FlBorderData(show: false),
                        barGroups: List.generate(entries.length, (i) {
                          final isCurrent =
                              entries[i].key == widget.currentMonthKey;
                          final isTouched = i == _touched;
                          return BarChartGroupData(
                            x: i,
                            barRods: [
                              BarChartRodData(
                                toY: entries[i].value,
                                color: (isTouched || isCurrent)
                                    ? _gold
                                    : (isDark ? const Color(0xFF6B5220) : const Color(0xFFE8D1A0)),
                                width: 28,
                                borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(5)),
                                backDrawRodData:
                                    BackgroundBarChartRodData(
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
// 3b. Payment method pie chart
// ─────────────────────────────────────────────────────────────────────────────
class _PaymentPieCard extends StatefulWidget {
  final Map<String, double> data;
  const _PaymentPieCard({required this.data});

  @override
  State<_PaymentPieCard> createState() => _PaymentPieCardState();
}

class _PaymentPieCardState extends State<_PaymentPieCard> {
  int _touched = -1;

  static const _colors = [
    Color(0xFF00C49A),
    Color(0xFF0074D9),
    Color(0xFFD9A441),
    Color(0xFF9B59B6),
    Color(0xFF94A3B8),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final entries = widget.data.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total =
        entries.fold<double>(0, (s, e) => s + e.value);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        side: BorderSide(color: AppTheme.panelBorder(isDark)),
      ),
      color: AppTheme.panelColor(isDark),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Revenue by Payment Method',
                style:
                    TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            const Text('Completed orders',
                style: TextStyle(fontSize: 11, color: Colors.grey)),
            const SizedBox(height: 20),
            if (total == 0)
              const SizedBox(
                height: 160,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.pie_chart_outline_rounded,
                          size: 36, color: Colors.grey),
                      SizedBox(height: 8),
                      Text('No payment data for this period.',
                          style: TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                ),
              )
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    height: 160,
                    width: 160,
                    child: PieChart(
                      PieChartData(
                        pieTouchData: PieTouchData(
                          touchCallback: (event, response) {
                            setState(() {
                              _touched =
                                  (!event.isInterestedForInteractions ||
                                          response?.touchedSection == null)
                                      ? -1
                                      : response!
                                          .touchedSection!
                                          .touchedSectionIndex;
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
                            color: _colors[i % _colors.length],
                            radius: isTouched ? 72 : 60,
                            title: '${pct.toStringAsFixed(0)}%',
                            titleStyle: TextStyle(
                              fontSize: isTouched ? 13 : 10,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          );
                        }),
                        centerSpaceRadius: 30,
                        sectionsSpace: 2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
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
                                  color: _colors[i % _colors.length],
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

// ─────────────────────────────────────────────────────────────────────────────
// 4. Sales Trend indicator + 3-month mini bars
// ─────────────────────────────────────────────────────────────────────────────
class _TrendCard extends StatelessWidget {
  final double thisMonthRev;
  final double lastMonthRev;
  final List<String> last3MonthKeys;
  final List<double> last3Rev;
  final DateTime now;

  const _TrendCard({
    required this.thisMonthRev,
    required this.lastMonthRev,
    required this.last3MonthKeys,
    required this.last3Rev,
    required this.now,
  });

  static const _green = Color(0xFF22C55E);
  static const _red = Color(0xFFEF4444);
  static const _grey = Color(0xFF94A3B8);
  static const _gold = Color(0xFFD9A441);
  static const _monthAbbr = [
    '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _label(String key) {
    final parts = key.split('-');
    if (parts.length < 2) return key;
    final m = int.tryParse(parts[1]) ?? 0;
    return m > 0 && m <= 12 ? _monthAbbr[m] : key;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Determine trend direction
    final bool isUp = thisMonthRev > lastMonthRev;
    final bool isDown = thisMonthRev < lastMonthRev;
    final bool isNew = lastMonthRev == 0 && thisMonthRev > 0;
    final bool noData = thisMonthRev == 0 && lastMonthRev == 0;

    Color trendColor;
    IconData trendIcon;
    String trendHeading;
    String trendDesc;
    String pctStr;

    if (noData) {
      trendColor = _grey;
      trendIcon = Icons.show_chart_rounded;
      trendHeading = 'NO SALES DATA YET';
      trendDesc = 'Complete orders will appear here once revenue is recorded.';
      pctStr = '—';
    } else if (isNew) {
      trendColor = _green;
      trendIcon = Icons.trending_up_rounded;
      trendHeading = 'NEW SALES THIS MONTH';
      trendDesc = 'First recorded revenue this month.';
      pctStr = 'New';
    } else if (isUp) {
      final pct = lastMonthRev > 0
          ? ((thisMonthRev - lastMonthRev) / lastMonthRev * 100)
          : 0.0;
      trendColor = _green;
      trendIcon = Icons.trending_up_rounded;
      trendHeading = 'SALES ARE TRENDING UP';
      trendDesc = 'Higher revenue than last month.';
      pctStr = '+${pct.toStringAsFixed(1)}%';
    } else if (isDown) {
      final pct = lastMonthRev > 0
          ? ((thisMonthRev - lastMonthRev) / lastMonthRev * 100)
          : 0.0;
      trendColor = _red;
      trendIcon = Icons.trending_down_rounded;
      trendHeading = 'SALES ARE TRENDING DOWN';
      trendDesc = 'Lower revenue than last month.';
      pctStr = '${pct.toStringAsFixed(1)}%';
    } else {
      trendColor = _grey;
      trendIcon = Icons.trending_flat_rounded;
      trendHeading = 'SALES ARE STABLE';
      trendDesc = 'Revenue is unchanged from last month.';
      pctStr = '0%';
    }

    final maxRev = last3Rev.fold<double>(1, (m, v) => v > m ? v : m);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: isDark
            ? (trendColor == _gold ? AppTheme.badgeGoldBorderDark
                : trendColor == _green ? AppTheme.badgeGreenBorderDark
                : trendColor == _red ? AppTheme.badgeRedBorderDark
                : const Color(0xFF5C5448))
            : (trendColor == _gold ? AppTheme.badgeGoldBorderLight
                : trendColor == _green ? AppTheme.badgeGreenBorderLight
                : trendColor == _red ? AppTheme.badgeRedBorderLight
                : const Color(0xFFD1CDBF))),
      ),
      color: AppTheme.panelColor(isDark),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Heading
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: isDark
                        ? (trendColor == _gold ? AppTheme.iconBadgeGoldDark
                            : trendColor == _green ? AppTheme.iconBadgeGreenDark
                            : trendColor == _red ? AppTheme.iconBadgeRoseDark
                            : const Color(0xFF2A2620))
                        : (trendColor == _gold ? AppTheme.iconBadgeGoldLight
                            : trendColor == _green ? AppTheme.iconBadgeGreenLight
                            : trendColor == _red ? AppTheme.iconBadgeRoseLight
                            : const Color(0xFFF2F0EC)),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(trendIcon, color: trendColor, size: 20),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      trendHeading,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: trendColor,
                        letterSpacing: 0.4,
                      ),
                    ),
                    Text(trendDesc,
                        style: const TextStyle(
                            fontSize: 12, color: Colors.grey)),
                  ],
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isDark
                        ? (trendColor == _gold ? AppTheme.iconBadgeGoldDark
                            : trendColor == _green ? AppTheme.iconBadgeGreenDark
                            : trendColor == _red ? AppTheme.iconBadgeRoseDark
                            : const Color(0xFF2A2620))
                        : (trendColor == _gold ? AppTheme.iconBadgeGoldLight
                            : trendColor == _green ? AppTheme.iconBadgeGreenLight
                            : trendColor == _red ? AppTheme.iconBadgeRoseLight
                            : const Color(0xFFF2F0EC)),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: isDark
                            ? (trendColor == _gold ? AppTheme.badgeGoldBorderDark
                                : trendColor == _green ? AppTheme.badgeGreenBorderDark
                                : trendColor == _red ? AppTheme.badgeRedBorderDark
                                : const Color(0xFF5C5448))
                            : (trendColor == _gold ? AppTheme.badgeGoldBorderLight
                                : trendColor == _green ? AppTheme.badgeGreenBorderLight
                                : trendColor == _red ? AppTheme.badgeRedBorderLight
                                : const Color(0xFFD1CDBF))),
                  ),
                  child: Text(
                    pctStr,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: trendColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Revenue comparison
            if (!noData)
              Row(
                children: [
                  Expanded(
                    child: _TrendRevBox(
                      label: 'This Month',
                      value: thisMonthRev,
                      color: trendColor,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _TrendRevBox(
                      label: 'Last Month',
                      value: lastMonthRev,
                      color: _grey,
                    ),
                  ),
                ],
              ),

            if (!noData && last3Rev.isNotEmpty) ...[
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 14),
              const Text('3-Month Revenue Trend',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey)),
              const SizedBox(height: 12),
              // Mini bar visualization using plain Containers
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(last3Rev.length, (i) {
                  final pct = maxRev > 0 ? last3Rev[i] / maxRev : 0.0;
                  final isLast = i == last3Rev.length - 1;
                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                          right: i < last3Rev.length - 1 ? 8 : 0),
                      child: Column(
                        children: [
                          Text(
                            last3Rev[i] >= 1000
                                ? '₱${(last3Rev[i] / 1000).toStringAsFixed(1)}k'
                                : '₱${last3Rev[i].toStringAsFixed(0)}',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: isLast ? trendColor : Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            height: 48 * (pct.clamp(0.05, 1.0)),
                            decoration: BoxDecoration(
                              color: isLast
                                  ? trendColor
                                  : (isDark ? const Color(0xFF6B5220) : const Color(0xFFE8D1A0)),
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(4)),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            i < last3MonthKeys.length
                                ? _label(last3MonthKeys[i])
                                : '',
                            style: TextStyle(
                              fontSize: 11,
                              color: isLast ? trendColor : Colors.grey,
                              fontWeight: isLast
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TrendRevBox extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  const _TrendRevBox(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const _goldVal = Color(0xFFD9A441);
    const _greenVal = Color(0xFF22C55E);
    const _redVal = Color(0xFFEF4444);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark
            ? (color == _goldVal ? AppTheme.iconBadgeGoldDark
                : color == _greenVal ? AppTheme.iconBadgeGreenDark
                : color == _redVal ? AppTheme.iconBadgeRoseDark
                : const Color(0xFF2A2620))
            : (color == _goldVal ? AppTheme.iconBadgeGoldLight
                : color == _greenVal ? AppTheme.iconBadgeGreenLight
                : color == _redVal ? AppTheme.iconBadgeRoseLight
                : const Color(0xFFF2F0EC)),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isDark
            ? (color == _goldVal ? AppTheme.badgeGoldBorderDark
                : color == _greenVal ? AppTheme.badgeGreenBorderDark
                : color == _redVal ? AppTheme.badgeRedBorderDark
                : const Color(0xFF5C5448))
            : (color == _goldVal ? AppTheme.badgeGoldBorderLight
                : color == _greenVal ? AppTheme.badgeGreenBorderLight
                : color == _redVal ? AppTheme.badgeRedBorderLight
                : const Color(0xFFD1CDBF))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: color)),
          const SizedBox(height: 4),
          Text(
            '₱${value.toStringAsFixed(2)}',
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w900, color: color),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 5. Top Selling Products table
// ─────────────────────────────────────────────────────────────────────────────
class _TopProductsTable extends StatelessWidget {
  final List<_ProductStat> products;
  final double totalRev;
  final String filter;
  const _TopProductsTable(
      {required this.products,
      required this.totalRev,
      required this.filter});

  static const _gold = Color(0xFFD9A441);
  static const _medals = ['🥇', '🥈', '🥉'];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final top = products.take(10).toList();

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
            Row(
              children: [
                const Text('🏆  Top Selling Products',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w800)),
                const Spacer(),
                Text('$filter · by bottles sold',
                    style: const TextStyle(
                        fontSize: 11, color: Colors.grey)),
              ],
            ),
            const SizedBox(height: 16),
            if (top.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.hive_outlined,
                          size: 40, color: Colors.grey),
                      SizedBox(height: 10),
                      Text('No product sales for this period.',
                          style: TextStyle(
                              color: Colors.grey,
                              fontSize: 14,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowColor:
                      WidgetStateProperty.all(const Color(0xFFF7F7F7)),
                  horizontalMargin: 12,
                  columnSpacing: 24,
                  columns: const [
                    DataColumn(
                        label: Text('RANK',
                            style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 11))),
                    DataColumn(
                        label: Text('PRODUCT',
                            style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 11))),
                    DataColumn(
                        label: Text('BOTTLES SOLD',
                            style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 11))),
                    DataColumn(
                        label: Text('REVENUE',
                            style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 11))),
                    DataColumn(
                        label: Text('% OF TOTAL',
                            style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 11))),
                  ],
                  rows: List.generate(top.length, (i) {
                    final p = top[i];
                    final sharePct = totalRev > 0
                        ? p.revenue / totalRev * 100
                        : 0.0;
                    final rankStr =
                        i < _medals.length ? _medals[i] : '${i + 1}';
                    return DataRow(cells: [
                      DataCell(Text(rankStr,
                          style: const TextStyle(fontSize: 14))),
                      DataCell(Text(p.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13))),
                      DataCell(Text(
                        '${p.bottles} bottle${p.bottles == 1 ? '' : 's'}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            color: _gold),
                      )),
                      DataCell(Text(
                        '₱${p.revenue.toStringAsFixed(2)}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                            color: Color(0xFF22C55E)),
                      )),
                      DataCell(_ShareBar(
                          pct: sharePct / 100, label: '${sharePct.toStringAsFixed(0)}%')),
                    ]);
                  }),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ShareBar extends StatelessWidget {
  final double pct;
  final String label;
  const _ShareBar({required this.pct, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 70,
          height: 8,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct.clamp(0.0, 1.0),
              backgroundColor: const Color(0xFFEEEEEE),
              valueColor: const AlwaysStoppedAnimation<Color>(
                  Color(0xFFD9A441)),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(label,
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 6. Demand Forecast card
// ─────────────────────────────────────────────────────────────────────────────
class _ForecastCard extends StatelessWidget {
  final _ForecastResult forecast;
  final int currentStock;
  const _ForecastCard(
      {required this.forecast, required this.currentStock});

  static const _gold = Color(0xFFD9A441);
  static const _green = Color(0xFF22C55E);
  static const _red = Color(0xFFEF4444);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fc = forecast.nextWeekForecast;
    final remaining = currentStock - fc;
    final sufficient = remaining >= 0;
    final maxCount = [
      ...forecast.weekCounts,
      forecast.thisWeekCount,
      if (fc > 0) fc,
    ].fold<int>(1, (m, v) => v > m ? v : m);

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
            Row(children: [
              Icon(Icons.auto_graph_rounded, color: _gold, size: 20),
              const SizedBox(width: 8),
              const Text('Demand Forecast',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w900)),
            ]),
            const SizedBox(height: 2),
            const Text(
                '3-week moving average · Does not modify inventory or orders.',
                style: TextStyle(fontSize: 11, color: Colors.grey)),
            const SizedBox(height: 18),

            // Weekly demand bars
            const Text('Weekly Demand',
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            if (forecast.weekCounts.every((c) => c == 0))
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Not enough historical data yet. '
                  'Forecasting becomes available after orders are completed.',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              )
            else ...[
              ...List.generate(forecast.weekCounts.length, (i) {
                final pct = maxCount > 0
                    ? forecast.weekCounts[i] / maxCount
                    : 0.0;
                return _FcBar(
                    label: 'Week ${i + 1}  (${forecast.weekLabels[i]})',
                    count: forecast.weekCounts[i],
                    pct: pct,
                    color: Colors.blue.shade300);
              }),
              _FcBar(
                label: 'This week (so far)',
                count: forecast.thisWeekCount,
                pct: maxCount > 0 ? forecast.thisWeekCount / maxCount : 0,
                color: _gold,
              ),
            ],

            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 14),

            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Forecast box
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark ? AppTheme.iconBadgeGoldDark : AppTheme.iconBadgeGoldLight,
                      borderRadius: BorderRadius.circular(10),
                      border:
                          Border.all(color: isDark ? AppTheme.badgeGoldBorderDark : AppTheme.badgeGoldBorderLight),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Next Week Forecast',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: _gold)),
                        const SizedBox(height: 6),
                        Text('≈ $fc bottle${fc == 1 ? '' : 's'}',
                            style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                color: _gold)),
                        const SizedBox(height: 4),
                        Text(
                            fc == 0
                                ? 'Need more data'
                                : 'Estimated demand next week',
                            style: const TextStyle(
                                fontSize: 10, color: Colors.grey)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Stock comparison box
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark
                          ? (sufficient ? AppTheme.iconBadgeGreenDark : AppTheme.iconBadgeRoseDark)
                          : (sufficient ? AppTheme.iconBadgeGreenLight : AppTheme.iconBadgeRoseLight),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isDark
                            ? (sufficient ? AppTheme.badgeGreenBorderDark : AppTheme.badgeRedBorderDark)
                            : (sufficient ? AppTheme.badgeGreenBorderLight : AppTheme.badgeRedBorderLight),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(
                            sufficient
                                ? Icons.check_circle_outline
                                : Icons.warning_amber_rounded,
                            size: 14,
                            color: sufficient ? _green : _red,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            sufficient
                                ? 'Stock Sufficient'
                                : 'Restock Needed',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: sufficient ? _green : _red),
                          ),
                        ]),
                        const SizedBox(height: 8),
                        _FcMetric('Current Stock',
                            '$currentStock bottles'),
                        _FcMetric(
                            'Predicted Demand', '≈ $fc bottles'),
                        const Divider(height: 12),
                        _FcMetric(
                          'Expected Remaining',
                          '${remaining.abs()} bottles '
                              '${remaining < 0 ? 'short' : 'left'}',
                          bold: true,
                          color: sufficient ? _green : _red,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            if (fc > 0) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF0F172A)
                      : const Color(0xFFF9F9F9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(children: [
                  const Icon(Icons.info_outline_rounded,
                      size: 14, color: Colors.grey),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Forecast: Approximately $fc bottle${fc == 1 ? '' : 's'} may be needed '
                      'next week. Expected remaining stock: ${remaining.abs()} bottle${remaining.abs() == 1 ? '' : 's'} '
                      '${remaining < 0 ? 'below requirement.' : 'after fulfilling demand.'}',
                      style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                          height: 1.4),
                    ),
                  ),
                ]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FcBar extends StatelessWidget {
  final String label;
  final int count;
  final double pct;
  final Color color;
  const _FcBar(
      {required this.label,
      required this.count,
      required this.pct,
      required this.color});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const _goldVal = Color(0xFFD9A441);
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        children: [
          SizedBox(
            width: 150,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 11, color: Colors.grey)),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: pct.clamp(0.0, 1.0),
                minHeight: 14,
                backgroundColor: isDark
                    ? (color == _goldVal ? AppTheme.iconBadgeGoldDark : AppTheme.iconBadgeBlueDark)
                    : (color == _goldVal ? AppTheme.iconBadgeGoldLight : AppTheme.iconBadgeBlueLight),
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 64,
            child: Text(
              '$count bottle${count == 1 ? '' : 's'}',
              style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _FcMetric extends StatelessWidget {
  final String label, value;
  final bool bold;
  final Color? color;
  const _FcMetric(this.label, this.value,
      {this.bold = false, this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style:
                  const TextStyle(fontSize: 11, color: Colors.grey)),
          Text(value,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight:
                      bold ? FontWeight.w800 : FontWeight.w600,
                  color: color)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 7. Sales History table
// ─────────────────────────────────────────────────────────────────────────────
class _SalesHistoryTable extends StatelessWidget {
  final List<Map<String, dynamic>> orders;
  final String filter;
  final double Function(dynamic) numFn;
  final int Function(dynamic) intFn;
  final void Function(dynamic, void Function(Map<String, dynamic>))
      eachItem;

  const _SalesHistoryTable({
    required this.orders,
    required this.filter,
    required this.numFn,
    required this.intFn,
    required this.eachItem,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
            Row(
              children: [
                const Text('Sales History',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w800)),
                const Spacer(),
                Text(
                    '${orders.length} transaction${orders.length == 1 ? '' : 's'} · $filter',
                    style: const TextStyle(
                        fontSize: 11, color: Colors.grey)),
              ],
            ),
            const SizedBox(height: 16),
            if (orders.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 36),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.receipt_long_outlined,
                          size: 40, color: Colors.grey),
                      SizedBox(height: 10),
                      Text('No completed sales for this period.',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey)),
                    ],
                  ),
                ),
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowColor:
                      WidgetStateProperty.all(const Color(0xFFF7F7F7)),
                  horizontalMargin: 12,
                  columnSpacing: 20,
                  columns: const [
                    DataColumn(
                        label: Text('ORDER ID',
                            style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 11))),
                    DataColumn(
                        label: Text('CUSTOMER',
                            style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 11))),
                    DataColumn(
                        label: Text('BOTTLES',
                            style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 11))),
                    DataColumn(
                        label: Text('TOTAL',
                            style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 11))),
                    DataColumn(
                        label: Text('PAYMENT',
                            style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 11))),
                    DataColumn(
                        label: Text('STATUS',
                            style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 11))),
                    DataColumn(
                        label: Text('DATE',
                            style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 11))),
                  ],
                  rows: orders.map((o) {
                    int bottles = 0;
                    eachItem(o['items'],
                        (item) => bottles += intFn(item['quantity']));
                    final id = o['_id']?.toString() ?? '';
                    final shortId = id.length >= 8
                        ? id.substring(0, 8).toUpperCase()
                        : id.toUpperCase();
                    return DataRow(cells: [
                      DataCell(Text('#$shortId',
                          style: const TextStyle(
                              fontWeight: FontWeight.w700))),
                      DataCell(Text(
                          o['customerName']?.toString() ?? 'N/A')),
                      DataCell(Text(
                          '$bottles bottle${bottles == 1 ? '' : 's'}')),
                      DataCell(Text(
                        '₱${numFn(o['totalAmount'] ?? o['amount']).toStringAsFixed(2)}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF22C55E)),
                      )),
                      DataCell(Text(
                          o['paymentMethod']?.toString() ?? 'N/A')),
                      DataCell(StatusBadge(
                          status: o['paymentStatus']?.toString() ??
                              'Paid')),
                      DataCell(Text(
                        o['orderDate']?.toString() ??
                            o['date']?.toString() ??
                            '-',
                        style:
                            const TextStyle(color: Colors.grey),
                      )),
                    ]);
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
