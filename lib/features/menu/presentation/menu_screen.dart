// lib/features/menu/presentation/menu_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/menu_provider.dart';
import '../../../shared/models/menu_model.dart';
import 'widgets/add_menu_form.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../core/models/staff_role.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/staff_shell.dart';

class MenuScreen extends ConsumerWidget {
  const MenuScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branchId = ref.watch(currentBranchIdProvider) ?? '';
    final staff = ref.watch(currentStaffProvider);
    final isSuperAdmin = staff?.role == StaffRole.superadmin;

    return _MenuScreenContent(
      branchId: branchId,
      isSuperAdmin: isSuperAdmin,
    );
  }
}

class _MenuScreenContent extends ConsumerStatefulWidget {
  final String branchId;
  final bool isSuperAdmin;
  const _MenuScreenContent({
    required this.branchId,
    required this.isSuperAdmin,
  });

  @override
  ConsumerState<_MenuScreenContent> createState() => _MenuScreenContentState();
}

class _MenuScreenContentState extends ConsumerState<_MenuScreenContent> {
  final _searchCtrl = TextEditingController();

  String? _selectedBranchId;
  List<Map<String, dynamic>> _branches = [];

  @override
  void initState() {
    super.initState();
    if (widget.isSuperAdmin) {
      _loadBranches();
    } else {
      // Non-superadmin: set the filter directly to their own branch
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(menuFilterProvider.notifier).update(
              (s) => s.copyWith(branchId: widget.branchId),
            );
      });
    }
  }

  Future<void> _loadBranches() async {
    try {
      final res = await Supabase.instance.client
          .from('branches')
          .select('id, name')
          .order('name');
      if (!mounted) return;

      final branches = List<Map<String, dynamic>>.from(res);
      setState(() {
        _branches = branches;
      });

      // ── FIX REFRESH BUG ──────────────────────────────────────────────────
      // After branches are loaded, check whether the provider already has a
      // filter. If not (e.g. after a refresh), auto-select the first branch
      // so the menu doesn't render blank.
      final currentFilter = ref.read(menuFilterProvider);
      if (currentFilter.branchId == null && branches.isNotEmpty) {
        final firstBranchId = branches.first['id'] as String;
        setState(() => _selectedBranchId = firstBranchId);
        ref.read(menuFilterProvider.notifier).update(
              (s) => s.copyWith(branchId: firstBranchId),
            );
      } else if (currentFilter.branchId != null) {
        // The provider already has a filter (e.g. user picked one before),
        // sync it back to local state so the dropdown doesn't reset to null
        setState(() => _selectedBranchId = currentFilter.branchId);
      }
      // ─────────────────────────────────────────────────────────────────────
    } catch (_) {}
  }

  void _onBranchChanged(String? branchId) {
    setState(() => _selectedBranchId = branchId);
    ref.read(menuFilterProvider.notifier).update(
          (s) => s.copyWith(
            branchId: branchId,
            // reset category when switching branch
            clearCategory: true,
          ),
        );
  }

  /// Effective branchId for widgets that need an explicit branchId
  /// (AddMenuForm, CategoryTabs)
  String get _effectiveBranchId => _selectedBranchId ?? widget.branchId;

  void _openAddMenu() {
    // If superadmin hasn't picked a branch yet, don't open the form
    if (widget.isSuperAdmin && _effectiveBranchId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a branch first.')),
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddMenuForm(branchId: _effectiveBranchId),
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StaffShell(
      pageTitle: 'Menu Items',
      activeRoute: AppRoutes.menu,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddMenu,
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('ADD MENU ITEM',
          style: TextStyle(
            color: Colors.white, fontFamily: 'Poppins',
            fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 0.3)),
      ),
      topBarActions: [
        // ── Branch filter (superadmin only) ──
        if (widget.isSuperAdmin && _branches.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                border: Border.all(color: AppColors.border),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: _selectedBranchId,
                  isDense: true,
                  icon: const Icon(Icons.keyboard_arrow_down,
                      size: 16, color: AppColors.textSecondary),
                  style: const TextStyle(
                      fontFamily: 'Poppins', fontSize: 12, color: AppColors.textPrimary),
                  items: _branches
                      .map((b) => DropdownMenuItem<String?>(
                            value: b['id'] as String,
                            child: Text(b['name'] as String,
                                style: const TextStyle(fontFamily: 'Poppins', fontSize: 12)),
                          ))
                      .toList(),
                  onChanged: _onBranchChanged,
                ),
              ),
            ),
          ),
        IconButton(
          tooltip: 'Refresh',
          icon: const Icon(Icons.refresh_rounded, color: AppColors.textSecondary),
          onPressed: () => ref.read(menuProvider.notifier).refresh(),
        ),
      ],
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Menu Management',
              style: TextStyle(
                fontFamily: 'Poppins', fontSize: 30,
                fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            const SizedBox(height: 4),
            const Text('Manage availability, pricing, and details for all dishes.',
              style: TextStyle(
                fontFamily: 'Poppins', fontSize: 13, color: AppColors.textSecondary)),
            const SizedBox(height: 20),
            _FilterPanel(searchCtrl: _searchCtrl, branchId: _effectiveBranchId),
            const SizedBox(height: 20),
            const _MenuGrid(),
          ],
        ),
      ),
    );
  }
}

