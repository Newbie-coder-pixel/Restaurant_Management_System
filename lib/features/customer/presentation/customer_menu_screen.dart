import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/cart_provider.dart';
import 'widgets/cart_bottom_bar.dart';

class CustomerMenuScreen extends ConsumerStatefulWidget {
  final String branchId;
  const CustomerMenuScreen({super.key, required this.branchId});
  @override
  ConsumerState<CustomerMenuScreen> createState() => _CustomerMenuScreenState();
}

class _CustomerMenuScreenState extends ConsumerState<CustomerMenuScreen> {
  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _menuItems = [];
  String? _selectedCategoryId;
  bool _loading = true;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final cats = await Supabase.instance.client
          .from('menu_categories').select()
          .eq('branch_id', widget.branchId).eq('is_active', true)
          .order('sort_order');
      final items = await Supabase.instance.client
          .from('menu_items').select()
          .eq('branch_id', widget.branchId).eq('is_available', true)
          .order('name');
      if (mounted) {
        setState(() {
          _categories = (cats as List).cast();
          _menuItems = (items as List).cast();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filteredItems {
    var items = _menuItems;
    if (_selectedCategoryId != null) {
      items = items.where((i) => i['category_id'] == _selectedCategoryId).toList();
    }
    if (_search.isNotEmpty) {
      items = items.where((i) =>
        (i['name'] as String).toLowerCase().contains(_search.toLowerCase())).toList();
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    return Scaffold(
      backgroundColor: const Color(0xFFFAF8F5),
      body: Column(children: [
        _buildHeader(),
        _buildSearchBar(),
        _buildCategoryChips(),
        Expanded(child: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFE94560)))
          : _filteredItems.isEmpty
              ? const Center(child: Text('Tidak ada menu',
                  style: TextStyle(fontFamily: 'Poppins', color: Colors.grey)))
              : GridView.builder(
                  padding: EdgeInsets.fromLTRB(16, 8, 16,
                    cart.isEmpty ? 16 : 100),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 200,
                    childAspectRatio: 0.72,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12),
                  itemCount: _filteredItems.length,
                  itemBuilder: (_, i) => _MenuCard(
                    item: _filteredItems[i],
                    cartQty: cart.items
                      .where((c) => c.menuItemId == _filteredItems[i]['id'])
                      .fold(0, (s, c) => s + c.quantity),
                    onAdd: () => ref.read(cartProvider.notifier).addItem(CartItem(
                      menuItemId: _filteredItems[i]['id'],
                      name: _filteredItems[i]['name'],
                      price: (_filteredItems[i]['price'] as num).toDouble(),
                      imageUrl: _filteredItems[i]['image_url'],
                    )),
                    onRemove: () => ref.read(cartProvider.notifier)
                      .updateQuantity(_filteredItems[i]['id'],
                        (cart.items.firstWhere(
                          (c) => c.menuItemId == _filteredItems[i]['id'],
                          orElse: () => CartItem(menuItemId: '', name: '', price: 0)).quantity) - 1),
                  ))),
        if (!cart.isEmpty)
          CartBottomBar(
            cart: cart,
            onCheckout: () => context.go('/customer/checkout')),
      ]),
    );
  }

