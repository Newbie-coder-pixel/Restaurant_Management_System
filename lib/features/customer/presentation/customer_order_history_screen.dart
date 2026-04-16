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

    // Capture context-dependent objects BEFORE any async gaps
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);

    if (validItems.isEmpty) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Tidak ada item yang bisa dipesan ulang.'),
        backgroundColor: Colors.orange));
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFE94560).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.replay_outlined, color: Color(0xFFE94560), size: 24),
            ),
            const SizedBox(width: 12),
            const Text('Pesan Ulang?',
                style: TextStyle(
                    fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 18)),
          ],
        ),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('${validItems.length} item dari order ini akan ditambahkan ke cart.',
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 13, height: 1.4)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(children: [
              ...validItems.take(3).map((i) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  Container(
                    width: 6, height: 6,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE94560).withValues(alpha: 0.5),
                      shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${i['quantity']}x ${(i['menu_items'] as Map)['name']}',
                    style: const TextStyle(
                        fontFamily: 'Poppins', fontSize: 12, color: Color(0xFF374151)),
                  ),
                ]))),
              if (validItems.length > 3)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('+ ${validItems.length - 3} item lainnya',
                      style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 11,
                          color: Colors.grey)),
                ),
            ]),
          )
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            child: const Text('Batal',
                style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 14, color: Colors.grey))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE94560),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12))),
            child: const Text('Pesan Lagi',
                style: TextStyle(
                    fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 14))),
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

    if (!mounted) return;
    messenger.showSnackBar(SnackBar(
      content: const Row(children: [
        Icon(Icons.check_circle, color: Colors.white, size: 20),
        SizedBox(width: 12),
        Expanded(child: Text('Item ditambahkan ke cart!')),
      ]),
      backgroundColor: const Color(0xFF1D9E75),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
    router.go('/customer/checkout');
  }

  @override
  Widget build(BuildContext context) {
    final historyAsync = ref.watch(_orderHistoryProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A2E),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () => context.go('/customer')),
        title: const Text('Riwayat Pesanan',
            style: TextStyle(
                fontFamily: 'Poppins', 
                fontWeight: FontWeight.w700,
                fontSize: 20)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(_orderHistoryProvider)),
        ],
      ),
      body: historyAsync.when(
        loading: () => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: Color(0xFFE94560)),
              const SizedBox(height: 16),
              Text('Memuat riwayat...',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      color: Colors.grey.shade600)),
            ],
          ),
        ),
        error: (e, _) => Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
            ),
            const SizedBox(height: 20),
            Text('Gagal memuat riwayat',
                style: TextStyle(
                    fontFamily: 'Poppins', 
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade800),
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text('$e',
                style: TextStyle(
                    fontFamily: 'Poppins', 
                    fontSize: 13, 
                    color: Colors.grey.shade600),
                textAlign: TextAlign.center),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => ref.invalidate(_orderHistoryProvider),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Coba Lagi'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE94560),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              )),
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
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                            style: TextStyle(
                                fontFamily: 'Poppins', 
                                fontSize: 13,
                                fontWeight: _filter == f.$1 ? FontWeight.w600 : FontWeight.normal)),
                        selected: _filter == f.$1,
                        onSelected: (_) =>
                            setState(() => _filter = f.$1),
                        backgroundColor: Colors.grey.shade50,
                        selectedColor:
                            const Color(0xFFE94560).withValues(alpha: 0.1),
                        checkmarkColor: const Color(0xFFE94560),
                        side: BorderSide(
                          color: _filter == f.$1 ? const Color(0xFFE94560) : Colors.grey.shade300,
                          width: 1,
                        ))),
                ])),
            ),

            // Count
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 12),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE94560).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    filtered.isEmpty
                        ? 'Tidak ada pesanan'
                        : '${filtered.length} pesanan',
                    style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFE94560)),
                  ),
                ),
              ])),
              
            const Divider(height: 1, thickness: 1, color: Color(0xFFE5E7EB)),

            // List
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.receipt_long_outlined,
                              size: 64, color: Colors.grey.shade400),
                          const SizedBox(height: 16),
                          Text(
                            'Tidak ada pesanan dengan status "$_filter"',
                            style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 14,
                                color: Colors.grey.shade600),
                            textAlign: TextAlign.center),
                        ]))
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 12),
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
          width: 100, height: 100,
          decoration: BoxDecoration(
            color: const Color(0xFFE94560).withValues(alpha: 0.08),
            shape: BoxShape.circle),
          child: const Icon(Icons.receipt_long_outlined,
              color: Color(0xFFE94560), size: 48)),
        const SizedBox(height: 24),
        const Text('Belum Ada Pesanan',
            style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A1A2E))),
        const SizedBox(height: 12),
        const Text(
          'Mulai pesan makanan favoritmu sekarang!',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 14,
              color: Colors.grey)),
        const SizedBox(height: 32),
        ElevatedButton.icon(
          onPressed: () => context.go('/customer'),
          icon: const Icon(Icons.restaurant_menu_outlined, size: 20),
          label: const Text('Lihat Menu',
              style: TextStyle(
                  fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 15)),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFE94560),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(
                horizontal: 32, vertical: 14),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)))),
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
    'new':       Color(0xFF3B82F6),
    'preparing': Color(0xFFF59E0B),
    'ready':     Color(0xFF10B981),
    'served':    Color(0xFF6366F1),
    'paid':      Color(0xFF10B981),
    'cancelled': Color(0xFFEF4444),
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
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 12, offset: const Offset(0, 4))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.08),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20))),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(statusIcon, color: statusColor, size: 16),
            ),
            const SizedBox(width: 10),
            Text(statusLabel,
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: statusColor)),
            const Spacer(),
            // Live badge untuk order aktif
            if (_isActive)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  AnimatedContainer(
                    duration: const Duration(seconds: 1),
                    width: 6, height: 6,
                    decoration: BoxDecoration(
                        color: statusColor, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Text('Aktif',
                      style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: statusColor)),
                ])),
          ])),

        // Body
        Padding(
          padding: const EdgeInsets.all(16),
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
                      fontSize: 15,
                      color: Color(0xFF1F2937))),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFE94560).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('Rp ${_fmt(total)}',
                    style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: Color(0xFFE94560))),
              ),
            ]),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.shopping_bag_outlined, size: 12, color: Colors.grey.shade500),
                const SizedBox(width: 4),
                Text(
                  '$itemCount item',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11,
                      color: Colors.grey.shade600)),
                const SizedBox(width: 8),
                Icon(Icons.access_time, size: 12, color: Colors.grey.shade500),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    _fmtDate(order['created_at'] as String?),
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 11,
                        color: Colors.grey.shade600)),
                ),
              ],
            ),

            // Preview items
            if (rawItems.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  rawItems.take(2).map((i) {
                    final m = (i as Map);
                    return '${m['quantity']}x ${(m['menu_items'] as Map?)?['name'] ?? '-'}';
                  }).join(' • ') + (rawItems.length > 2 ? ' • +${rawItems.length - 2}' : ''),
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      color: Colors.grey.shade700),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
              ),
            ],

            const SizedBox(height: 16),
            // Action buttons
            Row(children: [
              // Track — untuk order aktif
              if (_isActive)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onTrack,
                    icon: const Icon(Icons.location_on_outlined,
                        size: 16),
                    label: const Text('Lacak',
                        style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      side: const BorderSide(color: Color(0xFF6366F1), width: 1.5),
                      foregroundColor: const Color(0xFF6366F1),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12))),
                  )),
              if (_isActive) const SizedBox(width: 12),
              // Reorder — untuk semua status kecuali cancelled
              if (!(_isPaid == false && status == 'cancelled') ||
                  _isPaid)
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onReorder,
                    icon: const Icon(Icons.replay_outlined, size: 16),
                    label: const Text('Pesan Lagi',
                        style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      backgroundColor: const Color(0xFFE94560),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12))),
                  )),
            ]),
          ])),
      ]));
  }
}