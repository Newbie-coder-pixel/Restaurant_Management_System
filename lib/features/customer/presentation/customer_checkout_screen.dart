import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/cart_provider.dart';

class CustomerCheckoutScreen extends ConsumerStatefulWidget {
  const CustomerCheckoutScreen({super.key});
  @override
  ConsumerState<CustomerCheckoutScreen> createState() => _CustomerCheckoutScreenState();
}

class _CustomerCheckoutScreenState extends ConsumerState<CustomerCheckoutScreen> {
  final _nameCtrl = TextEditingController();
  final _tableCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool _submitting = false;
  String _orderType = 'dine_in'; // dine_in | takeaway

  @override
  void dispose() {
    _nameCtrl.dispose();
    _tableCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _placeOrder() async {
    final cart = ref.read(cartProvider);
    if (cart.isEmpty || cart.branchId == null) return;
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nama wajib diisi'),
          backgroundColor: Colors.red));
      return;
    }
    setState(() => _submitting = true);
    try {
      final orderNum = 'WEB-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
      // Insert order
      final orderRes = await Supabase.instance.client.from('orders').insert({
        'branch_id':       cart.branchId,
        'order_number':    orderNum,
        'status':          'new',
        'source':          _orderType,
        'subtotal':        cart.subtotal,
        'tax_amount':      cart.tax,
        'discount_amount': 0,
        'total_amount':    cart.total,
        'notes': '${_nameCtrl.text.trim()}'
            '${_tableCtrl.text.trim().isNotEmpty ? " | Meja: ${_tableCtrl.text.trim()}" : ""}'
            '${_notesCtrl.text.trim().isNotEmpty ? " | ${_notesCtrl.text.trim()}" : ""}',
      }).select().single();

      final orderId = orderRes['id'];
      // Find menu item IDs
      final menuRes = await Supabase.instance.client
          .from('menu_items').select('id, name, price')
          .eq('branch_id', cart.branchId!).inFilter('name', cart.items.map((i) => i.name).toList());
      final menuMap = {
        for (final m in (menuRes as List)) (m['name'] as String): m
      };

      // Insert order items
      final orderItems = cart.items.map((item) {
        final menu = menuMap[item.name];
        return {
          'order_id':        orderId,
          'menu_item_id':    menu?['id'] ?? item.menuItemId,
          'quantity':        item.quantity,
          'unit_price':      item.price,
          'subtotal':        item.subtotal,
          'status':          'pending',
          if (item.notes != null && item.notes!.isNotEmpty)
            'special_requests': item.notes,
        };
      }).toList();
      await Supabase.instance.client.from('order_items').insert(orderItems);

      // Clear cart and go to success
      ref.read(cartProvider.notifier).clear();
      if (mounted) context.go('/customer/order-success/$orderNum');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memesan: $e'),
            backgroundColor: Colors.red));
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    return Scaffold(
      backgroundColor: const Color(0xFFFAF8F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () => context.pop()),
        title: const Text('Checkout',
          style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        // Order type selector
        _section('Tipe Pesanan', [
          Row(children: [
            Expanded(child: _typeBtn('Makan di sini', Icons.restaurant_outlined, 'dine_in')),
            const SizedBox(width: 10),
            Expanded(child: _typeBtn('Bawa pulang', Icons.shopping_bag_outlined, 'takeaway')),
          ]),
        ]),
        const SizedBox(height: 16),
        // Customer info
        _section('Informasi Pemesan', [
          _field('Nama kamu *', _nameCtrl, Icons.person_outline),
          const SizedBox(height: 10),
          if (_orderType == 'dine_in')
            _field('Nomor meja (opsional)', _tableCtrl, Icons.table_restaurant_outlined),
          if (_orderType == 'dine_in') const SizedBox(height: 10),
          _field('Catatan pesanan', _notesCtrl, Icons.notes_outlined, maxLines: 2),
        ]),
        const SizedBox(height: 16),
        // Order summary
        _section('Ringkasan Pesanan', [
          ...cart.items.map((item) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              Container(
                width: 28, height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFE94560).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6)),
                child: Text('${item.quantity}',
                  style: const TextStyle(fontFamily: 'Poppins',
                    color: Color(0xFFE94560), fontWeight: FontWeight.w700,
                    fontSize: 12))),
              const SizedBox(width: 10),
              Expanded(child: Text(item.name,
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 13,
                  color: Color(0xFF1A1A2E)))),
              Text('Rp ${_fmt(item.subtotal)}',
                style: const TextStyle(fontFamily: 'Poppins',
                  fontWeight: FontWeight.w600, fontSize: 13)),
            ]))),
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
            ])),
          const SizedBox(height: 8),
          const Text('💡 Pembayaran dilakukan di kasir',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
              color: Color(0xFF9CA3AF))),
        ]),
        const SizedBox(height: 24),
        // Place order button
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
              ? const SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2))
              : const Text('Pesan Sekarang 🛒',
                  style: TextStyle(fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700, fontSize: 15)))),
      ]));
  }

  Widget _section(String title, List<Widget> children) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white, borderRadius: BorderRadius.circular(14),
      boxShadow: [BoxShadow(
        color: Colors.black.withValues(alpha: 0.04),
        blurRadius: 8)]),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(
        fontFamily: 'Poppins', fontWeight: FontWeight.w700,
        fontSize: 14, color: Color(0xFF1A1A2E))),
      const SizedBox(height: 12),
      ...children,
    ]));

  Widget _field(String hint, TextEditingController ctrl, IconData icon, {int maxLines = 1}) =>
    TextField(
      controller: ctrl,
      maxLines: maxLines,
      style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontFamily: 'Poppins',
          fontSize: 13, color: Colors.grey),
        prefixIcon: Icon(icon, size: 18, color: Colors.grey),
        filled: true, fillColor: const Color(0xFFF9F9F9),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12, vertical: 10)));

  Widget _typeBtn(String label, IconData icon, String value) => GestureDetector(
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
        Icon(icon, color: _orderType == value ? Colors.white : Colors.grey, size: 20),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(
          fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w600,
          color: _orderType == value ? Colors.white : Colors.grey)),
      ])));

  Widget _row(String label, String value) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(label, style: const TextStyle(
        fontFamily: 'Poppins', fontSize: 13, color: Color(0xFF6B7280))),
      Text('Rp $value', style: const TextStyle(
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