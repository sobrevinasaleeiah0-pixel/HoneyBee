import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../core/theme/app_theme.dart';
import '../widgets/status_badge.dart';
import 'login_page.dart';
import 'manage_accounts_page.dart';
import 'reports_page.dart';

Color _iconBadgeBg(Color accent, bool isDark) {
  if (accent == AppTheme.accentGold)
    return isDark ? AppTheme.iconBadgeGoldDark : AppTheme.iconBadgeGoldLight;
  if (accent == AppTheme.accentBlue)
    return isDark ? AppTheme.iconBadgeBlueDark : AppTheme.iconBadgeBlueLight;
  if (accent == AppTheme.accentGreen)
    return isDark ? AppTheme.iconBadgeGreenDark : AppTheme.iconBadgeGreenLight;
  if (accent == AppTheme.accentPurple)
    return isDark
        ? AppTheme.iconBadgePurpleDark
        : AppTheme.iconBadgePurpleLight;
  if (accent == AppTheme.accentRose)
    return isDark ? AppTheme.iconBadgeRoseDark : AppTheme.iconBadgeRoseLight;
  if (accent == AppTheme.warning)
    return isDark ? AppTheme.iconBadgeAmberDark : AppTheme.iconBadgeAmberLight;
  if (accent == AppTheme.success)
    return isDark ? AppTheme.iconBadgeGreenDark : AppTheme.iconBadgeGreenLight;
  if (accent == AppTheme.error)
    return isDark ? AppTheme.badgeRedBgDark : AppTheme.badgeRedBgLight;
  if (accent == AppTheme.info)
    return isDark ? AppTheme.iconBadgeBlueDark : AppTheme.iconBadgeBlueLight;
  return isDark ? AppTheme.iconBadgeGoldDark : AppTheme.iconBadgeGoldLight;
}

Color _pillBg(Color accent, bool isDark) {
  if (accent == AppTheme.success)
    return isDark ? AppTheme.badgeGreenBgDark : AppTheme.badgeGreenBgLight;
  if (accent == AppTheme.warning)
    return isDark ? AppTheme.badgeGoldBgDark : AppTheme.badgeGoldBgLight;
  if (accent == AppTheme.error)
    return isDark ? AppTheme.badgeRedBgDark : AppTheme.badgeRedBgLight;
  if (accent == AppTheme.accentGold)
    return isDark ? AppTheme.badgeGoldBgDark : AppTheme.badgeGoldBgLight;
  if (accent == AppTheme.accentBlue)
    return isDark ? AppTheme.badgeBlueBgDark : AppTheme.badgeBlueBgLight;
  if (accent == AppTheme.accentGreen)
    return isDark ? AppTheme.badgeGreenBgDark : AppTheme.badgeGreenBgLight;
  if (accent == AppTheme.accentPurple)
    return isDark
        ? AppTheme.iconBadgePurpleDark
        : AppTheme.iconBadgePurpleLight;
  if (accent == AppTheme.accentRose)
    return isDark ? AppTheme.iconBadgeRoseDark : AppTheme.iconBadgeRoseLight;
  return isDark ? AppTheme.iconBadgeGoldDark : AppTheme.iconBadgeGoldLight;
}

class OwnerPanel extends StatefulWidget {
  final AuthSession session;

  const OwnerPanel({super.key, required this.session});

  @override
  State<OwnerPanel> createState() => _OwnerPanelState();
}

class _OwnerPanelState extends State<OwnerPanel> {
  int _selectedIndex = 0;
  bool? _isSidebarCollapsed;
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _titles = const [
    'Dashboard',
    'Orders Overview',
    'Inventory Overview',
    'Production Overview',
    'Sales',
    'Reports',
    'Activity Logs',
    'Manage Accounts',
  ];

