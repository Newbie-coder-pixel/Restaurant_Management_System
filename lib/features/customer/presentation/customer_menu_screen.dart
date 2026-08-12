import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/cart_provider.dart';
import '../../../core/theme/app_theme.dart';
import 'widgets/menu_item_detail_sheet.dart';

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
        ref
            .read(cartProvider.notifier)
            .setBranch(
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
          .where(
            (i) => (i['name'] as String).toLowerCase().contains(
              _search.toLowerCase(),
            ),
          )
          .toList();
    }
    return items;
  }

  void _addItem(Map<String, dynamic> item) {
    ref
        .read(cartProvider.notifier)
        .addItem(
          CartItem(
            menuItemId: item['id'],
            name: item['name'],
            price: (item['price'] as num).toDouble(),
            imageUrl: item['image_url'],
          ),
        );
  }

  void _removeItem(Map<String, dynamic> item, int currentQty) {
    ref.read(cartProvider.notifier).updateQuantity(item['id'], currentQty - 1);
  }

  void _openDetail(Map<String, dynamic> item) {
    MenuItemDetailSheet.show(
      context,
      item: item,
      onAddToCart: (cartItem) =>
          ref.read(cartProvider.notifier).addItem(cartItem),
    );
  }

  int _qtyOf(CartState cart, dynamic itemId) => cart.items
      .where((c) => c.menuItemId == itemId)
      .fold(0, (s, c) => s + c.quantity);

  String _categorySectionTitle() {
    if (_selectedCategoryId == null) return 'Full Menu';
    final match = _categories
        .where((c) => c['id'] == _selectedCategoryId)
        .toList();
    final name = match.isNotEmpty ? match.first['name'] as String? : null;
    return '${name ?? 'Menu'} Selection';
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final featured = _search.isEmpty && _menuItems.isNotEmpty
        ? _menuItems.first
        : null;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            SliverToBoxAdapter(child: _buildTopNav(cart)),
            SliverToBoxAdapter(child: _buildBranchBar()),
            SliverToBoxAdapter(child: _buildSearchBar()),
            SliverToBoxAdapter(child: _buildCategoryTabs()),
            if (featured != null)
              SliverToBoxAdapter(child: _buildFeatured(featured, cart)),
            if (!_loading && _filteredItems.isNotEmpty)
              SliverToBoxAdapter(child: _buildSectionHeader()),
            _loading
                ? const SliverFillRemaining(
                    child: Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                      ),
                    ),
                  )
                : _filteredItems.isEmpty
                ? const SliverFillRemaining(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.restaurant_menu_outlined,
                            size: 80,
                            color: AppColors.border,
                          ),
                          SizedBox(height: 16),
                          Text(
                            'No menu items found',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 16,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Try a different keyword or choose another category',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 13,
                              color: AppColors.textHint,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                    sliver: SliverGrid(
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 220,
                            childAspectRatio: 0.72,
                            crossAxisSpacing: 16,
                            mainAxisSpacing: 20,
                          ),
                      delegate: SliverChildBuilderDelegate((_, i) {
                        final item = _filteredItems[i];
                        final qty = _qtyOf(cart, item['id']);
                        return _MenuCard(
                          item: item,
                          cartQty: qty,
                          onAdd: () => _addItem(item),
                          onRemove: () => _removeItem(item, qty),
                          onTapCard: () => _openDetail(item),
                        );
                      }, childCount: _filteredItems.length),
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  // ── TOP NAV ──────────────────────────────────────────────────
  Widget _buildTopNav(CartState cart) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 1)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          GestureDetector(
            onTap: () =>
                context.canPop() ? context.pop() : context.go('/customer'),
            child: const Text(
              'Restaurant',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(width: 28),
          Expanded(
            child: Row(
              children: [
                _NavLink(
                  label: 'Menu',
                  active: true,
                  onTap: () => _scrollController.animateTo(
                    0,
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeInOutCubic,
                  ),
                ),
                const SizedBox(width: 24),
                _NavLink(
                  label: 'Locations',
                  onTap: () => context.go('/customer'),
                ),
                const SizedBox(width: 24),
                _NavLink(
                  label: 'Reservations',
                  onTap: () => context.go('/customer?tab=1'),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: cart.isEmpty ? null : () => context.go('/customer/checkout'),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(
                  Icons.shopping_cart_outlined,
                  color: AppColors.textPrimary,
                  size: 24,
                ),
                if (!cart.isEmpty)
                  Positioned(
                    right: -6,
                    top: -6,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      constraints: const BoxConstraints(
                        minWidth: 16,
                        minHeight: 16,
                      ),
                      decoration: const BoxDecoration(
                        color: AppColors.accent,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${cart.itemCount}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Shown once the branch resolves — since "Menu" on the landing page now
  // auto-picks a branch instead of asking, customers need to see (and be
  // able to change) which branch they're actually ordering from.
  Widget _buildBranchBar() {
    if (_branchName.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          const Icon(Icons.storefront_outlined,
              size: 15, color: AppColors.textHint),
          const SizedBox(width: 6),
          Expanded(
            child: Text('Ordering from $_branchName',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12.5,
                    color: AppColors.textSecondary)),
          ),
          GestureDetector(
            onTap: () => context.go('/customer'),
            child: const Text('Change',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
    child: TextField(
      onChanged: (v) => setState(() => _search = v),
      decoration: InputDecoration(
        hintText: 'Search for your favorite menu...',
        hintStyle: const TextStyle(
          fontFamily: 'Poppins',
          fontSize: 13,
          color: AppColors.textHint,
        ),
        prefixIcon: const Icon(
          Icons.search_rounded,
          color: AppColors.textHint,
          size: 18,
        ),
        suffixIcon: _search.isNotEmpty
            ? IconButton(
                icon: const Icon(
                  Icons.clear,
                  size: 16,
                  color: AppColors.textHint,
                ),
                onPressed: () => setState(() => _search = ''),
              )
            : null,
        isDense: true,
        filled: true,
        fillColor: AppColors.surfaceVariant,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
      ),
      style: const TextStyle(
        fontFamily: 'Poppins',
        fontSize: 13,
        color: AppColors.textPrimary,
      ),
    ),
  );

  Widget _buildCategoryTabs() => SizedBox(
    height: 48,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      itemCount: _categories.length + 1,
      separatorBuilder: (_, __) => const SizedBox(width: 22),
      itemBuilder: (_, i) {
        if (i == 0) {
          return _NavLink(
            label: 'All Menu',
            active: _selectedCategoryId == null,
            onTap: () => setState(() => _selectedCategoryId = null),
          );
        }
        final cat = _categories[i - 1];
        return _NavLink(
          label: cat['name'] as String,
          active: _selectedCategoryId == cat['id'],
          onTap: () => setState(() => _selectedCategoryId = cat['id']),
        );
      },
    ),
  );

  // ── FEATURED ─────────────────────────────────────────────────
  Widget _buildFeatured(Map<String, dynamic> item, CartState cart) {
    final price = (item['price'] as num).toDouble();
    final name = item['name'] as String;
    final desc = item['description'] as String? ?? '';
    final qty = _qtyOf(cart, item['id']);

    Widget placeholder() => Container(
      color: AppColors.surfaceVariant,
      alignment: Alignment.center,
      child: Text(
        _emojiFor(item['category_id']),
        style: const TextStyle(fontSize: 48),
      ),
    );

    final image = GestureDetector(
      onTap: () => _openDetail(item),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: AspectRatio(
          aspectRatio: 1.5,
          child: item['image_url'] != null
              ? Image.network(
                  item['image_url'],
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => placeholder(),
                )
              : placeholder(),
        ),
      ),
    );

    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.badgeDark,
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Text(
            'DISH OF THE MONTH',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: 0.5,
            ),
          ),
        ),
        const SizedBox(height: 14),
        GestureDetector(
          onTap: () => _openDetail(item),
          child: Text(
            name,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        if (desc.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            desc,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              color: AppColors.textSecondary,
              height: 1.6,
            ),
          ),
        ],
        const SizedBox(height: 18),
        Row(
          children: [
            Text(
              'Rp${_fmtPrice(price)}',
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const Spacer(),
            if (qty == 0)
              ElevatedButton.icon(
                onPressed: () => _addItem(item),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add to Basket'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  textStyle: const TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                  elevation: 0,
                ),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _iconStepBtn(Icons.remove, () => _removeItem(item, qty)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Text(
                        '$qty',
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    _iconStepBtn(Icons.add, () => _addItem(item)),
                  ],
                ),
              ),
          ],
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 640;
          final content = isWide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(flex: 5, child: image),
                    const SizedBox(width: 28),
                    Expanded(flex: 5, child: details),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [image, const SizedBox(height: 16), details],
                );
          return Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(16),
            ),
            child: content,
          );
        },
      ),
    );
  }

  Widget _iconStepBtn(IconData icon, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.all(8),
      child: Icon(icon, color: Colors.white, size: 16),
    ),
  );

  Widget _buildSectionHeader() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          _categorySectionTitle(),
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        Row(
          children: List.generate(
            3,
            (i) => Container(
              margin: const EdgeInsets.only(left: 4),
              width: 5,
              height: 5,
              decoration: const BoxDecoration(
                color: AppColors.textHint,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ],
    ),
  );

  String _fmtPrice(double v) {
    final s = v.toStringAsFixed(0);
    final buffer = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buffer.write('.');
      buffer.write(s[i]);
    }
    return buffer.toString();
  }

  String _emojiFor(String? catId) {
    if (catId == null) return '🍽️';
    const emojis = ['🍜', '🍛', '🥗', '🍲', '☕', '🧃', '🍰', '🥤'];
    return emojis[catId.hashCode.abs() % emojis.length];
  }
}

