import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/qr_cart_provider.dart';
import '../data/qr_order_repository.dart';

// ─── Local Providers ──────────────────────────────────────────────────────────

final _menuDataProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>(
  (ref, branchId) async {
    final repo = ref.read(qrOrderRepositoryProvider);
    return repo.fetchMenuByBranch(branchId);
  },
);

final _tableInfoProvider =
    FutureProvider.family<Map<String, dynamic>?, String>((ref, tableId) async {
  final repo = ref.read(qrOrderRepositoryProvider);
  return repo.fetchTableInfo(tableId);
});

final _selectedCategoryProvider = StateProvider<String?>((ref) => null);
final _searchQueryProvider = StateProvider<String>((ref) => '');

// ─── Main Screen ──────────────────────────────────────────────────────────────

class QrMenuScreen extends ConsumerStatefulWidget {
  final String tableId;
  const QrMenuScreen({super.key, required this.tableId});

  @override
  ConsumerState<QrMenuScreen> createState() => _QrMenuScreenState();
}

class _QrMenuScreenState extends ConsumerState<QrMenuScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fabAnimCtrl;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fabAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }

  @override
  void dispose() {
    _fabAnimCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  List<MenuItem> _parseItems(List<Map<String, dynamic>> rows) {
    return rows.map((row) {
      final cat = row['menu_categories'] as Map<String, dynamic>?;
      return MenuItem(
        id: row['id'] as String,
        name: row['name'] as String,
        description: row['description'] as String? ?? '',
        price: (row['price'] as num).toDouble(),
        categoryId: row['category_id'] as String? ?? '',
        categoryName: cat?['name'] as String? ?? 'Lainnya',
        imageUrl: row['image_url'] as String?,
        isAvailable: row['is_available'] as bool? ?? true,
        sortOrder: row['sort_order'] as int? ?? 0,
      );
    }).toList();
  }

  Map<String, List<MenuItem>> _groupByCategory(List<MenuItem> items) {
    final map = <String, List<MenuItem>>{};
    for (final item in items) {
      map.putIfAbsent(item.categoryName, () => []).add(item);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final tableInfo = ref.watch(_tableInfoProvider(widget.tableId));
    final theme = Theme.of(context);

    return tableInfo.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            Text('Meja tidak ditemukan', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('Coba scan ulang QR code', style: theme.textTheme.bodySmall),
          ]),
        ),
      ),
      data: (tableData) {
        if (tableData == null) {
          return Scaffold(
            body: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.table_restaurant_outlined,
                    size: 64, color: Colors.orange),
                const SizedBox(height: 16),
                Text('Meja tidak tersedia', style: theme.textTheme.titleLarge),
              ]),
            ),
          );
        }

        final branch = tableData['branches'] as Map<String, dynamic>?;
        final branchId = branch?['id'] as String? ?? '';
        final branchName = branch?['name'] as String? ?? 'Restoran';
        final tableName = (tableData['table_number'] as String?) ?? 'Meja';

        WidgetsBinding.instance.addPostFrameCallback((_) {
          ref.read(activeQrTableProvider.notifier).state =
              (tableId: widget.tableId, tableName: tableName);
        });

        return _MenuBody(
          tableId: widget.tableId,
          tableName: tableName,
          branchId: branchId,
          branchName: branchName,
          parseItems: _parseItems,
          groupByCategory: _groupByCategory,
          fabAnimCtrl: _fabAnimCtrl,
          searchCtrl: _searchCtrl,
        );
      },
    );
  }
}

// ─── Menu Body ────────────────────────────────────────────────────────────────

class _MenuBody extends ConsumerWidget {
  final String tableId;
  final String tableName;
  final String branchId;
  final String branchName;
  final List<MenuItem> Function(List<Map<String, dynamic>>) parseItems;
  final Map<String, List<MenuItem>> Function(List<MenuItem>) groupByCategory;
  final AnimationController fabAnimCtrl;
  final TextEditingController searchCtrl;