// ─── SEARCH + CATEGORY FILTER PANEL ────────────────────────────────────────────

class _FilterPanel extends ConsumerWidget {
  final TextEditingController searchCtrl;
  final String branchId;
  const _FilterPanel({required this.searchCtrl, required this.branchId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(menuFilterProvider);
    final categoriesAsync = ref.watch(categoryNotifierProvider(branchId));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.border),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 320,
            child: TextField(
              controller: searchCtrl,
              onChanged: (v) => ref
                  .read(menuFilterProvider.notifier)
                  .update((s) => s.copyWith(searchQuery: v)),
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search menu items...',
                hintStyle: const TextStyle(
                    fontFamily: 'Poppins', fontSize: 13, color: AppColors.textHint),
                prefixIcon: const Icon(Icons.search, size: 18, color: AppColors.textSecondary),
                filled: true,
                fillColor: AppColors.surfaceVariant,
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
            ),
          ),
          _FilterPill(
            label: 'All',
            isSelected: filter.categoryId == null,
            onTap: () => ref
                .read(menuFilterProvider.notifier)
                .update((s) => s.copyWith(clearCategory: true)),
          ),
          categoriesAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (categories) => Wrap(
              spacing: 10,
              runSpacing: 10,
              children: categories
                  .map((cat) => _FilterPill(
                        label: cat.name,
                        isSelected: filter.categoryId == cat.id,
                        onTap: () => ref
                            .read(menuFilterProvider.notifier)
                            .update((s) => s.copyWith(categoryId: cat.id)),
                      ))
                  .toList(),
            ),
          ),
          _FilterPill(
            label: 'Available',
            isSelected: filter.showAvailableOnly == true,
            onTap: () => ref.read(menuFilterProvider.notifier).update(
                (s) => s.copyWith(
                    showAvailableOnly: filter.showAvailableOnly == true ? null : true)),
          ),
        ],
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  const _FilterPill({required this.label, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.accent : AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          border: Border.all(color: isSelected ? AppColors.accent : AppColors.border),
        ),
        child: Text(label.toUpperCase(),
          style: TextStyle(
            fontFamily: 'Poppins', fontSize: 12, letterSpacing: 0.3,
            fontWeight: FontWeight.w800,
            color: isSelected ? Colors.white : AppColors.textPrimary)),
      ),
    );
  }
}

// ─── MENU GRID ────────────────────────────────────────────────────────────────

class _MenuGrid extends ConsumerWidget {
  const _MenuGrid();

  int _crossAxisCount(double width) {
    if (width >= 1400) return 5;
    if (width >= 1100) return 4;
    if (width >= 780) return 3;
    if (width >= 480) return 2;
    return 1;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final menusAsync = ref.watch(filteredMenuProvider);

    return menusAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.only(top: 60),
        child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      ),
      error: (error, _) => Padding(
        padding: const EdgeInsets.only(top: 40),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppColors.accent),
              const SizedBox(height: 12),
              const Text('Failed to load menu',
                style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                onPressed: () => ref.refresh(menuProvider),
                child: const Text('Try Again'),
              ),
            ],
          ),
        ),
      ),
      data: (menus) {
        if (menus.isEmpty) return const _EmptyState();

        return LayoutBuilder(
          builder: (context, constraints) => GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: _crossAxisCount(constraints.maxWidth),
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 0.78,
            ),
            itemCount: menus.length,
            itemBuilder: (_, i) => _MenuItemCard(menu: menus[i]),
          ),
        );
      },
    );
  }
}

// ─── MENU ITEM CARD ───────────────────────────────────────────────────────────

class _MenuItemCard extends ConsumerStatefulWidget {
  final MenuItem menu;
  const _MenuItemCard({required this.menu});

  @override
  ConsumerState<_MenuItemCard> createState() => _MenuItemCardState();
}

