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
        debugPrint('Branch ID loaded: $_branchId');
        _initialized = true;
        _init();
      } else {
        ref.listenManual(currentStaffProvider, (_, next) {
          if (next != null && !_initialized && mounted) {
            setState(() {
              _branchId = next.branchId;
              _initialized = true;
            });
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

  // ── LOAD ACTIVE ORDERS ────────────────────────────────────────────────────
  Future<void> _load() async {
    if (_branchId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    if (mounted) setState(() => _isLoading = true);

    try {
      // Semua status aktif termasuk 'paid' (QR sudah bayar, menunggu dapur)
      final activeStatuses = ['new', 'created', 'paid', 'preparing', 'ready', 'served'];

      final ordRes = await Supabase.instance.client
          .from('orders')
          .select('''
            *,
            restaurant_tables!orders_table_id_fkey(table_number),
            order_items(*)
          ''')
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
          _orders = (ordRes as List<dynamic>)
              .map((e) => OrderModel.fromJson(e as Map<String, dynamic>))
              .toList();
          _tables = (tblRes as List<dynamic>)
              .map((e) => TableModel.fromJson(e as Map<String, dynamic>))
              .toList();
          _isLoading = false;
        });
      }
    } catch (e, st) {
      debugPrint('ERROR LOAD ORDERS: $e\n$st');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memuat order: $e'),
            backgroundColor: Colors.red, duration: const Duration(seconds: 5)));
      }
    }
  }

  // ── LOAD HISTORY ──────────────────────────────────────────────────────────
  Future<void> _loadHistory() async {
    if (_branchId == null) return;
    if (mounted) setState(() => _isHistoryLoading = true);

    try {
      var query = Supabase.instance.client
          .from('orders')
          .select('''
            *,
            restaurant_tables!orders_table_id_fkey(table_number),
            order_items(*, menu_items(name))
          ''')
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
          _history = (res as List<dynamic>).cast<Map<String, dynamic>>();
          _isHistoryLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error load history: $e');
      if (mounted) setState(() => _isHistoryLoading = false);
    }
  }

  // ── REALTIME ──────────────────────────────────────────────────────────────
  void _subscribeRealtime() {
    _channel?.unsubscribe();
    if (_branchId == null) return;
    _channel = Supabase.instance.client
        .channel('orders_realtime_$_branchId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'branch_id',
            value: _branchId!,
          ),
          callback: (_) { if (mounted) _load(); },
        )
        .subscribe();
  }

  // ── STATUS HELPERS ────────────────────────────────────────────────────────
  bool _isQrOrder(OrderModel o) =>
      o.orderType == 'qr_order' || o.status == OrderStatus.paid;

  Color _statusColor(OrderStatus s) {
    switch (s) {
      case OrderStatus.new_:
      case OrderStatus.created:
        return AppColors.orderNew;
      case OrderStatus.paid:
        return const Color(0xFF7C3AED); // ungu untuk QR paid
      case OrderStatus.preparing:
        return AppColors.orderPreparing;
      case OrderStatus.ready:
        return AppColors.orderReady;
      case OrderStatus.served:
        return AppColors.primary;
      case OrderStatus.cancelled:
        return AppColors.textHint;
    }
  }

  // ✅ FIX: paid → preparing (QR order sudah bayar, staff bisa update ke masak)
  OrderStatus? _nextStatus(OrderStatus current) {
    switch (current) {
      case OrderStatus.new_:
      case OrderStatus.created:
      case OrderStatus.paid:      // ← FIX: paid juga bisa lanjut ke preparing
        return OrderStatus.preparing;
      case OrderStatus.preparing:
        return OrderStatus.ready;
      case OrderStatus.ready:
        return OrderStatus.served;
      default:
        return null;
    }
  }

  String _nextStatusLabel(OrderStatus current) {
    switch (current) {
      case OrderStatus.new_:
      case OrderStatus.created:
      case OrderStatus.paid:      // ← FIX
        return 'Mulai Masak';
      case OrderStatus.preparing:
        return 'Tandai Siap';
      case OrderStatus.ready:
        return 'Tandai Tersaji';
      default:
        return '';
    }
  }

  IconData _nextStatusIcon(OrderStatus current) {
    switch (current) {
      case OrderStatus.new_:
      case OrderStatus.created:
      case OrderStatus.paid:      // ← FIX
        return Icons.soup_kitchen_outlined;
      case OrderStatus.preparing:
        return Icons.check_circle_outline;
      case OrderStatus.ready:
        return Icons.room_service_outlined;
      default:
        return Icons.arrow_forward;
    }
  }

  // ── UPDATE STATUS ─────────────────────────────────────────────────────────
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
            decoration: BoxDecoration(
              color: _statusColor(next).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8)),
            child: Icon(_nextStatusIcon(order.status),
              color: _statusColor(next), size: 20)),
          const SizedBox(width: 10),
          Text(_nextStatusLabel(order.status),
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w700, fontSize: 16)),
        ]),
        content: RichText(
          text: TextSpan(
            style: const TextStyle(
              fontFamily: 'Poppins', fontSize: 13,
              color: AppColors.textPrimary, height: 1.5),
            children: [
              const TextSpan(text: 'Update order '),
              TextSpan(text: '#${order.orderNumber}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
              const TextSpan(text: ' ke '),
              TextSpan(text: next.label,
                style: TextStyle(
                  fontWeight: FontWeight.w700, color: _statusColor(next))),
              const TextSpan(text: '?'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal',
              style: TextStyle(fontFamily: 'Poppins', color: AppColors.textSecondary))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _statusColor(next),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: Text(_nextStatusLabel(order.status),
              style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600))),
        ],
      ),
    );

    if (confirmed != true) return;
    setState(() => _updatingOrderId = order.id);

    try {
      final staff = ref.read(currentStaffProvider);
      await Supabase.instance.client.from('orders').update({
        'status': next.dbValue,
        'staff_id': staff?.id,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', order.id);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Order #${order.orderNumber} → ${next.label}'),
        backgroundColor: _statusColor(next),
        duration: const Duration(seconds: 2)));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Gagal update status order.'),
        backgroundColor: AppColors.accent));
    } finally {
      if (mounted) setState(() => _updatingOrderId = null);
    }
  }

  // ── HISTORY HELPERS ───────────────────────────────────────────────────────
  Color _historyStatusColor(String? s) {
    switch (s) {
      case 'paid':   return const Color(0xFF4CAF50);
      case 'served': return const Color(0xFF4CAF50);
      case 'cancelled': return const Color(0xFFE94560);
      default: return AppColors.textHint;
    }
  }

  String _historyStatusLabel(String? s) {
    switch (s) {
      case 'paid':   return 'Lunas';
      case 'served': return 'Tersaji';
      case 'cancelled': return 'Dibatalkan';
      default: return s ?? '-';
    }
  }

  String _formatDate(String? iso) {
    if (iso == null) return '-';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '-';
    return '${dt.day.toString().padLeft(2,'0')}/'
        '${dt.month.toString().padLeft(2,'0')}/'
        '${dt.year}  '
        '${dt.hour.toString().padLeft(2,'0')}:'
        '${dt.minute.toString().padLeft(2,'0')}';
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AppDrawer(),
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: const Text('Order Management',
          style: TextStyle(
            fontFamily: 'Poppins', fontSize: 18,
            fontWeight: FontWeight.w600, color: Colors.white)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load)
        ],
        bottom: TabBar(
          controller: _tab,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorColor: AppColors.accent,
          labelStyle: const TextStyle(
            fontFamily: 'Poppins', fontWeight: FontWeight.w600),
          tabs: [
            Tab(text: 'Aktif (${_orders.length})'),
            const Tab(text: 'Order Baru'),
            const Tab(text: 'Riwayat'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tab,
              children: [
                _buildActiveOrders(),
                MenuItemSelector(
                  branchId: _branchId ?? '',
                  tables: _tables,
                  onOrderCreated: () {
                    _load();
                    _tab.animateTo(0);
                  },
                ),
                _buildHistory(),
              ],
            ),
    );
  }

  // ── TAB: AKTIF ────────────────────────────────────────────────────────────
  Widget _buildActiveOrders() {
    if (_orders.isEmpty) {
      return const Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.receipt_long_outlined, size: 64, color: AppColors.textHint),
          SizedBox(height: 12),
          Text('Tidak ada order aktif',
            style: TextStyle(fontFamily: 'Poppins', color: AppColors.textSecondary)),
        ]),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _orders.length,
      itemBuilder: (_, i) {
        final o = _orders[i];
        final color = _statusColor(o.status);
        final nextS = _nextStatus(o.status);
        final isUpdating = _updatingOrderId == o.id;
        final isQr = _isQrOrder(o);

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: ExpansionTile(
            leading: CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.15),
              child: Text(o.orderNumber.split('-').last,
                style: TextStyle(
                  fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                  color: color, fontSize: 12))),
            title: Row(children: [
              Text(
                o.tableNumber != null ? 'Meja ${o.tableNumber}' : 'Takeaway',
                style: const TextStyle(
                  fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
              if (o.customerName != null) ...[
                const SizedBox(width: 6),
                Text('• ${o.customerName}', style: AppTextStyles.caption),
              ],
            ]),
            subtitle: Row(children: [
              // Status badge
              Container(
                margin: const EdgeInsets.only(top: 3),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: color.withValues(alpha: 0.4))),
                child: Text(o.status.label,
                  style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 10,
                    fontWeight: FontWeight.w600, color: color))),
              const SizedBox(width: 6),
              // ✅ Badge QR vs Staff
              Container(
                margin: const EdgeInsets.only(top: 3),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isQr
                      ? const Color(0xFF7C3AED).withValues(alpha: 0.08)
                      : AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isQr
                        ? const Color(0xFF7C3AED).withValues(alpha: 0.3)
                        : AppColors.primary.withValues(alpha: 0.3))),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(
                    isQr ? Icons.qr_code_scanner : Icons.person_outline,
                    size: 9,
                    color: isQr ? const Color(0xFF7C3AED) : AppColors.primary),
                  const SizedBox(width: 3),
                  Text(isQr ? 'QR' : 'Staff',
                    style: TextStyle(
                      fontFamily: 'Poppins', fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: isQr ? const Color(0xFF7C3AED) : AppColors.primary)),
                ])),
              const SizedBox(width: 6),
              Text('• ${o.items.length} item', style: AppTextStyles.caption),
            ]),
            trailing: Text('Rp ${o.totalAmount.toStringAsFixed(0)}',
              style: const TextStyle(
                fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                color: AppColors.accent)),
            children: [
              ...o.items.map((item) => OrderItemTile(item: item)),

              if (o.notes != null && o.notes!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.reserved.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.reserved.withValues(alpha: 0.3))),
                    child: Row(children: [
                      const Icon(Icons.notes, size: 14, color: AppColors.reserved),
                      const SizedBox(width: 6),
                      Expanded(child: Text(o.notes!,
                        style: const TextStyle(
                          fontFamily: 'Poppins', fontSize: 12,
                          color: AppColors.reserved))),
                    ]),
                  )),

              const Divider(height: 1),

              // ✅ FIX: nextS tidak null untuk 'paid', jadi tombol aksi selalu muncul
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: nextS != null
                    ? SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: isUpdating ? null : () => _updateOrderStatus(o),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _statusColor(nextS),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(vertical: 10)),
                          icon: isUpdating
                              ? const SizedBox(width: 16, height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                              : Icon(_nextStatusIcon(o.status), size: 18),
                          label: Text(
                            isUpdating ? 'Memperbarui...' : _nextStatusLabel(o.status),
                            style: const TextStyle(
                              fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
                        ))
                    // Sudah tersaji — selesai
                    : Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.available.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: AppColors.available.withValues(alpha: 0.3))),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_circle_outline,
                              size: 16, color: AppColors.available),
                            SizedBox(width: 8),
                            Text('Sudah Tersaji',
                              style: TextStyle(
                                fontFamily: 'Poppins', fontSize: 12,
                                color: AppColors.available,
                                fontWeight: FontWeight.w500)),
                          ]),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── TAB: RIWAYAT ──────────────────────────────────────────────────────────
  Widget _buildHistory() {
    return Column(children: [
      Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final f in [
              ('all', 'Semua'),
              ('paid', 'Lunas'),
              ('cancelled', 'Dibatalkan'),
            ])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(f.$2,
                    style: const TextStyle(fontFamily: 'Poppins', fontSize: 12)),
                  selected: _historyFilter == f.$1,
                  onSelected: (_) {
                    setState(() { _historyFilter = f.$1; _history = []; });
                    _loadHistory();
                  },
                  selectedColor: AppColors.primary.withValues(alpha: 0.15),
                  checkmarkColor: AppColors.primary)),
          ]),
        ),
      ),

      Expanded(
        child: _isHistoryLoading
            ? const Center(child: CircularProgressIndicator())
            : _history.isEmpty
                ? const Center(child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.receipt_long_outlined,
                        size: 64, color: AppColors.textHint),
                      SizedBox(height: 12),
                      Text('Tidak ada riwayat order',
                        style: TextStyle(
                          fontFamily: 'Poppins', color: AppColors.textSecondary)),
                    ]))
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _history.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final o = _history[i];
                      final status = o['status'] as String?;
                      final orderType = o['order_type'] as String?;
                      final total = (o['total_amount'] as num?)?.toDouble() ?? 0;
                      final statusColor = _historyStatusColor(status);
                      final rawItems = o['order_items'] as List? ?? [];
                      final isQr = orderType == 'qr_order';

                      return Card(
                        child: ExpansionTile(
                          leading: Container(
                            width: 44, height: 44,
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10)),
                            child: Icon(Icons.receipt_long,
                              color: statusColor, size: 22)),
                          title: Row(children: [
                            Text(o['order_number'] ?? '-',
                              style: const TextStyle(
                                fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: isQr
                                    ? const Color(0xFF7C3AED).withValues(alpha: 0.10)
                                    : AppColors.primary.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(4)),
                              child: Text(isQr ? 'QR' : 'Staff',
                                style: TextStyle(
                                  fontFamily: 'Poppins', fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: isQr
                                      ? const Color(0xFF7C3AED)
                                      : AppColors.primary))),
                          ]),
                          subtitle: Text(_formatDate(o['created_at'] as String?),
                            style: AppTextStyles.caption),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: statusColor.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: statusColor.withValues(alpha: 0.4))),
                                child: Text(_historyStatusLabel(status),
                                  style: TextStyle(
                                    fontFamily: 'Poppins', fontSize: 10,
                                    fontWeight: FontWeight.w600, color: statusColor))),
                              const SizedBox(height: 4),
                              Text('Rp ${total.toStringAsFixed(0)}',
                                style: const TextStyle(
                                  fontFamily: 'Poppins', fontSize: 12,
                                  fontWeight: FontWeight.w700)),
                            ]),
                          children: [
                            if (rawItems.isNotEmpty) ...[
                              const Divider(height: 1),
                              ...rawItems.map((item) {
                                final name = (item['menu_items'] as Map?)?['name']
                                    as String? ?? '-';
                                final qty = item['quantity'] as int? ?? 0;
                                final sub = (item['subtotal'] as num?)?.toDouble() ?? 0;
                                final notes = item['special_requests'] as String?;

                                return ListTile(
                                  dense: true,
                                  leading: Container(
                                    width: 28, height: 28,
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(6)),
                                    child: Center(child: Text('$qty',
                                      style: const TextStyle(
                                        fontFamily: 'Poppins',
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12, color: AppColors.primary)))),
                                  title: Text(name,
                                    style: const TextStyle(
                                      fontFamily: 'Poppins', fontSize: 13)),
                                  subtitle: notes != null && notes.isNotEmpty
                                      ? Text('📝 $notes',
                                          style: const TextStyle(
                                            fontFamily: 'Poppins', fontSize: 11,
                                            color: AppColors.reserved))
                                      : null,
                                  trailing: Text('Rp ${sub.toStringAsFixed(0)}',
                                    style: const TextStyle(
                                      fontFamily: 'Poppins', fontSize: 12,
                                      fontWeight: FontWeight.w600)));
                              }),
                            ],
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                              child: Row(children: [
                                const Spacer(),
                                const Text('Total: ',
                                  style: TextStyle(
                                    fontFamily: 'Poppins', fontSize: 13,
                                    color: AppColors.textSecondary)),
                                Text('Rp ${total.toStringAsFixed(0)}',
                                  style: const TextStyle(
                                    fontFamily: 'Poppins', fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.accent)),
                              ])),
                          ],
                        ),
                      );
                    }),
      ),
    ]);
  }
}