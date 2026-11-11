import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/permissions/admin_capabilities.dart';
import '../core/theme/app_theme.dart';
import '../services/auth_service.dart';
import '../services/supabase_activity_service.dart';
import 'login_page.dart';

// Monitoring-only pages (read access, no write actions for main_admin)
import 'dashboard_page.dart';
import 'orders_page.dart';
import 'inventory_page.dart';
import 'production_page.dart';
import 'reports_page.dart';
import 'notifications_page.dart';
import 'feedback_page.dart';

// ─────────────────────────────────────────────────────────────────────────────
// OwnerShell
//
// The Owner / Main Admin monitoring panel.
// Navigation: 8 read-only sections.
// No write actions are exposed — each page is gated by RoleCapabilities.owner.
// This shell is intentionally separate from MainDashboardPage (Co-Admin ops).
// ─────────────────────────────────────────────────────────────────────────────

class OwnerShell extends StatefulWidget {
  final AuthSession session;
  const OwnerShell({super.key, required this.session});

  @override
  State<OwnerShell> createState() => _OwnerShellState();
}

class _OwnerShellState extends State<OwnerShell> {
  int _selectedIndex = 0;
  bool? _isSidebarCollapsed;
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  static const String _storageKey = 'owner_selected_tab';

  // ── Navigation items ────────────────────────────────────────────────────────
  // All items are monitoring/read-only. No operational write pages are listed.
  static const _navItems = [
    _OwnerNavItem(
      title: 'Overview Dashboard',
      icon: Icons.grid_view_outlined,
      index: 0,
    ),
    _OwnerNavItem(
      title: 'Sales & Reports',
      icon: Icons.bar_chart_outlined,
      index: 1,
    ),
    _OwnerNavItem(
      title: 'Orders Overview',
      icon: Icons.shopping_bag_outlined,
      index: 2,
    ),
    _OwnerNavItem(
      title: 'Inventory Overview',
      icon: Icons.inventory_2_outlined,
      index: 3,
    ),
    _OwnerNavItem(
      title: 'Production Overview',
      icon: Icons.factory_outlined,
      index: 4,
    ),
    _OwnerNavItem(
      title: 'Activity Logs',
      icon: Icons.history_outlined,
      index: 5,
    ),
    _OwnerNavItem(
      title: 'Notifications',
      icon: Icons.notifications_none_outlined,
      index: 6,
    ),
    _OwnerNavItem(
      title: 'Feedback Monitoring',
      icon: Icons.reviews_outlined,
      index: 7,
    ),
  ];

  @override
  void initState() {
    super.initState();
    assert(
      RoleCapabilities.forRole(widget.session.role).isMonitoringOnly,
      'OwnerShell must only be used with a monitoring-only role.',
    );
    _loadSelectedTab();
  }

