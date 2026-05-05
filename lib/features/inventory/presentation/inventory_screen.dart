// lib/features/inventory/presentation/inventory_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/inventory_provider.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../shared/widgets/app_drawer.dart';
import 'widgets/inventory_card.dart';
import 'widgets/add_inventory_form.dart';

class InventoryScreen extends ConsumerWidget {
  const InventoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branchId = ref.watch(currentBranchIdProvider) ?? '';
    return _InventoryScreenContent(branchId: branchId);
  }
}

class _InventoryScreenContent extends ConsumerStatefulWidget {
  final String branchId;
  const _InventoryScreenContent({required this.branchId});

  @override
  ConsumerState<_InventoryScreenContent> createState() =>
      _InventoryScreenContentState();
}

class _InventoryScreenContentState
    extends ConsumerState<_InventoryScreenContent> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _openAddItem() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddInventoryForm(branchId: widget.branchId),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      drawer: const AppDrawer(),
      body: NestedScrollView(
        headerSliverBuilder: (_, __) => [
          _InventoryAppBar(branchId: widget.branchId, onAdd: _openAddItem),
        ],
        body: Column(
          children: [
            _SummaryBanner(branchId: widget.branchId),
            _SearchFilterBar(
              searchCtrl: _searchCtrl,
              branchId: widget.branchId,
            ),
            _CategoryFilterTabs(branchId: widget.branchId),
            _DateSelector(),
            Expanded(child: _InventoryGrid(branchId: widget.branchId)),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddItem,
        icon: const Icon(Icons.add),
        label: const Text('Tambah Item',
            style: TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }
}

// ─── APP BAR ──────────────────────────────────────────────────────────────────

class _InventoryAppBar extends ConsumerWidget {
  final String branchId;
  final VoidCallback onAdd;

  const _InventoryAppBar({required this.branchId, required this.onAdd});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final lowCount = ref.watch(lowStockCountProvider(branchId));

    return SliverAppBar(
      expandedHeight: 120,
      floating: true,
      snap: true,
      pinned: true,
      backgroundColor: colorScheme.surface,
      surfaceTintColor: colorScheme.primary,
      flexibleSpace: FlexibleSpaceBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Inventory',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
            ),
            if (lowCount > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red.shade500,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$lowCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ],
        ),
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                colorScheme.tertiaryContainer.withValues(alpha: 0.5),
                colorScheme.surface,
              ],
            ),
          ),
        ),
      ),
      actions: [
        IconButton(
          onPressed: () =>
              ref.read(inventoryNotifierProvider.notifier).refresh(),
          icon: const Icon(Icons.refresh, color: Colors.white),
          tooltip: 'Refresh',
        ),
        IconButton(
          onPressed: () => _showRolloverDialog(context, ref),
          icon: const Icon(Icons.date_range_outlined, color: Colors.white),
          tooltip: 'Rollover Harian',
        ),
        IconButton(
          onPressed: onAdd,
          icon: const Icon(Icons.add_circle_outline, color: Colors.white),
          tooltip: 'Tambah Item',
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  void _showRolloverDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Rollover Stok Harian'),
        content: const Text(
          'Stok akhir hari ini akan dijadikan stok awal untuk besok. Lanjutkan?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              await ref
                  .read(inventoryNotifierProvider.notifier)
                  .rolloverDaily();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('✅ Rollover berhasil'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            child: const Text('Rollover'),
          ),
        ],
      ),
    );
  }
}

// ─── SUMMARY BANNER ───────────────────────────────────────────────────────────

class _SummaryBanner extends ConsumerWidget {
  final String branchId;
  const _SummaryBanner({required this.branchId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(inventorySummaryProvider(branchId));
    final colorScheme = Theme.of(context).colorScheme;

    if (summary == null) return const SizedBox.shrink();

    String fmtCurrency(double v) {
      if (v >= 1000000) return 'Rp ${(v / 1000000).toStringAsFixed(1)}jt';
      if (v >= 1000) return 'Rp ${(v / 1000).toStringAsFixed(0)}rb';
      return 'Rp ${v.toInt()}';
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colorScheme.primaryContainer.withValues(alpha: 0.7),
            colorScheme.secondaryContainer.withValues(alpha: 0.4),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          _SummaryTile(
            label: 'Total Item',
            value: '${summary.totalItems}',
            icon: Icons.inventory_2_outlined,
            color: colorScheme.primary,
          ),
          _VerticalDivider(),
          _SummaryTile(
            label: 'Low Stock',
            value: '${summary.lowStockItems}',
            icon: Icons.warning_amber_rounded,
            color: Colors.orange.shade600,
          ),
          _VerticalDivider(),
          _SummaryTile(
            label: 'Habis',
            value: '${summary.outOfStockItems}',
            icon: Icons.remove_circle_outline,
            color: Colors.red.shade500,
          ),
          _VerticalDivider(),
          _SummaryTile(
            label: 'Nilai Stok',
            value: fmtCurrency(summary.totalInventoryValue),
            icon: Icons.account_balance_wallet_outlined,
            color: Colors.green.shade600,
          ),
        ],
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _SummaryTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 3),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55),
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _VerticalDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 36,
      color:
          Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
    );
  }
}

// ─── SEARCH & FILTER ──────────────────────────────────────────────────────────

