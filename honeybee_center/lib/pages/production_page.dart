import 'package:flutter/material.dart';
import 'package:rxdart/rxdart.dart';
import 'package:honeybee_center/services/auth_service.dart';
import 'package:honeybee_center/services/supabase_data_service.dart';
import 'package:honeybee_center/widgets/status_badge.dart';
import 'package:honeybee_center/core/theme/app_theme.dart';
import 'package:honeybee_center/core/permissions/admin_capabilities.dart';

class ProductionPage extends StatefulWidget {
  final AuthSession session;
  const ProductionPage({super.key, required this.session});

  @override
  State<ProductionPage> createState() => _ProductionPageState();
}

class _ProductionPageState extends State<ProductionPage> {
  final _supabaseData = SupabaseDataService();
  bool _showBundles = false;
  String _searchQuery = '';
  String _statusFilter = 'All';

  bool get _canOperate =>
      RoleCapabilities.forRole(widget.session.role).canRunProduction;

  @override
  void initState() {
    super.initState();
    _supabaseData.fetchProductionBatches().catchError((e) {
      debugPrint('[ProductionPage] Error fetching batches: $e');
      return <Map<String, dynamic>>[];
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? AppTheme.backgroundDark : AppTheme.backgroundLight,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          _buildViewToggle(),
          _buildSearchAndFilter(),
          Expanded(child: _showBundles ? _buildBundleProductionList() : _buildStandardProductionList()),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppTheme.textDark : AppTheme.textLight;
    final subColor = isDark ? AppTheme.subtitleDark(isDark) : AppTheme.subtitleLight(isDark);
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 750;
          final titleCol = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              Text(
                'Production',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Track standard bottling processes and bulk customer order production',
                style: TextStyle(color: subColor, fontSize: 13),
              ),
            ],
          );
          final actionButtons = _canOperate
              ? Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _showResetTestDataDialog(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.error,
                        side: const BorderSide(color: AppTheme.error),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                        ),
                      ),
                      icon: const Icon(Icons.restore_rounded, size: 18),
                      label: const Text(
                        'Reset Test Data',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _showAddStandardBatchDialog(),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text(
                        '+ Add Production',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _showAddBulkProductionDialog(),
                      icon: const Icon(Icons.inventory_outlined, size: 18),
                      label: const Text(
                        '+ Bulk Production',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                )
              : const SizedBox.shrink();

          if (isNarrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                titleCol,
                const SizedBox(height: 16),
                actionButtons,
              ],
            );
          }

          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: titleCol),
              const SizedBox(width: 16),
              actionButtons,
            ],
          );
        },
      ),
    );
  }

  Widget _buildViewToggle() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final subColor = isDark ? AppTheme.subtitleDark(isDark) : AppTheme.subtitleLight(isDark);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 8),
      child: Row(
        children: [
          ChoiceChip(
            label: const Text('Standard Production'),
            selected: !_showBundles,
            onSelected: (selected) => setState(() => _showBundles = false),
            selectedColor: isDark ? AppTheme.iconBadgeGoldDark : AppTheme.iconBadgeGoldLight,
            labelStyle: TextStyle(fontWeight: FontWeight.w700, color: !_showBundles ? AppTheme.primaryGold : subColor),
          ),
          const SizedBox(width: 12),
          ChoiceChip(
            label: const Text('Bulk Production'),
            selected: _showBundles,
            onSelected: (selected) => setState(() => _showBundles = true),
            selectedColor: isDark ? AppTheme.iconBadgeGoldDark : AppTheme.iconBadgeGoldLight,
            labelStyle: TextStyle(fontWeight: FontWeight.w700, color: _showBundles ? AppTheme.primaryGold : subColor),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndFilter() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppTheme.textDark : AppTheme.textLight;
    final subColor = isDark ? AppTheme.subtitleDark(isDark) : AppTheme.subtitleLight(isDark);
    final fillColor = isDark ? AppTheme.surfaceDark : Colors.white;
    final borderColor = isDark ? AppTheme.borderDark : AppTheme.borderLight;

    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 4, 32, 12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              onChanged: (v) => setState(() => _searchQuery = v),
              style: TextStyle(fontSize: 13, color: textColor),
              decoration: InputDecoration(
                hintText: 'Search by product name, bottle size, or batch ID...',
                hintStyle: TextStyle(fontSize: 12, color: subColor),
                prefixIcon: Icon(Icons.search_rounded, size: 18, color: subColor),
                filled: true,
                fillColor: fillColor,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppTheme.radiusMd), borderSide: BorderSide(color: borderColor)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppTheme.radiusMd), borderSide: BorderSide(color: borderColor)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppTheme.radiusMd), borderSide: const BorderSide(color: AppTheme.primaryGold, width: 1.6)),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(color: fillColor, borderRadius: BorderRadius.circular(AppTheme.radiusMd), border: Border.all(color: borderColor)),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _statusFilter,
                style: TextStyle(fontSize: 13, color: textColor, fontWeight: FontWeight.w600),
                dropdownColor: fillColor,
                items: ['All', 'Planned', 'In Progress', 'Completed', 'Preparing', 'Ready for Production'].map((s) => DropdownMenuItem(value: s, child: Text(s, style: TextStyle(color: textColor)))).toList(),
                onChanged: (v) => setState(() => _statusFilter = v ?? 'All'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStandardProductionList() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _supabaseData.productionBatchesStream,
      builder: (context, snapshot) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final textColor = isDark ? AppTheme.textDark : AppTheme.textLight;
        final subColor = isDark ? AppTheme.subtitleDark(isDark) : AppTheme.subtitleLight(isDark);
        final headerBg = isDark ? AppTheme.backgroundDarkAlt : AppTheme.backgroundLightAlt;
        final cardBg = isDark ? AppTheme.surfaceDark : Colors.white;
        final cardBorder = isDark ? AppTheme.borderDark : AppTheme.borderLight;
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final list = (snapshot.data ?? _supabaseData.currentProductionBatches)
            .where((r) => r['isBundle'] != true && r['isArchived'] != true)
            .toList()
            ..sort((a, b) => (b['createdAt'] ?? '').compareTo(a['createdAt'] ?? ''));

        final filteredList = list.where((r) {
          final q = _searchQuery.toLowerCase().trim();
          final idStr = r['id'].toString().toLowerCase();
          final nameStr = (r['productName'] ?? '').toString().toLowerCase();
          final sizeStr = (r['bottleSize'] ?? '').toString().toLowerCase();
          final matchesSearch = q.isEmpty || idStr.contains(q) || nameStr.contains(q) || sizeStr.contains(q);
          final statusStr = (r['status'] ?? 'Planned').toString();
          final matchesStatus = _statusFilter == 'All' || statusStr.toLowerCase() == _statusFilter.toLowerCase();
          return matchesSearch && matchesStatus;
        }).toList();

        if (filteredList.isEmpty) {
          return Center(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
              margin: const EdgeInsets.symmetric(horizontal: 32),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.backgroundDarkAlt : const Color(0xFFFFFBF1),
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.inventory_2_outlined, size: 40, color: AppTheme.primaryGold),
                  const SizedBox(height: 14),
                  Text('No matching production batches', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: textColor)),
                  const SizedBox(height: 6),
                  Text('Try adjusting your search query or status filter.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: subColor, height: 1.4)),
                ],
              ),
            ),
          );
        }

        return Container(
          margin: const EdgeInsets.fromLTRB(32, 8, 32, 24),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(AppTheme.radiusLg),
            border: Border.all(color: cardBorder),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(headerBg),
              horizontalMargin: 24,
              columns: [
                DataColumn(label: Text('BATCH ID', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11.5, color: subColor, letterSpacing: 0.3))),
                DataColumn(label: Text('PRODUCT / SIZE', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11.5, color: subColor, letterSpacing: 0.3))),
                DataColumn(label: Text('TARGET', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11.5, color: subColor, letterSpacing: 0.3))),
                DataColumn(label: Text('COMPLETED', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11.5, color: subColor, letterSpacing: 0.3))),
                DataColumn(label: Text('REMAINING', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11.5, color: subColor, letterSpacing: 0.3))),
                DataColumn(label: Text('PROGRESS', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11.5, color: subColor, letterSpacing: 0.3))),
                DataColumn(label: Text('TARGET DATE', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11.5, color: subColor, letterSpacing: 0.3))),
                DataColumn(label: Text('STATUS', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11.5, color: subColor, letterSpacing: 0.3))),
                DataColumn(label: Text('ACTIONS', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11.5, color: subColor, letterSpacing: 0.3))),
              ],
              rows: filteredList.map((r) {
                final int target = r['quantityTarget'] ?? r['quantityProduced'] ?? 100;
                final int completed = r['completedQuantity'] ?? 0;
                final int remaining = (target - completed).clamp(0, target);
                final double progress = target > 0 ? (completed / target) : 0.0;
                final String targetDate = r['targetCompletionDate'] ?? r['productionDate'] ?? '-';
                final scheduleStatus = _getScheduleIndicator(targetDate, r['status']);
                final shortBatchId = '#BCH-${r['id'].toString().replaceAll('-', '').substring(0, r['id'].toString().replaceAll('-', '').length >= 6 ? 6 : r['id'].toString().length).toUpperCase()}';

                return DataRow(cells: [
                  DataCell(Text(shortBatchId, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
                  DataCell(ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 140),
                    child: Text('${r['productName'] ?? 'Product'} (${r['bottleSize'] ?? '-'})', style: const TextStyle(fontWeight: FontWeight.w700)),
                  )),
                  DataCell(Text('$target')),
                  // Interactive Quick-Edit Completed Cell [ 40 ✎ ] — Co-Admin only
                  DataCell(
                    _canOperate
                        ? Tooltip(
                            message: 'Update completed quantity',
                            child: InkWell(
                              onTap: () => _showUpdateProgressDialog(r['id'], 'Standard', target, completed),
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: isDark ? AppTheme.iconBadgeGreenDark : AppTheme.iconBadgeGreenLight,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: isDark ? AppTheme.badgeGreenBorderDark : AppTheme.badgeGreenBorderLight),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text('$completed', style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.green, fontSize: 13)),
                                    const SizedBox(width: 6),
                                    const Icon(Icons.edit_rounded, size: 14, color: Color(0xFFD9A441)),
                                  ],
                                ),
                              ),
                            ),
                          )
                        : Text('$completed', style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.green, fontSize: 13)),
                  ),
                  DataCell(Text('$remaining')),
                  DataCell(
                    SizedBox(
                      width: 120,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          LinearProgressIndicator(value: progress, color: const Color(0xFFD9A441), backgroundColor: Colors.grey.shade200),
                          const SizedBox(height: 4),
                          Text('${(progress * 100).toStringAsFixed(1)}%', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                        ],
                      ),
                    ),
                  ),
                  DataCell(ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 130),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(targetDate, style: const TextStyle(fontSize: 12)),
                        Text(scheduleStatus, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: _scheduleColor(scheduleStatus))),
                      ],
                    ),
                  )),
                  DataCell(StatusBadge(status: r['status'] ?? 'Planned')),
                  DataCell(ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 200),
                    child: _canOperate
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (r['status'] == 'Planned')
                                TextButton.icon(
                                  onPressed: () async {
                                    await _supabaseData.updateProductionBatchStatus(batchId: r['id'], newStatus: 'In Progress');
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Batch started! Status changed to In Progress.'), backgroundColor: Colors.green),
                                    );
                                  },
                                  icon: const Icon(Icons.play_arrow_rounded, size: 16, color: AppTheme.primaryGold),
                                  label: const Text('Start', style: TextStyle(color: AppTheme.primaryGold, fontWeight: FontWeight.bold)),
                                ),
                              TextButton(
                                onPressed: () => _showUpdateProgressDialog(r['id'], 'Standard', target, completed),
                                child: const Text('Update Qty', style: TextStyle(color: Color(0xFFD9A441), fontWeight: FontWeight.bold)),
                              ),
                              if (r['status'] != 'Completed')
                                TextButton(
                                  onPressed: () => _showCompleteBatchDialog(r),
                                  child: const Text('Finish', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                                ),
                              IconButton(
                                icon: const Icon(Icons.archive_outlined, size: 18, color: Colors.grey),
                                tooltip: 'Archive Batch',
                                onPressed: () => _showArchiveConfirmationDialog(r['id'], r['productName'] ?? 'Batch'),
                              ),
                            ],
                          )
                        : const Text('View only', style: TextStyle(fontSize: 11, color: Colors.grey, fontStyle: FontStyle.italic)),
                  )),
                ]);
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBundleProductionList() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _supabaseData.productionBatchesStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final list = (snapshot.data ?? _supabaseData.currentProductionBatches)
            .where((r) => r['isBundle'] == true && r['isArchived'] != true)
            .toList()
            ..sort((a, b) => (b['createdAt'] ?? '').compareTo(a['createdAt'] ?? ''));

        final filteredList = list.where((r) {
          final q = _searchQuery.toLowerCase().trim();
          final idStr = r['id'].toString().toLowerCase();
          final customerStr = (r['customerName'] ?? '').toString().toLowerCase();
          final orderStr = (r['orderId'] ?? '').toString().toLowerCase();
          final matchesSearch = q.isEmpty || idStr.contains(q) || customerStr.contains(q) || orderStr.contains(q);
          final statusStr = (r['status'] ?? 'Preparing').toString();
          final matchesStatus = _statusFilter == 'All' || statusStr.toLowerCase() == _statusFilter.toLowerCase();
          return matchesSearch && matchesStatus;
        }).toList();

        if (filteredList.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(48.0),
              child: Text('No matching bulk production orders found.', style: TextStyle(color: Colors.grey)),
            ),
          );
        }

        return Card(
          margin: const EdgeInsets.all(32),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(const Color(0xFFF7F7F7)),
              horizontalMargin: 32,
              columns: const [
                DataColumn(label: Text('BULK ID', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
                DataColumn(label: Text('ORDER ID', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
                DataColumn(label: Text('CUSTOMER', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
                DataColumn(label: Text('TOTAL TARGET', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
                DataColumn(label: Text('COMPLETED', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
                DataColumn(label: Text('PROGRESS', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
                DataColumn(label: Text('TARGET DATE', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
                DataColumn(label: Text('STATUS', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
                DataColumn(label: Text('ACTIONS', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
              ],
              rows: filteredList.map((r) {
                final int target = r['quantityTarget'] ?? r['quantityProduced'] ?? 100;
                final int completed = r['quantityCompleted'] ?? 0;
                final double progress = target > 0 ? (completed / target) : 0.0;
                final String targetDate = r['targetCompletionDate'] ?? '-';
                final scheduleStatus = _getScheduleIndicator(targetDate, r['status']);
                final shortBulkId = '#BLK-${r['id'].toString().replaceAll('-', '').substring(0, r['id'].toString().replaceAll('-', '').length >= 6 ? 6 : r['id'].toString().length).toUpperCase()}';
                final shortOrderId = (r['orderId'] ?? '').toString().isEmpty
                    ? '-'
                    : '#ORD-${r['orderId'].toString().replaceAll('-', '').substring(0, r['orderId'].toString().replaceAll('-', '').length >= 6 ? 6 : r['orderId'].toString().length).toUpperCase()}';

                return DataRow(cells: [
                  DataCell(Text(shortBulkId, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
                  DataCell(Text(shortOrderId)),
                  DataCell(ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 130),
                    child: Text(r['customerName'] ?? 'N/A', style: const TextStyle(fontWeight: FontWeight.w600)),
                  )),
                  DataCell(Text('$target')),
                  DataCell(Text('$completed', style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.green))),
                  DataCell(
                    SizedBox(
                      width: 110,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          LinearProgressIndicator(value: progress, color: const Color(0xFFD9A441), backgroundColor: Colors.grey.shade200),
                          const SizedBox(height: 4),
                          Text('${(progress * 100).toStringAsFixed(1)}%', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                        ],
                      ),
                    ),
                  ),
                  DataCell(ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 130),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(targetDate, style: const TextStyle(fontSize: 12)),
                        Text(scheduleStatus, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: _scheduleColor(scheduleStatus))),
                      ],
                    ),
                  )),
                  DataCell(StatusBadge(status: r['status'] ?? 'Preparing')),
                  DataCell(ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 160),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          onPressed: () => _showBulkDetailsDialog(r),
                          child: const Text('View Details', style: TextStyle(color: Color(0xFFD9A441), fontWeight: FontWeight.bold)),
                        ),
                        if (_canOperate)
                          IconButton(
                            icon: const Icon(Icons.archive_outlined, size: 18, color: Colors.grey),
                            tooltip: 'Archive Bulk Plan',
                            onPressed: () => _showArchiveConfirmationDialog(r['id'], r['bundleName'] ?? 'Bulk Production'),
                          ),
                      ],
                    ),
                  )),
                ]);
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  void _showArchiveConfirmationDialog(String batchId, String name) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Archive Production Batch', style: TextStyle(fontWeight: FontWeight.w900)),
        content: Text('Are you sure you want to archive "$name"? It will be hidden from Active Production but preserved in history.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () async {
              await _supabaseData.archiveProductionBatch(batchId);
              if (!mounted) return;
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Production batch archived successfully.')),
              );
            },
            child: const Text('Archive'),
          ),
        ],
      ),
    );
  }

  void _showCompleteBatchDialog(Map<String, dynamic> batch) {
    final int target = batch['quantityTarget'] ?? batch['quantityProduced'] ?? 100;
    final int currentCompleted = batch['completedQuantity'] ?? 0;
    final ctrl = TextEditingController(text: currentCompleted > 0 ? '$currentCompleted' : '$target');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Complete Production Batch', style: TextStyle(fontWeight: FontWeight.w900)),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Product: ${batch['productName']} (${batch['bottleSize']})', style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('Planned Target: $target units', style: const TextStyle(color: Colors.grey, fontSize: 13)),
              const SizedBox(height: 16),
              TextField(
                controller: ctrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Final Completed Quantity',
                  hintText: 'Enter final produced quantity',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              const Text('This quantity will be added directly to the active inventory stock.', style: TextStyle(color: Colors.grey, fontSize: 12)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () async {
              final finalQty = int.tryParse(ctrl.text.trim()) ?? target;
              if (finalQty <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Completed quantity must be greater than 0.'), backgroundColor: Colors.redAccent),
                );
                return;
              }
              await _supabaseData.updateProductionBatchStatus(batchId: batch['id'], newStatus: 'Partially Completed', qtyCompleted: finalQty);
              await _supabaseData.completeProductionBatch(batch['id']);
              if (!context.mounted) return;
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Batch completed! Added $finalQty units to inventory.'), backgroundColor: Colors.green),
              );
            },
            child: const Text('Confirm Completion', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  String _getScheduleIndicator(String dateStr, String? status) {
    if (status == 'Completed') return 'Completed';
    final targetDate = DateTime.tryParse(dateStr);
    if (targetDate == null) return 'On Schedule';
    final now = DateTime.now();
    final diff = targetDate.difference(now).inDays;
    if (diff < 0) return 'Overdue';
    if (diff <= 3) return 'Due Soon';
    return 'On Schedule';
  }

  Color _scheduleColor(String indicator) {
    switch (indicator) {
      case 'Completed':
        return Colors.green;
      case 'Overdue':
        return Colors.red;
      case 'Due Soon':
        return Colors.orange;
      default:
        return Colors.blue;
    }
  }

  void _showAddStandardBatchDialog() {
    showDialog(
      context: context,
      builder: (context) => const _AddStandardBatchDialog(),
    );
  }

  void _showAddBulkProductionDialog() {
    showDialog(
      context: context,
      builder: (context) => const _AddBulkProductionDialog(),
    );
  }

  void _showResetTestDataDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset Test Production & Inventory Data', style: TextStyle(fontWeight: FontWeight.w900)),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('This action will reset:'),
            SizedBox(height: 8),
            Text('• Reset all inventory stock levels to 0 bottles', style: TextStyle(fontWeight: FontWeight.w600)),
            Text('• Clear test production batch records', style: TextStyle(fontWeight: FontWeight.w600)),
            Text('• Clear test inventory movement logs', style: TextStyle(fontWeight: FontWeight.w600)),
            SizedBox(height: 12),
            Text('Real product definitions, user accounts, and orders will NOT be deleted.', style: TextStyle(color: Colors.grey, fontSize: 13)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              // Reset Test Data is disabled — not ported to Supabase per Phase 6 decision.
              // This button is kept for reference but performs no destructive operation.
              if (!mounted) return;
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Reset Test Data is disabled on Supabase. Use the database console to manage test data.'),
                  backgroundColor: Colors.orange,
                ),
              );
            },
            child: const Text('Reset Test Data', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showUpdateProgressDialog(String batchId, String type, int target, int current) {
    final ctrl = TextEditingController(text: '$current');
    int liveCompleted = current;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          int remaining = (target - liveCompleted).clamp(0, target);
          double progress = target > 0 ? (liveCompleted / target) : 0.0;

          return AlertDialog(
            title: const Text('Update Production Progress', style: TextStyle(fontWeight: FontWeight.w900)),
            content: SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Target Quantity:     $target', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: ctrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Completed Quantity',
                      hintText: 'Enter completed qty',
                    ),
                    onChanged: (val) {
                      final parsed = int.tryParse(val.trim());
                      if (parsed != null) {
                        setDialogState(() {
                          liveCompleted = parsed;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  Text('Remaining:           $remaining', style: const TextStyle(color: Colors.grey, fontSize: 13)),
                  const SizedBox(height: 4),
                  Text('Progress:            ${(progress * 100).toStringAsFixed(1)}%', style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFFD9A441), fontSize: 13)),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD9A441)),
                onPressed: () async {
                  final parsed = int.tryParse(ctrl.text.trim());
                  if (parsed == null || parsed < 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Invalid quantity! Must be 0 or greater.'), backgroundColor: Colors.redAccent),
                    );
                    return;
                  }

                  await _supabaseData.updateProductionBatchStatus(batchId: batchId, newStatus: 'In Progress', qtyCompleted: parsed);
                  if (!context.mounted) return;
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Production progress updated successfully.')),
                  );
                },
                child: const Text('Save', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showBulkDetailsDialog(Map<String, dynamic> bulk) {
    final items = Map<String, dynamic>.from(bulk['items'] ?? {});
    final requirements = Map<String, dynamic>.from(bulk['requirements'] ?? {});

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Bulk Production #${bulk['id'].toString().substring(0, 8).toUpperCase()}', style: const TextStyle(fontWeight: FontWeight.w900)),
        content: SizedBox(
          width: 600,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Customer: ${bulk['customerName'] ?? 'N/A'}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                Text('Order ID: #${bulk['orderId'] ?? ''}', style: const TextStyle(color: Colors.grey, fontSize: 13)),
                const Divider(height: 24),
                const Text('Production Items', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                const SizedBox(height: 8),
                ...items.entries.map((e) {
                  final itm = Map<String, dynamic>.from(e.value);
                  int target = itm['targetQuantity'] ?? 0;
                  int completed = itm['completedQuantity'] ?? 0;
                  double prog = target > 0 ? (completed / target) : 0.0;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6.0),
                    child: Row(
                      children: [
                        Expanded(flex: 2, child: Text('${itm['productName']} (${itm['bottleSize']})', style: const TextStyle(fontWeight: FontWeight.w600))),
                        Expanded(flex: 1, child: Text('Target: $target')),
                        Expanded(flex: 1, child: Text('Done: $completed', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold))),
                        Expanded(flex: 1, child: Text('${(prog * 100).toStringAsFixed(0)}%')),
                      ],
                    ),
                  );
                }),
                const Divider(height: 24),
                const Text('Supply Requirements & Shortage Check', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                const SizedBox(height: 8),
                ...requirements.entries.map((e) {
                  final req = Map<String, dynamic>.from(e.value);
                  int required = req['required'] ?? 0;
                  int available = req['available'] ?? 0;
                  int shortage = req['shortage'] ?? 0;
                  bool isInsuff = shortage > 0;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6.0),
                    child: Row(
                      children: [
                        Expanded(flex: 2, child: Text(req['supplyName'] ?? 'Bottle', style: const TextStyle(fontWeight: FontWeight.w600))),
                        Expanded(flex: 1, child: Text('Req: $required')),
                        Expanded(flex: 1, child: Text('Avail: $available')),
                        Expanded(flex: 1, child: Text('Short: $shortage', style: TextStyle(color: isInsuff ? Colors.red : Colors.green, fontWeight: FontWeight.bold))),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
        actions: [
          if (_canOperate && bulk['status'] == 'Preparing')
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () => _showRestockShortageDialog(bulk),
              icon: const Icon(Icons.add_shopping_cart, size: 16),
              label: const Text('Restock Shortage'),
            ),
          if (_canOperate && bulk['status'] == 'Ready for Production')
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD9A441)),
              onPressed: () async {
                await _supabaseData.updateProductionBatchStatus(batchId: bulk['id'], newStatus: 'In Progress');
                if (!context.mounted) return;
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Production started! Status is now In Progress.')));
              },
              child: const Text('Start Production'),
            ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showRestockShortageDialog(Map<String, dynamic> bulk) {
    final requirements = Map<String, dynamic>.from(bulk['requirements'] ?? {});
    final stockCtrl = TextEditingController(text: '100');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restock Production Supplies', style: TextStyle(fontWeight: FontWeight.w900)),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Record received empty bottles/supplies to resolve shortages:', style: TextStyle(color: Colors.grey, fontSize: 13)),
              const SizedBox(height: 16),
              ...requirements.entries.map((e) {
                final req = Map<String, dynamic>.from(e.value);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Text('• ${req['supplyName']}: Shortage of ${req['shortage']}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent)),
                );
              }),
              const SizedBox(height: 16),
              TextField(
                controller: stockCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Quantity Received', hintText: 'Enter quantity received'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD9A441)),
            onPressed: () async {
              int received = int.tryParse(stockCtrl.text.trim()) ?? 0;
              if (received <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Received quantity must be greater than 0.')));
                return;
              }

              bool stillHasShortage = false;
              final updatedReqs = <String, dynamic>{};
              requirements.forEach((k, v) {
                final req = Map<String, dynamic>.from(v);
                int reqQty = req['required'] ?? 0;
                int avail = (req['available'] ?? 0) + received;
                int shortage = (reqQty - avail).clamp(0, reqQty);
                if (shortage > 0) stillHasShortage = true;

                updatedReqs[k] = {
                  ...req,
                  'available': avail,
                  'shortage': shortage,
                };
              });

              String newStatus = stillHasShortage ? 'Preparing' : 'Ready for Production';

              // Requirements are recalculated from live inventory — not stored in Supabase.
              await _supabaseData.updateProductionBatchStatus(batchId: bulk['id'], newStatus: newStatus);

              if (!context.mounted) return;
              Navigator.pop(context); // close restock dialog
              Navigator.pop(context); // close details dialog
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Supplies restocked! New status: $newStatus')),
              );
            },
            child: const Text('Confirm Restock'),
          ),
        ],
      ),
    );
  }
}

