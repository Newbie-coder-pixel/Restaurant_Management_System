import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/cart_provider.dart';

// ── Provider riwayat order milik user ─────────────────────────────
final _orderHistoryProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) return [];

  final res = await Supabase.instance.client
      .from('orders')
      .select('*, order_items(*, menu_items(name))')
      .eq('customer_user_id', user.id)
      .order('created_at', ascending: false)
      .limit(50);

  return (res as List).cast<Map<String, dynamic>>();
});

// ── Screen ─────────────────────────────────────────────────────────
class CustomerOrderHistoryScreen extends ConsumerStatefulWidget {
  const CustomerOrderHistoryScreen({super.key});

  @override
  ConsumerState<CustomerOrderHistoryScreen> createState() =>
      _CustomerOrderHistoryScreenState();
}

class _CustomerOrderHistoryScreenState
    extends ConsumerState<CustomerOrderHistoryScreen> {
  String _filter = 'all';

  // ── Reorder ────────────────────────────────────────────────────
  Future<void> _reorder(
      BuildContext context, Map<String, dynamic> order) async {
    final branchId = order['branch_id'] as String?;
    if (branchId == null) return;

    final rawItems = order['order_items'] as List? ?? [];
    final validItems = rawItems
        .cast<Map<String, dynamic>>()
        .where((i) =>
            i['menu_item_id'] != null && i['menu_items'] != null)
        .toList();

    if (validItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Tidak ada item yang bisa dipesan ulang.'),
        backgroundColor: Colors.orange));
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Pesan Ulang?',
            style: TextStyle(
                fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('${validItems.length} item dari order ini akan ditambahkan ke cart.',
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 13)),
          const SizedBox(height: 8),
          ...validItems.take(3).map((i) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(children: [
              const Icon(Icons.circle, size: 6, color: Colors.grey),
              const SizedBox(width: 8),
              Text(
                '${i['quantity']}x ${(i['menu_items'] as Map)['name']}',
                style: const TextStyle(
                    fontFamily: 'Poppins', fontSize: 12, color: Colors.grey)),
            ]))),
          if (validItems.length > 3)
            Text('... dan ${validItems.length - 3} item lainnya',
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    color: Colors.grey)),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal',
                style: TextStyle(
                    fontFamily: 'Poppins', color: Colors.grey))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE94560),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10))),
            child: const Text('Pesan Lagi',
                style: TextStyle(
                    fontFamily: 'Poppins', fontWeight: FontWeight.w600))),
        ]));

    if (confirm != true || !mounted) return;

    ref.read(cartProvider.notifier).setBranch(branchId, '');
    for (final item in validItems) {
      ref.read(cartProvider.notifier).addItem(CartItem(
        menuItemId: item['menu_item_id'] as String,
        name: (item['menu_items'] as Map)['name'] as String,
        price: (item['unit_price'] as num).toDouble(),
        quantity: item['quantity'] as int? ?? 1,
      ));
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('✅ Item ditambahkan ke cart!'),
        backgroundColor: Color(0xFF1D9E75)));
      context.go('/customer/checkout');
    }
  }

  @override
  Widget build(BuildContext context) {
    final historyAsync = ref.watch(_orderHistoryProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFFAF8F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () => context.go('/customer')),
        title: const Text('Riwayat Pesanan',
            style: TextStyle(
                fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(_orderHistoryProvider)),
        ],
      ),
      body: historyAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            Text('Gagal memuat: $e',
                style: const TextStyle(
                    fontFamily: 'Poppins', color: Colors.grey),
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => ref.invalidate(_orderHistoryProvider),
              child: const Text('Coba Lagi')),
          ])),
        data: (orders) {
          if (orders.isEmpty) return _emptyState(context);

          // Filter
          final filtered = _filter == 'all'
              ? orders
              : orders
                  .where((o) => o['status'] == _filter)
                  .toList();

          return Column(children: [
            // Filter chips
            Container(
              color: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (final f in [
                    ('all', 'Semua'),
                    ('paid', 'Lunas'),
                    ('new', 'Baru'),
                    ('preparing', 'Dimasak'),
                    ('served', 'Tersaji'),
                    ('cancelled', 'Dibatalkan'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(f.$2,
                            style: const TextStyle(
                                fontFamily: 'Poppins', fontSize: 12)),
                        selected: _filter == f.$1,
                        onSelected: (_) =>
                            setState(() => _filter = f.$1),
                        selectedColor:
                            const Color(0xFFE94560).withValues(alpha: 0.15),
                        checkmarkColor: const Color(0xFFE94560))),
                ])),
            ),

            // Count
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 8),
              child: Row(children: [
                Text(
                  filtered.isEmpty
                      ? 'Tidak ada pesanan'
                      : '${filtered.length} pesanan',
                  style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      color: Colors.grey)),
              ])),

            // List
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.receipt_long_outlined,
                              size: 48, color: Colors.grey),
                          const SizedBox(height: 12),
                          Text(
                            'Tidak ada pesanan dengan status "$_filter"',
                            style: const TextStyle(
                                fontFamily: 'Poppins',
                                color: Colors.grey),
                            textAlign: TextAlign.center),
                        ]))
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 10),
                      itemBuilder: (_, i) => _OrderHistoryCard(
                        order: filtered[i],
                        onReorder: () =>
                            _reorder(context, filtered[i]),
                        onTrack: () => context.go(
                            '/customer/track/${filtered[i]['order_number']}'),
                      )),
            ),
          ]);
        },
      ),
    );
  }

  Widget _emptyState(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 80, height: 80,
          decoration: BoxDecoration(
            color: const Color(0xFFE94560).withValues(alpha: 0.08),
            shape: BoxShape.circle),
          child: const Icon(Icons.receipt_long_outlined,
              color: Color(0xFFE94560), size: 38)),
        const SizedBox(height: 20),
        const Text('Belum Ada Pesanan',
            style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A1A2E))),
        const SizedBox(height: 8),
        const Text(
          'Mulai pesan makanan favoritmu sekarang!',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              color: Colors.grey)),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: () => context.go('/customer'),
          icon: const Icon(Icons.restaurant_menu_outlined, size: 18),
          label: const Text('Lihat Menu',
              style: TextStyle(
                  fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFE94560),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(
                horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)))),
      ])));
}

