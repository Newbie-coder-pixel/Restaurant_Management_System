import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
            style: TextStyle(fontFamily: 'Poppins', fontSize: 22,
              fontWeight: FontWeight.w800, color: Color(0xFF1A1A2E)),
            textAlign: TextAlign.center),
          const SizedBox(height: 12),
          const Text('Pesananmu sudah masuk ke dapur.\nSilakan tunjukkan kode ini ke kasir.',
            style: TextStyle(fontFamily: 'Poppins', color: Colors.grey,
              height: 1.6), textAlign: TextAlign.center),
          const SizedBox(height: 28),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(16)),
            child: Column(children: [
              const Text('No. Pesanan', style: TextStyle(
                fontFamily: 'Poppins', color: Colors.white54, fontSize: 12)),
              const SizedBox(height: 4),
              Text(orderNumber, style: const TextStyle(
                fontFamily: 'Poppins', color: Colors.white,
                fontSize: 22, fontWeight: FontWeight.w800,
                letterSpacing: 2)),
            ])),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: () => context.go('/customer/track'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE94560),
              foregroundColor: Colors.white,
              minimumSize: const Size(200, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12))),
            child: const Text('Cek Status Pesanan',
              style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700))),
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
            style: TextStyle(fontFamily: 'Poppins', fontSize: 22,
              fontWeight: FontWeight.w800, color: Color(0xFF1A1A2E)),
            textAlign: TextAlign.center),
          const SizedBox(height: 12),
          const Text('Reservasi kamu sudah tercatat.\nKami menantikan kedatanganmu!',
            style: TextStyle(fontFamily: 'Poppins', color: Colors.grey,
              height: 1.6), textAlign: TextAlign.center),
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
              style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700))),
        ]))));
}

// ── Order Tracker Screen ───────────────────────────────────────────
class CustomerOrderTrackerScreen extends StatefulWidget {
  const CustomerOrderTrackerScreen({super.key});
  @override
  State<CustomerOrderTrackerScreen> createState() => _CustomerOrderTrackerScreenState();
}

class _CustomerOrderTrackerScreenState extends State<CustomerOrderTrackerScreen> {
  final _ctrl = TextEditingController();
  Map<String, dynamic>? _order;
  List<Map<String, dynamic>> _items = [];
  bool _loading = false;
  String? _error;

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _search() async {
    final code = _ctrl.text.trim().toUpperCase();
    if (code.isEmpty) return;
    setState(() { _loading = true; _error = null; _order = null; _items = []; });
    try {
      // ✅ Fix 1: Hapus cast (orders as List) yang tidak perlu — Supabase sudah return List
      final orders = await Supabase.instance.client
          .from('orders').select()
          .ilike('order_number', '%$code%')
          .limit(1);
      if (orders.isEmpty) {
        setState(() { _error = 'Pesanan tidak ditemukan'; _loading = false; });
        return;
      }
      final order = orders.first;
      final items = await Supabase.instance.client
          .from('order_items')
          .select('*, menu_items(name)')
          .eq('order_id', order['id'])
          .order('created_at');
      // ✅ Fix 2: Tambah curly braces pada if (mounted)
      if (mounted) {
        setState(() {
          _order = order;
          _items = items.cast();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() { _error = 'Error: $e'; _loading = false; });
      }
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
    ),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      // Search box
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Masukkan Nomor Pesanan',
            style: TextStyle(fontFamily: 'Poppins',
              fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: TextField(
              controller: _ctrl,
              textCapitalization: TextCapitalization.characters,
              style: const TextStyle(fontFamily: 'Poppins',
                fontWeight: FontWeight.w700, letterSpacing: 1.5),
              decoration: InputDecoration(
                hintText: 'Contoh: WEB-1234567',
                hintStyle: const TextStyle(fontFamily: 'Poppins',
                  fontWeight: FontWeight.normal, color: Colors.grey,
                  letterSpacing: 0),
                filled: true, fillColor: const Color(0xFFF3F4F6),
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
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.search_rounded)),
          ]),
        ])),

      if (_error != null) ...[
        const SizedBox(height: 20),
        Center(child: Text(_error!, style: const TextStyle(
          fontFamily: 'Poppins', color: Colors.red))),
      ],

      if (_order != null) ...[
        const SizedBox(height: 16),
        _OrderStatusCard(order: _order!, items: _items),
      ],

      if (_order == null && _error == null) ...[
        const SizedBox(height: 32),
        const Center(child: Column(children: [
          Icon(Icons.receipt_long_outlined, size: 48, color: Colors.grey),
          SizedBox(height: 12),
          Text('Masukkan nomor pesanan di atas\nuntuk melihat status.',
            style: TextStyle(fontFamily: 'Poppins', color: Colors.grey,
              height: 1.6), textAlign: TextAlign.center),
        ])),
      ],
    ]));
}

