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

  List<Map<String, dynamic>> _availableTables = [];
  String? _selectedTableNumber;
  bool _loadingTables = false;
  String? _lastFetchedBranchId;

  final Map<String, TextEditingController> _itemNotesCtrls = {};

  // ── TAMBAH: flag agar fetch hanya dipanggil sekali dari didChangeDependencies
  bool _didFetchOnce = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Panggil fetch di sini (bukan di build), hanya sekali saat branchId tersedia
    if (!_didFetchOnce) {
      final cart = ref.read(cartProvider);
      if (_orderType == 'dine_in' && cart.branchId != null) {
        _didFetchOnce = true;
        _fetchTables(cart.branchId!);
      }
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _tableCtrl.dispose();
    _notesCtrl.dispose();
    for (final c in _itemNotesCtrls.values) { c.dispose(); }
    super.dispose();
  }

  Future<void> _fetchTables(String branchId) async {
    // Guard: jangan fetch ulang jika branchId sama
    if (_lastFetchedBranchId == branchId) return;
    setState(() {
      _loadingTables = true;
      _selectedTableNumber = null;
    });
    try {
      final res = await Supabase.instance.client
          .from('restaurant_tables')
          .select('id, table_number, capacity, status')
          .eq('branch_id', branchId)
          .eq('is_active', true)
          .order('table_number', ascending: true);

      if (mounted) {
        setState(() {
          _availableTables = List<Map<String, dynamic>>.from(res);
          _lastFetchedBranchId = branchId;
          _loadingTables = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingTables = false);
        debugPrint('_fetchTables error: $e');
      }
    }
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
              if (_orderType == 'dine_in' && _selectedTableNumber != null)
                _confirmRow('Meja', 'No. $_selectedTableNumber'),
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

      final orderRes = await Supabase.instance.client
          .from('orders')
          .insert({
            'branch_id':        cart.branchId,
            'order_number':     _generateOrderNumber(),
            'status':           'new',
            'source':           _orderType == 'dine_in' ? 'dine_in' : 'takeaway',
            'customer_name':    _nameCtrl.text.trim(),
            'customer_phone':   _phoneCtrl.text.trim().isEmpty
                ? null : _phoneCtrl.text.trim(),
            'customer_user_id': user?.id,
            'discount_amount':  0,
            'notes':            _buildOrderNotes(),
          })
          .select()
          .single();

      final orderId = orderRes['id'] as String;

      final orderItems = ref.read(cartProvider).items.map((item) => {
        'order_id':     orderId,
        'menu_item_id': item.menuItemId,
        'quantity':     item.quantity,
        'unit_price':   item.price,
        'status':       'pending',
        if (item.notes != null && item.notes!.isNotEmpty)
          'special_requests': item.notes,
      }).where((i) => (i['menu_item_id'] as String).isNotEmpty).toList();

      if (orderItems.isEmpty) throw Exception('Tidak ada item valid di cart.');

      await Supabase.instance.client.from('order_items').insert(orderItems);

      if (_orderType == 'dine_in' && _selectedTableNumber != null) {
        await _markTableOccupied(cart.branchId!, _selectedTableNumber!);
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
    if (_orderType == 'dine_in' && _selectedTableNumber != null) {
      parts.add('Meja: $_selectedTableNumber');
    }
    if (_notesCtrl.text.trim().isNotEmpty) {
      parts.add(_notesCtrl.text.trim());
    }
    return parts.isEmpty ? null : parts.join(' | ');
  }

  Future<void> _markTableOccupied(
      String branchId, String tableNumber) async {
    try {
      final tables = await Supabase.instance.client
          .from('restaurant_tables')
          .select('id')
          .eq('branch_id', branchId)
          .eq('table_number', tableNumber)
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

    // ✅ HAPUS pemanggilan _fetchTables dari sini!
    // Sudah dipindah ke didChangeDependencies

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
            Row(children: [
              Expanded(child: _typeBtn(
                  'Makan di sini', Icons.restaurant_outlined, 'dine_in')),
              const SizedBox(width: 10),
              Expanded(child: _typeBtn(
                  'Bawa pulang', Icons.shopping_bag_outlined, 'takeaway')),
            ]),
          ]),
          const SizedBox(height: 16),

          _section('Informasi Pemesan', [
            _field('Nama kamu *', _nameCtrl, Icons.person_outline),
            const SizedBox(height: 10),
            _phoneField(),
            if (_orderType == 'dine_in') ...[
              const SizedBox(height: 10),
              _tableDropdown(),
            ],
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

  Widget _tableDropdown() {
    if (_loadingTables) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF9F9F9),
          borderRadius: BorderRadius.circular(10)),
        child: const Row(children: [
          Icon(Icons.table_restaurant_outlined, size: 18, color: Colors.grey),
          SizedBox(width: 12),
          SizedBox(
            width: 16, height: 16,
            child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 10),
          Text('Memuat daftar meja...',
              style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 13, color: Colors.grey)),
        ]),
      );
    }

    if (_availableTables.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF3F3),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.red.shade100)),
        child: const Row(children: [
          Icon(Icons.info_outline, size: 18, color: Colors.orange),
          SizedBox(width: 10),
          Text('Tidak ada meja tersedia di cabang ini',
              style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 13, color: Colors.orange)),
        ]),
      );
    }

    return DropdownButtonFormField<String>(
      initialValue: _selectedTableNumber,   // ✅ fix: was 'value'
      decoration: InputDecoration(
        hintText: 'Pilih nomor meja',
        hintStyle: const TextStyle(
            fontFamily: 'Poppins', fontSize: 13, color: Colors.grey),
        prefixIcon: const Icon(
            Icons.table_restaurant_outlined, size: 18, color: Colors.grey),
        filled: true,
        fillColor: const Color(0xFFF9F9F9),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(
            horizontal: 12, vertical: 10),
      ),
      style: const TextStyle(
          fontFamily: 'Poppins', fontSize: 13, color: Color(0xFF1A1A2E)),
      icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.grey),
      isExpanded: true,
      items: _availableTables.map((table) {
        final number = table['table_number']?.toString() ?? '-';
        final capacity = table['capacity'];
        final status = table['status']?.toString() ?? '';
        final isOccupied = status == 'occupied';

        return DropdownMenuItem<String>(
          value: number,
          enabled: !isOccupied,
          child: Row(children: [
            Icon(
              isOccupied ? Icons.block : Icons.check_circle_outline,
              size: 14,
              color: isOccupied ? Colors.red.shade300 : Colors.green.shade400,
            ),
            const SizedBox(width: 8),
            Text(
              'Meja $number',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                color: isOccupied
                    ? Colors.grey.shade400
                    : const Color(0xFF1A1A2E),
              ),
            ),
            if (capacity != null) ...[
              const SizedBox(width: 6),
              Text(
                '($capacity kursi)',   // ✅ fix: was '${capacity}'
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    color: Colors.grey.shade500),
              ),
            ],
            if (isOccupied) ...[
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(6)),
                child: Text('Terisi',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 10,
                        color: Colors.red.shade400,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ]),
        );
      }).toList(),
      onChanged: (val) => setState(() => _selectedTableNumber = val),
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

  Widget _typeBtn(String label, IconData icon, String value) =>
      GestureDetector(
        onTap: () {
          setState(() {
            _orderType = value;
            if (value != 'dine_in') {
              _selectedTableNumber = null;
            } else {
              // ✅ Fetch ulang meja jika user switch ke dine_in
              final branchId = ref.read(cartProvider).branchId;
              if (branchId != null) {
                _lastFetchedBranchId = null; // reset guard agar bisa fetch ulang
                _fetchTables(branchId);
              }
            }
          });
        },
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