  Future<void> _loadSelectedTab() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getInt(_storageKey) ?? 0;
    final valid = saved >= 0 && saved < _navItems.length;
    setState(() => _selectedIndex = valid ? saved : 0);
  }

  Future<void> _setSelectedTab(int index) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_storageKey, index);
    setState(() => _selectedIndex = index);
  }

  Future<void> _logout() async {
    await AuthService().signOut();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );
  }

  // ── Page routing ────────────────────────────────────────────────────────────
  Widget _pageForIndex(int index) {
    switch (index) {
      case 0:
        return DashboardPage(session: widget.session);
      case 1:
        return ReportsPage(session: widget.session);
      case 2:
        return OrdersPage(session: widget.session);
      case 3:
        return InventoryPage(session: widget.session);
      case 4:
        return ProductionPage(session: widget.session);
      case 5:
        // Activity Logs — Phase 3 will replace this placeholder
        return _ActivityLogsPlaceholder(session: widget.session);
      case 6:
        return NotificationsPage(
          session: widget.session,
          onNavigateTab: _setSelectedTab,
        );
      case 7:
        return FeedbackPage(session: widget.session);
      default:
        return DashboardPage(session: widget.session);
    }
  }

  // ── Drawer (compact / mobile) ───────────────────────────────────────────────
  Widget _buildCompactDrawer() {
    return SafeArea(
      child: Material(
        color: AppTheme.sidebarBg,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 24, 14, 18),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(14, 0, 14, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Honeybee Center',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Owner Panel',
                    style: TextStyle(
                      color: AppTheme.primaryGold,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            ..._navItems.map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: _SidebarTile(
                    icon: item.icon,
                    title: item.title,
                    isSelected: _selectedIndex == item.index,
                    isCollapsed: false,
                    onTap: () {
                      _setSelectedTab(item.index);
                      Navigator.of(context).pop();
                    },
                  ),
                )),
            const Divider(color: Colors.white24, height: 28),
            _SidebarTile(
              icon: Icons.logout_rounded,
              title: 'Logout',
              isSelected: false,
              isCollapsed: false,
              isLogout: true,
              onTap: _logout,
            ),
          ],
        ),
      ),
    );
  }

  // ── Sidebar (desktop) ────────────────────────────────────────────────────────
  Widget _buildSidebar({required bool isCollapsed, required bool isDark}) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeInOutCubic,
      width: isCollapsed ? 76 : 264,
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: AppTheme.sidebarBg,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppTheme.sidebarBorder, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          // Brand header
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isCollapsed ? 12 : 18,
            ),
            child: Row(
              mainAxisAlignment: isCollapsed
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.spaceBetween,
              children: [
                if (!isCollapsed) ...[
                  Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: AppTheme.sidebarBrandBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppTheme.sidebarBrandRing,
                            width: 1.5,
                          ),
                        ),
                        child: const Icon(
                          Icons.hive_rounded,
                          color: AppTheme.primaryGold,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Honeybee Center',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            'Owner Panel',
                            style: TextStyle(
                              color: AppTheme.primaryGold,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ] else ...[
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppTheme.sidebarBrandBg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.hive_rounded,
                      color: AppTheme.primaryGold,
                      size: 22,
                    ),
                  ),
                ],
                if (!isCollapsed)
                  IconButton(
                    onPressed: () =>
                        setState(() => _isSidebarCollapsed = !isCollapsed),
                    icon: const Icon(
                      Icons.chevron_left_rounded,
                      color: Colors.white54,
                      size: 20,
                    ),
                    padding: EdgeInsets.zero,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Nav items
          Expanded(
            child: ListView(
              padding: EdgeInsets.symmetric(
                horizontal: isCollapsed ? 10 : 12,
              ),
              children: _navItems
                  .map((item) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: _SidebarTile(
                          icon: item.icon,
                          title: item.title,
                          isSelected: _selectedIndex == item.index,
                          isCollapsed: isCollapsed,
                          onTap: () => _setSelectedTab(item.index),
                        ),
                      ))
                  .toList(),
            ),
          ),

          // Bottom: collapse toggle + logout
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isCollapsed ? 10 : 12,
              vertical: 12,
            ),
            child: Column(
              children: [
                const Divider(color: Colors.white12, height: 16),
                if (isCollapsed)
                  IconButton(
                    onPressed: () =>
                        setState(() => _isSidebarCollapsed = false),
                    icon: const Icon(
                      Icons.chevron_right_rounded,
                      color: Colors.white54,
                      size: 20,
                    ),
                    tooltip: 'Expand sidebar',
                  ),
                _SidebarTile(
                  icon: Icons.logout_rounded,
                  title: 'Logout',
                  isSelected: false,
                  isCollapsed: isCollapsed,
                  isLogout: true,
                  onTap: _logout,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Top bar ──────────────────────────────────────────────────────────────────
  Widget _buildTopBar({required bool isCompact, required bool isCollapsed}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppTheme.textDark : AppTheme.textLight;
    final headerBg = AppTheme.pageBackground(isDark);
    final borderColor = AppTheme.panelBorder(isDark);
    final title = _navItems[_selectedIndex].title;

    return Container(
      height: 68,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: headerBg,
        border: Border(
          bottom: BorderSide(color: borderColor),
        ),
      ),
      child: Row(
        children: [
          if (isCompact || isCollapsed)
            IconButton(
              onPressed: isCompact
                  ? () => _scaffoldKey.currentState?.openDrawer()
                  : () => setState(() => _isSidebarCollapsed = false),
              icon: Icon(Icons.menu_rounded, color: textColor),
              tooltip: 'Open navigation',
            ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: textColor,
                letterSpacing: -0.2,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // Monitoring badge
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF1A2D1A)
                  : const Color(0xFFEAF7EA),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark
                    ? const Color(0xFF2E5E2E)
                    : const Color(0xFFB4DEB4),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  'Monitoring',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? const Color(0xFF4CAF50)
                        : const Color(0xFF2E7D32),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),

          // Theme toggle
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppTheme.panelColor(isDark),
              border: Border.all(color: AppTheme.panelBorder(isDark)),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              onPressed: () => ThemeNotifier.instance.toggleTheme(),
              icon: Icon(
                ThemeNotifier.instance.themeMode == ThemeMode.dark
                    ? Icons.wb_sunny_outlined
                    : Icons.dark_mode_outlined,
                color: textColor,
                size: 18,
              ),
              padding: EdgeInsets.zero,
            ),
          ),
          const SizedBox(width: 10),

          // Avatar + role pill
          Container(
            padding: const EdgeInsets.fromLTRB(5, 5, 12, 5),
            decoration: BoxDecoration(
              color: isDark ? AppTheme.surfaceDark : Colors.white,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: isDark
                    ? AppTheme.borderDarkAlt
                    : AppTheme.borderLightAlt,
                width: 1.2,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppTheme.primaryGold,
                        AppTheme.primaryGoldDeep,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      widget.session.name.isNotEmpty
                          ? widget.session.name[0].toUpperCase()
                          : 'O',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF1F1500),
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.session.name.split(' ').first,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: textColor,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1.5,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF332508)
                            : const Color(0xFFFFF6DF),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: isDark
                              ? const Color(0xFF6B4E10)
                              : const Color(0xFFE8D09E),
                          width: 0.8,
                        ),
                      ),
                      child: Text(
                        'OWNER',
                        style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w900,
                          color: isDark
                              ? AppTheme.primaryGold
                              : AppTheme.primaryGoldDeep,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isCompact = screenWidth < 900;
    final isCollapsed = _isSidebarCollapsed ?? (screenWidth < 1100);

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTopBar(isCompact: isCompact, isCollapsed: isCollapsed),
        Expanded(child: _pageForIndex(_selectedIndex)),
      ],
    );

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppTheme.pageBackground(isDark),
      drawer: isCompact ? Drawer(child: _buildCompactDrawer()) : null,
      body: Container(
        color: AppTheme.pageBackground(isDark),
        child: Padding(
          padding: EdgeInsets.all(screenWidth < 600 ? 8.0 : 16.0),
          child: isCompact
              ? content
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildSidebar(
                        isCollapsed: isCollapsed, isDark: isDark),
                    const SizedBox(width: 16),
                    Expanded(child: content),
                  ],
                ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// OwnerActivityLogsPage — Phase 3 Supabase-backed activity log viewer
// ─────────────────────────────────────────────────────────────────────────────

class _ActivityLogsPlaceholder extends StatefulWidget {
  const _ActivityLogsPlaceholder({required this.session});
  final AuthSession session;

  @override
  State<_ActivityLogsPlaceholder> createState() =>
      _ActivityLogsPlaceholderState();
}

class _ActivityLogsPlaceholderState
    extends State<_ActivityLogsPlaceholder> {
  final _service = SupabaseActivityService();
  final _searchController = TextEditingController();

  List<ActivityLogEntry> _entries = [];
  bool _loading = true;
  String? _error;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final entries = await _service.fetchLogs(
        limit: 200,
        search: _search.isEmpty ? null : _search,
      );
      if (mounted) setState(() => _entries = entries);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatDate(DateTime dt) {
    final d = dt.toLocal();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}  '
        '${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}:'
        '${d.second.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = AppTheme.textPrimary(isDark);
    final subColor = AppTheme.textSecondary(isDark);
    final borderColor = AppTheme.panelBorder(isDark);
    final headerBg = AppTheme.tableHeader(isDark);
    final cardBg = isDark ? AppTheme.surfaceDark : Colors.white;

    return Scaffold(
      backgroundColor: AppTheme.pageBackground(isDark),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 24, 32, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Activity Logs',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: textColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Real-time record of all administrator actions '
                        'from Supabase.',
                        style: TextStyle(fontSize: 13, color: subColor),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                // Search
                SizedBox(
                  width: 260,
                  height: 40,
                  child: TextField(
                    controller: _searchController,
                    onChanged: (v) {
                      setState(() => _search = v.trim());
                    },
                    onSubmitted: (_) => _load(),
                    style: TextStyle(fontSize: 13, color: textColor),
                    decoration: InputDecoration(
                      hintText: 'Search action or details…',
                      hintStyle:
                          TextStyle(fontSize: 12, color: subColor),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        size: 18,
                        color: subColor,
                      ),
                      suffixIcon: _search.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.close_rounded,
                                  size: 16, color: subColor),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _search = '');
                                _load();
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: AppTheme.panelColor(isDark),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: borderColor),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: borderColor),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                            color: AppTheme.primaryGold, width: 1.5),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // Refresh
                IconButton(
                  onPressed: _loading ? null : _load,
                  icon: _loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2),
                        )
                      : Icon(Icons.refresh_rounded,
                          color: textColor, size: 20),
                  tooltip: 'Refresh logs',
                ),
              ],
            ),
          ),

          // ── Error banner ────────────────────────────────────────────────
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 12),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppTheme.badgeRedBgDark
                      : AppTheme.badgeRedBgLight,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isDark
                        ? AppTheme.badgeRedBorderDark
                        : AppTheme.badgeRedBorderLight,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded,
                        color: AppTheme.error, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Could not load activity logs: $_error',
                        style: const TextStyle(
                            color: AppTheme.error, fontSize: 12),
                      ),
                    ),
                    TextButton(
                      onPressed: _load,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),

          // ── Table ────────────────────────────────────────────────────────
          Expanded(
            child: _loading && _entries.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _entries.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.history_outlined,
                                size: 48, color: AppTheme.primaryGold),
                            const SizedBox(height: 14),
                            Text(
                              _search.isEmpty
                                  ? 'No activity logs yet.'
                                  : 'No logs match "$_search".',
                              style: TextStyle(
                                  color: subColor, fontSize: 14),
                            ),
                          ],
                        ),
                      )
                    : Padding(
                        padding:
                            const EdgeInsets.fromLTRB(32, 0, 32, 24),
                        child: Container(
                          decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius:
                                BorderRadius.circular(AppTheme.radiusLg),
                            border: Border.all(color: borderColor),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Table header
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 20, vertical: 12),
                                decoration: BoxDecoration(
                                  color: headerBg,
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(
                                        AppTheme.radiusLg),
                                  ),
                                ),
                                child: Row(children: [
                                  SizedBox(
                                    width: 170,
                                    child: Text('TIMESTAMP',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 11,
                                            color: subColor,
                                            letterSpacing: 0.3)),
                                  ),
                                  SizedBox(
                                    width: 120,
                                    child: Text('ADMIN',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 11,
                                            color: subColor,
                                            letterSpacing: 0.3)),
                                  ),
                                  SizedBox(
                                    width: 200,
                                    child: Text('ACTION',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 11,
                                            color: subColor,
                                            letterSpacing: 0.3)),
                                  ),
                                  Expanded(
                                    child: Text('DETAILS',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 11,
                                            color: subColor,
                                            letterSpacing: 0.3)),
                                  ),
                                ]),
                              ),
                              // Table rows
                              Expanded(
                                child: ListView.separated(
                                  itemCount: _entries.length,
                                  separatorBuilder: (_, __) => Divider(
                                      height: 1, color: borderColor),
                                  itemBuilder: (context, i) {
                                    final entry = _entries[i];
                                    return Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 20, vertical: 12),
                                      child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            SizedBox(
                                              width: 170,
                                              child: Text(
                                                _formatDate(
                                                    entry.createdAt),
                                                style: TextStyle(
                                                    fontSize: 11.5,
                                                    color: subColor,
                                                    fontFamily:
                                                        'monospace'),
                                              ),
                                            ),
                                            SizedBox(
                                              width: 120,
                                              child: Text(
                                                entry.adminName ??
                                                    entry.adminEmail ??
                                                    '—',
                                                style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight:
                                                        FontWeight.w600,
                                                    color: textColor),
                                                maxLines: 2,
                                                overflow:
                                                    TextOverflow.ellipsis,
                                              ),
                                            ),
                                            SizedBox(
                                              width: 200,
                                              child: Container(
                                                padding: const EdgeInsets
                                                    .symmetric(
                                                    horizontal: 8,
                                                    vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: isDark
                                                      ? AppTheme
                                                          .iconBadgeGoldDark
                                                      : AppTheme
                                                          .iconBadgeGoldLight,
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          6),
                                                ),
                                                child: Text(
                                                  entry.action,
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    fontWeight:
                                                        FontWeight.w800,
                                                    color:
                                                        AppTheme.primaryGold,
                                                    letterSpacing: 0.3,
                                                  ),
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Text(
                                                entry.details ?? '—',
                                                style: TextStyle(
                                                    fontSize: 12,
                                                    color: subColor,
                                                    height: 1.4),
                                                maxLines: 3,
                                                overflow:
                                                    TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ]),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _OwnerNavItem — immutable nav definition
// ─────────────────────────────────────────────────────────────────────────────

class _OwnerNavItem {
  const _OwnerNavItem({
    required this.title,
    required this.icon,
    required this.index,
  });

  final String title;
  final IconData icon;
  final int index;
}

// ─────────────────────────────────────────────────────────────────────────────
// _SidebarTile — reusable sidebar nav tile
// ─────────────────────────────────────────────────────────────────────────────

class _SidebarTile extends StatelessWidget {
  const _SidebarTile({
    required this.icon,
    required this.title,
    required this.isSelected,
    required this.isCollapsed,
    required this.onTap,
    this.isLogout = false,
  });

  final IconData icon;
  final String title;
  final bool isSelected;
  final bool isCollapsed;
  final VoidCallback onTap;
  final bool isLogout;

  @override
  Widget build(BuildContext context) {
    final iconColor = isLogout
        ? AppTheme.sidebarLogoutText
        : isSelected
            ? const Color(0xFF1F1500)
            : Colors.white70;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        hoverColor: isLogout
            ? AppTheme.sidebarLogoutText.withValues(alpha: 0.12)
            : Colors.white.withValues(alpha: 0.08),
        splashColor: AppTheme.primaryGold.withValues(alpha: 0.2),
        highlightColor: Colors.transparent,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: isCollapsed ? 0 : 14,
            vertical: 11,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: isSelected && !isLogout
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppTheme.primaryGold, AppTheme.primaryGoldDeep],
                  )
                : null,
          ),
          child: isCollapsed
              ? Center(
                  child: Tooltip(
                    message: title,
                    child: Icon(icon, size: 22, color: iconColor),
                  ),
                )
              : Row(
                  children: [
                    Icon(icon, size: 20, color: iconColor),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isSelected
                              ? FontWeight.w800
                              : FontWeight.w500,
                          color: iconColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