class _OrderStatusCard extends StatelessWidget {
  final Map<String, dynamic> order;
  final List<Map<String, dynamic>> items;
  const _OrderStatusCard({required this.order, required this.items});

  static const _statusLabels = {
    'new':        '🆕 Pesanan Baru',
    'preparing':  '👨‍🍳 Sedang Dimasak',
    'ready':      '✅ Siap Disajikan',
    'served':     '🍽️ Sudah Disajikan',
    'paid':       '💳 Lunas',
    'cancelled':  '❌ Dibatalkan',
  };
  static const _statusColors = {
    'new':       Color(0xFF6B7280),
    'preparing': Color(0xFFD97706),
    'ready':     Color(0xFF1D9E75),
    'served':    Color(0xFF0F3460),
    'paid':      Color(0xFF1D9E75),
    'cancelled': Color(0xFFE94560),
  };

  @override
  Widget build(BuildContext context) {
    final status = order['status'] as String? ?? 'new';
    final statusLabel = _statusLabels[status] ?? status;
    final statusColor = _statusColors[status] ?? Colors.grey;
    final total = (order['total_amount'] as num?)?.toDouble() ?? 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(order['order_number'] as String? ?? '',
            style: const TextStyle(fontFamily: 'Poppins',
              fontWeight: FontWeight.w800, fontSize: 16))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20)),
            child: Text(statusLabel, style: TextStyle(
              fontFamily: 'Poppins', fontSize: 11,
              fontWeight: FontWeight.w600, color: statusColor))),
        ]),
        const Divider(height: 20),
        _StatusProgress(status: status),
        const SizedBox(height: 16),
        const Text('Item Pesanan', style: TextStyle(
          fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 13)),
        const SizedBox(height: 8),
        ...items.map((item) {
          final name = (item['menu_items'] as Map?)?['name'] as String? ?? '-';
          final qty = item['quantity'] as int? ?? 1;
          final sub = (item['subtotal'] as num?)?.toDouble() ?? 0;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              Text('${qty}x ', style: const TextStyle(
                fontFamily: 'Poppins', color: Colors.grey, fontSize: 12)),
              Expanded(child: Text(name, style: const TextStyle(
                fontFamily: 'Poppins', fontSize: 12))),
              Text('Rp ${_fmt(sub)}', style: const TextStyle(
                fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w500)),
            ]));
        }),
        const Divider(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Total', style: TextStyle(
            fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 14)),
          Text('Rp ${_fmt(total)}', style: const TextStyle(
            fontFamily: 'Poppins', fontWeight: FontWeight.w800,
            fontSize: 15, color: Color(0xFFE94560))),
        ]),
        if (status != 'paid' && status != 'cancelled') ...[
          const SizedBox(height: 10),
          const Text('💡 Pembayaran di kasir saat pesanan siap.',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: Colors.grey)),
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

class _StatusProgress extends StatelessWidget {
  final String status;
  const _StatusProgress({required this.status});

  @override
  Widget build(BuildContext context) {
    const steps = ['new', 'preparing', 'ready', 'served', 'paid'];
    final currentIdx = steps.indexOf(status);

    return Row(children: steps.asMap().entries.map((e) {
      final idx = e.key;
      final isActive = idx <= currentIdx;
      final isLast = idx == steps.length - 1;
      return Expanded(child: Row(children: [
        Expanded(child: Column(children: [
          Container(
            width: 20, height: 20,
            decoration: BoxDecoration(
              color: isActive ? const Color(0xFFE94560) : const Color(0xFFE5E7EB),
              shape: BoxShape.circle),
            child: isActive
              ? const Icon(Icons.check, color: Colors.white, size: 12)
              : null),
          const SizedBox(height: 4),
          Text(['Baru','Masak','Siap','Saji','Lunas'][idx],
            style: TextStyle(fontFamily: 'Poppins', fontSize: 9,
              color: isActive ? const Color(0xFFE94560) : Colors.grey),
            textAlign: TextAlign.center),
        ])),
        if (!isLast)
          Expanded(child: Container(
            height: 2,
            color: idx < currentIdx
              ? const Color(0xFFE94560) : const Color(0xFFE5E7EB))),
      ]));
    }).toList());
  }
}