class _MenuItemCardState extends ConsumerState<_MenuItemCard> {
  bool _isToggling = false;

  Future<void> _handleToggle() async {
    if (_isToggling) return;
    setState(() => _isToggling = true);
    final success = await ref
        .read(menuProvider.notifier)
        .toggleAvailability(widget.menu.id, widget.menu.isAvailable);
    if (mounted) {
      setState(() => _isToggling = false);
      if (!success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to change menu status'),
            backgroundColor: AppColors.accent,
          ),
        );
      }
    }
  }

  void _handleEdit() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddMenuForm(existingMenu: widget.menu, branchId: widget.menu.branchId),
    );
  }

  void _handleDelete() {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Menu Item?',
          style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        content: Text('"${widget.menu.name}" will be permanently deleted.',
          style: const TextStyle(fontFamily: 'Poppins')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
            onPressed: () async {
              Navigator.pop(dialogCtx);
              await ref.read(menuProvider.notifier).deleteMenu(widget.menu.id);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  String _fmtPrice(double v) => v.toStringAsFixed(0).replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');

  @override
  Widget build(BuildContext context) {
    final menu = widget.menu;
    final categoriesAsync = ref.watch(categoryNotifierProvider(menu.branchId));
    final categoryName = categoriesAsync.valueOrNull
            ?.where((c) => c.id == menu.categoryId)
            .map((c) => c.name)
            .firstOrNull ??
        'Uncategorized';

    final isOut = !menu.isAvailable;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            children: [
              AspectRatio(
                aspectRatio: 16 / 10,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    (menu.imageUrl != null && menu.imageUrl!.isNotEmpty)
                        ? Image.network(menu.imageUrl!,
                            fit: BoxFit.cover,
                            color: isOut ? Colors.black.withValues(alpha: 0.35) : null,
                            colorBlendMode: isOut ? BlendMode.darken : null,
                            errorBuilder: (_, __, ___) => const _PlaceholderImage())
                        : const _PlaceholderImage(),
                  ],
                ),
              ),
              Positioned(
                top: 10, right: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Text(categoryName.toUpperCase(),
                    style: const TextStyle(
                      fontFamily: 'Poppins', fontSize: 10,
                      fontWeight: FontWeight.w800, letterSpacing: 0.3,
                      color: AppColors.textPrimary)),
                ),
              ),
              Positioned(
                top: 10, left: 10,
                child: Row(children: [
                  _RoundIconButton(icon: Icons.edit_outlined, onTap: _handleEdit),
                  const SizedBox(width: 6),
                  _RoundIconButton(icon: Icons.delete_outline, onTap: _handleDelete,
                    color: Colors.red.shade600),
                ]),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(menu.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Poppins', fontSize: 16,
                    fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                const SizedBox(height: 4),
                Text('Rp ${_fmtPrice(menu.price)}',
                  style: const TextStyle(
                    fontFamily: 'Poppins', fontSize: 14,
                    fontWeight: FontWeight.w700, color: AppColors.primary)),
                const SizedBox(height: 12),
                const Divider(height: 1, color: AppColors.border),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(isOut ? 'SOLD OUT' : 'AVAILABLE',
                      style: TextStyle(
                        fontFamily: 'Poppins', fontSize: 11,
                        fontWeight: FontWeight.w800, letterSpacing: 0.3,
                        color: isOut ? AppColors.accent : AppColors.textPrimary)),
                    _isToggling
                        ? const SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
                        : Switch(
                            value: menu.isAvailable,
                            onChanged: (_) => _handleToggle(),
                            activeThumbColor: Colors.white,
                            activeTrackColor: AppColors.accent,
                            inactiveThumbColor: Colors.white,
                            inactiveTrackColor: AppColors.border,
                          ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color? color;
  const _RoundIconButton({required this.icon, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      child: Container(
        width: 28, height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.92),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 15, color: color ?? AppColors.textSecondary),
      ),
    );
  }
}

class _PlaceholderImage extends StatelessWidget {
  const _PlaceholderImage();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surfaceVariant,
      child: const Icon(Icons.restaurant, size: 32, color: AppColors.textHint),
    );
  }
}

// ─── EMPTY STATE ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 60),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96, height: 96,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.restaurant_menu, size: 48, color: AppColors.primary),
            ),
            const SizedBox(height: 20),
            const Text('No menu items yet',
              style: TextStyle(
                fontFamily: 'Poppins', fontSize: 18,
                fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            const Text('Add your first menu item\nto start receiving orders.',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Poppins', color: AppColors.textSecondary, height: 1.5)),
          ],
        ),
      ),
    );
  }
}