// ── Top nav / category text link ─────────────────────────────────
class _NavLink extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _NavLink({
    required this.label,
    this.active = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.only(bottom: 4),
        decoration: active
            ? const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: AppColors.primary, width: 2),
                ),
              )
            : null,
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 14,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            color: active ? AppColors.primary : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

// ── Menu Card ─────────────────────────────────────────────────────
class _MenuCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final int cartQty;
  final VoidCallback onAdd;
  final VoidCallback onRemove;
  final VoidCallback onTapCard;
  const _MenuCard({
    required this.item,
    required this.cartQty,
    required this.onAdd,
    required this.onRemove,
    required this.onTapCard,
  });

  @override
  Widget build(BuildContext context) {
    final price = (item['price'] as num).toDouble();
    final name = item['name'] as String;
    final desc = item['description'] as String? ?? '';

    return GestureDetector(
      onTap: onTapCard,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: cartQty > 0 ? AppColors.accent : AppColors.border,
            width: cartQty > 0 ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 120,
              decoration: const BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.vertical(top: Radius.circular(11)),
              ),
              clipBehavior: Clip.antiAlias,
              child: item['image_url'] != null
                  ? Image.network(
                      item['image_url'],
                      fit: BoxFit.cover,
                      width: double.infinity,
                      errorBuilder: (_, __, ___) => _buildPlaceholder(),
                    )
                  : _buildPlaceholder(),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: AppColors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Rp${_fmt(price)}',
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                    if (desc.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        desc,
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 11,
                          color: AppColors.textSecondary,
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const Spacer(),
                    const SizedBox(height: 8),
                    cartQty == 0
                        ? SizedBox(
                            width: double.infinity,
                            child: GestureDetector(
                              onTap: onAdd,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 9,
                                ),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: AppColors.accent,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  'Add',
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                          )
                        : Container(
                            decoration: BoxDecoration(
                              color: AppColors.accent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                _iqBtn(Icons.remove, onRemove),
                                Expanded(
                                  child: Text(
                                    '$cartQty',
                                    style: const TextStyle(
                                      fontFamily: 'Poppins',
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                      color: Colors.white,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                _iqBtn(Icons.add, onAdd),
                              ],
                            ),
                          ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            _emoji(item['category_id']),
            style: const TextStyle(fontSize: 32),
          ),
          const SizedBox(height: 4),
          Text(
            _getCategoryName(item['category_id']),
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 10,
              color: AppColors.textHint,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  String _getCategoryName(String? catId) {
    if (catId == null) return 'Menu';
    const names = [
      'Food',
      'Rice',
      'Vegetables',
      'Soup',
      'Drinks',
      'Snacks',
      'Dessert',
      'Juice',
    ];
    return names[catId.hashCode.abs() % names.length];
  }

  Widget _iqBtn(IconData icon, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 10),
      child: Icon(icon, color: Colors.white, size: 15),
    ),
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

  String _emoji(String? catId) {
    if (catId == null) return '🍽️';
    const emojis = ['🍜', '🍛', '🥗', '🍲', '☕', '🧃', '🍰', '🥤'];
    return emojis[catId.hashCode.abs() % emojis.length];
  }
}
