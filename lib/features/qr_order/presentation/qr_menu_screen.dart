import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../providers/qr_cart_provider.dart';
import '../data/qr_order_repository.dart';

final _menuDataProvider = FutureProvider.family<List<Map<String, dynamic>>, String>(
  (ref, branchId) async => ref.read(qrOrderRepositoryProvider).fetchMenuByBranch(branchId),
);

final _tableInfoProvider = FutureProvider.family<Map<String, dynamic>?, String>(
  (ref, tableId) async => ref.read(qrOrderRepositoryProvider).fetchTableInfo(tableId),
);

final _selectedCategoryProvider = StateProvider<String?>((ref) => null);
final _searchQueryProvider = StateProvider<String>((ref) => '');

class QrMenuScreen extends ConsumerStatefulWidget {
  final String tableId;
  const QrMenuScreen({super.key, required this.tableId});

  @override
  ConsumerState<QrMenuScreen> createState() => _QrMenuScreenState();
}

class _QrMenuScreenState extends ConsumerState<QrMenuScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _fabAnimCtrl;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fabAnimCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
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
        // ✅ FIX: petakan preparation_time_minutes dari Supabase ke MenuItem
        preparationTimeMinutes: row['preparation_time_minutes'] as int? ?? 15,
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
    final tableInfoAsync = ref.watch(_tableInfoProvider(widget.tableId));

    return tableInfoAsync.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        body: Center(child: Text('Error memuat meja: $e')),
      ),
      data: (tableData) {
        final branchId = (tableData?['branch_id'] as String?)?.trim() ?? '';

        if (branchId.isEmpty) {
          return const Scaffold(
            body: Center(child: Text('Branch ID tidak ditemukan pada meja ini')),
          );
        }

        final branch = tableData?['branches'] as Map<String, dynamic>?;
        final branchName = branch?['name'] as String? ?? 'Restoran';
        final tableName = (tableData?['table_number'] as String?) ?? 'Meja';

        // Simpan data ke activeQrTableProvider
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ref.read(activeQrTableProvider.notifier).state = (
            tableId: widget.tableId,
            tableName: tableName,
            branchId: branchId,
          );
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

// ─── Menu Body (Responsive) ───────────────────────────────────────────────────
class _MenuBody extends ConsumerWidget {
  final String tableId, tableName, branchId, branchName;
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
    final selectedCat = ref.watch(_selectedCategoryProvider);
    final searchQuery = ref.watch(_searchQueryProvider);
    final cart = ref.watch(activeQrCartProvider);

    final isWideScreen = MediaQuery.of(context).size.width > 700;

    cart.totalItems > 0 ? fabAnimCtrl.forward() : fabAnimCtrl.reverse();

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Column(
        children: [
          _QrMenuHeader(
            tableName: tableName,
            branchName: branchName,
            searchCtrl: searchCtrl,
            onSearchChanged: (q) => ref.read(_searchQueryProvider.notifier).state = q,
          ),
          Expanded(
            child: menuAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.wifi_off_outlined, size: 48),
                  const SizedBox(height: 12),
                  Text('Gagal memuat menu: $e'),
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

                var displayItems = selectedCat == null
                    ? allItems
                    : (grouped[selectedCat] ?? []);

                if (searchQuery.isNotEmpty) {
                  final q = searchQuery.toLowerCase();
                  displayItems = displayItems
                      .where((i) => i.name.toLowerCase().contains(q) ||
                          i.description.toLowerCase().contains(q))
                      .toList();
                }

                if (isWideScreen) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _CategorySidebar(
                        categories: categories,
                        selected: selectedCat,
                        onSelect: (cat) => ref.read(_selectedCategoryProvider.notifier).state = cat,
                      ),
                      Expanded(
                        child: _MenuContent(
                          displayItems: displayItems,
                          tableId: tableId,
                          tableName: tableName,
                        ),
                      ),
                    ],
                  );
                } else {
                  return Column(
                    children: [
                      _CategorySelector(
                        categories: categories,
                        selected: selectedCat,
                        onSelect: (cat) => ref.read(_selectedCategoryProvider.notifier).state = cat,
                      ),
                      Expanded(
                        child: _MenuContent(
                          displayItems: displayItems,
                          tableId: tableId,
                          tableName: tableName,
                        ),
                      ),
                    ],
                  );
                }
              },
            ),
          ),
        ],
      ),
      floatingActionButton: cart.isEmpty
          ? null
          : ScaleTransition(
              scale: CurvedAnimation(parent: fabAnimCtrl, curve: Curves.elasticOut),
              child: _CartFab(cart: cart, tableId: tableId, tableName: tableName),
            ),
    );
  }
}