class _AddStandardBatchDialog extends StatefulWidget {
  const _AddStandardBatchDialog();

  @override
  State<_AddStandardBatchDialog> createState() => _AddStandardBatchDialogState();
}

class _AddStandardBatchDialogState extends State<_AddStandardBatchDialog> {
  String? _selectedProductId;
  String? _selectedVariantId;
  final _qtyCtrl = TextEditingController(text: '50');
  DateTime _startDate = DateTime.now();
  DateTime _targetCompletionDate = DateTime.now().add(const Duration(days: 5));

  Future<void> _pickDate(BuildContext context, bool isStartDate) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStartDate ? _startDate : _targetCompletionDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFFD9A441),
              onPrimary: Colors.white,
              onSurface: Color(0xFF111111),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        if (isStartDate) {
          _startDate = picked;
          if (_targetCompletionDate.isBefore(_startDate)) {
            _targetCompletionDate = _startDate.add(const Duration(days: 5));
          }
        } else {
          _targetCompletionDate = picked;
        }
      });
    }
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  Widget _summaryRow(String label, String value, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: isBold ? const Color(0xFF111111) : Colors.grey.shade700, fontWeight: isBold ? FontWeight.w700 : FontWeight.w500)),
          Text(value, style: TextStyle(fontSize: 12, color: isBold ? const Color(0xFFD9A441) : const Color(0xFF111111), fontWeight: isBold ? FontWeight.w900 : FontWeight.w700)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<dynamic>>(
      stream: CombineLatestStream.list([
        SupabaseDataService().productsStream,
        SupabaseDataService().inventoryStream,
      ]),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const AlertDialog(content: SizedBox(height: 100, child: Center(child: CircularProgressIndicator())));
        }

        final isDark = Theme.of(context).brightness == Brightness.dark;
        final productsMap = snapshot.data != null && snapshot.data!.isNotEmpty && snapshot.data![0] is Map
            ? snapshot.data![0] as Map<String, dynamic>
            : SupabaseDataService().currentProducts;
        final inventoryMap = snapshot.data != null && snapshot.data!.length > 1 && snapshot.data![1] is Map
            ? snapshot.data![1] as Map<String, dynamic>
            : SupabaseDataService().currentInventory;

        String selectedProductName = 'Not selected';
        String selectedVariantSize = 'Not selected';
        int currentStock = 0;

        if (_selectedProductId != null && productsMap.containsKey(_selectedProductId)) {
          final p = productsMap[_selectedProductId];
          selectedProductName = p['variety'] ?? p['name'] ?? 'Product';
          final vars = Map<String, dynamic>.from(p['variants'] as Map? ?? {});
          if (_selectedVariantId != null && vars.containsKey(_selectedVariantId)) {
            final v = vars[_selectedVariantId];
            selectedVariantSize = v['size'] ?? '-';
            final pInv = Map<String, dynamic>.from(inventoryMap[_selectedProductId] as Map? ?? {});
            final vInv = Map<String, dynamic>.from(pInv[_selectedVariantId] as Map? ?? {});
            currentStock = (vInv['quantity'] ?? 0) as int;
          }
        }

        final int targetQty = int.tryParse(_qtyCtrl.text.trim()) ?? 0;

        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.iconBadgeGoldDark : AppTheme.iconBadgeGoldLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.factory_outlined, color: Color(0xFFD9A441), size: 22),
              ),
              const SizedBox(width: 12),
              const Text('New Standard Production Batch', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            ],
          ),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('PRODUCTION PARAMETERS', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11, color: Colors.grey, letterSpacing: 0.8)),
                  const SizedBox(height: 12),

                  // 1. Date Fields (Start Date & Target Completion Date using Date Pickers)
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Start Date', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: Color(0xFF444444))),
                            const SizedBox(height: 6),
                            InkWell(
                              onTap: () => _pickDate(context, true),
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.grey.shade300),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.calendar_today_rounded, size: 16, color: Color(0xFFD9A441)),
                                    const SizedBox(width: 10),
                                    Text(_formatDate(_startDate), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF111111))),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Target Completion Date', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: Color(0xFF444444))),
                            const SizedBox(height: 6),
                            InkWell(
                              onTap: () => _pickDate(context, false),
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.grey.shade300),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.event_available_rounded, size: 16, color: Color(0xFFD9A441)),
                                    const SizedBox(width: 10),
                                    Text(_formatDate(_targetCompletionDate), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF111111))),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // 2. Select Product Field
                  const Text('Select Product', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: Color(0xFF444444))),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFD9A441), width: 1.5)),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                    hint: const Text('Select a product', style: TextStyle(fontSize: 13)),
                    value: _selectedProductId,
                    items: productsMap.entries.map((e) {
                      return DropdownMenuItem(
                        value: e.key,
                        child: Text(e.value['variety'] ?? e.value['name'] ?? 'Product', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      );
                    }).toList(),
                    onChanged: (v) {
                      setState(() {
                        _selectedProductId = v;
                        _selectedVariantId = null;
                      });
                    },
                  ),
                  const SizedBox(height: 16),

                  if (_selectedProductId != null) ...[
                    const Text('Select Bottle Size', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: Color(0xFF444444))),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFD9A441), width: 1.5)),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                      ),
                      hint: const Text('Select bottle size', style: TextStyle(fontSize: 13)),
                      value: _selectedVariantId,
                      items: (Map<String, dynamic>.from(productsMap[_selectedProductId]['variants'] as Map? ?? {})).entries.map((e) {
                        return DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value['size'] ?? 'Size', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                        );
                      }).toList(),
                      onChanged: (v) => setState(() => _selectedVariantId = v),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // 3. Target Quantity Field
                  const Text('Target Quantity', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: Color(0xFF444444))),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _qtyCtrl,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Enter target production quantity',
                      hintStyle: const TextStyle(fontSize: 13, color: Colors.grey),
                      prefixIcon: const Icon(Icons.numbers_rounded, size: 18, color: Color(0xFFD9A441)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFD9A441), width: 1.5)),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // 4. Prediction / Summary Preview Result Area
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF9F9FB),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFEEEEEE)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.analytics_outlined, size: 18, color: Color(0xFFD9A441)),
                            SizedBox(width: 8),
                            Text('PRODUCTION PREVIEW & FORECAST', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11, color: Color(0xFF111111), letterSpacing: 0.5)),
                          ],
                        ),
                        const Divider(height: 20),
                        _summaryRow('Selected Product:', selectedProductName),
                        _summaryRow('Bottle Size:', selectedVariantSize),
                        _summaryRow('Current System Stock:', '$currentStock bottles'),
                        _summaryRow('Target Production Qty:', '$targetQty bottles'),
                        _summaryRow('Forecasted Stock After Completion:', '${currentStock + targetQty} bottles', isBold: true),
                        _summaryRow('Target Completion Date:', _formatDate(_targetCompletionDate)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600)),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD9A441),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () async {
                if (_selectedProductId == null || _selectedVariantId == null || _qtyCtrl.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please select product, bottle size, and enter target quantity.'), backgroundColor: Colors.orange),
                  );
                  return;
                }

                // createProductionBatch resolves product/variant by external_id
                final int target = int.tryParse(_qtyCtrl.text.trim()) ?? 0;

                if (target <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Target quantity must be greater than 0.'), backgroundColor: Colors.redAccent),
                  );
                  return;
                }

                await SupabaseDataService().createProductionBatch(
                  productExternalId: _selectedProductId!,
                  variantExternalId: _selectedVariantId!,
                  qtyTarget: target,
                  startDate: _formatDate(_startDate),
                  targetCompletionDate: _formatDate(_targetCompletionDate),
                );

                if (!context.mounted) return;
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Standard production batch created successfully!'), backgroundColor: Colors.green),
                );
              },
              icon: const Icon(Icons.add_circle_outline_rounded, size: 18, color: Colors.white),
              label: const Text('Create Batch', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
            ),
          ],
        );
      },
    );
  }
}

