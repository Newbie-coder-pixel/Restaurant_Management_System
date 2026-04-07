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
final _searchQueryProvider      = StateProvider<String>((ref) => '');
final _isGridViewProvider       = StateProvider<bool>((ref) => true);

// ─── Konstanta ukuran card ────────────────────────────────────────────────────
// Dengan mainAxisExtent semua card SELALU sama tinggi, tidak ada space sisa.
const double _kCardImageHeight = 110.0;
const double _kCardInfoHeight  = 108.0; // nama(2baris)+harga+tombol+padding
const double _kCardHeight      = _kCardImageHeight + _kCardInfoHeight; // 218

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
        id:           row['id'] as String,
        name:         row['name'] as String,
        description:  row['description'] as String? ?? '',
        price:        (row['price'] as num).toDouble(),
        categoryId:   row['category_id'] as String? ?? '',
        categoryName: cat?['name'] as String? ?? 'Lainnya',
        imageUrl:     row['image_url'] as String?,
        isAvailable:  row['is_available'] as bool? ?? true,
        sortOrder:    row['sort_order'] as int? ?? 0,
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

        final branch    = tableData['branches'] as Map<String, dynamic>?;
        final branchId  = branch?['id'] as String? ?? '';
        final branchName = branch?['name'] as String? ?? 'Restoran';
        final tableName = (tableData['table_number'] as String?) ?? 'Meja';

        WidgetsBinding.instance.addPostFrameCallback((_) {
          ref.read(activeQrTableProvider.notifier).state =
              (tableId: widget.tableId, tableName: tableName);
        });

        return _MenuBody(
          tableId:       widget.tableId,
          tableName:     tableName,
          branchId:      branchId,
          branchName:    branchName,
          parseItems:    _parseItems,
          groupByCategory: _groupByCategory,
          fabAnimCtrl:   _fabAnimCtrl,
          searchCtrl:    _searchCtrl,
        );
      },
    );
  }
}

// ─── Menu Body ────────────────────────────────────────────────────────────────

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
    final menuAsync      = ref.watch(_menuDataProvider(branchId));
    final selectedCat    = ref.watch(_selectedCategoryProvider);
    final searchQuery    = ref.watch(_searchQueryProvider);
    final cart           = ref.watch(activeQrCartProvider);

    cart.totalItems > 0 ? fabAnimCtrl.forward() : fabAnimCtrl.reverse();

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Column(children: [
        _QrMenuHeader(
          tableName:       tableName,
          branchName:      branchName,
          searchCtrl:      searchCtrl,
          onSearchChanged: (q) =>
              ref.read(_searchQueryProvider.notifier).state = q,
        ),
        Expanded(
          child: menuAsync.when(
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.wifi_off_outlined, size: 48),
                const SizedBox(height: 12),
                const Text('Gagal memuat menu'),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: () =>
                      ref.invalidate(_menuDataProvider(branchId)),
                  child: const Text('Coba Lagi'),
                ),
              ]),
            ),
            data: (rawItems) {
              final allItems  = parseItems(rawItems);
              final grouped   = groupByCategory(allItems);
              final categories = grouped.keys.toList();

              var displayItems = selectedCat == null
                  ? allItems
                  : (grouped[selectedCat] ?? []);

              if (searchQuery.isNotEmpty) {
                final q = searchQuery.toLowerCase();
                displayItems = displayItems
                    .where((i) =>
                        i.name.toLowerCase().contains(q) ||
                        i.description.toLowerCase().contains(q))
                    .toList();
              }

              return Row(children: [
                _CategorySidebar(
                  categories: categories,
                  selected:   selectedCat,
                  onSelect:   (cat) {
                    ref.read(_selectedCategoryProvider.notifier).state =
                        cat == selectedCat ? null : cat;
                  },
                ),
                Expanded(
                  child: displayItems.isEmpty
                      ? const Center(
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.search_off, size: 48, color: Colors.grey),
                            SizedBox(height: 12),
                            Text('Menu tidak ditemukan'),
                          ]),
                        )
                      : _MenuGrid(
                          items:     displayItems,
                          tableId:   tableId,
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
              scale: CurvedAnimation(
                  parent: fabAnimCtrl, curve: Curves.elasticOut),
              child: _CartFab(
                  cart: cart, tableId: tableId, tableName: tableName),
            ),
    );
  }
}

