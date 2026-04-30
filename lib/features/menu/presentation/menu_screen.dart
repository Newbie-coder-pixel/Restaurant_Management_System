// lib/features/menu/presentation/menu_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/menu_provider.dart';
import 'widgets/menu_card.dart';
import 'widgets/add_menu_form.dart';
import '../../../features/auth/providers/auth_provider.dart';

class MenuScreen extends ConsumerWidget {
  const MenuScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branchId = ref.watch(currentBranchIdProvider) ?? '';

    return _MenuScreenContent(branchId: branchId);
  }
}

class _MenuScreenContent extends ConsumerStatefulWidget {
  final String branchId;
  const _MenuScreenContent({required this.branchId});

  @override
  ConsumerState<_MenuScreenContent> createState() => _MenuScreenContentState();
}

class _MenuScreenContentState extends ConsumerState<_MenuScreenContent> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _openAddMenu() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddMenuForm(branchId: widget.branchId),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: NestedScrollView(
        headerSliverBuilder: (_, __) => [
          _MenuAppBar(onAddMenu: _openAddMenu),
        ],
        body: Column(
          children: [
            _SearchFilterBar(searchCtrl: _searchCtrl),
            _CategoryTabs(branchId: widget.branchId),
            const _StatsRow(),
            const Expanded(child: _MenuGrid()),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddMenu,
        icon: const Icon(Icons.add),
        label: const Text('Tambah Menu',
            style: TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }
}

// ─── APP BAR ──────────────────────────────────────────────────────────────────

class _MenuAppBar extends StatelessWidget {
  final VoidCallback onAddMenu;
  const _MenuAppBar({required this.onAddMenu});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SliverAppBar(
      expandedHeight: 120,
      floating: true,
      snap: true,
      pinned: true,
      backgroundColor: colorScheme.surface,
      surfaceTintColor: colorScheme.primary,
      flexibleSpace: FlexibleSpaceBar(
        title: Text(
          'Menu Management',
          style: TextStyle(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w800,
            fontSize: 20,
          ),
        ),
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                colorScheme.primaryContainer.withValues(alpha: 0.5),
                colorScheme.surface,
              ],
            ),
          ),
        ),
      ),
      actions: [
        Consumer(
          builder: (_, ref, __) => IconButton(
            onPressed: () => ref.read(menuProvider.notifier).refresh(),
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ),
        IconButton(
          onPressed: onAddMenu,
          icon: const Icon(Icons.add_circle_outline),
          tooltip: 'Tambah Menu',
        ),
        const SizedBox(width: 8),
      ],
    );
  }
}

// ─── SEARCH & FILTER BAR ──────────────────────────────────────────────────────

