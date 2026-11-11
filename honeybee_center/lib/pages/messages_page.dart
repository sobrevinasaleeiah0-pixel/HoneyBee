import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/theme/app_theme.dart';
import '../services/auth_service.dart';
import '../services/conversation_service.dart';
import '../services/supabase_data_service.dart';
import '../core/permissions/admin_capabilities.dart';

class MessagesPage extends StatefulWidget {
  final AuthSession session;

  const MessagesPage({super.key, required this.session});

  @override
  State<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends State<MessagesPage> {
  final _service = ConversationService();
  final _orderService = SupabaseDataService();
  final _searchController = TextEditingController();
  final _replyController = TextEditingController();
  final _scrollController = ScrollController();
  final _imagePicker = ImagePicker();

  List<Map<String, dynamic>> _inbox = [];
  String? _selectedEntryKey;
  String _search = '';
  String? _loadError;
  XFile? _pendingImage;
  bool _loading = true;
  bool _sending = false;
  int _inboxFilter = 0;
  int _loadGeneration = 0;
  final Set<String> _markingReadConversations = {};
  final Set<String> _updatingOrders = {};
  RealtimeChannel? _realtimeChannel;

  bool get _canReply =>
      RoleCapabilities.forRole(widget.session.role).canReplyMessages;

  Map<String, dynamic>? get _selectedConversation {
    for (final conversation in _inbox) {
      if (_entryKey(conversation) == _selectedEntryKey) {
        return conversation;
      }
    }
    return null;
  }

  String _entryKey(Map<String, dynamic> entry) =>
      entry['conversation_id']?.toString() ??
      'customer:${entry['customer_id']}';

  @override
  void initState() {
    super.initState();
    _loadInbox();
    _subscribeToChanges();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _replyController.dispose();
    _scrollController.dispose();
    final channel = _realtimeChannel;
    if (channel != null) {
      unawaited(Supabase.instance.client.removeChannel(channel));
    }
    super.dispose();
  }

  void _subscribeToChanges() {
    _realtimeChannel = Supabase.instance.client
        .channel('admin-customer-conversations')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'messages',
          callback: (_) => _loadInbox(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'conversations',
          callback: (_) => _loadInbox(),
        )
        .subscribe((status, error) {
          if (status == RealtimeSubscribeStatus.channelError ||
              status == RealtimeSubscribeStatus.timedOut) {
            _showError('Realtime messaging updates are unavailable: $error');
          }
        });
  }

  Future<void> _loadInbox() async {
    final generation = ++_loadGeneration;
    try {
      final inbox = await _service.fetchInbox();
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _inbox = inbox;
        _loadError = null;
        _loading = false;
        if (_selectedEntryKey != null &&
            !inbox.any((item) => _entryKey(item) == _selectedEntryKey)) {
          _selectedEntryKey = null;
        }
      });
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loadError = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _selectConversation(Map<String, dynamic> conversation) async {
    final id = conversation['conversation_id']?.toString();
    setState(() => _selectedEntryKey = _entryKey(conversation));
    if (id == null || id.isEmpty) return;
    try {
      await _service.markRead(id);
      await _loadInbox();
    } catch (error) {
      _showError('Could not mark conversation as read: $error');
    }
  }

  Future<void> _markIncomingMessagesRead(
    String conversationId,
    List<Map<String, dynamic>> messages,
  ) async {
    final hasUnreadCustomerMessage = messages.any(
      (message) =>
          message['sender_role'] == 'customer' && message['is_read'] != true,
    );
    if (!hasUnreadCustomerMessage ||
        !_markingReadConversations.add(conversationId)) {
      return;
    }
    try {
      await _service.markRead(conversationId);
      await _loadInbox();
    } catch (error) {
      _showError('Could not mark incoming messages as read: $error');
    } finally {
      _markingReadConversations.remove(conversationId);
    }
  }

  Future<void> _chooseImage() async {
    try {
      final image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1800,
        maxHeight: 1800,
      );
      if (image != null && mounted) {
        setState(() => _pendingImage = image);
      }
    } catch (error) {
      _showError('Could not select image: $error');
    }
  }

