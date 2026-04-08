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
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    final staff = ref.read(currentStaffProvider);
    if (staff != null) {
      _branchId = staff.branchId;
      _initialized = true;
      _load();
      _subscribeRealtime();
    } else {
      _initialized = true;
      ref.listenManual(currentStaffProvider, (_, next) {
        if (next != null && _branchId == null && mounted) {
          setState(() => _branchId = next.branchId);
          _load();
          _subscribeRealtime();
        }
      });
    }
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
          // ✅ FIX: tambah 'paid' — order QR masuk KDS setelah kasir konfirmasi
          // 'new' = order internal dari waiter/kasir
          // 'paid' = order QR yang sudah dibayar, siap dimasak
          // 'preparing' = sedang dimasak
          .inFilter('status', ['new', 'paid', 'preparing'])
          .order('created_at');
      if (mounted) {
        setState(() {
          _orders = (res as List).map((e) => OrderModel.fromJson(e)).toList();
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
    _channel = Supabase.instance.client
        .channel('kds_realtime_${DateTime.now().millisecondsSinceEpoch}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          callback: (_) => _load(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'order_items',
          callback: (_) => _load(),
        )
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

  // ── Helpers: tentukan apakah order ini "baru" (belum mulai masak) ──────────
  // 'new' = order internal waiter, 'paid' = order QR sudah bayar — keduanya belum masak
  bool _isNewOrder(OrderModel order) =>
      order.status == OrderStatus.new_ || order.status == OrderStatus.paid;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      drawer: const AppDrawer(),
      backgroundColor: colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Row(children: [
          Container(
            width: 10, height: 10,
            decoration: BoxDecoration(
              color: _orders.isNotEmpty ? AppColors.available : Colors.grey,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Dapur (KDS)',
            style: theme.textTheme.titleLarge?.copyWith(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurface,
            ),
          ),
        ]),
        actions: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: _orders.isEmpty
                  ? colorScheme.surfaceContainerHighest
                  : AppColors.accent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              '${_orders.length} Aktif',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: _orders.isEmpty ? colorScheme.outline : Colors.white,
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.refresh, color: colorScheme.onSurface),
            onPressed: _load,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _orders.isEmpty
              ? _buildEmptyState(colorScheme)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 340,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      childAspectRatio: 0.72,
                    ),
                    itemCount: _orders.length,
                    itemBuilder: (_, i) => _buildKDSCard(_orders[i], colorScheme),
                  ),
                ),
    );
  }

  Widget _buildEmptyState(ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100, height: 100,
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.check_circle_outline,
                size: 60, color: Colors.green.shade400),
          ),
          const SizedBox(height: 20),
          Text(
            'Semua order selesai! 🎉',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Menunggu order baru...',
            style: TextStyle(
              fontFamily: 'Poppins',
              color: colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKDSCard(OrderModel order, ColorScheme colorScheme) {
    final elapsed = _elapsedMinutes(order.createdAt);
    final isUrgent = elapsed > 15;
    final isNew = _isNewOrder(order);

    // Warna berdasarkan urgensi & status
    final Color statusColor = isUrgent
        ? AppColors.accent
        : isNew
            ? AppColors.orderNew
            : AppColors.orderPreparing;

    // Badge label untuk tipe order
    final bool isQrOrder = order.status == OrderStatus.paid;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isUrgent
              ? AppColors.accent.withValues(alpha: 0.8)
              : colorScheme.outlineVariant,
          width: isUrgent ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isUrgent
                ? AppColors.accent.withValues(alpha: 0.12)
                : Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(children: [
        // ── Header ──────────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.10),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
          ),
          child: Row(children: [
            // Status dot
            Container(
              width: 8, height: 8,
              decoration: BoxDecoration(
                color: statusColor, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '# ${order.orderNumber}',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: colorScheme.onSurface,
                ),
              ),
            ),
            // Meja badge
            if (order.tableNumber != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Meja ${order.tableNumber}',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
          ]),
        ),

        // ── Sub-header: tipe order + timer ──────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: isUrgent
                ? AppColors.accent.withValues(alpha: 0.08)
                : colorScheme.surfaceContainerLowest,
            border: Border(
              bottom: BorderSide(color: colorScheme.outlineVariant, width: 0.5),
            ),
          ),
          child: Row(children: [
            // QR badge
            if (isQrOrder)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'QR Order',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.primary,
                  ),
                ),
              ),
            Icon(
              Icons.timer_outlined,
              size: 13,
              color: isUrgent ? AppColors.accent : colorScheme.outline,
            ),
            const SizedBox(width: 4),
            Text(
              '$elapsed mnt',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12,
                color: isUrgent ? AppColors.accent : colorScheme.outline,
                fontWeight: isUrgent ? FontWeight.w700 : FontWeight.normal,
              ),
            ),
            if (isUrgent) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  '⚠ TERLAMBAT',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 10,
                    color: AppColors.accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
            const Spacer(),
            // Status pill
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: statusColor.withValues(alpha: 0.3)),
              ),
              child: Text(
                isNew ? 'Baru' : 'Dimasak',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: statusColor,
                ),
              ),
            ),
          ]),
        ),

        // ── Items list ───────────────────────────────────────────────────────
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            children: order.items.map((item) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: colorScheme.outlineVariant, width: 0.8),
              ),
              child: Row(children: [
                // Quantity badge
                Container(
                  width: 30, height: 30,
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(child: Text(
                    '${item.quantity}',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w800,
                      color: statusColor,
                      fontSize: 14,
                    ),
                  )),
                ),
                const SizedBox(width: 10),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.menuItemName,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                        fontSize: 13,
                      ),
                    ),
                    if (item.specialRequests != null &&
                        item.specialRequests!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          '📝 ${item.specialRequests}',
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 11,
                            color: AppColors.reserved,
                          ),
                        ),
                      ),
                  ],
                )),
              ]),
            )).toList(),
          ),
        ),

        // ── Action button ────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
          child: SizedBox(
            width: double.infinity,
            height: 42,
            child: isNew
                ? ElevatedButton.icon(
                    onPressed: () => _markPreparing(order.id),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.orderPreparing,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.local_fire_department_outlined, size: 16),
                    label: const Text('Mulai Masak',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      )),
                  )
                : ElevatedButton.icon(
                    onPressed: () => _markReady(order.id),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade600,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.check_circle_outline, size: 16),
                    label: const Text('✓ Siap Saji',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      )),
                  ),
          ),
        ),
      ]),
    );
  }
}