// ── Order History Card ─────────────────────────────────────────────
class _OrderHistoryCard extends StatelessWidget {
  final Map<String, dynamic> order;
  final VoidCallback onReorder;
  final VoidCallback onTrack;

  const _OrderHistoryCard({
    required this.order,
    required this.onReorder,
    required this.onTrack,
  });

  static const _statusColors = {
    'new':       Color(0xFF6B7280),
    'preparing': Color(0xFFD97706),
    'ready':     Color(0xFF1D9E75),
    'served':    Color(0xFF0F3460),
    'paid':      Color(0xFF1D9E75),
    'cancelled': Color(0xFFE94560),
  };
  static const _statusLabels = {
    'new':       'Baru',
    'preparing': 'Dimasak',
    'ready':     'Siap',
    'served':    'Tersaji',
    'paid':      'Lunas',
    'cancelled': 'Dibatalkan',
  };
  static const _statusIcons = {
    'new':       Icons.fiber_new_outlined,
    'preparing': Icons.soup_kitchen_outlined,
    'ready':     Icons.check_circle_outline,
    'served':    Icons.room_service_outlined,
    'paid':      Icons.payment_outlined,
    'cancelled': Icons.cancel_outlined,
  };

  bool get _isActive {
    final s = order['status'] as String? ?? '';
    return s == 'new' || s == 'preparing' || s == 'ready' || s == 'served';
  }

  bool get _isPaid => order['status'] == 'paid';

  String _fmtDate(String? iso) {
    if (iso == null) return '-';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '-';
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
      'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'
    ];
    return '${dt.day} ${months[dt.month]} ${dt.year}, '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }

  String _fmt(double v) {
    final s = v.toStringAsFixed(0);
    final buffer = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buffer.write('.');
      buffer.write(s[i]);
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    final status      = order['status'] as String? ?? 'new';
    final statusColor = _statusColors[status] ?? Colors.grey;
    final statusLabel = _statusLabels[status] ?? status;
    final statusIcon  = _statusIcons[status] ?? Icons.receipt_outlined;
    final total       = (order['total_amount'] as num?)?.toDouble() ?? 0;
    final rawItems    = order['order_items'] as List? ?? [];
    final itemCount   = rawItems.fold<int>(
        0, (s, i) => s + ((i as Map)['quantity'] as int? ?? 0));

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(
          color: Colors.black.withValues(alpha: 0.05),
          blurRadius: 8, offset: const Offset(0, 2))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.06),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(16))),
          child: Row(children: [
            Icon(statusIcon, color: statusColor, size: 16),
            const SizedBox(width: 6),
            Text(statusLabel,
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: statusColor)),
            const Spacer(),
            // Live badge untuk order aktif
            if (_isActive)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 6, height: 6,
                    decoration: BoxDecoration(
                        color: statusColor, shape: BoxShape.circle)),
                  const SizedBox(width: 4),
                  Text('Live',
                      style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: statusColor)),
                ])),
          ])),

        // Body
        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Row(children: [
              Expanded(
                child: Text(
                  order['order_number'] as String? ?? '-',
                  style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: Color(0xFF1A1A2E))),
              ),
              Text('Rp ${_fmt(total)}',
                  style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: Color(0xFFE94560))),
            ]),
            const SizedBox(height: 4),
            Text(
              '$itemCount item • ${_fmtDate(order['created_at'] as String?)}',
              style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  color: Colors.grey)),

            // Preview items
            if (rawItems.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                rawItems.take(2).map((i) {
                  final m = (i as Map);
                  return '${m['quantity']}x ${(m['menu_items'] as Map?)?['name'] ?? '-'}';
                }).join(', ') + (rawItems.length > 2 ? '...' : ''),
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    color: Color(0xFF374151)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            ],

            const SizedBox(height: 12),
            // Action buttons
            Row(children: [
              // Track — untuk order aktif
              if (_isActive)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onTrack,
                    icon: const Icon(Icons.gps_fixed_outlined,
                        size: 14, color: Color(0xFF0F3460)),
                    label: const Text('Lacak',
                        style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF0F3460))),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      side: const BorderSide(color: Color(0xFF0F3460)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8))),
                  )),
              if (_isActive) const SizedBox(width: 10),
              // Reorder — untuk semua status kecuali cancelled
              if (!(_isPaid == false && status == 'cancelled') ||
                  _isPaid)
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onReorder,
                    icon: const Icon(Icons.replay_outlined, size: 14),
                    label: const Text('Pesan Lagi',
                        style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      backgroundColor: const Color(0xFFE94560),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8))),
                  )),
            ]),
          ])),
      ]));
  }
}