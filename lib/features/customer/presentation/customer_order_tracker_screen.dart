import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/cart_provider.dart';

// ── Order Success Screen ───────────────────────────────────────────
class CustomerOrderSuccessScreen extends StatelessWidget {
  final String orderNumber;
  const CustomerOrderSuccessScreen({super.key, required this.orderNumber});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFFAF8F5),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 100, height: 100,
            decoration: BoxDecoration(
              color: const Color(0xFF1D9E75).withValues(alpha: 0.1),
              shape: BoxShape.circle),
            child: const Icon(Icons.check_circle_outline_rounded,
                color: Color(0xFF1D9E75), size: 56)),
          const SizedBox(height: 24),
          const Text('Pesanan Berhasil! 🎉',
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1A1A2E)),
              textAlign: TextAlign.center),
          const SizedBox(height: 12),
          const Text(
            'Pesananmu sudah masuk ke dapur.\nSilakan tunjukkan kode ini ke kasir.',
            style: TextStyle(
                fontFamily: 'Poppins', color: Colors.grey, height: 1.6),
            textAlign: TextAlign.center),
          const SizedBox(height: 28),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(16)),
            child: Column(children: [
              const Text('No. Pesanan',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      color: Colors.white54,
                      fontSize: 12)),
              const SizedBox(height: 4),
              Text(orderNumber,
                  style: const TextStyle(
                      fontFamily: 'Poppins',
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2)),
            ])),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: () => context.go('/customer/track/$orderNumber'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE94560),
              foregroundColor: Colors.white,
              minimumSize: const Size(200, 48),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12))),
            child: const Text('Cek Status Pesanan',
                style: TextStyle(
                    fontFamily: 'Poppins', fontWeight: FontWeight.w700))),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => context.go('/customer'),
            child: const Text('Kembali ke Beranda',
                style: TextStyle(fontFamily: 'Poppins', color: Colors.grey))),
        ]))));
}

// ── Booking Success Screen ─────────────────────────────────────────
class CustomerBookingSuccessScreen extends StatelessWidget {
  const CustomerBookingSuccessScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFFAF8F5),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 100, height: 100,
            decoration: BoxDecoration(
              color: const Color(0xFF0F3460).withValues(alpha: 0.1),
              shape: BoxShape.circle),
            child: const Icon(Icons.calendar_today_rounded,
                color: Color(0xFF0F3460), size: 48)),
          const SizedBox(height: 24),
          const Text('Reservasi Dikonfirmasi! 📅',
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1A1A2E)),
              textAlign: TextAlign.center),
          const SizedBox(height: 12),
          const Text(
            'Reservasi kamu sudah tercatat.\nKami menantikan kedatanganmu!',
            style: TextStyle(
                fontFamily: 'Poppins', color: Colors.grey, height: 1.6),
            textAlign: TextAlign.center),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: () => context.go('/customer'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F3460),
              foregroundColor: Colors.white,
              minimumSize: const Size(200, 48),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12))),
            child: const Text('Kembali ke Beranda',
                style: TextStyle(
                    fontFamily: 'Poppins', fontWeight: FontWeight.w700))),
        ]))));
}

// ── Order Tracker Screen ───────────────────────────────────────────
class CustomerOrderTrackerScreen extends ConsumerStatefulWidget {
  final String? initialOrderNumber;
  const CustomerOrderTrackerScreen({super.key, this.initialOrderNumber});

  @override
  ConsumerState<CustomerOrderTrackerScreen> createState() =>
      _CustomerOrderTrackerScreenState();
}

