import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_database/firebase_database.dart';
import '../services/auth_service.dart';
import '../services/supabase_notification_service.dart';
import '../core/permissions/admin_capabilities.dart';
import '../core/theme/app_theme.dart';
import 'login_page.dart';
import 'dashboard_page.dart';
import 'products_page.dart';
import 'production_page.dart';
import 'inventory_page.dart';
import 'orders_page.dart';
import 'sales_page.dart';
import 'suppliers_page.dart';
import 'reports_page.dart';
import 'notifications_page.dart';
import 'customers_page.dart';
import 'messages_page.dart';
import 'feedback_page.dart';
import 'pickup_qr_scanner_page.dart';
import 'work_queue_page.dart';
// manage_accounts_page.dart is intentionally NOT imported here.
// ManageAccountsPage is kept for Phase 5 provisioning but is not routed
// through either dashboard panel.

class MainDashboardPage extends StatefulWidget {
  final AuthSession session;

  const MainDashboardPage({super.key, required this.session});

  @override
  State<MainDashboardPage> createState() => _MainDashboardPageState();
}

class _MainDashboardPageState extends State<MainDashboardPage> {
  int _selectedIndex = 0;
  bool? _isSidebarCollapsed;
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  static const String _storageKey = 'admin_selected_tab';

  late final List<Map<String, dynamic>> _allNavItems;
  late final List<Map<String, dynamic>> _visibleNavItems;

  @override
  void initState() {
    super.initState();
    // ── Navigation Items Order ───────────────────────────────────────────
    // Dashboard is placed first at the top for both Owner and Co-Admin.
    // Work Queue follows immediately for operational staff.
    _allNavItems = [
      {'title': 'Dashboard', 'icon': Icons.grid_view_outlined, 'page': 0},
      {
        'title': 'Work Queue',
        'icon': Icons.checklist_rounded,
        'page': 20,
        'coAdminOnly': true, // Co-Admin only — monitoring Owner has a dashboard
      },
      {'title': 'Orders', 'icon': Icons.shopping_bag_outlined, 'page': 1},
      {'title': 'Production', 'icon': Icons.factory_outlined, 'page': 4},
      {'title': 'Inventory', 'icon': Icons.inventory_2_outlined, 'page': 2},
      {
        'title': 'Pickup QR Scanner',
        'icon': Icons.qr_code_scanner_outlined,
        'page': 12,
        'coAdminOnly': true,
      },
      {'title': 'Messages', 'icon': Icons.message_outlined, 'page': 6},
      {'title': 'Customers', 'icon': Icons.people_outline, 'page': 5},
      {'title': 'Products', 'icon': Icons.hive_outlined, 'page': 3},
      {'title': 'Suppliers', 'icon': Icons.local_shipping_outlined, 'page': 8},
      {'title': 'Sales', 'icon': Icons.monetization_on_outlined, 'page': 7},
      {'title': 'Reports', 'icon': Icons.bar_chart_outlined, 'page': 9},
      {
        'title': 'Notifications',
        'icon': Icons.notifications_none_outlined,
        'page': 10,
      },
      {'title': 'Feedback', 'icon': Icons.reviews_outlined, 'page': 11},
    ];

    // Filter items based on role capabilities.
    final caps = RoleCapabilities.forRole(widget.session.role);
    _visibleNavItems = _allNavItems.where((item) {
      // Pickup QR Scanner: Co-Admin only (canConfirmPickup).
      if (item['coAdminOnly'] == true) {
        return caps.canConfirmPickup;
      }
      return true;
    }).toList();

    _loadSelectedTab();
  }

  Future<void> _loadSelectedTab() async {
    final prefs = await SharedPreferences.getInstance();
    int savedIndex = prefs.getInt(_storageKey) ?? 0;

    final isAllowed = _visibleNavItems.any(
      (item) => item['page'] == savedIndex,
    );
    if (!isAllowed) {
      savedIndex = 0;
    }

    setState(() {
      _selectedIndex = savedIndex;
    });
  }

