// lib/features/inventory/presentation/inventory_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/inventory_item.dart';
import '../providers/inventory_provider.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../core/models/staff_role.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/staff_shell.dart';
import 'widgets/add_inventory_form.dart';
import 'widgets/inventory_detail_sheet.dart';

class InventoryScreen extends ConsumerWidget {
  const InventoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branchId = ref.watch(currentBranchIdProvider) ?? '';
    final staff = ref.watch(currentStaffProvider);
    final isSuperAdmin = staff?.role == StaffRole.superadmin;

    return _InventoryScreenContent(
      branchId: branchId,
      isSuperAdmin: isSuperAdmin,
    );
  }
}

class _InventoryScreenContent extends ConsumerStatefulWidget {
  final String branchId;
  final bool isSuperAdmin;
  const _InventoryScreenContent({
    required this.branchId,
    required this.isSuperAdmin,
  });

  @override
  ConsumerState<_InventoryScreenContent> createState() =>
      _InventoryScreenContentState();
}

class _InventoryScreenContentState
    extends ConsumerState<_InventoryScreenContent> {
  final _searchCtrl = TextEditingController();

  String? _selectedBranchId;
  List<Map<String, dynamic>> _branches = [];
  String? _selectedItemId;

  @override
  void initState() {
    super.initState();
    if (widget.isSuperAdmin) _loadBranches();
  }

  Future<void> _loadBranches() async {
    try {
      final res = await Supabase.instance.client
          .from('branches')
          .select('id, name')
          .order('name');
      if (!mounted) return;
      setState(() => _branches = List<Map<String, dynamic>>.from(res));
    } catch (_) {}
  }

  void _onBranchChanged(String? branchId) {
    setState(() => _selectedBranchId = branchId);
  }

  /// Effective branchId: superadmin can pick a specific branch or all (null → falls back to their own branchId for widgets that require a branchId)
  String get _effectiveBranchId => _selectedBranchId ?? widget.branchId;

  void _openAddItem() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddInventoryForm(branchId: _effectiveBranchId),
    );
  }

  void _showRolloverDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Daily Stock Rollover',
          style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        content: const Text(
          'Today\'s closing stock will become tomorrow\'s opening stock. Continue?',
          style: TextStyle(fontFamily: 'Poppins'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () async {
              Navigator.pop(context);
              await ref.read(inventoryNotifierProvider.notifier).rolloverDaily();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Rollover successful'),
                    backgroundColor: AppColors.available,
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

  Future<void> _pickDate() async {
    final selectedDate = ref.read(inventorySelectedDateProvider);
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 90)),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      ref.read(inventorySelectedDateProvider.notifier).state = picked;
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inventoryAsync =
        ref.watch(filteredInventoryProvider(_effectiveBranchId));

    return StaffShell(
      pageTitle: 'Inventory Status',
      activeRoute: AppRoutes.inventory,
      topBarActions: _buildTopBarActions(),
      body: Column(
        children: [
          _CategoryTabs(branchId: _effectiveBranchId),
          const Divider(height: 1, color: AppColors.border),
          Expanded(
            child: inventoryAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator(color: AppColors.primary)),
              error: (error, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 48, color: AppColors.accent),
                    const SizedBox(height: 12),
                    const Text('Failed to load inventory',
                      style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
                    const SizedBox(height: 16),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                      onPressed: () =>
                          ref.invalidate(inventoryStreamProvider(_effectiveBranchId)),
                      child: const Text('Try Again'),
                    ),
                  ],
                ),
              ),
              data: (items) {
                if (items.isEmpty) return const _EmptyInventoryState();

                InventoryItem? selected;
                if (_selectedItemId != null) {
                  for (final i in items) {
                    if (i.id == _selectedItemId) selected = i;
                  }
                }
                selected ??= items.firstWhere(
                  (i) => i.isLowStock || i.isOutOfStock,
                  orElse: () => items.first,
                );

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: ListView.separated(
                        padding: const EdgeInsets.only(bottom: 24),
                        itemCount: items.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, color: AppColors.border),
                        itemBuilder: (_, i) => _ItemRow(
                          item: items[i],
                          isSelected: items[i].id == selected!.id,
                          onTap: () => setState(() => _selectedItemId = items[i].id),
                        ),
                      ),
                    ),
                    const VerticalDivider(width: 1, color: AppColors.border),
                    SizedBox(
                      width: 380,
                      child: _DetailPanel(item: selected),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildTopBarActions() {
    final lowCount = ref.watch(lowStockCountProvider(_effectiveBranchId));
    final filter = ref.watch(inventoryFilterProvider);
    final selectedDate = ref.watch(inventorySelectedDateProvider);
    final isToday = _isSameDay(selectedDate, DateTime.now());

    return [
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
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('All Branches',
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 12))),
                  ..._branches.map((b) => DropdownMenuItem<String?>(
                        value: b['id'] as String,
                        child: Text(b['name'] as String,
                            style: const TextStyle(fontFamily: 'Poppins', fontSize: 12)))),
                ],
                onChanged: _onBranchChanged,
              ),
            ),
          ),
        ),
      // ── Search ──
      SizedBox(
        width: 220,
        height: 38,
        child: TextField(
          controller: _searchCtrl,
          onChanged: (v) => ref
              .read(inventoryFilterProvider.notifier)
              .update((s) => s.copyWith(searchQuery: v)),
          style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Search stock...',
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
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
        ),
      ),
      const SizedBox(width: 8),
      // ── Low-stock filter toggle ──
      Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            decoration: BoxDecoration(
              color: filter.showLowStockOnly == true
                  ? AppColors.accent
                  : AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              border: Border.all(
                color: filter.showLowStockOnly == true
                    ? AppColors.accent
                    : AppColors.border),
            ),
            child: IconButton(
              tooltip: filter.showLowStockOnly == true ? 'Show all' : 'Low stock only',
              icon: Icon(Icons.filter_alt_outlined,
                color: filter.showLowStockOnly == true ? Colors.white : AppColors.textPrimary),
              onPressed: () {
                final isFiltered = filter.showLowStockOnly == true;
                ref.read(inventoryFilterProvider.notifier).update(
                    (s) => s.copyWith(showLowStockOnly: isFiltered ? null : true));
              },
            ),
          ),
          if (lowCount > 0)
            Positioned(
              top: -4, right: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                  border: Border.all(color: AppColors.surface, width: 1.5),
                ),
                child: Text('$lowCount',
                  style: const TextStyle(
                    fontFamily: 'Poppins', fontSize: 9,
                    fontWeight: FontWeight.w800, color: Colors.white)),
              ),
            ),
        ],
      ),
      const SizedBox(width: 8),
      // ── Date selector ──
      GestureDetector(
        onTap: _pickDate,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.calendar_today_outlined, size: 13, color: AppColors.textSecondary),
            const SizedBox(width: 6),
            Text(isToday ? 'Today' : _formatDate(selectedDate),
              style: TextStyle(
                fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w600,
                color: isToday ? AppColors.textPrimary : AppColors.primary)),
          ]),
        ),
      ),
      IconButton(
        tooltip: 'Daily Rollover',
        icon: const Icon(Icons.date_range_outlined, color: AppColors.textSecondary),
        onPressed: _showRolloverDialog,
      ),
      IconButton(
        tooltip: 'Refresh',
        icon: const Icon(Icons.refresh_rounded, color: AppColors.textSecondary),
        onPressed: () => ref.read(inventoryNotifierProvider.notifier).refresh(),
      ),
      Padding(
        padding: const EdgeInsets.only(left: 4),
        child: FilledButton.icon(
          onPressed: _openAddItem,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm)),
          ),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add Item',
            style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 13)),
        ),
      ),
    ];
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

