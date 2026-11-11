import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:rxdart/rxdart.dart';
import 'package:honeybee_center/services/auth_service.dart';
import 'package:honeybee_center/services/database_service.dart';
import 'package:honeybee_center/services/supabase_data_service.dart';
import 'package:honeybee_center/widgets/status_badge.dart';
import 'package:honeybee_center/widgets/camera_mjpeg_preview.dart';
import 'package:honeybee_center/core/theme/app_theme.dart';
import 'package:honeybee_center/core/permissions/admin_capabilities.dart';

class InventoryPage extends StatefulWidget {
  final AuthSession session;
  const InventoryPage({super.key, required this.session});

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  final _db = DatabaseService();
  final _supabaseData = SupabaseDataService();
  int _tab = 0;
  String _search = '';
  String _stockFilter = 'All';
  int _verifyView = 0; // 0=Pending, 1=History, 2=Size Thresholds
  bool _verifyInfoExpanded = false;
  // IoT scan & camera state
  late Stream<DatabaseEvent> _scanCommandsStream;
  late Stream<DatabaseEvent> _scanResultsStream;
  late Stream<DatabaseEvent> _iotStatusStream;
  String? _activeScanCommandId; // non-null while a scan is pending
  bool _cameraPreviewExpanded = true;
  String _esp32CameraIp = '192.168.1.100';
  CameraStreamStatus _cameraStatus = CameraStreamStatus.connecting;
  int _cameraRetryKey = 0;

  @override
  void initState() {
    super.initState();
    _replaceScannerStreams();
    _supabaseData.refreshAll().catchError((e) {
      debugPrint('[InventoryPage] Error fetching Supabase inventory: $e');
    });
  }

  void _replaceScannerStreams() {
    _scanCommandsStream = _db.getScanCommandsStream();
    _scanResultsStream = _db.getScanResultsStream();
    _iotStatusStream = _db.getIotStatusStream();
  }

  void _retryScannerConnection() {
    setState(_replaceScannerStreams);
  }

  void _selectTab(int index) {
    setState(() {
      _tab = index;
      if (index == 1) _cameraStatus = CameraStreamStatus.connecting;
    });
  }

  void _selectVerificationView(int index) {
    setState(() {
      _verifyView = index;
      if (index == 0) _cameraStatus = CameraStreamStatus.connecting;
    });
  }

  String? get _cameraStreamUrl {
    return cameraMjpegStreamUrl(_esp32CameraIp);
  }

  void _updateCameraStatus(CameraStreamStatus status) {
    if (!mounted || _cameraStatus == status) return;
    setState(() => _cameraStatus = status);
  }

  void _retryCameraStream() {
    setState(() {
      _cameraRetryKey++;
      _cameraStatus = CameraStreamStatus.connecting;
    });
  }

  static const _gold = AppTheme.primaryGold;
  static const _tabs = [
    'Overview',
    'Verification',
    'Stock Corrections',
    'Bottle Sizes',
  ];

  String _timeAgo(dynamic ts) {
    if (ts == null || ts == 0) return 'Never';
    final dt = DateTime.fromMillisecondsSinceEpoch(
      ts is int ? ts : int.tryParse(ts.toString()) ?? 0,
    );
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return dt.toLocal().toString().split(' ')[0];
  }

