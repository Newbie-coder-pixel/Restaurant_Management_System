import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../providers/qr_cart_provider.dart';
import '../data/qr_order_repository.dart';
import '../models/qr_order_model.dart';
import '../services/qr_device_id_service.dart';
import '../../../shared/models/table_model.dart';

final _menuDataProvider = FutureProvider.family<List<Map<String, dynamic>>, String>(
  (ref, branchId) async => ref.read(qrOrderRepositoryProvider).fetchMenuByBranch(branchId),
);

final _tableInfoProvider = FutureProvider.family<Map<String, dynamic>?, String>(
  (ref, tableId) async => ref.read(qrOrderRepositoryProvider).fetchTableInfo(tableId),
);

// Prevents disconnected duplicate orders: if this table already has an
// active (unpaid, uncancelled) order, a fresh QR scan should offer to join
// it rather than silently starting an unrelated second order.
final _activeOrderForTableProvider = FutureProvider.family<QrOrderModel?, String>(
  (ref, tableId) async => ref.read(qrOrderRepositoryProvider).fetchActiveOrderForTable(tableId),
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
  bool _activeOrderPromptShown = false;

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
        categoryName: cat?['name'] as String? ?? 'Other',
        imageUrl: row['image_url'] as String?,
        isAvailable: row['is_available'] as bool? ?? true,
        sortOrder: row['sort_order'] as int? ?? 0,
        preparationTimeMinutes: row['preparation_time_minutes'] as int? ?? 15,
        allergens: List<String>.from(row['allergens'] as List? ?? []),
        dietaryTags: List<String>.from(row['dietary_tags'] as List? ?? []),
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

  void _joinActiveOrder(QrOrderModel order) {
    ref.read(addOrderModeProvider.notifier).state = AddOrderModeState(
      orderId: order.id,
      queueNumber: order.queueNumber,
      tableId: order.tableId,
    );
    ref.read(activeQrCartNotifierProvider).clearCart();
  }

  // Only the device that created the table's active order may add items to
  // it or start a fresh one — every other device scanning the same QR is
  // forced to finish/pay on the original device, and can only check status
  // from here. See supabase/migrations/20260803010000_qr_order_device_id.sql.
  Future<void> _showActiveOrderDialog(QrOrderModel order) async {
    if (!mounted) return;
    final deviceId = await QrDeviceIdService.getDeviceId();
    if (!mounted) return;

    // An order with no device_id recorded at all (placed before the
    // device-lock feature shipped) has no owner to defer to, so this device
    // is treated as the owner and claims it for real in the background —
    // otherwise the customer who placed it would be permanently locked out.
    final orderHasNoOwner = order.deviceId == null || order.deviceId!.isEmpty;
    final isOwner = orderHasNoOwner || order.deviceId == deviceId;
    if (orderHasNoOwner) {
      ref.read(qrOrderRepositoryProvider).claimOrderIfUnowned(order.id, deviceId);
    }
    final itemCount = order.items.fold<int>(0, (s, i) => s + i.quantity);

    void goToStatus(BuildContext ctx) {
      Navigator.pop(ctx);
      context.go('/qr/${widget.tableId}/track/${order.id}?queue=${order.queueNumber}');
    }

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            isOwner ? 'You have an order in progress' : 'This table already has an order',
            style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700),
          ),
          content: Text(
            isOwner
                ? 'Order #${order.queueNumber} ($itemCount item${itemCount == 1 ? '' : 's'}) is '
                    'already open at this table. Add more items to it or check its status.'
                : 'Order #${order.queueNumber} is already open at this table on another '
                    'device or browser. Please finish and complete payment there first — '
                    'this device can only check its status until then.',
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
          ),
          actionsOverflowDirection: VerticalDirection.down,
          actions: isOwner
              ? [
                  OutlinedButton(
                    onPressed: () => goToStatus(ctx),
                    child: const Text('View order status',
                        style: TextStyle(fontFamily: 'Poppins')),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _joinActiveOrder(order);
                    },
                    child: Text('Add to Order #${order.queueNumber}',
                        style: const TextStyle(fontFamily: 'Poppins')),
                  ),
                ]
              : [
                  ElevatedButton(
                    onPressed: () => goToStatus(ctx),
                    child: const Text('View order status',
                        style: TextStyle(fontFamily: 'Poppins')),
                  ),
                ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tableInfoAsync = ref.watch(_tableInfoProvider(widget.tableId));

    ref.listen<AsyncValue<QrOrderModel?>>(
      _activeOrderForTableProvider(widget.tableId),
      (previous, next) {
        final order = next.valueOrNull;
        if (order == null || _activeOrderPromptShown) return;
        // Already in add-order mode for this exact order (e.g. came back
        // from "Add Order" on the tracker screen) — nothing to prompt.
        if (ref.read(addOrderModeProvider)?.orderId == order.id) return;
        _activeOrderPromptShown = true;
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _showActiveOrderDialog(order));
      },
    );

    return tableInfoAsync.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        body: Center(child: Text('Error loading table: $e')),
      ),
      data: (tableData) {
        final branchId = (tableData?['branch_id'] as String?)?.trim() ?? '';

        if (branchId.isEmpty) {
          return const Scaffold(
            body: Center(child: Text('Branch ID not found for this table')),
          );
        }

        final branch = tableData?['branches'] as Map<String, dynamic>?;
        final branchName = branch?['name'] as String? ?? 'Restaurant';
        final tableName = (tableData?['table_number'] as String?) ?? 'Table';

        // Gate ordering on the table's real status — the staff app already
        // enforces this structurally (MenuItemSelector's table dropdown only
        // ever lists available tables), QR ordering had no equivalent check
        // at all since there's no dropdown to filter, just whichever QR was
        // scanned. 'occupied' is deliberately NOT gated here — that case is
        // already handled by the active-order-for-table dialog below (join
        // the existing order / view its status), which is more specific.
        final tableStatus =
            TableStatusExt.fromString(tableData?['status'] as String? ?? 'available');
        if (tableStatus == TableStatus.cleaning || tableStatus == TableStatus.reserved) {
          return _TableNotReadyScreen(
            tableId: widget.tableId,
            tableName: tableName,
            status: tableStatus,
          );
        }

        // Save data to activeQrTableProvider
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

// ─── Table Not Ready Screen ────────────────────────────────────────────────────
// Shown instead of the menu when the scanned table's status is 'cleaning' or
// 'reserved' — the customer can flag staff instead of silently being allowed
// to order. See supabase/migrations/20260803040000_table_status_gate_and_anon_lockdown.sql.
class _TableNotReadyScreen extends ConsumerStatefulWidget {
  final String tableId;
  final String tableName;
  final TableStatus status;

  const _TableNotReadyScreen({
    required this.tableId,
    required this.tableName,
    required this.status,
  });

  @override
  ConsumerState<_TableNotReadyScreen> createState() => _TableNotReadyScreenState();
}

class _TableNotReadyScreenState extends ConsumerState<_TableNotReadyScreen> {
  bool _reporting = false;
  bool _reported = false;

  bool get _isCleaning => widget.status == TableStatus.cleaning;

  Future<void> _reportIssue() async {
    setState(() => _reporting = true);
    try {
      await ref.read(qrOrderRepositoryProvider).reportTableIssue(widget.tableId);
      if (mounted) setState(() { _reported = true; _reporting = false; });
    } catch (e) {
      if (mounted) {
        setState(() => _reporting = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to notify staff: $e'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final color = widget.status.color;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _isCleaning ? Icons.cleaning_services_rounded : Icons.event_seat_rounded,
                    color: color,
                    size: 40,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Table ${widget.tableName}',
                  style: theme.textTheme.titleMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                Text(
                  _isCleaning ? 'This table is still being cleaned' : 'This table is reserved',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Text(
                  _isCleaning
                      ? 'Please wait for staff to finish preparing this table before ordering. '
                        "If it actually looks ready, let staff know and they'll update it."
                      : 'This table is reserved for another booking. If this is your reservation, '
                        'please let our staff know so they can seat you.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 32),
                if (_reported)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.green.shade300),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_outline, color: Colors.green.shade700, size: 20),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Staff notified — thanks!',
                            style: TextStyle(color: Colors.green.shade700, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _reporting ? null : _reportIssue,
                      icon: _reporting
                          ? const SizedBox(
                              width: 16, height: 16,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.campaign_outlined),
                      label: Text(_reporting ? 'Notifying...' : 'Notify Staff'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: colorScheme.primary,
                        foregroundColor: colorScheme.onPrimary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: () {
                    ref.invalidate(_tableInfoProvider(widget.tableId));
                  },
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Check again'),
                ),
              ],
            ),
          ),
        ),
      ),
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

    final addMode = ref.watch(addOrderModeProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Column(
        children: [
          _QrMenuHeader(
            tableName: tableName,
            branchName: branchName,
            searchCtrl: searchCtrl,
            onSearchChanged: (q) => ref.read(_searchQueryProvider.notifier).state = q,
            addOrderQueueNumber: addMode?.queueNumber,
          ),
          Expanded(
            child: menuAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.wifi_off_outlined, size: 48),
                  const SizedBox(height: 12),
                  Text('Failed to load menu: $e'),
                  ElevatedButton(
                    onPressed: () => ref.invalidate(_menuDataProvider(branchId)),
                    child: const Text('Try Again'),
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
              child: _CartFab(
                cart: cart,
                tableId: tableId,
                tableName: tableName,
                isAddMode: addMode != null,
              ),
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
    final all = ['All', ...categories];

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
            child: Text('CATEGORIES', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
          ),
          ...all.map((label) {
            final isActive = selected == (label == 'All' ? null : label);
            return GestureDetector(
              onTap: () => onSelect(label == 'All' ? null : label),
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
    final allCategories = ['All', ...categories];
    final cs = Theme.of(context).colorScheme;

    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: allCategories.length,
        itemBuilder: (context, index) {
          final label = allCategories[index];
          final isActive = selected == (label == 'All' ? null : label);
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              selected: isActive,
              label: Text(label),
              onSelected: (_) => onSelect(label == 'All' ? null : label),
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
            Text('No menu items found'),
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
                        child: Text('Sold Out', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
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
                  const SizedBox(height: 5),
                  _MenuItemBadges(item: item, cs: cs),
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
                    child: Text('Sold Out', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, fontWeight: FontWeight.w500)),
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
                              Text('Add', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onPrimary)),
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

// ─── Menu Item Badges (prep time, dietary, allergen) ─────────────────────────
class _MenuItemBadges extends StatelessWidget {
  final MenuItem item;
  final ColorScheme cs;

  const _MenuItemBadges({required this.item, required this.cs});

  @override
  Widget build(BuildContext context) {
    final hasInfo = item.dietaryTags.isNotEmpty ||
        item.allergens.isNotEmpty ||
        item.preparationTimeMinutes > 0;

    if (!hasInfo) return const SizedBox.shrink();

    return Wrap(
      spacing: 4,
      runSpacing: 3,
      children: [
        // Prep time
        if (item.preparationTimeMinutes > 0)
          _Badge(
            label: '~${item.preparationTimeMinutes} min',
            icon: Icons.schedule_outlined,
            color: cs.onSurfaceVariant,
            bg: cs.surfaceContainerHighest,
          ),
        // Dietary tags (green)
        ...item.dietaryTags.map((tag) => _Badge(
              label: tag,
              color: Colors.green[700]!,
              bg: Colors.green.withValues(alpha: 0.10),
            )),
        // Allergens (orange) — max 2, rest as "+N"
        ...item.allergens.take(2).map((a) => _Badge(
              label: a,
              icon: Icons.warning_amber_rounded,
              color: Colors.orange[800]!,
              bg: Colors.orange.withValues(alpha: 0.10),
            )),
        if (item.allergens.length > 2)
          _Badge(
            label: '+${item.allergens.length - 2} allergen',
            color: Colors.orange[800]!,
            bg: Colors.orange.withValues(alpha: 0.10),
          ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color color;
  final Color bg;

  const _Badge({required this.label, this.icon, required this.color, required this.bg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 10, color: color),
            const SizedBox(width: 2),
          ],
          Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
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
  final String? addOrderQueueNumber;

  const _QrMenuHeader({
    required this.tableName,
    required this.branchName,
    required this.searchCtrl,
    required this.onSearchChanged,
    this.addOrderQueueNumber,
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
              if (addOrderQueueNumber != null) ...[
                // Add-to-order banner
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.add_circle_outline, size: 14, color: cs.onPrimary),
                    const SizedBox(width: 6),
                    Text(
                      'Add to order #$addOrderQueueNumber',
                      style: TextStyle(
                        color: cs.onPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 6),
              ],
              Text(
                addOrderQueueNumber != null
                    ? 'Select the items you want to add'
                    : 'Choose your favorite menu',
                style: theme.textTheme.headlineSmall?.copyWith(
                    color: cs.onPrimary, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: searchCtrl,
                onChanged: onSearchChanged,
                style: theme.textTheme.bodyMedium,
                decoration: InputDecoration(
                  hintText: 'Search for food or drinks...',
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
  final bool isAddMode;

  const _CartFab({
    required this.cart,
    required this.tableId,
    required this.tableName,
    required this.isAddMode,
  });

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
          Text('Cart', style: theme.textTheme.labelLarge?.copyWith(color: cs.onPrimary, fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Container(width: 1, height: 16, color: cs.onPrimary.withValues(alpha: 0.4)),
          const SizedBox(width: 8),
          // In add mode: show only the new items' subtotal (not total+tax)
          Text(
            isAddMode ? _fmt(cart.subtotal) : _fmt(cart.totalAmount),
            style: theme.textTheme.labelLarge?.copyWith(color: cs.onPrimary, fontWeight: FontWeight.bold),
          ),
        ]),
      ),
    );
  }

  String _fmt(double p) => 'Rp ${p.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}';
}