class _AddBulkProductionDialog extends StatefulWidget {
  const _AddBulkProductionDialog();

  @override
  State<_AddBulkProductionDialog> createState() => _AddBulkProductionDialogState();
}

class _AddBulkProductionDialogState extends State<_AddBulkProductionDialog> {
  String? _selectedOrderId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: SupabaseDataService().ordersStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const AlertDialog(
            title: Text('Add Bulk Production'),
            content: SizedBox(height: 100, child: Center(child: CircularProgressIndicator())),
          );
        }

        final ordersList = snapshot.data ?? SupabaseDataService().currentOrders;
        if (ordersList.isEmpty) {
          return const AlertDialog(
            title: Text('Add Bulk Production'),
            content: Text('No customer orders found in the system.'),
          );
        }

        // Build a map for dropdown lookup (key = Supabase UUID)
        final ordersMap = {for (final o in ordersList) o['id'].toString(): o};
        
        return AlertDialog(
          title: const Text('Create Bulk Production from Order', style: TextStyle(fontWeight: FontWeight.w900)),
          content: SizedBox(
            width: 450,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Select an existing customer order to generate a bulk production plan:', style: TextStyle(color: Colors.grey, fontSize: 13)),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: 'Customer Order ID'),
                  value: _selectedOrderId,
                  items: ordersMap.entries.map((e) {
                    final o = Map<String, dynamic>.from(e.value);
                    return DropdownMenuItem(
                      value: e.key,
                      child: Text('#${e.key.substring(0, 8).toUpperCase()} - ${o['customerName'] ?? 'Customer'}'),
                    );
                  }).toList(),
                  onChanged: (v) => setState(() => _selectedOrderId = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD9A441)),
              onPressed: () async {
                if (_selectedOrderId == null) return;
                final rawOrderData = ordersMap[_selectedOrderId];
                if (rawOrderData == null) return;
                final orderData = Map<String, dynamic>.from(rawOrderData);
                final itemsMap = Map<String, dynamic>.from(orderData['items'] ?? {});

                // Calculate requirements & check against supply inventory (read-only)
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
                  String prodName = itm['product'] ?? itm['productName'] ?? 'Honey';

                  prodItems['item_$index'] = {
                    'productId': pId,
                    'variantId': vId,
                    'productName': prodName,
                    'bottleSize': size,
                    'targetQuantity': qtyNeeded,
                    'completedQuantity': 0,
                    'status': 'Pending',
                  };

                  // Check supply inventory (empty bottles)
                  int availableSupply = 100; // default stock if uninitialized
                  if (inventoryMap.containsKey(pId)) {
                    final pInv = Map<String, dynamic>.from(inventoryMap[pId]);
                    if (pInv.containsKey(vId)) {
                      final vInv = Map<String, dynamic>.from(pInv[vId]);
                      availableSupply = vInv['quantity'] ?? 50;
                    }
                  }

                  int shortage = (qtyNeeded - availableSupply).clamp(0, qtyNeeded);
                  if (shortage > 0) hasShortage = true;

                  requirements['req_$index'] = {
                    'supplyName': '$prodName ($size Empty Bottles)',
                    'required': qtyNeeded,
                    'available': availableSupply,
                    'shortage': shortage,
                  };

                  index++;
                });

                String initialStatus = hasShortage ? 'Preparing' : 'Ready for Production';

                // Build items array for Supabase RPC (JSONB)
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
                  orderId:               _selectedOrderId!,
                  customerName:          orderData['customerName'] ?? 'Customer',
                  bundleName:            'Wholesale Order #${_selectedOrderId!.substring(0, 6).toUpperCase()}',
                  qtyTarget:             totalTargetQty,
                  initialStatus:         initialStatus,
                  itemsSummary:          '${prodItems.length} product line(s)',
                  startDate:             DateTime.now().toString().split(' ')[0],
                  targetCompletionDate:  orderData['orderDate'] ?? DateTime.now().add(const Duration(days: 7)).toString().split(' ')[0],
                  items:                 itemsArray,
                );

                if (!context.mounted) return;
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Bulk production plan created! Status: $initialStatus')),
                );
              },
              child: const Text('Generate Bulk Plan'),
            ),
          ],
        );
      },
    );
  }
}
