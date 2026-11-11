import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/supabase_notification_service.dart';
import '../core/theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// NotificationsPage — list-style with All / Unread / Archive tabs
// ─────────────────────────────────────────────────────────────────────────────
class NotificationsPage extends StatefulWidget {
  final AuthSession session;
  final void Function(int tabIndex)? onNavigateTab;
  const NotificationsPage({super.key, required this.session, this.onNavigateTab});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage>
    with SingleTickerProviderStateMixin {
  final _notifications = SupabaseNotificationService.instance;
  late final TabController _tabCtrl;
  String _search = '';

  static const _gold = AppTheme.primaryGold;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
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
          // ── Header ──────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 28, 32, 0),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 650;
                final titleBlock = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'List Notification',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: isDark ? AppTheme.textDark : AppTheme.textLight,
                      ),
                    ),
                    const SizedBox(height: 4),
                    StreamBuilder<List<Map<String, dynamic>>>(
                      stream: _notifications.notificationsStream,
                      builder: (context, snap) {
                        final total = snap.data?.length ?? 0;
                        return Text(
                          '$total Notification${total == 1 ? '' : 's'}',
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? AppTheme.textMutedDark : AppTheme.textMutedLight,
                          ),
                        );
                      },
                    ),
                  ],
                );

                final actionsBlock = Row(
                  mainAxisSize: isNarrow ? MainAxisSize.max : MainAxisSize.min,
                  children: [
                    // Search bar
                    Expanded(
                      flex: isNarrow ? 1 : 0,
                      child: SizedBox(
                        width: isNarrow ? null : 240,
                        height: 38,
                        child: TextField(
                          onChanged: (v) => setState(() => _search = v),
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? AppTheme.textDark : AppTheme.textLight,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Search by message or type...',
                            hintStyle: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                            prefixIcon: const Icon(
                              Icons.search_rounded,
                              size: 17,
                              color: Colors.grey,
                            ),
                            filled: true,
                            fillColor: isDark
                                ? AppTheme.surfaceDark
                                : AppTheme.surfaceLight,
                            contentPadding: EdgeInsets.zero,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(
                                color: isDark ? AppTheme.dividerDark : AppTheme.dividerLight,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(
                                color: isDark ? AppTheme.dividerDark : AppTheme.dividerLight,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: AppTheme.primaryGold),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    TextButton.icon(
                      onPressed: () =>
                          _runNotificationAction(_notifications.markAllAsRead),
                      icon: const Icon(Icons.done_all_rounded, size: 16),
                      label: const Text(
                        'Mark all read',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.primaryGold,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                    ),
                  ],
                );

                if (isNarrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      titleBlock,
                      const SizedBox(height: 14),
                      actionsBlock,
                    ],
                  );
                }

                return Row(
                  children: [
                    titleBlock,
                    const Spacer(),
                    actionsBlock,
                  ],
                );
              },
            ),
          ),

          // ── Tabs ────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 16, 32, 0),
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _notifications.notificationsStream,
              builder: (context, snap) {
                int unread = 0;
                int archived = 0;
                if (snap.hasData) {
                  unread = snap.data!
                      .where(
                        (notification) =>
                            notification['isRead'] != true &&
                            notification['isArchived'] != true,
                      )
                      .length;
                  archived = snap.data!
                      .where(
                        (notification) => notification['isArchived'] == true,
                      )
                      .length;
                }

                return TabBar(
                  controller: _tabCtrl,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  labelColor: _gold,
                  unselectedLabelColor: Colors.grey,
                  indicatorColor: _gold,
                  indicatorWeight: 2.5,
                  labelStyle: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                  ),
                  tabs: [
                    const Tab(text: 'All'),
                    Tab(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Unread'),
                          if (unread > 0) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE53935),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '$unread',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Tab(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Archive'),
                          if (archived > 0) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade400,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '$archived',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                ),
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
          ),

          const Divider(height: 1),

          // ── Tab content ─────────────────────────────────────────────────
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                _NotifList(
                  notifications: _notifications,
                  filter: _NotifFilter.all,
                  search: _search,
                  onNavigateTab: widget.onNavigateTab,
                ),
                _NotifList(
                  notifications: _notifications,
                  filter: _NotifFilter.unread,
                  search: _search,
                  onNavigateTab: widget.onNavigateTab,
                ),
                _NotifList(
                  notifications: _notifications,
                  filter: _NotifFilter.archived,
                  search: _search,
                  onNavigateTab: widget.onNavigateTab,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _runNotificationAction(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      debugPrint('[NotificationsPage] Notification action failed: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Notification update failed: $error')),
        );
      }
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Filter enum
// ─────────────────────────────────────────────────────────────────────────────
enum _NotifFilter { all, unread, archived }