class _CustomerOrderTrackerScreenState
    extends ConsumerState<CustomerOrderTrackerScreen> {
  final _ctrl = TextEditingController();
  Map<String, dynamic>? _order;
  List<Map<String, dynamic>> _items = [];
  bool _loading = false;
  String? _error;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    if (widget.initialOrderNumber != null) {
      _ctrl.text = widget.initialOrderNumber!;
      WidgetsBinding.instance.addPostFrameCallback((_) => _search());
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _channel?.unsubscribe();
    super.dispose();
  }

  void _subscribeRealtime(String orderId) {
    _channel?.unsubscribe();
    _channel = Supabase.instance.client
        .channel('tracker_$orderId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'orders',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: orderId),
          callback: (payload) {
            if (mounted && payload.newRecord.isNotEmpty) {
              setState(() => _order = {..._order!, ...payload.newRecord});
            }
          })
        .subscribe();
  }

  Future<void> _search() async {
    // FIX: trim + uppercase untuk konsistensi
    final code = _ctrl.text.trim().toUpperCase();
    if (code.isEmpty) return;

    setState(() { _loading = true; _error = null; _order = null; _items = []; });
    _channel?.unsubscribe();

    try {
      final user = Supabase.instance.client.auth.currentUser;

      // FIX: exact match dulu, kalau tidak ketemu baru partial
      // Dan filter by customer_user_id kalau user login
      var query = Supabase.instance.client
          .from('orders')
          .select()
          .eq('order_number', code);

      // Kalau user login, pastikan order milik dia
      if (user != null) {
        // Coba exact match milik user ini dulu
        final ownOrders = await Supabase.instance.client
            .from('orders')
            .select()
            .eq('order_number', code)
            .eq('customer_user_id', user.id)
            .limit(1);

        if ((ownOrders as List).isNotEmpty) {
          // Ketemu — order milik user ini
          await _processOrderResult(ownOrders.first);
          return;
        }

        // Coba tanpa filter user (mungkin order sebelum login)
        final anyOrder = await query.limit(1);
        if ((anyOrder as List).isNotEmpty) {
          await _processOrderResult(anyOrder.first);
          return;
        }
      } else {
        // Tidak login — cari by exact order number
        final res = await query.limit(1);
        if ((res as List).isNotEmpty) {
          await _processOrderResult(res.first);
          return;
        }
      }

      // Tidak ketemu sama sekali
      if (mounted) {
        setState(() {
          _error = 'Pesanan "$code" tidak ditemukan.\nPastikan nomor pesanan sudah benar.';
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() { _error = 'Terjadi kesalahan. Coba lagi.'; _loading = false; });
      }
    }
  }

  Future<void> _processOrderResult(Map<String, dynamic> order) async {
    try {
      final items = await Supabase.instance.client
          .from('order_items')
          .select('*, menu_items(name)')
          .eq('order_id', order['id'])
          .order('created_at');

      if (mounted) {
        setState(() {
          _order = order;
          _items = (items as List).cast();
          _loading = false;
        });
        _subscribeRealtime(order['id'] as String);
      }
    } catch (e) {
      if (mounted) {
        setState(() { _error = 'Gagal memuat detail pesanan.'; _loading = false; });
      }
    }
  }

  // ── Reorder: tambahkan semua item ke cart ulang ────────────────
  Future<void> _reorder() async {
    if (_order == null || _items.isEmpty) return;

    final branchId = _order!['branch_id'] as String?;
    if (branchId == null) return;

    // Cek apakah ada item yang menu_item_id-nya valid
    final validItems = _items
        .where((i) => i['menu_item_id'] != null && i['menu_items'] != null)
        .toList();

    if (validItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Tidak ada item yang bisa dipesan ulang.'),
        backgroundColor: Colors.orange));
      return;
    }

    // Konfirmasi
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Pesan Ulang?',
            style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        content: Text(
            'Semua item dari order #${_order!['order_number']} akan ditambahkan ke cart.',
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal',
                style: TextStyle(fontFamily: 'Poppins', color: Colors.grey))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE94560),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10))),
            child: const Text('Ya, Pesan Lagi',
                style: TextStyle(
                    fontFamily: 'Poppins', fontWeight: FontWeight.w600))),
        ]));

    if (confirm != true || !mounted) return;

    // Set branch & tambah ke cart
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
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFFAF8F5),
    appBar: AppBar(
      backgroundColor: const Color(0xFF1A1A2E),
      foregroundColor: Colors.white,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new, size: 18),
        onPressed: () => context.go('/customer')),
      title: const Text('Cek Pesanan',
          style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
      actions: [
        if (_order != null)
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 8, height: 8,
                decoration: const BoxDecoration(
                  color: Color(0xFF1D9E75), shape: BoxShape.circle)),
              const SizedBox(width: 4),
              const Text('Live',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11,
                      color: Color(0xFF1D9E75))),
            ])),
      ]),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      // Search box
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Masukkan Nomor Pesanan',
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                  fontSize: 14)),
          const SizedBox(height: 4),
          const Text('Nomor pesanan ada di struk atau layar konfirmasi.',
              style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: TextField(
              controller: _ctrl,
              textCapitalization: TextCapitalization.characters,
              onSubmitted: (_) => _search(),
              style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5),
              decoration: InputDecoration(
                hintText: 'Contoh: WEB-20260327-1234',
                hintStyle: const TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.normal,
                    color: Colors.grey,
                    letterSpacing: 0),
                filled: true,
                fillColor: const Color(0xFFF3F4F6),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none)))),
            const SizedBox(width: 10),
            ElevatedButton(
              onPressed: _loading ? null : _search,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE94560),
                foregroundColor: Colors.white,
                minimumSize: const Size(52, 52),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10))),
              child: _loading
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.search_rounded)),
          ]),
        ])),

      // Error
      if (_error != null) ...[
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.red.withValues(alpha: 0.2))),
          child: Row(children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 18),
            const SizedBox(width: 10),
            Expanded(child: Text(_error!,
                style: const TextStyle(
                    fontFamily: 'Poppins', fontSize: 13, color: Colors.red))),
          ])),
      ],

      // Order card
      if (_order != null) ...[
        const SizedBox(height: 16),
        _OrderStatusCard(order: _order!, items: _items),
        // Tombol reorder kalau sudah paid
        if (_order!['status'] == 'paid') ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _reorder,
              icon: const Icon(Icons.replay_outlined,
                  size: 18, color: Color(0xFFE94560)),
              label: const Text('Pesan Lagi',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFE94560))),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: const BorderSide(color: Color(0xFFE94560)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12))),
            )),
        ],
      ],

      // Empty state
      if (_order == null && _error == null && !_loading) ...[
        const SizedBox(height: 40),
        const Center(child: Column(children: [
          Icon(Icons.receipt_long_outlined, size: 56, color: Colors.grey),
          SizedBox(height: 12),
          Text('Masukkan nomor pesanan di atas\nuntuk melihat status.',
              style: TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.grey,
                  height: 1.6),
              textAlign: TextAlign.center),
        ])),
      ],
    ]));
}

