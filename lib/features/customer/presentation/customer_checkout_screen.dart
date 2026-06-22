import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
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
  final _notesCtrl = TextEditingController();
  bool _submitting = false;

  final Map<String, TextEditingController> _itemNotesCtrls = {};

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
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

  Future<bool> _showConfirmDialog(CartState cart) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ──────────────────────────────────────────────
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A2E),
                    borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.shopping_cart_outlined,
                      color: Colors.white, size: 18)),
                const SizedBox(width: 10),
                const Text('Konfirmasi Pesanan',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: Color(0xFF1A1A2E))),
              ]),
              const SizedBox(height: 16),

              // ── Info rows ───────────────────────────────────────────
              _dialogRow('Nama', _nameCtrl.text.trim()),
              if (_phoneCtrl.text.trim().isNotEmpty)
                _dialogRow('No. HP', _phoneCtrl.text.trim()),
              _dialogRow('Tipe', 'Bawa Pulang'),
              _dialogRow('Total', 'Rp ${_fmt(cart.total)}'),
              _dialogRow('Item', '${cart.itemCount} item'),
              const SizedBox(height: 14),

              // ── Warning box ─────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF0F0),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: const Color(0xFFE94560).withValues(alpha: 0.25))),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(Icons.error_outline,
                          color: Color(0xFFE94560), size: 16),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Pesanan yang telah dikirim ke dapur tidak dapat dibatalkan.',
                          style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFE94560)),
                        ),
                      ),
                    ]),
                    SizedBox(height: 6),
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(Icons.check_circle_outline,
                          color: Color(0xFFE94560), size: 16),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Pastikan pesanan sudah benar sebelum melanjutkan.',
                          style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 11,
                              color: Color(0xFFE94560)),
                        ),
                      ),
                    ]),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ── Buttons ─────────────────────────────────────────────
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF6B7280),
                      side: const BorderSide(color: Color(0xFFD1D5DB)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      minimumSize: const Size(0, 44)),
                    child: const Text('Cek Lagi',
                        style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w600,
                            fontSize: 13)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1A1A2E),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      minimumSize: const Size(0, 44),
                      elevation: 0),
                    child: const Text('Pesan Sekarang',
                        style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w600,
                            fontSize: 13)),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
    return result ?? false;
  }

  Widget _dialogRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                color: Color(0xFF6B7280))),
        Text(value,
            style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A1A2E))),
      ],
    ),
  );



  Future<void> _placeOrder() async {
    final cart = ref.read(cartProvider);

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

    for (final entry in _itemNotesCtrls.entries) {
      ref.read(cartProvider.notifier).updateNotes(
          entry.key,
          entry.value.text.trim().isEmpty ? null : entry.value.text.trim());
    }

    final confirmed = await _showConfirmDialog(cart);
    if (!confirmed || !mounted) return;

    setState(() => _submitting = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;

      // Generate id & order_number di client — hindari .select() setelah insert
      // agar tidak kena RLS 403 saat anon SELECT
      final orderId      = const Uuid().v4();
      final orderNumber  = _generateOrderNumber();

      await Supabase.instance.client
          .from('orders')
          .insert({
            'id':               orderId,
            'branch_id':        cart.branchId,
            'order_number':     orderNumber,
            'status':           'new',
            'source':           'takeaway',
            'order_type':       'takeaway',
            'customer_name':    _nameCtrl.text.trim(),
            'customer_phone':   _phoneCtrl.text.trim().isEmpty
                ? null : _phoneCtrl.text.trim(),
            'customer_email':   user?.email,
            'customer_user_id': user?.id,
            'table_id':         null,
            'table_name':       null,
            'discount_amount':  0,
            'subtotal':         cart.subtotal,
            'tax_amount':       cart.pb1Amount,
            'total_amount':     cart.total,
            'payment_status':   'unpaid',
            'notes':            _notesCtrl.text.trim().isEmpty
                ? null : _notesCtrl.text.trim(),
          });

      final orderItems = ref.read(cartProvider).items.map((item) => {
        'order_id':        orderId,
        'menu_item_id':    item.menuItemId,
        'menu_item_name':  item.name,
        'quantity':        item.quantity,
        'unit_price':      item.price,
        // subtotal tidak di-insert karena generated column di Supabase
        'status':          'pending',
        if (item.notes != null && item.notes!.isNotEmpty)
          'special_requests': item.notes,
      }).where((i) => (i['menu_item_id'] as String).isNotEmpty).toList();

      if (orderItems.isEmpty) throw Exception('Tidak ada item valid di cart.');

      await Supabase.instance.client.from('order_items').insert(orderItems);

      ref.read(cartProvider.notifier).clear();

      if (mounted) {
        context.go('/customer/order-success/$orderNumber');
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

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    _syncItemNotesControllers(cart.items);

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
            const Icon(Icons.shopping_cart_outlined, size: 64, color: Colors.grey),
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
                    fontFamily: 'Poppins', fontSize: 13, color: Colors.grey)),
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
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFE94560),
              borderRadius: BorderRadius.circular(12)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.shopping_cart_outlined, color: Colors.white, size: 14),
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
          _section('Tipe Pesanan', [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFE94560).withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: const Color(0xFFE94560).withValues(alpha: 0.3))),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE94560),
                    borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.shopping_bag_outlined,
                    color: Colors.white, size: 18)),
                const SizedBox(width: 12),
                const Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Bawa Pulang (Takeaway)',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: Color(0xFF1A1A2E))),
                    SizedBox(height: 2),
                    Text('Ambil pesanan di restoran',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 11,
                        color: Color(0xFF9CA3AF))),
                  ])),
              ]),
            ),
          ]),
          const SizedBox(height: 16),

          _section('Informasi Pemesan', [
            _field('Nama kamu *', _nameCtrl, Icons.person_outline),
            const SizedBox(height: 10),
            _phoneField(),
            const SizedBox(height: 10),
            _field('Catatan umum pesanan', _notesCtrl,
                Icons.notes_outlined, maxLines: 2),
          ]),
          const SizedBox(height: 16),

          _section('Ringkasan Pesanan', [
            ...cart.items.map((item) => _buildItemRow(item)),
            const Divider(height: 20),
            _row('Subtotal', _fmt(cart.subtotal)),
            const SizedBox(height: 4),
            _row('Service Charge (3%)', _fmt(cart.serviceCharge)),
            const SizedBox(height: 4),
            _row('PB1 (10%)', _fmt(cart.pb1Amount)),
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

  // ── Helpers ────────────────────────────────────────────────────────────────

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
                  fontFamily: 'Poppins', fontSize: 11, color: Colors.grey),
              prefixIcon: const Icon(Icons.edit_note, size: 16, color: Colors.grey),
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
                borderSide: _phoneCtrl.text.trim().isNotEmpty &&
                        !_isValidPhone(_phoneCtrl.text.trim())
                    ? const BorderSide(color: Colors.red, width: 1.5)
                    : BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 10)),
        ),
        if (_phoneCtrl.text.trim().isNotEmpty &&
            !_isValidPhone(_phoneCtrl.text.trim())) ...[
          const SizedBox(height: 4),
          const Padding(
            padding: EdgeInsets.only(left: 4),
            child: Text(
              'Format: 08xxxxxxxxxx (10–13 digit)',
              style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 11, color: Colors.red),
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

  Widget _row(String label, String value) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(label,
          style: const TextStyle(
              fontFamily: 'Poppins', fontSize: 13, color: Color(0xFF6B7280))),
      Text('Rp $value',
          style: const TextStyle(
              fontFamily: 'Poppins', fontSize: 13, color: Color(0xFF1A1A2E))),
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