  Future<void> _sendReply() async {
    final conversationId = _selectedConversation?['conversation_id']
        ?.toString();
    final text = _replyController.text.trim();
    final image = _pendingImage;
    if (conversationId == null || (text.isEmpty && image == null) || _sending) {
      return;
    }
    if (!_canReply) {
      _showError('Only Co-Admins can reply to customer conversations.');
      return;
    }

    setState(() => _sending = true);
    try {
      if (image == null) {
        await _service.sendText(conversationId: conversationId, message: text);
      } else {
        await _service.sendImage(
          conversationId: conversationId,
          adminUid: widget.session.uid,
          image: image,
          message: text,
        );
      }
      if (!mounted) return;
      _replyController.clear();
      setState(() {
        _pendingImage = null;
        _sending = false;
      });
      await _loadInbox();
    } catch (error) {
      if (!mounted) return;
      setState(() => _sending = false);
      _showError('Could not send message: $error');
    }
  }

  Future<void> _setConversationStatus(String status) async {
    final conversationId = _selectedConversation?['conversation_id']
        ?.toString();
    if (conversationId == null || !_canReply) return;
    try {
      await _service.setStatus(conversationId, status);
      await _loadInbox();
    } catch (error) {
      _showError('Could not update conversation: $error');
    }
  }

