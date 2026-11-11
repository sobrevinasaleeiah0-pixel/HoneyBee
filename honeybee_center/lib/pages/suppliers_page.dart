import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/supabase_data_service.dart';
import '../widgets/status_badge.dart';
import '../core/theme/app_theme.dart';
import '../core/permissions/admin_capabilities.dart';

class SuppliersPage extends StatefulWidget {
  final AuthSession session;
  const SuppliersPage({super.key, required this.session});

  @override
  State<SuppliersPage> createState() => _SuppliersPageState();
}

class _SuppliersPageState extends State<SuppliersPage> {
  final _supabaseData = SupabaseDataService();
  final _searchController = TextEditingController();
  String _searchQuery = '';
  String _statusFilter = 'All';

  bool get _canManage =>
      RoleCapabilities.forRole(widget.session.role).canManageSuppliers;

  // Suppliers are loaded via FutureBuilder + pull-to-refresh.
  late Future<List<Map<String, dynamic>>> _suppliersFuture;

  @override
  void initState() {
    super.initState();
    _suppliersFuture = _supabaseData.fetchSuppliers();
  }

  void _refresh() {
    setState(() {
      _suppliersFuture = _supabaseData.fetchSuppliers();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showSupplierDialog({Map<String, dynamic>? supplier}) {
    final isEditing = supplier != null;
    final nameController = TextEditingController(text: supplier?['supplierName'] ?? '');
    final contactPersonController = TextEditingController(text: supplier?['contactPerson'] ?? '');
    final contactNumberController = TextEditingController(text: supplier?['contactNumber'] ?? '');
    final addressController = TextEditingController(text: supplier?['address'] ?? '');
    final suppliesController = TextEditingController(text: supplier?['supplies'] ?? '');
    final lastSupplyController = TextEditingController(text: supplier?['lastSupplyDate'] ?? '');
    final notesController = TextEditingController(text: supplier?['notes'] ?? '');
    String status = supplier?['status'] ?? 'Active';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(isEditing ? 'Edit Supplier' : 'Add New Supplier', style: const TextStyle(fontWeight: FontWeight.w900)),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Supplier Name *', hintText: 'e.g. San Pablo Bottle Factory'),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: contactPersonController,
                    decoration: const InputDecoration(labelText: 'Contact Person', hintText: 'e.g. Juan Dela Cruz'),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: contactNumberController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Contact Number', hintText: 'e.g. 09123456789'),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: addressController,
                    decoration: const InputDecoration(labelText: 'Address', hintText: 'e.g. San Pablo, Laguna'),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: suppliesController,
                    decoration: const InputDecoration(labelText: 'Supplies / Items Provided', hintText: 'e.g. Honey Bottles, Caps'),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: lastSupplyController,
                    decoration: const InputDecoration(labelText: 'Last Supply Date', hintText: 'e.g. September 20, 2026'),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: notesController,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Notes', hintText: 'Additional remarks...'),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: status,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: ['Active', 'Inactive']
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (v) => setDialogState(() => status = v!),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD9A441)),
              onPressed: () async {
                if (nameController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Supplier Name is required.'), backgroundColor: Colors.redAccent),
                  );
                  return;
                }

                final data = {
                  'supplierName': nameController.text.trim(),
                  'contactPerson': contactPersonController.text.trim(),
                  'contactNumber': contactNumberController.text.trim(),
                  'address': addressController.text.trim(),
                  'supplies': suppliesController.text.trim(),
                  'lastSupplyDate': lastSupplyController.text.trim(),
                  'notes': notesController.text.trim(),
                  'status': status,
                };

                try {
                  if (isEditing) {
                    await _supabaseData.updateSupplier(supplier['id'], data);
                  } else {
                    await _supabaseData.createSupplier(data);
                  }
                  if (!mounted) return;
                  Navigator.of(context).pop();
                  _refresh();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(isEditing ? 'Supplier updated successfully.' : 'Supplier added successfully.')),
                  );
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
                  );
                }
              },
              child: Text(isEditing ? 'Save Changes' : 'Add Supplier'),
            ),
          ],
        ),
      ),
    );
  }

  void _showSupplierDetails(Map<String, dynamic> supplier) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(supplier['supplierName'] ?? 'Supplier Details', style: const TextStyle(fontWeight: FontWeight.w900)),
        content: SizedBox(
          width: 450,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _detailRow('Status', supplier['status'] ?? 'Active'),
              _detailRow('Contact Person', supplier['contactPerson']),
              _detailRow('Contact Number', supplier['contactNumber']),
              _detailRow('Address', supplier['address']),
              _detailRow('Supplies Provided', supplier['supplies']),
              _detailRow('Last Supply Date', supplier['lastSupplyDate']),
              _detailRow('Notes', supplier['notes']),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.grey, fontSize: 13)),
          ),
          Expanded(
            child: Text(value?.isNotEmpty == true ? value! : '-', style: const TextStyle(fontSize: 13, color: Color(0xFF111111))),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmation(Map<String, dynamic> supplier) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Supplier', style: TextStyle(fontWeight: FontWeight.w900)),
        content: Text('Are you sure you want to delete "${supplier['supplierName']}"? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              try {
                await _supabaseData.deleteSupplier(supplier['id']);
                if (!mounted) return;
                Navigator.of(context).pop();
                _refresh();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Supplier deleted successfully.')),
                );
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
                );
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 24),
            _buildSupplierTable(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Builder(
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final textColor = isDark ? AppTheme.textDark : AppTheme.textLight;
        final subColor = isDark ? AppTheme.subtitleDark(isDark) : AppTheme.subtitleLight(isDark);
        final fill = isDark ? AppTheme.backgroundDarkAlt : Colors.white;
        final border = isDark ? AppTheme.borderDarkAlt : AppTheme.borderLightAlt;
        return Padding(
          padding: const EdgeInsets.fromLTRB(32, 24, 32, 16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 850;
              final titleCol = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Suppliers',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: textColor),
                  ),
                  const SizedBox(height: 4),
                  Text('Manage internal supplier records and material providers', style: TextStyle(color: subColor, fontSize: 13)),
                ],
              );

              final controls = Wrap(
                spacing: 12,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: isNarrow ? constraints.maxWidth : 240,
                    child: TextField(
                      controller: _searchController,
                      onChanged: (v) => setState(() => _searchQuery = v.trim().toLowerCase()),
                      style: TextStyle(color: textColor, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Search suppliers...',
                        hintStyle: TextStyle(color: subColor, fontSize: 12),
                        prefixIcon: Icon(Icons.search, size: 18, color: AppTheme.primaryGold),
                        filled: true,
                        fillColor: fill,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppTheme.radiusMd), borderSide: BorderSide(color: border)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppTheme.radiusMd), borderSide: BorderSide(color: border)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppTheme.radiusMd), borderSide: const BorderSide(color: AppTheme.primaryGold, width: 1.6)),
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(AppTheme.radiusMd), border: Border.all(color: border)),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _statusFilter,
                        style: TextStyle(fontSize: 13, color: textColor, fontWeight: FontWeight.w600),
                        dropdownColor: fill,
                        items: ['All', 'Active', 'Inactive'].map((s) => DropdownMenuItem(value: s, child: Text(s, style: TextStyle(color: textColor)))).toList(),
                        onChanged: (v) => setState(() => _statusFilter = v ?? 'All'),
                      ),
                    ),
                  ),
                  if (_canManage)
                    ElevatedButton.icon(
                      onPressed: () => _showSupplierDialog(),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Add Supplier', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                ],
              );

              if (isNarrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    titleCol,
                    const SizedBox(height: 14),
                    controls,
                  ],
                );
              }

              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(child: titleCol),
                  const SizedBox(width: 16),
                  controls,
                ],
              );
            },
          ),
        );
      }
    );
  }

  Widget _buildSupplierTable() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _suppliersFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()));
        }
        if (snapshot.hasError) {
          return Center(child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Error loading suppliers: ${snapshot.error}', style: const TextStyle(color: Colors.red)),
          ));
        }

        // Map Supabase snake_case → camelCase expected by the rest of the UI
        final raw = snapshot.data ?? [];
        final suppliers = raw.map((r) => <String, dynamic>{
          'supplierId':    r['id']?.toString() ?? '',
          'id':            r['id']?.toString() ?? '',
          'supplierName':  r['supplier_name']?.toString() ?? '',
          'contactPerson': r['contact_person']?.toString() ?? '',
          'contactNumber': r['contact_number']?.toString() ?? '',
          'address':       r['address']?.toString() ?? '',
          'supplies':      r['supplies']?.toString() ?? '',
          'lastSupplyDate':r['last_supply_date']?.toString() ?? '',
          'notes':         r['notes']?.toString() ?? '',
          'status':        r['status']?.toString() ?? 'Active',
        }).toList();

        // Filter by search query & status
        final filteredSuppliers = suppliers.where((s) {
          final q = _searchQuery;
          final name = (s['supplierName'] ?? '').toLowerCase();
          final contact = (s['contactPerson'] ?? '').toLowerCase();
          final supplies = (s['supplies'] ?? '').toLowerCase();
          final address = (s['address'] ?? '').toLowerCase();
          final matchesSearch = q.isEmpty || name.contains(q) || contact.contains(q) || supplies.contains(q) || address.contains(q);

          final status = (s['status'] ?? 'Active').toString().toLowerCase();
          final matchesStatus = _statusFilter == 'All' || status == _statusFilter.toLowerCase();
          return matchesSearch && matchesStatus;
        }).toList();

        if (filteredSuppliers.isEmpty) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(48.0),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.business_outlined, size: 48, color: Colors.grey),
                    SizedBox(height: 16),
                    Text('No suppliers found.', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey)),
                    SizedBox(height: 4),
                    Text('Try adjusting your search query or status filter.', style: TextStyle(fontSize: 13, color: Colors.grey)),
                  ],
                ),
              ),
            ),
          );
        }

        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusLg),
            side: BorderSide(color: isDark ? AppTheme.borderDark : AppTheme.borderLight),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(isDark ? AppTheme.backgroundDarkAlt : AppTheme.backgroundLightAlt),
              horizontalMargin: 24,
              columns: const [
                DataColumn(label: Text('SUPPLIER ID', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
                DataColumn(label: Text('SUPPLIER', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
                DataColumn(label: Text('CONTACT PERSON', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
                DataColumn(label: Text('CONTACT NUMBER', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
                DataColumn(label: Text('SUPPLIES', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
                DataColumn(label: Text('LAST SUPPLY', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
                DataColumn(label: Text('STATUS', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
                DataColumn(label: Text('ACTIONS', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
              ],
              rows: filteredSuppliers.map((s) {
                final rawId = s['supplierId'].toString().replaceAll('-', '');
                final shortId = '#SUP-${rawId.substring(0, rawId.length >= 6 ? 6 : rawId.length).toUpperCase()}';
                return DataRow(cells: [
                  DataCell(Text(shortId, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
                  DataCell(Text(s['supplierName'] ?? 'N/A', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
                  DataCell(Text(s['contactPerson'] ?? '-', style: const TextStyle(fontSize: 13))),
                  DataCell(Text(s['contactNumber'] ?? '-', style: const TextStyle(fontSize: 13))),
                  DataCell(Text(s['supplies'] ?? '-', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                  DataCell(Text(s['lastSupplyDate'] ?? '-', style: const TextStyle(fontSize: 13, color: Colors.grey))),
                  DataCell(StatusBadge(status: s['status'] ?? 'Active')),
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.visibility_outlined, size: 18, color: Colors.grey),
                          tooltip: 'View Details',
                          onPressed: () => _showSupplierDetails(s),
                        ),
                        if (_canManage) ...[
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 18, color: Color(0xFFD9A441)),
                            tooltip: 'Edit Supplier',
                            onPressed: () => _showSupplierDialog(supplier: s),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.redAccent),
                            tooltip: 'Delete Supplier',
                            onPressed: () => _showDeleteConfirmation(s),
                          ),
                        ],
                      ],
                    ),
                  ),
                ]);
              }).toList(),
            ),
          ),
        );
      },
    );
  }
}
