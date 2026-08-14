import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/models/order_model.dart';
import '../../../shared/models/order_event_model.dart';
import '../../../shared/providers/order_events_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/order_sound_service.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../shared/widgets/staff_shell.dart';
import '../../../core/models/staff_role.dart';
import '../services/kitchen_inventory_service.dart';

class KDSScreen extends ConsumerStatefulWidget {
  const KDSScreen({super.key});
  @override
  ConsumerState<KDSScreen> createState() => _KDSScreenState();
}

class _KDSScreenState extends ConsumerState<KDSScreen> {
  List<OrderModel> _orders = [];
  int _newOrderCount = 0;
  List<Map<String, dynamic>> _lowStockItems = [];
  bool _isLoading = true;
  String? _branchId;       // branch belonging to the logged-in staff
  StaffRole? _userRole;
  RealtimeChannel? _channel;
  ProviderSubscription<AsyncValue<OrderEvent>>? _orderEventsSub;
  bool _initialized = false;
  final _kitchenInventoryService =
      KitchenInventoryService(Supabase.instance.client);
  final Set<String> _preparingInProgress = {}; // guard: prevent double-tap

  // Multi-branch (superadmin only)
  List<_BranchItem> _branches = [];
  String? _selectedBranchId; // null = all branches

  bool get _isMultiBranchRole => _userRole == StaffRole.superadmin;

  // Purely decorative wall-clock tick so wait-time/overdue labels stay live.
  Timer? _tickTimer;

  @override
  void initState() {
    super.initState();
    _tickTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    final staff = ref.read(currentStaffProvider);
    if (staff != null) {
      _branchId = staff.branchId;
      _userRole = staff.role;
      _initialized = true;
      if (_isMultiBranchRole) _fetchBranches();
      _load();
      _subscribeRealtime();
      _subscribeOrderEvents();
    } else {
      _initialized = true;
      ref.listenManual(currentStaffProvider, (_, next) {
        if (next != null && _branchId == null && mounted) {
          setState(() {
            _branchId = next.branchId;
            _userRole = next.role;
          });
          if (_isMultiBranchRole) _fetchBranches();
          _load();
          _subscribeRealtime();
          _subscribeOrderEvents();
        }
      });
    }
  }

  /// Feeds the "N new orders" banner below and the new-order chime — a
  /// lightweight second subscription alongside _subscribeRealtime()'s
  /// existing full-grid refetch, sourced from order_events (see
  /// order_events_provider.dart) rather than reinventing another raw
  /// orders/order_items channel here.
  ///
  /// Uses the same nullable-branch pattern as _subscribeRealtime() (null =
  /// superadmin "All Branches") and must be re-called whenever
  /// _selectedBranchId changes — previously this only ever watched the
  /// staff's own _branchId once at startup, so a superadmin with no fixed
  /// home branch (branchId null) never subscribed to anything and got no
  /// chime for ANY order, and a superadmin who *did* have one only heard
  /// chimes for that one branch regardless of which branch the "All
  /// Branches"/branch-switcher dropdown was actually showing.
  void _subscribeOrderEvents() {
    if (!_isMultiBranchRole && _branchId == null) return;
    final targetBranch = _isMultiBranchRole ? _selectedBranchId : _branchId;
    _orderEventsSub?.close();
    _orderEventsSub =
        ref.listenManual(orderEventsForBranchProvider(targetBranch), (prev, next) {
      next.whenData((event) {
        final isNewOrder = event.eventType == OrderEventType.statusChanged &&
            event.oldValue == null;
        if (isNewOrder && mounted) {
          setState(() => _newOrderCount++);
          OrderSoundService.playNewOrder();
        }
      });
    });
  }

  Future<void> _fetchBranches() async {
    final res = await Supabase.instance.client
        .from('branches')
        .select('id, name')
        .eq('is_active', true)
        .order('name');
    if (mounted) {
      setState(() {
        _branches = (res as List)
            .map((e) => _BranchItem(id: e['id'], name: e['name']))
            .toList();
      });
    }
  }