  Widget _buildHeader() => Container(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: [Color(0xFF1A1A2E), Color(0xFF0F3460)])),
    padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 12, 16, 16),
    child: Row(children: [
      IconButton(
        icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
        onPressed: () => context.go('/customer')),
      const Expanded(
        child: Text('Menu', style: TextStyle(
          fontFamily: 'Poppins', color: Colors.white,
          fontSize: 18, fontWeight: FontWeight.w700),
          textAlign: TextAlign.center)),
      IconButton(
        icon: const Icon(Icons.calendar_today_outlined, color: Colors.white60, size: 20),
        tooltip: 'Booking meja',
        // FIX: pakai context.push agar back button bisa kembali ke menu ini
        onPressed: () => context.push('/customer/booking/${widget.branchId}')),
    ]));

  Widget _buildSearchBar() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
    child: TextField(
      onChanged: (v) => setState(() => _search = v),
      decoration: InputDecoration(
        hintText: 'Cari menu...',
        hintStyle: const TextStyle(fontFamily: 'Poppins', color: Colors.grey),
        prefixIcon: const Icon(Icons.search_rounded, color: Colors.grey),
        filled: true, fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(vertical: 12)),
      style: const TextStyle(fontFamily: 'Poppins')));

  Widget _buildCategoryChips() => SizedBox(
    height: 52,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      itemCount: _categories.length + 1,
      separatorBuilder: (_, __) => const SizedBox(width: 8),
      itemBuilder: (_, i) {
        if (i == 0) {
          return _chip('Semua', _selectedCategoryId == null,
            () => setState(() => _selectedCategoryId = null));
        }
        final cat = _categories[i - 1];
        return _chip(cat['name'], _selectedCategoryId == cat['id'],
          () => setState(() => _selectedCategoryId = cat['id']));
      }));

  Widget _chip(String label, bool selected, VoidCallback onTap) =>
    GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFE94560) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: selected ? [BoxShadow(
            color: const Color(0xFFE94560).withValues(alpha: 0.3),
            blurRadius: 8)] : []),
        child: Text(label, style: TextStyle(
          fontFamily: 'Poppins', fontSize: 12,
          fontWeight: FontWeight.w600,
          color: selected ? Colors.white : const Color(0xFF6B7280)))));
}

class _MenuCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final int cartQty;
  final VoidCallback onAdd;
  final VoidCallback onRemove;
  const _MenuCard({required this.item, required this.cartQty,
    required this.onAdd, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final price = (item['price'] as num).toDouble();
    final name = item['name'] as String;
    final desc = item['description'] as String? ?? '';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(
          color: Colors.black.withValues(alpha: 0.05),
          blurRadius: 8, offset: const Offset(0, 2))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          height: 100,
          decoration: const BoxDecoration(
            color: Color(0xFFF3F4F6),
            borderRadius: BorderRadius.vertical(top: Radius.circular(14))),
          child: item['image_url'] != null
            ? ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                child: Image.network(item['image_url'], fit: BoxFit.cover,
                  width: double.infinity))
            : Center(child: Text(
                _emoji(item['category_id']),
                style: const TextStyle(fontSize: 36)))),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: const TextStyle(
              fontFamily: 'Poppins', fontWeight: FontWeight.w700,
              fontSize: 12, color: Color(0xFF1A1A2E)),
              maxLines: 1, overflow: TextOverflow.ellipsis),
            if (desc.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(desc, style: const TextStyle(
                fontFamily: 'Poppins', fontSize: 10, color: Color(0xFF9CA3AF)),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
            const SizedBox(height: 6),
            Text('Rp ${_fmt(price)}',
              style: const TextStyle(
                fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                fontSize: 13, color: Color(0xFFE94560))),
          ])),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          child: cartQty == 0
            ? SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onAdd,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE94560),
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(30),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                    padding: EdgeInsets.zero),
                  child: const Text('+ Tambah',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                      fontWeight: FontWeight.w600))))
            : Row(children: [
                _iqBtn(Icons.remove, onRemove),
                Expanded(child: Text('$cartQty',
                  style: const TextStyle(fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700, fontSize: 13),
                  textAlign: TextAlign.center)),
                _iqBtn(Icons.add, onAdd),
              ])),
      ]));
  }

  Widget _iqBtn(IconData icon, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 28, height: 28,
      decoration: BoxDecoration(
        color: const Color(0xFFE94560),
        borderRadius: BorderRadius.circular(8)),
      child: Icon(icon, color: Colors.white, size: 14)));

  String _fmt(double v) {
    final s = v.toStringAsFixed(0);
    final buffer = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buffer.write('.');
      buffer.write(s[i]);
    }
    return buffer.toString();
  }

  String _emoji(String? catId) {
    if (catId == null) return '🍽️';
    const emojis = ['🍜', '🍛', '🥗', '🍲', '☕', '🧃', '🍰', '🥤'];
    return emojis[catId.hashCode.abs() % emojis.length];
  }
}