// ─── Category Sidebar (Web) ───────────────────────────────────────────────────
class _CategorySidebar extends StatelessWidget {
  final List<String> categories;
  final String? selected;
  final ValueChanged<String?> onSelect;

  const _CategorySidebar({required this.categories, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final all = ['Semua', ...categories];

    return Container(
      width: 180,
      decoration: BoxDecoration(
        color: cs.surface,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 6, offset: const Offset(2, 0))],
      ),
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Text('KATEGORI', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
          ),
          ...all.map((label) {
            final isActive = selected == (label == 'Semua' ? null : label);
            return GestureDetector(
              onTap: () => onSelect(label == 'Semua' ? null : label),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: isActive ? cs.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                    color: isActive ? cs.onPrimary : cs.onSurface,
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ─── Category Selector (Mobile) ───────────────────────────────────────────────
class _CategorySelector extends StatelessWidget {
  final List<String> categories;
  final String? selected;
  final ValueChanged<String?> onSelect;

  const _CategorySelector({required this.categories, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final allCategories = ['Semua', ...categories];
    final cs = Theme.of(context).colorScheme;

    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: allCategories.length,
        itemBuilder: (context, index) {
          final label = allCategories[index];
          final isActive = selected == (label == 'Semua' ? null : label);
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              selected: isActive,
              label: Text(label),
              onSelected: (_) => onSelect(label == 'Semua' ? null : label),
              backgroundColor: cs.surfaceContainer,
              selectedColor: cs.primary,
              labelStyle: TextStyle(
                color: isActive ? cs.onPrimary : cs.onSurface,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─── Menu Content ─────────────────────────────────────────────────────────────
class _MenuContent extends StatelessWidget {
  final List<MenuItem> displayItems;
  final String tableId;
  final String tableName;

  const _MenuContent({required this.displayItems, required this.tableId, required this.tableName});

  @override
  Widget build(BuildContext context) {
    if (displayItems.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 48, color: Colors.grey),
            SizedBox(height: 12),
            Text('Menu tidak ditemukan'),
          ],
        ),
      );
    }
    return _MenuList(items: displayItems, tableId: tableId, tableName: tableName);
  }
}

// ─── Menu List ────────────────────────────────────────────────────────────────
class _MenuList extends ConsumerWidget {
  final List<MenuItem> items;
  final String tableId, tableName;

  const _MenuList({required this.items, required this.tableId, required this.tableName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(activeQrCartProvider);
    final notifier = ref.read(activeQrCartNotifierProvider);

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final item = items[i];
        final qty = cart.items
            .where((c) => c.menuItem.id == item.id)
            .fold(0, (s, c) => s + c.quantity);

        return _MenuItemTile(
          item: item,
          quantity: qty,
          onAdd: () => notifier.addItem(item),
          onRemove: () => notifier.removeItem(item.id),
        );
      },
    );
  }
}

// ─── Menu Item Tile ───────────────────────────────────────────────────────────
class _MenuItemTile extends StatelessWidget {
  final MenuItem item;
  final int quantity;
  final VoidCallback onAdd, onRemove;

  const _MenuItemTile({
    required this.item,
    required this.quantity,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final inCart = quantity > 0;
    final unavailable = !item.isAvailable;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: inCart ? cs.primary : cs.outlineVariant.withValues(alpha: 0.5),
          width: inCart ? 1.5 : 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: inCart
                ? cs.primary.withValues(alpha: 0.07)
                : Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.horizontal(left: Radius.circular(15)),
            child: SizedBox(
              width: 90,
              height: 90,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _MenuImage(imageUrl: item.imageUrl, cs: cs),
                  if (unavailable)
                    Container(
                      color: Colors.black.withValues(alpha: 0.52),
                      child: const Center(
                        child: Text('Habis', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.name,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (item.description.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      item.description,
                      style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant, height: 1.3),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    _fmt(item.price),
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cs.primary),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: unavailable
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('Habis', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, fontWeight: FontWeight.w500)),
                  )
                : inCart
                    ? Container(
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: cs.primary.withValues(alpha: 0.2), width: 1),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _QtyBtn(icon: Icons.remove, onTap: onRemove, cs: cs),
                            SizedBox(
                              width: 28,
                              child: Center(child: Text('$quantity', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: cs.primary))),
                            ),
                            _QtyBtn(icon: Icons.add, onTap: onAdd, cs: cs),
                          ],
                        ),
                      )
                    : GestureDetector(
                        onTap: onAdd,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: cs.primary,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.add, size: 14, color: cs.onPrimary),
                              const SizedBox(width: 4),
                              Text('Tambah', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onPrimary)),
                            ],
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  String _fmt(double p) => 'Rp ${p.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}';
}

class _QtyBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final ColorScheme cs;

  const _QtyBtn({required this.icon, required this.onTap, required this.cs});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(width: 32, height: 32, child: Icon(icon, size: 16, color: cs.primary)),
    );
  }
}