  Future<void> _load() async {
    // superadmin: uses _selectedBranchId (null = all branches)
    // other roles: must use their own _branchId
    final targetBranch = _isMultiBranchRole ? _selectedBranchId : _branchId;

    if (!_isMultiBranchRole && targetBranch == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    try {
      // FIX: Explicitly select columns so order_type is guaranteed to be fetched
      // (using * together with a relation sometimes doesn't include all columns)
      // Includes 'ready' alongside 'new'/'created'/'preparing' so the board's
      // "Ready for Runner" column can render real tickets, not just a count.
      var query = Supabase.instance.client
          .from('orders')
          .select('''
            id, branch_id, table_id, order_number,
            status, source, order_type, customer_name,
            discount_amount, notes, created_at, updated_at,
            estimated_prep_minutes,
            restaurant_tables(table_number),
            order_items(
              id, menu_item_id, menu_item_name, unit_price,
              quantity, subtotal, special_requests, status
            )
          ''')
          .inFilter('status', ['new', 'created', 'preparing', 'ready'])
          .gt('total_amount', 0); // exclude empty orders (0 items / Rp 0)

      if (targetBranch != null) {
        query = query.eq('branch_id', targetBranch);
      }

      final res = await query.order('created_at');

      // ── Fetch low stock items ──────────────────────────────────
      List<Map<String, dynamic>> lowStock = [];
      try {
        final today = DateTime.now();
        final todayStr =
            '${today.year}-${today.month.toString().padLeft(2,'0')}-${today.day.toString().padLeft(2,'0')}';
        final lsRes = await Supabase.instance.client
            .from('inventory_items')
            .select('name, unit, opening_stock, used_stock, minimum_stock')
            .eq('branch_id', targetBranch ?? _branchId!)
            .eq('date', todayStr);
        for (final item in lsRes as List) {
          final opening = (item['opening_stock'] ?? 0) as num;
          final used    = (item['used_stock'] ?? 0) as num;
          final minimum = (item['minimum_stock'] ?? 0) as num;
          final closing = opening - used;
          if (closing <= minimum) lowStock.add(item);
        }
      } catch (e) {
        debugPrint('⚠️ Failed to fetch low stock: $e');
      }
      // ──────────────────────────────────────────────────────────

      if (mounted) {
        setState(() {
          _orders = (res as List)
              .map((e) => OrderModel.fromJson(e))
              .where((o) => o.items.isNotEmpty) // double-check: skip orders with no items
              .toList();
          _lowStockItems = lowStock; // FIX Bug 1: assign to state so the banner shows
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('KDS load error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _subscribeRealtime() {
    _channel?.unsubscribe();

    // Determine the branch used for the realtime filter.
    // Superadmin with no branch filter → subscribe to all (null = no filter).
    // Other roles → filter to their own branch.
    final targetBranch = _isMultiBranchRole ? _selectedBranchId : _branchId;

    var channelBuilder = Supabase.instance.client
        .channel('kds_realtime_${DateTime.now().millisecondsSinceEpoch}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          // filter per branch unless it's a superadmin "all branches" view
          filter: targetBranch != null
              ? PostgresChangeFilter(
                  type: PostgresChangeFilterType.eq,
                  column: 'branch_id',
                  value: targetBranch)
              : null,
          callback: (_) { if (mounted) _load(); },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'order_items',
          callback: (_) { if (mounted) _load(); },
        );

    _channel = channelBuilder.subscribe();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    _orderEventsSub?.close();
    _tickTimer?.cancel();
    super.dispose();
  }

  // ── FIX: Add sent_to_kitchen_at when the kitchen starts cooking ───────────
  // ── NEW: Deduct inventory stock per the menu recipe when cooking starts ───
  Future<void> _markPreparing(String orderId) async {
    if (_preparingInProgress.contains(orderId)) return; // prevent double-tap
    _preparingInProgress.add(orderId);

    final now = DateTime.now().toIso8601String();

    try {
      // Update order status + record the time cooking started
      await Supabase.instance.client.from('orders').update({
        'status':     'preparing',
        'updated_at': now,
      }).eq('id', orderId);

      // Record sent_to_kitchen_at on all order_items belonging to this order
      // This is the starting point for measuring actual_prep_time for ML training data
      await Supabase.instance.client.from('order_items').update({
        'sent_to_kitchen_at': now,
      }).eq('order_id', orderId);

      // ── Deduct inventory stock per the recipe (menu_ingredients) ────────
      // Done right when the order starts cooking (not when the order is
      // created), matching the flow: kitchen starts cooking → ingredients
      // are automatically consumed.
      final order = _orders.firstWhere(
        (o) => o.id == orderId,
        orElse: () => OrderModel(
          id: orderId,
          branchId: '',
          orderNumber: '',
          status: OrderStatus.preparing,
          source: OrderSource.dineIn,
          createdAt: DateTime.now(),
        ),
      );

      if (order.branchId.isNotEmpty && order.items.isNotEmpty) {
        final result = await _kitchenInventoryService.deductStockForOrder(
          order: order,
          createdBy: ref.read(currentStaffProvider)?.id,
        );

        if (mounted && result.hasWarnings) {
          final warnings = <String>[
            if (result.menusWithoutRecipe.isNotEmpty)
              'No recipe yet: ${result.menusWithoutRecipe.join(', ')}',
            if (result.notFoundInInventory.isNotEmpty)
              'Ingredients not found in inventory: ${result.notFoundInInventory.join(', ')}',
          ];
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('⚠️ ${warnings.join(' • ')}'),
              backgroundColor: Colors.orange.shade700,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('KDS _markPreparing error: $e');
    } finally {
      _preparingInProgress.remove(orderId);
    }
  }

  Future<void> _markReady(String orderId) async {
    final now = DateTime.now().toIso8601String();

    await Supabase.instance.client.from('orders').update({
      'status':     'ready',
      'updated_at': now,
    }).eq('id', orderId);

    // prepared_at already existed before, still populated here
    await Supabase.instance.client.from('order_items').update({
      'status':      'ready',
      'prepared_at': now,
    }).eq('order_id', orderId);
  }

  /// Mark 1 item as ready to serve (without changing the overall order status)
  Future<void> _markItemReady(String itemId, String orderId) async {
    final now = DateTime.now().toIso8601String();
    await Supabase.instance.client.from('order_items').update({
      'status':      'ready',
      'prepared_at': now,
    }).eq('id', itemId);

    // Check whether all items in this order are ready → auto-update the order too
    final remaining = await Supabase.instance.client
        .from('order_items')
        .select('id')
        .eq('order_id', orderId)
        .neq('status', 'ready');

    if ((remaining as List).isEmpty) {
      await Supabase.instance.client.from('orders').update({
        'status':     'ready',
        'updated_at': now,
      }).eq('id', orderId);
    }
  }

  bool _isNewOrder(OrderModel order) =>
      order.status == OrderStatus.new_ || order.status == OrderStatus.created;

  bool _isQrOrder(OrderModel order) => order.orderType == 'qr_order';

  String _orderSourceLabel(OrderModel order) {
    if (_isQrOrder(order)) return 'QR Order';
    if (order.orderType == 'app_order') return 'App Order';
    if (order.orderType == 'takeaway') return 'App Order (Takeaway)';
    return 'Staff Order';
  }

  List<OrderModel> get _newOrders => _orders.where(_isNewOrder).toList();
  List<OrderModel> get _preparingOrders =>
      _orders.where((o) => o.status == OrderStatus.preparing).toList();
  List<OrderModel> get _readyOrders =>
      _orders.where((o) => o.status == OrderStatus.ready).toList();

  bool _isOverdue(OrderModel order) {
    if (order.status != OrderStatus.preparing) return false;
    final estimate = order.estimatedPrepMinutes ?? 20;
    return DateTime.now().difference(order.createdAt).inMinutes > estimate;
  }

  String _elapsedLabel(DateTime since) {
    // Clamped to zero: a negative elapsed time is never meaningful (it
    // means `since` is in the future relative to this client, e.g. clock
    // skew or a timestamp stored without a timezone offset — see the fix
    // in qr_order_repository.dart for one such case) and showing "-19:-58"
    // instead of "00:00" just reads as broken rather than informative.
    final elapsed = DateTime.now().difference(since);
    if (elapsed.isNegative) return '00:00';
    final mm = elapsed.inMinutes.remainder(100).toString().padLeft(2, '0');
    final ss = elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  String _ticketLabel(OrderModel order) =>
      order.tableNumber != null ? 'T-${order.tableNumber}' : '#${order.orderNumber}';

  @override
  Widget build(BuildContext context) {
    return StaffShell(
      pageTitle: 'Kitchen Display',
      activeRoute: AppRoutes.kitchen,
      topBarActions: _topBarActions(),
      body: Column(children: [
        if (_newOrderCount > 0) _buildNewOrderBanner(),
        if (_lowStockItems.isNotEmpty) _buildLowStockBanner(),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
              : _orders.isEmpty
                  ? _buildEmptyState()
                  : RefreshIndicator(
                      onRefresh: _load,
                      color: AppColors.primary,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildColumn(
                              title: 'New',
                              headerColor: AppColors.primary,
                              headerTextColor: Colors.white,
                              orders: _newOrders,
                            ),
                            const SizedBox(width: AppSpacing.md),
                            _buildColumn(
                              title: 'In Progress',
                              headerColor: AppColors.textSecondary,
                              headerTextColor: Colors.white,
                              orders: _preparingOrders,
                            ),
                            const SizedBox(width: AppSpacing.md),
                            _buildColumn(
                              title: 'Ready for Runner',
                              headerColor: AppColors.statusClosed,
                              headerTextColor: AppColors.textPrimary,
                              orders: _readyOrders,
                            ),
                          ],
                        ),
                      ),
                    ),
        ),
      ]),
    );
  }

  // ── Top bar actions: branch filter (superadmin) + active/refresh ────────
  List<Widget> _topBarActions() {
    return [
      if (_isMultiBranchRole)
        Padding(
          padding: const EdgeInsets.only(right: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              border: Border.all(color: AppColors.border),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: _selectedBranchId,
                isDense: true,
                icon: const Icon(Icons.keyboard_arrow_down,
                    size: 16, color: AppColors.textSecondary),
                style: const TextStyle(
                    fontFamily: 'Poppins', fontSize: 12, color: AppColors.textPrimary),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('All Branches',
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 12))),
                  ..._branches.map((b) => DropdownMenuItem<String?>(
                        value: b.id,
                        child: Text(b.name,
                            style: const TextStyle(fontFamily: 'Poppins', fontSize: 12)))),
                ],
                onChanged: (val) {
                  setState(() {
                    _selectedBranchId = val;
                    _isLoading = true;
                  });
                  _load();
                  _subscribeRealtime();
                  _subscribeOrderEvents();
                },
              ),
            ),
          ),
        ),
      Container(
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: _orders.isEmpty ? AppColors.surfaceVariant : AppColors.accent,
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        ),
        child: Text('${_orders.length} Active',
          style: TextStyle(
            fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w700,
            color: _orders.isEmpty ? AppColors.textSecondary : Colors.white)),
      ),
      IconButton(
        icon: const Icon(Icons.refresh_rounded, color: AppColors.textSecondary),
        onPressed: _load,
      ),
    ];
  }

  Widget _buildNewOrderBanner() {
    return InkWell(
      onTap: () => setState(() => _newOrderCount = 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 10),
        color: AppColors.primary,
        child: Row(children: [
          const Icon(Icons.notifications_active_rounded, color: Colors.white, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _newOrderCount == 1
                  ? '1 new order came in'
                  : '$_newOrderCount new orders came in',
              style: const TextStyle(
                fontFamily: 'Poppins', color: Colors.white,
                fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
          const Icon(Icons.close_rounded, color: Colors.white70, size: 16),
        ]),
      ),
    );
  }

  Widget _buildLowStockBanner() {
    final names = _lowStockItems
        .map((i) => '${i['name']} (${i['unit']})')
        .join(', ');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 10),
      color: AppColors.accentOrange,
      child: Row(children: [
        const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Stock running low: $names',
            style: const TextStyle(
              fontFamily: 'Poppins', color: Colors.white,
              fontWeight: FontWeight.w600, fontSize: 12),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ]),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100, height: 100,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.10), shape: BoxShape.circle),
            child: const Icon(Icons.check_circle_outline, size: 60, color: AppColors.primary),
          ),
          const SizedBox(height: 20),
          const Text('All orders done! 🎉',
            style: TextStyle(
              fontFamily: 'Poppins', fontSize: 20,
              fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          const Text('Waiting for new orders...',
            style: TextStyle(fontFamily: 'Poppins', color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  // ── Kanban column ────────────────────────────────────────────────────────
  Widget _buildColumn({
    required String title,
    required Color headerColor,
    required Color headerTextColor,
    required List<OrderModel> orders,
  }) {
    return SizedBox(
      width: 380,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: headerColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(AppSpacing.radiusMd)),
            ),
            child: Row(children: [
              Text(title.toUpperCase(),
                style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 15,
                  fontWeight: FontWeight.w800, letterSpacing: 0.4,
                  color: headerTextColor)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                ),
                child: Text(
                  orders.length == 1 ? '1 Order' : '${orders.length} Orders',
                  style: const TextStyle(
                    fontFamily: 'Poppins', fontSize: 11,
                    fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              ),
            ]),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant.withValues(alpha: 0.5),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(AppSpacing.radiusMd)),
              ),
              child: orders.isEmpty
                  ? Center(
                      child: Text('No orders',
                        style: TextStyle(
                          fontFamily: 'Poppins', fontSize: 13,
                          color: AppColors.textSecondary.withValues(alpha: 0.7))))
                  : ListView.separated(
                      itemCount: orders.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (_, i) => _buildTicket(orders[i]),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Ticket card ───────────────────────────────────────────────────────────
  Widget _buildTicket(OrderModel order) {
    final isNew    = _isNewOrder(order);
    final isReady  = order.status == OrderStatus.ready;
    final overdue  = _isOverdue(order);
    final source   = _orderSourceLabel(order);

    return Container(
      decoration: BoxDecoration(
        color: overdue ? AppColors.accent.withValues(alpha: 0.08) : AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(
          color: overdue ? AppColors.accent : AppColors.border,
          width: overdue ? 1.6 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header: ticket id + wait time / overdue / done ────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_ticketLabel(order),
                      style: TextStyle(
                        fontFamily: 'Poppins', fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: overdue
                            ? AppColors.accent
                            : (isReady ? AppColors.textSecondary : AppColors.textPrimary))),
                    const SizedBox(height: 2),
                    Text(source,
                      style: const TextStyle(
                        fontFamily: 'Poppins', fontSize: 12,
                        fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              if (isReady)
                const Icon(Icons.check_circle_rounded, color: AppColors.available, size: 26)
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(_elapsedLabel(order.createdAt),
                      style: TextStyle(
                        fontFamily: 'Poppins', fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: overdue ? AppColors.accent : AppColors.textPrimary)),
                    Text(overdue ? 'OVERDUE' : (isNew ? 'Wait Time' : 'Cooking'),
                      style: TextStyle(
                        fontFamily: 'Poppins', fontSize: 10,
                        fontWeight: FontWeight.w700, letterSpacing: 0.4,
                        color: overdue ? AppColors.accent : AppColors.textSecondary)),
                  ],
                ),
            ]),
          ),
          const Divider(height: 1, color: AppColors.border),

          // ── Items ────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: order.items.map((item) {
                final notes     = item.specialRequests;
                final itemReady = item.status == OrderItemStatus.ready;
                // Per-item toggle only useful while the order is cooking.
                final showToggle = order.status == OrderStatus.preparing && !itemReady;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${item.quantity}x',
                      style: TextStyle(
                        fontFamily: 'Poppins', fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: itemReady ? AppColors.textSecondary : AppColors.accent)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.menuItemName,
                            style: TextStyle(
                              fontFamily: 'Poppins', fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: itemReady ? AppColors.textSecondary : AppColors.textPrimary,
                              decoration: itemReady ? TextDecoration.lineThrough : null)),
                          if (notes != null && notes.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text('- $notes',
                                style: const TextStyle(
                                  fontFamily: 'Poppins', fontSize: 13,
                                  fontStyle: FontStyle.italic,
                                  color: AppColors.textSecondary)),
                            ),
                        ],
                      ),
                    ),
                    if (showToggle)
                      IconButton(
                        icon: const Icon(Icons.check_circle_outline_rounded, size: 22),
                        color: AppColors.available,
                        tooltip: 'Ready to serve',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => _markItemReady(item.id, order.id),
                      )
                    else if (itemReady)
                      const Icon(Icons.check_circle_rounded, size: 20, color: AppColors.available),
                  ]),
                );
              }).toList(),
            ),
          ),

          // ── Primary action ───────────────────────────────────────────────
          if (!isReady)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
              child: SizedBox(
                width: double.infinity, height: 48,
                child: ElevatedButton(
                  onPressed: () => isNew ? _markPreparing(order.id) : _markReady(order.id),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isNew ? AppColors.accent : AppColors.available,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSm)),
                  ),
                  child: Text(isNew ? 'BUMP' : 'MARK READY',
                    style: const TextStyle(
                      fontFamily: 'Poppins', fontWeight: FontWeight.w800,
                      fontSize: 14, letterSpacing: 0.4)),
                ),
              ),
            )
          else
            const SizedBox(height: 14),
        ],
      ),
    );
  }
}

// ── Helper model ───────────────────────────────────────────────────────
class _BranchItem {
  final String id;
  final String name;
  _BranchItem({required this.id, required this.name});
}
