import 'package:flutter/material.dart';
import 'package:rxdart/rxdart.dart';
import '../services/auth_service.dart';
import '../services/supabase_data_service.dart';
import '../core/theme/app_theme.dart';
import '../core/permissions/admin_capabilities.dart';

class ProductsPage extends StatefulWidget {
  final AuthSession session;
  const ProductsPage({super.key, required this.session});

  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage> {
  final _supabaseData = SupabaseDataService();
  String _searchQuery = '';
  bool _showArchived = false;
  bool _isLoading = true;
  String? _loadError;

  bool get _canManageCatalog =>
      RoleCapabilities.forRole(widget.session.role).canManageCatalog;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    try {
      await Future.wait([
        _supabaseData.fetchProducts(),
        _supabaseData.fetchInventory(),
      ]);
    } catch (e) {
      debugPrint('[ProductsPage] Error loading Supabase products: $e');
      if (mounted) {
        setState(() => _loadError = 'Could not load catalog from Supabase: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // ── #5 helper: parse leading number from size string for sorting ──────────
  // e.g. "250g" → 250, "1kg" → 1000, "500ml" → 500, "Large" → 9999
  int _sizeToGrams(String size) {
    final lower = size.toLowerCase().trim();
    final match = RegExp(r'^(\d+(?:\.\d+)?)\s*(kg|g|ml|l)?').firstMatch(lower);
    if (match == null) return 9999;
    final num = double.tryParse(match.group(1) ?? '0') ?? 0;
    final unit = match.group(2) ?? 'g';
    if (unit == 'kg' || unit == 'l') return (num * 1000).round();
    return num.round();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: AppTheme.pageBackground(isDark),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppTheme.adminPagePadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            if (_loadError != null) ...[
              const SizedBox(height: AppTheme.adminSectionGap),
              _buildLoadErrorBanner(),
            ],
            const SizedBox(height: AppTheme.adminSectionGap),
            _buildControls(),
            const SizedBox(height: AppTheme.adminSectionGap),
            _buildProductList(),
          ],
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = AppTheme.textPrimary(isDark);
    final subColor = AppTheme.textSecondary(isDark);
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 600;
        final title = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Products',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: textColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Manage honey varieties and product variants',
              style: TextStyle(color: subColor, fontSize: 13),
            ),
          ],
        );
        final actions = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Refresh Products',
              onPressed: _loadData,
            ),
            const SizedBox(width: 8),
            if (_canManageCatalog)
              ElevatedButton.icon(
                onPressed: _showAddProductDialog,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add Product'),
              ),
          ],
        );

        if (isNarrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              title,
              const SizedBox(height: 14),
              actions,
            ],
          );
        }

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: title),
            const SizedBox(width: 16),
            actions,
          ],
        );
      },
    );
  }

  Widget _buildLoadErrorBanner() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.mutedPanel(isDark),
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: AppTheme.error),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: AppTheme.error),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _loadError!,
              style: TextStyle(color: AppTheme.textPrimary(isDark)),
            ),
          ),
          TextButton.icon(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  // ── Search / filter bar ───────────────────────────────────────────────────
  Widget _buildControls() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = AppTheme.textPrimary(isDark);
    final subColor = AppTheme.textSecondary(isDark);
    return Row(
      children: [
        Expanded(
          child: TextField(
            onChanged: (v) => setState(() => _searchQuery = v),
            style: TextStyle(
              fontSize: 13,
              color: textColor,
              fontWeight: FontWeight.w600,
            ),
            decoration: AppTheme.searchInputDecoration(
              isDark,
              hintText: 'Search products...',
            ),
          ),
        ),
        const SizedBox(width: 16),
        Row(
          children: [
            Text(
              'Show Archived',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: subColor,
              ),
            ),
            Switch(
              value: _showArchived,
              onChanged: (v) => setState(() => _showArchived = v),
              activeThumbColor: AppTheme.primaryGold,
            ),
          ],
        ),
      ],
    );
  }

  // ── Product list ──────────────────────────────────────────────────────────
  Widget _buildProductList() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: CombineLatestStream.list([
        _supabaseData.productsStream,
        _supabaseData.inventoryStream,
      ]),
      builder: (context, snapshot) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final textColor = isDark ? AppTheme.textDark : AppTheme.textLight;
        final subColor = isDark
            ? AppTheme.subtitleDark(isDark)
            : AppTheme.subtitleLight(isDark);

        final productsMap = snapshot.data?[0] ?? _supabaseData.currentProducts;
        final invMap = snapshot.data?[1] ?? _supabaseData.currentInventory;

        if (_isLoading && productsMap.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        if (productsMap.isEmpty) {
          return Center(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
              margin: const EdgeInsets.symmetric(horizontal: 32),
              decoration: BoxDecoration(
                color: AppTheme.mutedPanel(isDark),
                borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                border: Border.all(color: AppTheme.panelBorder(isDark)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.hive_outlined,
                    size: 52,
                    color: AppTheme.primaryGold,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No products yet',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Click "Add Product" to create your first honey variety.',
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
        }

        final productsList = productsMap.entries.map((e) {
          final val = Map<String, dynamic>.from(e.value as Map);
          val['id'] = e.key;
          return val;
        }).toList();

        final filtered = productsList.where((p) {
          final matchesArchive = (p['isActive'] != false) == !_showArchived;
          final q = _searchQuery.toLowerCase();
          final matchesSearch =
              q.isEmpty ||
              p['name'].toString().toLowerCase().contains(q) ||
              p['variety'].toString().toLowerCase().contains(q);
          return matchesArchive && matchesSearch;
        }).toList();

        if (filtered.isEmpty) {
          return Center(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
              margin: const EdgeInsets.symmetric(horizontal: 32),
              decoration: BoxDecoration(
                color: AppTheme.mutedPanel(isDark),
                borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                border: Border.all(color: AppTheme.panelBorder(isDark)),
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
                    'No matching products',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Try adjusting your search or toggle archived filter.',
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
        }

        return Column(
          children: filtered.map((p) => _buildProductCard(p, invMap)).toList(),
        );
      },
    );
  }

  // ── Product card ──────────────────────────────────────────────────────────
  Widget _buildProductCard(
    Map<String, dynamic> product,
    Map<String, dynamic> invMap,
  ) {
    final variants = product['variants'] as Map? ?? {};
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = AppTheme.textPrimary(isDark);
    final subColor = AppTheme.textSecondary(isDark);
    final headerBg = AppTheme.tableHeader(isDark);
    final rowBorder = isDark ? AppTheme.borderDark : AppTheme.borderLight;

    // Build variant list with live inventory qty attached, then sort by size
    // (#5 — ascending by numeric gram/ml value).
    final variantList =
        variants.entries.map((e) {
          final v = Map<String, dynamic>.from(e.value as Map);
          v['id'] = e.key;
          final invVariant =
              ((invMap[product['id']] as Map?) ?? {})[e.key] as Map?;
          v['_inventoryQty'] = (invVariant?['quantity'] as num?)?.toInt() ?? 0;
          return v;
        }).toList()..sort(
          (a, b) => _sizeToGrams(
            a['size'] ?? '',
          ).compareTo(_sizeToGrams(b['size'] ?? '')),
        );

    // #3 — build summary: "N variants · M out of stock"
    final totalVariants = variantList.length;
    final outOfStockCount = variantList.where((v) {
      final isActive = v['isActive'] != false;
      final pq = (v['productQuantity'] as num?)?.toInt() ?? 0;
      return isActive && pq == 0;
    }).length;
    final summaryParts = <String>[
      '$totalVariants variant${totalVariants == 1 ? '' : 's'}',
    ];
    if (outOfStockCount > 0) summaryParts.add('$outOfStockCount out of stock');
    final variantSummary = summaryParts.join(' · ');
    final summaryColor = outOfStockCount > 0 ? AppTheme.error : subColor;

    return Container(
      margin: const EdgeInsets.only(bottom: 28),
      decoration: AppTheme.adminPanelDecoration(isDark),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Product header ─────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              product['name'] ?? '',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: textColor,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: isDark ? AppTheme.iconBadgeGoldDark : AppTheme.iconBadgeGoldLight,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: AppTheme.primaryGold.withAlpha(80)),
                            ),
                            child: Text(
                              '#PRD-${product['id'].toString().replaceAll('-', '').substring(0, 6).toUpperCase()}',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.primaryGold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      // Variety + optional description
                      Text(
                        '${product['variety'] ?? ''}',
                        style: TextStyle(color: subColor, fontSize: 13),
                      ),
                      if ((product['description'] ?? '').toString().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            product['description'],
                            style: TextStyle(
                              color: subColor,
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      // #3 — variant summary line
                      const SizedBox(height: 4),
                      Text(
                        variantSummary,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: summaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_canManageCatalog)
                  Row(
                    children: [
                      IconButton(
                        onPressed: () =>
                            _showAddVariantDialog(product['uuid'].toString()),
                        icon: Icon(
                          Icons.add_circle_outline,
                          size: 20,
                          color: AppTheme.primaryGold,
                        ),
                        tooltip: 'Add Variant',
                      ),
                      IconButton(
                        onPressed: () => _showEditProductDialog(product),
                        icon: Icon(
                          Icons.edit_outlined,
                          size: 20,
                          color: subColor,
                        ),
                        tooltip: 'Edit Product',
                      ),
                      IconButton(
                        onPressed: () =>
                            _confirmArchiveProduct(product, variantList),
                        icon: Icon(
                          product['isActive'] == false
                              ? Icons.unarchive_outlined
                              : Icons.archive_outlined,
                          size: 20,
                          color: AppTheme.error,
                        ),
                        tooltip: product['isActive'] == false
                            ? 'Restore'
                            : 'Archive',
                      ),
                    ],
                  ),
              ],
            ),
          ),

          // ── Variants table ─────────────────────────────────────────────
          if (variantList.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(
                  'No variants added yet',
                  style: TextStyle(color: subColor, fontSize: 13),
                ),
              ),
            )
          else
            Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: headerBg,
                    border: Border(top: BorderSide(color: rowBorder)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text(
                          'SIZE / VARIANT',
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
                          'PRICE',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 11.5,
                            color: subColor,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                      // Product Quantity — customer-facing available units
                      Expanded(
                        flex: 2,
                        child: Text(
                          'PRODUCT QTY',
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
                          'INVENTORY QTY',
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
                      // #2 — actions column, narrower now (icon + chip)
                      SizedBox(
                        width: 148,
                        child: Text(
                          'ACTIONS',
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

                // Table rows
                ...variantList.asMap().entries.map((entry) {
                  final i = entry.key;
                  final v = entry.value;
                  final isLast = i == variantList.length - 1;

                  final int productQty =
                      (v['productQuantity'] as num?)?.toInt() ?? 0;
                  final int inventoryQty = v['_inventoryQty'] as int? ?? 0;
                  final bool isActive = v['isActive'] != false;

                  // Availability badge driven by productQuantity
                  final String availability = !isActive
                      ? 'Inactive'
                      : productQty == 0
                      ? 'Out of Stock'
                      : 'Available';
                  final Color availColor = !isActive
                      ? subColor
                      : productQty == 0
                      ? AppTheme.error
                      : AppTheme.accentGreen;

                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 13,
                    ),
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: rowBorder)),
                      borderRadius: isLast
                          ? BorderRadius.vertical(
                              bottom: Radius.circular(AppTheme.radiusLg),
                            )
                          : null,
                    ),
                    child: Row(
                      children: [
                        // Size & Short Variant ID
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                v['size'] ?? 'N/A',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  color: textColor,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '#VAR-${v['id'].toString().replaceAll('-', '').substring(0, 4).toUpperCase()}',
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
                        // Price
                        Expanded(
                          flex: 2,
                          child: Text(
                            '₱${v['price'] ?? 0}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                              color: AppTheme.accentGreen,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            '$productQty',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                              color: productQty == 0
                                  ? AppTheme.error
                                  : textColor,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            '$inventoryQty',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                              color: inventoryQty == 0 ? subColor : textColor,
                            ),
                          ),
                        ),
                        // Status badge
                        Expanded(
                          flex: 2,
                          child: _buildStatusBadge(availability, availColor),
                        ),
                        SizedBox(
                          width: 148,
                          child: _canManageCatalog
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    OutlinedButton.icon(
                                      onPressed: () => _showAddDialog(
                                        variantUuid: v['uuid'].toString(),
                                        size: v['size'] ?? '',
                                        productName: product['name'] ?? '',
                                        currentProductQty: productQty,
                                        currentInventoryQty: inventoryQty,
                                      ),
                                      icon: const Icon(
                                        Icons.add_circle_outline_rounded,
                                        size: 13,
                                      ),
                                      label: const Text(
                                        'Add',
                                        style: TextStyle(fontSize: 11.5),
                                      ),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: AppTheme.primaryGold,
                                        side: const BorderSide(
                                          color: AppTheme.primaryGold,
                                          width: 1.2,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        minimumSize: Size.zero,
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    IconButton(
                                      onPressed: () => _showEditVariantDialog(
                                        v['uuid'].toString(),
                                        v,
                                      ),
                                      icon: Icon(
                                        Icons.edit_outlined,
                                        size: 17,
                                        color: subColor,
                                      ),
                                      tooltip: 'Edit Variant',
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                    ),
                                  ],
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),

          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // ── Status badge ──────────────────────────────────────────────────────────
  Widget _buildStatusBadge(String label, Color color) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bgColor;
    if (color == AppTheme.accentGreen) {
      bgColor = isDark
          ? AppTheme.iconBadgeGreenDark
          : AppTheme.iconBadgeGreenLight;
    } else if (color == AppTheme.error) {
      bgColor = isDark ? AppTheme.badgeRedBgDark : AppTheme.badgeRedBgLight;
    } else {
      bgColor = isDark ? const Color(0xFF2A2823) : const Color(0xFFF3EEE2);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  // ── DIALOGS ───────────────────────────────────────────────────────────────

  // Add Product — #7: includes Description field
  void _showAddProductDialog() {
    final nameCtrl = TextEditingController();
    final varietyCtrl = TextEditingController();
    final categoryCtrl = TextEditingController();
    final descCtrl = TextEditingController();
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
          'Add Honey Variety',
          style: TextStyle(
            color: AppTheme.textPrimary(isDark),
            fontWeight: FontWeight.w900,
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Display Name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: varietyCtrl,
                decoration: const InputDecoration(labelText: 'Variety'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: categoryCtrl,
                decoration: const InputDecoration(labelText: 'Category'),
              ),
              const SizedBox(height: 12),
              // #7 — Description field
              TextField(
                controller: descCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                  alignLabelWithHint: true,
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
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) {
                _showProductsError('Product name is required.');
                return;
              }
              try {
                await _supabaseData.createCatalogProduct(
                  name: name,
                  variety: varietyCtrl.text,
                  category: categoryCtrl.text,
                  description: descCtrl.text,
                );
                if (ctx.mounted) Navigator.pop(ctx);
              } catch (error) {
                _showProductsError('Could not create product: $error');
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // Edit Product — #7: includes Description field; does NOT touch inventory
  void _showEditProductDialog(Map<String, dynamic> p) {
    final nameCtrl = TextEditingController(text: p['name'] ?? '');
    final varietyCtrl = TextEditingController(text: p['variety'] ?? '');
    final descCtrl = TextEditingController(text: p['description'] ?? '');
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
          'Edit Honey Variety',
          style: TextStyle(
            color: AppTheme.textPrimary(isDark),
            fontWeight: FontWeight.w900,
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Display Name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: varietyCtrl,
                decoration: const InputDecoration(labelText: 'Variety'),
              ),
              const SizedBox(height: 12),
              // #7 — Description field
              TextField(
                controller: descCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                  alignLabelWithHint: true,
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
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) {
                _showProductsError('Product name is required.');
                return;
              }
              try {
                await _supabaseData.updateCatalogProduct(
                  productUuid: p['uuid'].toString(),
                  name: name,
                  variety: varietyCtrl.text,
                  description: descCtrl.text,
                );
                if (ctx.mounted) Navigator.pop(ctx);
              } catch (error) {
                _showProductsError('Could not update product: $error');
              }
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  // Add Variant — #4: productQuantity always starts at 0; no editable field
  void _showAddVariantDialog(String pId) {
    final sizeCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    final reorderCtrl = TextEditingController(text: '10');
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
          'Add Size Variant',
          style: TextStyle(
            color: AppTheme.textPrimary(isDark),
            fontWeight: FontWeight.w900,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: sizeCtrl,
              decoration: const InputDecoration(
                labelText: 'Bottle Size (e.g. 250g)',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: priceCtrl,
              decoration: const InputDecoration(labelText: 'Price (₱)'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reorderCtrl,
              decoration: const InputDecoration(
                labelText: 'Inventory Reorder Level',
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 14),
            // #4 — locked to 0; point admin to Add
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDark
                    ? AppTheme.backgroundDarkAlt
                    : AppTheme.backgroundLightAlt,
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                border: Border.all(
                  color: isDark ? AppTheme.borderDarkAlt : AppTheme.borderLight,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 14,
                    color: isDark
                        ? AppTheme.subtitleDark(isDark)
                        : AppTheme.subtitleLight(isDark),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Product Quantity starts at 0.\n'
                      'Use Add after adding inventory stock '
                      'to make units available for ordering.',
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.45,
                        color: isDark
                            ? AppTheme.subtitleDark(isDark)
                            : AppTheme.subtitleLight(isDark),
                      ),
                    ),
                  ),
                ],
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
            onPressed: () async {
              final price = int.tryParse(priceCtrl.text.trim()) ?? 0;
              final reorder = int.tryParse(reorderCtrl.text.trim()) ?? 10;
              if (sizeCtrl.text.trim().isEmpty || price <= 0 || reorder < 0) {
                _showProductsError(
                  'Enter a size, a price greater than zero, and a non-negative reorder level.',
                );
                return;
              }
              try {
                await _supabaseData.createCatalogVariant(
                  productUuid: pId,
                  size: sizeCtrl.text,
                  price: price,
                  reorderLevel: reorder,
                );
                if (ctx.mounted) Navigator.pop(ctx);
              } catch (error) {
                _showProductsError('Could not add variant: $error');
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  // Edit Variant — price, reorderLevel, isActive only; productQuantity read-only
  void _showEditVariantDialog(String variantUuid, Map<String, dynamic> v) {
    final priceCtrl = TextEditingController(text: (v['price'] ?? 0).toString());
    final reorderCtrl = TextEditingController(
      text: (v['reorderLevel'] ?? 10).toString(),
    );
    bool active = v['isActive'] != false;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setDialogState) => AlertDialog(
          backgroundColor: AppTheme.panelColor(isDark),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusLg),
            side: BorderSide(
              color: isDark ? AppTheme.borderDarkAlt : AppTheme.borderLight,
            ),
          ),
          title: Text(
            'Edit ${v['size']} Variant',
            style: TextStyle(
              color: AppTheme.textPrimary(isDark),
              fontWeight: FontWeight.w900,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Read-only product qty info banner
              Container(
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppTheme.backgroundDarkAlt
                      : AppTheme.backgroundLightAlt,
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                  border: Border.all(
                    color: isDark
                        ? AppTheme.borderDarkAlt
                        : AppTheme.borderLight,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 14,
                      color: isDark
                          ? AppTheme.subtitleDark(isDark)
                          : AppTheme.subtitleLight(isDark),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Product Quantity: ${(v['productQuantity'] as num?)?.toInt() ?? 0} units  •  '
                        'Use "Add" to increase it.',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: isDark
                              ? AppTheme.subtitleDark(isDark)
                              : AppTheme.subtitleLight(isDark),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              TextField(
                controller: priceCtrl,
                decoration: const InputDecoration(labelText: 'Price (₱)'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reorderCtrl,
                decoration: const InputDecoration(
                  labelText: 'Inventory Reorder Level',
                ),
                keyboardType: TextInputType.number,
              ),
              SwitchListTile(
                title: const Text('Active'),
                value: active,
                onChanged: (val) => setDialogState(() => active = val),
                activeThumbColor: AppTheme.primaryGold,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final price = int.tryParse(priceCtrl.text.trim()) ?? 0;
                final reorderLevel =
                    int.tryParse(reorderCtrl.text.trim()) ?? -1;
                if (price <= 0 || reorderLevel < 0) {
                  _showProductsError(
                    'Price must be greater than zero and reorder level cannot be negative.',
                  );
                  return;
                }
                try {
                  await _supabaseData.updateCatalogVariant(
                    variantUuid: variantUuid,
                    price: price,
                    reorderLevel: reorderLevel,
                    isActive: active,
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                } catch (error) {
                  _showProductsError('Could not update variant: $error');
                }
              },
              child: const Text('Update'),
            ),
          ],
        ),
      ),
    );
  }

  // #6 — Archive confirmation dialog
  // Warns if product has variants with productQuantity > 0 but does not block.
  void _confirmArchiveProduct(
    Map<String, dynamic> product,
    List<Map<String, dynamic>> variantList,
  ) {
    final isArchiving = product['isActive'] != false;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Calculate total exposed product quantity across all variants
    final totalProductQty = variantList.fold<int>(
      0,
      (sum, v) => sum + ((v['productQuantity'] as num?)?.toInt() ?? 0),
    );

    if (!isArchiving) {
      _setProductActive(product['uuid'].toString(), true);
      return;
    }

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
        title: Row(
          children: [
            const Icon(Icons.archive_outlined, color: AppTheme.error, size: 22),
            const SizedBox(width: 10),
            Text(
              'Archive ${product['name'] ?? 'Product'}?',
              style: TextStyle(
                color: AppTheme.textPrimary(isDark),
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Archiving will hide this product from the active catalog '
              'and make it unavailable for new orders.',
              style: TextStyle(
                fontSize: 13,
                color: AppTheme.textSecondary(isDark),
                height: 1.5,
              ),
            ),
            // Warning if units are still exposed
            if (totalProductQty > 0) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppTheme.iconBadgeAmberDark
                      : AppTheme.iconBadgeAmberLight,
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                  border: Border.all(
                    color: isDark
                        ? AppTheme.badgeGoldBorderDark
                        : AppTheme.badgeGoldBorderLight,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 16,
                      color: AppTheme.warning,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This product currently has $totalProductQty unit${totalProductQty == 1 ? '' : 's'} '
                        'available in Product Quantity. Archiving will hide it '
                        'from the catalog. The quantity is preserved and will '
                        'be visible again if you restore the product.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.warning,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
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
                await _supabaseData.setCatalogProductActive(
                  productUuid: product['uuid'].toString(),
                  isActive: false,
                );
                if (ctx.mounted) Navigator.pop(ctx);
              } catch (error) {
                _showProductsError('Could not archive product: $error');
              }
            },
            child: const Text(
              'Archive',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _setProductActive(String productUuid, bool isActive) async {
    try {
      await _supabaseData.setCatalogProductActive(
        productUuid: productUuid,
        isActive: isActive,
      );
    } catch (error) {
      _showProductsError('Could not restore product: $error');
    }
  }

  void _showProductsError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppTheme.error),
    );
  }

  // ── Add Product Quantity dialog ─────────────────────────────────────
  void _showAddDialog({
    required String variantUuid,
    required String size,
    required String productName,
    required int currentProductQty,
    required int currentInventoryQty,
  }) {
    final qtyCtrl = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    bool isLoading = false;
    String? errorMsg;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setDialogState) {
          final requested = int.tryParse(qtyCtrl.text.trim()) ?? 0;
          final projectedProductQty = currentProductQty + requested;
          final projectedInventoryQty = currentInventoryQty - requested;

          return AlertDialog(
            backgroundColor: AppTheme.panelColor(isDark),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusLg),
              side: BorderSide(
                color: isDark ? AppTheme.borderDarkAlt : AppTheme.borderLight,
              ),
            ),
            title: Row(
              children: [
                Icon(
                  Icons.add_circle_outline_rounded,
                  color: AppTheme.primaryGold,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Add Product Quantity',
                    style: TextStyle(
                      color: AppTheme.textPrimary(isDark),
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Product info panel (shows BOTH quantities — this is the
                  // only place INVENTORY QTY is visible per #1)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppTheme.backgroundDarkAlt
                          : AppTheme.backgroundLightAlt,
                      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                      border: Border.all(
                        color: isDark
                            ? AppTheme.borderDarkAlt
                            : AppTheme.borderLight,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$productName — $size',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                            color: AppTheme.textPrimary(isDark),
                          ),
                        ),
                        const SizedBox(height: 10),
                        _replenishInfoRow(
                          isDark: isDark,
                          label: 'Product Quantity',
                          value: '$currentProductQty units',
                          sublabel: '(customer-facing available stock)',
                          color: currentProductQty == 0
                              ? AppTheme.error
                              : AppTheme.accentGreen,
                        ),
                        const SizedBox(height: 6),
                        _replenishInfoRow(
                          isDark: isDark,
                          label: 'Inventory Quantity',
                          value: '$currentInventoryQty units',
                          sublabel: '(available to transfer)',
                          color: AppTheme.textPrimary(isDark),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Quantity input
                  Text(
                    'Quantity to Add',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary(isDark),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: qtyCtrl,
                    keyboardType: TextInputType.number,
                    autofocus: true,
                    onChanged: (_) => setDialogState(() => errorMsg = null),
                    decoration: InputDecoration(
                      hintText: 'e.g. 20',
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
                      errorText: errorMsg,
                      suffixText: 'units',
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Live before → after preview
                  if (requested > 0) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF0E2714)
                            : const Color(0xFFF0FBF3),
                        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                        border: Border.all(
                          color: isDark
                              ? AppTheme.badgeGreenBorderDark
                              : AppTheme.badgeGreenBorderLight,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'After Addment:',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textSecondary(isDark),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: _arrowRow(
                                  isDark: isDark,
                                  label: 'Product QTY',
                                  from: currentProductQty,
                                  to: projectedProductQty,
                                  positive: true,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _arrowRow(
                                  isDark: isDark,
                                  label: 'Inventory',
                                  from: currentInventoryQty,
                                  to: projectedInventoryQty,
                                  positive: false,
                                ),
                              ),
                            ],
                          ),
                          if (projectedInventoryQty < 0)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                '⚠ Requested quantity exceeds available inventory.',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.error,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isLoading ? null : () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryGold,
                  foregroundColor: Colors.black87,
                ),
                onPressed: isLoading
                    ? null
                    : () async {
                        final qty = int.tryParse(qtyCtrl.text.trim());
                        if (qty == null || qty <= 0) {
                          setDialogState(
                            () => errorMsg = 'Enter a quantity greater than 0.',
                          );
                          return;
                        }
                        if (qty > currentInventoryQty) {
                          setDialogState(
                            () => errorMsg =
                                'Not enough inventory. Available: $currentInventoryQty units.',
                          );
                          return;
                        }

                        setDialogState(() => isLoading = true);

                        // Capture messenger before async gap
                        final scaffold = ScaffoldMessenger.of(context);

                        try {
                          await _supabaseData.replenishProductQuantity(
                            variantUuid: variantUuid,
                            quantity: qty,
                            adminUid: widget.session.uid,
                          );
                          if (!ctx.mounted) return;
                          setDialogState(() => isLoading = false);
                          Navigator.pop(ctx);
                          scaffold.showSnackBar(
                            SnackBar(
                              content: Text(
                                '✓ Added $qty units for $productName $size. '
                                'Product QTY: $currentProductQty → ${currentProductQty + qty}.',
                              ),
                              backgroundColor: AppTheme.success,
                            ),
                          );
                        } catch (error) {
                          if (!ctx.mounted) return;
                          setDialogState(() {
                            isLoading = false;
                            errorMsg = error.toString();
                          });
                        }
                      },
                icon: isLoading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black87,
                        ),
                      )
                    : const Icon(Icons.check_rounded, size: 16),
                label: const Text(
                  'Confirm Addment',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── Add dialog helpers ──────────────────────────────────────────────

  Widget _replenishInfoRow({
    required bool isDark,
    required String label,
    required String value,
    required String sublabel,
    required Color color,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 140,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.textSecondary(isDark),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
              ),
              Text(
                sublabel,
                style: TextStyle(
                  fontSize: 10.5,
                  color: AppTheme.textSecondary(isDark),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _arrowRow({
    required bool isDark,
    required String label,
    required int from,
    required int to,
    required bool positive,
  }) {
    final Color arrowColor = positive ? AppTheme.accentGreen : AppTheme.warning;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 10, color: AppTheme.textSecondary(isDark)),
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            Text(
              '$from',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary(isDark),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Icon(
                Icons.arrow_forward_rounded,
                size: 13,
                color: arrowColor,
              ),
            ),
            Text(
              '$to',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: arrowColor,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