  Future<void> _setSelectedTab(int index) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_storageKey, index);
    setState(() {
      _selectedIndex = index;
    });
  }

  Widget _compactDrawer() {
    return SafeArea(
      child: Material(
        color: AppTheme.sidebarBg,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 24, 14, 18),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(14, 0, 14, 20),
              child: Text(
                'Honeybee Center\nAdmin Panel',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  height: 1.4,
                ),
              ),
            ),
            ...List.generate(_visibleNavItems.length, (index) {
              final item = _visibleNavItems[index];
              final isSelected = _selectedIndex == item['page'];
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: _NavTile(
                  icon: item['icon'],
                  title: item['title'],
                  isSelected: isSelected,
                  onTap: () {
                    _setSelectedTab(item['page']);
                    Navigator.of(context).pop();
                  },
                ),
              );
            }),
            const Divider(color: Colors.white24, height: 28),
            _NavTile(
              icon: Icons.logout_rounded,
              title: 'Logout',
              isSelected: false,
              isLogout: true,
              onTap: () {
                Navigator.of(context).pop();
                _onLogout();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebar({required bool isAutoCollapsed, bool isDark = false}) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeInOutCubic,
      width: isAutoCollapsed ? 76 : 264,
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: AppTheme.sidebarBg,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppTheme.sidebarBorder, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.35 : 0.08),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isAutoCollapsed ? 12 : 18,
            ),
            child: Row(
              mainAxisAlignment: isAutoCollapsed
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.spaceBetween,
              children: [
                if (!isAutoCollapsed) ...[
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
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x33F59E0B),
                              blurRadius: 8,
                              offset: Offset(0, 2),
                            ),
                          ],
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
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: -0.2,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Admin Panel',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFC7AA76),
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
                Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    hoverColor: Colors.white.withOpacity(0.08),
                    onTap: () {
                      setState(() {
                        _isSidebarCollapsed = !isAutoCollapsed;
                      });
                    },
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.04),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.08),
                        ),
                      ),
                      child: Icon(
                        isAutoCollapsed
                            ? Icons.menu_open_rounded
                            : Icons.menu_rounded,
                        color: AppTheme.primaryGold,
                        size: 19,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Expanded(
            child: ListView.separated(
              padding: EdgeInsets.symmetric(
                horizontal: isAutoCollapsed ? 10 : 14,
                vertical: 4,
              ),
              itemCount: _visibleNavItems.length,
              separatorBuilder: (_, __) => const SizedBox(height: 4),
              itemBuilder: (context, index) {
                final item = _visibleNavItems[index];
                return _NavTile(
                  icon: item['icon'],
                  title: item['title'],
                  isSelected: _selectedIndex == item['page'],
                  isCollapsed: isAutoCollapsed,
                  onTap: () => _setSelectedTab(item['page']),
                );
              },
            ),
          ),
          Divider(
            color: AppTheme.sidebarDivider,
            indent: isAutoCollapsed ? 12 : 20,
            endIndent: isAutoCollapsed ? 12 : 20,
            height: 1,
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              isAutoCollapsed ? 10 : 14,
              10,
              isAutoCollapsed ? 10 : 14,
              14,
            ),
            child: _NavTile(
              icon: Icons.logout_rounded,
              title: 'Logout',
              isSelected: false,
              isCollapsed: isAutoCollapsed,
              onTap: _onLogout,
              isLogout: true,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onLogout() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('No'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Yes, log out'),
          ),
        ],
      ),
    );
    if (shouldLogout != true || !mounted) return;

    try {
      await AuthService().signOut();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storageKey);
    } catch (error) {
      debugPrint('[MainDashboardPage] Logout failed: $error');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not log out: $error')));
      }
      return;
    }
    if (!mounted) return;
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => const LoginPage()));
  }

  Widget _widgetForIndex(int index) {
    switch (index) {
      case 0:
        return DashboardPage(session: widget.session);
      case 1:
        return OrdersPage(session: widget.session);
      case 2:
        return InventoryPage(session: widget.session);
      case 3:
        return ProductsPage(session: widget.session);
      case 4:
        return ProductionPage(session: widget.session);
      case 5:
        return CustomersPage(session: widget.session);
      case 6:
        return MessagesPage(session: widget.session);
      case 7:
        return SalesPage(session: widget.session);
      case 8:
        return SuppliersPage(session: widget.session);
      case 9:
        return ReportsPage(session: widget.session);
      case 10:
        return NotificationsPage(
          session: widget.session,
          onNavigateTab: _setSelectedTab,
        );
      case 11:
        return FeedbackPage(session: widget.session);
      case 12:
        return PickupQrScannerPage(session: widget.session);
      case 20:
        return WorkQueuePage(
          session: widget.session,
          onNavigateTab: _setSelectedTab,
        );
      // case 13 (Manage Accounts) removed — no longer in either panel.
      // ManageAccountsPage is kept in the codebase for Phase 5 provisioning
      // but is not reachable through the dashboard navigation.
      default:
        return DashboardPage(session: widget.session);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isAutoCollapsed = _isSidebarCollapsed ?? (screenWidth < 1100);
    final isCompact = screenWidth < 900;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TopNavBar(
          title:
              _allNavItems.firstWhere(
                    (item) => item['page'] == _selectedIndex,
                    orElse: () => {'title': 'Honeybee Center'},
                  )['title']
                  as String,
          session: widget.session,
          compact: isCompact,
          onNavigateTab: _setSelectedTab,
          onMenu: isCompact
              ? () => _scaffoldKey.currentState?.openDrawer()
              : null,
          onToggleSidebar: () {
            if (isCompact) {
              _scaffoldKey.currentState?.openDrawer();
            } else {
              setState(() {
                _isSidebarCollapsed = !isAutoCollapsed;
              });
            }
          },
          isSidebarCollapsed: isAutoCollapsed,
        ),
        Expanded(child: _widgetForIndex(_selectedIndex)),
      ],
    );

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppTheme.pageBackground(isDark),
      drawer: isCompact ? Drawer(child: _compactDrawer()) : null,
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
                      isAutoCollapsed: isAutoCollapsed,
                      isDark: isDark,
                    ),
                    const SizedBox(width: 16),
                    Expanded(child: content),
                  ],
                ),
        ),
      ),
    );
  }
}