  const _MenuBody({
    required this.tableId,
    required this.tableName,
    required this.branchId,
    required this.branchName,
    required this.parseItems,
    required this.groupByCategory,
    required this.fabAnimCtrl,
    required this.searchCtrl,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final menuAsync = ref.watch(_menuDataProvider(branchId));
    final selectedCategory = ref.watch(_selectedCategoryProvider);
    final searchQuery = ref.watch(_searchQueryProvider);
    final cart = ref.watch(activeQrCartProvider);

    if (cart.totalItems > 0) {
      fabAnimCtrl.forward();
    } else {
      fabAnimCtrl.reverse();
    }

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Column(children: [
        _QrMenuHeader(
          tableName: tableName,
          branchName: branchName,
          searchCtrl: searchCtrl,
          onSearchChanged: (q) =>
              ref.read(_searchQueryProvider.notifier).state = q,
        ),
        Expanded(
          child: menuAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.wifi_off_outlined, size: 48),
                const SizedBox(height: 12),
                const Text('Gagal memuat menu'),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: () => ref.invalidate(_menuDataProvider(branchId)),
                  child: const Text('Coba Lagi'),
                ),
              ]),
            ),
            data: (rawItems) {
              final allItems = parseItems(rawItems);
              final grouped = groupByCategory(allItems);
              final categories = grouped.keys.toList();

              // Filter items berdasarkan kategori + search
              List<MenuItem> displayItems;
              if (selectedCategory == null) {
                displayItems = allItems;
              } else {
                displayItems =
                    grouped[selectedCategory] ?? [];
              }

              if (searchQuery.isNotEmpty) {
                displayItems = displayItems.where((item) {
                  return item.name
                          .toLowerCase()
                          .contains(searchQuery.toLowerCase()) ||
                      item.description
                          .toLowerCase()
                          .contains(searchQuery.toLowerCase());
                }).toList();
              }

              return Row(children: [
                // ── Category Sidebar ────────────────────────────────────
                _CategorySidebar(
                  categories: categories,
                  selected: selectedCategory,
                  onSelect: (cat) {
                    ref.read(_selectedCategoryProvider.notifier).state =
                        cat == selectedCategory ? null : cat;
                  },
                ),

                // ── Menu Grid ───────────────────────────────────────────
                Expanded(
                  child: displayItems.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.search_off,
                                  size: 48, color: Colors.grey),
                              SizedBox(height: 12),
                              Text('Menu tidak ditemukan'),
                            ],
                          ),
                        )
                      : _MenuGrid(
                          items: displayItems,
                          tableId: tableId,
                          tableName: tableName,
                        ),
                ),
              ]);
            },
          ),
        ),
      ]),
      floatingActionButton: cart.isEmpty
          ? null
          : ScaleTransition(
              scale:
                  CurvedAnimation(parent: fabAnimCtrl, curve: Curves.elasticOut),
              child: _CartFab(
                  cart: cart, tableId: tableId, tableName: tableName),
            ),
    );
  }
}

// ─── Header ───────────────────────────────────────────────────────────────────

class _QrMenuHeader extends StatelessWidget {
  final String tableName;
  final String branchName;
  final TextEditingController searchCtrl;
  final ValueChanged<String> onSearchChanged;