// ─── Header ───────────────────────────────────────────────────────────────────

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
    final theme       = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color:         colorScheme.primary,
        borderRadius:  const BorderRadius.vertical(bottom: Radius.circular(24)),
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
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color:         colorScheme.onPrimary.withValues(alpha: 0.2),
                  borderRadius:  BorderRadius.circular(20),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.table_restaurant,
                      size: 14, color: colorScheme.onPrimary),
                  const SizedBox(width: 4),
                  Text(tableName,
                      style: theme.textTheme.labelMedium?.copyWith(
                          color:      colorScheme.onPrimary,
                          fontWeight: FontWeight.bold)),
                ]),
              ),
            ]),
            const SizedBox(height: 8),
            Text('Pilih menu favoritmu',
                style: theme.textTheme.headlineSmall?.copyWith(
                    color:      colorScheme.onPrimary,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 14),
            TextField(
              controller: searchCtrl,
              onChanged:  onSearchChanged,
              style:      theme.textTheme.bodyMedium,
              decoration: InputDecoration(
                hintText:    'Cari makanan atau minuman...',
                prefixIcon:  const Icon(Icons.search, size: 20),
                suffixIcon:  searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon:      const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          searchCtrl.clear();
                          onSearchChanged('');
                        },
                      )
                    : null,
                filled:         true,
                fillColor:      colorScheme.surface,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:   BorderSide.none),
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

  static const _icons = <String, IconData>{
    'Makanan': Icons.rice_bowl_outlined,
    'Minuman': Icons.local_drink_outlined,
    'Snack':   Icons.cookie_outlined,
    'Dessert': Icons.cake_outlined,
    'Paket':   Icons.lunch_dining_outlined,
    'Promo':   Icons.local_offer_outlined,
    'Lainnya': Icons.more_horiz,
  };

  @override
  Widget build(BuildContext context) {
    final theme       = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final all         = ['Semua', ...categories];

    return Container(
      width: 72,
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      child: ListView.separated(
        padding:          const EdgeInsets.symmetric(vertical: 8),
        itemCount:        all.length,
        separatorBuilder: (_, __) => const SizedBox(height: 2),
        itemBuilder: (context, i) {
          final label    = all[i];
          final isSemua  = label == 'Semua';
          final isSel    = isSemua ? selected == null : selected == label;
          final icon     = isSemua
              ? Icons.grid_view_rounded
              : (_icons[label] ?? Icons.fastfood_outlined);

          return GestureDetector(
            onTap: () {
              if (isSemua) {
                if (selected != null) onSelect(selected!);
              } else {
                onSelect(label);
              }
            },
            child: AnimatedContainer(
              duration:  const Duration(milliseconds: 200),
              margin:    const EdgeInsets.symmetric(horizontal: 6),
              padding:   const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              decoration: BoxDecoration(
                color:        isSel ? colorScheme.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon,
                    size:  22,
                    color: isSel
                        ? colorScheme.onPrimary
                        : colorScheme.onSurfaceVariant),
                const SizedBox(height: 4),
                Text(label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color:      isSel
                          ? colorScheme.onPrimary
                          : colorScheme.onSurfaceVariant,
                      fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                    ),
                    textAlign: TextAlign.center,
                    maxLines:  2,
                    overflow:  TextOverflow.ellipsis),
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
  final String tableId, tableName;

  const _MenuGrid({
    required this.items,
    required this.tableId,
    required this.tableName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart     = ref.watch(activeQrCartProvider);
    final notifier = ref.read(activeQrCartNotifierProvider);
    final isGrid   = ref.watch(_isGridViewProvider);

    return Column(children: [
      // ── Toolbar ───────────────────────────────────────────────────────
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Row(children: [
          Text('${items.length} menu tersedia',
              style: TextStyle(
                  fontSize:   11,
                  color:      Colors.grey[500],
                  fontWeight: FontWeight.w500)),
          const Spacer(),
          _ViewToggle(
            isGrid:   isGrid,
            onToggle: (v) =>
                ref.read(_isGridViewProvider.notifier).state = v,
          ),
        ]),
      ),

      Expanded(
        child: isGrid
            ? GridView.builder(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 100),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount:  2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing:  10,
                  // ✅ mainAxisExtent = fixed height, TIDAK ada space sisa
                  mainAxisExtent:  _kCardHeight,
                ),
                itemCount:   items.length,
                itemBuilder: (_, i) {
                  final item = items[i];
                  final qty  = cart.items
                      .where((c) => c.menuItem.id == item.id)
                      .fold(0, (s, c) => s + c.quantity);
                  return _MenuItemCard(
                    item:     item,
                    quantity: qty,
                    onAdd:    () => notifier.addItem(item),
                    onRemove: () => notifier.removeItem(item.id),
                  );
                },
              )
            : ListView.builder(
                padding:     const EdgeInsets.fromLTRB(12, 6, 12, 100),
                itemCount:   items.length,
                itemBuilder: (_, i) {
                  final item = items[i];
                  final qty  = cart.items
                      .where((c) => c.menuItem.id == item.id)
                      .fold(0, (s, c) => s + c.quantity);
                  return _MenuItemListTile(
                    item:     item,
                    quantity: qty,
                    onAdd:    () => notifier.addItem(item),
                    onRemove: () => notifier.removeItem(item.id),
                  );
                },
              ),
      ),
    ]);
  }
}

// ─── View Toggle ──────────────────────────────────────────────────────────────

class _ViewToggle extends StatelessWidget {
  final bool isGrid;
  final ValueChanged<bool> onToggle;
  const _ViewToggle({required this.isGrid, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color:        cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        _TBtn(icon: Icons.grid_view_rounded,  active: isGrid,  onTap: () => onToggle(true)),
        _TBtn(icon: Icons.view_list_rounded,  active: !isGrid, onTap: () => onToggle(false)),
      ]),
    );
  }
}

