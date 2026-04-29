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

  final Map<String, TextEditingController> _itemNotesCtrls = {};

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _tableCtrl.dispose();
    _notesCtrl.dispose();
    for (final c in _itemNotesCtrls.values) { c.dispose(); }
    super.dispose();
  }

  void _syncItemNotesControllers(List<CartItem> items) {
    for (final item in items) {
      if (!_itemNotesCtrls.containsKey(item.menuItemId)) {
        _itemNotesCtrls[item.menuItemId] =
            TextEditingController(text: item.notes ?? '');
      }
    }
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

  // ── Konfirmasi sebelum submit ──────────────────────────────────
  Future<bool> _showConfirmDialog(CartState cart) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.shopping_cart_checkout, color: Color(0xFFE94560), size: 22),
          SizedBox(width: 10),
          Text('Konfirmasi Pesanan',
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                  fontSize: 16)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          // Ringkasan
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(10)),
            child: Column(children: [
              _confirmRow('Nama', _nameCtrl.text.trim()),
              if (_phoneCtrl.text.trim().isNotEmpty)
                _confirmRow('No. HP', _phoneCtrl.text.trim()),
              _confirmRow('Tipe',
                  _orderType == 'dine_in' ? 'Makan di sini' : 'Bawa pulang'),
              if (_orderType == 'dine_in' &&
                  _tableCtrl.text.trim().isNotEmpty)
                _confirmRow('Meja', _tableCtrl.text.trim()),
              _confirmRow('Total', 'Rp ${_fmt(cart.total)}'),
              _confirmRow('Item', '${cart.itemCount} item'),
            ])),
          const SizedBox(height: 10),
          const Text(
            '💡 Pembayaran dilakukan di kasir setelah pesanan selesai.',
            style: TextStyle(
                fontFamily: 'Poppins', fontSize: 11, color: Colors.grey),
            textAlign: TextAlign.center),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cek Lagi',
                style: TextStyle(
                    fontFamily: 'Poppins', color: Colors.grey))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE94560),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10))),
            child: const Text('Pesan Sekarang',
                style: TextStyle(
                    fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Widget _confirmRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(children: [
      Text('$label: ',
          style: const TextStyle(
              fontFamily: 'Poppins', fontSize: 12, color: Colors.grey)),
      Expanded(
        child: Text(value,
            style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A1A2E)),
            textAlign: TextAlign.end),
      ),
    ]),
  );

  Future<void> _placeOrder() async {
    final cart = ref.read(cartProvider);

    // Guard: cart kosong
    if (cart.isEmpty || cart.branchId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Cart kosong, tambahkan menu terlebih dahulu.'),
        backgroundColor: Colors.orange));
      return;
    }

    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Nama wajib diisi'),
        backgroundColor: Colors.red));
      return;
    }

    // Validasi nomor HP jika diisi
    final phone = _phoneCtrl.text.trim();
    if (phone.isNotEmpty) {
      final phoneRegex = RegExp(r'^08[0-9]{8,11}$');
      if (!phoneRegex.hasMatch(phone)) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Format nomor HP tidak valid. Contoh: 08123456789'),
          backgroundColor: Colors.red));
        return;
      }
    }

    // Simpan notes per item ke provider
    for (final entry in _itemNotesCtrls.entries) {
      ref.read(cartProvider.notifier).updateNotes(
          entry.key,
          entry.value.text.trim().isEmpty ? null : entry.value.text.trim());
    }

    // Konfirmasi dulu
    final confirmed = await _showConfirmDialog(cart);
    if (!confirmed || !mounted) return;

    setState(() => _submitting = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;

      final orderRes = await Supabase.instance.client
          .from('orders')
          .insert({
            'branch_id':       cart.branchId,
            'order_number':    _generateOrderNumber(),
            'status':          'new',
            'source':          _orderType == 'dine_in' ? 'dineIn' : 'takeaway', // webApp customer order
            'customer_name':   _nameCtrl.text.trim(),
            'customer_phone':  _phoneCtrl.text.trim().isEmpty
                ? null : _phoneCtrl.text.trim(),
            // FIX: simpan customer_user_id supaya bisa filter di history
            'customer_user_id': user?.id,
            'subtotal':        cart.subtotal,
            'tax_amount':      cart.tax,
            'discount_amount': 0,
            'total_amount':    cart.total,
            'notes':           _buildOrderNotes(),
          })
          .select()
          .single();

      final orderId = orderRes['id'] as String;

      // FIX: gunakan menuItemId langsung (UUID), bukan lookup by name
      // cart_provider sudah menyimpan menuItemId yang benar
      final orderItems = ref.read(cartProvider).items.map((item) => {
        'order_id':     orderId,
        // FIX: pastikan menu_item_id valid — kalau kosong skip
        'menu_item_id': item.menuItemId,
        'quantity':     item.quantity,
        'unit_price':   item.price,
        'subtotal':     item.subtotal,
        'status':       'pending',
        if (item.notes != null && item.notes!.isNotEmpty)
          'special_requests': item.notes,
      }).where((i) => (i['menu_item_id'] as String).isNotEmpty).toList();

      if (orderItems.isEmpty) throw Exception('Tidak ada item valid di cart.');

      await Supabase.instance.client.from('order_items').insert(orderItems);

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
          backgroundColor: Colors.red));
        setState(() => _submitting = false);
      }
    }
  }

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

  // FIX: exact match table_number, bukan ilike
  Future<void> _markTableOccupied(
      String branchId, String tableNumber) async {
    try {
      final tables = await Supabase.instance.client
          .from('restaurant_tables')
          .select('id')
          .eq('branch_id', branchId)
          .eq('table_number', tableNumber) // FIX: exact match
          .limit(1);
      if ((tables as List).isNotEmpty) {
        await Supabase.instance.client
            .from('restaurant_tables')
            .update({'status': 'occupied'})
            .eq('id', tables.first['id']);
      }
    } catch (_) {
      // Non-critical
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    _syncItemNotesControllers(cart.items);

    // Guard: redirect kalau cart kosong
    if (cart.isEmpty) {
      return Scaffold(
        backgroundColor: const Color(0xFFFAF8F5),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1A1A2E),
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 18),
            onPressed: () => context.canPop() ? context.pop() : context.go('/customer?tab=0')),
          title: const Text('Checkout',
              style: TextStyle(
                  fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        ),
        body: Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.shopping_cart_outlined,
                size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('Cart kamu kosong',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A2E))),
            const SizedBox(height: 8),
            const Text('Tambahkan menu terlebih dahulu',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    color: Colors.grey)),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => context.go('/customer'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE94560),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12))),
              child: const Text('Lihat Menu',
                  style: TextStyle(
                      fontFamily: 'Poppins', fontWeight: FontWeight.w600))),
          ])),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFFAF8F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () => context.canPop() ? context.pop() : context.go('/customer?tab=0')),
        title: const Text('Checkout',
            style: TextStyle(
                fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        // Badge item count di appbar
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFE94560),
              borderRadius: BorderRadius.circular(12)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.shopping_cart_outlined,
                  color: Colors.white, size: 14),
              const SizedBox(width: 4),
              Text('${cart.itemCount}',
                  style: const TextStyle(
                      fontFamily: 'Poppins',
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
            ])),
        ],
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
            _phoneField(),
            if (_orderType == 'dine_in') ...[
              const SizedBox(height: 10),
              _field('Nomor meja', _tableCtrl,
                  Icons.table_restaurant_outlined,
                  keyboardType: TextInputType.number),
            ],
            const SizedBox(height: 10),
            _field('Catatan umum pesanan', _notesCtrl,
                Icons.notes_outlined, maxLines: 2),
          ]),
          const SizedBox(height: 16),

          // ── Ringkasan pesanan
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
                const Text('Total',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: Color(0xFF1A1A2E))),
                const Spacer(),
                Text('Rp ${_fmt(cart.total)}',
                    style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: Color(0xFFE94560))),
              ]),
            ),
            const SizedBox(height: 8),
            const Text('💡 Pembayaran dilakukan di kasir',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    color: Color(0xFF9CA3AF))),
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
                      style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w700,
                          fontSize: 15)),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

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
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    color: Color(0xFFE94560),
                    fontWeight: FontWeight.w700,
                    fontSize: 12)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(item.name,
              style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  color: Color(0xFF1A1A2E)))),
          Text('Rp ${_fmt(item.subtotal)}',
              style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w600,
                  fontSize: 13)),
        ]),
        if (notesCtrl != null) ...[
          const SizedBox(height: 6),
          TextField(
            controller: notesCtrl,
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 11),
            decoration: InputDecoration(
              hintText: 'Catatan untuk item ini (contoh: tidak pedas...)',
              hintStyle: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  color: Colors.grey),
              prefixIcon: const Icon(Icons.edit_note,
                  size: 16, color: Colors.grey),
              filled: true,
              fillColor: const Color(0xFFF3F4F6),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 8),
              isDense: true),
          ),
        ],
      ]),
    );
  }

  Widget _section(String title, List<Widget> children) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      boxShadow: [BoxShadow(
          color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)]),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title,
          style: const TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: Color(0xFF1A1A2E))),
      const SizedBox(height: 12),
      ...children,
    ]));

  Widget _phoneField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _phoneCtrl,
          keyboardType: TextInputType.phone,
          style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'Contoh: 08123456789',
            hintStyle: const TextStyle(
                fontFamily: 'Poppins', fontSize: 13, color: Colors.grey),
            prefixIcon: const Icon(Icons.phone_outlined, size: 18, color: Colors.grey),
            suffixIcon: _phoneCtrl.text.trim().isNotEmpty
                ? Icon(
                    _isValidPhone(_phoneCtrl.text.trim())
                        ? Icons.check_circle
                        : Icons.cancel,
                    size: 18,
                    color: _isValidPhone(_phoneCtrl.text.trim())
                        ? Colors.green
                        : Colors.red,
                  )
                : null,
            filled: true,
            fillColor: const Color(0xFFF9F9F9),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: _phoneCtrl.text.trim().isNotEmpty && !_isValidPhone(_phoneCtrl.text.trim())
                    ? const BorderSide(color: Colors.red, width: 1.5)
                    : BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 10)),
        ),
        if (_phoneCtrl.text.trim().isNotEmpty && !_isValidPhone(_phoneCtrl.text.trim())) ...[
          const SizedBox(height: 4),
          const Padding(
            padding: EdgeInsets.only(left: 4),
            child: Text(
              'Format: 08xxxxxxxxxx (10–13 digit)',
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  color: Colors.red),
            ),
          ),
        ],
      ],
    );
  }

  bool _isValidPhone(String phone) {
    return RegExp(r'^08[0-9]{8,11}$').hasMatch(phone);
  }

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
          filled: true,
          fillColor: const Color(0xFFF9F9F9),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(
              horizontal: 12, vertical: 10)));

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
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _orderType == value ? Colors.white : Colors.grey)),
          ])));

  Widget _row(String label, String value) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(label,
          style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              color: Color(0xFF6B7280))),
      Text('Rp $value',
          style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              color: Color(0xFF1A1A2E))),
    ]);

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