class _SearchFilterBar extends ConsumerWidget {
  final TextEditingController searchCtrl;
  const _SearchFilterBar({required this.searchCtrl});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final filter = ref.watch(menuFilterProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: searchCtrl,
              onChanged: (v) => ref.read(menuFilterProvider.notifier).update(
                    (s) => s.copyWith(searchQuery: v),
                  ),
              decoration: InputDecoration(
                hintText: 'Cari menu...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: ValueListenableBuilder(
                  valueListenable: searchCtrl,
                  builder: (_, v, __) => v.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            searchCtrl.clear();
                            ref.read(menuFilterProvider.notifier).update(
                                  (s) => s.copyWith(searchQuery: ''),
                                );
                          },
                        )
                      : const SizedBox.shrink(),
                ),
                filled: true,
                fillColor:
                    colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: filter.showAvailableOnly == true
                ? 'Tampilkan semua'
                : 'Hanya tersedia',
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                color: filter.showAvailableOnly == true
                    ? colorScheme.primary
                    : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: IconButton(
                onPressed: () {
                  final isFiltered = filter.showAvailableOnly == true;
                  ref.read(menuFilterProvider.notifier).update(
                        (s) => s.copyWith(
                          showAvailableOnly: isFiltered ? null : true,
                        ),
                      );
                },
                icon: Icon(
                  Icons.tune,
                  color: filter.showAvailableOnly == true
                      ? colorScheme.onPrimary
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

class _CategoryTabs extends ConsumerWidget {
  final String branchId;
  const _CategoryTabs({required this.branchId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(menuFilterProvider);
    final colorScheme = Theme.of(context).colorScheme;

    final categoriesAsync = ref.watch(menuCategoriesProvider(branchId));
    final counts = ref.watch(menuCountByCategoryProvider);
    final totalCount = counts.values.fold(0, (a, b) => a + b);

    return SizedBox(
      height: 44,
      child: categoriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const SizedBox.shrink(),
        data: (categories) {
          return ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: categories.length + 1,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              if (i == 0) {
                final isSelected = filter.categoryId == null;
                return _categoryChip(
                  context: context,
                  colorScheme: colorScheme,
                  emoji: '🍽️',
                  label: 'Semua',
                  count: totalCount,
                  isSelected: isSelected,
                  onTap: () => ref.read(menuFilterProvider.notifier).update(
                        (s) => s.copyWith(clearCategory: true),
                      ),
                );
              }

              final cat = categories[i - 1];
              final isSelected = filter.categoryId == cat.id;
              final count = counts[cat.id] ?? 0;

              return _categoryChip(
                context: context,
                colorScheme: colorScheme,
                emoji: '🍴',
                label: cat.name,
                count: count,
                isSelected: isSelected,
                onTap: () => ref.read(menuFilterProvider.notifier).update(
                      (s) => s.copyWith(categoryId: cat.id),
                    ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _categoryChip({
    required BuildContext context,
    required ColorScheme colorScheme,
    required String emoji,
    required String label,
    required int count,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? colorScheme.primary
              : colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color:
                    isSelected ? colorScheme.onPrimary : colorScheme.onSurface,
              ),
            ),
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: isSelected
                    ? colorScheme.onPrimary.withValues(alpha: 0.25)
                    : colorScheme.onSurface.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: isSelected
                      ? colorScheme.onPrimary
                      : colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── STATS ROW ────────────────────────────────────────────────────────────────

class _StatsRow extends ConsumerWidget {
  const _StatsRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final menus = ref.watch(menuProvider).valueOrNull ?? [];
    final available = menus.where((m) => m.isAvailable).length;
    final total = menus.length;
    final unavailable = total - available;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Row(
        children: [
          _StatChip(
              label: 'Total', value: '$total', color: Colors.blue.shade400),
          const SizedBox(width: 8),
          _StatChip(
              label: 'Tersedia',
              value: '$available',
              color: Colors.green.shade500),
          const SizedBox(width: 8),
          _StatChip(
              label: 'Habis',
              value: '$unavailable',
              color: Colors.red.shade400),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatChip(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: RichText(
        text: TextSpan(
          style: TextStyle(fontSize: 12, color: color),
          children: [
            TextSpan(
                text: value,
                style: const TextStyle(fontWeight: FontWeight.w800)),
            TextSpan(
                text: ' $label',
                style: TextStyle(color: color.withValues(alpha: 0.8))),
          ],
        ),
      ),
    );
  }
}

// ─── MENU GRID ────────────────────────────────────────────────────────────────

class _MenuGrid extends ConsumerWidget {
  const _MenuGrid();

  int _crossAxisCount(double width) {
    if (width >= 1200) return 5;
    if (width >= 900) return 4;
    if (width >= 600) return 3;
    return 2;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final menusAsync = ref.watch(filteredMenuProvider);

    return menusAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                size: 56, color: Colors.red.withValues(alpha: 0.7)),
            const SizedBox(height: 12),
            Text('Gagal memuat menu',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              error.toString(),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.5),
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: () => ref.refresh(menuProvider),
              child: const Text('Coba Lagi'),
            ),
          ],
        ),
      ),
      data: (menus) {
        if (menus.isEmpty) return const _EmptyState();

        return LayoutBuilder(
          builder: (context, constraints) {
            return GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: _crossAxisCount(constraints.maxWidth),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.72,
              ),
              itemCount: menus.length,
              itemBuilder: (_, i) => MenuCard(menu: menus[i]),
            );
          },
        );
      },
    );
  }
}

// ─── EMPTY STATE ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

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
              color: colorScheme.primaryContainer.withValues(alpha: 0.4),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.restaurant_menu,
              size: 48,
              color: colorScheme.primary.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Belum ada menu',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'Tambahkan menu pertama Anda\nuntuk mulai menerima pesanan.',
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