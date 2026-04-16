import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/models/order_model.dart';
import '../../../shared/models/table_model.dart';
import '../../../core/theme/app_theme.dart';
import '../../../features/auth/providers/auth_provider.dart';
import 'widgets/order_item_tile.dart';
import 'widgets/menu_item_selector.dart';
import '../../../shared/widgets/app_drawer.dart';

class OrderScreen extends ConsumerStatefulWidget {
  const OrderScreen({super.key});

  @override
  ConsumerState<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends ConsumerState<OrderScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  List<OrderModel> _orders = [];
  List<Map<String, dynamic>> _history = [];
  List<TableModel> _tables = [];
  bool _isLoading = true;
  bool _isHistoryLoading = false;
  String? _branchId;
  RealtimeChannel? _channel;
  String _historyFilter = 'all';
  String? _updatingOrderId;
  String _selectedGroup = '';

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _tab.addListener(() {
      if (_tab.index == 2 && _history.isEmpty) _loadHistory();
    });
  }

  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      final staff = ref.read(currentStaffProvider);
      if (staff != null) {
        _branchId = staff.branchId;
        _initialized = true;
        _init();
      } else {
        ref.listenManual(currentStaffProvider, (_, next) {
          if (next != null && !_initialized && mounted) {
            setState(() { _branchId = next.branchId; _initialized = true; });
            _init();
          }
        });
        _initialized = true;
      }
    }
  }

  @override
  void dispose() {
    _tab.dispose();
    _channel?.unsubscribe();
    super.dispose();
  }

  Future<void> _init() async {
    await _load();
    _subscribeRealtime();
  }

  Future<void> _load() async {
    if (_branchId == null) { if (mounted) setState(() => _isLoading = false); return; }
    if (mounted) setState(() => _isLoading = true);
    try {
      final activeStatuses = ['new', 'created', 'paid', 'preparing', 'ready', 'served'];
      final ordRes = await Supabase.instance.client
          .from('orders')
          .select('*, restaurant_tables!orders_table_id_fkey(table_number), order_items(*)')
          .eq('branch_id', _branchId!)
          .inFilter('status', activeStatuses)
          .order('created_at', ascending: false);
      final tblRes = await Supabase.instance.client
          .from('restaurant_tables')
          .select()
          .eq('branch_id', _branchId!)
          .order('table_number');
      if (mounted) {
        setState(() {
          _orders = (ordRes as List).map((e) => OrderModel.fromJson(e)).toList();
          _tables = (tblRes as List).map((e) => TableModel.fromJson(e)).toList();
          _isLoading = false;
        });
      }
    } catch (e, st) {
      debugPrint('ERROR LOAD: $e\n$st');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadHistory() async {
    if (_branchId == null) return;
    if (mounted) setState(() => _isHistoryLoading = true);
    try {
      var query = Supabase.instance.client
          .from('orders')
          .select('*, restaurant_tables!orders_table_id_fkey(table_number), order_items(*, menu_items(name))')
          .eq('branch_id', _branchId!);
      if (_historyFilter == 'paid') {
        query = query.inFilter('status', ['paid', 'served']);
      } else if (_historyFilter == 'cancelled') {
        query = query.eq('status', 'cancelled');
      } else {
        query = query.inFilter('status', ['paid', 'preparing', 'ready', 'served', 'cancelled']);
      }
      final res = await query.order('created_at', ascending: false).limit(200);
      if (mounted) {
        setState(() {
          _history = (res as List).cast<Map<String, dynamic>>();
          _isHistoryLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isHistoryLoading = false);
    }
  }

  void _subscribeRealtime() {
    _channel?.unsubscribe();
    if (_branchId == null) return;
    _channel = Supabase.instance.client
        .channel('orders_realtime_$_branchId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all, schema: 'public', table: 'orders',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'branch_id', value: _branchId!),
          callback: (_) { if (mounted) _load(); },
        ).subscribe();
  }

  bool _isQrOrder(OrderModel o) => o.orderType == 'qr_order';

  Color _statusColor(OrderStatus s) {
    switch (s) {
      case OrderStatus.new_:
      case OrderStatus.created:   return AppColors.orderNew;
      case OrderStatus.preparing: return AppColors.orderPreparing;
      case OrderStatus.ready:     return AppColors.orderReady;
      case OrderStatus.served:    return AppColors.primary;
      case OrderStatus.cancelled: return AppColors.textHint;
      default:                    return AppColors.textHint;
    }
  }

  OrderStatus? _nextStatus(OrderStatus current) {
    switch (current) {
      case OrderStatus.new_:
      case OrderStatus.created:    return OrderStatus.preparing;
      case OrderStatus.preparing:  return OrderStatus.ready;
      case OrderStatus.ready:      return OrderStatus.served;
      default:                     return null;
    }
  }

  String _nextStatusLabel(OrderStatus current) {
    switch (current) {
      case OrderStatus.new_:
      case OrderStatus.created:    return 'Mulai Masak';
      case OrderStatus.preparing:  return 'Tandai Siap';
      case OrderStatus.ready:      return '✓ Sudah Diantar';
      default:                     return '';
    }
  }

  IconData _nextStatusIcon(OrderStatus current) {
    switch (current) {
      case OrderStatus.new_:
      case OrderStatus.created:    return Icons.soup_kitchen_outlined;
      case OrderStatus.preparing: return Icons.check_circle_outline;
      case OrderStatus.ready:     return Icons.room_service_outlined;
      default:                    return Icons.arrow_forward;
    }
  }

  Future<void> _updateOrderStatus(OrderModel order) async {
    final next = _nextStatus(order.status);
    if (next == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: _statusColor(next).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
            child: Icon(_nextStatusIcon(order.status), color: _statusColor(next), size: 20)),
          const SizedBox(width: 10),
          Text(_nextStatusLabel(order.status), style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 16)),
        ]),
        content: RichText(text: TextSpan(
          style: const TextStyle(fontFamily: 'Poppins', fontSize: 13, color: AppColors.textPrimary, height: 1.5),
          children: [
            const TextSpan(text: 'Update order '),
            TextSpan(text: '#${order.orderNumber}', style: const TextStyle(fontWeight: FontWeight.w700)),
            const TextSpan(text: ' ke '),
            TextSpan(text: next.label, style: TextStyle(fontWeight: FontWeight.w700, color: _statusColor(next))),
            const TextSpan(text: '?'),
          ],
        )),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal', style: TextStyle(fontFamily: 'Poppins', color: AppColors.textSecondary))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: _statusColor(next), foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: Text(_nextStatusLabel(order.status), style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600))),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _updatingOrderId = order.id);
    try {
      final staff = ref.read(currentStaffProvider);
      await Supabase.instance.client.from('orders').update({
        'status': next.dbValue, 'staff_id': staff?.id, 'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', order.id);

      // Sync order_items status agar konsisten dengan orders
      await Supabase.instance.client.from('order_items').update({
        'status': next.dbValue,
      }).eq('order_id', order.id);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Order #${order.orderNumber} → ${next.label}'),
        backgroundColor: _statusColor(next), duration: const Duration(seconds: 2)));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Gagal update status order.'), backgroundColor: AppColors.accent));
    } finally {
      if (mounted) setState(() => _updatingOrderId = null);
    }
  }

  // ── Group definitions ──────────────────────────────────────────────────────
  static const _groupDefs = [
    _GroupDef('Antri Masak',     Icons.restaurant_menu_outlined,   Color(0xFFFF9800)),
    _GroupDef('Sedang Dimasak',  Icons.outdoor_grill_outlined,     Color(0xFFE53935)),
    _GroupDef('Siap Disajikan',  Icons.dining_outlined,            Color(0xFF43A047)),
    _GroupDef('Sudah Tersaji',   Icons.check_circle_outline,       Color(0xFF1E88E5)),
  ];

  Map<String, List<OrderModel>> _groupOrders(List<OrderModel> orders) {
    final groups = <String, List<OrderModel>>{for (final g in _groupDefs) g.name: []};
    for (final o in orders) {
      switch (o.status) {
        case OrderStatus.new_:
        case OrderStatus.created:   groups['Antri Masak']!.add(o); break;
        case OrderStatus.preparing: groups['Sedang Dimasak']!.add(o); break;
        case OrderStatus.ready:     groups['Siap Disajikan']!.add(o); break;
        case OrderStatus.served:    groups['Sudah Tersaji']!.add(o); break;
        default: break;
      }
    }
    return groups;
  }

  Color _historyStatusColor(String? s) {
    switch (s) {
      case 'paid':      return const Color(0xFF4CAF50);
      case 'served':    return const Color(0xFF4CAF50);
      case 'cancelled': return const Color(0xFFE94560);
      default:          return AppColors.textHint;
    }
  }

  String _historyStatusLabel(String? s) {
    switch (s) {
      case 'paid':      return 'Lunas';
      case 'served':    return 'Tersaji';
      case 'cancelled': return 'Dibatalkan';
      default:          return s ?? '-';
    }
  }

  String _formatDate(String? iso) {
    if (iso == null) return '-';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '-';
    return '${dt.day.toString().padLeft(2,'0')}/${dt.month.toString().padLeft(2,'0')}/${dt.year}  ${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AppDrawer(),
      backgroundColor: AppColors.background,
      body: Column(children: [
        // ── Custom AppBar ────────────────────────────────────────────────────
        Container(
          color: AppColors.primary,
          child: SafeArea(
            bottom: false,
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(children: [
                  Builder(builder: (ctx) => IconButton(
                    icon: const Icon(Icons.menu, color: Colors.white),
                    onPressed: () => Scaffold.of(ctx).openDrawer())),
                  const Expanded(child: Text('Order Management',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 18,
                      fontWeight: FontWeight.w600, color: Colors.white))),
                  IconButton(icon: const Icon(Icons.refresh, color: Colors.white), onPressed: _load),
                ]),
              ),
              // Tab bar
              TabBar(
                controller: _tab,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white60,
                indicatorColor: AppColors.accent,
                indicatorWeight: 3,
                labelStyle: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 13),
                unselectedLabelStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
                tabs: [
                  Tab(text: 'Aktif (${_orders.length})'),
                  const Tab(text: 'Order Baru'),
                  const Tab(text: 'Riwayat'),
                ],
              ),
            ]),
          ),
        ),

        // ── Body ─────────────────────────────────────────────────────────────
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : TabBarView(
                  controller: _tab,
                  children: [
                    _buildActiveOrders(),
                    _buildNewOrder(),
                    _buildHistory(),
                  ],
                ),
        ),
      ]),
    );
  }

  // ── TAB: AKTIF ────────────────────────────────────────────────────────────
  Widget _buildActiveOrders() {
    final grouped = _groupOrders(_orders);
    final activeGroups = _groupDefs.where((g) => (grouped[g.name] ?? []).isNotEmpty).toList();

    if (_orders.isEmpty) {
      return const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.receipt_long_outlined, size: 64, color: AppColors.textHint),
        SizedBox(height: 12),
        Text('Tidak ada order aktif', style: TextStyle(fontFamily: 'Poppins', color: AppColors.textSecondary)),
      ]));
    }

    // Auto-select
    if (_selectedGroup.isEmpty || !activeGroups.any((g) => g.name == _selectedGroup)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && activeGroups.isNotEmpty) setState(() => _selectedGroup = activeGroups.first.name);
      });
    }

    final currentOrders = grouped[_selectedGroup] ?? [];
    final currentGroupDef = _groupDefs.firstWhere((g) => g.name == _selectedGroup,
        orElse: () => _groupDefs.first);

    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // ── Sidebar kiri ──────────────────────────────────────────────────────
      Container(
        width: 120,
        height: double.infinity,
        decoration: const BoxDecoration(
          color: Color(0xFF1A1F2E),
          boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(2, 0))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 16, 14, 10),
            child: Text('STATUS', style: TextStyle(
              fontFamily: 'Poppins', fontSize: 9, fontWeight: FontWeight.w700,
              color: Colors.white38, letterSpacing: 1.5)),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 16),
              children: _groupDefs.map((def) {
                final count = (grouped[def.name] ?? []).length;
                if (count == 0) return const SizedBox.shrink();
                final isSelected = _selectedGroup == def.name;

                return GestureDetector(
                  onTap: () => setState(() => _selectedGroup = def.name),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected ? def.color : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      border: isSelected ? null : Border.all(color: def.color.withValues(alpha: 0.2)),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Icon(def.icon, size: 14,
                          color: isSelected ? Colors.white : def.color),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isSelected ? Colors.white.withValues(alpha: 0.25) : def.color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10)),
                          child: Text('$count', style: TextStyle(
                            fontFamily: 'Poppins', fontSize: 10, fontWeight: FontWeight.w700,
                            color: isSelected ? Colors.white : def.color))),
                      ]),
                      const SizedBox(height: 6),
                      Text(def.name, style: TextStyle(
                        fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w600,
                        color: isSelected ? Colors.white : Colors.white60,
                        height: 1.3)),
                    ]),
                  ),
                );
              }).toList(),
            ),
          ),
        ]),
      ),

      // ── Konten kanan ──────────────────────────────────────────────────────
      Expanded(
        child: Column(children: [
          // Header group
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            decoration: BoxDecoration(
              color: currentGroupDef.color.withValues(alpha: 0.07),
              border: Border(bottom: BorderSide(color: currentGroupDef.color.withValues(alpha: 0.15)))),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: currentGroupDef.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8)),
                child: Icon(currentGroupDef.icon, color: currentGroupDef.color, size: 16)),
              const SizedBox(width: 10),
              Text(_selectedGroup, style: TextStyle(
                fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                fontSize: 14, color: currentGroupDef.color)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: currentGroupDef.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10)),
                child: Text('${currentOrders.length} order', style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w600,
                  color: currentGroupDef.color))),
            ]),
          ),

          // Order list
          Expanded(
            child: currentOrders.isEmpty
                ? const Center(child: Text('Tidak ada order'))
                : ListView.builder(
                    padding: const EdgeInsets.all(10),
                    itemCount: currentOrders.length,
                    itemBuilder: (_, i) => _buildOrderCard(currentOrders[i]),
                  ),
          ),
        ]),
      ),
    ]);
  }

  Widget _buildOrderCard(OrderModel o) {
    final color = _statusColor(o.status);
    final nextS = _nextStatus(o.status);
    final isUpdating = _updatingOrderId == o.id;
    final isQr = _isQrOrder(o);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withValues(alpha: 0.2))),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: CircleAvatar(
          radius: 20,
          backgroundColor: color.withValues(alpha: 0.12),
          child: Text(o.orderNumber.split('-').last,
            style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, color: color, fontSize: 11))),
        title: Row(children: [
          Text(o.tableNumber != null ? 'Meja ${o.tableNumber}' : 'Takeaway',
            style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 14)),
          if (o.customerName != null) ...[
            const SizedBox(width: 6),
            Flexible(child: Text('• ${o.customerName}',
              style: AppTextStyles.caption, overflow: TextOverflow.ellipsis)),
          ],
        ]),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(children: [
            // QR / Staff badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isQr ? const Color(0xFF7C3AED).withValues(alpha: 0.08) : AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: isQr ? const Color(0xFF7C3AED).withValues(alpha: 0.3) : AppColors.primary.withValues(alpha: 0.3))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(isQr ? Icons.qr_code_scanner : Icons.person_outline, size: 9,
                  color: isQr ? const Color(0xFF7C3AED) : AppColors.primary),
                const SizedBox(width: 3),
                Text(isQr ? 'QR' : 'Staff', style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 9, fontWeight: FontWeight.w700,
                  color: isQr ? const Color(0xFF7C3AED) : AppColors.primary)),
              ])),
            const SizedBox(width: 6),
            Text('${o.items.length} item', style: AppTextStyles.caption),
          ]),
        ),
        trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('Rp ${o.totalAmount.toStringAsFixed(0)}',
            style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, color: AppColors.accent, fontSize: 13)),
        ]),
        children: [
          // Items
          ...o.items.map((item) => OrderItemTile(item: item)),

          // Notes order
          if (o.notes != null && o.notes!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.reserved.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.reserved.withValues(alpha: 0.3))),
                child: Row(children: [
                  const Icon(Icons.notes, size: 13, color: AppColors.reserved),
                  const SizedBox(width: 6),
                  Expanded(child: Text(o.notes!, style: const TextStyle(fontFamily: 'Poppins', fontSize: 12, color: AppColors.reserved))),
                ]))),

          const Divider(height: 1),

          // Action button
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: nextS != null
                    ? SizedBox(
                        width: double.infinity,
                        // Tombol "Sudah Diantar" (ready→served) tampil lebih besar & hijau terang
                        // agar waiter mudah tap setelah antar ke meja
                        child: ElevatedButton.icon(
                          onPressed: isUpdating ? null : () => _updateOrderStatus(o),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: o.status == OrderStatus.ready
                                ? Colors.green.shade600
                                : _statusColor(nextS),
                            foregroundColor: Colors.white,
                            elevation: o.status == OrderStatus.ready ? 3 : 0,
                            shadowColor: o.status == OrderStatus.ready
                                ? Colors.green.withValues(alpha: 0.4)
                                : null,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: EdgeInsets.symmetric(
                              vertical: o.status == OrderStatus.ready ? 13 : 10)),
                          icon: isUpdating
                              ? const SizedBox(width: 16, height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : Icon(_nextStatusIcon(o.status), size: 18),
                          label: Text(
                            isUpdating ? 'Memperbarui...' : _nextStatusLabel(o.status),
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w700,
                              fontSize: o.status == OrderStatus.ready ? 14 : 13))))
                    : o.status == OrderStatus.served
                        ? _infoChip(Icons.point_of_sale_outlined, 'Menunggu pembayaran di kasir', Colors.orange)
                        : _infoChip(Icons.check_circle_outline, 'Selesai', AppColors.available),
          ),
        ],
      ),
    );
  }

  Widget _infoChip(IconData icon, String label, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25))),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: color, fontWeight: FontWeight.w500)),
      ]),
    );
  }

  // ── TAB: ORDER BARU (Menu Selector) ──────────────────────────────────────
  Widget _buildNewOrder() {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Sidebar kiri: pilih meja
      Container(
        width: 120,
        height: double.infinity,
        decoration: const BoxDecoration(
          color: Color(0xFF1A1F2E),
          boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(2, 0))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 16, 14, 10),
            child: Text('MEJA', style: TextStyle(
              fontFamily: 'Poppins', fontSize: 9, fontWeight: FontWeight.w700,
              color: Colors.white38, letterSpacing: 1.5)),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 16),
              children: [
                // Takeaway option
                const _TableSidebarItem(
                  label: 'Takeaway',
                  icon: Icons.takeout_dining_outlined,
                  color: AppColors.accent,
                  isSelected: false,
                  count: null,
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(14, 12, 14, 6),
                  child: Text('MEJA', style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 9, fontWeight: FontWeight.w700,
                    color: Colors.white24, letterSpacing: 1.5)),
                ),
                ..._tables.map((t) => _TableSidebarItem(
                  label: 'Meja ${t.tableNumber}',
                  icon: Icons.table_restaurant_outlined,
                  color: t.status == TableStatus.available ? const Color(0xFF43A047) : Colors.orange,
                  isSelected: false,
                  count: t.capacity,
                )),
              ],
            ),
          ),
        ]),
      ),

      // Content kanan: menu selector
      Expanded(
        child: MenuItemSelector(
          branchId: _branchId ?? '',
          tables: _tables,
          onOrderCreated: () { _load(); _tab.animateTo(0); },
        ),
      ),
    ]);
  }

  // ── TAB: RIWAYAT ──────────────────────────────────────────────────────────
  Widget _buildHistory() {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Sidebar kiri: filter
      Container(
        width: 120,
        height: double.infinity,
        decoration: const BoxDecoration(
          color: Color(0xFF1A1F2E),
          boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(2, 0))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 16, 14, 10),
            child: Text('FILTER', style: TextStyle(
              fontFamily: 'Poppins', fontSize: 9, fontWeight: FontWeight.w700,
              color: Colors.white38, letterSpacing: 1.5)),
          ),
          ...[
            ('all', 'Semua', Icons.receipt_long_outlined, Colors.white),
            ('paid', 'Lunas', Icons.check_circle_outline, const Color(0xFF43A047)),
            ('cancelled', 'Dibatalkan', Icons.cancel_outlined, const Color(0xFFE53935)),
          ].map((f) {
            final isSelected = _historyFilter == f.$1;
            final color = f.$4;
            return GestureDetector(
              onTap: () {
                setState(() { _historyFilter = f.$1; _history = []; });
                _loadHistory();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected ? color.withValues(alpha: 0.2) : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: isSelected ? Border.all(color: color.withValues(alpha: 0.4)) : null),
                child: Row(children: [
                  Icon(f.$3, size: 14, color: isSelected ? color : Colors.white38),
                  const SizedBox(width: 8),
                  Text(f.$2, style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 11, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                    color: isSelected ? color : Colors.white54)),
                ]),
              ),
            );
          }),
        ]),
      ),

      // Content kanan
      Expanded(
        child: _isHistoryLoading
            ? const Center(child: CircularProgressIndicator())
            : _history.isEmpty
                ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.receipt_long_outlined, size: 64, color: AppColors.textHint),
                    SizedBox(height: 12),
                    Text('Tidak ada riwayat', style: TextStyle(fontFamily: 'Poppins', color: AppColors.textSecondary)),
                  ]))
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _history.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (_, i) {
                      final o = _history[i];
                      final status = o['status'] as String?;
                      final orderType = o['order_type'] as String?;
                      final total = (o['total_amount'] as num?)?.toDouble() ?? 0;
                      final statusColor = _historyStatusColor(status);
                      final rawItems = o['order_items'] as List? ?? [];
                      final isQr = orderType == 'qr_order';

                      return Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: statusColor.withValues(alpha: 0.2))),
                        child: ExpansionTile(
                          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                          leading: Container(
                            width: 40, height: 40,
                            decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                            child: Icon(Icons.receipt_long, color: statusColor, size: 20)),
                          title: Row(children: [
                            Text(o['order_number'] ?? '-',
                              style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 13)),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: isQr ? const Color(0xFF7C3AED).withValues(alpha: 0.10) : AppColors.primary.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(4)),
                              child: Text(isQr ? 'QR' : 'Staff', style: TextStyle(
                                fontFamily: 'Poppins', fontSize: 9, fontWeight: FontWeight.w700,
                                color: isQr ? const Color(0xFF7C3AED) : AppColors.primary))),
                          ]),
                          subtitle: Text(_formatDate(o['created_at'] as String?), style: AppTextStyles.caption),
                          trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: statusColor.withValues(alpha: 0.4))),
                              child: Text(_historyStatusLabel(status),
                                style: TextStyle(fontFamily: 'Poppins', fontSize: 10, fontWeight: FontWeight.w600, color: statusColor))),
                            const SizedBox(height: 4),
                            Text('Rp ${total.toStringAsFixed(0)}',
                              style: const TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w700)),
                          ]),
                          children: [
                            if (rawItems.isNotEmpty) ...[
                              const Divider(height: 1),
                              ...rawItems.map((item) {
                                final name = (item['menu_items'] as Map?)?['name'] as String? ?? item['menu_item_name'] as String? ?? '-';
                                final qty = item['quantity'] as int? ?? 0;
                                final sub = (item['subtotal'] as num?)?.toDouble() ?? 0;
                                final notes = item['special_requests'] as String?;
                                return ListTile(
                                  dense: true,
                                  leading: Container(
                                    width: 28, height: 28,
                                    decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                                    child: Center(child: Text('$qty', style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 12, color: AppColors.primary)))),
                                  title: Text(name, style: const TextStyle(fontFamily: 'Poppins', fontSize: 13)),
                                  subtitle: notes != null && notes.isNotEmpty
                                      ? Text('📝 $notes', style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: AppColors.reserved))
                                      : null,
                                  trailing: Text('Rp ${sub.toStringAsFixed(0)}', style: const TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w600)));
                              }),
                            ],
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                              child: Row(children: [
                                const Spacer(),
                                const Text('Total: ', style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: AppColors.textSecondary)),
                                Text('Rp ${total.toStringAsFixed(0)}', style: const TextStyle(fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.accent)),
                              ])),
                          ],
                        ),
                      );
                    }),
      ),
    ]);
  }
}

// ── Helper data class ──────────────────────────────────────────────────────────
class _GroupDef {
  final String name;
  final IconData icon;
  final Color color;
  const _GroupDef(this.name, this.icon, this.color);
}

// ── Sidebar table item widget ──────────────────────────────────────────────────
class _TableSidebarItem extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool isSelected;
  final int? count;

  const _TableSidebarItem({
    required this.label,
    required this.icon,
    required this.color,
    required this.isSelected,
    this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: isSelected ? color.withValues(alpha: 0.2) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: isSelected ? Border.all(color: color.withValues(alpha: 0.4)) : null,
      ),
      child: Row(children: [
        Icon(icon, size: 13, color: isSelected ? color : Colors.white38),
        const SizedBox(width: 7),
        Expanded(child: Text(label, style: TextStyle(
          fontFamily: 'Poppins', fontSize: 11,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          color: isSelected ? color : Colors.white54),
          overflow: TextOverflow.ellipsis)),
        if (count != null)
          Text('$count org', style: const TextStyle(fontFamily: 'Poppins', fontSize: 9, color: Colors.white24)),
      ]),
    );
  }
}