class _TBtn extends StatelessWidget {
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  const _TBtn({required this.icon, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration:  const Duration(milliseconds: 180),
        padding:   const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color:        active ? cs.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon,
            size:  16,
            color: active ? cs.onPrimary : cs.onSurfaceVariant),
      ),
    );
  }
}

// ─── Shared: Menu Image ───────────────────────────────────────────────────────
// Gambar dengan double-fallback:
//  1. CachedNetworkImage (dengan headers)
//  2. Image.network langsung (browser handle CORS)
//  3. Placeholder icon
// Mengatasi URL 404 dari Unsplash / imgix dengan graceful degradation.

class _MenuImage extends StatelessWidget {
  final String? imageUrl;
  final ColorScheme cs;
  const _MenuImage({required this.imageUrl, required this.cs});

  @override
  Widget build(BuildContext context) {
    if (imageUrl == null || imageUrl!.trim().isEmpty) return _placeholder();

    return CachedNetworkImage(
      imageUrl: imageUrl!,
      fit:      BoxFit.cover,
      httpHeaders: const {
        'Accept': 'image/webp,image/apng,image/*,*/*;q=0.8',
      },
      placeholder: (_, __) => Container(
        color: cs.surfaceContainerHighest,
        child: Center(
          child: SizedBox(
            width: 18, height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: cs.primary.withValues(alpha: 0.35),
            ),
          ),
        ),
      ),
      errorWidget: (_, url, __) => Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder:   (_, __, ___) => _placeholder(),
        loadingBuilder: (_, child, prog) =>
            prog == null ? child : _loadingBox(prog),
      ),
    );
  }

  Widget _placeholder() => Container(
        color: cs.surfaceContainerHighest,
        child: Center(
          child: Icon(Icons.fastfood_outlined,
              size:  32,
              color: cs.onSurfaceVariant.withValues(alpha: 0.3)),
        ),
      );

  Widget _loadingBox(ImageChunkEvent prog) => Container(
        color: cs.surfaceContainerHighest,
        child: Center(
          child: SizedBox(
            width: 18, height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              value: prog.expectedTotalBytes != null
                  ? prog.cumulativeBytesLoaded / prog.expectedTotalBytes!
                  : null,
              color: cs.primary.withValues(alpha: 0.35),
            ),
          ),
        ),
      );
}