// ── Order Status Card ──────────────────────────────────────────────
class _OrderStatusCard extends StatelessWidget {
  final Map<String, dynamic> order;
  final List<Map<String, dynamic>> items;
  const _OrderStatusCard({required this.order, required this.items});

  static const _statusLabels = {
    'new':       '🆕 Pesanan Baru',
    'preparing': '👨‍🍳 Sedang Dimasak',
    'ready':     '✅ Siap Disajikan',
    'served':    '🍽️ Sudah Disajikan',
    'paid':      '💳 Lunas',
    'cancelled': '❌ Dibatalkan',
  };
  static const _statusColors = {
    'new':       Color(0xFF6B7280),
    'preparing': Color(0xFFD97706),
    'ready':     Color(0xFF1D9E75),
    'served':    Color(0xFF0F3460),
    'paid':      Color(0xFF1D9E75),
    'cancelled': Color(0xFFE94560),
  };
  static const _statusMessages = {
    'new':       '⏳ Pesananmu sedang menunggu konfirmasi dapur.',
    'preparing': '🔥 Dapur sedang memasak pesananmu, sebentar lagi!',
    'ready':     '🎉 Pesananmu siap! Pelayan akan segera mengantarkan.',
    'served':    '😊 Pesananmu sudah disajikan. Selamat menikmati!',
    'paid':      '✅ Pembayaran selesai. Terima kasih sudah berkunjung!',
    'cancelled': '❌ Pesanan ini dibatalkan.',
  };