class _SearchFilterBar extends ConsumerWidget {
  final TextEditingController searchCtrl;
  final String branchId;

  const _SearchFilterBar(
      {required this.searchCtrl, required this.branchId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final filter = ref.watch(inventoryFilterProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: searchCtrl,
              onChanged: (v) => ref.read(inventoryFilterProvider.notifier).update(
                    (s) => s.copyWith(searchQuery: v),
                  ),
              decoration: InputDecoration(
                hintText: 'Cari bahan / item...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: ValueListenableBuilder(
                  valueListenable: searchCtrl,
                  builder: (_, v, __) => v.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            searchCtrl.clear();
                            ref.read(inventoryFilterProvider.notifier).update(
                                  (s) => s.copyWith(searchQuery: ''),
                                );
                          },
                        )
                      : const SizedBox.shrink(),
                ),
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Low stock filter toggle
          Tooltip(
            message: filter.showLowStockOnly == true
                ? 'Tampilkan semua'
                : 'Hanya stok rendah',
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                color: filter.showLowStockOnly == true
                    ? Colors.orange.shade500
                    : colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: IconButton(
                onPressed: () {
                  final isFiltered = filter.showLowStockOnly == true;
                  ref.read(inventoryFilterProvider.notifier).update(
                        (s) => s.copyWith(
                          showLowStockOnly: isFiltered ? null : true,
                        ),
                      );
                },
                icon: Icon(
                  Icons.warning_amber_rounded,
                  color: filter.showLowStockOnly == true
                      ? Colors.white
                      : colorScheme.onSurface,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── CATEGORY TABS ────────────────────────────────────────────────────────────

class _CategoryFilterTabs extends ConsumerWidget {
  final String branchId;
  const _CategoryFilterTabs({required this.branchId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final categories = ref.watch(inventoryCategoriesProvider(branchId));
    final filter = ref.watch(inventoryFilterProvider);

    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _CategoryChip(
            label: 'Semua',
            isSelected: filter.category == null,
            colorScheme: colorScheme,
            onTap: () => ref.read(inventoryFilterProvider.notifier).update(
                  (s) => s.copyWith(category: null),
                ),
          ),
          ...categories.map(
            (cat) => Padding(
              padding: const EdgeInsets.only(left: 8),
              child: _CategoryChip(
                label: cat,
                isSelected: filter.category == cat,
                colorScheme: colorScheme,
                onTap: () =>
                    ref.read(inventoryFilterProvider.notifier).update(
                          (s) => s.copyWith(category: cat),
                        ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final ColorScheme colorScheme;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.label,
    required this.isSelected,
    required this.colorScheme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? colorScheme.primary
              : colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isSelected ? colorScheme.onPrimary : colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}

// ─── DATE SELECTOR ────────────────────────────────────────────────────────────

class _DateSelector extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedDate = ref.watch(inventorySelectedDateProvider);
    final colorScheme = Theme.of(context).colorScheme;

    final isToday = _isSameDay(selectedDate, DateTime.now());

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
      child: Row(
        children: [
          Icon(Icons.calendar_today_outlined,
              size: 14,
              color: colorScheme.onSurface.withValues(alpha: 0.5)),
          const SizedBox(width: 6),
          Text(
            isToday ? 'Hari Ini' : _formatDate(selectedDate),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isToday
                  ? colorScheme.primary
                  : colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: selectedDate,
                firstDate: DateTime.now().subtract(const Duration(days: 90)),
                lastDate: DateTime.now(),
              );
              if (picked != null) {
                ref
                    .read(inventorySelectedDateProvider.notifier)
                    .state = picked;
              }
            },
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color:
                    colorScheme.primaryContainer.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'Ganti Tanggal',
                style: TextStyle(
                  fontSize: 10,
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

// ─── INVENTORY GRID ───────────────────────────────────────────────────────────

class _InventoryGrid extends ConsumerWidget {
  final String branchId;
  const _InventoryGrid({required this.branchId});

  int _crossAxisCount(double width) {
    if (width >= 1200) return 5;
    if (width >= 900) return 4;
    if (width >= 600) return 3;
    return 2;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inventoryAsync = ref.watch(filteredInventoryProvider(branchId));

    return inventoryAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                size: 56, color: Colors.red.withValues(alpha: 0.7)),
            const SizedBox(height: 12),
            Text('Gagal memuat inventory',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: () =>
                  ref.invalidate(inventoryStreamProvider(branchId)),
              child: const Text('Coba Lagi'),
            ),
          ],
        ),
      ),
      data: (items) {
        if (items.isEmpty) return const _EmptyInventoryState();

        return LayoutBuilder(
          builder: (context, constraints) => GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: _crossAxisCount(constraints.maxWidth),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.82,
            ),
            itemCount: items.length,
            itemBuilder: (_, i) => InventoryCard(item: items[i]),
          ),
        );
      },
    );
  }
}

class _EmptyInventoryState extends StatelessWidget {
  const _EmptyInventoryState();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: colorScheme.tertiaryContainer.withValues(alpha: 0.4),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.inventory_2_outlined,
              size: 48,
              color: colorScheme.tertiary.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Belum ada data inventory',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'Tambahkan bahan baku dan item\nuntuk mulai melacak stok.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colorScheme.onSurface.withValues(alpha: 0.55),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