// ─── Menu Item Card (Grid) ────────────────────────────────────────────────────

class _MenuItemCard extends StatelessWidget {
  final MenuItem item;
  final int quantity;
  final VoidCallback onAdd, onRemove;

  const _MenuItemCard({
    required this.item,
    required this.quantity,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme       = Theme.of(context);
    final cs          = theme.colorScheme;
    final inCart      = quantity > 0;
    final unavailable = !item.isAvailable;

    return DecoratedBox(
      decoration: BoxDecoration(
        color:        cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: inCart
              ? cs.primary
              : cs.outlineVariant.withValues(alpha: 0.6),
          width: inCart ? 1.5 : 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color:     inCart
                ? cs.primary.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.04),
            blurRadius: inCart ? 8 : 4,
            offset:     const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        // ✅ Column dengan fixed height dari mainAxisExtent — tidak ada sisa ruang
        child: SizedBox(
          height: _kCardHeight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Gambar: fixed 110px ──────────────────────────────────
              SizedBox(
                height: _kCardImageHeight,
                width:  double.infinity,
                child: Stack(fit: StackFit.expand, children: [
                  _MenuImage(imageUrl: item.imageUrl, cs: cs),

                  if (unavailable)
                    Container(
                      color: Colors.black.withValues(alpha: 0.55),
                      child: const Center(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.remove_circle_outline,
                              color: Colors.white, size: 18),
                          SizedBox(height: 3),
                          Text('Habis',
                              style: TextStyle(
                                  color:      Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize:   11)),
                        ]),
                      ),
                    ),

                  if (inCart)
                    Positioned(
                      top: 6, right: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                            color:        cs.primary,
                            borderRadius: BorderRadius.circular(20)),
                        child: Text('$quantity',
                            style: const TextStyle(
                                color:      Colors.white,
                                fontSize:   11,
                                fontWeight: FontWeight.w700)),
                      ),
                    ),
                ]),
              ),

              // ── Info: sisa _kCardInfoHeight ──────────────────────────
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                  child: Column(
                    crossAxisAlignment:  CrossAxisAlignment.start,
                    mainAxisAlignment:   MainAxisAlignment.spaceBetween,
                    children: [
                      // Nama + harga
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.name,
                              style: const TextStyle(
                                  fontSize:   13,
                                  fontWeight: FontWeight.w600),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 2),
                          Text(_fmt(item.price),
                              style: TextStyle(
                                  fontSize:   12,
                                  fontWeight: FontWeight.w700,
                                  color:      cs.primary)),
                        ],
                      ),

                      // Tombol — selalu di paling bawah
                      _ActionButton(
                        inCart:      inCart,
                        unavailable: unavailable,
                        quantity:    quantity,
                        cs:          cs,
                        onAdd:       onAdd,
                        onRemove:    onRemove,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _fmt(double p) => 'Rp ${p.toStringAsFixed(0).replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}';
}

// ─── Shared: Action Button ────────────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  final bool inCart, unavailable;
  final int quantity;
  final ColorScheme cs;
  final VoidCallback onAdd, onRemove;

  const _ActionButton({
    required this.inCart,
    required this.unavailable,
    required this.quantity,
    required this.cs,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    if (unavailable) {
      return Container(
        width:     double.infinity,
        padding:   const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          color:        cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(
          child: Text('Habis',
              style: TextStyle(
                  fontSize:   12,
                  color:      Colors.grey,
                  fontWeight: FontWeight.w500)),
        ),
      );
    }

    if (inCart) {
      return Container(
        decoration: BoxDecoration(
          color:        cs.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _QtyButton(icon: Icons.remove, onTap: onRemove, cs: cs),
            Text('$quantity',
                style: TextStyle(
                    fontSize:   13,
                    fontWeight: FontWeight.w700,
                    color:      cs.primary)),
            _QtyButton(icon: Icons.add, onTap: onAdd, cs: cs),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: onAdd,
      child: Container(
        width:   double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          color:        cs.primary,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.add, size: 14, color: cs.onPrimary),
            const SizedBox(width: 4),
            Text('Tambah',
                style: TextStyle(
                    fontSize:   12,
                    fontWeight: FontWeight.w600,
                    color:      cs.onPrimary)),
          ]),
        ),
      ),
    );
  }
}

