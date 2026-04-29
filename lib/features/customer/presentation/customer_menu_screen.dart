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
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
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
      backgroundColor: const Color(0xFFF8F9FA),
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          _buildSliverHeader(),
          SliverToBoxAdapter(
            child: Column(
              children: [
                _buildSearchBar(),
                _buildCategoryChips(),
              ],
            ),
          ),
          _loading
              ? const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator(color: Color(0xFFE94560))))
              : _filteredItems.isEmpty
                  ? SliverFillRemaining(
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.restaurant_menu_outlined, 
                              size: 80, color: Colors.grey.shade300),
                            const SizedBox(height: 16),
                            Text('Tidak ada menu ditemukan',
                              style: TextStyle(
                                fontFamily: 'Poppins', 
                                fontSize: 16,
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.w500)),
                            const SizedBox(height: 8),
                            Text('Coba kata kunci lain atau pilih kategori berbeda',
                              style: TextStyle(
                                fontFamily: 'Poppins', 
                                fontSize: 13,
                                color: Colors.grey.shade400)),
                          ],
                        ),
                      ))
                  : SliverPadding(
                      padding: EdgeInsets.fromLTRB(16, 8, 16, 
                        cart.isEmpty ? 100 : 120),
                      sliver: SliverGrid(
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 180,
                          childAspectRatio: 0.68,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 16),
                        delegate: SliverChildBuilderDelegate(
                          (_, i) => _MenuCard(
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
                          ),
                          childCount: _filteredItems.length,
                        ),
                      ),
                    ),
        ],
      ),
      bottomNavigationBar: CartBottomBar(
        cart: cart,
        show: !cart.isEmpty,
        onCheckout: () => context.go('/customer/checkout')),
    );
  }

  Widget _buildSliverHeader() => SliverAppBar(
    expandedHeight: 120,
    pinned: true,
    floating: true,
    backgroundColor: const Color(0xFF1A1A2E),
    foregroundColor: Colors.white,
    elevation: 0,
    flexibleSpace: FlexibleSpaceBar(
      title: const Text('Menu Restoran',
        style: TextStyle(
          fontFamily: 'Poppins',
          fontWeight: FontWeight.w600,
          fontSize: 18)),
      centerTitle: true,
      background: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1A1A2E), Color(0xFF0F3460), Color(0xFF16213E)])),
      ),
    ),
    leading: IconButton(
      icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
      onPressed: () => context.go('/customer'),
    ),
    actions: [
      Container(
        margin: const EdgeInsets.only(right: 12),
        child: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.calendar_today_outlined, 
              color: Colors.white, size: 18)),
          tooltip: 'Booking meja',
          onPressed: () => context.push('/customer/booking/${widget.branchId}'),
        ),
      ),
    ],
  );

  Widget _buildSearchBar() => Container(
    margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
    child: TextField(
      onChanged: (v) => setState(() => _search = v),
      decoration: InputDecoration(
        hintText: 'Cari menu favoritmu...',
        hintStyle: const TextStyle(
          fontFamily: 'Poppins', 
          fontSize: 14,
          color: Color(0xFF9CA3AF)),
        prefixIcon: const Icon(Icons.search_rounded, 
          color: Color(0xFF9CA3AF), size: 20),
        suffixIcon: _search.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear, size: 18),
                onPressed: () => setState(() => _search = ''),
              )
            : null,
        filled: true, 
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFE94560), width: 2)),
        contentPadding: const EdgeInsets.symmetric(vertical: 14)),
      style: const TextStyle(fontFamily: 'Poppins', fontSize: 14)));

  Widget _buildCategoryChips() => SizedBox(
    height: 56,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      itemCount: _categories.length + 1,
      separatorBuilder: (_, __) => const SizedBox(width: 10),
      itemBuilder: (_, i) {
        if (i == 0) {
          return _chip('Semua Menu', _selectedCategoryId == null,
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
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFE94560) : Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: selected ? Colors.transparent : const Color(0xFFE5E7EB),
            width: 1.5),
          boxShadow: selected ? [
            BoxShadow(
              color: const Color(0xFFE94560).withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 2))
          ] : const [],
        ),
        child: Text(label, 
          style: TextStyle(
            fontFamily: 'Poppins', 
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : const Color(0xFF4B5563))),
      ));
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
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 4)),
            if (cartQty > 0)
              BoxShadow(
                color: const Color(0xFFE94560).withValues(alpha: 0.15),
                blurRadius: 14,
                offset: const Offset(0, 3)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Container(
                  height: 120,
                  decoration: const BoxDecoration(
                    color: Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  child: item['image_url'] != null
                    ? ClipRRect(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                        child: Image.network(
                          item['image_url'], 
                          fit: BoxFit.cover,
                          width: double.infinity,
                          errorBuilder: (_, __, ___) => _buildPlaceholder(),
                        ))
                    : _buildPlaceholder(),
                ),
                if (cartQty > 0)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE94560),
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 4,
                          )
                        ],
                      ),
                      child: Text('$cartQty',
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, 
                    style: const TextStyle(
                      fontFamily: 'Poppins', 
                      fontWeight: FontWeight.w700,
                      fontSize: 13, 
                      color: Color(0xFF1A1A2E)),
                    maxLines: 1, 
                    overflow: TextOverflow.ellipsis),
                  if (desc.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(desc, 
                      style: const TextStyle(
                        fontFamily: 'Poppins', 
                        fontSize: 10, 
                        color: Color(0xFF9CA3AF)),
                      maxLines: 1, 
                      overflow: TextOverflow.ellipsis),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text('Rp${_fmt(price)}',
                          style: const TextStyle(
                            fontFamily: 'Poppins', 
                            fontWeight: FontWeight.w800,
                            fontSize: 14, 
                            color: Color(0xFFE94560))),
                      ),
                      if (cartQty == 0)
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: onAdd,
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE94560),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.add, 
                                color: Colors.white, size: 18)),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (cartQty > 0) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Row(
                  children: [
                    _iqBtn(Icons.remove, onRemove),
                    Expanded(
                      child: Text('$cartQty',
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w700, 
                          fontSize: 14,
                          color: Color(0xFF1A1A2E)),
                        textAlign: TextAlign.center)),
                    _iqBtn(Icons.add, onAdd),
                  ],
                ),
              ),
            ] else
              const SizedBox(height: 12),
          ],
        ),
    );
  }

  Widget _buildPlaceholder() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(_emoji(item['category_id']),
            style: const TextStyle(fontSize: 32)),
          const SizedBox(height: 4),
          Text(_getCategoryName(item['category_id']),
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 10,
              color: Color(0xFF9CA3AF)),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  String _getCategoryName(String? catId) {
    if (catId == null) return 'Menu';
    const names = ['Makanan', 'Nasi', 'Sayur', 'Sup', 'Minuman', 'Camilan', 'Dessert', 'Jus'];
    return names[catId.hashCode.abs() % names.length];
  }

  Widget _iqBtn(IconData icon, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 32, 
      height: 32,
      decoration: BoxDecoration(
        color: const Color(0xFFE94560),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFE94560).withValues(alpha: 0.3),
            blurRadius: 4,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: Icon(icon, color: Colors.white, size: 16)));

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