class _MenuImage extends StatelessWidget {
  final String? imageUrl;
  final ColorScheme cs;

  const _MenuImage({required this.imageUrl, required this.cs});

  @override
  Widget build(BuildContext context) {
    if (imageUrl == null || imageUrl!.trim().isEmpty) return _placeholder();

    return CachedNetworkImage(
      imageUrl: imageUrl!,
      fit: BoxFit.cover,
      placeholder: (_, __) => Container(
        color: cs.surfaceContainerHighest,
        child: const Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 1.5))),
      ),
      errorWidget: (_, __, ___) => _placeholder(),
    );
  }

  Widget _placeholder() => Container(
        color: cs.surfaceContainerHighest,
        child: const Center(child: Icon(Icons.fastfood_outlined, size: 28, color: Colors.grey)),
      );
}

class _QrMenuHeader extends StatelessWidget {
  final String tableName, branchName;
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
    final cs = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.primary,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.restaurant, color: cs.onPrimary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(branchName, style: theme.textTheme.labelLarge?.copyWith(color: cs.onPrimary.withValues(alpha: 0.85)), overflow: TextOverflow.ellipsis),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(color: cs.onPrimary.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(20)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.table_restaurant, size: 14, color: cs.onPrimary),
                    const SizedBox(width: 4),
                    Text(tableName, style: theme.textTheme.labelMedium?.copyWith(color: cs.onPrimary, fontWeight: FontWeight.bold)),
                  ]),
                ),
              ]),
              const SizedBox(height: 8),
              Text('Pilih menu favoritmu', style: theme.textTheme.headlineSmall?.copyWith(color: cs.onPrimary, fontWeight: FontWeight.bold)),
              const SizedBox(height: 14),
              TextField(
                controller: searchCtrl,
                onChanged: onSearchChanged,
                style: theme.textTheme.bodyMedium,
                decoration: InputDecoration(
                  hintText: 'Cari makanan atau minuman...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: searchCtrl.text.isNotEmpty
                      ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () { searchCtrl.clear(); onSearchChanged(''); })
                      : null,
                  filled: true,
                  fillColor: cs.surface,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CartFab extends StatelessWidget {
  final QrOrderSession cart;
  final String tableId, tableName;

  const _CartFab({required this.cart, required this.tableId, required this.tableName});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return GestureDetector(
      onTap: () => context.push('/qr/$tableId/cart'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: cs.primary,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: cs.primary.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 4))],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Stack(children: [
            Icon(Icons.shopping_cart_outlined, color: cs.onPrimary, size: 22),
            if (cart.totalItems > 0)
              Positioned(
                top: -2,
                right: -2,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(color: cs.error, shape: BoxShape.circle),
                  constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
                  child: Text('${cart.totalItems}', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                ),
              ),
          ]),
          const SizedBox(width: 10),
          Text('Keranjang', style: theme.textTheme.labelLarge?.copyWith(color: cs.onPrimary, fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Container(width: 1, height: 16, color: cs.onPrimary.withValues(alpha: 0.4)),
          const SizedBox(width: 8),
          Text(_fmt(cart.totalAmount), style: theme.textTheme.labelLarge?.copyWith(color: cs.onPrimary, fontWeight: FontWeight.bold)),
        ]),
      ),
    );
  }

  String _fmt(double p) => 'Rp ${p.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}';
}