  @override
  Widget build(BuildContext context) {
    final status      = order['status'] as String? ?? 'new';
    final statusLabel = _statusLabels[status] ?? status;
    final statusColor = _statusColors[status] ?? Colors.grey;
    final statusMsg   = _statusMessages[status] ?? '';
    final total       = (order['total_amount'] as num?)?.toDouble() ?? 0;
    final customerName = order['customer_name'] as String?;
    final notes       = order['notes'] as String?;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(
          color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Row(children: [
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(order['order_number'] as String? ?? '',
                  style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w800,
                      fontSize: 16)),
              if (customerName != null)
                Text('Atas nama: $customerName',
                    style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        color: Colors.grey)),
            ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20)),
            child: Text(statusLabel,
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: statusColor))),
        ]),

        if (statusMsg.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10)),
            child: Text(statusMsg,
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    color: statusColor,
                    height: 1.4))),
        ],

        const Divider(height: 20),
        _StatusProgress(status: status),
        const SizedBox(height: 16),

        const Text('Item Pesanan',
            style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                fontSize: 13)),
        const SizedBox(height: 8),
        ...items.map((item) {
          final name    = (item['menu_items'] as Map?)?['name'] as String? ?? '-';
          final qty     = item['quantity'] as int? ?? 1;
          final sub     = (item['subtotal'] as num?)?.toDouble() ?? 0;
          final special = item['special_requests'] as String?;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text('${qty}x ',
                    style: const TextStyle(
                        fontFamily: 'Poppins',
                        color: Colors.grey,
                        fontSize: 12)),
                Expanded(child: Text(name,
                    style: const TextStyle(
                        fontFamily: 'Poppins', fontSize: 12))),
                Text('Rp ${_fmt(sub)}',
                    style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        fontWeight: FontWeight.w500)),
              ]),
              if (special != null && special.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 24, top: 2),
                  child: Text('⚡ $special',
                      style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 11,
                          color: Color(0xFFD97706)))),
            ]));
        }),

        if (notes != null && notes.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(8)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.notes, size: 14, color: Colors.grey),
              const SizedBox(width: 6),
              Expanded(child: Text(notes,
                  style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11,
                      color: Colors.grey))),
            ])),
        ],

        const Divider(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Total',
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                  fontSize: 14)),
          Text('Rp ${_fmt(total)}',
              style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: Color(0xFFE94560))),
        ]),

        if (status != 'paid' && status != 'cancelled') ...[
          const SizedBox(height: 10),
          const Text('💡 Pembayaran di kasir saat pesanan siap.',
              style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 11, color: Colors.grey)),
        ],
      ]));
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
}

// ── Progress Bar ───────────────────────────────────────────────────
class _StatusProgress extends StatelessWidget {
  final String status;
  const _StatusProgress({required this.status});

  @override
  Widget build(BuildContext context) {
    const steps  = ['new', 'preparing', 'ready', 'served', 'paid'];
    const labels = ['Baru', 'Masak', 'Siap', 'Saji', 'Lunas'];
    final currentIdx  = steps.indexOf(status);
    final isCancelled = status == 'cancelled';

    if (isCancelled) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.cancel_outlined, color: Color(0xFFE94560), size: 18),
          SizedBox(width: 6),
          Text('Pesanan dibatalkan',
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  color: Color(0xFFE94560),
                  fontWeight: FontWeight.w600)),
        ]));
    }

    return Row(
      children: steps.asMap().entries.map((e) {
        final idx       = e.key;
        final isActive  = idx <= currentIdx;
        final isCurrent = idx == currentIdx;
        final isLast    = idx == steps.length - 1;

        return Expanded(child: Row(children: [
          Expanded(child: Column(children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: isCurrent ? 24 : 20,
              height: isCurrent ? 24 : 20,
              decoration: BoxDecoration(
                color: isActive
                    ? const Color(0xFFE94560)
                    : const Color(0xFFE5E7EB),
                shape: BoxShape.circle,
                boxShadow: isCurrent
                    ? [BoxShadow(
                        color: const Color(0xFFE94560).withValues(alpha: 0.4),
                        blurRadius: 8)]
                    : []),
              child: isActive
                  ? const Icon(Icons.check, color: Colors.white, size: 12)
                  : null),
            const SizedBox(height: 4),
            Text(labels[idx],
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 9,
                    fontWeight: isCurrent
                        ? FontWeight.w700
                        : FontWeight.normal,
                    color: isActive
                        ? const Color(0xFFE94560)
                        : Colors.grey),
                textAlign: TextAlign.center),
          ])),
          if (!isLast)
            Expanded(child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              height: 2,
              color: idx < currentIdx
                  ? const Color(0xFFE94560)
                  : const Color(0xFFE5E7EB))),
        ]));
      }).toList());
  }
}