  Future<void> _setOrderStatus(
    Map<String, dynamic> order,
    String status,
  ) async {
    if (!_canReply) {
      _showError('Only Co-Admins can update order statuses.');
      return;
    }
    final orderId = order['id']?.toString();
    if (orderId == null || !_updatingOrders.add(orderId)) return;
    setState(() {});
    try {
      await _orderService.updateOrderStatus(orderId, status);
      await _loadInbox();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Order status updated to $status.')),
      );
    } catch (error) {
      _showError('Could not update order status: $error');
    } finally {
      _updatingOrders.remove(orderId);
      if (mounted) setState(() {});
    }
  }

  Future<void> _verifyPayment(Map<String, dynamic> order) async {
    if (!_canReply) {
      _showError('Only Co-Admins can verify payments.');
      return;
    }
    final orderId = order['id']?.toString();
    if (orderId == null || !_updatingOrders.add(orderId)) return;
    setState(() {});
    try {
      await _orderService.updatePaymentStatus(orderId, 'Confirmed');
      await _loadInbox();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment verified successfully.')),
      );
    } catch (error) {
      _showError('Could not verify payment: $error');
    } finally {
      _updatingOrders.remove(orderId);
      if (mounted) setState(() {});
    }
  }

  void _useQuickReply(String reply) {
    _replyController
      ..text = reply
      ..selection = TextSelection.collapsed(offset: reply.length);
  }

  Future<void> _showOrderDetails(Map<String, dynamic> order) async {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final items = order['items'] is List
        ? (order['items'] as List).whereType<Map>().toList()
        : const <Map>[];
    final reference =
        order['reference']?.toString() ?? order['id']?.toString() ?? 'Order';
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(reference),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _DetailItem(
                  label: 'Order status',
                  value: order['status']?.toString() ?? 'Unknown',
                  dark: dark,
                ),
                _DetailItem(
                  label: 'Payment status',
                  value: order['payment_status']?.toString() ?? 'Pending',
                  dark: dark,
                ),
                _DetailItem(
                  label: 'Payment method',
                  value: order['payment_method']?.toString() ?? '',
                  dark: dark,
                ),
                _DetailItem(
                  label: 'Payment reference',
                  value: order['payment_reference']?.toString() ?? '',
                  dark: dark,
                ),
                _DetailItem(
                  label: 'Payment proof',
                  value: order['payment_proof_url']?.toString() ?? '',
                  dark: dark,
                ),
                _DetailItem(
                  label: 'Order total',
                  value: _formatPeso(order['total']),
                  dark: dark,
                ),
                if (items.isNotEmpty) ...[
                  const Divider(),
                  Text(
                    'Items',
                    style: TextStyle(
                      color: AppTheme.textPrimary(dark),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...items.map((item) {
                    final name = item['product_name']?.toString() ?? 'Product';
                    final size = item['bottle_size']?.toString() ?? '';
                    final quantity = item['quantity']?.toString() ?? '1';
                    final subtotal = _formatPeso(item['subtotal']);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '$name${size.isEmpty ? '' : ' · $size'} × $quantity',
                              style: TextStyle(
                                color: AppTheme.textPrimary(dark),
                              ),
                            ),
                          ),
                          Text(
                            subtotal,
                            style: TextStyle(
                              color: AppTheme.textPrimary(dark),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppTheme.error),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final selected = _selectedConversation;
    return Scaffold(
      backgroundColor: AppTheme.pageBackground(dark),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(dark),
            if (_loadError != null) _buildErrorBanner(dark),
            const SizedBox(height: 16),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final showDetails = constraints.maxWidth >= 900;
                  final inboxWidth = showDetails
                      ? (constraints.maxWidth * 0.29).clamp(220.0, 310.0)
                      : constraints.maxWidth < 760
                      ? 260.0
                      : 310.0;
                  final detailsWidth = showDetails
                      ? (constraints.maxWidth * 0.25).clamp(230.0, 300.0)
                      : 0.0;
                  return Row(
                    children: [
                      SizedBox(width: inboxWidth, child: _buildInbox(dark)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: selected == null
                            ? _buildEmptyConversation(dark)
                            : selected['conversation_id'] == null
                            ? _buildCustomerProfile(selected, dark)
                            : _buildThread(selected, dark),
                      ),
                      if (showDetails) ...[
                        const SizedBox(width: 12),
                        SizedBox(
                          width: detailsWidth,
                          child: selected == null
                              ? _buildDetailsEmpty(dark)
                              : _buildCustomerDetails(selected, dark),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool dark) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Messages',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.textPrimary(dark),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'Customer conversations and support',
                style: TextStyle(color: AppTheme.textSecondary(dark)),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Refresh conversations',
          onPressed: _loadInbox,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    );
  }

  Widget _buildErrorBanner(bool dark) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(top: 12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppTheme.mutedPanel(dark),
      border: Border.all(color: AppTheme.error),
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
    ),
    child: Row(
      children: [
        const Icon(Icons.error_outline, color: AppTheme.error),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Could not load conversations: $_loadError',
            style: TextStyle(color: AppTheme.textPrimary(dark)),
          ),
        ),
        TextButton(onPressed: _loadInbox, child: const Text('Retry')),
      ],
    ),
  );

  int _conversationBucket(Map<String, dynamic> conversation) {
    if (conversation['conversation_id'] == null) return 0;
    final status = conversation['conversation_status']
        ?.toString()
        .toLowerCase();
    if (status == 'resolved') return 2;
    final lastSender = conversation['last_sender_role']?.toString();
    return lastSender == 'co_admin' ||
            lastSender == 'main_admin' ||
            lastSender == 'admin'
        ? 1
        : 0;
  }

  Widget _buildInbox(bool dark) {
    final filtered = _inbox.where((conversation) {
      if (_conversationBucket(conversation) != _inboxFilter) return false;
      final query = _search.trim().toLowerCase();
      if (query.isEmpty) return true;
      return [
        conversation['customer_name'],
        conversation['customer_email'],
        conversation['last_message'],
        conversation['order_reference'],
      ].any(
        (value) => value?.toString().toLowerCase().contains(query) ?? false,
      );
    }).toList();

    return Container(
      decoration: AppTheme.adminPanelDecoration(dark),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 15, 14, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Customer inbox',
                        style: TextStyle(
                          color: AppTheme.textPrimary(dark),
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    Text(
                      '${_inbox.length}',
                      style: TextStyle(
                        color: AppTheme.textSecondary(dark),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _searchController,
                  onChanged: (value) => setState(() => _search = value),
                  decoration: AppTheme.searchInputDecoration(
                    dark,
                    hintText: 'Search customers...',
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _InboxFilterTab(
                      label: 'Open',
                      count: _inbox
                          .where((entry) => _conversationBucket(entry) == 0)
                          .length,
                      selected: _inboxFilter == 0,
                      dark: dark,
                      onTap: () => setState(() => _inboxFilter = 0),
                    ),
                    _InboxFilterTab(
                      label: 'Pending customer',
                      count: _inbox
                          .where((entry) => _conversationBucket(entry) == 1)
                          .length,
                      selected: _inboxFilter == 1,
                      dark: dark,
                      onTap: () => setState(() => _inboxFilter = 1),
                    ),
                    _InboxFilterTab(
                      label: 'Resolved',
                      count: _inbox
                          .where((entry) => _conversationBucket(entry) == 2)
                          .length,
                      selected: _inboxFilter == 2,
                      dark: dark,
                      onTap: () => setState(() => _inboxFilter = 2),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _inbox.isEmpty
                ? _emptyInbox(dark)
                : filtered.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Text(
                        _search.isEmpty
                            ? 'No ${_inboxFilter == 0
                                  ? 'open'
                                  : _inboxFilter == 1
                                  ? 'pending'
                                  : 'resolved'} conversations.'
                            : 'No matching customers or conversations.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppTheme.textSecondary(dark)),
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final conversation = filtered[index];
                      return _ConversationTile(
                        conversation: conversation,
                        selected: _entryKey(conversation) == _selectedEntryKey,
                        onTap: () => _selectConversation(conversation),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _emptyInbox(bool dark) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.forum_outlined,
            size: 42,
            color: AppTheme.textSecondary(dark),
          ),
          const SizedBox(height: 12),
          Text(
            'No linked active customers yet',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppTheme.textPrimary(dark),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Customers linked to an account and conversations will appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textSecondary(dark), fontSize: 12),
          ),
        ],
      ),
    ),
  );

  Widget _buildEmptyConversation(bool dark) => Container(
    decoration: AppTheme.adminPanelDecoration(dark),
    child: Center(
      child: Text(
        'Select a customer conversation',
        style: TextStyle(color: AppTheme.textSecondary(dark)),
      ),
    ),
  );

  Widget _buildCustomerProfile(Map<String, dynamic> customer, bool dark) {
    final name = customer['customer_name']?.toString() ?? 'Customer';
    final email = customer['customer_email']?.toString() ?? '';
    return Container(
      decoration: AppTheme.adminPanelDecoration(dark),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Avatar(name: name, size: 64),
              const SizedBox(height: 14),
              Text(
                name,
                style: TextStyle(
                  color: AppTheme.textPrimary(dark),
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (email.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  email,
                  style: TextStyle(color: AppTheme.textSecondary(dark)),
                ),
              ],
              const SizedBox(height: 20),
              Text(
                'No conversation yet',
                style: TextStyle(
                  color: AppTheme.textPrimary(dark),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'This customer will appear in the chat when they send their first message.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textSecondary(dark)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThread(Map<String, dynamic> conversation, bool dark) {
    final conversationId = conversation['conversation_id'].toString();
    return Container(
      decoration: AppTheme.adminPanelDecoration(dark),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _buildThreadHeader(conversation, dark),
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _service.watchMessages(conversationId),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Could not load message history: ${snapshot.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppTheme.error),
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final messages = snapshot.data!;
                unawaited(_markIncomingMessagesRead(conversationId, messages));
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_scrollController.hasClients) {
                    _scrollController.jumpTo(
                      _scrollController.position.maxScrollExtent,
                    );
                  }
                });
                if (messages.isEmpty) {
                  return Center(
                    child: Text(
                      'No messages in this conversation.',
                      style: TextStyle(color: AppTheme.textSecondary(dark)),
                    ),
                  );
                }
                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 20,
                  ),
                  itemCount: messages.length,
                  itemBuilder: (context, index) =>
                      _MessageBubble(message: messages[index]),
                );
              },
            ),
          ),
          _buildComposer(dark),
        ],
      ),
    );
  }

  Widget _buildThreadHeader(Map<String, dynamic> conversation, bool dark) {
    final name = conversation['customer_name']?.toString() ?? 'Customer';
    final status = conversation['conversation_status']?.toString() ?? 'open';
    final order = conversation['order_reference']?.toString();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.panelBorder(dark))),
      ),
      child: Row(
        children: [
          _Avatar(name: name, size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary(dark),
                  ),
                ),
                Text(
                  order == null ? 'Customer conversation' : 'Order $order',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary(dark),
                  ),
                ),
              ],
            ),
          ),
          _StatusChip(
            status: status,
            label: status == 'resolved'
                ? 'Resolved'
                : conversation['last_sender_role'] == 'customer'
                ? 'Needs reply'
                : 'Open',
          ),
          if (_canReply) ...[
            const SizedBox(width: 8),
            PopupMenuButton<String>(
              tooltip: 'Conversation actions',
              onSelected: _setConversationStatus,
              itemBuilder: (_) => [
                if (status != 'resolved')
                  const PopupMenuItem(
                    value: 'resolved',
                    child: Text('Mark resolved'),
                  ),
                if (status == 'resolved')
                  const PopupMenuItem(value: 'open', child: Text('Reopen')),
              ],
              child: const Icon(Icons.more_vert_rounded),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildComposer(bool dark) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      border: Border(top: BorderSide(color: AppTheme.panelBorder(dark))),
    ),
    child: Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            runSpacing: 4,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 2),
                child: Text(
                  'Quick replies',
                  style: TextStyle(
                    color: AppTheme.textSecondary(dark),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              for (final reply in const [
                'Payment received, thank you!',
                'We are preparing your order.',
                'Your order is ready for pickup.',
              ])
                ActionChip(
                  visualDensity: VisualDensity.compact,
                  label: Text(reply),
                  onPressed: _canReply && !_sending
                      ? () => _useQuickReply(reply)
                      : null,
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (_pendingImage != null)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.mutedPanel(dark),
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            ),
            child: Row(
              children: [
                const Icon(Icons.image_outlined, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _pendingImage!.name,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: 'Remove image',
                  visualDensity: VisualDensity.compact,
                  onPressed: _sending
                      ? null
                      : () => setState(() => _pendingImage = null),
                  icon: const Icon(Icons.close, size: 18),
                ),
              ],
            ),
          ),
        Row(
          children: [
            IconButton(
              tooltip: 'Attach product image',
              onPressed: _canReply && !_sending ? _chooseImage : null,
              icon: const Icon(Icons.image_outlined),
            ),
            Expanded(
              child: TextField(
                controller: _replyController,
                enabled: _canReply && !_sending,
                minLines: 1,
                maxLines: 4,
                onSubmitted: (_) => _sendReply(),
                decoration: InputDecoration(
                  hintText: _canReply
                      ? 'Write a reply...'
                      : 'Owner can view conversations; Co-Admin replies.',
                  filled: true,
                  fillColor: AppTheme.fieldFill(dark),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    borderSide: BorderSide(color: AppTheme.panelBorder(dark)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              tooltip: 'Send message',
              onPressed: _canReply && !_sending ? _sendReply : null,
              icon: _sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_rounded),
            ),
          ],
        ),
        if (!_canReply)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Replying is limited to Co-Admins by the existing database policy.',
                style: TextStyle(
                  color: AppTheme.textSecondary(dark),
                  fontSize: 11,
                ),
              ),
            ),
          ),
      ],
    ),
  );

  Widget _buildCustomerDetails(Map<String, dynamic> conversation, bool dark) {
    final name = conversation['customer_name']?.toString() ?? 'Customer';
    final email = conversation['customer_email']?.toString() ?? '';
    final phone = conversation['customer_phone']?.toString() ?? '';
    final address = conversation['customer_address']?.toString() ?? '';
    final linkedOrderId = conversation['order_id']?.toString();
    final orders = conversation['customer_orders'] is List
        ? (conversation['customer_orders'] as List)
              .whereType<Map>()
              .map((order) => Map<String, dynamic>.from(order))
              .toList()
        : <Map<String, dynamic>>[];
    final conversationId = conversation['conversation_id']?.toString();
    final conversationStatus =
        conversation['conversation_status']?.toString() ?? 'open';
    return Container(
      decoration: AppTheme.adminPanelDecoration(dark),
      padding: const EdgeInsets.all(16),
      child: ListView(
        children: [
          Text(
            'Customer information',
            style: TextStyle(
              color: AppTheme.textPrimary(dark),
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 18),
          Center(child: _Avatar(name: name, size: 64)),
          const SizedBox(height: 10),
          Center(
            child: Text(
              name,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.textPrimary(dark),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 18),
          _DetailItem(label: 'Email', value: email, dark: dark),
          _DetailItem(label: 'Phone', value: phone, dark: dark),
          _DetailItem(label: 'Address', value: address, dark: dark),
          _DetailItem(
            label: 'Total orders',
            value: '${orders.length}',
            dark: dark,
          ),
          const Divider(height: 28),
          Text(
            'Recent orders',
            style: TextStyle(
              color: AppTheme.textPrimary(dark),
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 10),
          if (orders.isEmpty)
            Text(
              'No customer orders were found.',
              style: TextStyle(color: AppTheme.textSecondary(dark)),
            )
          else
            ...orders.map(
              (order) => _OrderDetailsCard(
                order: order,
                isConversationOrder: order['id']?.toString() == linkedOrderId,
                isUpdating: _updatingOrders.contains(order['id']?.toString()),
                canManage: _canReply,
                dark: dark,
                onViewDetails: () => _showOrderDetails(order),
                onPaymentVerify: () => _verifyPayment(order),
                onStatusChanged: (status) => _setOrderStatus(order, status),
              ),
            ),
          if (conversationId != null && _canReply) ...[
            const Divider(height: 28),
            Text(
              'Quick actions',
              style: TextStyle(
                color: AppTheme.textPrimary(dark),
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: conversationStatus == 'resolved'
                    ? () => _setConversationStatus('open')
                    : () => _setConversationStatus('resolved'),
                icon: Icon(
                  conversationStatus == 'resolved'
                      ? Icons.mark_chat_unread_outlined
                      : Icons.check_circle_outline_rounded,
                ),
                label: Text(
                  conversationStatus == 'resolved'
                      ? 'Reopen conversation'
                      : 'Mark resolved',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDetailsEmpty(bool dark) => Container(
    decoration: AppTheme.adminPanelDecoration(dark),
    child: Center(
      child: Text(
        'Customer and order details appear here.',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppTheme.textSecondary(dark)),
      ),
    ),
  );
}

class _InboxFilterTab extends StatelessWidget {
  const _InboxFilterTab({
    required this.label,
    required this.count,
    required this.selected,
    required this.dark,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final bool dark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 3),
        decoration: BoxDecoration(
          color: selected
              ? (dark
                    ? AppTheme.iconBadgeGoldDark
                    : AppTheme.iconBadgeGoldLight)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected
                    ? AppTheme.textPrimary(dark)
                    : AppTheme.textSecondary(dark),
                fontSize: 10,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '$count',
              style: TextStyle(
                color: selected
                    ? AppTheme.primaryGoldDeep
                    : AppTheme.textSecondary(dark),
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.conversation,
    required this.selected,
    required this.onTap,
  });

  final Map<String, dynamic> conversation;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final name = conversation['customer_name']?.toString() ?? 'Customer';
    final preview =
        conversation['last_message']?.toString() ?? 'No message yet';
    final unread = (conversation['unread_count'] as num?)?.toInt() ?? 0;
    final timestamp = _formatTimestamp(conversation['last_message_at']);
    final hasImage = conversation['last_attachment_path'] != null;
    return Material(
      color: selected
          ? (dark ? AppTheme.iconBadgeGoldDark : AppTheme.iconBadgeGoldLight)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              _Avatar(name: name, size: 42),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: unread > 0
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                              color: AppTheme.textPrimary(dark),
                            ),
                          ),
                        ),
                        Text(
                          timestamp,
                          style: TextStyle(
                            fontSize: 10,
                            color: AppTheme.textSecondary(dark),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            hasImage && preview.isEmpty ? '📷 Image' : preview,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary(dark),
                            ),
                          ),
                        ),
                        if (unread > 0)
                          Container(
                            margin: const EdgeInsets.only(left: 6),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: const BoxDecoration(
                              color: AppTheme.accentBlue,
                              borderRadius: BorderRadius.all(
                                Radius.circular(AppTheme.radiusPill),
                              ),
                            ),
                            child: Text(
                              unread > 99 ? '99+' : '$unread',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
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
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final Map<String, dynamic> message;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final role = message['sender_role']?.toString() ?? 'customer';
    final isAdmin =
        role == 'co_admin' || role == 'main_admin' || role == 'admin';
    final isAutomated = role == 'system';
    final text = message['message']?.toString() ?? '';
    final sender = message['sender_name']?.toString() ?? '';
    final time = _formatTimestamp(message['created_at']);
    final path = message['attachment_path']?.toString();

    return Align(
      alignment: isAutomated
          ? Alignment.center
          : isAdmin
          ? Alignment.centerRight
          : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth:
              MediaQuery.sizeOf(context).width * (isAutomated ? 0.7 : 0.5),
        ),
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isAutomated
              ? AppTheme.mutedPanel(dark)
              : isAdmin
              ? (dark ? AppTheme.primaryGold : const Color(0xFF17130B))
              : AppTheme.panelColor(dark),
          borderRadius: BorderRadius.circular(14),
          border: isAdmin && !isAutomated
              ? null
              : Border.all(color: AppTheme.panelBorder(dark)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (sender.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text(
                  sender,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                    color: isAutomated
                        ? AppTheme.primaryGoldDeep
                        : isAdmin
                        ? (dark ? Colors.black87 : Colors.white70)
                        : AppTheme.textSecondary(dark),
                  ),
                ),
              ),
            if (path != null) _SignedImage(path: path),
            if (text.isNotEmpty)
              Text(
                text,
                style: TextStyle(
                  color: isAdmin && !isAutomated
                      ? (dark ? Colors.black : Colors.white)
                      : AppTheme.textPrimary(dark),
                  height: 1.4,
                ),
              ),
            const SizedBox(height: 5),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                time,
                style: TextStyle(
                  fontSize: 10,
                  color: isAdmin
                      ? (dark ? Colors.black54 : Colors.white60)
                      : AppTheme.textSecondary(dark),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SignedImage extends StatefulWidget {
  const _SignedImage({required this.path});

  final String path;

  @override
  State<_SignedImage> createState() => _SignedImageState();
}

class _SignedImageState extends State<_SignedImage> {
  late Future<String> _urlFuture;

  @override
  void initState() {
    super.initState();
    _urlFuture = ConversationService().signedImageUrl(widget.path);
  }

  @override
  void didUpdateWidget(covariant _SignedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _urlFuture = ConversationService().signedImageUrl(widget.path);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _urlFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'Image unavailable',
              style: TextStyle(color: AppTheme.error),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const SizedBox(
            width: 220,
            height: 140,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.network(
              snapshot.data!,
              width: 260,
              fit: BoxFit.cover,
              errorBuilder: (_, error, _) => const SizedBox(
                width: 220,
                height: 100,
                child: Center(
                  child: Text(
                    'Could not display image',
                    style: TextStyle(color: AppTheme.error),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DetailItem extends StatelessWidget {
  const _DetailItem({
    required this.label,
    required this.value,
    required this.dark,
  });
  final String label;
  final String value;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 11, color: AppTheme.textSecondary(dark)),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: AppTheme.textPrimary(dark),
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderDetailsCard extends StatelessWidget {
  const _OrderDetailsCard({
    required this.order,
    required this.isConversationOrder,
    required this.isUpdating,
    required this.canManage,
    required this.dark,
    required this.onViewDetails,
    required this.onPaymentVerify,
    required this.onStatusChanged,
  });

  final Map<String, dynamic> order;
  final bool isConversationOrder;
  final bool isUpdating;
  final bool canManage;
  final bool dark;
  final VoidCallback onViewDetails;
  final VoidCallback onPaymentVerify;
  final ValueChanged<String> onStatusChanged;

  @override
  Widget build(BuildContext context) {
    final reference =
        order['reference']?.toString() ?? order['id']?.toString() ?? 'Order';
    final status = order['status']?.toString() ?? 'Unknown';
    final paymentStatus = order['payment_status']?.toString() ?? 'Pending';
    final total = _formatPeso(order['total']);
    final isPaymentVerificationOrder =
        SupabaseDataService.isPaymentVerificationOrder({
          'paymentMethod': order['payment_method'],
          'paymentReferenceNumber': order['payment_reference'],
          'paymentProofUrl': order['payment_proof_url'],
        });
    final isPaymentPending =
        SupabaseDataService.paymentVerificationStatus({
          'paymentStatus': paymentStatus,
        }) ==
        'Pending Verification';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.mutedPanel(dark),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(
          color: isConversationOrder
              ? AppTheme.primaryGold
              : AppTheme.panelBorder(dark),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  reference,
                  style: TextStyle(
                    color: AppTheme.textPrimary(dark),
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
              if (isConversationOrder)
                const Icon(
                  Icons.link_rounded,
                  size: 15,
                  color: AppTheme.primaryGoldDeep,
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  status,
                  style: TextStyle(
                    color: AppTheme.textSecondary(dark),
                    fontSize: 11,
                  ),
                ),
              ),
              Text(
                total,
                style: TextStyle(
                  color: AppTheme.textPrimary(dark),
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              Icon(
                paymentStatus == 'Confirmed' || paymentStatus == 'Paid'
                    ? Icons.check_circle_rounded
                    : Icons.payments_outlined,
                size: 14,
                color: paymentStatus == 'Confirmed' || paymentStatus == 'Paid'
                    ? AppTheme.success
                    : AppTheme.warning,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  'Payment: $paymentStatus',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppTheme.textSecondary(dark),
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 4,
            runSpacing: 0,
            children: [
              TextButton(
                onPressed: isUpdating ? null : onViewDetails,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                ),
                child: const Text('View details'),
              ),
              if (canManage && isPaymentVerificationOrder && isPaymentPending)
                TextButton.icon(
                  onPressed: isUpdating ? null : onPaymentVerify,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                  ),
                  icon: isUpdating
                      ? const SizedBox(
                          width: 13,
                          height: 13,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.verified_outlined, size: 15),
                  label: const Text('Verify'),
                ),
              if (canManage)
                PopupMenuButton<String>(
                  tooltip: 'Change order status',
                  enabled: !isUpdating,
                  onSelected: onStatusChanged,
                  itemBuilder: (context) => [
                    for (final value in const [
                      'Pending',
                      'Confirmed',
                      'Preparing',
                      'Ready for Pickup',
                      'Completed',
                      'Cancelled',
                    ])
                      PopupMenuItem<String>(
                        value: value,
                        enabled: value != status,
                        child: Text(value),
                      ),
                  ],
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 8,
                    ),
                    child: Text(
                      'Update status',
                      style: TextStyle(
                        color: isUpdating
                            ? AppTheme.textSecondary(dark)
                            : AppTheme.primaryGoldDeep,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, required this.size});
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? 'C' : name.trim()[0].toUpperCase();
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: AppTheme.iconBadgeGoldLight,
      child: Text(
        initial,
        style: TextStyle(
          color: AppTheme.primaryGoldDeep,
          fontWeight: FontWeight.w800,
          fontSize: size * .38,
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status, required this.label});
  final String status;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: status == 'resolved'
          ? AppTheme.badgeGreenBgLight
          : AppTheme.badgeGoldBgLight,
      borderRadius: BorderRadius.circular(AppTheme.radiusPill),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 10,
        color: status == 'resolved'
            ? AppTheme.success
            : AppTheme.primaryGoldDeep,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

String _formatTimestamp(dynamic value) {
  if (value == null) return '';
  final dateTime = DateTime.tryParse(value.toString())?.toLocal();
  if (dateTime == null) return '';
  final now = DateTime.now();
  if (dateTime.year == now.year &&
      dateTime.month == now.month &&
      dateTime.day == now.day) {
    return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
  return '${dateTime.month}/${dateTime.day}';
}

String _formatPeso(dynamic value) {
  if (value is num) return '₱${value.toStringAsFixed(2)}';
  final amount = num.tryParse(value?.toString() ?? '');
  return amount == null ? '₱0.00' : '₱${amount.toStringAsFixed(2)}';
}