  String _movementLabel(String type) {
    switch (type) {
      case 'production':
        return 'Production Completed';
      case 'production_adjustment':
        return 'Production Edit';
      case 'sale':
        return 'Order Completed';
      case 'reconciliation_adjustment':
        return 'IoT Reconciliation';
      case 'manual_adjustment':
        return 'Manual Adjustment';
      default:
        return type;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark
          ? AppTheme.backgroundDark
          : AppTheme.backgroundLight,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildKpiHeader(),
          _buildTabBar(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildKpiHeader() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: CombineLatestStream.list([
        _supabaseData.productsStream,
        _supabaseData.inventoryStream,
      ]),
      builder: (context, snap) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final textColor = isDark ? AppTheme.textDark : AppTheme.textLight;
        final subColor = isDark
            ? AppTheme.subtitleDark(isDark)
            : AppTheme.subtitleLight(isDark);
        int totalStock = 0, lowStock = 0, outOfStock = 0, activeVariants = 0;
        final pRaw = snap.data != null && snap.data!.isNotEmpty
            ? snap.data![0]
            : _supabaseData.currentProducts;
        final iRaw = snap.data != null && snap.data!.length > 1
            ? snap.data![1]
            : _supabaseData.currentInventory;
        if (pRaw.isNotEmpty) {
          pRaw.forEach((pId, pVal) {
            if (pVal is! Map) return;
            (pVal['variants'] as Map? ?? {}).forEach((vId, vVal) {
              if (vVal is! Map || vVal['isActive'] == false) return;
              activeVariants++;
              final invV = (iRaw[pId] as Map? ?? {})[vId];
              final qty = invV is Map ? (invV['quantity'] ?? 0) as int : 0;
              final reorder = (vVal['reorderLevel'] ?? 10) as int;
              totalStock += qty;
              if (qty == 0) {
                outOfStock++;
              } else if (qty <= reorder) {
                lowStock++;
              }
            });
          });
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            AppTheme.adminPagePaddingCompact,
            16,
            AppTheme.adminPagePaddingCompact,
            0,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Inventory Hub',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: textColor,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Bottle stock management, IoT verification, and adjustments',
                          style: TextStyle(color: subColor, fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded),
                    tooltip: 'Refresh Inventory',
                    onPressed: () async {
                      await _supabaseData.refreshAll();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Row of Flexible cards — they shrink proportionally at smaller widths
              // instead of wrapping to a second row (which would overflow the fixed-height body Column).
              Row(
                children: [
                  Flexible(
                    child: _KpiCard(
                      label: 'Total Stock',
                      value: '$totalStock bottles',
                      icon: Icons.inventory_2_outlined,
                      color: AppTheme.primaryGold,
                    ),
                  ),
                  const SizedBox(width: AppTheme.adminRowGap),
                  Flexible(
                    child: _KpiCard(
                      label: 'Low Stock',
                      value: '$lowStock variant${lowStock == 1 ? '' : 's'}',
                      icon: Icons.warning_amber_rounded,
                      color: AppTheme.warning,
                      warn: lowStock > 0,
                    ),
                  ),
                  const SizedBox(width: AppTheme.adminRowGap),
                  Flexible(
                    child: _KpiCard(
                      label: 'Out of Stock',
                      value: '$outOfStock variant${outOfStock == 1 ? '' : 's'}',
                      icon: Icons.remove_circle_outline_rounded,
                      color: AppTheme.error,
                      warn: outOfStock > 0,
                    ),
                  ),
                  const SizedBox(width: AppTheme.adminRowGap),
                  Flexible(
                    child: _KpiCard(
                      label: 'Active Variants',
                      value: '$activeVariants',
                      icon: Icons.hive_outlined,
                      color: AppTheme.accentGreen,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTabBar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppTheme.textDark : AppTheme.textLight;
    final subColor = isDark
        ? AppTheme.subtitleDark(isDark)
        : AppTheme.subtitleLight(isDark);
    final borderColor = isDark ? AppTheme.borderDark : AppTheme.borderLight;
    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppTheme.adminPagePaddingCompact,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: borderColor)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: List.generate(_tabs.length, (i) {
            final sel = _tab == i;
            return Padding(
              padding: const EdgeInsets.only(right: 28),
              child: InkWell(
                onTap: () => _selectTab(i),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: sel ? AppTheme.primaryGold : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                  child: Text(
                    _tabs[i],
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: sel ? FontWeight.w800 : FontWeight.w500,
                      color: sel ? textColor : subColor,
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_tab) {
      case 0:
        return _buildOverview();
      case 1:
        return _buildVerification();
      case 2:
        return _AdjustmentsTab(db: _db, session: widget.session);
      case 3:
        return _buildBottleSizes();
      default:
        return const SizedBox();
    }
  }

  // TAB 0 — OVERVIEW
  Widget _buildOverview() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: CombineLatestStream.list([
        _supabaseData.productsStream,
        _supabaseData.inventoryStream,
      ]),
      builder: (context, snap) {
        if (snap.hasError)
          return Center(
            child: Text(
              'Error: ${snap.error}',
              style: const TextStyle(color: Colors.red),
            ),
          );
        final prodMap = snap.data != null && snap.data!.isNotEmpty
            ? snap.data![0]
            : _supabaseData.currentProducts;
        final invMap = snap.data != null && snap.data!.length > 1
            ? snap.data![1]
            : _supabaseData.currentInventory;
        if (snap.connectionState == ConnectionState.waiting &&
            prodMap.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        final List<Map<String, dynamic>> items = [];
        invMap.forEach((pId, pInv) {
          if (pInv is! Map) return;
          pInv.forEach((vId, vData) {
            if (vData is! Map) return;
            final pMeta = prodMap[pId];
            if (pMeta is! Map) return;
            final vMeta = (pMeta['variants'] as Map? ?? {})[vId];
            if (vMeta is! Map) return;
            items.add({
              'productId': pId,
              'variantId': vId,
              'productName': pMeta['name'] ?? pMeta['variety'] ?? 'Honey',
              'variety': pMeta['variety'] ?? '',
              'size': vMeta['size'] ?? '-',
              'quantity': (vData['quantity'] ?? 0) as int,
              'reorderLevel': (vMeta['reorderLevel'] ?? 10) as int,
              'lastUpdated': vData['lastUpdated'],
            });
          });
        });
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final textColor = isDark ? AppTheme.textDark : AppTheme.textLight;
        final subColor = isDark
            ? AppTheme.subtitleDark(isDark)
            : AppTheme.subtitleLight(isDark);
        final fillColor = isDark ? AppTheme.backgroundDarkAlt : Colors.white;
        final borderColor = isDark
            ? AppTheme.borderDarkAlt
            : AppTheme.borderLightAlt;
        final headerBg = isDark
            ? AppTheme.backgroundDarkAlt
            : AppTheme.backgroundLightAlt;
        final rowBorder = isDark ? AppTheme.borderDark : AppTheme.borderLight;
        final cardBg = isDark ? AppTheme.surfaceDark : Colors.white;
        final cardBorder = isDark ? AppTheme.borderDark : AppTheme.borderLight;
        if (items.isEmpty)
          return Center(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.inventory_2_outlined,
                    size: 52,
                    color: AppTheme.primaryGold,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No inventory yet',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Inventory stock will appear once products are configured.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: subColor,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          );
        final q = _search.toLowerCase().trim();
        final filtered = items.where((item) {
          final qty = item['quantity'] as int;
          final reorder = item['reorderLevel'] as int;
          final ms =
              q.isEmpty ||
              item['variety'].toString().toLowerCase().contains(q) ||
              item['size'].toString().toLowerCase().contains(q);
          final mf =
              _stockFilter == 'All' ||
              (_stockFilter == 'Low Stock' && qty > 0 && qty <= reorder) ||
              (_stockFilter == 'Out of Stock' && qty == 0);
          return ms && mf;
        }).toList();
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 16, 32, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      onChanged: (v) => setState(() => _search = v),
                      style: TextStyle(fontSize: 13, color: textColor),
                      decoration: InputDecoration(
                        hintText: 'Search by product or size...',
                        hintStyle: TextStyle(fontSize: 12, color: subColor),
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          size: 18,
                          color: subColor,
                        ),
                        filled: true,
                        fillColor: fillColor,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusPill,
                          ),
                          borderSide: BorderSide(color: borderColor),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusPill,
                          ),
                          borderSide: BorderSide(color: borderColor),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusPill,
                          ),
                          borderSide: const BorderSide(
                            color: AppTheme.primaryGold,
                            width: 1.6,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: fillColor,
                      borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                      border: Border.all(color: borderColor),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _stockFilter,
                        style: TextStyle(fontSize: 13, color: textColor),
                        dropdownColor: cardBg,
                        items: ['All', 'Low Stock', 'Out of Stock']
                            .map(
                              (s) => DropdownMenuItem(
                                value: s,
                                child: Text(
                                  s,
                                  style: TextStyle(color: textColor),
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => _stockFilter = v!),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 48,
                          horizontal: 24,
                        ),
                        margin: const EdgeInsets.symmetric(horizontal: 32),
                        decoration: BoxDecoration(
                          color: isDark
                              ? AppTheme.backgroundDarkAlt
                              : const Color(0xFFFFFBF1),
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusMd,
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.filter_alt_off_outlined,
                              size: 40,
                              color: AppTheme.primaryGold,
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'No matching variants',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: textColor,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Try adjusting your search or filter criteria.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                color: subColor,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : Container(
                      margin: const EdgeInsets.fromLTRB(32, 0, 32, 24),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                        border: Border.all(color: cardBorder),
                      ),
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 14,
                              ),
                              decoration: BoxDecoration(
                                color: headerBg,
                                borderRadius: BorderRadius.vertical(
                                  top: Radius.circular(AppTheme.radiusLg),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: Text(
                                      'PRODUCT',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 11.5,
                                        color: subColor,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      'SIZE',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 11.5,
                                        color: subColor,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      'STOCK',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 11.5,
                                        color: subColor,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      'REORDER',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 11.5,
                                        color: subColor,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      'STATUS',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 11.5,
                                        color: subColor,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      'LAST UPDATED',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 11.5,
                                        color: subColor,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 120,
                                    child: Text(
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
                              ),
                            ),
                            ...filtered.asMap().entries.map((entry) {
                              final i = entry.key;
                              final item = entry.value;
                              final qty = item['quantity'] as int;
                              final reorder = item['reorderLevel'] as int;
                              final status = qty == 0
                                  ? 'Out of Stock'
                                  : qty <= reorder
                                  ? 'Low Stock'
                                  : 'In Stock';
                              final isLast = i == filtered.length - 1;
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 13,
                                ),
                                decoration: BoxDecoration(
                                  border: Border(
                                    top: BorderSide(color: rowBorder),
                                  ),
                                  borderRadius: isLast
                                      ? BorderRadius.vertical(
                                          bottom: Radius.circular(
                                            AppTheme.radiusLg,
                                          ),
                                        )
                                      : null,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      flex: 3,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item['variety'],
                                            style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 13,
                                              color: textColor,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '#INV-${item['variantId'].toString().replaceAll('-', '').substring(0, 5).toUpperCase()}',
                                            style: const TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                              color: AppTheme.primaryGold,
                                              letterSpacing: 0.3,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        item['size'],
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: textColor,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        '$qty',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 13,
                                          color: textColor,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        '$reorder',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: textColor,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: StatusBadge(status: status),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        _timeAgo(item['lastUpdated']),
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: subColor,
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      width: 120,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: Icon(
                                              Icons.history_rounded,
                                              size: 17,
                                              color: subColor,
                                            ),
                                            tooltip: 'View Movement History',
                                            onPressed: () =>
                                                _showViewHistory(item),
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(),
                                          ),
                                          const SizedBox(width: 4),
                                          IconButton(
                                            icon: Icon(
                                              Icons.settings_outlined,
                                              size: 17,
                                              color: subColor,
                                            ),
                                            tooltip: 'Edit Reorder Level',
                                            onPressed: () {
                                              _selectTab(3);
                                            },
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(),
                                          ),
                                          if (status != 'In Stock' &&
                                              RoleCapabilities.forRole(
                                                widget.session.role,
                                              ).canRunProduction) ...[
                                            const SizedBox(width: 4),
                                            TextButton.icon(
                                              onPressed: () =>
                                                  _showCreateProduction(item),
                                              style: TextButton.styleFrom(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 2,
                                                    ),
                                                minimumSize: Size.zero,
                                                tapTargetSize:
                                                    MaterialTapTargetSize
                                                        .shrinkWrap,
                                              ),
                                              icon: Icon(
                                                Icons.add_rounded,
                                                size: 13,
                                                color: AppTheme.primaryGold,
                                              ),
                                              label: Text(
                                                'Prod.',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700,
                                                  color: AppTheme.primaryGold,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }

  void _showViewHistory(Map<String, dynamic> item) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: SizedBox(
          width: 600,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 16, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${item['variety']} — ${item['size']}',
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const Text(
                            'Inventory movement history',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              const Divider(height: 20),
              SizedBox(
                height: 380,
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: SupabaseDataService()
                      .fetchMovementsForVariantExternalId(
                        item['variantId']?.toString() ?? '',
                      ),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting)
                      return const Center(child: CircularProgressIndicator());
                    if (snap.hasError)
                      return Center(
                        child: Text(
                          'Error: ${snap.error}',
                          style: const TextStyle(color: Colors.grey),
                        ),
                      );
                    final relevant = snap.data ?? [];
                    if (relevant.isEmpty)
                      return const Center(
                        child: Text(
                          'No movements yet for this variant.',
                          style: TextStyle(color: Colors.grey),
                        ),
                      );
                    return ListView.separated(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 8,
                      ),
                      itemCount: relevant.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final m = relevant[i];
                        final change = (m['quantity_change'] ?? 0) as int;
                        final isPos = change > 0;
                        final prevQty = (m['prev_quantity'] ?? 0).toString();
                        final newQty = (m['new_quantity'] ?? 0).toString();
                        final reason = m['reason']?.toString();
                        final notes = m['notes']?.toString();
                        final movType = m['movement_type']?.toString() ?? '';
                        final darkHist =
                            Theme.of(context).brightness == Brightness.dark;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: isPos
                                      ? (darkHist
                                            ? AppTheme.iconBadgeGreenDark
                                            : AppTheme.iconBadgeGreenLight)
                                      : (darkHist
                                            ? AppTheme.badgeRedBgDark
                                            : AppTheme.badgeRedBgLight),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  isPos
                                      ? Icons.arrow_upward_rounded
                                      : Icons.arrow_downward_rounded,
                                  size: 16,
                                  color: isPos ? Colors.green : Colors.red,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          '${isPos ? '+' : ''}$change bottles',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w800,
                                            color: isPos
                                                ? Colors.green
                                                : Colors.red,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          '$prevQty → $newQty',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Text(
                                      _movementLabel(movType) +
                                          (reason != null ? ' · $reason' : ''),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                      ),
                                    ),
                                    if (notes != null && notes.isNotEmpty)
                                      Text(
                                        notes,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    Text(
                                      _timeAgo(m['timestamp']),
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  void _showCreateProduction(Map<String, dynamic> item) {
    final int current = item['quantity'] as int;
    final int reorder = item['reorderLevel'] as int;
    final int suggested = ((reorder - current) > 0
        ? (reorder - current) * 2
        : 50);
    final ctrl = TextEditingController(text: '$suggested');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Create Production from Low Stock Alert',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Product: ${item['variety']} (${item['size']})',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Current Stock: $current',
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'Reorder Level: $reorder',
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: ctrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Target Quantity',
                  hintText: 'Enter production target',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _gold),
            onPressed: () async {
              final target = int.tryParse(ctrl.text.trim()) ?? suggested;
              if (target <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Target must be > 0.')),
                );
                return;
              }
              await SupabaseDataService().createProductionBatch(
                productExternalId: item['productId'] as String,
                variantExternalId: item['variantId'] as String,
                qtyTarget: target,
                startDate: DateTime.now().toString().split(' ')[0],
                targetCompletionDate: DateTime.now()
                    .add(const Duration(days: 5))
                    .toString()
                    .split(' ')[0],
              );
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Production batch created from low stock alert.',
                  ),
                ),
              );
            },
            child: const Text('Create Production'),
          ),
        ],
      ),
    );
  }

  // TAB 1 — VERIFICATION
  Widget _buildVerification() {
    return Column(
      children: [
        // ── Top bar: toggles + ESP32 live status ─────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
          child: Row(
            children: [
              _ToggleChip(
                label: 'Pending Results',
                active: _verifyView == 0,
                onTap: () => _selectVerificationView(0),
              ),
              const SizedBox(width: 10),
              _ToggleChip(
                label: 'Scan History',
                active: _verifyView == 1,
                onTap: () => _selectVerificationView(1),
              ),
              const SizedBox(width: 10),
              _ToggleChip(
                label: 'Size Thresholds',
                active: _verifyView == 2,
                onTap: () => _selectVerificationView(2),
              ),
              const Spacer(),
              // Live ESP32 connection status badge
              StreamBuilder<DatabaseEvent>(
                stream: _iotStatusStream,
                builder: (context, snap) {
                  bool online = false;
                  if (snap.hasData && snap.data?.snapshot.value != null) {
                    final data = snap.data!.snapshot.value;
                    if (data is Map) {
                      final lastSeen = (data['lastSeen'] ?? 0) as int;
                      online =
                          DateTime.now()
                              .difference(
                                DateTime.fromMillisecondsSinceEpoch(lastSeen),
                              )
                              .inSeconds <
                          90;
                    }
                  }
                  final statusLabel = snap.hasError
                      ? 'ESP32 · Unavailable'
                      : online
                      ? 'ESP32 · Online'
                      : 'ESP32 · Offline';
                  final darkEsp =
                      Theme.of(context).brightness == Brightness.dark;
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: online
                          ? (darkEsp
                                ? AppTheme.iconBadgeGreenDark
                                : AppTheme.iconBadgeGreenLight)
                          : (darkEsp
                                ? const Color(0xFF2A2620)
                                : const Color(0xFFF2F0EC)),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: online
                            ? (darkEsp
                                  ? AppTheme.badgeGreenBorderDark
                                  : AppTheme.badgeGreenBorderLight)
                            : (darkEsp
                                  ? const Color(0xFF4C4638)
                                  : const Color(0xFFE8DFC8)),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: online ? Colors.green : Colors.grey,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          statusLabel,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: online ? Colors.green : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _verifyView == 0
              ? _buildPendingScans()
              : _verifyView == 1
              ? _buildScanHistory()
              : _buildSizeThresholds(),
        ),
      ],
    );
  }

  Widget _buildScannerUnavailable() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 36,
              color: AppTheme.textSecondary(isDark),
            ),
            const SizedBox(height: 12),
            Text(
              'Scanner connection unavailable',
              style: TextStyle(
                color: AppTheme.textPrimary(isDark),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Firebase scanner data could not be loaded. Supabase inventory is unaffected.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary(isDark)),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _retryScannerConnection,
              child: const Text('Retry scanner connection'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPendingScans() {
    // Listen to scan_commands to track active/completed scans
    return StreamBuilder<DatabaseEvent>(
      stream: _scanCommandsStream,
      builder: (context, cmdSnap) {
        // Determine if a scan is currently pending
        bool scanInProgress = false;
        if (cmdSnap.hasData && cmdSnap.data?.snapshot.value != null) {
          final cmdsRaw = cmdSnap.data!.snapshot.value;
          if (cmdsRaw is Map) {
            cmdsRaw.forEach((k, v) {
              if (v is Map && v['status'] == 'pending') {
                scanInProgress = true;
              }
            });
          }
          // If we had an active command and it's now completed, clear local state
          if (_activeScanCommandId != null && !scanInProgress) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                setState(() {
                  _activeScanCommandId = null;
                });
              }
            });
          }
        }

        return StreamBuilder<DatabaseEvent>(
          stream: _scanResultsStream,
          builder: (context, snap) {
            if (cmdSnap.hasError || snap.hasError) {
              return _buildScannerUnavailable();
            }
            final pending = <Map<String, dynamic>>[];
            if (snap.hasData && snap.data?.snapshot.value != null) {
              final raw = Map<String, dynamic>.from(
                snap.data!.snapshot.value as Map,
              );
              pending.addAll(
                raw.entries
                    .map((e) {
                      final v = Map<String, dynamic>.from(e.value as Map);
                      v['id'] = e.key;
                      return v;
                    })
                    .where((s) => s['isAcknowledged'] != true)
                    .toList()
                  ..sort(
                    (a, b) => ((b['scanTimestamp'] ?? 0) as int).compareTo(
                      (a['scanTimestamp'] ?? 0) as int,
                    ),
                  ),
              );
            }

            final darkInfo = Theme.of(context).brightness == Brightness.dark;
            return ListView(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              children: [
                // ── Start Scan panel ────────────────────────────────────────
                _buildStartScanPanel(scanInProgress),
                const SizedBox(height: 16),

                // ── How it works (collapsible) ───────────────────────────────
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: darkInfo
                        ? const Color(0xFF12213F)
                        : const Color(0xFFF0F7FF),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: darkInfo
                          ? AppTheme.badgeBlueBorderDark
                          : AppTheme.badgeBlueBorderLight,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      InkWell(
                        onTap: () => setState(
                          () => _verifyInfoExpanded = !_verifyInfoExpanded,
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.info_outline_rounded,
                              size: 16,
                              color: Colors.blueAccent,
                            ),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'How IoT Verification Works',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.blueAccent,
                                ),
                              ),
                            ),
                            Icon(
                              _verifyInfoExpanded
                                  ? Icons.expand_less_rounded
                                  : Icons.expand_more_rounded,
                              size: 18,
                              color: Colors.blueAccent,
                            ),
                          ],
                        ),
                      ),
                      if (_verifyInfoExpanded) ...[
                        const SizedBox(height: 6),
                        const Text(
                          '1. Click "Start Scan" — the ESP32-CAM will physically count bottles.\n'
                          '2. Results appear here automatically.\n'
                          '3. MATCH → Acknowledge (no inventory change).\n'
                          '4. MISMATCH → Physically verify first, then:\n'
                          '   – Reconcile: Trust the ESP32 count, adjust inventory.\n'
                          '   – Acknowledge: Reviewed, no change needed. Use\n'
                          '     Stock Corrections later if needed.',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.blueAccent,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // ── Pending scan results ────────────────────────────────────
                if (pending.isEmpty)
                  _emptyVerification()
                else
                  ...pending.map((s) => _buildScanCard(s, widget.session)),
              ],
            );
          },
        );
      },
    );
  }

  // ── Start Scan panel ────────────────────────────────────────────────────────
  Widget _buildStartScanPanel(bool scanInProgress) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cameraUrl = _cameraStreamUrl;
    final cameraStatus = cameraUrl == null
        ? 'INVALID CAMERA URL'
        : switch (_cameraStatus) {
            CameraStreamStatus.connecting => 'CONNECTING',
            CameraStreamStatus.connected => 'CONNECTED',
            CameraStreamStatus.disconnected => 'DISCONNECTED',
          };
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isDark
              ? AppTheme.badgeGoldBorderDark
              : AppTheme.badgeGoldBorderLight,
        ),
      ),
      color: isDark ? const Color(0xFF1E293B) : const Color(0xFFFFFDF5),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppTheme.iconBadgeGoldDark
                        : AppTheme.iconBadgeGoldLight,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.videocam_rounded,
                    color: _gold,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          const Text(
                            'ESP32-CAM Physical Stock Scanner',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.orange.withAlpha(35),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: Colors.orange.withAlpha(70),
                              ),
                            ),
                            child: const Text(
                              'OV5640 · UNVERIFIED',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                color: Colors.deepOrange,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'MJPEG stream: ${cameraUrl ?? 'Enter a valid ESP32 address'}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.settings_outlined, size: 18),
                  tooltip: 'Configure Camera IP',
                  onPressed: _showEsp32ConfigDialog,
                ),
                IconButton(
                  icon: Icon(
                    _cameraPreviewExpanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 20,
                  ),
                  tooltip: 'Toggle Camera Viewfinder',
                  onPressed: () => setState(() {
                    _cameraPreviewExpanded = !_cameraPreviewExpanded;
                    _cameraStatus = CameraStreamStatus.connecting;
                  }),
                ),
              ],
            ),

            if (_cameraPreviewExpanded) ...[
              const SizedBox(height: 16),
              // The platform-specific view renders the camera's MJPEG stream.
              Container(
                height: 200,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _gold.withAlpha(80), width: 1.5),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: cameraUrl == null
                          ? const Center(
                              child: Text(
                                'Enter a valid camera IP or HTTP URL.',
                                style: TextStyle(color: Colors.white),
                              ),
                            )
                          : CameraMjpegPreview(
                              key: ValueKey(cameraUrl),
                              url: cameraUrl,
                              retryKey: _cameraRetryKey,
                              onStatusChanged: _updateCameraStatus,
                            ),
                    ),
                    Positioned(
                      top: 10,
                      left: 12,
                      child: Row(
                        children: [
                          Icon(
                            _cameraStatus == CameraStreamStatus.connected
                                ? Icons.circle
                                : Icons.circle_outlined,
                            color: _cameraStatus == CameraStreamStatus.connected
                                ? Colors.greenAccent
                                : Colors.orangeAccent,
                            size: 9,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            cameraStatus,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Continuous MJPEG',
                            style: TextStyle(
                              color: Colors.white.withAlpha(180),
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      bottom: 10,
                      left: 12,
                      child: const Text(
                        'ESP32 CameraWebServer',
                        style: TextStyle(color: Colors.white70, fontSize: 10),
                      ),
                    ),
                    Positioned(
                      bottom: 10,
                      right: 12,
                      child: TextButton.icon(
                        onPressed: _retryCameraStream,
                        icon: const Icon(
                          Icons.refresh_rounded,
                          size: 14,
                          color: Colors.white,
                        ),
                        label: const Text(
                          'Reconnect',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          backgroundColor: Colors.black54,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 16),

            if (scanInProgress)
              // Active scan in progress
              Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _gold,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'Scan command sent — waiting for ESP32 results...',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _gold,
                    ),
                  ),
                ],
              )
            else
            // Action buttons row — Co-Admin only (IoT scan creates a Firebase write)
            if (RoleCapabilities.forRole(widget.session.role).canAdjustStock)
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _gold,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                      onPressed: () async {
                        try {
                          final cmdId = await _db.createScanCommand(
                            adminId:
                                widget.session.firebaseUid ??
                                widget.session.uid,
                            adminName: widget.session.name,
                          );
                          if (mounted)
                            setState(() => _activeScanCommandId = cmdId);
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Failed to start scan: $e'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.play_arrow_rounded, size: 20),
                      label: const Text(
                        'Start Physical Count Scan',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        vertical: 13,
                        horizontal: 16,
                      ),
                    ),
                    onPressed: _retryCameraStream,
                    icon: const Icon(Icons.camera_alt_outlined, size: 18),
                    label: const Text(
                      'Reconnect Camera',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  void _showEsp32ConfigDialog() {
    final ipCtrl = TextEditingController(text: _esp32CameraIp);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Configure ESP32-CAM',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter the ESP32 camera IP or URL. The admin page opens a continuous MJPEG connection on the CameraWebServer stream port.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: ipCtrl,
              decoration: const InputDecoration(
                labelText: 'ESP32-CAM IP Address',
                hintText: 'e.g. 192.168.1.100',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lan_outlined),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _gold,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              final candidate = ipCtrl.text.trim();
              final address = candidate.contains('://')
                  ? candidate
                  : 'http://$candidate';
              final uri = Uri.tryParse(address);
              if (uri == null ||
                  !uri.hasAuthority ||
                  uri.host.isEmpty ||
                  !const {'http', 'https'}.contains(uri.scheme.toLowerCase())) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Enter a valid camera IP or HTTP URL.'),
                  ),
                );
                return;
              }
              setState(() {
                _esp32CameraIp = candidate;
                _cameraRetryKey++;
                _cameraStatus = CameraStreamStatus.connecting;
              });
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('ESP32-CAM IP updated to $_esp32CameraIp'),
                ),
              );
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Widget _emptyVerification() {
    final darkEmpty = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(top: 40),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: darkEmpty
                    ? AppTheme.iconBadgeGreenDark
                    : AppTheme.iconBadgeGreenLight,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.verified_outlined,
                size: 32,
                color: Colors.green,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'All clear — no pending scan results.',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Click "Start Scan" to request a physical inventory count.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScanCard(Map<String, dynamic> s, AuthSession session) {
    // Determine if this is a new multi-size scan (has detectedSizes map)
    // or a legacy single-size scan (has detectedQuantity field)
    final detectedSizes = s['detectedSizes'];
    if (detectedSizes is Map && detectedSizes.isNotEmpty) {
      return _buildMultiSizeScanCard(s, session);
    }
    // Legacy single-size scan card (backward compatible)
    final int detected = s['detectedQuantity'] ?? 0;
    final int system = s['systemQuantity'] ?? 0;
    final int diff = s['difference'] ?? (detected - system);
    final String status =
        s['status'] ?? (detected == system ? 'MATCH' : 'MISMATCH');
    final bool isMismatch = status == 'MISMATCH';
    final darkScan1 = Theme.of(context).brightness == Brightness.dark;
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isMismatch
              ? (darkScan1 ? const Color(0xFF6B4520) : const Color(0xFFF0C7A2))
              : (darkScan1
                    ? AppTheme.badgeGreenBorderDark
                    : AppTheme.badgeGreenBorderLight),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: isMismatch
                        ? (darkScan1
                              ? const Color(0xFF3A2410)
                              : const Color(0xFFFBEEE1))
                        : (darkScan1
                              ? AppTheme.iconBadgeGreenDark
                              : AppTheme.iconBadgeGreenLight),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isMismatch
                        ? Icons.warning_amber_rounded
                        : Icons.check_circle_outline_rounded,
                    color: isMismatch ? Colors.deepOrange : Colors.green,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${s['productName'] ?? 'Honey'} (${s['bottleSize'] ?? '-'})',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        'Scanned ${_timeAgo(s['scanTimestamp'])}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                StatusBadge(status: status),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _CountBox(
                  label: 'Physical Count',
                  value: detected,
                  color: isMismatch ? Colors.deepOrange : Colors.green,
                ),
                const SizedBox(width: 10),
                _CountBox(
                  label: 'System Inventory',
                  value: system,
                  color: Colors.grey,
                ),
                const SizedBox(width: 10),
                _CountBox(
                  label: 'Difference',
                  value: diff,
                  color: diff == 0 ? Colors.green : Colors.deepOrange,
                  showSign: true,
                ),
              ],
            ),
            if (isMismatch) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: darkScan1
                      ? const Color(0xFF3A2410)
                      : const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: darkScan1
                        ? const Color(0xFF6B4520)
                        : const Color(0xFFF0C7A2),
                  ),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.tips_and_updates_outlined,
                      size: 14,
                      color: Color(0xFFB8860B),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Physically count the bottles. If ESP32 is correct → Reconcile. '
                        'If system is correct → Acknowledge.',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF7A6300),
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: () => _confirmAcknowledge(s['id']),
                  child: const Text('Acknowledge'),
                ),
                if (isMismatch) ...[
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryGold,
                      foregroundColor: Colors.black87,
                    ),
                    onPressed: () {
                      _confirmAcknowledge(s['id'], thenGoToCorrections: true);
                    },
                    icon: const Icon(Icons.search_rounded, size: 15),
                    label: const Text(
                      'Investigate → Stock Corrections',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── New multi-size scan card (ESP32 with detectedSizes map) ─────────────────
  Widget _buildMultiSizeScanCard(Map<String, dynamic> s, AuthSession session) {
    final detectedSizes = Map<String, dynamic>.from(s['detectedSizes'] as Map);
    final int totalDetected =
        s['totalDetected'] ??
        detectedSizes.values.fold<int>(
          0,
          (sum, v) => sum + ((v as num).toInt()),
        );
    final String overallStatus = s['overallStatus'] ?? 'UNKNOWN';
    final bool hasMismatch =
        overallStatus == 'PARTIAL_MISMATCH' || overallStatus == 'MISMATCH';
    final initiatedBy = s['requestedByName']?.toString() ?? 'Co-Admin';

    // Build per-size comparisons from scan result
    // comparisons map: { "250g": { physical, system, diff, status } }
    final comparisons = <Map<String, dynamic>>[];
    if (s['comparisons'] is Map) {
      final cmpMap = Map<String, dynamic>.from(s['comparisons'] as Map);
      cmpMap.forEach((size, val) {
        if (val is Map) {
          comparisons.add({
            'size': size,
            'physical': (val['physical'] ?? 0) as int,
            'system': (val['system'] ?? 0) as int,
            'diff': (val['diff'] ?? 0) as int,
            'status': val['status']?.toString() ?? 'UNKNOWN',
            'productId': val['productId']?.toString() ?? '',
            'variantId': val['variantId']?.toString() ?? '',
          });
        }
      });
    } else {
      // Fallback: build from detectedSizes only (no system comparison yet)
      detectedSizes.forEach((size, count) {
        final qty = count is int ? count : (count as num).toInt();
        comparisons.add({
          'size': size,
          'physical': qty,
          'system': 0,
          'diff': qty,
          'status': 'UNKNOWN',
          'productId': '',
          'variantId': '',
        });
      });
    }
    comparisons.sort((a, b) => a['size'].compareTo(b['size']));

    final mismatches = comparisons
        .where((c) => c['status'] == 'MISMATCH' && c['diff'] != 0)
        .toList();

    final darkScan2 = Theme.of(context).brightness == Brightness.dark;
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: hasMismatch
              ? (darkScan2 ? const Color(0xFF6B4520) : const Color(0xFFF0C7A2))
              : (darkScan2
                    ? AppTheme.badgeGreenBorderDark
                    : AppTheme.badgeGreenBorderLight),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: hasMismatch
                        ? (darkScan2
                              ? const Color(0xFF3A2410)
                              : const Color(0xFFFBEEE1))
                        : (darkScan2
                              ? AppTheme.iconBadgeGreenDark
                              : AppTheme.iconBadgeGreenLight),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.camera_alt_outlined,
                    color: hasMismatch ? Colors.deepOrange : Colors.green,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Physical Inventory Scan',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        '${_timeAgo(s['scanTimestamp'])} · by $initiatedBy',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: hasMismatch
                            ? (darkScan2
                                  ? const Color(0xFF3A2410)
                                  : const Color(0xFFFBEEE1))
                            : (darkScan2
                                  ? AppTheme.iconBadgeGreenDark
                                  : AppTheme.iconBadgeGreenLight),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: hasMismatch
                              ? (darkScan2
                                    ? const Color(0xFF6B4520)
                                    : const Color(0xFFF0C7A2))
                              : (darkScan2
                                    ? AppTheme.badgeGreenBorderDark
                                    : AppTheme.badgeGreenBorderLight),
                        ),
                      ),
                      child: Text(
                        hasMismatch
                            ? 'PARTIAL MISMATCH'
                            : overallStatus == 'MATCH'
                            ? 'ALL MATCH'
                            : overallStatus,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: hasMismatch ? Colors.deepOrange : Colors.green,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Total: $totalDetected bottles detected',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Per-size comparison table
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFEEEEEE)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  // Header row
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: const BoxDecoration(
                      color: Color(0xFFF7F7F7),
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(8),
                      ),
                    ),
                    child: const Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: Text(
                            'SIZE',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            'PHYSICAL',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            'SYSTEM',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            'DIFF',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            'STATUS',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Data rows
                  ...comparisons.map((c) {
                    final isMismatch = c['status'] == 'MISMATCH';
                    final diff = c['diff'] as int;
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: isMismatch
                            ? (darkScan2
                                  ? const Color(0xFF3A2410)
                                  : const Color(0xFFFBEEE1))
                            : null,
                        border: const Border(
                          top: BorderSide(color: Color(0xFFEEEEEE)),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: Text(
                              c['size'],
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              '${c['physical']}',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                                color: isMismatch
                                    ? Colors.deepOrange
                                    : Colors.green,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              '${c['system']}',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              diff == 0 ? '0' : '${diff > 0 ? '+' : ''}$diff',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: diff == 0
                                    ? Colors.green
                                    : Colors.deepOrange,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isMismatch
                                      ? Icons.warning_amber_rounded
                                      : Icons.check_circle_outline_rounded,
                                  size: 14,
                                  color: isMismatch
                                      ? Colors.deepOrange
                                      : Colors.green,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  isMismatch ? 'Mismatch' : 'Match',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: isMismatch
                                        ? Colors.deepOrange
                                        : Colors.green,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),

            // Mismatch summary
            if (hasMismatch) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: darkScan2
                      ? const Color(0xFF3A2410)
                      : const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: darkScan2
                        ? const Color(0xFF6B4520)
                        : const Color(0xFFF0C7A2),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.tips_and_updates_outlined,
                      size: 14,
                      color: Color(0xFFB8860B),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${mismatches.length} size${mismatches.length == 1 ? '' : 's'} '
                        'differ from system inventory. Physically verify the counts, then '
                        'choose Acknowledge (no change) or Reconcile (adjust inventory).',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF7A6300),
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 14),
            // ── Architecture note displayed for mismatches ─────────────────
            if (hasMismatch) ...[
              Container(
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: darkScan2
                      ? const Color(0xFF0E1F35)
                      : const Color(0xFFF0F7FF),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: darkScan2
                        ? AppTheme.badgeBlueBorderDark
                        : AppTheme.badgeBlueBorderLight,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.info_outline_rounded,
                      size: 14,
                      color: Colors.blueAccent,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'The ESP32-CAM counts bottles by size — it cannot identify '
                        'which honey variety they belong to. Use Stock Corrections '
                        'to adjust a specific product after physically investigating.',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.blueAccent,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Always available — marks the scan as reviewed, no inventory change
                OutlinedButton(
                  onPressed: () => _confirmAcknowledgeMulti(s['id'], session),
                  child: const Text('Acknowledge'),
                ),
                if (hasMismatch) ...[
                  const SizedBox(width: 10),
                  // Opens Stock Corrections tab — admin picks the specific product/variant
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryGold,
                      foregroundColor: Colors.black87,
                    ),
                    onPressed: () {
                      _confirmAcknowledgeMulti(
                        s['id'],
                        session,
                        thenGoToCorrections: true,
                      );
                    },
                    icon: const Icon(Icons.search_rounded, size: 15),
                    label: const Text(
                      'Investigate → Stock Corrections',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _confirmAcknowledgeMulti(
    String scanId,
    AuthSession session, {
    bool thenGoToCorrections = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.panelColor(isDark),
        title: const Text(
          'Acknowledge Scan Result',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        content: Text(
          thenGoToCorrections
              ? 'Mark this scan as reviewed, then go to Stock Corrections to apply '
                    'any manual adjustment to the specific product/variant you identified.\n\n'
                    'No inventory will be changed automatically.'
              : 'Mark this scan as reviewed with no inventory changes.\n\n'
                    'The scan will move to Scan History.\n\n'
                    'If a correction is needed, use Stock Corrections → Counting Correction.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: thenGoToCorrections
                ? ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryGold,
                    foregroundColor: Colors.black87,
                  )
                : null,
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await _db.acknowledgeScan(
                  scanId,
                  session.firebaseUid ?? session.uid,
                );
              } catch (error) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Failed to acknowledge scan: $error'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              if (!mounted) return;
              if (thenGoToCorrections) {
                _selectTab(2); // go to Stock Corrections
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Scan acknowledged. Use Stock Corrections to adjust the specific product.',
                    ),
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text(
                      'Scan acknowledged. No inventory changes made.',
                    ),
                    action: SnackBarAction(
                      label: 'Stock Corrections',
                      onPressed: () => _selectTab(2),
                    ),
                  ),
                );
              }
            },
            child: Text(
              thenGoToCorrections
                  ? 'Acknowledge & Go to Corrections'
                  : 'Acknowledge',
            ),
          ),
        ],
      ),
    );
  }

  // ── TAB 1 / VIEW 2 — BOTTLE SIZE THRESHOLDS ──────────────────────────────
  //
  // Lets the admin configure per-size low-stock thresholds that are used when
  // updateScanResultWithComparisons() fires after an ESP32 scan.
  //
  // All known sizes are derived live from the products/ node so the list
  // always stays in sync as products are added or changed.
  Widget _buildSizeThresholds() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppTheme.textDark : AppTheme.textLight;
    final subColor = isDark
        ? AppTheme.subtitleDark(isDark)
        : AppTheme.subtitleLight(isDark);
    final cardBg = isDark ? AppTheme.surfaceDark : Colors.white;
    final cardBorder = isDark ? AppTheme.borderDark : const Color(0xFFEEEEEE);
    final headerBg = isDark
        ? AppTheme.backgroundDarkAlt
        : const Color(0xFFF7F7F7);

    return StreamBuilder<List<dynamic>>(
      stream: CombineLatestStream.list([
        _supabaseData.productsStream,
        _db.getBottleSizeThresholdsStream(),
      ]),
      builder: (context, snap) {
        if (snap.hasError) return _buildScannerUnavailable();
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        // Collect all unique sizes from products
        final pRaw = snap.data != null && snap.data!.isNotEmpty
            ? (snap.data![0] is Map
                  ? snap.data![0] as Map
                  : _supabaseData.currentProducts)
            : _supabaseData.currentProducts;
        final tRaw =
            snap.data != null &&
                snap.data!.length > 1 &&
                snap.data![1] is DatabaseEvent
            ? (snap.data![1] as DatabaseEvent).snapshot.value
            : null;

        final Set<String> knownSizes = {};
        if (pRaw.isNotEmpty) {
          pRaw.forEach((_, pVal) {
            if (pVal is! Map) return;
            (pVal['variants'] as Map? ?? {}).forEach((_, vVal) {
              if (vVal is! Map) return;
              final size = vVal['size']?.toString() ?? '';
              if (size.isNotEmpty) knownSizes.add(size);
            });
          });
        }

        // Parse existing thresholds
        final Map<String, int> thresholds = {};
        if (tRaw is Map) {
          tRaw.forEach((_, v) {
            if (v is! Map) return;
            final size = v['size']?.toString() ?? '';
            final t = (v['lowStockThreshold'] as num?)?.toInt() ?? 0;
            if (size.isNotEmpty) thresholds[size] = t;
          });
        }

        // Sort sizes (numeric gram value, same as products_page.dart)
        int sizeToGrams(String s) {
          final lower = s.toLowerCase().trim();
          final m = RegExp(
            r'^(\d+(?:\.\d+)?)\s*(kg|g|ml|l)?',
          ).firstMatch(lower);
          if (m == null) return 9999;
          final n = double.tryParse(m.group(1) ?? '0') ?? 0;
          final u = m.group(2) ?? 'g';
          return (u == 'kg' || u == 'l') ? (n * 1000).round() : n.round();
        }

        final sortedSizes = knownSizes.toList()
          ..sort((a, b) => sizeToGrams(a).compareTo(sizeToGrams(b)));

        return ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          children: [
            // ── Explanation header ─────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(14),
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF12213F)
                    : const Color(0xFFF0F7FF),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isDark
                      ? AppTheme.badgeBlueBorderDark
                      : AppTheme.badgeBlueBorderLight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.settings_outlined,
                        size: 15,
                        color: Colors.blueAccent,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Bottle Size Low-Stock Thresholds',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: Colors.blueAccent,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Set the minimum acceptable physical bottle count per size. '
                    'After each ESP32 scan, if the detected count for a size '
                    'falls at or below its threshold, a low-stock notification '
                    'is automatically sent.\n\n'
                    'These thresholds are independent from product-level Reorder Levels. '
                    'They apply to the total physical bottle count across all honey varieties '
                    'sharing the same bottle size.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.blueAccent,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),

            if (sortedSizes.isEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppTheme.backgroundDarkAlt
                      : const Color(0xFFFFFBF1),
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                  border: Border.all(
                    color: isDark
                        ? AppTheme.borderDarkAlt
                        : AppTheme.borderLight,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.hive_outlined,
                      size: 40,
                      color: AppTheme.primaryGold,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No bottle sizes found.',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Add product variants in the Products module to populate this list.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: subColor),
                    ),
                  ],
                ),
              )
            else
              // ── Thresholds table ─────────────────────────────────────────
              Container(
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                  border: Border.all(color: cardBorder),
                ),
                child: Column(
                  children: [
                    // Table header
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 13,
                      ),
                      decoration: BoxDecoration(
                        color: headerBg,
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(AppTheme.radiusLg),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Text(
                              'BOTTLE SIZE',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 11.5,
                                color: subColor,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text(
                              'LOW-STOCK THRESHOLD',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 11.5,
                                color: subColor,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text(
                              'CURRENT STATUS',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 11.5,
                                color: subColor,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 80,
                            child: Text(
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
                      ),
                    ),

                    // One row per known bottle size
                    ...sortedSizes.asMap().entries.map((entry) {
                      final i = entry.key;
                      final size = entry.value;
                      final isLast = i == sortedSizes.length - 1;
                      final int? threshold = thresholds[size];
                      final bool configured = threshold != null;

                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 13,
                        ),
                        decoration: BoxDecoration(
                          border: Border(top: BorderSide(color: cardBorder)),
                          borderRadius: isLast
                              ? BorderRadius.vertical(
                                  bottom: Radius.circular(AppTheme.radiusLg),
                                )
                              : null,
                        ),
                        child: Row(
                          children: [
                            // Size label
                            Expanded(
                              flex: 3,
                              child: Text(
                                size,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  color: textColor,
                                ),
                              ),
                            ),
                            // Threshold value
                            Expanded(
                              flex: 3,
                              child: configured
                                  ? Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: isDark
                                                ? AppTheme.iconBadgeGoldDark
                                                : AppTheme.iconBadgeGoldLight,
                                            borderRadius: BorderRadius.circular(
                                              AppTheme.radiusPill,
                                            ),
                                            border: Border.all(
                                              color: isDark
                                                  ? AppTheme.badgeGoldBorderDark
                                                  : AppTheme
                                                        .badgeGoldBorderLight,
                                            ),
                                          ),
                                          child: Text(
                                            '≤ $threshold bottles',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w800,
                                              color: AppTheme.primaryGold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    )
                                  : Text(
                                      'Not set',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: subColor,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                            ),
                            // Current status (notConfigured / OK / low-stock indicator)
                            Expanded(
                              flex: 3,
                              child: !configured
                                  ? Text('—', style: TextStyle(color: subColor))
                                  : Text(
                                      'Alerts when detected ≤ $threshold',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: subColor,
                                      ),
                                    ),
                            ),
                            // Action: set / edit / remove — Co-Admin only
                            SizedBox(
                              width: 80,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (RoleCapabilities.forRole(
                                    widget.session.role,
                                  ).canAdjustStock) ...[
                                    IconButton(
                                      icon: Icon(
                                        Icons.edit_outlined,
                                        size: 17,
                                        color: AppTheme.primaryGold,
                                      ),
                                      tooltip: configured
                                          ? 'Edit threshold'
                                          : 'Set threshold',
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      onPressed: () => _showSetThresholdDialog(
                                        size: size,
                                        current: threshold,
                                      ),
                                    ),
                                    if (configured) ...[
                                      const SizedBox(width: 8),
                                      IconButton(
                                        icon: Icon(
                                          Icons.delete_outline_rounded,
                                          size: 17,
                                          color: AppTheme.error,
                                        ),
                                        tooltip: 'Remove threshold',
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        onPressed: () =>
                                            _confirmDeleteThreshold(size),
                                      ),
                                    ],
                                  ], // end canAdjustStock
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  void _showSetThresholdDialog({required String size, int? current}) {
    final ctrl = TextEditingController(text: current != null ? '$current' : '');
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.panelColor(isDark),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
          side: BorderSide(
            color: isDark ? AppTheme.borderDarkAlt : AppTheme.borderLight,
          ),
        ),
        title: Text(
          '${current != null ? 'Edit' : 'Set'} Threshold — $size',
          style: TextStyle(
            color: AppTheme.textPrimary(isDark),
            fontWeight: FontWeight.w900,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter the minimum acceptable physical bottle count for $size. '
              'When the ESP32 detects this quantity or fewer, a low-stock '
              'notification will be sent automatically.',
              style: TextStyle(
                fontSize: 13,
                color: AppTheme.textSecondary(isDark),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Low-Stock Threshold',
                hintText: 'e.g. 15',
                suffixText: 'bottles',
                filled: true,
                fillColor: AppTheme.fieldFill(isDark),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                  borderSide: const BorderSide(
                    color: AppTheme.primaryGold,
                    width: 1.8,
                  ),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryGold,
              foregroundColor: Colors.black87,
            ),
            onPressed: () async {
              final val = int.tryParse(ctrl.text.trim());
              if (val == null || val < 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please enter a valid number (0 or more).'),
                    backgroundColor: Colors.redAccent,
                  ),
                );
                return;
              }
              try {
                await _db.upsertBottleSizeThreshold(
                  size: size,
                  lowStockThreshold: val,
                  adminName: widget.session.name,
                );
              } catch (error) {
                if (!mounted || !ctx.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Failed to save threshold: $error'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Threshold saved: $size will alert at ≤ $val bottles.',
                  ),
                  backgroundColor: AppTheme.success,
                ),
              );
            },
            child: const Text(
              'Save',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteThreshold(String size) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.panelColor(isDark),
        title: Text(
          'Remove Threshold — $size',
          style: TextStyle(
            color: AppTheme.textPrimary(isDark),
            fontWeight: FontWeight.w900,
          ),
        ),
        content: Text(
          'Remove the low-stock threshold for $size? '
          'No low-stock notification will be sent for this size after scans.',
          style: TextStyle(fontSize: 13, color: AppTheme.textSecondary(isDark)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              try {
                await _db.deleteBottleSizeThreshold(size);
              } catch (error) {
                if (!mounted || !ctx.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Failed to remove threshold: $error'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Threshold removed for $size.')),
              );
            },
            child: const Text(
              'Remove',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanHistory() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final subColor = isDark
        ? AppTheme.subtitleDark(isDark)
        : AppTheme.subtitleLight(isDark);
    final headerBg = isDark
        ? AppTheme.backgroundDarkAlt
        : const Color(0xFFF7F7F7);
    final borderColor = isDark ? AppTheme.borderDark : const Color(0xFFEEEEEE);
    final cardBg = isDark ? AppTheme.surfaceDark : Colors.white;
    final cardBorder = isDark ? AppTheme.borderDark : const Color(0xFFEEEEEE);
    final textColor = isDark ? AppTheme.textDark : AppTheme.textLight;

    return StreamBuilder<DatabaseEvent>(
      stream: _scanResultsStream,
      builder: (context, snap) {
        if (snap.hasError) return _buildScannerUnavailable();
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snap.hasData || snap.data?.snapshot.value == null) {
          return Center(
            child: Text(
              'No scan history recorded.',
              style: TextStyle(color: subColor, fontSize: 13),
            ),
          );
        }

        final raw = Map<String, dynamic>.from(snap.data!.snapshot.value as Map);
        // Sort newest first
        final scans =
            raw.entries.map((e) {
              final v = Map<String, dynamic>.from(e.value as Map);
              v['id'] = e.key;
              return v;
            }).toList()..sort(
              (a, b) => ((b['scanTimestamp'] ?? 0) as int).compareTo(
                (a['scanTimestamp'] ?? 0) as int,
              ),
            );

        if (scans.isEmpty) {
          return Center(
            child: Text(
              'No scan history recorded.',
              style: TextStyle(color: subColor, fontSize: 13),
            ),
          );
        }

        // Each scan may be multi-size (detectedSizes map) or legacy single-size.
        // We expand each scan into display rows — one row per bottle size.
        // Rows share the same scan date/session indicator.
        final List<Map<String, dynamic>> displayRows = [];
        for (final scan in scans) {
          final String scanId = scan['id'];
          final int ts = (scan['scanTimestamp'] ?? 0) as int;
          final String timeStr = ts > 0
              ? DateTime.fromMillisecondsSinceEpoch(
                  ts,
                ).toLocal().toString().split('.')[0]
              : '-';
          final String status = scan['status'] ?? 'UNKNOWN';
          final bool isAck = scan['isAcknowledged'] == true;

          final detectedSizes = scan['detectedSizes'];
          final comparisons = scan['comparisons'];

          if (detectedSizes is Map && detectedSizes.isNotEmpty) {
            // ── Multi-size scan (new architecture) ──────────────────────────
            // One display row per size inside this scan. The first row in
            // each group carries the scan date; the rest show a continuation marker.
            final sizes = detectedSizes.keys.toList()..sort();
            for (int si = 0; si < sizes.length; si++) {
              final size = sizes[si].toString();
              final int physical = (detectedSizes[size] as num?)?.toInt() ?? 0;

              // System qty comes from enriched comparisons if available
              int systemQty = 0;
              int diff = 0;
              String sizeStatus = 'UNKNOWN';
              if (comparisons is Map && comparisons.containsKey(size)) {
                final c = comparisons[size] as Map;
                systemQty = (c['system'] as num?)?.toInt() ?? 0;
                diff = (c['diff'] as num?)?.toInt() ?? (physical - systemQty);
                sizeStatus = c['status']?.toString() ?? 'UNKNOWN';
              } else {
                diff = physical;
                sizeStatus = 'UNKNOWN';
              }

              displayRows.add({
                'scanId': scanId,
                'timeStr': si == 0
                    ? timeStr
                    : '', // only first row shows the date
                'isFirstInGroup': si == 0,
                'isLastInGroup': si == sizes.length - 1,
                'groupSize': sizes.length,
                'size': size,
                'physical': physical,
                'system': systemQty,
                'diff': diff,
                'sizeStatus': sizeStatus,
                'scanStatus': status,
                'isAcknowledged': isAck,
                'isMultiSize': true,
              });
            }
          } else {
            // ── Legacy single-size scan ──────────────────────────────────────
            final int detected =
                (scan['detectedQuantity'] as num?)?.toInt() ?? 0;
            final int sys = (scan['systemQuantity'] as num?)?.toInt() ?? 0;
            final int diff =
                (scan['difference'] as num?)?.toInt() ?? (detected - sys);
            final String bottleSize = scan['bottleSize']?.toString() ?? '-';

            displayRows.add({
              'scanId': scanId,
              'timeStr': timeStr,
              'isFirstInGroup': true,
              'isLastInGroup': true,
              'groupSize': 1,
              'size': bottleSize,
              'physical': detected,
              'system': sys,
              'diff': diff,
              'sizeStatus': status,
              'scanStatus': status,
              'isAcknowledged': isAck,
              'isMultiSize': false,
            });
          }
        }

        return Container(
          margin: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(AppTheme.radiusLg),
            border: Border.all(color: cardBorder),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Table header ───────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: headerBg,
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(AppTheme.radiusLg),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Text(
                        'SCAN DATE',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                          color: subColor,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        'BOTTLE SIZE',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                          color: subColor,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        'DETECTED',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                          color: subColor,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        'SYSTEM',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                          color: subColor,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        'DIFFERENCE',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                          color: subColor,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        'STATUS',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                          color: subColor,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // ── Data rows ─────────────────────────────────────────────────
              ...displayRows.asMap().entries.map((entry) {
                final idx = entry.key;
                final row = entry.value;
                final isLast = idx == displayRows.length - 1;
                final bool isFirstInGroup = row['isFirstInGroup'] as bool;
                final bool isMulti = row['isMultiSize'] as bool;

                final int physical = row['physical'] as int;
                final int system = row['system'] as int;
                final int diff = row['diff'] as int;
                final String sizeStatus = row['sizeStatus'] as String;
                final bool acked = row['isAcknowledged'] as bool;

                final bool isMismatch =
                    sizeStatus == 'MISMATCH' ||
                    sizeStatus == 'PARTIAL_MISMATCH';
                final bool isMatch = sizeStatus == 'MATCH';
                final bool isUnknown = !isMismatch && !isMatch;

                Color diffColor = isMatch
                    ? Colors.green
                    : isMismatch
                    ? Colors.redAccent
                    : subColor;

                // Top border: first row of every group gets a slightly thicker
                // separator; continuation rows within the same scan get a subtle
                // indented line to indicate grouping.
                final BorderSide topBorder = isFirstInGroup
                    ? BorderSide(
                        color: isMulti && isFirstInGroup
                            ? (isDark
                                  ? const Color(0xFF3A3020)
                                  : const Color(0xFFE8D89A))
                            : borderColor,
                        width: isMulti ? 1.5 : 1.0,
                      )
                    : BorderSide(
                        color: isDark
                            ? const Color(0xFF282520)
                            : const Color(0xFFF5F3EE),
                        width: 0.8,
                      );

                // Slight left accent for multi-size groups
                final Color? rowBg = isMulti && !isFirstInGroup
                    ? (isDark
                          ? const Color(0xFF1A1810)
                          : const Color(0xFFFFFDF7))
                    : null;

                return Container(
                  padding: EdgeInsets.only(
                    left: isMulti && !isFirstInGroup ? 28 : 16,
                    right: 16,
                    top: 11,
                    bottom: 11,
                  ),
                  decoration: BoxDecoration(
                    color: rowBg,
                    border: Border(top: topBorder),
                    borderRadius: isLast
                        ? BorderRadius.vertical(
                            bottom: Radius.circular(AppTheme.radiusLg),
                          )
                        : null,
                  ),
                  child: Row(
                    children: [
                      // Scan date — only show on first row of each group
                      Expanded(
                        flex: 3,
                        child: isFirstInGroup
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    row['timeStr'] as String,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: subColor,
                                    ),
                                  ),
                                  if (isMulti && (row['groupSize'] as int) > 1)
                                    Text(
                                      '${row['groupSize']} sizes detected',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: isDark
                                            ? AppTheme.primaryGold
                                            : const Color(0xFFB8860B),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  if (acked)
                                    Text(
                                      'Reviewed',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.green,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                ],
                              )
                            : const SizedBox.shrink(),
                      ),
                      // Bottle size
                      Expanded(
                        flex: 2,
                        child: Text(
                          row['size'] as String,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: textColor,
                          ),
                        ),
                      ),
                      // Detected
                      Expanded(
                        flex: 2,
                        child: Text(
                          '$physical',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                            color: isUnknown
                                ? subColor
                                : (isMismatch
                                      ? Colors.redAccent
                                      : Colors.green),
                          ),
                        ),
                      ),
                      // System
                      Expanded(
                        flex: 2,
                        child: Text(
                          isUnknown ? '—' : '$system',
                          style: TextStyle(fontSize: 13, color: subColor),
                        ),
                      ),
                      // Difference
                      Expanded(
                        flex: 2,
                        child: Text(
                          isUnknown
                              ? '—'
                              : diff == 0
                              ? '0'
                              : '${diff > 0 ? '+' : ''}$diff',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: diffColor,
                          ),
                        ),
                      ),
                      // Status badge
                      Expanded(
                        flex: 2,
                        child: isUnknown
                            ? Text('—', style: TextStyle(color: subColor))
                            : StatusBadge(
                                status: isMatch ? 'MATCH' : 'MISMATCH',
                              ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  void _confirmAcknowledge(String scanId, {bool thenGoToCorrections = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.panelColor(isDark),
        title: const Text(
          'Acknowledge Scan Result',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        content: Text(
          thenGoToCorrections
              ? 'Mark this scan as reviewed, then go to Stock Corrections to apply '
                    'any manual adjustment to the specific product/variant.\n\n'
                    'No inventory will be changed automatically.'
              : 'This will mark the scan as reviewed with no inventory changes.\n'
                    'The scan will move to Scan History.\n\n'
                    'Use Stock Corrections → Counting Correction if a manual adjustment is needed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: thenGoToCorrections
                ? ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryGold,
                    foregroundColor: Colors.black87,
                  )
                : null,
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await _db.verifyScan(scanId);
              } catch (error) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Failed to acknowledge scan: $error'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              if (!mounted) return;
              if (thenGoToCorrections) {
                _selectTab(2);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Scan acknowledged. Use Stock Corrections to adjust the specific product.',
                    ),
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text(
                      'Scan acknowledged. No inventory changes made.',
                    ),
                    action: SnackBarAction(
                      label: 'Stock Corrections',
                      onPressed: () => _selectTab(2),
                    ),
                  ),
                );
              }
            },
            child: Text(
              thenGoToCorrections
                  ? 'Acknowledge & Go to Corrections'
                  : 'Acknowledge',
            ),
          ),
        ],
      ),
    );
  }

  // TAB 3 — BOTTLE SIZES
  Widget _buildBottleSizes() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: CombineLatestStream.list([
        _supabaseData.productsStream,
        _supabaseData.inventoryStream,
      ]),
      builder: (context, snap) {
        final productsMap = snap.data != null && snap.data!.isNotEmpty
            ? snap.data![0]
            : _supabaseData.currentProducts;
        final inventoryMap = snap.data != null && snap.data!.length > 1
            ? snap.data![1]
            : _supabaseData.currentInventory;

        if (snap.connectionState == ConnectionState.waiting &&
            productsMap.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        // Build grouped structure: {productId → {name, variety, variants[]}}
        final List<Map<String, dynamic>> groups = [];
        productsMap.forEach((pId, pData) {
          if (pData is! Map) return;
          final List<Map<String, dynamic>> variantRows = [];
          (pData['variants'] as Map? ?? {}).forEach((vId, vData) {
            if (vData is! Map) return;
            final invV = (inventoryMap[pId] as Map? ?? {})[vId];
            final currentStock = invV is Map
                ? (invV['quantity'] ?? 0) as int
                : 0;
            variantRows.add({
              ...Map<String, dynamic>.from(vData),
              'pId': pId,
              'variety': pData['variety'] ?? '',
              'productName': pData['name'] ?? pData['variety'] ?? 'Honey',
              'currentStock': currentStock,
            });
          });
          // Sort by size label
          variantRows.sort(
            (a, b) => (a['size']?.toString() ?? '').compareTo(
              b['size']?.toString() ?? '',
            ),
          );
          if (variantRows.isNotEmpty) {
            groups.add({
              'pId': pId,
              'productName': pData['name'] ?? pData['variety'] ?? 'Honey',
              'variety': pData['variety'] ?? '',
              'variants': variantRows,
            });
          }
        });

        if (groups.isEmpty) {
          return const Center(
            child: Text(
              'No bottle sizes configured.',
              style: TextStyle(color: Colors.grey),
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          children: [
            // Header
            const Text(
              'Bottle Size Configuration',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            const Text(
              'Edit reorder levels, prices, and active status per variant. '
              'Reorder level controls when Low Stock alerts trigger.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 20),

            // One table per product group
            ...groups.map((group) {
              final variants = group['variants'] as List<Map<String, dynamic>>;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Group header
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Container(
                          width: 4,
                          height: 18,
                          decoration: BoxDecoration(
                            color: _gold,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          group['productName'],
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF111111),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${variants.length} size${variants.length == 1 ? '' : 's'}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Full-width table using Column + Row (no DataTable)
                  Card(
                    elevation: 0,
                    margin: const EdgeInsets.only(bottom: 24),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: const BorderSide(color: Color(0xFFEEEEEE)),
                    ),
                    child: Column(
                      children: [
                        // Header row
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: const BoxDecoration(
                            color: Color(0xFFF7F7F7),
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(10),
                            ),
                          ),
                          child: Row(
                            children: const [
                              Expanded(
                                flex: 3,
                                child: Text(
                                  'SIZE',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 11,
                                    color: Colors.grey,
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  'PRICE',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 11,
                                    color: Colors.grey,
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  'REORDER',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 11,
                                    color: Colors.grey,
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 3,
                                child: Text(
                                  'CURRENT STOCK',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 11,
                                    color: Colors.grey,
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  'STATUS',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 11,
                                    color: Colors.grey,
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 64,
                                child: Text(
                                  'ACTION',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 11,
                                    color: Colors.grey,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Data rows
                        ...variants.asMap().entries.map((entry) {
                          final i = entry.key;
                          final v = entry.value;
                          final darkBt =
                              Theme.of(context).brightness == Brightness.dark;
                          final isActive = v['isActive'] != false;
                          final stock = v['currentStock'] as int;
                          final reorder = (v['reorderLevel'] ?? 10) as int;
                          final isLast = i == variants.length - 1;

                          Color stockColor = Colors.green;
                          String? stockLabel;
                          if (stock == 0) {
                            stockColor = Colors.redAccent;
                            stockLabel = 'Out';
                          } else if (stock <= reorder) {
                            stockColor = const Color(0xFFD97706);
                            stockLabel = 'Low';
                          }

                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 13,
                            ),
                            decoration: BoxDecoration(
                              color: isActive
                                  ? null
                                  : (darkBt
                                        ? const Color(0xFF2A2620)
                                        : const Color(0xFFF2F0EC)),
                              border: Border(
                                top: const BorderSide(color: Color(0xFFEEEEEE)),
                                bottom: isLast
                                    ? BorderSide.none
                                    : BorderSide.none,
                              ),
                              borderRadius: isLast
                                  ? const BorderRadius.vertical(
                                      bottom: Radius.circular(10),
                                    )
                                  : null,
                            ),
                            child: Row(
                              children: [
                                // SIZE
                                Expanded(
                                  flex: 3,
                                  child: Text(
                                    v['size']?.toString() ?? '-',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                      color: isActive
                                          ? const Color(0xFF111111)
                                          : Colors.grey,
                                    ),
                                  ),
                                ),
                                // PRICE
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    v['price'] != null ? '₱${v['price']}' : '—',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                // REORDER
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    '${v['reorderLevel'] ?? 10}',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                // CURRENT STOCK
                                Expanded(
                                  flex: 3,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        '$stock',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 13,
                                          color: stockColor,
                                        ),
                                      ),
                                      if (stockLabel != null) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: stock == 0
                                                ? (darkBt
                                                      ? AppTheme.badgeRedBgDark
                                                      : AppTheme
                                                            .badgeRedBgLight)
                                                : (darkBt
                                                      ? AppTheme
                                                            .iconBadgeAmberDark
                                                      : AppTheme
                                                            .iconBadgeAmberLight),
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          child: Text(
                                            stockLabel,
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w800,
                                              color: stockColor,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                // STATUS
                                Expanded(
                                  flex: 2,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        isActive
                                            ? Icons.check_circle_outline_rounded
                                            : Icons.block_rounded,
                                        size: 14,
                                        color: isActive
                                            ? Colors.green
                                            : Colors.grey,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        isActive ? 'Active' : 'Inactive',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: isActive
                                              ? Colors.green
                                              : Colors.grey,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // ACTION
                                SizedBox(
                                  width: 64,
                                  child: TextButton.icon(
                                    onPressed: () => _showEditVariantConfig(v),
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      minimumSize: Size.zero,
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    icon: const Icon(
                                      Icons.edit_outlined,
                                      size: 13,
                                      color: _gold,
                                    ),
                                    label: const Text(
                                      'Edit',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: _gold,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ],
              );
            }),
          ],
        );
      },
    );
  }

  void _showEditVariantConfig(Map<String, dynamic> variant) {
    int reorder = (variant['reorderLevel'] ?? 10) as int;
    bool isActive = variant['isActive'] != false;
    int price = (variant['price'] ?? 0) as int;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text(
            'Edit — ${variant['variety']} ${variant['size'] ?? ''}',
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Size read-only
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F7F7),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.lock_outline_rounded,
                        size: 14,
                        color: Colors.grey,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Size: ${variant['size'] ?? '-'}  (read-only)',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Price
                const Text(
                  'Price (₱)',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  initialValue: price > 0 ? '$price' : '',
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'e.g. 260',
                    prefixText: '₱ ',
                  ),
                  onChanged: (v) {
                    final p = int.tryParse(v.trim());
                    if (p != null && p >= 0) price = p;
                  },
                ),
                const SizedBox(height: 16),

                // Reorder Level
                const Text(
                  'Reorder Level',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  initialValue: '$reorder',
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'e.g. 10',
                    helperText:
                        'Low Stock alert triggers when stock ≤ this value.',
                  ),
                  onChanged: (v) {
                    final p = int.tryParse(v.trim());
                    if (p != null && p >= 0) reorder = p;
                  },
                ),
                const SizedBox(height: 16),

                // Active toggle
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Active',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    'Inactive variants are hidden from KPIs, forecasting, and stock corrections.',
                    style: TextStyle(fontSize: 11),
                  ),
                  value: isActive,
                  activeThumbColor: _gold,
                  onChanged: (v) => setDialog(() => isActive = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _gold),
              onPressed: () async {
                try {
                  await _db.updateVariantConfig(
                    productId: variant['pId'],
                    variantId: variant['id'] ?? '',
                    reorderLevel: reorder,
                    isActive: isActive,
                    price: price > 0 ? price : null,
                  );
                } catch (error) {
                  if (!mounted || !ctx.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to save variant settings: $error'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      '${variant['variety']} ${variant['size']} saved.',
                    ),
                  ),
                );
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

// ADJUSTMENTS TAB
class _AdjustmentsTab extends StatefulWidget {
  final DatabaseService db;
  final AuthSession session;
  const _AdjustmentsTab({required this.db, required this.session});

  @override
  State<_AdjustmentsTab> createState() => _AdjustmentsTabState();
}

class _AdjustmentsTabState extends State<_AdjustmentsTab>
    with AutomaticKeepAliveClientMixin {
  // Keep the form alive across tab switches so partially-filled
  // data is not lost when the user navigates away and comes back.
  @override
  bool get wantKeepAlive => true;

  static const _increaseReasons = [
    'Counting Correction',
    'Returned Product',
    'Other',
  ];
  static const _decreaseReasons = [
    'Damaged / Broken',
    'Quality Rejection',
    'Counting Correction',
    'Other',
  ];

  String _direction = 'Increase';
  String? _selectedProductId;
  String? _selectedVariantId;
  String? _reason;
  final _qtyCtrl = TextEditingController(text: '1');
  final _notesCtrl = TextEditingController();
  bool _isLoading = false;

  List<String> get _reasons =>
      _direction == 'Increase' ? _increaseReasons : _decreaseReasons;

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // required by AutomaticKeepAliveClientMixin
    return StreamBuilder<List<dynamic>>(
      stream: CombineLatestStream.list([
        SupabaseDataService().productsStream,
        SupabaseDataService().inventoryStream,
      ]),
      builder: (context, snap) {
        final prodMap =
            snap.data != null && snap.data!.isNotEmpty && snap.data![0] is Map
            ? snap.data![0] as Map<String, dynamic>
            : SupabaseDataService().currentProducts;
        final invMap =
            snap.data != null && snap.data!.length > 1 && snap.data![1] is Map
            ? snap.data![1] as Map<String, dynamic>
            : SupabaseDataService().currentInventory;
        // Firebase inventory_movements removed — Supabase FutureBuilder used in historyCard below.
        final List<Map<String, dynamic>> variants = [];
        prodMap.forEach((pId, pData) {
          if (pData is! Map) return;
          (pData['variants'] as Map? ?? {}).forEach((vId, vData) {
            if (vData is! Map || vData['isActive'] == false) return;
            final pInv = (invMap[pId] as Map? ?? {})[vId] as Map? ?? {};
            variants.add({
              'productId': pId,
              'variantId': vId,
              'variantUuid': vData['uuid']?.toString(),
              'label':
                  '${pData['variety'] ?? pData['name'] ?? 'Honey'} (${vData['size'] ?? '-'})',
              'currentQty': (pInv['quantity'] ?? 0) as int,
              'reorderLevel': (vData['reorderLevel'] ?? 10) as int,
            });
          });
        });
        _selectedProductId ??= variants.isNotEmpty
            ? variants.first['productId']
            : null;
        _selectedVariantId ??= variants.isNotEmpty
            ? variants.first['variantId']
            : null;
        _reason ??= _reasons.first;
        final sv = variants.firstWhere(
          (v) =>
              v['productId'] == _selectedProductId &&
              v['variantId'] == _selectedVariantId,
          orElse: () =>
              variants.isNotEmpty ? variants.first : <String, dynamic>{},
        );
        final int currentQty = (sv['currentQty'] ?? 0) as int;
        final int reorderLevel = (sv['reorderLevel'] ?? 10) as int;
        final String stockStatus = currentQty == 0
            ? 'Out of Stock'
            : currentQty <= reorderLevel
            ? 'Low Stock'
            : 'In Stock';
        // recentAdj is displayed in historyCard below via FutureBuilder from Supabase.
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(bottom: 20),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF9F9F9),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFEEEEEE)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.info_outline_rounded,
                      size: 16,
                      color: Colors.grey,
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Stock Corrections are for exceptions only.\nNormal stock changes happen automatically through Production (stock +) and Orders (stock −).',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth > 700;

                  // Form card (left on wide, top on narrow)
                  final formCard = Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(color: Color(0xFFEEEEEE)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Manual Stock Adjustment',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Use for corrections and exceptions only.',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            'Adjustment Type',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              _DirChip(
                                label: 'Increase',
                                icon: Icons.add_rounded,
                                active: _direction == 'Increase',
                                color: Colors.green,
                                onTap: () => setState(() {
                                  _direction = 'Increase';
                                  _reason = _increaseReasons.first;
                                }),
                              ),
                              const SizedBox(width: 10),
                              _DirChip(
                                label: 'Decrease',
                                icon: Icons.remove_rounded,
                                active: _direction == 'Decrease',
                                color: Colors.red,
                                onTap: () => setState(() {
                                  _direction = 'Decrease';
                                  _reason = _decreaseReasons.first;
                                }),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          const Text(
                            'Product',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          variants.isEmpty
                              ? const Text(
                                  'No active variants.',
                                  style: TextStyle(color: Colors.grey),
                                )
                              : DropdownButtonFormField<String>(
                                  isExpanded: true,
                                  value:
                                      '${_selectedProductId ?? ''}:${_selectedVariantId ?? ''}',
                                  decoration: const InputDecoration(
                                    border: OutlineInputBorder(),
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 12,
                                    ),
                                  ),
                                  items: variants
                                      .map(
                                        (v) => DropdownMenuItem(
                                          value:
                                              '${v['productId']}:${v['variantId']}',
                                          child: Text(
                                            '${v['label']}  (Stock: ${v['currentQty']})',
                                            style: const TextStyle(
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (val) {
                                    if (val == null) return;
                                    final p = val.split(':');
                                    setState(() {
                                      _selectedProductId = p[0];
                                      _selectedVariantId = p[1];
                                    });
                                  },
                                ),
                          const SizedBox(height: 12),
                          if (variants.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF9F9F9),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.inventory_2_outlined,
                                    size: 15,
                                    color: Colors.grey,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Current: $currentQty bottle${currentQty == 1 ? '' : 's'}',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    'Reorder: $reorderLevel',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  StatusBadge(status: stockStatus),
                                ],
                              ),
                            ),
                          const SizedBox(height: 16),
                          const Text(
                            'Quantity',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _qtyCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              hintText: 'e.g. 5',
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Reason',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            isExpanded: true,
                            value: _reason,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                            ),
                            items: _reasons
                                .map(
                                  (r) => DropdownMenuItem(
                                    value: r,
                                    child: Text(r),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) => setState(() => _reason = v),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Notes (optional)',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _notesCtrl,
                            maxLines: 2,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              hintText: 'e.g. Cracked during storage',
                            ),
                          ),
                          const SizedBox(height: 24),
                          Row(
                            children: [
                              TextButton(
                                onPressed: () {
                                  _qtyCtrl.text = '1';
                                  _notesCtrl.clear();
                                  setState(() => _reason = _reasons.first);
                                },
                                child: const Text(
                                  'Reset',
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ),
                              const Spacer(),
                              if (RoleCapabilities.forRole(
                                widget.session.role,
                              ).canAdjustStock)
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _direction == 'Increase'
                                        ? Colors.green
                                        : Colors.redAccent,
                                    foregroundColor: Colors.white,
                                  ),
                                  onPressed: _isLoading || variants.isEmpty
                                      ? null
                                      : () => _submitAdjustment(
                                          currentQty: currentQty,
                                          variantUuid: sv['variantUuid']
                                              ?.toString(),
                                        ),
                                  icon: Icon(
                                    _direction == 'Increase'
                                        ? Icons.add_rounded
                                        : Icons.remove_rounded,
                                    size: 16,
                                  ),
                                  label: _isLoading
                                      ? const SizedBox(
                                          height: 16,
                                          width: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Text(
                                          'Submit Adjustment',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );

                  // History card — Supabase inventory movements (right on wide, bottom on narrow)
                  final historyCard = Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(color: Color(0xFFEEEEEE)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Recent Corrections',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 12),
                          FutureBuilder<List<Map<String, dynamic>>>(
                            future: SupabaseDataService()
                                .fetchRecentManualAdjustments(),
                            builder: (context, adjSnap) {
                              if (adjSnap.connectionState ==
                                  ConnectionState.waiting) {
                                return const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 20),
                                  child: Center(
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                );
                              }
                              final adjList = adjSnap.data ?? [];
                              if (adjList.isEmpty) {
                                return const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 20),
                                  child: Center(
                                    child: Text(
                                      'No corrections yet.',
                                      style: TextStyle(
                                        color: Colors.grey,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                );
                              }
                              return Column(
                                mainAxisSize: MainAxisSize.min,
                                children: adjList.take(15).map((m) {
                                  final change =
                                      (m['quantity_change'] ?? 0) as int;
                                  final isPos = change > 0;
                                  final prevQty =
                                      m['prev_quantity']?.toString() ?? '0';
                                  final newQty =
                                      m['new_quantity']?.toString() ?? '0';
                                  final reason = m['reason']?.toString() ?? '-';
                                  final notes = m['notes']?.toString();
                                  final darkAdj =
                                      Theme.of(context).brightness ==
                                      Brightness.dark;
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          width: 28,
                                          height: 28,
                                          decoration: BoxDecoration(
                                            color: isPos
                                                ? (darkAdj
                                                      ? AppTheme
                                                            .iconBadgeGreenDark
                                                      : AppTheme
                                                            .iconBadgeGreenLight)
                                                : (darkAdj
                                                      ? AppTheme.badgeRedBgDark
                                                      : AppTheme
                                                            .badgeRedBgLight),
                                            shape: BoxShape.circle,
                                          ),
                                          child: Icon(
                                            isPos
                                                ? Icons.add_rounded
                                                : Icons.remove_rounded,
                                            size: 14,
                                            color: isPos
                                                ? Colors.green
                                                : Colors.red,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                '${isPos ? '+' : ''}$change  ($prevQty → $newQty)',
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w700,
                                                  color: isPos
                                                      ? Colors.green
                                                      : Colors.red,
                                                ),
                                              ),
                                              Text(
                                                reason,
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey,
                                                ),
                                              ),
                                              if (notes != null &&
                                                  notes.isNotEmpty)
                                                Text(
                                                  notes,
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.grey,
                                                  ),
                                                ),
                                            ],
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

                  // Wide: side-by-side  |  Narrow: stacked
                  if (isWide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 2, child: formCard),
                        const SizedBox(width: 20),
                        Expanded(flex: 1, child: historyCard),
                      ],
                    );
                  } else {
                    return Column(
                      children: [
                        formCard,
                        const SizedBox(height: 16),
                        historyCard,
                      ],
                    );
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _submitAdjustment({
    required int currentQty,
    String? variantUuid,
  }) async {
    final qty = int.tryParse(_qtyCtrl.text.trim());
    if (qty == null || qty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Quantity must be a positive number.')),
      );
      return;
    }
    if (_selectedProductId == null || _selectedVariantId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please select a product.')));
      return;
    }
    if (_direction == 'Decrease' && qty > currentQty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Cannot decrease by $qty — only $currentQty in stock.'),
        ),
      );
      return;
    }
    if (!RoleCapabilities.forRole(widget.session.role).canAdjustStock) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Access restricted: Owner is monitoring-focused. Stock corrections require Co-Admin role.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isLoading = true);
    try {
      final change = _direction == 'Increase' ? qty : -qty;
      bool success = false;
      if (variantUuid != null && variantUuid.isNotEmpty) {
        try {
          success = await SupabaseDataService().adjustInventory(
            variantUuid: variantUuid,
            change: change,
            reason: _reason ?? 'Other',
            notes: _notesCtrl.text.trim().isEmpty
                ? null
                : _notesCtrl.text.trim(),
          );
        } catch (rpcErr) {
          debugPrint('[InventoryPage] Supabase adjustInventory RPC: $rpcErr');
        }
      }

      if (!success) {
        try {
          success = await widget.db.addManualAdjustment(
            productId: _selectedProductId!,
            variantId: _selectedVariantId!,
            change: change,
            reason: _reason ?? 'Other',
            notes: _notesCtrl.text.trim().isEmpty
                ? null
                : _notesCtrl.text.trim(),
            adminName: widget.session.name,
          );
        } catch (firebaseError) {
          debugPrint(
            '[InventoryPage] Firebase adjustment fallback failed: $firebaseError',
          );
        }
      }

      if (!mounted) return;
      if (success) {
        final newQty = currentQty + change;
        _notesCtrl.clear();
        await SupabaseDataService().refreshAll();
        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Adjustment recorded. Stock: $currentQty → ${newQty < 0 ? 0 : newQty} bottles.',
            ),
          ),
        );
      } else {
        if (!mounted) return;
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Adjustment failed. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}

// SHARED WIDGETS
class _KpiCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  final bool warn;
  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.warn = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final subColor = isDark
        ? AppTheme.subtitleDark(isDark)
        : AppTheme.subtitleLight(isDark);
    final textColor = isDark ? AppTheme.textDark : AppTheme.textLight;
    final cardBorder = isDark ? AppTheme.borderDark : AppTheme.borderLight;
    final isGold = color == AppTheme.primaryGold || color == AppTheme.warning;
    final isRed = color == AppTheme.error;
    final isGreen = color == AppTheme.accentGreen;
    final iconBg = isDark
        ? (isGold
              ? AppTheme.iconBadgeGoldDark
              : isRed
              ? AppTheme.badgeRedBgDark
              : isGreen
              ? AppTheme.iconBadgeGreenDark
              : AppTheme.iconBadgeGoldDark)
        : (isGold
              ? AppTheme.iconBadgeGoldLight
              : isRed
              ? AppTheme.badgeRedBgLight
              : isGreen
              ? AppTheme.iconBadgeGreenLight
              : AppTheme.iconBadgeGoldLight);
    final warnBorder = isDark
        ? (isGold
              ? AppTheme.badgeGoldBorderDark
              : isRed
              ? AppTheme.badgeRedBorderDark
              : AppTheme.badgeGoldBorderDark)
        : (isGold
              ? AppTheme.badgeGoldBorderLight
              : isRed
              ? AppTheme.badgeRedBorderLight
              : AppTheme.badgeGoldBorderLight);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: warn ? warnBorder : cardBorder),
        boxShadow: [
          BoxShadow(
            color: isDark ? const Color(0xFF0B0A08) : const Color(0xFFEFE6D2),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            label,
            style: TextStyle(
              color: subColor,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: warn ? color : textColor,
              letterSpacing: -0.3,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _CountBox extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  final bool showSign;
  const _CountBox({
    required this.label,
    required this.value,
    required this.color,
    this.showSign = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final subColor = isDark
        ? AppTheme.subtitleDark(isDark)
        : AppTheme.subtitleLight(isDark);
    final display = showSign && value > 0 ? '+$value' : '$value';
    final isGreen = color == Colors.green || color == AppTheme.accentGreen;
    final isGrey = color == Colors.grey;
    final isDeepOrange = color == Colors.deepOrange;
    final isRed =
        color == Colors.red ||
        color == Colors.redAccent ||
        color == AppTheme.error;
    final bgColor = isDark
        ? AppTheme.surfaceDark
        : (isGreen
              ? AppTheme.iconBadgeGreenLight
              : isGrey
              ? const Color(0xFFF2F0EC)
              : isDeepOrange
              ? const Color(0xFFFBEEE1)
              : isRed
              ? AppTheme.badgeRedBgLight
              : AppTheme.iconBadgeGoldLight);
    final borderColor = isDark
        ? (isGreen
              ? AppTheme.badgeGreenBorderDark
              : isGrey
              ? AppTheme.borderDarkAlt
              : isDeepOrange
              ? const Color(0xFF6B4520)
              : isRed
              ? AppTheme.badgeRedBorderDark
              : AppTheme.badgeGoldBorderDark)
        : (isGreen
              ? AppTheme.badgeGreenBorderLight
              : isGrey
              ? AppTheme.borderLightAlt
              : isDeepOrange
              ? const Color(0xFFF0C7A2)
              : isRed
              ? AppTheme.badgeRedBorderLight
              : AppTheme.badgeGoldBorderLight);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          border: Border.all(color: borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              display,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
            Text('bottles', style: TextStyle(fontSize: 10, color: subColor)),
          ],
        ),
      ),
    );
  }
}

class _ToggleChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _ToggleChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final subColor = isDark
        ? AppTheme.subtitleDark(isDark)
        : AppTheme.subtitleLight(isDark);
    final borderColor = isDark
        ? AppTheme.borderDarkAlt
        : AppTheme.borderLightAlt;
    final chipBg = active
        ? (isDark ? AppTheme.iconBadgeGoldDark : AppTheme.iconBadgeGoldLight)
        : (isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
        decoration: BoxDecoration(
          color: chipBg,
          borderRadius: BorderRadius.circular(AppTheme.radiusPill),
          border: Border.all(
            color: active ? AppTheme.primaryGold : borderColor,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: active ? AppTheme.primaryGold : subColor,
          ),
        ),
      ),
    );
  }
}

class _DirChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final Color color;
  final VoidCallback onTap;
  const _DirChip({
    required this.label,
    required this.icon,
    required this.active,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = isDark
        ? AppTheme.borderDarkAlt
        : AppTheme.borderLightAlt;
    final isGreen = color == Colors.green || color == AppTheme.accentGreen;
    final isRed =
        color == Colors.red ||
        color == Colors.redAccent ||
        color == AppTheme.error;
    final dirChipBg = active
        ? (isDark
              ? (isGreen
                    ? AppTheme.iconBadgeGreenDark
                    : isRed
                    ? AppTheme.badgeRedBgDark
                    : AppTheme.iconBadgeGoldDark)
              : (isGreen
                    ? AppTheme.iconBadgeGreenLight
                    : isRed
                    ? AppTheme.badgeRedBgLight
                    : AppTheme.iconBadgeGoldLight))
        : (isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        decoration: BoxDecoration(
          color: dirChipBg,
          borderRadius: BorderRadius.circular(AppTheme.radiusPill),
          border: Border.all(color: active ? color : borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: active ? color : Colors.grey),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: active ? color : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
