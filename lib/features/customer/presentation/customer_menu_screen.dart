import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/cart_provider.dart';
import '../../../core/theme/app_theme.dart';

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
  String _branchName = ''; // ✅ ADDED: store the branch name
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _load();

    // ✅ FIX: setBranch is called when the screen opens, not when an item is added
    // Use addPostFrameCallback so ref.read is safe to call after the first build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(cartProvider.notifier).setBranch(
          widget.branchId,
          _branchName, // will be updated after _load() completes
        );
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      // ✅ FIX: fetch the branch name at the same time
      final branchRes = await Supabase.instance.client
          .from('branches')
          .select('name')
          .eq('id', widget.branchId)
          .single();

      final cats = await Supabase.instance.client
          .from('menu_categories')
          .select()
          .eq('branch_id', widget.branchId)
          .eq('is_active', true)
          .order('sort_order');

      final items = await Supabase.instance.client
          .from('menu_items')
          .select()
          .eq('branch_id', widget.branchId)
          .eq('is_available', true)
          .order('name');

      if (mounted) {
        final name = branchRes['name'] as String? ?? '';
        setState(() {
          _branchName = name;
          _categories = (cats as List).cast();
          _menuItems = (items as List).cast();
          _loading = false;
        });

        // ✅ Update setBranch with the fetched name
        ref.read(cartProvider.notifier).setBranch(widget.branchId, name);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filteredItems {
    var items = _menuItems;
    if (_selectedCategoryId != null) {
      items = items
          .where((i) => i['category_id'] == _selectedCategoryId)
          .toList();
    }
    if (_search.isNotEmpty) {
      items = items
          .where((i) => (i['name'] as String)
              .toLowerCase()
              .contains(_search.toLowerCase()))
          .toList();
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
                  child: Center(
                      child: CircularProgressIndicator(
                          color: AppColors.accent)))
              : _filteredItems.isEmpty
                  ? SliverFillRemaining(
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.restaurant_menu_outlined,
                                size: 80, color: Colors.grey.shade300),
                            const SizedBox(height: 16),
                            Text('No menu items found',
                                style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 16,
                                    color: Colors.grey.shade600,
                                    fontWeight: FontWeight.w500)),
                            const SizedBox(height: 8),
                            Text(
                                'Try a different keyword or choose another category',
                                style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 13,
                                    color: Colors.grey.shade400)),
                          ],
                        ),
                      ))
                  : SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                          16, 8, 16, cart.isEmpty ? 100 : 140),
                      sliver: SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 180,
                                childAspectRatio: 0.68,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 16),
                        delegate: SliverChildBuilderDelegate(
                          (_, i) {
                            final item = _filteredItems[i];
                            final qty = cart.items
                                .where((c) => c.menuItemId == item['id'])
                                .fold(0, (s, c) => s + c.quantity);
                            return _MenuCard(
                              item: item,
                              cartQty: qty,
                              onAdd: () {
                                // ✅ setBranch was already called in initState,
                                // no need to call it again here
                                ref.read(cartProvider.notifier).addItem(
                                    CartItem(
                                      menuItemId: item['id'],
                                      name: item['name'],
                                      price:
                                          (item['price'] as num).toDouble(),
                                      imageUrl: item['image_url'],
                                    ));
                              },
                              onRemove: () {
                                final currentQty = cart.items
                                    .where((c) => c.menuItemId == item['id'])
                                    .fold(0, (s, c) => s + c.quantity);
                                ref
                                    .read(cartProvider.notifier)
                                    .updateQuantity(
                                        item['id'], currentQty - 1);
                              },
                            );
                          },
                          childCount: _filteredItems.length,
                        ),
                      ),
                    ),
        ],
      ),
      floatingActionButton: cart.isEmpty
          ? null
          : _CartFab(
              cart: cart,
              onCheckout: () => context.go('/customer/checkout'),
            ),
    );
  }

  Widget _buildSliverHeader() => SliverAppBar(
        expandedHeight: 120,
        pinned: true,
        floating: true,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        flexibleSpace: FlexibleSpaceBar(
          // ✅ Show the branch name in the header
          title: Text(
            _branchName.isNotEmpty ? _branchName : 'Restaurant Menu',
            style: const TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w600,
                fontSize: 18),
          ),
          centerTitle: true,
          background: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.primary,
                    AppColors.primaryLight,
                    AppColors.primaryLight
                  ]),
            ),
          ),
        ),
        leading: IconButton(
          icon:
              const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/customer?tab=0'),
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
              tooltip: 'Book a table',
              onPressed: () =>
                  context.push('/customer/booking/${widget.branchId}'),
            ),
          ),
        ],
      );

  Widget _buildSearchBar() => Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: TextField(
          onChanged: (v) => setState(() => _search = v),
          decoration: InputDecoration(
            hintText: 'Search for your favorite menu...',
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
                borderSide:
                    const BorderSide(color: AppColors.accent, width: 2)),
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
              return _chip('All Menu', _selectedCategoryId == null,
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              decoration: BoxDecoration(
                color: selected ? AppColors.accent : Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                    color: selected
                        ? Colors.transparent
                        : const Color(0xFFE5E7EB),
                    width: 1.5),
                boxShadow: selected
                    ? [
                        BoxShadow(
                            color: AppColors.accent
                                .withValues(alpha: 0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 2))
                      ]
                    : const [],
              ),
              child: Text(label,
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: selected
                          ? Colors.white
                          : const Color(0xFF4B5563)))));
}

