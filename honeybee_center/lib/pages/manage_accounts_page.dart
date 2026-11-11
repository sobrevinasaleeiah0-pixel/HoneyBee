import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:honeybee_center/services/auth_service.dart';
import 'package:honeybee_center/services/database_service.dart';
import 'package:honeybee_center/services/admin_status_service.dart';
import 'package:honeybee_center/widgets/status_badge.dart';
import 'package:honeybee_center/core/theme/app_theme.dart';
import 'package:honeybee_center/core/permissions/admin_capabilities.dart';

class ManageAccountsPage extends StatefulWidget {
  final AuthSession session;
  const ManageAccountsPage({super.key, required this.session});

  @override
  State<ManageAccountsPage> createState() => _ManageAccountsPageState();
}

class _ManageAccountsPageState extends State<ManageAccountsPage> {
  final _dbService = DatabaseService();
  final _authService = AuthService();
  final _adminStatusService = AdminStatusServiceProduction.create();
  String _searchQuery = '';
  String _roleFilter = 'All';

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Route guard: Manage Accounts is not accessible through either dashboard.
    // Admin provisioning is handled separately via a secure Edge Function
    // (Phase 5). This guard prevents access through direct/manual navigation.
    if (!RoleCapabilities.forRole(widget.session.role).canManageAccounts) {
      return Scaffold(
        backgroundColor: AppTheme.pageBackground(isDark),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.lock_outline,
                  size: 56,
                  color: AppTheme.primaryGold,
                ),
                const SizedBox(height: 20),
                Text(
                  'Access Restricted',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.textPrimary(isDark),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Administrator provisioning is managed outside the dashboard.\n'
                  'Contact your system administrator.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSecondary(isDark),
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.pageBackground(isDark),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          _buildSearchAndFilter(),
          Expanded(child: _buildAdminTable()),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Builder(
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final textColor = AppTheme.textPrimary(isDark);
        final subColor = AppTheme.textSecondary(isDark);
        return Padding(
          padding: const EdgeInsets.fromLTRB(32, 24, 32, 16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 600;
              final title = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Manage Accounts',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Control administrative access and user roles',
                    style: TextStyle(color: subColor, fontSize: 13),
                  ),
                ],
              );
              final btn = ElevatedButton.icon(
                onPressed: () => _showAddAdminDialog(),
                icon: const Icon(Icons.person_add_outlined, size: 18),
                label: const Text('Add Co-Admin'),
              );

              if (isNarrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [title, const SizedBox(height: 14), btn],
                );
              }

              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(child: title),
                  const SizedBox(width: 16),
                  btn,
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildSearchAndFilter() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = AppTheme.textPrimary(isDark);
    final subColor = AppTheme.textSecondary(isDark);
    final fillColor = AppTheme.fieldFill(isDark);
    final borderColor = AppTheme.panelBorder(isDark);

    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 0, 32, 14),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              onChanged: (v) => setState(() => _searchQuery = v),
              style: TextStyle(fontSize: 13, color: textColor),
              decoration: InputDecoration(
                hintText: 'Search by admin name or email...',
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
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                  borderSide: BorderSide(color: borderColor),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                  borderSide: BorderSide(color: borderColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
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
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: fillColor,
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              border: Border.all(color: borderColor),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _roleFilter,
                style: TextStyle(
                  fontSize: 13,
                  color: textColor,
                  fontWeight: FontWeight.w600,
                ),
                dropdownColor: AppTheme.panelColor(isDark),
                items: ['All', 'Owner', 'Co-Admin']
                    .map(
                      (s) => DropdownMenuItem(
                        value: s,
                        child: Text(s, style: TextStyle(color: textColor)),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _roleFilter = v ?? 'All'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdminTable() {
    return StreamBuilder<DatabaseEvent>(
      stream: _dbService.getAdminsStream(),
      builder: (context, snapshot) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final textColor = AppTheme.textPrimary(isDark);
        final subColor = AppTheme.textSecondary(isDark);
        if (snapshot.connectionState == ConnectionState.waiting)
          return const Center(child: CircularProgressIndicator());

        if (!snapshot.hasData || snapshot.data?.snapshot.value == null) {
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
                    Icons.supervisor_account_outlined,
                    size: 52,
                    color: AppTheme.primaryGold,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No admin accounts',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Click "Add Co-Admin" to invite a team member.',
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

        final map = Map<String, dynamic>.from(
          snapshot.data!.snapshot.value as Map,
        );
        final list = map.entries.map((e) {
          final val = Map<String, dynamic>.from(e.value);
          val['uid'] = e.key;
          return val;
        }).toList();

        final filteredList = list.where((admin) {
          final q = _searchQuery.toLowerCase().trim();
          final nameMatch = (admin['name'] ?? '')
              .toString()
              .toLowerCase()
              .contains(q);
          final emailMatch = (admin['email'] ?? '')
              .toString()
              .toLowerCase()
              .contains(q);
          final idMatch = (admin['uid'] ?? '')
              .toString()
              .toLowerCase()
              .contains(q);
          final matchesSearch = q.isEmpty || nameMatch || emailMatch || idMatch;

          final role = (admin['role'] ?? 'co_admin').toString();
          final matchesRole =
              _roleFilter == 'All' ||
              (_roleFilter == 'Owner' && role == 'main_admin') ||
              (_roleFilter == 'Co-Admin' && role == 'co_admin');
          return matchesSearch && matchesRole;
        }).toList();

        if (filteredList.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(48.0),
              child: Text(
                'No accounts match your search or filter criteria.',
                style: TextStyle(color: subColor, fontSize: 13),
              ),
            ),
          );
        }

        return Container(
          margin: const EdgeInsets.fromLTRB(32, 8, 32, 24),
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
                    'ADMIN ID',
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
                    'ADMIN NAME',
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
                    'EMAIL',
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
                    'ROLE',
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
              rows: filteredList.map((admin) {
                final isMainAdmin = admin['role'] == 'main_admin';
                final isActive = admin['status'] == 'active';
                final shortAdminId =
                    '#ADM-${admin['uid'].toString().replaceAll('-', '').substring(0, admin['uid'].toString().replaceAll('-', '').length >= 6 ? 6 : admin['uid'].toString().length).toUpperCase()}';

                return DataRow(
                  cells: [
                    DataCell(
                      Text(
                        shortAdminId,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          color: textColor,
                        ),
                      ),
                    ),
                    DataCell(
                      Text(
                        admin['name'] ?? 'N/A',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: textColor,
                        ),
                      ),
                    ),
                    DataCell(
                      Text(
                        admin['email'] ?? 'N/A',
                        style: TextStyle(
                          fontSize: 13,
                          color: subColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    DataCell(StatusBadge(status: admin['role'] ?? 'co_admin')),
                    DataCell(
                      StatusBadge(status: isActive ? 'Active' : 'Inactive'),
                    ),
                    DataCell(
                      isMainAdmin
                          ? Text(
                              'Protected',
                              style: TextStyle(
                                color: subColor,
                                fontSize: 12,
                                fontStyle: FontStyle.italic,
                                fontWeight: FontWeight.w700,
                              ),
                            )
                          : Row(
                              children: [
                                IconButton(
                                  icon: Icon(
                                    Icons.edit_outlined,
                                    size: 18,
                                    color: textColor,
                                  ),
                                  onPressed: () => _showEditAdminDialog(admin),
                                ),
                                IconButton(
                                  icon: Icon(
                                    isActive
                                        ? Icons.block
                                        : Icons.check_circle_outline,
                                    size: 18,
                                    color: isActive
                                        ? AppTheme.error
                                        : AppTheme.success,
                                  ),
                                  onPressed: () =>
                                      _toggleAdminStatus(admin, isActive),
                                  tooltip: isActive ? 'Deactivate' : 'Activate',
                                ),
                              ],
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

  void _showAddAdminDialog() {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          return AlertDialog(
            backgroundColor: AppTheme.panelColor(isDark),
            title: Text(
              'Add New Co-Admin',
              style: TextStyle(
                color: AppTheme.textPrimary(isDark),
                fontWeight: FontWeight.w900,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Full Name'),
                ),
                TextField(
                  controller: emailCtrl,
                  decoration: const InputDecoration(labelText: 'Email Address'),
                ),
                TextField(
                  controller: passCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Temporary Password',
                  ),
                  obscureText: true,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: isLoading
                    ? null
                    : () async {
                        setDialogState(() => isLoading = true);
                        try {
                          await _authService.createCoAdmin(
                            fullName: nameCtrl.text,
                            email: emailCtrl.text,
                            password: passCtrl.text,
                            creatorId: widget.session.uid,
                          );
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Co-Admin account created successfully.',
                              ),
                            ),
                          );
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(e.toString()),
                              backgroundColor: Colors.red,
                            ),
                          );
                        } finally {
                          setDialogState(() => isLoading = false);
                        }
                      },
                child: isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Create Account'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showEditAdminDialog(Map<String, dynamic> admin) {
    final nameCtrl = TextEditingController(text: admin['name']);

    showDialog(
      context: context,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: AppTheme.panelColor(isDark),
          title: Text(
            'Edit Account Info',
            style: TextStyle(
              color: AppTheme.textPrimary(isDark),
              fontWeight: FontWeight.w900,
            ),
          ),
          content: TextField(
            controller: nameCtrl,
            decoration: const InputDecoration(labelText: 'Full Name'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                try {
                  await FirebaseDatabase.instance
                      .ref()
                      .child('admins')
                      .child(admin['uid'])
                      .update({'name': nameCtrl.text});
                  if (!context.mounted) return;
                  Navigator.pop(context);
                } catch (error) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Failed to update Firebase profile: $error',
                      ),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              child: const Text('Update'),
            ),
          ],
        );
      },
    );
  }

  // ── Toggle Co-Admin status (Supabase-first, then Firebase mirror) ─────────
  //
  // Supabase is the single source of truth for login authorization.
  // Firebase is updated only as a display mirror after Supabase succeeds.
  Future<void> _toggleAdminStatus(
    Map<String, dynamic> admin,
    bool currentlyActive,
  ) async {
    final email = admin['email']?.toString() ?? '';
    final firebaseId = admin['uid']?.toString() ?? '';
    final newStatus = currentlyActive ? 'inactive' : 'active';

    if (email.isEmpty || firebaseId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot update: admin email or ID is missing.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final result = await _adminStatusService.updateCoAdminStatus(
      adminEmail: email,
      adminFirebaseId: firebaseId,
      newStatus: newStatus,
      performerName: widget.session.name,
    );

    if (!mounted) return;

    if (result.success && result.firebaseUpdated) {
      // Full success — log activity via DatabaseService.
      await _dbService.logAdminActivity(
        action: 'UPDATE_ADMIN_STATUS',
        details: '${widget.session.name} set $email to $newStatus.',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Status updated: $email is now $newStatus.')),
      );
      return;
    }

    if (result.isPartialFailure) {
      // Supabase updated (login is already enforced) but Firebase mirror failed.
      // Login is governed by Supabase, so security is intact.
      // Offer a retry for the display inconsistency.
      await _dbService.logAdminActivity(
        action: 'UPDATE_ADMIN_STATUS_PARTIAL',
        details:
            '${widget.session.name} set $email to $newStatus in Supabase, '
            'but Firebase sync failed: ${result.firebaseErrorMessage}',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Status updated in Supabase — login is already '
            '${newStatus == 'active' ? 're-enabled' : 'blocked'}. '
            'Display sync failed. Tap Retry to fix.',
          ),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 10),
          action: SnackBarAction(
            label: 'Retry',
            textColor: Colors.white,
            onPressed: () async {
              final retried = await _adminStatusService.retryFirebaseSync(
                firebaseAdminId: firebaseId,
                newStatus: newStatus,
              );
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    retried
                        ? 'Firebase display sync resolved.'
                        : 'Retry failed. Supabase status is still correct.',
                  ),
                  backgroundColor: retried ? Colors.green : Colors.red,
                ),
              );
            },
          ),
        ),
      );
      return;
    }

    // Both failed — surface the error.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.errorMessage ?? 'Status update failed. Please try again.',
        ),
        backgroundColor: Colors.red,
      ),
    );
  }
}
