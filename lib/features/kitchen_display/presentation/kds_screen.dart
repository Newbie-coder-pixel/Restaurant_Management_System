import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/models/order_model.dart';
import '../../../core/theme/app_theme.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../shared/widgets/app_drawer.dart';

class KDSScreen extends ConsumerStatefulWidget {
  const KDSScreen({super.key});
  @override
  ConsumerState<KDSScreen> createState() => _KDSScreenState();
}

class _KDSScreenState extends ConsumerState<KDSScreen> {
  List<OrderModel> _orders = [];
  bool _isLoading = true;
  String? _branchId;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
  }

  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    final staff = ref.read(currentStaffProvider);
    if (staff != null) {
      _branchId = staff.branchId;
      _initialized = true;
      _init();
      _subscribeRealtime();
    } else {
      _initialized = true;
      ref.listenManual(currentStaffProvider, (_, next) {
        if (next != null && _branchId == null && mounted) {
          setState(() => _branchId = next.branchId);
          _init();
          _subscribeRealtime();
        }
      });
    }
  }

  Future<void> _init() async {
    await _load();
    _subscribeRealtime();
  }

  Future<void> _load() async {
    if (_branchId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    try {
      final res = await Supabase.instance.client
          .from('orders')
          .select('*, restaurant_tables(table_number), order_items(*, menu_items(name))')
          .eq('branch_id', _branchId!)
          .inFilter('status', ['new', 'preparing'])
          .order('created_at');
      if (mounted) {
        setState(() {
          _orders = (res as List).map((e) => OrderModel.fromJson(e)).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _subscribeRealtime() {
    _channel = Supabase.instance.client
        .channel('kds_realtime')
        .onPostgresChanges(
          event: PostgresChangeEvent.all, schema: 'public',
          table: 'orders', callback: (_) => _load())
        .onPostgresChanges(
          event: PostgresChangeEvent.all, schema: 'public',
          table: 'order_items', callback: (_) => _load())
        .subscribe();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  Future<void> _markPreparing(String orderId) async {
    await Supabase.instance.client.from('orders').update({
      'status': 'preparing',
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', orderId);
  }

  Future<void> _markReady(String orderId) async {
    await Supabase.instance.client.from('orders').update({
      'status': 'ready',
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', orderId);
    await Supabase.instance.client.from('order_items').update({
      'status': 'ready',
      'prepared_at': DateTime.now().toIso8601String(),
    }).eq('order_id', orderId);
  }

  int _elapsedMinutes(DateTime dt) => DateTime.now().difference(dt).inMinutes;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AppDrawer(),
      backgroundColor: const Color(0xFF0F0F1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        title: Row(children: [
          Container(
            width: 10, height: 10,
            decoration: const BoxDecoration(
              color: Color(0xFF4CAF50), shape: BoxShape.circle)),
          const SizedBox(width: 8),
          const Flexible(child: Text('Dapur (KDS)',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Poppins', fontSize: 18,
              fontWeight: FontWeight.w700, color: Colors.white))),
        ]),
        actions: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.accent, borderRadius: BorderRadius.circular(16)),
            child: Text('${_orders.length} Aktif',
              style: const TextStyle(
                fontFamily: 'Poppins', fontSize: 12,
                fontWeight: FontWeight.w700, color: Colors.white)),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _load),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
          : _orders.isEmpty
              ? const Center(child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle_outline, size: 80, color: Color(0xFF4CAF50)),
                    SizedBox(height: 16),
                    Text('Semua order selesai! 🎉',
                      style: TextStyle(
                        fontFamily: 'Poppins', fontSize: 20,
                        fontWeight: FontWeight.w600, color: Colors.white)),
                    SizedBox(height: 8),
                    Text('Menunggu order baru...',
                      style: TextStyle(fontFamily: 'Poppins', color: Colors.white38)),
                  ]))
              : GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 320,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: 0.75,
                  ),
                  itemCount: _orders.length,
                  itemBuilder: (_, i) => _buildKDSCard(_orders[i]),
                ),
    );
  }

  Widget _buildKDSCard(OrderModel order) {
    final elapsed = _elapsedMinutes(order.createdAt);
    final isUrgent = elapsed > 15;
    final isNew = order.status == OrderStatus.new_;
    final borderColor = isUrgent
        ? AppColors.accent
        : isNew ? AppColors.orderNew : AppColors.orderPreparing;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: isUrgent ? 2.5 : 1.5),
        boxShadow: [
          BoxShadow(color: borderColor.withValues(alpha: 0.2), blurRadius: 12),
        ],
      ),
      child: Column(children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: borderColor.withValues(alpha: 0.15),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
          ),
          child: Row(children: [
            Text('# ${order.orderNumber}',
              style: const TextStyle(
                fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                fontSize: 16, color: Colors.white)),
            const Spacer(),
            if (order.tableNumber != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8)),
                child: Text('Meja ${order.tableNumber}',
                  style: const TextStyle(
                    fontFamily: 'Poppins', fontSize: 11, color: Colors.white70)),
              ),
          ]),
        ),
        // Timer
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 8),
          color: isUrgent ? AppColors.accent.withValues(alpha: 0.2) : Colors.transparent,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.timer, size: 14,
              color: isUrgent ? AppColors.accent : Colors.white54),
            const SizedBox(width: 4),
            Text('$elapsed menit',
              style: TextStyle(
                fontFamily: 'Poppins', fontSize: 12,
                color: isUrgent ? AppColors.accent : Colors.white54,
                fontWeight: isUrgent ? FontWeight.w700 : FontWeight.normal)),
            if (isUrgent) ...[
              const SizedBox(width: 4),
              const Text('⚠️ TERLAMBAT',
                style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 11,
                  color: AppColors.accent, fontWeight: FontWeight.w700)),
            ],
          ]),
        ),
        // Items
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: order.items.map((item) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Row(children: [
                Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(
                    color: borderColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6)),
                  child: Center(child: Text('${item.quantity}',
                    style: TextStyle(
                      fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                      color: borderColor, fontSize: 13))),
                ),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(item.menuItemName,
                    style: const TextStyle(
                      fontFamily: 'Poppins', fontWeight: FontWeight.w600,
                      color: Colors.white, fontSize: 13)),
                  if (item.specialRequests != null && item.specialRequests!.isNotEmpty)
                    Text('⚡ ${item.specialRequests}',
                      style: const TextStyle(
                        fontFamily: 'Poppins', fontSize: 11, color: AppColors.reserved)),
                ])),
              ]),
            )).toList(),
          ),
        ),
        // Action buttons
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            if (isNew) Expanded(child: ElevatedButton(
              onPressed: () => _markPreparing(order.id),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.orderPreparing, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              child: const Text('Mulai Masak',
                style: TextStyle(
                  fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 12)),
            )),
            if (!isNew) Expanded(child: ElevatedButton(
              onPressed: () => _markReady(order.id),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.orderReady, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              child: const Text('✓ Siap Saji',
                style: TextStyle(
                  fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 13)),
            )),
          ]),
        ),
      ]),
    );
  }
}