// ── Cart FAB ──────────────────────────────────────────────────────
class _CartFab extends StatelessWidget {
  final CartState cart;
  final VoidCallback onCheckout;
  const _CartFab({required this.cart, required this.onCheckout});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onCheckout,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                  color:
                      AppColors.primary.withValues(alpha: 0.35),
                  blurRadius: 12,
                  offset: const Offset(0, 4))
            ]),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Stack(children: [
            const Icon(Icons.shopping_cart_outlined,
                color: Colors.white, size: 22),
            Positioned(
              top: -2,
              right: -2,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                    color: AppColors.accent, shape: BoxShape.circle),
                constraints: const BoxConstraints(
                    minWidth: 14, minHeight: 14),
                child: Text('${cart.itemCount}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold)),
              ),
            ),
          ]),
          const SizedBox(width: 10),
          const Text('Cart',
              style: TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14)),
          const SizedBox(width: 8),
          Container(
              width: 1,
              height: 16,
              color: Colors.white.withValues(alpha: 0.4)),
          const SizedBox(width: 8),
          Text(_fmt(cart.total),
              style: const TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14)),
        ]),
      ),
    );
  }

  String _fmt(double v) {
    final s = v.toStringAsFixed(0);
    final buffer = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buffer.write('.');
      buffer.write(s[i]);
    }
    return 'Rp $buffer';
  }
}

// ── Menu Card ─────────────────────────────────────────────────────
class _MenuCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final int cartQty;
  final VoidCallback onAdd;
  final VoidCallback onRemove;
  const _MenuCard(
      {required this.item,
      required this.cartQty,
      required this.onAdd,
      required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final price = (item['price'] as num).toDouble();
    final name = item['name'] as String;
    final desc = item['description'] as String? ?? '';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: cartQty > 0
              ? AppColors.accent
              : const Color(0xFFE5E7EB),
          width: cartQty > 0 ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
              color: cartQty > 0
                  ? AppColors.accent.withValues(alpha: 0.12)
                  : Colors.black.withValues(alpha: 0.06),
              blurRadius: cartQty > 0 ? 14 : 12,
              offset: const Offset(0, 4)),
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
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: item['image_url'] != null
                    ? ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(20)),
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
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(10),
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
                        color: AppColors.primary),
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
                              color: AppColors.accent)),
                    ),
                    if (cartQty == 0)
                      GestureDetector(
                        onTap: onAdd,
                        child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: AppColors.accent,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.add,
                                color: Colors.white, size: 18)),
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
                              color: AppColors.primary),
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
    const names = [
      'Food', 'Rice', 'Vegetables', 'Soup',
      'Drinks', 'Snacks', 'Dessert', 'Juice'
    ];
    return names[catId.hashCode.abs() % names.length];
  }

  Widget _iqBtn(IconData icon, VoidCallback onTap) => GestureDetector(
      onTap: onTap,
      child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: AppColors.accent,
            borderRadius: BorderRadius.circular(10),
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