// ─── CATEGORY TABS ────────────────────────────────────────────────────────────

class _CategoryTabs extends ConsumerWidget {
  final String branchId;
  const _CategoryTabs({required this.branchId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(inventoryCategoriesProvider(branchId));
    final filter = ref.watch(inventoryFilterProvider);

    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          _TabItem(
            label: 'All Items',
            isSelected: filter.category == null,
            onTap: () => ref
                .read(inventoryFilterProvider.notifier)
                .update((s) => s.copyWith(category: null)),
          ),
          ...categories.map((cat) => _TabItem(
                label: cat,
                isSelected: filter.category == cat,
                onTap: () => ref
                    .read(inventoryFilterProvider.notifier)
                    .update((s) => s.copyWith(category: cat)),
              )),
        ],
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  const _TabItem({required this.label, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 28),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isSelected ? AppColors.primary : Colors.transparent,
              width: 2.5),
          ),
        ),
        child: Text(label.toUpperCase(),
          style: TextStyle(
            fontFamily: 'Poppins', fontSize: 12, letterSpacing: 0.4,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
            color: isSelected ? AppColors.primary : AppColors.textSecondary)),
      ),
    );
  }
}

// ─── ITEM ROW ─────────────────────────────────────────────────────────────────

class _ItemRow extends StatelessWidget {
  final InventoryItem item;
  final bool isSelected;
  final VoidCallback onTap;
  const _ItemRow({required this.item, required this.isSelected, required this.onTap});