  const _QrMenuHeader({
    required this.tableName,
    required this.branchName,
    required this.searchCtrl,
    required this.onSearchChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.primary,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.restaurant, color: colorScheme.onPrimary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(branchName,
                    style: theme.textTheme.labelLarge?.copyWith(
                        color: colorScheme.onPrimary.withValues(alpha: 0.85)),
                    overflow: TextOverflow.ellipsis),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: colorScheme.onPrimary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.table_restaurant,
                      size: 14, color: colorScheme.onPrimary),
                  const SizedBox(width: 4),
                  Text(tableName,
                      style: theme.textTheme.labelMedium?.copyWith(
                          color: colorScheme.onPrimary,
                          fontWeight: FontWeight.bold)),
                ]),
              ),
            ]),
            const SizedBox(height: 8),
            Text('Pilih menu favoritmu',
                style: theme.textTheme.headlineSmall?.copyWith(
                    color: colorScheme.onPrimary,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 14),
            TextField(
              controller: searchCtrl,
              onChanged: onSearchChanged,
              style: theme.textTheme.bodyMedium,
              decoration: InputDecoration(
                hintText: 'Cari makanan atau minuman...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          searchCtrl.clear();
                          onSearchChanged('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: colorScheme.surface,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
                isDense: true,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ─── Category Sidebar ─────────────────────────────────────────────────────────

class _CategorySidebar extends StatelessWidget {
  final List<String> categories;
  final String? selected;
  final ValueChanged<String> onSelect;

  const _CategorySidebar({
    required this.categories,
    required this.selected,
    required this.onSelect,
  });

  static const _categoryIcons = <String, IconData>{
    'Makanan': Icons.rice_bowl_outlined,
    'Minuman': Icons.local_drink_outlined,
    'Snack': Icons.cookie_outlined,
    'Dessert': Icons.cake_outlined,
    'Paket': Icons.lunch_dining_outlined,
    'Promo': Icons.local_offer_outlined,
    'Lainnya': Icons.more_horiz,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Item "Semua" + semua kategori
    final allItems = ['Semua', ...categories];

    return Container(
      width: 72,
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: allItems.length,
        separatorBuilder: (_, __) => const SizedBox(height: 2),
        itemBuilder: (context, index) {
          final label = allItems[index];
          final isSemua = label == 'Semua';
          final isSelected =
              isSemua ? selected == null : selected == label;
          final icon = isSemua
              ? Icons.grid_view_rounded
              : (_categoryIcons[label] ?? Icons.fastfood_outlined);

          return GestureDetector(
            onTap: () {
              if (isSemua) {
                // Reset ke semua
                onSelect(selected ?? '');
                if (selected != null) onSelect(selected!);
              } else {
                onSelect(label);
              }
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 6),
              padding:
                  const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              decoration: BoxDecoration(
                color: isSelected ? colorScheme.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon,
                    size: 22,
                    color: isSelected
                        ? colorScheme.onPrimary
                        : colorScheme.onSurfaceVariant),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: isSelected
                        ? colorScheme.onPrimary
                        : colorScheme.onSurfaceVariant,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ]),
            ),
          );
        },
      ),
    );
  }
}

// ─── Menu Grid ────────────────────────────────────────────────────────────────

class _MenuGrid extends ConsumerWidget {
  final List<MenuItem> items;
  final String tableId;
  final String tableName;

  const _MenuGrid({
    required this.items,
    required this.tableId,
    required this.tableName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(activeQrCartProvider);
    final notifier = ref.read(activeQrCartNotifierProvider);

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.75,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final qty = cart.items
            .where((i) => i.menuItem.id == item.id)
            .fold(0, (s, i) => s + i.quantity);

        return _MenuItemCard(
          item: item,
          quantity: qty,
          onAdd: () => notifier.addItem(item),
          onRemove: () => notifier.removeItem(item.id),
        );
      },
    );
  }
}

// ─── Menu Item Card ───────────────────────────────────────────────────────────