/*
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 22),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppTheme.sidebarBrandBg,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppTheme.sidebarBrandRing,
                            ),
                          ),
                          child: const Icon(
                            Icons.hive_rounded,
                            color: AppTheme.primaryGold,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Honeybee Center',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Admin Panel',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF9A9080),
                                  letterSpacing: 0.1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 2,
                      ),
                      itemCount: _visibleNavItems.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 4),
                      itemBuilder: (context, index) {
                        final item = _visibleNavItems[index];
                        final isSelected = _selectedIndex == item['page'];
                        return _NavTile(
                          icon: item['icon'],
                          title: item['title'],
                          isSelected: isSelected,
                          onTap: () => _setSelectedTab(item['page']),
                        );
                      },
                    ),
                  ),
                  Divider(
                    color: AppTheme.sidebarDivider,
                    indent: 22,
                    endIndent: 22,
                    height: 1,
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
                    child: _NavTile(
                      icon: Icons.logout_rounded,
                      title: 'Logout',
                      isSelected: false,
                      onTap: _onLogout,
                      isLogout: true,
                    ),
                  ),
                ],
              ),
            ),
            // ── Main Content Area ───────────────────────────────────────
            // Fills all remaining horizontal space. Header + current page
            // sit directly on the page background with NO outer max-width,
            // centered wrapper, or inner-sized container.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _TopNavBar(
                    title: _allNavItems[_selectedIndex]['title'],
                    session: widget.session,
                  ),
                  Expanded(
                    child: SizedBox(
                      width: double.infinity,
                      child: _widgetForIndex(_selectedIndex),
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
}*/

class _TopNavBar extends StatefulWidget {
  final String title;
  final AuthSession session;
  final bool compact;
  final VoidCallback? onMenu;
  final VoidCallback? onToggleSidebar;
  final bool isSidebarCollapsed;
  final void Function(int tabIndex)? onNavigateTab;

  const _TopNavBar({
    required this.title,
    required this.session,
    this.compact = false,
    this.onMenu,
    this.onToggleSidebar,
    this.isSidebarCollapsed = false,
    this.onNavigateTab,
  });

  @override
  State<_TopNavBar> createState() => _TopNavBarState();
}

class _TopNavBarState extends State<_TopNavBar> {
  final _searchController = TextEditingController();
  final GlobalSearchService _searchService = GlobalSearchService();
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;
  OverlayEntry? _overlayEntry;
  final LayerLink _layerLink = LayerLink();

  @override
  void dispose() {
    _searchController.dispose();
    _removeOverlay();
    super.dispose();
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _onSearchChanged(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      _removeOverlay();
      return;
    }

    setState(() => _isSearching = true);
    final results = await _searchService.searchAll(query);
    if (!mounted) return;

    setState(() {
      _searchResults = results;
      _isSearching = false;
    });

    _showOverlay();
  }