// ─── Menu Item List Tile (List view) ─────────────────────────────────────────

class _MenuItemListTile extends StatelessWidget {
  final MenuItem item;
  final int quantity;
  final VoidCallback onAdd, onRemove;

  const _MenuItemListTile({
    required this.item,
    required this.quantity,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final cs          = Theme.of(context).colorScheme;
    final inCart      = quantity > 0;
    final unavailable = !item.isAvailable;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin:   const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color:        cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: inCart
              ? cs.primary
              : cs.outlineVariant.withValues(alpha: 0.6),
          width: inCart ? 1.5 : 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color:     Colors.black.withValues(alpha: 0.04),
            blurRadius: 4,
            offset:     const Offset(0, 2),
          ),
        ],
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(
          borderRadius:
              const BorderRadius.horizontal(left: Radius.circular(13)),
          child: SizedBox(
            width: 100, height: 100,
            child: Stack(fit: StackFit.expand, children: [
              _MenuImage(imageUrl: item.imageUrl, cs: cs),
              if (unavailable)
                Container(
                  color: Colors.black.withValues(alpha: 0.5),
                  child: const Center(
                    child: Text('Habis',
                        style: TextStyle(
                            color:      Colors.white,
                            fontSize:   11,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
            ]),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name,
                    style: const TextStyle(
                        fontSize:   13,
                        fontWeight: FontWeight.w600),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                if (item.description.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(item.description,
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_fmt(item.price),
                        style: TextStyle(
                            fontSize:   13,
                            fontWeight: FontWeight.w700,
                            color:      cs.primary)),
                    _ActionButton(
                      inCart:      inCart,
                      unavailable: unavailable,
                      quantity:    quantity,
                      cs:          cs,
                      onAdd:       onAdd,
                      onRemove:    onRemove,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ]),
    );
  }

  String _fmt(double p) => 'Rp ${p.toStringAsFixed(0).replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}';
}

// ─── Qty Button ───────────────────────────────────────────────────────────────

class _QtyButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final ColorScheme cs;
  const _QtyButton(
      {required this.icon, required this.onTap, required this.cs});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30, height: 30,
        decoration: BoxDecoration(
            color:        cs.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, size: 15, color: cs.primary),
      ),
    );
  }
}

// ─── Cart FAB ─────────────────────────────────────────────────────────────────

class _CartFab extends StatelessWidget {
  final QrOrderSession cart;
  final String tableId, tableName;

  const _CartFab(
      {required this.cart, required this.tableId, required this.tableName});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs    = theme.colorScheme;

    return GestureDetector(
      onTap: () => context.push('/qr/$tableId/cart'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color:        cs.primary,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
                color:     cs.primary.withValues(alpha: 0.35),
                blurRadius: 12,
                offset:     const Offset(0, 4))
          ],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Stack(children: [
            Icon(Icons.shopping_cart_outlined,
                color: cs.onPrimary, size: 22),
            Positioned(
              top: -2, right: -2,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                    color: cs.error, shape: BoxShape.circle),
                constraints:
                    const BoxConstraints(minWidth: 14, minHeight: 14),
                child: Text('${cart.totalItems}',
                    style: const TextStyle(
                        color:      Colors.white,
                        fontSize:   9,
                        fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center),
              ),
            ),
          ]),
          const SizedBox(width: 10),
          Text('Keranjang',
              style: theme.textTheme.labelLarge?.copyWith(
                  color:      cs.onPrimary,
                  fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Container(width: 1, height: 16,
              color: cs.onPrimary.withValues(alpha: 0.4)),
          const SizedBox(width: 8),
          Text(_fmt(cart.totalAmount),
              style: theme.textTheme.labelLarge?.copyWith(
                  color:      cs.onPrimary,
                  fontWeight: FontWeight.bold)),
        ]),
      ),
    );
  }

  String _fmt(double p) => 'Rp ${p.toStringAsFixed(0).replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}';
}