class _MenuItemCard extends StatelessWidget {
  final MenuItem item;
  final int quantity;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  const _MenuItemCard({
    required this.item,
    required this.quantity,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: quantity > 0
              ? colorScheme.primary
              : colorScheme.outlineVariant,
          width: quantity > 0 ? 1.5 : 0.8,
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Gambar AspectRatio 16:9 supaya proporsional di semua ukuran ──
        AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(fit: StackFit.expand, children: [
            item.imageUrl != null && item.imageUrl!.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: item.imageUrl!,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(
                      color: colorScheme.surfaceContainerHighest,
                      child: const Center(
                          child: Icon(Icons.image_outlined, color: Colors.grey)),
                    ),
                    errorWidget: (_, __, ___) => _placeholder(colorScheme),
                  )
                : _placeholder(colorScheme),
            if (!item.isAvailable)
              Container(
                color: Colors.black54,
                child: const Center(
                  child: Text('Habis',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            if (quantity > 0)
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                      color: colorScheme.primary,
                      borderRadius: BorderRadius.circular(20)),
                  child: Text('$quantity',
                      style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onPrimary,
                          fontWeight: FontWeight.bold)),
                ),
              ),
          ]),
        ),

        // ── Info ─────────────────────────────────────────────────────────
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.name,
                  style: theme.textTheme.labelLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(_formatPrice(item.price),
                  style: theme.textTheme.labelMedium?.copyWith(
                      color: colorScheme.primary, fontWeight: FontWeight.bold)),
            ]),
          ),
        ),

        // ── Quantity Controls ─────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 4, 6, 8),
          child: item.isAvailable
              ? (quantity == 0
                  ? SizedBox(
                      width: double.infinity,
                      height: 32,
                      child: ElevatedButton(
                        onPressed: onAdd,
                        style: ElevatedButton.styleFrom(
                            padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8))),
                        child: const Text('Tambah'),
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _QtyButton(icon: Icons.remove, onTap: onRemove),
                        Text('$quantity',
                            style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: colorScheme.primary)),
                        _QtyButton(icon: Icons.add, onTap: onAdd),
                      ],
                    ))
              : const SizedBox(
                  width: double.infinity,
                  height: 32,
                  child: OutlinedButton(
                      onPressed: null, child: Text('Habis'))),
        ),
      ]),
    );
  }

  Widget _placeholder(ColorScheme colorScheme) => Container(
        color: colorScheme.surfaceContainerHighest,
        child: Center(
          child: Icon(Icons.fastfood_outlined,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
              size: 36),
        ),
      );

  String _formatPrice(double price) => 'Rp ${price.toStringAsFixed(0).replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}';
}

class _QtyButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _QtyButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, size: 16, color: colorScheme.onPrimaryContainer),
      ),
    );
  }
}

// ─── Cart FAB ─────────────────────────────────────────────────────────────────

class _CartFab extends StatelessWidget {
  final QrOrderSession cart;
  final String tableId;
  final String tableName;

  const _CartFab(
      {required this.cart, required this.tableId, required this.tableName});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return GestureDetector(
      onTap: () => context.push('/qr/$tableId/cart'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: colorScheme.primary,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
                color: colorScheme.primary.withValues(alpha: 0.35),
                blurRadius: 12,
                offset: const Offset(0, 4))
          ],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Stack(children: [
            Icon(Icons.shopping_cart_outlined,
                color: colorScheme.onPrimary, size: 22),
            Positioned(
              top: -2,
              right: -2,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                    color: colorScheme.error, shape: BoxShape.circle),
                constraints:
                    const BoxConstraints(minWidth: 14, minHeight: 14),
                child: Text('${cart.totalItems}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center),
              ),
            ),
          ]),
          const SizedBox(width: 10),
          Text('Keranjang',
              style: theme.textTheme.labelLarge?.copyWith(
                  color: colorScheme.onPrimary, fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Container(
              width: 1,
              height: 16,
              color: colorScheme.onPrimary.withValues(alpha: 0.4)),
          const SizedBox(width: 8),
          Text(_formatPrice(cart.totalAmount),
              style: theme.textTheme.labelLarge?.copyWith(
                  color: colorScheme.onPrimary, fontWeight: FontWeight.bold)),
        ]),
      ),
    );
  }

  String _formatPrice(double price) => 'Rp ${price.toStringAsFixed(0).replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}';
}