  void _showOverlay() {
    _removeOverlay();
    if (_searchResults.isEmpty) return;

    final overlay = Overlay.of(context);
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    _overlayEntry = OverlayEntry(
      builder: (context) => CompositedTransformFollower(
        link: _layerLink,
        showWhenUnlinked: false,
        offset: const Offset(-60, 45),
        child: SizedBox(
          width: 320,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            color: AppTheme.panelColor(isDark),
            child: Container(
              constraints: const BoxConstraints(maxHeight: 350),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.panelBorder(isDark)),
                boxShadow: AppTheme.softShadow(isDark),
              ),
              child: ListView.separated(
                padding: const EdgeInsets.all(8),
                shrinkWrap: true,
                itemCount: _searchResults.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = _searchResults[index];
                  return Material(
                    type: MaterialType.transparency,
                    child: ListTile(
                      leading: Icon(
                        item['icon'],
                        color: const Color(0xFFD9A441),
                        size: 20,
                      ),
                      title: Text(
                        item['title'],
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      subtitle: Text(
                        '${item['type']} • ${item['subtitle']}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                      ),
                      onTap: () {
                        _removeOverlay();
                        _searchController.clear();
                        showDialog(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: Text('${item['type']} Details'),
                            content: SizedBox(
                              width: 400,
                              child: SingleChildScrollView(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: (item['data'] as Map).entries
                                      .map<Widget>((e) {
                                        return Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 8.0,
                                          ),
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                '${e.key}: ',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12,
                                                ),
                                              ),
                                              Expanded(
                                                child: Text(
                                                  '${e.value}',
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.grey,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      })
                                      .toList(),
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
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );

    overlay.insert(_overlayEntry!);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final roleName = widget.session.role == UserRole.mainAdmin
        ? 'System Owner'
        : 'Co-Admin / Store Manager';
    final initial = widget.session.name.isNotEmpty
        ? widget.session.name[0].toUpperCase()
        : 'A';
    final nameParts = widget.session.name.trim().split(' ');
    final displayName = nameParts.isEmpty ? 'Admin' : nameParts.first;
    final subColor = isDark
        ? AppTheme.textDarkSecondary
        : AppTheme.subtitleLight(isDark);
    final textColor = isDark ? AppTheme.textDark : AppTheme.textLight;
    final searchBorder = AppTheme.panelBorder(isDark);
    final searchFill = AppTheme.panelColor(isDark);
    final headerFill = AppTheme.pageBackground(isDark);

    if (widget.compact) {
      return Container(
        height: 72,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        color: headerFill,
        child: Row(
          children: [
            IconButton(
              onPressed: widget.onMenu,
              icon: Icon(Icons.menu_rounded, color: textColor),
              tooltip: 'Open navigation',
            ),
            Expanded(
              child: Text(
                widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: textColor,
                ),
              ),
            ),
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: searchFill,
                shape: BoxShape.circle,
                border: Border.all(color: searchBorder),
              ),
              child: IconButton(
                onPressed: () => ThemeNotifier.instance.toggleTheme(),
                icon: Icon(
                  ThemeNotifier.instance.themeMode == ThemeMode.dark
                      ? Icons.wb_sunny_outlined
                      : Icons.dark_mode_outlined,
                  color: textColor,
                  size: 19,
                ),
                padding: EdgeInsets.zero,
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 42,
              height: 42,
              child: _NotificationBell(
                session: widget.session,
                onNavigateTab: widget.onNavigateTab,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      height: 76,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      color: headerFill,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final bool showWelcome = width > 750;
          final bool showFullProfile = width > 580;

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (widget.onToggleSidebar != null) ...[
                Material(
                  color: Colors.transparent,
                  child: IconButton(
                    onPressed: widget.onToggleSidebar,
                    icon: Icon(
                      widget.isSidebarCollapsed
                          ? Icons.menu_open_rounded
                          : Icons.menu_rounded,
                      color: textColor,
                      size: 22,
                    ),
                    tooltip: widget.isSidebarCollapsed
                        ? 'Expand navigation'
                        : 'Collapse navigation',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 40,
                      minHeight: 40,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],

              if (showWelcome) ...[
                // Welcome / brand column
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'WELCOME BACK,',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0,
                        color: subColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          displayName,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: textColor,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.hive_rounded,
                          color: AppTheme.primaryGold,
                          size: 16,
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(width: 20),
              ],

              // Search bar — flexible middle zone
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: CompositedTransformTarget(
                    link: _layerLink,
                    child: Container(
                      height: 44,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: searchFill,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: searchBorder),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.search_rounded, size: 18, color: subColor),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              onChanged: _onSearchChanged,
                              style: TextStyle(
                                fontSize: 13,
                                color: textColor,
                                fontWeight: FontWeight.w500,
                              ),
                              decoration: InputDecoration(
                                hintText: width > 600
                                    ? 'Search orders, customers, products...'
                                    : 'Search...',
                                hintStyle: TextStyle(
                                  fontSize: 12.5,
                                  color: subColor,
                                  fontWeight: FontWeight.w500,
                                ),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          ),
                          if (_isSearching)
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppTheme.primaryGold,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),

              // Theme toggle
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: searchFill,
                  border: Border.all(color: searchBorder),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  onPressed: () {
                    ThemeNotifier.instance.toggleTheme();
                  },
                  icon: Icon(
                    ThemeNotifier.instance.themeMode == ThemeMode.dark
                        ? Icons.wb_sunny_outlined
                        : Icons.dark_mode_outlined,
                    color: textColor,
                    size: 19,
                  ),
                  tooltip: 'Toggle Theme Mode',
                  padding: EdgeInsets.zero,
                ),
              ),
              const SizedBox(width: 10),

              // Notifications bell
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: searchFill,
                  border: Border.all(color: searchBorder),
                  shape: BoxShape.circle,
                ),
                child: _NotificationBell(
                  session: widget.session,
                  onNavigateTab: widget.onNavigateTab,
                ),
              ),
              const SizedBox(width: 12),

              // Profile chip (adaptive width)
              Container(
                height: 48,
                padding: EdgeInsets.fromLTRB(6, 4, showFullProfile ? 14 : 6, 4),
                decoration: BoxDecoration(
                  color: searchFill,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: searchBorder),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFFE2B04A), Color(0xFFC89127)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          initial,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF1A1300),
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                    if (showFullProfile) ...[
                      const SizedBox(width: 8),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 120),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.session.name.toUpperCase(),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                color: textColor,
                                letterSpacing: 0.15,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 1),
                            Text(
                              roleName,
                              style: TextStyle(
                                fontSize: 9.5,
                                color: subColor,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool isSelected;
  final VoidCallback onTap;
  final bool isLogout;
  final bool isCollapsed;

  const _NavTile({
    required this.icon,
    required this.title,
    required this.isSelected,
    required this.onTap,
    this.isLogout = false,
    this.isCollapsed = false,
  });

  @override
  Widget build(BuildContext context) {
    final tile = Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        hoverColor: isLogout
            ? AppTheme.sidebarLogoutText.withValues(alpha: 0.12)
            : (isSelected
                  ? Colors.transparent
                  : Colors.white.withValues(alpha: 0.08)),
        splashColor: AppTheme.primaryGold.withValues(alpha: 0.2),
        highlightColor: Colors.transparent,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: isCollapsed ? 12 : 14,
            vertical: 11,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: isSelected
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppTheme.primaryGold, AppTheme.primaryGoldDeep],
                  )
                : null,
            border: Border.all(
              color: isSelected
                  ? AppTheme.primaryGold.withValues(alpha: 0.4)
                  : Colors.transparent,
              width: 1,
            ),
            boxShadow: isSelected
                ? const [
                    BoxShadow(
                      color: Color(0x66000000),
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                    BoxShadow(
                      color: Color(0x40F59E0B),
                      blurRadius: 12,
                      offset: Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: isCollapsed
                ? MainAxisAlignment.center
                : MainAxisAlignment.start,
            children: [
              Icon(
                icon,
                color: isSelected
                    ? const Color(0xFF1A1300)
                    : isLogout
                    ? AppTheme.sidebarLogoutText
                    : AppTheme.sidebarNavIcon,
                size: 20,
              ),
              if (!isCollapsed) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: isSelected
                          ? FontWeight.w800
                          : FontWeight.w600,
                      color: isSelected
                          ? const Color(0xFF1A1300)
                          : isLogout
                          ? AppTheme.sidebarLogoutText
                          : AppTheme.sidebarNavText,
                      letterSpacing: 0.1,
                    ),
                  ),
                ),
                if (isSelected)
                  const Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 12,
                    color: Color(0xFF3E2800),
                  ),
              ],
            ],
          ),
        ),
      ),
    );

    if (isCollapsed) {
      return Tooltip(
        message: title,
        waitDuration: const Duration(milliseconds: 300),
        child: tile,
      );
    }
    return tile;
  }
}

class GlobalSearchService {
  DatabaseReference get _db => FirebaseDatabase.instance.ref();

  Future<List<Map<String, dynamic>>> searchAll(String query) async {
    if (query.trim().isEmpty) return [];
    final q = query.toLowerCase().trim();
    final List<Map<String, dynamic>> results = [];

    try {
      final futures = await Future.wait([
        _db.child('orders').get(),
        _db.child('customers').get(),
        _db.child('products').get(),
        _db.child('production_batches').get(),
        _db.child('suppliers').get(),
      ]);

      final ordersSnap = futures[0];
      final customersSnap = futures[1];
      final productsSnap = futures[2];
      final productionSnap = futures[3];
      final suppliersSnap = futures[4];

      if (ordersSnap.exists && ordersSnap.value is Map) {
        (ordersSnap.value as Map).forEach((k, v) {
          final data = Map<String, dynamic>.from(v as Map);
          final id = k.toString();
          final cust = (data['customerName'] ?? '').toString();
          final ref = (data['orderReference'] ?? '').toString();
          if (id.toLowerCase().contains(q) ||
              cust.toLowerCase().contains(q) ||
              ref.toLowerCase().contains(q)) {
            results.add({
              'type': 'Order',
              'title':
                  'Order #${id.length > 8 ? id.substring(0, 8).toUpperCase() : id.toUpperCase()}',
              'subtitle':
                  'Customer: $cust • ₱${data['totalAmount'] ?? data['amount'] ?? 0}',
              'icon': Icons.shopping_bag_outlined,
              'data': data,
              'id': id,
            });
          }
        });
      }

      if (customersSnap.exists && customersSnap.value is Map) {
        (customersSnap.value as Map).forEach((k, v) {
          final data = Map<String, dynamic>.from(v as Map);
          final name = (data['name'] ?? '').toString();
          final email = (data['email'] ?? '').toString();
          final contact = (data['contact'] ?? data['phone'] ?? '').toString();
          if (name.toLowerCase().contains(q) ||
              email.toLowerCase().contains(q) ||
              contact.toLowerCase().contains(q)) {
            results.add({
              'type': 'Customer',
              'title': name,
              'subtitle': 'Email: $email',
              'icon': Icons.person_outline,
              'data': data,
              'id': k,
            });
          }
        });
      }

      if (productsSnap.exists && productsSnap.value is Map) {
        (productsSnap.value as Map).forEach((k, v) {
          final data = Map<String, dynamic>.from(v as Map);
          final name = (data['name'] ?? '').toString();
          final variety = (data['variety'] ?? '').toString();
          if (name.toLowerCase().contains(q) ||
              variety.toLowerCase().contains(q)) {
            results.add({
              'type': 'Product',
              'title': '$name ($variety)',
              'subtitle': 'Honey Product',
              'icon': Icons.hive_outlined,
              'data': data,
              'id': k,
            });
          }
        });
      }

      if (productionSnap.exists && productionSnap.value is Map) {
        (productionSnap.value as Map).forEach((k, v) {
          final data = Map<String, dynamic>.from(v as Map);
          final id = k.toString();
          final bundle = (data['bundleName'] ?? data['productName'] ?? '')
              .toString();
          if (id.toLowerCase().contains(q) ||
              bundle.toLowerCase().contains(q)) {
            results.add({
              'type': 'Production Batch',
              'title': bundle.isNotEmpty ? bundle : 'Batch #$id',
              'subtitle': 'Status: ${data['status'] ?? 'Planned'}',
              'icon': Icons.factory_outlined,
              'data': data,
              'id': id,
            });
          }
        });
      }

      if (suppliersSnap.exists && suppliersSnap.value is Map) {
        (suppliersSnap.value as Map).forEach((k, v) {
          final data = Map<String, dynamic>.from(v as Map);
          final name = (data['name'] ?? data['supplierName'] ?? '').toString();
          final contact = (data['contact'] ?? '').toString();
          if (name.toLowerCase().contains(q) ||
              contact.toLowerCase().contains(q)) {
            results.add({
              'type': 'Supplier',
              'title': name,
              'subtitle': 'Contact: $contact',
              'icon': Icons.local_shipping_outlined,
              'data': data,
              'id': k,
            });
          }
        });
      }
    } catch (e) {
      print('[DEBUG] GlobalSearch error: $e');
    }

    return results;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _NotificationBell — real-time bell with unread badge + dropdown panel
// ─────────────────────────────────────────────────────────────────────────────
class _NotificationBell extends StatefulWidget {
  final AuthSession session;
  final void Function(int tabIndex)? onNavigateTab;
  const _NotificationBell({required this.session, this.onNavigateTab});

  @override
  State<_NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<_NotificationBell>
    with SingleTickerProviderStateMixin {
  final _notifications = SupabaseNotificationService.instance;
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlay;
  bool _open = false;

  late final AnimationController _animCtrl;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _scaleAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutBack);
  }

  @override
  void dispose() {
    _closePanel();
    _animCtrl.dispose();
    super.dispose();
  }

  void _togglePanel() {
    if (_open) {
      _closePanel();
    } else {
      _openPanel();
    }
  }

  void _openPanel() {
    setState(() => _open = true);
    final overlay = Overlay.of(context);
    _overlay = OverlayEntry(
      builder: (_) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _closePanel,
        child: Stack(
          children: [
            Positioned.fill(child: Container(color: Colors.transparent)),
            CompositedTransformFollower(
              link: _layerLink,
              showWhenUnlinked: false,
              offset: const Offset(-310, 48),
              child: ScaleTransition(
                scale: _scaleAnim,
                alignment: Alignment.topRight,
                child: _NotificationPanel(
                  notifications: _notifications,
                  onClose: _closePanel,
                  onNavigateTab: widget.onNavigateTab,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    overlay.insert(_overlay!);
    _animCtrl.forward(from: 0);
  }

  void _closePanel() {
    _animCtrl.reverse().then((_) {
      _overlay?.remove();
      _overlay = null;
      if (mounted) setState(() => _open = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _notifications.notificationsStream,
        builder: (context, snapshot) {
          final unread =
              snapshot.data
                  ?.where(
                    (notification) =>
                        notification['isRead'] != true &&
                        notification['isArchived'] != true,
                  )
                  .length ??
              0;

          return Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                onPressed: _togglePanel,
                tooltip: 'Notifications',
                icon: Icon(
                  _open
                      ? Icons.notifications_rounded
                      : Icons.notifications_none_rounded,
                  color: _open
                      ? const Color(0xFFD9A441)
                      : Theme.of(context).colorScheme.onSurface,
                  size: 22,
                ),
              ),
              if (unread > 0)
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    decoration: const BoxDecoration(
                      color: Color(0xFFE53935),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      unread > 99 ? '99+' : '$unread',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        height: 1,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _NotificationPanel — the dropdown card
// ─────────────────────────────────────────────────────────────────────────────
class _NotificationPanel extends StatelessWidget {
  final SupabaseNotificationService notifications;
  final VoidCallback onClose;
  final void Function(int tabIndex)? onNavigateTab;

  const _NotificationPanel({
    required this.notifications,
    required this.onClose,
    this.onNavigateTab,
  });

  Future<void> _runNotificationAction(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (error) {
      debugPrint('[NotificationPanel] Notification action failed: $error');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Notification update failed: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      elevation: 16,
      borderRadius: BorderRadius.circular(16),
      color: isDark ? AppTheme.surfaceDark : Colors.white,
      child: Container(
        width: 360,
        constraints: const BoxConstraints(maxHeight: 500),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? AppTheme.borderDarkAlt : const Color(0xFFEEEEEE),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              child: Row(
                children: [
                  const Text(
                    'Notifications',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => _runNotificationAction(
                      context,
                      notifications.markAllAsRead,
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      'Mark all read',
                      style: TextStyle(fontSize: 12, color: Color(0xFFD9A441)),
                    ),
                  ),
                  IconButton(
                    onPressed: onClose,
                    icon: const Icon(Icons.close_rounded, size: 18),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    color: Colors.grey,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Notification list
            Flexible(
              child: StreamBuilder<List<Map<String, dynamic>>>(
                stream: notifications.notificationsStream,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Unable to load notifications: ${snapshot.error}',
                        style: const TextStyle(color: Colors.red),
                      ),
                    );
                  }
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }

                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.notifications_off_outlined,
                              size: 40,
                              color: Colors.grey,
                            ),
                            SizedBox(height: 12),
                            Text(
                              'No notifications yet.',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  // Show max 8 in the panel
                  final recent = snapshot.data!.take(8).toList();

                  return ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: recent.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, indent: 20, endIndent: 20),
                    itemBuilder: (context, i) {
                      final n = recent[i];
                      final isRead = n['isRead'] == true;
                      final ts = n['timestamp'] as int? ?? 0;
                      final time = _timeAgo(ts);

                      return InkWell(
                        onTap: () async {
                          await _runNotificationAction(
                            context,
                            () => notifications.markAsRead(n['id'].toString()),
                          );
                          onClose();
                          if (onNavigateTab != null) {
                            final t = (n['type']?.toString() ?? '')
                                .toUpperCase();
                            if (t.contains('ORDER')) {
                              onNavigateTab!(1);
                            } else if (t.contains('STOCK') ||
                                t.contains('DISCREPANCY') ||
                                t.contains('INVENTORY')) {
                              onNavigateTab!(2);
                            } else if (t.contains('PRODUCTION')) {
                              onNavigateTab!(4);
                            } else if (t.contains('MESSAGE') ||
                                t.contains('CHAT')) {
                              onNavigateTab!(6);
                            } else if (t.contains('FEEDBACK') ||
                                t.contains('REVIEW')) {
                              onNavigateTab!(11);
                            }
                          }
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          color: isRead
                              ? Colors.transparent
                              : (isDark
                                    ? AppTheme.backgroundDarkAlt
                                    : const Color(0xFFFFFDF5)),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _typeIcon(
                                n['type']?.toString() ?? '',
                                isDark: isDark,
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            _typeLabel(
                                              n['type']?.toString() ?? '',
                                            ),
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: isRead
                                                  ? FontWeight.w500
                                                  : FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                        Text(
                                          time,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      n['message']?.toString() ?? '',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                        height: 1.4,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              if (!isRead) ...[
                                const SizedBox(width: 8),
                                const CircleAvatar(
                                  radius: 4,
                                  backgroundColor: Color(0xFFD9A441),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),

            // Footer
            const Divider(height: 1),
            InkWell(
              onTap: () {
                onClose();
                if (onNavigateTab != null) {
                  onNavigateTab!(10);
                }
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: const Text(
                  'View All Notifications',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFD9A441),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _typeIcon(String type, {required bool isDark}) {
    IconData icon;
    Color fg;
    Color bg;
    switch (type) {
      case 'LOW_STOCK':
      case 'OUT_OF_STOCK':
        icon = Icons.warning_amber_rounded;
        fg = AppTheme.error;
        bg = isDark ? AppTheme.iconBadgeRoseDark : AppTheme.iconBadgeRoseLight;
        break;
      case 'NEW_SALE':
      case 'NEW_ORDER':
        icon = Icons.shopping_bag_outlined;
        fg = AppTheme.success;
        bg = isDark
            ? AppTheme.iconBadgeGreenDark
            : AppTheme.iconBadgeGreenLight;
        break;
      case 'NEW_CUSTOMER':
        icon = Icons.person_add_alt_1_outlined;
        fg = AppTheme.info;
        bg = isDark ? AppTheme.iconBadgeBlueDark : AppTheme.iconBadgeBlueLight;
        break;
      case 'PRODUCTION_COMPLETED':
        icon = Icons.factory_outlined;
        fg = AppTheme.info;
        bg = isDark ? AppTheme.iconBadgeBlueDark : AppTheme.iconBadgeBlueLight;
        break;
      case 'PAYMENT_VERIFIED':
        icon = Icons.verified_outlined;
        fg = const Color(0xFF0D9488);
        bg = isDark
            ? AppTheme.iconBadgeGreenDark
            : AppTheme.iconBadgeGreenLight;
        break;
      case 'PAYMENT_REJECTED':
        icon = Icons.cancel_outlined;
        fg = AppTheme.error;
        bg = isDark ? AppTheme.iconBadgeRoseDark : AppTheme.iconBadgeRoseLight;
        break;
      case 'SCAN_MISMATCH':
        icon = Icons.qr_code_scanner_outlined;
        fg = AppTheme.warning;
        bg = isDark
            ? AppTheme.iconBadgeAmberDark
            : AppTheme.iconBadgeAmberLight;
        break;
      default:
        icon = Icons.notifications_none_rounded;
        fg = isDark ? AppTheme.textDarkSecondary : AppTheme.textLightSecondary;
        bg = isDark ? AppTheme.backgroundDarkAlt : AppTheme.backgroundLightAlt;
    }

    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Icon(icon, color: fg, size: 18),
    );
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'LOW_STOCK':
        return 'Low Stock Alert';
      case 'OUT_OF_STOCK':
        return 'Out of Stock';
      case 'NEW_SALE':
        return 'New Sale';
      case 'NEW_ORDER':
        return 'New Order';
      case 'NEW_CUSTOMER':
        return 'New Customer';
      case 'PRODUCTION_COMPLETED':
        return 'Production Completed';
      case 'PAYMENT_VERIFIED':
        return 'Payment Verified';
      case 'PAYMENT_REJECTED':
        return 'Payment Rejected';
      case 'SCAN_MISMATCH':
        return 'Scan Mismatch';
      default:
        return 'Notification';
    }
  }

  String _timeAgo(int timestamp) {
    if (timestamp == 0) return '';
    final diff = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(timestamp),
    );
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${(diff.inDays / 7).floor()}w ago';
  }
}
