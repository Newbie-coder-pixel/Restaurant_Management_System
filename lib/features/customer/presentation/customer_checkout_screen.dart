import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/cart_provider.dart';

class CustomerCheckoutScreen extends ConsumerStatefulWidget {
  const CustomerCheckoutScreen({super.key});
  @override
  ConsumerState<CustomerCheckoutScreen> createState() =>
      _CustomerCheckoutScreenState();
}

class _CustomerCheckoutScreenState
    extends ConsumerState<CustomerCheckoutScreen> {
  final _nameCtrl  = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _tableCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool _submitting = false;
  String _orderType = 'dine_in';

  // notes per item: key = menuItemId
  final Map<String, TextEditingController> _itemNotesCtrls = {};

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _tableCtrl.dispose();
    _notesCtrl.dispose();
    for (final c in _itemNotesCtrls.values) c.dispose();
    super.dispose();
  }

  // Pastikan controller notes tersedia untuk setiap item di cart
  void _syncItemNotesControllers(List<CartItem> items) {
    for (final item in items) {
      if (!_itemNotesCtrls.containsKey(item.menuItemId)) {
        _itemNotesCtrls[item.menuItemId] =
            TextEditingController(text: item.notes ?? '');
      }
    }
    // Hapus controller untuk item yang sudah dihapus dari cart
    _itemNotesCtrls.removeWhere(
        (id, _) => !items.any((i) => i.menuItemId == id));
  }

  String _generateOrderNumber() {
    final now  = DateTime.now();
    final date = '${now.year}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}';
    final rand = Random().nextInt(9000) + 1000;
    return 'WEB-$date-$rand';
  }

  Future<void> _placeOrder() async {
    final cart = ref.read(cartProvider);
    if (cart.isEmpty || cart.branchId == null) return;

    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Nama wajib diisi'),
        backgroundColor: Colors.red,
      ));
      return;
    }

    // Simpan notes per item ke provider sebelum submit
    for (final entry in _itemNotesCtrls.entries) {
      ref.read(cartProvider.notifier)
          .updateNotes(entry.key, entry.value.text.trim().isEmpty
              ? null
              : entry.value.text.trim());
    }

    setState(() => _submitting = true);
    try {
      final orderRes = await Supabase.instance.client
          .from('orders')
          .insert({
            'branch_id':       cart.branchId,
            'order_number':    _generateOrderNumber(),
            'status':          'new',
            'source':          _orderType == 'dine_in' ? 'dineIn' : 'takeaway',
            'customer_name':   _nameCtrl.text.trim(),
            'customer_phone':  _phoneCtrl.text.trim().isEmpty
                ? null
                : _phoneCtrl.text.trim(),
            'subtotal':        cart.subtotal,
            'tax_amount':      cart.tax,
            'discount_amount': 0,
            'total_amount':    cart.total,
            'notes': _buildOrderNotes(),
          })
          .select()
          .single();

      final orderId = orderRes['id'];

      // Resolve menu_item_id by name (fallback kalau id tidak ada)
      final menuRes = await Supabase.instance.client
          .from('menu_items')
          .select('id, name')
          .eq('branch_id', cart.branchId!)
          .inFilter('name', cart.items.map((i) => i.name).toList());
      final menuMap = {
        for (final m in (menuRes as List)) (m['name'] as String): m['id'] as String,
      };

      final orderItems = cart.items.map((item) => {
        'order_id':        orderId,
        'menu_item_id':    menuMap[item.name] ?? item.menuItemId,
        'quantity':        item.quantity,
        'unit_price':      item.price,
        'subtotal':        item.subtotal,
        'status':          'pending',
        if (item.notes != null && item.notes!.isNotEmpty)
          'special_requests': item.notes,
      }).toList();

      await Supabase.instance.client
          .from('order_items')
          .insert(orderItems);

      // Update table status kalau dine in dan ada nomor meja
      if (_orderType == 'dine_in' && _tableCtrl.text.trim().isNotEmpty) {
        await _markTableOccupied(cart.branchId!, _tableCtrl.text.trim());
      }

      ref.read(cartProvider.notifier).clear();
      if (mounted) {
        context.go('/customer/order-success/${orderRes['order_number']}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Gagal memesan: $e'),
          backgroundColor: Colors.red,
        ));
        setState(() => _submitting = false);
      }
    }
  }

  // Bangun notes order dari meja + catatan umum
  String? _buildOrderNotes() {
    final parts = <String>[];
    if (_orderType == 'dine_in' && _tableCtrl.text.trim().isNotEmpty) {
      parts.add('Meja: ${_tableCtrl.text.trim()}');
    }
    if (_notesCtrl.text.trim().isNotEmpty) {
      parts.add(_notesCtrl.text.trim());
    }
    return parts.isEmpty ? null : parts.join(' | ');
  }

  // Cari & update status meja berdasarkan nomor meja
  Future<void> _markTableOccupied(String branchId, String tableNumber) async {
    try {
      final tables = await Supabase.instance.client
          .from('restaurant_tables')
          .select('id')
          .eq('branch_id', branchId)
          .ilike('table_number', tableNumber)
          .limit(1);
      if ((tables as List).isNotEmpty) {
        await Supabase.instance.client
            .from('restaurant_tables')
            .update({'status': 'occupied'})
            .eq('id', tables.first['id']);
      }
    } catch (_) {
      // Non-critical, skip
    }
  }

  // ─── BUILD ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    _syncItemNotesControllers(cart.items);

    return Scaffold(
      backgroundColor: const Color(0xFFFAF8F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () => context.pop()),
        title: const Text('Checkout',
            style: TextStyle(
                fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Tipe pesanan
          _section('Tipe Pesanan', [
            Row(children: [
              Expanded(child: _typeBtn(
                  'Makan di sini', Icons.restaurant_outlined, 'dine_in')),
              const SizedBox(width: 10),
              Expanded(child: _typeBtn(
                  'Bawa pulang', Icons.shopping_bag_outlined, 'takeaway')),
            ]),
          ]),
          const SizedBox(height: 16),

          // ── Info pemesan
          _section('Informasi Pemesan', [
            _field('Nama kamu *', _nameCtrl, Icons.person_outline),
            const SizedBox(height: 10),
            _field('No. HP (opsional)', _phoneCtrl, Icons.phone_outlined,
                keyboardType: TextInputType.phone),
            if (_orderType == 'dine_in') ...[
              const SizedBox(height: 10),
              _field('Nomor meja (opsional)', _tableCtrl,
                  Icons.table_restaurant_outlined,
                  keyboardType: TextInputType.number),
            ],
            const SizedBox(height: 10),
            _field('Catatan umum pesanan', _notesCtrl,
                Icons.notes_outlined, maxLines: 2),
          ]),
          const SizedBox(height: 16),

          // ── Ringkasan pesanan + notes per item
          _section('Ringkasan Pesanan', [
            ...cart.items.map((item) => _buildItemRow(item)),
            const Divider(height: 20),
            _row('Subtotal', _fmt(cart.subtotal)),
            const SizedBox(height: 4),
            _row('PPN 11%', _fmt(cart.tax)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A2E).withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                const Text('Total', style: TextStyle(
                    fontFamily: 'Poppins', fontWeight: FontWeight.w800,
                    fontSize: 15, color: Color(0xFF1A1A2E))),
                const Spacer(),
                Text('Rp ${_fmt(cart.total)}', style: const TextStyle(
                    fontFamily: 'Poppins', fontWeight: FontWeight.w800,
                    fontSize: 16, color: Color(0xFFE94560))),
              ]),
            ),
            const SizedBox(height: 8),
            const Text('💡 Pembayaran dilakukan di kasir',
                style: TextStyle(fontFamily: 'Poppins',
                    fontSize: 11, color: Color(0xFF9CA3AF))),
          ]),
          const SizedBox(height: 24),

          // ── Tombol pesan
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _submitting ? null : _placeOrder,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE94560),
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0),
              child: _submitting
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Text('Pesan Sekarang 🛒',
                      style: TextStyle(fontFamily: 'Poppins',
                          fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Item row dengan inline notes input
  Widget _buildItemRow(CartItem item) {
    final notesCtrl = _itemNotesCtrls[item.menuItemId];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 28, height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFE94560).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6)),
            child: Text('${item.quantity}',
                style: const TextStyle(fontFamily: 'Poppins',
                    color: Color(0xFFE94560),
                    fontWeight: FontWeight.w700, fontSize: 12)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(item.name,
              style: const TextStyle(fontFamily: 'Poppins',
                  fontSize: 13, color: Color(0xFF1A1A2E)))),
          Text('Rp ${_fmt(item.subtotal)}',
              style: const TextStyle(fontFamily: 'Poppins',
                  fontWeight: FontWeight.w600, fontSize: 13)),
        ]),
        if (notesCtrl != null) ...[
          const SizedBox(height: 6),
          TextField(
            controller: notesCtrl,
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 11),
            decoration: InputDecoration(
              hintText: 'Catatan untuk item ini (contoh: tidak pedas, no bawang...)',
              hintStyle: const TextStyle(fontFamily: 'Poppins',
                  fontSize: 11, color: Colors.grey),
              prefixIcon: const Icon(Icons.edit_note,
                  size: 16, color: Colors.grey),
              filled: true,
              fillColor: const Color(0xFFF3F4F6),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 8),
              isDense: true,
            ),
          ),
        ],
      ]),
    );
  }

  // ── Reusable widgets
  Widget _section(String title, List<Widget> children) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      boxShadow: [BoxShadow(
          color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)]),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(
          fontFamily: 'Poppins', fontWeight: FontWeight.w700,
          fontSize: 14, color: Color(0xFF1A1A2E))),
      const SizedBox(height: 12),
      ...children,
    ]),
  );

  Widget _field(String hint, TextEditingController ctrl, IconData icon,
      {int maxLines = 1, TextInputType? keyboardType}) =>
      TextField(
        controller: ctrl,
        maxLines: maxLines,
        keyboardType: keyboardType,
        style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(
              fontFamily: 'Poppins', fontSize: 13, color: Colors.grey),
          prefixIcon: Icon(icon, size: 18, color: Colors.grey),
          filled: true, fillColor: const Color(0xFFF9F9F9),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(
              horizontal: 12, vertical: 10)),
      );

  Widget _typeBtn(String label, IconData icon, String value) =>
      GestureDetector(
        onTap: () => setState(() => _orderType = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: _orderType == value
                ? const Color(0xFFE94560)
                : const Color(0xFFF3F4F6),
            borderRadius: BorderRadius.circular(10)),
          child: Column(children: [
            Icon(icon,
                color: _orderType == value ? Colors.white : Colors.grey,
                size: 20),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _orderType == value
                        ? Colors.white
                        : Colors.grey)),
          ]),
        ),
      );

  Widget _row(String label, String value) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(label, style: const TextStyle(
          fontFamily: 'Poppins', fontSize: 13, color: Color(0xFF6B7280))),
      Text('Rp $value', style: const TextStyle(
          fontFamily: 'Poppins', fontSize: 13, color: Color(0xFF1A1A2E))),
    ],
  );

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