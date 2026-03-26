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

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _tab.addListener(() {
      if (_tab.index == 2 && _history.isEmpty) { _loadHistory(); }
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

  Future<void> _init() async { await _load(); _subscribeRealtime(); }

  Future<void> _load() async {
    if (_branchId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    try {
      final ordRes = await Supabase.instance.client
          .from('orders')
          .select('*, restaurant_tables(table_number), order_items(*, menu_items(name))')
          .eq('branch_id', _branchId!)
          .inFilter('status', ['new', 'preparing', 'ready', 'served'])
          .order('created_at', ascending: false);
      final tblRes = await Supabase.instance.client
          .from('restaurant_tables').select()
          .eq('branch_id', _branchId!).order('table_number');
      if (mounted) {
        setState(() {
          _orders = (ordRes as List).map((e) => OrderModel.fromJson(e)).toList();
          _tables = (tblRes as List).map((e) => TableModel.fromJson(e)).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) { setState(() => _isLoading = false); }
    }
  }

  Future<void> _loadHistory() async {
    if (_branchId == null) return;
    setState(() => _isHistoryLoading = true);
    try {
      var q = Supabase.instance.client.from('orders').select()
          .eq('branch_id', _branchId!);
      if (_historyFilter == 'paid') {
        q = q.eq('status', 'paid');
      } else if (_historyFilter == 'cancelled') {
        q = q.eq('status', 'cancelled');
      } else {
        q = q.inFilter('status', ['paid', 'cancelled', 'served']);
      }
      final res = await q.order('created_at', ascending: false).limit(200);
      if (mounted) {
        setState(() {
          _history = (res as List).cast<Map<String, dynamic>>();
          _isHistoryLoading = false;
        });
      }
    } catch (_) {
      if (mounted) { setState(() => _isHistoryLoading = false); }
    }
  }

  void _subscribeRealtime() {
    _channel = Supabase.instance.client.channel('order_realtime')
        .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public',
          table: 'orders', callback: (_) => _load())
        .subscribe();
  }

  Color _statusColor(OrderStatus s) {
    switch (s) {
      case OrderStatus.new_:      return AppColors.orderNew;
      case OrderStatus.preparing: return AppColors.orderPreparing;
      case OrderStatus.ready:     return AppColors.orderReady;
      case OrderStatus.served:    return AppColors.primary;
      case OrderStatus.cancelled: return AppColors.textHint;
      case OrderStatus.paid:      return AppColors.available;
    }
  }

  Color _historyStatusColor(String? s) {
    switch (s) {
      case 'paid':      return const Color(0xFF4CAF50);
      case 'cancelled': return const Color(0xFFE94560);
      case 'served':    return const Color(0xFF2196F3);
      default:          return AppColors.textHint;
    }
  }

  String _historyStatusLabel(String? s) {
    switch (s) {
      case 'paid':      return 'Lunas';
      case 'cancelled': return 'Dibatalkan';
      case 'served':    return 'Tersaji';
      default:          return s ?? '-';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AppDrawer(),
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: const Text('Order Management',
          style: TextStyle(fontFamily: 'Poppins', fontSize: 18,
            fontWeight: FontWeight.w600, color: Colors.white)),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
        bottom: TabBar(
          controller: _tab,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorColor: AppColors.accent,
          labelStyle: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600),
          tabs: [
            Tab(text: 'Aktif (${_orders.length})'),
            const Tab(text: 'Order Baru'),
            const Tab(text: 'Riwayat'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(controller: _tab, children: [
              _buildActiveOrders(),
              MenuItemSelector(
                branchId: _branchId ?? '',
                tables: _tables,
                onOrderCreated: () { _load(); _tab.animateTo(0); },
              ),
              _buildHistory(),
            ]),
    );
  }

  Widget _buildActiveOrders() {
    if (_orders.isEmpty) {
      return const Center(child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt_long_outlined, size: 64, color: AppColors.textHint),
          SizedBox(height: 12),
          Text('Tidak ada order aktif',
            style: TextStyle(fontFamily: 'Poppins', color: AppColors.textSecondary)),
        ]));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _orders.length,
      itemBuilder: (_, i) {
        final o = _orders[i];
        final color = _statusColor(o.status);
        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: ExpansionTile(
            leading: CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.15),
              child: Text(o.orderNumber.split('-').last,
                style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                  color: color, fontSize: 12))),
            title: Text(o.tableNumber != null ? 'Meja ${o.tableNumber}' : 'Takeaway',
              style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
            subtitle: Text('${o.items.length} item • ${o.status.label}',
              style: AppTextStyles.caption),
            trailing: Text('Rp ${o.totalAmount.toStringAsFixed(0)}',
              style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                color: AppColors.accent)),
            children: o.items.map((item) => OrderItemTile(item: item)).toList(),
          ));
      });
  }

  Widget _buildHistory() {
    return Column(children: [
      Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final f in [('all','Semua'), ('paid','Lunas'), ('cancelled','Dibatalkan')])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(f.$2, style: const TextStyle(fontFamily: 'Poppins', fontSize: 12)),
                  selected: _historyFilter == f.$1,
                  onSelected: (_) { setState(() { _historyFilter = f.$1; _history = []; }); _loadHistory(); },
                  selectedColor: AppColors.primary.withValues(alpha: 0.15),
                  checkmarkColor: AppColors.primary)),
          ]))),
      Expanded(
        child: _isHistoryLoading
          ? const Center(child: CircularProgressIndicator())
          : _history.isEmpty
              ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.receipt_long_outlined, size: 64, color: AppColors.textHint),
                  SizedBox(height: 12),
                  Text('Tidak ada riwayat order',
                    style: TextStyle(fontFamily: 'Poppins', color: AppColors.textSecondary))]))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _history.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final o = _history[i];
                    final status = o['status'] as String?;
                    final total = (o['total_amount'] as num?)?.toDouble() ?? 0;
                    final created = o['created_at'] as String? ?? '';
                    final dt = DateTime.tryParse(created)?.toLocal();
                    final dateStr = dt != null
                        ? '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}'
                        : '-';
                    return Card(
                      child: ListTile(
                        leading: Container(
                          width: 44, height: 44,
                          decoration: BoxDecoration(
                            color: _historyStatusColor(status).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10)),
                          child: Icon(Icons.receipt_long,
                            color: _historyStatusColor(status), size: 22)),
                        title: Text(o['order_number'] ?? '-',
                          style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
                        subtitle: Text(dateStr, style: AppTextStyles.caption),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: _historyStatusColor(status).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: _historyStatusColor(status).withValues(alpha: 0.4))),
                              child: Text(_historyStatusLabel(status),
                                style: TextStyle(fontFamily: 'Poppins', fontSize: 10,
                                  fontWeight: FontWeight.w600, color: _historyStatusColor(status)))),
                            const SizedBox(height: 4),
                            Text('Rp ${total.toStringAsFixed(0)}',
                              style: const TextStyle(fontFamily: 'Poppins', fontSize: 12,
                                fontWeight: FontWeight.w700)),
                          ])));
                  })),
    ]);
  }
}