  IconData _iconFor(String category) {
    final c = category.toLowerCase();
    if (c.contains('produce') || c.contains('veg') || c.contains('sayur')) return Icons.eco_outlined;
    if (c.contains('protein') || c.contains('meat') || c.contains('daging') || c.contains('ayam')) {
      return Icons.set_meal_outlined;
    }
    if (c.contains('dry') || c.contains('kering')) return Icons.rice_bowl_outlined;
    if (c.contains('dairy') || c.contains('susu')) return Icons.icecream_outlined;
    if (c.contains('condiment') || c.contains('bumbu') || c.contains('sauce')) {
      return Icons.liquor_outlined;
    }
    if (c.contains('beverage') || c.contains('minuman')) return Icons.local_bar_outlined;
    return Icons.inventory_2_outlined;
  }

  String _fmtQty(double v) =>
      v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final isOut = item.isOutOfStock;
    final isLow = item.isLowStock;
    final warn = isOut || isLow;

    return InkWell(
      onTap: onTap,
      child: Container(
        color: isSelected ? AppColors.primary.withValues(alpha: 0.07) : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44, height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: warn
                    ? AppColors.accent.withValues(alpha: 0.10)
                    : AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                border: warn ? Border.all(color: AppColors.accent.withValues(alpha: 0.4)) : null,
              ),
              child: Icon(
                warn ? Icons.warning_amber_rounded : _iconFor(item.category),
                size: 22,
                color: warn ? AppColors.accent : AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.name,
                    style: const TextStyle(
                      fontFamily: 'Poppins', fontSize: 16,
                      fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  const SizedBox(height: 3),
                  Text(
                    item.category,
                    style: const TextStyle(
                      fontFamily: 'Poppins', fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(_fmtQty(item.availableStock),
                      style: TextStyle(
                        fontFamily: 'Poppins', fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: isOut
                            ? AppColors.accent
                            : isLow ? AppColors.accentOrange : AppColors.textPrimary)),
                    const SizedBox(width: 4),
                    Text(item.unit,
                      style: const TextStyle(
                        fontFamily: 'Poppins', fontSize: 13, color: AppColors.textSecondary)),
                  ],
                ),
                if (isLow || isOut) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    ),
                    child: Text(
                      isOut
                          ? 'OUT OF STOCK'
                          : 'LOW STOCK (MIN ${_fmtQty(item.minimumStock)}${item.unit.toUpperCase()})',
                      style: const TextStyle(
                        fontFamily: 'Poppins', fontSize: 9,
                        fontWeight: FontWeight.w800, letterSpacing: 0.2, color: AppColors.accent)),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── DETAIL PANEL ─────────────────────────────────────────────────────────────

class _DetailPanel extends ConsumerWidget {
  final InventoryItem item;
  const _DetailPanel({required this.item});

  String _fmtQty(double v) =>
      v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOut = item.isOutOfStock;
    final isLow = item.isLowStock;
    final warn = isOut || isLow;
    final statusColor = isOut
        ? AppColors.accent
        : isLow ? AppColors.accentOrange : AppColors.available;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 56, height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                ),
                child: Icon(
                  warn ? Icons.warning_amber_rounded : Icons.check_circle_outline_rounded,
                  color: statusColor, size: 28),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Edit',
                icon: const Icon(Icons.edit_outlined, color: AppColors.textSecondary),
                onPressed: () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => AddInventoryForm(branchId: item.branchId, editItem: item),
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded, color: AppColors.textSecondary),
                onSelected: (v) {
                  if (v == 'manage') {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) => InventoryDetailSheet(item: item),
                    );
                  } else if (v == 'delete') {
                    _showDeleteDialog(context, ref);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'manage',
                    child: Text('Manage Stock (Purchase / Waste / Transfer)')),
                  PopupMenuItem(value: 'delete',
                    child: Text('Delete Item', style: TextStyle(color: Colors.red))),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(item.name,
            style: const TextStyle(
              fontFamily: 'Poppins', fontSize: 24,
              fontWeight: FontWeight.w800, color: AppColors.textPrimary, height: 1.15)),
          const SizedBox(height: 4),
          Text('ID: ${item.id.length > 8 ? item.id.substring(0, 8).toUpperCase() : item.id.toUpperCase()} • ${item.category}',
            style: const TextStyle(
              fontFamily: 'Poppins', fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _StatTile(
                  label: 'Current Stock',
                  value: '${_fmtQty(item.availableStock)} ${item.unit}',
                  color: statusColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatTile(
                  label: 'Minimum Level',
                  value: '${_fmtQty(item.minimumStock)} ${item.unit}',
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _showRestockDialog(context, ref),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm)),
              ),
              icon: const Icon(Icons.shopping_cart_outlined, size: 18),
              label: const Text('ORDER RESTOCK',
                style: TextStyle(
                  fontFamily: 'Poppins', fontWeight: FontWeight.w800,
                  fontSize: 13, letterSpacing: 0.4)),
            ),
          ),
          const SizedBox(height: 24),
          const Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 16),
          const Text('RECENT ACTIVITY',
            style: TextStyle(
              fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w800,
              letterSpacing: 0.6, color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          _RecentActivityList(item: item),
        ],
      ),
    );
  }

  void _showRestockDialog(BuildContext context, WidgetRef ref) {
    final qtyCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Order Restock — ${item.name}',
          style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        content: TextField(
          controller: qtyCtrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Quantity (${item.unit})',
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () async {
              final qty = double.tryParse(qtyCtrl.text);
              if (qty == null || qty <= 0) return;
              Navigator.pop(context);
              await ref.read(inventoryNotifierProvider.notifier).recordPurchase(
                    itemId: item.id, quantity: qty, note: 'Restock order');
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Restock recorded'),
                    backgroundColor: AppColors.available,
                  ),
                );
              }
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(BuildContext context, WidgetRef ref) {
    if (item.availableStock > 0) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Cannot Be Deleted'),
          content: Text(
            'Item "${item.name}" still has ${_fmtQty(item.availableStock)} ${item.unit} in stock. Clear the stock first.'),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK')),
          ],
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Item'),
        content: Text('Are you sure you want to delete "${item.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(context);
              await Supabase.instance.client
                  .from('inventory_items')
                  .delete()
                  .eq('id', item.id);
              ref.invalidate(inventoryStreamProvider(item.branchId));
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatTile({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
            style: const TextStyle(
              fontFamily: 'Poppins', fontSize: 9, fontWeight: FontWeight.w700,
              letterSpacing: 0.4, color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          Text(value,
            style: TextStyle(
              fontFamily: 'Poppins', fontSize: 18, fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }
}

class _RecentActivityList extends ConsumerWidget {
  final InventoryItem item;
  const _RecentActivityList({required this.item});

  String _fmtQty(double v) =>
      v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

  String _label(InventoryTransaction t) {
    final qty = _fmtQty(t.quantity);
    switch (t.type) {
      case 'purchase': return '+$qty ${item.unit} Restock Delivered';
      case 'order_deduct': return '-$qty ${item.unit} Used in Kitchen';
      case 'waste': return '-$qty ${item.unit} Wasted';
      case 'adjustment': return '${t.quantity >= 0 ? '+' : ''}$qty ${item.unit} Adjusted';
      case 'transfer_out': return '-$qty ${item.unit} Transferred Out';
      case 'transfer_in': return '+$qty ${item.unit} Transferred In';
      default: return '$qty ${item.unit} ${t.type}';
    }
  }

  Color _color(String type) {
    switch (type) {
      case 'purchase':
      case 'transfer_in':
        return AppColors.available;
      case 'order_deduct':
        return AppColors.accentOrange;
      case 'waste':
      case 'transfer_out':
        return AppColors.accent;
      default:
        return AppColors.textSecondary;
    }
  }

  String _formatWhen(DateTime dt) {
    final now = DateTime.now();
    final isToday = dt.year == now.year && dt.month == now.month && dt.day == now.day;
    final yesterday = now.subtract(const Duration(days: 1));
    final isYesterday =
        dt.year == yesterday.year && dt.month == yesterday.month && dt.day == yesterday.day;
    final time =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    if (isToday) return 'Today, $time';
    if (isYesterday) return 'Yesterday, $time';
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[dt.month - 1]} ${dt.day}, $time';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txAsync = ref.watch(inventoryTransactionsProvider(item.id));

    return txAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)),
      ),
      error: (_, __) => const Text('Failed to load activity',
        style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: AppColors.textSecondary)),
      data: (transactions) {
        if (transactions.isEmpty) {
          return const Text('No activity recorded yet.',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: AppColors.textSecondary));
        }
        final recent = transactions.take(6).toList();
        return Column(
          children: List.generate(recent.length, (i) {
            final t = recent[i];
            final isLast = i == recent.length - 1;
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    children: [
                      Container(
                        width: 10, height: 10,
                        margin: const EdgeInsets.only(top: 4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i == 0 ? _color(t.type) : Colors.transparent,
                          border: Border.all(color: _color(t.type), width: 1.6),
                        ),
                      ),
                      if (!isLast)
                        Expanded(
                          child: Container(width: 1.4, color: AppColors.border),
                        ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_label(t),
                            style: const TextStyle(
                              fontFamily: 'Poppins', fontSize: 13,
                              fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                          const SizedBox(height: 2),
                          Text(
                            [
                              _formatWhen(t.createdAt),
                              if (t.note != null && t.note!.isNotEmpty) t.note!,
                            ].join(' • '),
                            style: const TextStyle(
                              fontFamily: 'Poppins', fontSize: 11, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        );
      },
    );
  }
}

// ─── EMPTY STATE ──────────────────────────────────────────────────────────────

class _EmptyInventoryState extends StatelessWidget {
  const _EmptyInventoryState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 96, height: 96,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.inventory_2_outlined, size: 48, color: AppColors.primary),
          ),
          const SizedBox(height: 20),
          const Text('No inventory data yet',
            style: TextStyle(
              fontFamily: 'Poppins', fontSize: 18,
              fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          const Text('Add raw materials and items\nto start tracking stock.',
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Poppins', color: AppColors.textSecondary, height: 1.5)),
        ],
      ),
    );
  }
}