// ─────────────────────────────────────────────────────────────────────────────
// _NotifList — shared list widget for each tab
// ─────────────────────────────────────────────────────────────────────────────
class _NotifList extends StatelessWidget {
  final SupabaseNotificationService notifications;
  final _NotifFilter filter;
  final String search;
  final void Function(int tabIndex)? onNavigateTab;

  const _NotifList({
    required this.notifications,
    required this.filter,
    required this.search,
    this.onNavigateTab,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: notifications.notificationsStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Unable to load notifications: ${snapshot.error}',
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return _emptyState('No notifications yet.');
        }

        var list = List<Map<String, dynamic>>.from(snapshot.data!);

        // Apply filter
        list = list.where((n) {
          final isArchived = n['isArchived'] == true;
          final isRead = n['isRead'] == true;
          switch (filter) {
            case _NotifFilter.all:
              return !isArchived;
            case _NotifFilter.unread:
              return !isRead && !isArchived;
            case _NotifFilter.archived:
              return isArchived;
          }
        }).toList();

        // Apply search
        if (search.trim().isNotEmpty) {
          final q = search.toLowerCase();
          list = list
              .where(
                (n) =>
                    (n['message'] ?? '').toString().toLowerCase().contains(q) ||
                    (n['type'] ?? '').toString().toLowerCase().contains(q),
              )
              .toList();
        }

        if (list.isEmpty) {
          return _emptyState(
            filter == _NotifFilter.unread
                ? 'All caught up! No unread notifications.'
                : filter == _NotifFilter.archived
                ? 'No archived notifications.'
                : 'No notifications found.',
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
          itemCount: list.length,
          separatorBuilder: (_, __) => const Divider(height: 1, indent: 56),
          itemBuilder: (context, i) => _NotifRow(
            item: list[i],
            notifications: notifications,
            onAction: (action) => _runNotificationAction(context, action),
            onNavigateTab: onNavigateTab,
          ),
        );
      },
    );
  }

  Future<void> _runNotificationAction(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (error) {
      debugPrint('[NotificationsList] Notification action failed: $error');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Notification update failed: $error')),
        );
      }
    }
  }

  Widget _emptyState(String msg) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.notifications_off_outlined,
            size: 48,
            color: Colors.grey,
          ),
          const SizedBox(height: 12),
          Text(msg, style: const TextStyle(color: Colors.grey, fontSize: 14)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _NotifRow — single notification row
// ─────────────────────────────────────────────────────────────────────────────
class _NotifRow extends StatelessWidget {
  final Map<String, dynamic> item;
  final SupabaseNotificationService notifications;
  final Future<void> Function(Future<void> Function()) onAction;
  final void Function(int tabIndex)? onNavigateTab;

  const _NotifRow({
    required this.item,
    required this.notifications,
    required this.onAction,
    this.onNavigateTab,
  });

  static const _gold = Color(0xFFD9A441);

  @override
  Widget build(BuildContext context) {
    final isRead = item['isRead'] == true;
    final isArchived = item['isArchived'] == true;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final type = item['type']?.toString() ?? '';
    final message = item['message']?.toString() ?? '';
    final ts = item['timestamp'] as int? ?? 0;

    return InkWell(
      onTap: () async {
        if (!isRead) {
          await onAction(() => notifications.markAsRead(item['id'].toString()));
        }
        if (onNavigateTab != null) {
          final t = type.toUpperCase();
          if (t.contains('ORDER')) {
            onNavigateTab!(1); // Orders
          } else if (t.contains('STOCK') || t.contains('DISCREPANCY') || t.contains('INVENTORY')) {
            onNavigateTab!(2); // Inventory
          } else if (t.contains('PRODUCTION')) {
            onNavigateTab!(4); // Production
          } else if (t.contains('MESSAGE') || t.contains('CHAT')) {
            onNavigateTab!(6); // Messages
          } else if (t.contains('FEEDBACK') || t.contains('REVIEW')) {
            onNavigateTab!(11); // Feedback
          }
        }
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: isRead
              ? Colors.transparent
              : (isDark ? AppTheme.backgroundDarkAlt : const Color(0xFFFFFDF5)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Unread dot
            Padding(
              padding: const EdgeInsets.only(top: 18, right: 10),
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: isRead ? Colors.transparent : _gold,
                  shape: BoxShape.circle,
                ),
              ),
            ),

            // Type icon
            _typeIcon(type, isDark),
            const SizedBox(width: 14),

            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          message,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isRead
                                ? FontWeight.w400
                                : FontWeight.w700,
                            color: isDark
                                ? Colors.white
                                : const Color(0xFF111111),
                            height: 1.4,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        _timeAgo(ts),
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _typeLabel(type),
                    style: TextStyle(
                      fontSize: 11,
                      color: _typeThemeColor(type),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),

            // Actions
            PopupMenuButton<String>(
              icon: const Icon(
                Icons.more_horiz_rounded,
                size: 18,
                color: Colors.grey,
              ),
              onSelected: (val) {
                if (val == 'read') {
                  onAction(
                    () => notifications.markAsRead(item['id'].toString()),
                  );
                }
                if (val == 'archive') {
                  onAction(
                    () => notifications.setArchived(
                      item['id'].toString(),
                      !isArchived,
                    ),
                  );
                }
              },
              itemBuilder: (_) => [
                if (!isRead)
                  const PopupMenuItem(
                    value: 'read',
                    child: Text('Mark as read', style: TextStyle(fontSize: 13)),
                  ),
                PopupMenuItem(
                  value: 'archive',
                  child: Text(
                    isArchived ? 'Unarchive' : 'Archive',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _typeIcon(String type, bool isDark) {
    final color = _typeColor(type);
    final icon = _iconData(type);
    final themeColor = _typeThemeColor(type);
    Color bgColor;
    if (isDark) {
      if (themeColor.value == AppTheme.error.value) {
        bgColor = AppTheme.badgeRedBgDark;
      } else if (themeColor.value == AppTheme.success.value) {
        bgColor = AppTheme.badgeGreenBgDark;
      } else if (themeColor.value == AppTheme.info.value) {
        bgColor = const Color(0xFF1A3260);
      } else if (themeColor.value == AppTheme.warning.value) {
        bgColor = const Color(0xFF3A2D10);
      } else {
        bgColor = const Color(0xFF2A2620);
      }
    } else {
      if (themeColor.value == AppTheme.error.value) {
        bgColor = AppTheme.badgeRedBgLight;
      } else if (themeColor.value == AppTheme.success.value) {
        bgColor = AppTheme.badgeGreenBgLight;
      } else if (themeColor.value == AppTheme.info.value) {
        bgColor = const Color(0xFFE0ECFA);
      } else if (themeColor.value == AppTheme.warning.value) {
        bgColor = const Color(0xFFFBF1DD);
      } else {
        bgColor = const Color(0xFFF2F0EC);
      }
    }
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle),
      child: Icon(icon, color: color, size: 18),
    );
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'LOW_STOCK':
      case 'OUT_OF_STOCK':
        return Colors.redAccent;
      case 'NEW_SALE':
      case 'NEW_ORDER':
        return Colors.green;
      case 'NEW_CUSTOMER':
        return Colors.blue;
      case 'PRODUCTION_COMPLETED':
        return Colors.blue;
      case 'PAYMENT_VERIFIED':
        return Colors.teal;
      case 'PAYMENT_REJECTED':
        return Colors.red;
      case 'SCAN_MISMATCH':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  Color _typeThemeColor(String type) {
    switch (type) {
      case 'LOW_STOCK':
      case 'OUT_OF_STOCK':
      case 'PAYMENT_REJECTED':
        return AppTheme.error;
      case 'NEW_SALE':
      case 'NEW_ORDER':
        return AppTheme.success;
      case 'NEW_CUSTOMER':
        return AppTheme.info;
      case 'PRODUCTION_COMPLETED':
      case 'PAYMENT_VERIFIED':
        return AppTheme.info;
      case 'SCAN_MISMATCH':
        return AppTheme.warning;
      default:
        return Colors.grey;
    }
  }

  IconData _iconData(String type) {
    switch (type) {
      case 'LOW_STOCK':
      case 'OUT_OF_STOCK':
        return Icons.warning_amber_rounded;
      case 'NEW_SALE':
      case 'NEW_ORDER':
        return Icons.shopping_bag_outlined;
      case 'NEW_CUSTOMER':
        return Icons.person_add_alt_1_outlined;
      case 'PRODUCTION_COMPLETED':
        return Icons.factory_outlined;
      case 'PAYMENT_VERIFIED':
        return Icons.verified_outlined;
      case 'PAYMENT_REJECTED':
        return Icons.cancel_outlined;
      case 'SCAN_MISMATCH':
        return Icons.qr_code_scanner_outlined;
      default:
        return Icons.notifications_none_rounded;
    }
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
        return 'New Order Received';
      case 'NEW_CUSTOMER':
        return 'New Customer';
      case 'PRODUCTION_COMPLETED':
        return 'Production Completed';
      case 'PAYMENT_VERIFIED':
        return 'Payment Verified';
      case 'PAYMENT_REJECTED':
        return 'Payment Rejected';
      case 'SCAN_MISMATCH':
        return 'IoT Scan Mismatch';
      default:
        return 'System Notification';
    }
  }

  String _timeAgo(int ts) {
    if (ts == 0) return '';
    final diff = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(ts),
    );
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 30) return '${diff.inDays} days ago';
    return DateTime.fromMillisecondsSinceEpoch(
      ts,
    ).toLocal().toString().split(' ')[0];
  }
}