  Future<void> _logout() async {
    await AuthService().signOut();
    if (!mounted) return;
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => const LoginPage()));
  }

  Widget _widgetForIndex(int index) {
    switch (index) {
      case 0:
        return OwnerDashboardPage(session: widget.session);
      case 1:
        return OwnerOrdersPage(session: widget.session);
      case 2:
        return OwnerInventoryPage(session: widget.session);
      case 3:
        return OwnerProductionPage(session: widget.session);
      case 4:
        return OwnerSalesPage(session: widget.session);
      case 5:
        return ReportsPage(session: widget.session);
      case 6:
        return OwnerActivityPage(session: widget.session);
      case 7:
        return ManageAccountsPage(session: widget.session);
      default:
        return OwnerDashboardPage(session: widget.session);
    }
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
                'Honeybee Center\nOwner Panel',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  height: 1.4,
                ),
              ),
            ),
            ...List.generate(_titles.length, (index) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: _NavTile(
                  icon: _icons[index],
                  title: _titles[index],
                  isSelected: _selectedIndex == index,
                  onTap: () {
                    setState(() => _selectedIndex = index);
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
              onTap: _logout,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    // Default to collapsed on screens < 900 if user hasn't explicitly set preference
    final isAutoCollapsed = _isSidebarCollapsed ?? (screenWidth < 900);
    final isCompact = screenWidth < 900;

    return Scaffold(
      key: _scaffoldKey,
      drawer: isCompact ? Drawer(child: _compactDrawer()) : null,
      backgroundColor: AppTheme.pageBackground(isDark),
      body: Container(
        color: AppTheme.pageBackground(isDark),
        child: Padding(
          padding: EdgeInsets.all(screenWidth < 600 ? 8.0 : 16.0),
          child: Row(
            children: [
              // Sidebar Floating Rounded Container Panel (Collapsible & Automatic Adaptive)
              if (!isCompact)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeInOutCubic,
                  width: isCompact ? 0 : (isAutoCollapsed ? 76 : 264),
                  clipBehavior: Clip.hardEdge,
                  decoration: BoxDecoration(
                    color: AppTheme.sidebarBg,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: AppTheme.sidebarBorder,
                      width: 1.2,
                    ),
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                          itemCount: _titles.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 4),
                          itemBuilder: (context, index) => _NavTile(
                            icon: _icons[index],
                            title: _titles[index],
                            isSelected: _selectedIndex == index,
                            isCollapsed: isAutoCollapsed,
                            onTap: () => setState(() => _selectedIndex = index),
                          ),
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
                          onTap: _logout,
                          isLogout: true,
                        ),
                      ),
                    ],
                  ),
                ),
              if (!isCompact) const SizedBox(width: 16),
              // Main content
              Expanded(
                child: Column(
                  children: [
                    _OwnerHeader(
                      title: _titles[_selectedIndex],
                      session: widget.session,
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
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static const _icons = [
    Icons.grid_view_outlined,
    Icons.shopping_bag_outlined,
    Icons.inventory_2_outlined,
    Icons.factory_outlined,
    Icons.monetization_on_outlined,
    Icons.bar_chart_outlined,
    Icons.history_outlined,
    Icons.admin_panel_settings_outlined,
  ];
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
    return Material(
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
  }
}

class _OwnerHeader extends StatelessWidget {
  final String title;
  final AuthSession session;
  final VoidCallback? onToggleSidebar;
  final bool isSidebarCollapsed;

  const _OwnerHeader({
    required this.title,
    required this.session,
    this.onToggleSidebar,
    this.isSidebarCollapsed = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final initial = session.name.isNotEmpty
        ? session.name[0].toUpperCase()
        : 'O';
    final nameParts = session.name.trim().split(' ');
    final displayName = nameParts.isEmpty ? 'Owner' : nameParts.first;
    final subColor = isDark
        ? AppTheme.subtitleDark(isDark)
        : AppTheme.subtitleLight(isDark);
    final textColor = isDark ? AppTheme.textDark : AppTheme.textLight;
    final searchBorder = isDark ? AppTheme.borderDark : AppTheme.borderLightAlt;
    final searchFill = isDark ? AppTheme.backgroundDarkAlt : Colors.white;
    final headerFill = isDark
        ? AppTheme.backgroundDark
        : AppTheme.backgroundLight;
    final headerBorder = isDark ? AppTheme.borderDark : AppTheme.borderLightAlt;

    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: headerFill,
        border: Border(bottom: BorderSide(color: headerBorder, width: 1)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 650;
          final isVeryCompact = constraints.maxWidth < 450;

          return Row(
            children: [
              if (onToggleSidebar != null &&
                  MediaQuery.sizeOf(context).width < 900) ...[
                IconButton(
                  onPressed: onToggleSidebar,
                  icon: Icon(Icons.menu_rounded, color: textColor),
                  tooltip: 'Open navigation',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 40,
                    minHeight: 40,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              // Title / Welcome Info
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'WELCOME BACK,',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0,
                        color: subColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            displayName,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: textColor,
                              letterSpacing: -0.3,
                            ),
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
              ),

              // Search field (hidden on very small viewports to prevent overflow)
              if (!isCompact) ...[
                const SizedBox(width: 12),
                Flexible(
                  flex: 2,
                  child: Container(
                    height: 38,
                    constraints: const BoxConstraints(maxWidth: 320),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: searchFill,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: searchBorder),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.search_rounded, size: 16, color: subColor),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Search...',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: subColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              const SizedBox(width: 10),

              // Theme Mode Toggle
              Container(
                width: 38,
                height: 38,
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
                    size: 18,
                  ),
                  tooltip: 'Toggle Theme Mode',
                  padding: EdgeInsets.zero,
                ),
              ),

              const SizedBox(width: 10),

              // User avatar & role badge
              Container(
                padding: const EdgeInsets.fromLTRB(5, 5, 14, 5),
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.surfaceDark : Colors.white,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: isDark
                        ? AppTheme.borderDarkAlt
                        : AppTheme.borderLightAlt,
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: isDark
                          ? Colors.black.withValues(alpha: 0.25)
                          : const Color(0x1AE4B043),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [
                                AppTheme.primaryGold,
                                AppTheme.primaryGoldDeep,
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.4),
                              width: 1.2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.primaryGold.withValues(
                                  alpha: 0.35,
                                ),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              initial,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF1F1500),
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          right: -1,
                          bottom: -1,
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: AppTheme.success,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isDark
                                    ? AppTheme.surfaceDark
                                    : Colors.white,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (!isVeryCompact) ...[
                      const SizedBox(width: 10),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 150),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              session.name,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                color: textColor,
                                letterSpacing: -0.2,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
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
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.verified_user_rounded,
                                    size: 9.5,
                                    color: isDark
                                        ? AppTheme.primaryGold
                                        : AppTheme.primaryGoldDeep,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    'MAIN ADMIN',
                                    style: TextStyle(
                                      fontSize: 8.5,
                                      fontWeight: FontWeight.w900,
                                      color: isDark
                                          ? AppTheme.primaryGold
                                          : AppTheme.primaryGoldDeep,
                                      letterSpacing: 0.4,
                                    ),
                                  ),
                                ],
                              ),
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

class OwnerDashboardPage extends StatelessWidget {
  final AuthSession session;
  final _db = DatabaseService();

  OwnerDashboardPage({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DatabaseEvent>(
      stream: _db.getOrdersStream(),
      builder: (context, orderSnapshot) {
        return StreamBuilder<DatabaseEvent>(
          stream: _db.getInventoryStream(),
          builder: (context, inventorySnapshot) {
            return StreamBuilder<DatabaseEvent>(
              stream: _db.getProductsStream(),
              builder: (context, productSnapshot) {
                final orders = _asMap(orderSnapshot.data?.snapshot.value);
                final inventory = _asMap(
                  inventorySnapshot.data?.snapshot.value,
                );
                final products = _asMap(productSnapshot.data?.snapshot.value);
                final totalSales = orders.values
                    .where((o) => o['orderStatus'] == 'Completed')
                    .fold<double>(
                      0,
                      (sum, o) => sum + _number(o['totalAmount']),
                    );
                final orderCount = orders.length;
                final lowStock = _inventoryRows(inventory, products)
                    .where((item) => item['quantity'] <= item['reorderLevel'])
                    .length;
                return ListView(
                  padding: const EdgeInsets.fromLTRB(32, 24, 32, 40),
                  children: [
                    const SizedBox(height: 8),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final cards = [
                          _OwnerStatCard(
                            label: 'Total Sales',
                            value: '₱${totalSales.toStringAsFixed(2)}',
                            accentColor: AppTheme.accentRose,
                            icon: Icons.paid_outlined,
                          ),
                          _OwnerStatCard(
                            label: 'Total Orders',
                            value: '$orderCount',
                            accentColor: AppTheme.accentGold,
                            icon: Icons.shopping_bag_outlined,
                          ),
                          _OwnerStatCard(
                            label: 'Current Inventory',
                            value: '${_inventoryUnits(inventory)} bottles',
                            accentColor: AppTheme.accentGreen,
                            icon: Icons.inventory_2_outlined,
                          ),
                          _OwnerStatCard(
                            label: 'Low Stock Alerts',
                            value: '$lowStock',
                            accentColor: AppTheme.accentPurple,
                            icon: Icons.warning_amber_rounded,
                            isWarning: lowStock > 0,
                          ),
                          _OwnerStatCard(
                            label: 'Production Status',
                            value: 'Live',
                            accentColor: AppTheme.accentBlue,
                            icon: Icons.factory_outlined,
                            isLive: true,
                          ),
                        ];
                        const double gap = 18;
                        const double minCardWidth = 170;
                        final maxWidth = constraints.maxWidth;
                        final cardsPerRow = maxWidth <= 0
                            ? cards.length
                            : ((maxWidth + gap) / (minCardWidth + gap))
                                  .floor()
                                  .clamp(1, cards.length);
                        final cardWidth =
                            ((maxWidth - (cardsPerRow - 1) * gap) / cardsPerRow)
                                .clamp(minCardWidth, double.infinity);

                        return Wrap(
                          spacing: gap,
                          runSpacing: gap,
                          children: cards
                              .map((c) => SizedBox(width: cardWidth, child: c))
                              .toList(),
                        );
                      },
                    ),
                    const SizedBox(height: 28),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final isSingleColumn = constraints.maxWidth < 700;
                        if (isSingleColumn) {
                          return Column(
                            children: [
                              _DashboardSalesCard(orders: orders),
                              const SizedBox(height: 20),
                              _DashboardAlertsCard(
                                inventory: inventory,
                                products: products,
                              ),
                            ],
                          );
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _DashboardSalesCard(orders: orders),
                            ),
                            const SizedBox(width: 20),
                            Expanded(
                              child: _DashboardAlertsCard(
                                inventory: inventory,
                                products: products,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 28),
                    _DashboardRecentOrders(orders: orders),
                    const SizedBox(height: 28),
                    _DashboardActivity(),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}

class OwnerOrdersPage extends StatelessWidget {
  final AuthSession session;
  final _db = DatabaseService();

  OwnerOrdersPage({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppTheme.textDark : AppTheme.textLight;
    final subColor = isDark
        ? AppTheme.subtitleDark(isDark)
        : AppTheme.subtitleLight(isDark);
    final cardBg = isDark ? AppTheme.surfaceDark : Colors.white;
    final cardBorder = isDark ? AppTheme.borderDark : AppTheme.borderLight;
    final headerBg = isDark
        ? AppTheme.backgroundDarkAlt
        : AppTheme.backgroundLightAlt;
    final rowBorder = isDark ? AppTheme.borderDark : AppTheme.borderLight;

    return StreamBuilder<DatabaseEvent>(
      stream: _db.getOrdersStream(),
      builder: (context, snapshot) {
        final orders = _asMap(snapshot.data?.snapshot.value);
        final list = orders.entries.toList()
          ..sort(
            (a, b) => _text(
              b.value['orderDate'],
            ).compareTo(_text(a.value['orderDate'])),
          );
        if (snapshot.connectionState == ConnectionState.waiting)
          return const Center(child: CircularProgressIndicator());
        if (list.isEmpty)
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
                    Icons.shopping_bag_outlined,
                    size: 52,
                    color: AppTheme.primaryGold,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No orders found',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Orders will appear here once customers place orders.',
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
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTheme.adminPagePaddingCompact,
                24,
                AppTheme.adminPagePaddingCompact,
                12,
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _iconBadgeBg(AppTheme.accentGold, isDark),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.shopping_bag_outlined,
                      color: AppTheme.accentGold,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Orders Overview',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                      color: textColor,
                      letterSpacing: -0.1,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                margin: const EdgeInsets.fromLTRB(
                  AppTheme.adminPagePaddingCompact,
                  0,
                  AppTheme.adminPagePaddingCompact,
                  24,
                ),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                  border: Border.all(color: cardBorder),
                ),
                child: SingleChildScrollView(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 680),
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
                                  flex: 2,
                                  child: Text(
                                    'ORDER ID',
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
                                    'CUSTOMER',
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
                                    'DATE',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 11.5,
                                      color: subColor,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 1,
                                  child: Text(
                                    'ITEMS',
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
                                    'TOTAL',
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
                              ],
                            ),
                          ),
                          ...list.asMap().entries.map((entry) {
                            final i = entry.key;
                            final order = entry.value;
                            final orderId = order.key;
                            final items = _asMap(order.value['items']).length;
                            final isLast = i == list.length - 1;
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
                                    flex: 2,
                                    child: Text(
                                      '#${orderId.toString().substring(0, orderId.toString().length > 8 ? 8 : orderId.toString().length).toUpperCase()}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                        color: textColor,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 3,
                                    child: Text(
                                      _text(
                                        order.value['customerName'],
                                        fallback: 'N/A',
                                      ),
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: textColor,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      _text(
                                        order.value['orderDate'],
                                        fallback: '-',
                                      ),
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: textColor,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 1,
                                    child: Text(
                                      '$items',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: textColor,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      '₱${_number(order.value['totalAmount']).toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 13,
                                        color: AppTheme.accentGreen,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: StatusBadge(
                                      status: _text(
                                        order.value['orderStatus'],
                                        fallback: 'Pending',
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
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class OwnerInventoryPage extends StatelessWidget {
  final AuthSession session;
  final _db = DatabaseService();

  OwnerInventoryPage({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppTheme.textDark : AppTheme.textLight;
    final subColor = isDark
        ? AppTheme.subtitleDark(isDark)
        : AppTheme.subtitleLight(isDark);

    return StreamBuilder<DatabaseEvent>(
      stream: _db.getInventoryStream(),
      builder: (context, inventorySnapshot) => StreamBuilder<DatabaseEvent>(
        stream: _db.getProductsStream(),
        builder: (context, productSnapshot) {
          final inventory = _asMap(inventorySnapshot.data?.snapshot.value);
          final products = _asMap(productSnapshot.data?.snapshot.value);
          final rows = _inventoryRows(inventory, products);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTheme.adminPagePaddingCompact,
                  24,
                  AppTheme.adminPagePaddingCompact,
                  16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: _iconBadgeBg(AppTheme.accentGreen, isDark),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.inventory_2_outlined,
                            color: AppTheme.accentGreen,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Inventory Overview',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: textColor,
                                letterSpacing: -0.2,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'System-wide inventory monitoring and stock levels',
                              style: TextStyle(color: subColor, fontSize: 12),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: Row(
                        children: [
                          _OwnerStatCard(
                            width: 220,
                            label: 'Current Stock',
                            value: '${_inventoryUnits(inventory)} bottles',
                            accentColor: AppTheme.accentGreen,
                            icon: Icons.inventory_2_outlined,
                          ),
                          const SizedBox(width: AppTheme.adminRowGap),
                          _OwnerStatCard(
                            width: 220,
                            label: 'Low Stock Items',
                            value:
                                '${rows.where((r) => r['quantity'] <= r['reorderLevel']).length}',
                            accentColor: AppTheme.warning,
                            icon: Icons.warning_amber_rounded,
                            isWarning: rows.any(
                              (r) => r['quantity'] <= r['reorderLevel'],
                            ),
                          ),
                          const SizedBox(width: AppTheme.adminRowGap),
                          _OwnerStatCard(
                            width: 220,
                            label: 'IoT Monitoring',
                            value: 'Connected',
                            accentColor: AppTheme.accentBlue,
                            icon: Icons.camera_alt_outlined,
                            isLive: true,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(child: _InventoryTable(rows: rows)),
            ],
          );
        },
      ),
    );
  }
}

class OwnerProductionPage extends StatelessWidget {
  final AuthSession session;
  final _db = DatabaseService();

  OwnerProductionPage({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppTheme.textDark : AppTheme.textLight;
    final subColor = isDark
        ? AppTheme.subtitleDark(isDark)
        : AppTheme.subtitleLight(isDark);

    return StreamBuilder<DatabaseEvent>(
      stream: _db.getProductionBatchesStream(),
      builder: (context, snapshot) {
        final batches = _asMap(snapshot.data?.snapshot.value).entries.toList()
          ..sort(
            (a, b) => _number(
              b.value['createdTimestamp'],
            ).compareTo(_number(a.value['createdTimestamp'])),
          );

        final activeBatches = batches
            .where((e) => e.value['isArchived'] != true)
            .toList();
        final bulkBatches = activeBatches
            .where((e) => e.value['isBundle'] == true)
            .toList();
        final inProgressCount = activeBatches
            .where(
              (e) =>
                  e.value['status'] == 'In Progress' ||
                  e.value['status'] == 'Partially Completed',
            )
            .length;
        final preparingCount = activeBatches
            .where((e) => e.value['status'] == 'Preparing')
            .length;
        final completedCount = activeBatches
            .where((e) => e.value['status'] == 'Completed')
            .length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTheme.adminPagePaddingCompact,
                24,
                AppTheme.adminPagePaddingCompact,
                0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Production Overview',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Bulk production and batch status monitoring',
                    style: TextStyle(color: subColor, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Row(
                      children: [
                        _OwnerStatCard(
                          label: 'Active Bulk Orders',
                          value: '${bulkBatches.length}',
                          accentColor: AppTheme.accentGold,
                          icon: Icons.local_shipping_outlined,
                        ),
                        const SizedBox(width: AppTheme.adminRowGap),
                        _OwnerStatCard(
                          label: 'In Progress',
                          value: '$inProgressCount',
                          accentColor: AppTheme.accentBlue,
                          icon: Icons.schedule_outlined,
                        ),
                        const SizedBox(width: AppTheme.adminRowGap),
                        _OwnerStatCard(
                          label: 'Preparing (Shortage)',
                          value: '$preparingCount',
                          accentColor: AppTheme.warning,
                          icon: Icons.warning_amber_rounded,
                          isWarning: preparingCount > 0,
                        ),
                        const SizedBox(width: AppTheme.adminRowGap),
                        _OwnerStatCard(
                          label: 'Completed',
                          value: '$completedCount',
                          accentColor: AppTheme.accentGreen,
                          icon: Icons.check_circle_outline_rounded,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
            Expanded(
              child: _BulkProductionTable(
                bulkBatches: bulkBatches,
                isDark: isDark,
                textColor: textColor,
                subColor: subColor,
              ),
            ),
          ],
        );
      },
    );
  }
}

class OwnerSalesPage extends StatelessWidget {
  final AuthSession session;
  final _db = DatabaseService();

  OwnerSalesPage({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppTheme.textDark : AppTheme.textLight;
    final softBorder = isDark
        ? AppTheme.borderDarkAlt
        : AppTheme.borderLightAlt;
    return StreamBuilder<DatabaseEvent>(
      stream: _db.getSalesStream(),
      builder: (context, snapshot) {
        final sales = _asMap(snapshot.data?.snapshot.value).values
            .where(
              (sale) =>
                  sale['orderStatus'] == 'Completed' ||
                  sale['paymentStatus'] == 'Paid',
            )
            .toList();
        final total = sales.fold<double>(
          0,
          (sum, sale) => sum + _number(sale['totalAmount'] ?? sale['amount']),
        );
        final now = DateTime.now();
        final today = sales
            .where(
              (sale) => _sameDay(_date(sale['orderDate'] ?? sale['date']), now),
            )
            .fold<double>(
              0,
              (sum, sale) =>
                  sum + _number(sale['totalAmount'] ?? sale['amount']),
            );
        final month = sales
            .where((sale) {
              final date = _date(sale['orderDate'] ?? sale['date']);
              return date?.year == now.year && date?.month == now.month;
            })
            .fold<double>(
              0,
              (sum, sale) =>
                  sum + _number(sale['totalAmount'] ?? sale['amount']),
            );
        return ListView(
          padding: const EdgeInsets.fromLTRB(32, 24, 32, 40),
          children: [
            const SizedBox(height: 8),
            Wrap(
              spacing: 20,
              runSpacing: 20,
              children: [
                _OwnerStatCard(
                  label: 'Total Sales',
                  value: '₱${total.toStringAsFixed(2)}',
                  accentColor: AppTheme.accentRose,
                  icon: Icons.paid_outlined,
                ),
                _OwnerStatCard(
                  label: "Today's Sales",
                  value: '₱${today.toStringAsFixed(2)}',
                  accentColor: AppTheme.accentGreen,
                  icon: Icons.today_outlined,
                ),
                _OwnerStatCard(
                  label: 'Monthly Sales',
                  value: '₱${month.toStringAsFixed(2)}',
                  accentColor: AppTheme.accentGold,
                  icon: Icons.calendar_month_outlined,
                ),
              ],
            ),
            const SizedBox(height: 28),
            Container(
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
                            color: _iconBadgeBg(AppTheme.accentRose, isDark),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.receipt_long_rounded,
                            color: AppTheme.accentRose,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Completed Sales',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 17,
                            color: textColor,
                            letterSpacing: -0.1,
                          ),
                        ),
                        const Spacer(),
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
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('CUSTOMER')),
                          DataColumn(label: Text('AMOUNT')),
                          DataColumn(label: Text('DATE')),
                          DataColumn(label: Text('STATUS')),
                        ],
                        rows: sales
                            .map(
                              (sale) => DataRow(
                                cells: [
                                  DataCell(
                                    Text(
                                      _text(
                                        sale['customerName'],
                                        fallback: 'N/A',
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      '₱${_number(sale['totalAmount'] ?? sale['amount']).toStringAsFixed(2)}',
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      _text(
                                        sale['orderDate'] ?? sale['date'],
                                        fallback: '-',
                                      ),
                                    ),
                                  ),
                                  DataCell(StatusBadge(status: 'Completed')),
                                ],
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class OwnerActivityPage extends StatelessWidget {
  final AuthSession session;
  const OwnerActivityPage({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppTheme.textDark : AppTheme.textLight;
    final subColor = isDark
        ? AppTheme.subtitleDark(isDark)
        : AppTheme.subtitleLight(isDark);
    final cardBg = isDark ? AppTheme.surfaceDark : Colors.white;
    final cardBorder = isDark ? AppTheme.borderDark : AppTheme.borderLight;
    final headerBg = isDark
        ? AppTheme.backgroundDarkAlt
        : AppTheme.backgroundLightAlt;
    final rowBorder = isDark ? AppTheme.borderDark : AppTheme.borderLight;

    return StreamBuilder<DatabaseEvent>(
      stream: DatabaseService().getAdminActivityLogsStream(),
      builder: (context, snapshot) {
        final logs = _asMap(snapshot.data?.snapshot.value).entries.toList()
          ..sort(
            (a, b) => _number(
              b.value['timestamp'],
            ).compareTo(_number(a.value['timestamp'])),
          );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTheme.adminPagePaddingCompact,
                24,
                AppTheme.adminPagePaddingCompact,
                12,
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _iconBadgeBg(AppTheme.accentGreen, isDark),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.history_outlined,
                      color: AppTheme.accentGreen,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Activity Logs',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                      color: textColor,
                      letterSpacing: -0.1,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: logs.isEmpty
                  ? Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 48,
                          horizontal: 24,
                        ),
                        margin: const EdgeInsets.symmetric(horizontal: 32),
                        decoration: BoxDecoration(
                          color: AppTheme.mutedPanel(isDark),
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusLg,
                          ),
                          border: Border.all(
                            color: AppTheme.panelBorder(isDark),
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.history_outlined,
                              size: 52,
                              color: AppTheme.primaryGold,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No activity logs yet',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: textColor,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Admin activity will be logged here.',
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
                      margin: const EdgeInsets.fromLTRB(
                        AppTheme.adminPagePaddingCompact,
                        0,
                        AppTheme.adminPagePaddingCompact,
                        24,
                      ),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                        border: Border.all(color: cardBorder),
                      ),
                      child: SingleChildScrollView(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minWidth: 680),
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
                                        flex: 2,
                                        child: Text(
                                          'TIMESTAMP',
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
                                          'ADMIN',
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
                                          'ACTION',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 11.5,
                                            color: subColor,
                                            letterSpacing: 0.3,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 4,
                                        child: Text(
                                          'DETAILS',
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
                                ...logs.asMap().entries.map((entry) {
                                  final i = entry.key;
                                  final log = entry.value;
                                  final isLast = i == logs.length - 1;
                                  final ts = _number(log.value['timestamp']);
                                  final dt = ts > 0
                                      ? DateTime.fromMillisecondsSinceEpoch(
                                          ts.toInt(),
                                        )
                                      : null;
                                  final timeStr = dt != null
                                      ? dt.toLocal().toString().replaceFirst(
                                          '.',
                                          ' ',
                                        )
                                      : '-';
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
                                          flex: 2,
                                          child: Text(
                                            timeStr,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: subColor,
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          flex: 2,
                                          child: Text(
                                            _text(
                                              log.value['adminName'],
                                              fallback: '-',
                                            ),
                                            style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 13,
                                              color: textColor,
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          flex: 3,
                                          child: Text(
                                            _text(
                                              log.value['action'],
                                              fallback: '-',
                                            ),
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: textColor,
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          flex: 4,
                                          child: Text(
                                            _text(
                                              log.value['details'],
                                              fallback: '-',
                                            ),
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: textColor,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
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
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _BulkProductionTable extends StatelessWidget {
  final List<MapEntry<dynamic, dynamic>> bulkBatches;
  final bool isDark;
  final Color textColor;
  final Color subColor;

  const _BulkProductionTable({
    required this.bulkBatches,
    required this.isDark,
    required this.textColor,
    required this.subColor,
  });

  @override
  Widget build(BuildContext context) {
    final cardBg = isDark ? AppTheme.surfaceDark : Colors.white;
    final cardBorder = isDark ? AppTheme.borderDark : AppTheme.borderLight;
    final headerBg = isDark
        ? AppTheme.backgroundDarkAlt
        : AppTheme.backgroundLightAlt;
    final rowBorder = isDark ? AppTheme.borderDark : AppTheme.borderLight;

    if (bulkBatches.isEmpty) {
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
                Icons.local_shipping_outlined,
                size: 52,
                color: AppTheme.primaryGold,
              ),
              const SizedBox(height: 16),
              Text(
                'No bulk production plans active',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Bulk production plans will appear here.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: subColor, height: 1.4),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppTheme.adminPagePaddingCompact,
        0,
        AppTheme.adminPagePaddingCompact,
        24,
      ),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: cardBorder),
      ),
      child: SingleChildScrollView(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 680),
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
                        flex: 2,
                        child: Text(
                          'BULK ID',
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
                          'CUSTOMER',
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
                          'TARGET QTY',
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
                          'PROGRESS',
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
                          'TARGET DATE',
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
                    ],
                  ),
                ),
                ...bulkBatches.asMap().entries.map((entry) {
                  final i = entry.key;
                  final batch = entry.value;
                  final isLast = i == bulkBatches.length - 1;
                  final target = _number(
                    batch.value['quantityTarget'] ??
                        batch.value['quantityProduced'] ??
                        100,
                  ).toInt();
                  final completed = _number(
                    batch.value['completedQuantity'] ?? 0,
                  ).toInt();
                  final progress = target > 0 ? (completed / target) : 0.0;
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
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
                        Expanded(
                          flex: 2,
                          child: Text(
                            '#${entry.key.toString().substring(0, 8).toUpperCase()}',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: textColor,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            _text(batch.value['customerName'], fallback: '-'),
                            style: TextStyle(fontSize: 13, color: textColor),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            '$target',
                            style: TextStyle(fontSize: 13, color: textColor),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            '${(progress * 100).toStringAsFixed(1)}%',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: AppTheme.accentGreen,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            _text(
                              batch.value['targetCompletionDate'] ??
                                  batch.value['productionDate'],
                              fallback: '-',
                            ),
                            style: TextStyle(fontSize: 13, color: textColor),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: StatusBadge(
                            status: _text(
                              batch.value['status'],
                              fallback: 'Planned',
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
        ),
      ),
    );
  }
}

class _OwnerStatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color accentColor;
  final IconData icon;
  final bool isWarning;
  final bool isLive;
  final double? width;

  const _OwnerStatCard({
    required this.label,
    required this.value,
    required this.accentColor,
    required this.icon,
    this.isWarning = false,
    this.isLive = false,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final valueColor = isWarning
        ? AppTheme.warning
        : isDark
        ? AppTheme.textDark
        : AppTheme.textLight;
    final subColor = isDark
        ? AppTheme.subtitleDark(isDark)
        : AppTheme.subtitleLight(isDark);
    final chevronColor = isDark
        ? const Color(0xFF6B6357)
        : const Color(0xFF9A9080);
    final softBorder = isDark
        ? AppTheme.borderDarkAlt
        : AppTheme.borderLightAlt;

    Color pill;
    if (isLive) {
      pill = _pillBg(AppTheme.success, isDark);
    } else if (isWarning) {
      pill = _pillBg(AppTheme.warning, isDark);
    } else {
      pill = _pillBg(accentColor, isDark);
    }

    return Container(
      width: width ?? 220,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: softBorder),
        boxShadow: [
          BoxShadow(
            color: isDark ? const Color(0xFF0B0A08) : const Color(0xFFEFE6D2),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _iconBadgeBg(accentColor, isDark),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: accentColor, size: 22),
              ),
              const Spacer(),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: chevronColor,
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
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: valueColor,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: pill,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isLive) ...[
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: AppTheme.success,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                    ] else if (isWarning) ...[
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 10,
                        color: AppTheme.warning,
                      ),
                      const SizedBox(width: 2),
                    ] else ...[
                      Icon(Icons.north_rounded, size: 10, color: accentColor),
                      const SizedBox(width: 2),
                    ],
                    Text(
                      isLive
                          ? 'Live'
                          : isWarning
                          ? 'Needs Attention'
                          : 'On Track',
                      style: TextStyle(
                        color: isLive
                            ? AppTheme.success
                            : isWarning
                            ? AppTheme.warning
                            : accentColor,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DashboardSalesCard extends StatelessWidget {
  final Map<String, Map<String, dynamic>> orders;
  const _DashboardSalesCard({required this.orders});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppTheme.textDark : AppTheme.textLight;
    final subColor = isDark
        ? AppTheme.subtitleDark(isDark)
        : AppTheme.subtitleLight(isDark);
    final softBorder = isDark
        ? AppTheme.borderDarkAlt
        : AppTheme.borderLightAlt;
    final completed = orders.values
        .where((o) => o['orderStatus'] == 'Completed')
        .toList();
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
                    color: _iconBadgeBg(AppTheme.accentRose, isDark),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.paid_outlined,
                    color: AppTheme.accentRose,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Sales Overview',
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
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    isDark
                        ? AppTheme.iconBadgeRoseDark
                        : AppTheme.iconBadgeRoseLight,
                    isDark
                        ? AppTheme.iconBadgeGoldDark
                        : AppTheme.iconBadgeGoldLight,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                border: Border.all(
                  color: isDark ? AppTheme.borderDark : AppTheme.borderLight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Completed orders:',
                        style: TextStyle(
                          color: subColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${completed.length}',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                          color: textColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Text(
                        'Revenue:',
                        style: TextStyle(
                          color: subColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '₱${completed.fold<double>(0, (sum, o) => sum + _number(o['totalAmount'])).toStringAsFixed(2)}',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                          color: AppTheme.accentRose,
                        ),
                      ),
                    ],
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

class _DashboardAlertsCard extends StatelessWidget {
  final Map<String, Map<String, dynamic>> inventory;
  final Map<String, Map<String, dynamic>> products;
  const _DashboardAlertsCard({required this.inventory, required this.products});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppTheme.textDark : AppTheme.textLight;
    final lowStock = _inventoryRows(
      inventory,
      products,
    ).where((item) => item['quantity'] <= item['reorderLevel']).length;
    final warnBg = isDark
        ? AppTheme.backgroundDarkAlt
        : const Color(0xFFFFFBF1);
    final softBorder = isDark
        ? AppTheme.borderDarkAlt
        : AppTheme.borderLightAlt;
    final normal = lowStock == 0;
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
                    color: _iconBadgeBg(AppTheme.warning, isDark),
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
                    'Important Alerts',
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
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: warnBg,
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                border: Border.all(
                  color: isDark ? AppTheme.borderDark : AppTheme.borderLight,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: normal
                          ? (isDark
                                ? AppTheme.iconBadgeGreenDark
                                : AppTheme.iconBadgeGreenLight)
                          : (isDark
                                ? AppTheme.iconBadgeGoldDark
                                : AppTheme.iconBadgeGoldLight),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: normal
                            ? (isDark
                                  ? AppTheme.badgeGreenBorderDark
                                  : AppTheme.badgeGreenBorderLight)
                            : (isDark
                                  ? AppTheme.badgeGoldBorderDark
                                  : AppTheme.badgeGoldBorderLight),
                      ),
                    ),
                    child: Icon(
                      normal
                          ? Icons.verified_outlined
                          : Icons.warning_amber_rounded,
                      color: normal
                          ? AppTheme.success
                          : const Color(0xFFD9A441),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      normal
                          ? 'No low stock alerts.'
                          : '$lowStock inventory item(s) need attention.',
                      style: TextStyle(
                        color: normal ? AppTheme.success : AppTheme.warning,
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                      ),
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

class _DashboardRecentOrders extends StatelessWidget {
  final Map<String, Map<String, dynamic>> orders;
  const _DashboardRecentOrders({required this.orders});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppTheme.textDark : AppTheme.textLight;
    final subColor = isDark
        ? AppTheme.subtitleDark(isDark)
        : AppTheme.subtitleLight(isDark);
    final softBorder = isDark
        ? AppTheme.borderDarkAlt
        : AppTheme.borderLightAlt;
    final rowBorder = isDark ? AppTheme.borderDark : AppTheme.borderLightAlt;
    final recent = orders.entries.toList()
      ..sort(
        (a, b) =>
            _text(b.value['orderDate']).compareTo(_text(a.value['orderDate'])),
      );
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
                    color: _iconBadgeBg(AppTheme.accentGold, isDark),
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
            const SizedBox(height: 12),
            ...recent
                .take(5)
                .map(
                  (e) => Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                      border: Border.all(color: rowBorder),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _text(e.value['customerName'], fallback: 'N/A'),
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                  color: textColor,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _text(e.value['orderDate'], fallback: '-'),
                                style: TextStyle(fontSize: 12, color: subColor),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '₱${_number(e.value['totalAmount']).toStringAsFixed(2)}',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                            color: AppTheme.primaryGold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _DashboardActivity extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppTheme.textDark : AppTheme.textLight;
    final subColor = isDark
        ? AppTheme.subtitleDark(isDark)
        : AppTheme.subtitleLight(isDark);
    final softBorder = isDark
        ? AppTheme.borderDarkAlt
        : AppTheme.borderLightAlt;
    final rowBorder = isDark ? AppTheme.borderDark : AppTheme.borderLightAlt;
    return StreamBuilder<DatabaseEvent>(
      stream: DatabaseService().getAdminActivityLogsStream(),
      builder: (context, snapshot) {
        final logs = _asMap(snapshot.data?.snapshot.value).values.toList();
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
                        color: _iconBadgeBg(AppTheme.accentGreen, isDark),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.timeline_rounded,
                        color: AppTheme.accentGreen,
                        size: 20,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'Recent Admin Activity',
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
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
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
                const SizedBox(height: 12),
                if (logs.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'No activity recorded yet.',
                      style: TextStyle(color: subColor),
                    ),
                  ),
                ...logs.reversed
                    .take(5)
                    .map(
                      (log) => Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusMd,
                          ),
                          border: Border.all(color: rowBorder),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: _iconBadgeBg(
                                  AppTheme.accentPurple,
                                  isDark,
                                ),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.history_outlined,
                                color: AppTheme.accentPurple,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _text(log['action'], fallback: 'Activity'),
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13.5,
                                      color: textColor,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _text(
                                      log['targetName'],
                                      fallback: 'System',
                                    ),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: subColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _InventoryTable extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  const _InventoryTable({required this.rows});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppTheme.textDark : AppTheme.textLight;
    final softBorder = isDark
        ? AppTheme.borderDarkAlt
        : AppTheme.borderLightAlt;
    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppTheme.adminPagePaddingCompact,
        0,
        AppTheme.adminPagePaddingCompact,
        24,
      ),
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
                    color: _iconBadgeBg(AppTheme.accentGreen, isDark),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.inventory_2_outlined,
                    color: AppTheme.accentGreen,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Inventory Stock Levels',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 17,
                    color: textColor,
                    letterSpacing: -0.1,
                  ),
                ),
                const Spacer(),
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
            Expanded(
              child: SingleChildScrollView(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 600),
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('PRODUCT / SIZE')),
                        DataColumn(label: Text('CURRENT STOCK')),
                        DataColumn(label: Text('REORDER LEVEL')),
                        DataColumn(label: Text('STATUS')),
                      ],
                      rows: rows.map((item) {
                        final qty = item['quantity'] as int;
                        final status = qty == 0
                            ? 'Out of Stock'
                            : qty <= item['reorderLevel']
                            ? 'Low Stock'
                            : 'In Stock';
                        return DataRow(
                          cells: [
                            DataCell(
                              Text('${item['size']} (${item['variety']})'),
                            ),
                            DataCell(Text('$qty')),
                            DataCell(Text('${item['reorderLevel']}')),
                            DataCell(StatusBadge(status: status)),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OwnerScanSummary extends StatelessWidget {
  @override
  Widget build(BuildContext context) => StreamBuilder<DatabaseEvent>(
    stream: DatabaseService().getScanResultsStream(),
    builder: (context, snapshot) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      final textColor = isDark ? AppTheme.textDark : AppTheme.textLight;
      final softBorder = isDark
          ? AppTheme.borderDarkAlt
          : AppTheme.borderLightAlt;
      final scans = _asMap(snapshot.data?.snapshot.value);
      final unacknowledged = scans.values
          .where(
            (scan) =>
                scan['isAcknowledged'] != true || scan['status'] == 'MISMATCH',
          )
          .length;
      final unaccentedPill = snapshot.hasError
          ? AppTheme.textSecondary(isDark)
          : unacknowledged > 0
          ? AppTheme.error
          : AppTheme.success;
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
                      color: _iconBadgeBg(AppTheme.accentBlue, isDark),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.camera_alt_outlined,
                      color: AppTheme.accentBlue,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'IoT Inventory Monitoring',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                      color: textColor,
                      letterSpacing: -0.1,
                    ),
                  ),
                  const Spacer(),
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
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      isDark
                          ? AppTheme.iconBadgeBlueDark
                          : AppTheme.iconBadgeBlueLight,
                      isDark
                          ? AppTheme.iconBadgeGoldDark
                          : AppTheme.iconBadgeGoldLight,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                  border: Border.all(
                    color: isDark ? AppTheme.borderDark : AppTheme.borderLight,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: _iconBadgeBg(const Color(0xFFD9A441), isDark),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.camera_alt_outlined,
                        color: Color(0xFFD9A441),
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Text(
                        'IoT Inventory Monitoring',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _pillBg(unaccentedPill, isDark),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        snapshot.hasError
                            ? 'Scanner unavailable'
                            : '$unacknowledged unacknowledged',
                        style: TextStyle(
                          color: unaccentedPill,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _InventoryActivity extends StatelessWidget {
  @override
  Widget build(BuildContext context) => StreamBuilder<DatabaseEvent>(
    stream: DatabaseService().getInventoryMovementsStream(),
    builder: (context, snapshot) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      final textColor = isDark ? AppTheme.textDark : AppTheme.textLight;
      final subColor = isDark
          ? AppTheme.subtitleDark(isDark)
          : AppTheme.subtitleLight(isDark);
      final softBorder = isDark
          ? AppTheme.borderDarkAlt
          : AppTheme.borderLightAlt;
      final rowBorder = isDark ? AppTheme.borderDark : AppTheme.borderLightAlt;
      final movements = _asMap(snapshot.data?.snapshot.value).values.toList()
        ..sort(
          (a, b) => _number(b['timestamp']).compareTo(_number(a['timestamp'])),
        );
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
                      color: _iconBadgeBg(AppTheme.accentGreen, isDark),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.swap_vert_rounded,
                      color: AppTheme.accentGreen,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Inventory Activity',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                      color: textColor,
                      letterSpacing: -0.1,
                    ),
                  ),
                  const Spacer(),
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
              const SizedBox(height: 12),
              if (movements.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'No inventory activity recorded.',
                    style: TextStyle(color: subColor),
                  ),
                ),
              ...movements.take(5).map((move) {
                final change = _number(move['quantityChange']);
                final moveColor = change >= 0
                    ? AppTheme.success
                    : AppTheme.error;
                return Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    border: Border.all(color: rowBorder),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: _iconBadgeBg(moveColor, isDark),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          change >= 0
                              ? Icons.add_rounded
                              : Icons.remove_rounded,
                          color: moveColor,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_text(move['type'], fallback: 'Movement')} ${change >= 0 ? '+' : ''}${change.toInt()} bottles',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5,
                                color: textColor,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Reference: ${_text(move['referenceId'], fallback: '-')}',
                              style: TextStyle(fontSize: 12, color: subColor),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: _pillBg(AppTheme.primaryGold, isDark),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '${_text(move['newQuantity'], fallback: '-')}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                            color: AppTheme.primaryGold,
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
      );
    },
  );
}

Map<String, Map<String, dynamic>> _asMap(Object? value) {
  if (value is! Map) return {};
  return value.map(
    (key, item) => MapEntry(
      key.toString(),
      item is Map ? Map<String, dynamic>.from(item) : <String, dynamic>{},
    ),
  );
}

List<Map<String, dynamic>> _inventoryRows(
  Map<String, Map<String, dynamic>> inventory,
  Map<String, Map<String, dynamic>> products,
) {
  final rows = <Map<String, dynamic>>[];
  inventory.forEach((productId, variants) {
    final product = products[productId];
    final productVariants = _asMap(product?['variants']);
    variants.forEach((variantId, data) {
      final variant = productVariants[variantId];
      if (variant != null) {
        rows.add({
          'variety': _text(
            product?['variety'],
            fallback: _text(product?['name'], fallback: 'Product'),
          ),
          'size': _text(variant['size'], fallback: '-'),
          'quantity': _number(data['quantity']).toInt(),
          'reorderLevel': _number(
            variant['reorderLevel'],
            fallback: 10,
          ).toInt(),
        });
      }
    });
  });
  return rows;
}

int _inventoryUnits(Map<String, Map<String, dynamic>> inventory) =>
    inventory.values.fold(
      0,
      (sum, variants) =>
          sum +
          variants.values.fold(
            0,
            (inner, value) => inner + _number(value['quantity']).toInt(),
          ),
    );
double _number(Object? value, {num fallback = 0}) => value is num
    ? value.toDouble()
    : double.tryParse(value?.toString() ?? '') ?? fallback.toDouble();
String _text(Object? value, {String fallback = ''}) =>
    value?.toString() ?? fallback;
DateTime? _date(Object? value) => DateTime.tryParse(value?.toString() ?? '');
bool _sameDay(DateTime? date, DateTime other) =>
    date != null &&
    date.year == other.year &&
    date.month == other.month &&
    date.day == other.day;
