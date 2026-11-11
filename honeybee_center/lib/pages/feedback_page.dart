import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/supabase_data_service.dart';
import '../core/theme/app_theme.dart';
import '../core/permissions/admin_capabilities.dart';

// ─────────────────────────────────────────────────────────────────────────────
// FeedbackPage — customer reviews & ratings submitted to the admin panel
// ─────────────────────────────────────────────────────────────────────────────
class FeedbackPage extends StatefulWidget {
  final AuthSession session;
  const FeedbackPage({super.key, required this.session});

  @override
  State<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<FeedbackPage>
    with SingleTickerProviderStateMixin {
  final _supabaseData = SupabaseDataService();
  late final TabController _tabCtrl;
  String _search = '';
  List<Map<String, dynamic>> _feedback = [];
  bool _loading = true;
  String? _loadError;

  static const _gold = AppTheme.primaryGold;

  bool get _canModerate =>
      RoleCapabilities.forRole(widget.session.role).canReplyMessages;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _loadFeedback();
  }

  Future<void> _loadFeedback() async {
    setState(() { _loading = true; _loadError = null; });
    try {
      final raw = await _supabaseData.fetchFeedback();
      // Map Supabase snake_case → camelCase for existing UI widgets
      final mapped = raw.map((r) => <String, dynamic>{
        'id':           r['id']?.toString() ?? '',
        'customerName': r['customer_name']?.toString() ?? 'Anonymous',
        'customerEmail':r['customer_email']?.toString() ?? '',
        'rating':       (r['rating'] as num?)?.toInt() ?? 0,
        'message':      r['message']?.toString() ?? '',
        'orderId':      r['order_id']?.toString(),
        'productName':  r['product_name']?.toString(),
        'adminReply':   r['admin_reply']?.toString(),
        'repliedAt':    r['replied_at']?.toString(),
        'isRead':       r['is_read'] == true,
        'isArchived':   r['is_archived'] == true,
        'timestamp':    r['created_at'] != null
            ? (DateTime.tryParse(r['created_at'].toString())?.millisecondsSinceEpoch ?? 0)
            : 0,
      }).toList();
      if (mounted) setState(() { _feedback = mapped; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _loadError = e.toString(); _loading = false; });
    }
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
      backgroundColor: isDark ? AppTheme.backgroundDark : AppTheme.backgroundLight,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 28, 32, 0),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 950;
                final titleWidget = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Customer Feedback',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: isDark ? AppTheme.textDark : AppTheme.textLight,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Reviews and ratings submitted by customers',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? AppTheme.textMutedDark : AppTheme.textMutedLight,
                      ),
                    ),
                  ],
                );

                final chipsWidget = Builder(
                  builder: (context) {
                    final active = _feedback.where((v) => v['isArchived'] != true).toList();
                    final total = active.length;
                    final unread = active.where((v) => v['isRead'] != true).length;
                    final avgRating = total > 0
                        ? active.fold<double>(0, (s, v) => s + ((v['rating'] as num?) ?? 0)) / total
                        : 0.0;
                    return Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _SummaryChip(icon: Icons.star_rounded, color: _gold, label: avgRating > 0 ? avgRating.toStringAsFixed(1) : '—', sub: 'Avg Rating'),
                        _SummaryChip(icon: Icons.reviews_outlined, color: Colors.blue, label: '$total', sub: 'Total Reviews'),
                        _SummaryChip(icon: Icons.mark_email_unread_outlined, color: Colors.orange, label: '$unread', sub: 'Unread'),
                      ],
                    );
                  },
                );

                if (isNarrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      titleWidget,
                      const SizedBox(height: 16),
                      chipsWidget,
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    titleWidget,
                    const Spacer(),
                    chipsWidget,
                  ],
                );
              },
            ),
          ),

          // ── Search + Actions ───────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 16, 32, 0),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 700;
                final searchField = SizedBox(
                  width: isNarrow ? double.infinity : 280,
                  height: 38,
                  child: TextField(
                    onChanged: (v) => setState(() => _search = v),
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? AppTheme.textDark : AppTheme.textLight,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Search by customer, message, or product...',
                      hintStyle: const TextStyle(fontSize: 12, color: Colors.grey),
                      prefixIcon: const Icon(Icons.search_rounded,
                          size: 17, color: Colors.grey),
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
                      focusedBorder: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(10)),
                        borderSide: BorderSide(color: AppTheme.primaryGold),
                      ),
                    ),
                  ),
                );

                final actionBtns = Row(
                  mainAxisSize: isNarrow ? MainAxisSize.max : MainAxisSize.min,
                  children: [
                    if (_canModerate) ...[
                      TextButton.icon(
                        onPressed: () async {
                          await _supabaseData.markAllFeedbackRead();
                          _loadFeedback();
                        },
                        icon: const Icon(Icons.done_all_rounded, size: 16),
                        label: const Text('Mark all read',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        style: TextButton.styleFrom(foregroundColor: _gold),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: () => _showAddFeedbackDialog(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _gold,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        ),
                        icon: const Icon(Icons.add_rounded, size: 16),
                        label: const Text('Add Review', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ],
                );

                if (isNarrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      searchField,
                      const SizedBox(height: 10),
                      actionBtns,
                    ],
                  );
                }

                return Row(
                  children: [
                    searchField,
                    const Spacer(),
                    actionBtns,
                  ],
                );
              },
            ),
          ),

          // ── Tabs ────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 12, 32, 0),
            child: TabBar(
              controller: _tabCtrl,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelColor: _gold,
              unselectedLabelColor: Colors.grey,
              indicatorColor: _gold,
              indicatorWeight: 2.5,
              labelStyle: const TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 13),
              unselectedLabelStyle: const TextStyle(
                  fontWeight: FontWeight.w500, fontSize: 13),
              tabs: const [
                Tab(text: 'All Reviews'),
                Tab(text: 'Unread'),
                Tab(text: 'Archived'),
              ],
            ),
          ),
          const Divider(height: 1),

          // ── Tab content ─────────────────────────────────────────────────
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _loadError != null
                    ? Center(child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.error_outline_rounded, color: AppTheme.error, size: 40),
                          const SizedBox(height: 12),
                          Text('Could not load feedback: $_loadError', textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          ElevatedButton(onPressed: _loadFeedback, child: const Text('Retry')),
                        ]),
                      ))
                    : TabBarView(
                        controller: _tabCtrl,
                        children: [
                          _FeedbackList(
                              items: _feedback,
                              filter: _FbFilter.all,
                              search: _search,
                              session: widget.session,
                              supabaseData: _supabaseData,
                              onRefresh: _loadFeedback),
                          _FeedbackList(
                              items: _feedback,
                              filter: _FbFilter.unread,
                              search: _search,
                              session: widget.session,
                              supabaseData: _supabaseData,
                              onRefresh: _loadFeedback),
                          _FeedbackList(
                              items: _feedback,
                              filter: _FbFilter.archived,
                              search: _search,
                              session: widget.session,
                              supabaseData: _supabaseData,
                              onRefresh: _loadFeedback),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  void _showAddFeedbackDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final msgCtrl = TextEditingController();
    final orderCtrl = TextEditingController();
    final productCtrl = TextEditingController();
    int rating = 5;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: const Text('Add Customer Review',
              style: TextStyle(fontWeight: FontWeight.w800)),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Customer Name *'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: emailCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Customer Email'),
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: productCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Product (optional)'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: orderCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Order ID (optional)'),
                  ),
                  const SizedBox(height: 16),
                  const Text('Rating',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF444444))),
                  const SizedBox(height: 6),
                  Row(
                    children: List.generate(
                      5,
                      (i) => GestureDetector(
                        onTap: () => setDialog(() => rating = i + 1),
                        child: Icon(
                          i < rating
                              ? Icons.star_rounded
                              : Icons.star_outline_rounded,
                          color: const Color(0xFFD9A441),
                          size: 32,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: msgCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Review Message *',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD9A441),
                  foregroundColor: Colors.white),
              onPressed: () {
                // Admin feedback submission is not permitted via the admin panel.
                // Feedback is submitted by customers through the customer app.
                // The 'Add Review' button is reserved for future Phase 5
                // service-role provisioning if required.
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Feedback submission is only available to customers.')),
                );
              },
              child: const Text('Submit Review'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _SummaryChip
// ─────────────────────────────────────────────────────────────────────────────
class _SummaryChip extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String sub;

  const _SummaryChip({
    required this.icon,
    required this.color,
    required this.label,
    required this.sub,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? AppTheme.dividerDark : AppTheme.dividerLight,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: isDark
                  ? (color == AppTheme.primaryGold
                      ? const Color(0xFF3A2D10)
                      : color == Colors.blue
                          ? const Color(0xFF1A3260)
                          : const Color(0xFF3A2D10))
                  : (color == AppTheme.primaryGold
                      ? const Color(0xFFFBF1DD)
                      : color == Colors.blue
                          ? const Color(0xFFE0ECFA)
                          : const Color(0xFFFBF1DD)),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: isDark ? AppTheme.textDark : AppTheme.textLight)),
              Text(sub,
                  style: TextStyle(
                      fontSize: 11,
                      color: isDark ? AppTheme.textMutedDark : AppTheme.textMutedLight)),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Filter enum
// ─────────────────────────────────────────────────────────────────────────────
enum _FbFilter { all, unread, archived }

// ─────────────────────────────────────────────────────────────────────────────
// _FeedbackList
// ─────────────────────────────────────────────────────────────────────────────
class _FeedbackList extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  final _FbFilter filter;
  final String search;
  final AuthSession session;
  final SupabaseDataService supabaseData;
  final VoidCallback onRefresh;

  const _FeedbackList({
    required this.items,
    required this.filter,
    required this.search,
    required this.session,
    required this.supabaseData,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    var list = List<Map<String, dynamic>>.from(items)
      ..sort((a, b) => ((b['timestamp'] ?? 0) as int)
          .compareTo((a['timestamp'] ?? 0) as int));

    list = list.where((n) {
      final isArchived = n['isArchived'] == true;
      final isRead = n['isRead'] == true;
      switch (filter) {
        case _FbFilter.all:      return !isArchived;
        case _FbFilter.unread:   return !isRead && !isArchived;
        case _FbFilter.archived: return isArchived;
      }
    }).toList();

    if (search.trim().isNotEmpty) {
      final q = search.toLowerCase();
      list = list.where((n) =>
          (n['customerName'] ?? '').toString().toLowerCase().contains(q) ||
          (n['message'] ?? '').toString().toLowerCase().contains(q) ||
          (n['productName'] ?? '').toString().toLowerCase().contains(q))
          .toList();
    }

    if (list.isEmpty) {
      return _emptyState(filter == _FbFilter.unread
          ? 'No unread reviews.'
          : filter == _FbFilter.archived
              ? 'No archived reviews.'
              : 'No reviews found.');
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) =>
          _FeedbackCard(item: list[i], supabaseData: supabaseData, session: session, onRefresh: onRefresh),
    );
  }

  Widget _emptyState(String msg) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.reviews_outlined, size: 48, color: Colors.grey),
          const SizedBox(height: 12),
          Text(msg,
              style: const TextStyle(color: Colors.grey, fontSize: 14)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _FeedbackCard — single review card
// ─────────────────────────────────────────────────────────────────────────────
class _FeedbackCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final SupabaseDataService supabaseData;
  final AuthSession session;
  final VoidCallback onRefresh;

  const _FeedbackCard({
    required this.item,
    required this.supabaseData,
    required this.session,
    required this.onRefresh,
  });

  static const _gold = AppTheme.primaryGold;

  bool get _canModerate =>
      RoleCapabilities.forRole(session.role).canReplyMessages;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isRead = item['isRead'] == true;
    final isArchived = item['isArchived'] == true;
    final rating = (item['rating'] as num?)?.toInt() ?? 0;
    final name = item['customerName']?.toString() ?? 'Anonymous';
    final email = item['customerEmail']?.toString() ?? '';
    final message = item['message']?.toString() ?? '';
    final product = item['productName']?.toString();
    final orderId = item['orderId']?.toString();
    final ts = item['timestamp'] as int? ?? 0;
    final adminReply = item['adminReply']?.toString();
    final initial =
        name.isNotEmpty ? name[0].toUpperCase() : 'A';

    return Card(
      elevation: isRead ? 0 : 2,
      color: isRead
          ? (isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight)
          : (isDark
              ? AppTheme.surfaceDarkAlt
              : const Color(0xFFFFFDF5)),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isRead
              ? (isDark ? AppTheme.dividerDark : AppTheme.dividerLight)
              : (isDark ? const Color(0xFF6B5220) : const Color(0xFFE8D1A0)),
          width: isRead ? 1 : 1.2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Top row: avatar, name, rating, time, actions ───────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Avatar
                CircleAvatar(
                  radius: 20,
                  backgroundColor: isDark ? const Color(0xFF3A2D10) : const Color(0xFFFBF1DD),
                  child: Text(
                    initial,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: _gold,
                        fontSize: 16),
                  ),
                ),
                const SizedBox(width: 12),

                // Name + email + stars
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14),
                          ),
                          if (!isRead) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF3A2D10) : const Color(0xFFFBF1DD),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'NEW',
                                style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    color: _gold),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (email.isNotEmpty)
                        Text(email,
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey)),
                      const SizedBox(height: 4),
                      // Star rating
                      Row(
                        children: List.generate(
                          5,
                          (i) => Icon(
                            i < rating
                                ? Icons.star_rounded
                                : Icons.star_outline_rounded,
                            color: _gold,
                            size: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Time
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _timeAgo(ts),
                      style: const TextStyle(
                          fontSize: 11, color: Colors.grey),
                    ),
                    const SizedBox(height: 4),
                    // Actions — write operations only visible to Co-Admin
                    if (_canModerate)
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_horiz_rounded,
                          size: 18, color: Colors.grey),
                      onSelected: (val) async {
                        if (val == 'read') {
                          await supabaseData.markFeedbackRead(item['id']);
                          onRefresh();
                        } else if (val == 'archive') {
                          await supabaseData.archiveFeedback(item['id'],
                              archive: !isArchived);
                          onRefresh();
                        } else if (val == 'reply') {
                          _showReplyDialog(context);
                        }
                      },
                      itemBuilder: (_) => [
                        if (!isRead)
                          const PopupMenuItem(
                            value: 'read',
                            child: Row(children: [
                              Icon(Icons.done_rounded,
                                  size: 16, color: Colors.grey),
                              SizedBox(width: 8),
                              Text('Mark as read',
                                  style: TextStyle(fontSize: 13)),
                            ]),
                          ),
                        const PopupMenuItem(
                          value: 'reply',
                          child: Row(children: [
                            Icon(Icons.reply_rounded,
                                size: 16, color: Colors.grey),
                            SizedBox(width: 8),
                            Text('Reply',
                                style: TextStyle(fontSize: 13)),
                          ]),
                        ),
                        PopupMenuItem(
                          value: 'archive',
                          child: Row(children: [
                            Icon(
                              isArchived
                                  ? Icons.unarchive_outlined
                                  : Icons.archive_outlined,
                              size: 16,
                              color: Colors.grey,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              isArchived ? 'Unarchive' : 'Archive',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ]),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 12),

            // ── Review message ─────────────────────────────────────────
            Text(
              message,
              style: TextStyle(
                fontSize: 13,
                color: isDark
                    ? Colors.white70
                    : const Color(0xFF333333),
                height: 1.5,
              ),
            ),

            // ── Product / Order tags ───────────────────────────────────
            if (product != null || orderId != null) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: [
                  if (product != null)
                    _Tag(
                        icon: Icons.hive_outlined,
                        label: product,
                        color: Colors.blue),
                  if (orderId != null)
                    _Tag(
                        icon: Icons.receipt_outlined,
                        label: 'Order #${orderId.length > 8 ? orderId.substring(0, 8).toUpperCase() : orderId.toUpperCase()}',
                        color: Colors.purple),
                ],
              ),
            ],

            // ── Admin reply ────────────────────────────────────────────
            if (adminReply != null && adminReply.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF3A2D10) : const Color(0xFFFBF1DD),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: isDark ? const Color(0xFF6B5220) : const Color(0xFFE8D1A0), width: 1),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.reply_rounded,
                        size: 15, color: _gold),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Admin Reply · ${session.name}',
                            style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: _gold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            adminReply,
                            style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF555555),
                                height: 1.4),
                          ),
                        ],
                      ),
                    ),
                    // Edit reply — Co-Admin only
                    if (_canModerate)
                    GestureDetector(
                      onTap: () => _showReplyDialog(context),
                      child: const Icon(Icons.edit_outlined,
                          size: 14, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ] else if (_canModerate) ...[
              // Quick reply button — Co-Admin only
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: () => _showReplyDialog(context),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: const Icon(Icons.reply_rounded,
                    size: 14, color: _gold),
                label: const Text('Reply to this review',
                    style: TextStyle(fontSize: 12, color: _gold)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showReplyDialog(BuildContext context) {
    final existing = item['adminReply']?.toString() ?? '';
    final ctrl = TextEditingController(text: existing);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.reply_rounded,
                color: Color(0xFFD9A441), size: 20),
            const SizedBox(width: 8),
            const Text('Reply to Review',
                style: TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Show the review
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F7F7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item['customerName']?.toString() ?? 'Customer',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item['message']?.toString() ?? '',
                      style: const TextStyle(
                          fontSize: 13, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: ctrl,
                maxLines: 4,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Your reply',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
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
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD9A441),
                foregroundColor: Colors.white),
            onPressed: () async {
              if (ctrl.text.trim().isEmpty) return;
              await supabaseData.replyToFeedback(item['id'], ctrl.text.trim());
              onRefresh();
              if (ctx.mounted) Navigator.pop(ctx);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Reply saved.')),
                );
              }
            },
            child: const Text('Save Reply'),
          ),
        ],
      ),
    );
  }

  String _timeAgo(int ts) {
    if (ts == 0) return '';
    final diff = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(ts));
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 30) return '${diff.inDays}d ago';
    return DateTime.fromMillisecondsSinceEpoch(ts)
        .toLocal()
        .toString()
        .split(' ')[0];
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _Tag — small pill tag
// ─────────────────────────────────────────────────────────────────────────────
class _Tag extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _Tag(
      {required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isDark
            ? (color == Colors.blue
                ? const Color(0xFF1A3260)
                : const Color(0xFF2A1A40))
            : (color == Colors.blue
                ? const Color(0xFFE0ECFA)
                : const Color(0xFFF0E5FA)),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
            color: isDark
                ? (color == Colors.blue
                    ? const Color(0xFF264580)
                    : const Color(0xFF4A2A60))
                : (color == Colors.blue
                    ? const Color(0xFFC4D8F5)
                    : const Color(0xFFD8B8F0))),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color),
          ),
        ],
      ),
    );
  }
}
