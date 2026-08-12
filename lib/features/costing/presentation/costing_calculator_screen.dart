// lib/features/costing/presentation/screens/costing_calculator_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models/costing_model.dart';
import '../providers/costing_providers.dart';
import 'costing_widgets.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/staff_shell.dart';
import '../../../shared/models/menu_model.dart';
import '../../menu/providers/menu_provider.dart';
import '../../../core/router/app_router.dart';

// ✅ RIVERPOD: StatefulWidget → ConsumerStatefulWidget
class CostingCalculatorScreen extends ConsumerStatefulWidget {
  final String? menuItemId;
  final String? menuItemName;
  final double? prefillIngredientCost;

  const CostingCalculatorScreen({
    super.key,
    this.menuItemId,
    this.menuItemName,
    this.prefillIngredientCost,
  });

  @override
  ConsumerState<CostingCalculatorScreen> createState() =>
      _CostingCalculatorScreenState();
}

// ✅ RIVERPOD: State<T> → ConsumerState<T>  (can access `ref` directly)
class _CostingCalculatorScreenState extends ConsumerState<CostingCalculatorScreen>
    with SingleTickerProviderStateMixin {
  // ─── Controllers ───────────────────────────────────────────────────────────
  final _menuNameCtrl = TextEditingController();
  final _ingredientCtrl = TextEditingController(text: '0');
  final _packagingCtrl = TextEditingController(text: '0');
  final _allocatedOpCtrl = TextEditingController(text: '0');
  final _currentPriceCtrl = TextEditingController(text: '0');
  final _targetMarginCtrl = TextEditingController(text: '30');

  late TabController _tabController;
  final _formKey = GlobalKey<FormState>();

  // The actual menu item ID being edited (not the costing id).
  // Used in _save() so the costing is genuinely linked to menu_items,
  // instead of generating a random 'custom-...' id every time it's saved.
  String? _selectedMenuItemId;
  bool _isComputingCost = false;
  // Presentational only — the picked MenuItem, kept just so the recipe
  // identity card can show its description when available. Not persisted.
  MenuItem? _pickedMenu;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _selectedMenuItemId = widget.menuItemId;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // ✅ RIVERPOD: context.read<X>() → ref.read(xProvider.notifier)
      final notifier = ref.read(costingProvider.notifier);

      // Init branch filter (superadmin check)
      notifier.init();

      if (widget.menuItemId != null) {
        notifier.loadCostingForMenu(widget.menuItemId!).then((_) {
          // ✅ RIVERPOD: read the current state via ref.read(costingProvider)
          _syncFromState(ref.read(costingProvider));
        });
      } else {
        notifier.clearActiveCosting();
        final opCost = ref.read(costingProvider).operatingExpense.operatingCostPerPortion;
        _allocatedOpCtrl.text = opCost.toStringAsFixed(0);
        notifier.updateLiveAllocatedOpCost(opCost);
      }

      if (widget.prefillIngredientCost != null) {
        _ingredientCtrl.text = widget.prefillIngredientCost!.toStringAsFixed(0);
        notifier.updateLiveIngredientCost(widget.prefillIngredientCost!);
      }

      if (widget.menuItemName != null) {
        _menuNameCtrl.text = widget.menuItemName!;
      }
    });
  }

  // ✅ RIVERPOD: parameter is now CostingState (not CostingProvider)
  void _syncFromState(CostingNotifier state) {
    final c = state.activeCosting;
    _menuNameCtrl.text = c.menuItemName;
    _ingredientCtrl.text = c.ingredientCost.toStringAsFixed(0);
    _packagingCtrl.text = c.packagingCost.toStringAsFixed(0);
    _allocatedOpCtrl.text = c.allocatedOperatingCost.toStringAsFixed(0);
    _currentPriceCtrl.text = c.currentSellingPrice.toStringAsFixed(0);
    _targetMarginCtrl.text = c.targetProfitMarginPercent.toStringAsFixed(0);
    if (c.menuItemId.isNotEmpty) _selectedMenuItemId = c.menuItemId;
  }

  /// Called when the user taps one of the menus in the "Menu List" tab to
  /// edit it. Unlike [_syncFromState]: this is called manually from outside
  /// the listener so the text controllers update as well, even though the
  /// notifier (ChangeNotifier) doesn't trigger a detectable rebuild.
  void _onSelectExistingCosting(CostingModel costing) {
    ref.read(costingProvider.notifier).setActiveCosting(costing);
    setState(() {
      _menuNameCtrl.text = costing.menuItemName;
      _ingredientCtrl.text = costing.ingredientCost.toStringAsFixed(0);
      _packagingCtrl.text = costing.packagingCost.toStringAsFixed(0);
      _allocatedOpCtrl.text = costing.allocatedOperatingCost.toStringAsFixed(0);
      _currentPriceCtrl.text = costing.currentSellingPrice.toStringAsFixed(0);
      _targetMarginCtrl.text = costing.targetProfitMarginPercent.toStringAsFixed(0);
      _selectedMenuItemId = costing.menuItemId;
      _pickedMenu = null;
    });
    _tabController.animateTo(0);
  }

  /// Called when the user picks a menu from the "Pick from Menu" picker.
  /// This is the Menu ↔ Inventory ↔ Costing connection point:
  ///  1. Check whether this menu already has saved costing data → if so, load it.
  ///  2. If not, automatically compute the ingredient cost from the recipe
  ///     (menu_ingredients) × the CURRENT ingredient price in inventory, then fill the form.
  ///  3. The allocated operating cost per portion is also auto-filled from the
  ///     most recently saved Operating Expense data.
  Future<void> _onMenuPicked(MenuItem menu) async {
    final notifier = ref.read(costingProvider.notifier);
    setState(() => _isComputingCost = true);

    try {
      final existing = await ref
          .read(costingServiceProvider)
          .getCostingByMenuItemId(menu.id);

      if (existing != null) {
        _onSelectExistingCosting(existing);
        return;
      }

      final ingredientCost =
          await notifier.computeIngredientCostForMenu(menu.id);
      final opCost = ref.read(costingProvider).operatingExpense.operatingCostPerPortion;

      notifier.clearActiveCosting();
      notifier.updateLiveIngredientCost(ingredientCost);
      notifier.updateLiveAllocatedOpCost(opCost);

      if (!mounted) return;
      setState(() {
        _selectedMenuItemId = menu.id;
        _menuNameCtrl.text = menu.name;
        _ingredientCtrl.text = ingredientCost.toStringAsFixed(0);
        _packagingCtrl.text = '0';
        _allocatedOpCtrl.text = opCost.toStringAsFixed(0);
        _currentPriceCtrl.text = menu.price > 0 ? menu.price.toStringAsFixed(0) : '0';
        _targetMarginCtrl.text = '30';
        _pickedMenu = menu;
      });
      notifier.updateLiveCurrentPrice(menu.price);

      if (ingredientCost <= 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '⚠️ "${menu.name}" doesn\'t have a recipe (ingredients) yet, or its ingredients weren\'t found in inventory. '
                'Enter the ingredient cost manually, or complete the recipe first in Menu Management.'),
            backgroundColor: AppColors.accentOrange,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isComputingCost = false);
    }
  }

  Future<void> _openMenuPicker() async {
    final branchId = ref.read(costingProvider.notifier).effectiveBranchId;
    final picked = await showModalBottomSheet<MenuItem>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppSpacing.radiusLg)),
      ),
      builder: (_) => _MenuPickerSheet(branchId: branchId),
    );
    if (picked != null) {
      await _onMenuPicked(picked);
    }
  }

  @override
  void dispose() {
    _menuNameCtrl.dispose();
    _ingredientCtrl.dispose();
    _packagingCtrl.dispose();
    _allocatedOpCtrl.dispose();
    _currentPriceCtrl.dispose();
    _targetMarginCtrl.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    // ✅ RIVERPOD: ref.read(costingProvider.notifier) for actions/mutations
    final success = await ref.read(costingProvider.notifier).saveCosting(
      menuItemId: _selectedMenuItemId ?? widget.menuItemId ?? 'custom-${DateTime.now().millisecondsSinceEpoch}',
      menuItemName: _menuNameCtrl.text.trim(),
      ingredientCost: double.tryParse(_ingredientCtrl.text) ?? 0,
      packagingCost: double.tryParse(_packagingCtrl.text) ?? 0,
      targetMarginPercent: double.tryParse(_targetMarginCtrl.text) ?? 30,
      currentSellingPrice: double.tryParse(_currentPriceCtrl.text) ?? 0,
    );

    if (!mounted) return;
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('✅ Costing data saved successfully'),
          backgroundColor: AppColors.available,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    } else {
      // ✅ RIVERPOD: read the error from state, not from the provider instance
      final errorMsg = ref.read(costingProvider).errorMessage;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ ${errorMsg.isEmpty ? "Failed to save" : errorMsg}'),
          backgroundColor: AppColors.accent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final notifier = ref.watch(costingProvider.notifier);
    return StaffShell(
      pageTitle: 'Costing Calculator',
      activeRoute: AppRoutes.costing,
      topBarActions: [
        if (notifier.isSuperAdmin)
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
                  value: notifier.selectedBranchId,
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
                    ...notifier.branches.map((b) => DropdownMenuItem<String?>(
                          value: b['id'] as String,
                          child: Text(b['name'] as String,
                              style: const TextStyle(fontFamily: 'Poppins', fontSize: 12)))),
                  ],
                  onChanged: (val) => notifier.selectBranch(val),
                ),
              ),
            ),
          ),
        IconButton(
          tooltip: 'Refresh',
          icon: const Icon(Icons.refresh_rounded, color: AppColors.textSecondary),
          onPressed: () => notifier.loadAll(),
        ),
      ],
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            child: _buildHeader(),
          ),
          const SizedBox(height: 12),
          _buildTabToggle(),
          const Divider(height: 1, color: AppColors.border),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _CalculatorTab(
                  formKey: _formKey,
                  menuNameCtrl: _menuNameCtrl,
                  ingredientCtrl: _ingredientCtrl,
                  packagingCtrl: _packagingCtrl,
                  allocatedOpCtrl: _allocatedOpCtrl,
                  currentPriceCtrl: _currentPriceCtrl,
                  targetMarginCtrl: _targetMarginCtrl,
                  onSave: _save,
                  onPickMenu: _openMenuPicker,
                  isComputingCost: _isComputingCost,
                  pickedMenu: _pickedMenu,
                ),
                _MenuListTab(onSelectCosting: _onSelectExistingCosting),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Costing Calculator',
                style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 30,
                  fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
              SizedBox(height: 4),
              Text('Recipe management and margin analysis.',
                style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 13, color: AppColors.textSecondary)),
            ],
          ),
        ),
        const SizedBox(width: 16),
        SizedBox(
          width: 240,
          child: _MenuItemSelector(
            currentName: _menuNameCtrl.text,
            isLoading: _isComputingCost,
            onTap: _openMenuPicker,
          ),
        ),
      ],
    );
  }

  Widget _buildTabToggle() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
      child: AnimatedBuilder(
        animation: _tabController,
        builder: (context, _) {
          return Row(
            children: [
              _TabToggleItem(
                label: 'Calculator',
                icon: Icons.calculate_outlined,
                isSelected: _tabController.index == 0,
                onTap: () => _tabController.animateTo(0),
              ),
              const SizedBox(width: 20),
              _TabToggleItem(
                label: 'Menu List',
                icon: Icons.list_alt_rounded,
                isSelected: _tabController.index == 1,
                onTap: () => _tabController.animateTo(1),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header controls
// ─────────────────────────────────────────────────────────────────────────────

class _TabToggleItem extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;
  const _TabToggleItem({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isSelected ? AppColors.primary : Colors.transparent,
              width: 2.5),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16,
              color: isSelected ? AppColors.primary : AppColors.textSecondary),
            const SizedBox(width: 6),
            Text(label,
              style: TextStyle(
                fontFamily: 'Poppins', fontSize: 13,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? AppColors.primary : AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}

class _MenuItemSelector extends StatelessWidget {
  final String currentName;
  final bool isLoading;
  final VoidCallback onTap;
  const _MenuItemSelector({
    required this.currentName,
    required this.isLoading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('SELECT MENU ITEM',
          style: TextStyle(
            fontFamily: 'Poppins', fontSize: 10, fontWeight: FontWeight.w800,
            letterSpacing: 0.5, color: AppColors.textSecondary)),
        const SizedBox(height: 6),
        InkWell(
          onTap: isLoading ? null : onTap,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    currentName.isEmpty ? 'Choose a menu item...' : currentName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w700,
                      color: currentName.isEmpty ? AppColors.textHint : AppColors.textPrimary)),
                ),
                if (isLoading)
                  const SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
                else
                  const Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: AppColors.textSecondary),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB 1: CALCULATOR
// ✅ RIVERPOD: StatelessWidget → ConsumerWidget (needs ref to watch state)
// ─────────────────────────────────────────────────────────────────────────────
class _CalculatorTab extends ConsumerWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController menuNameCtrl;
  final TextEditingController ingredientCtrl;
  final TextEditingController packagingCtrl;
  final TextEditingController allocatedOpCtrl;
  final TextEditingController currentPriceCtrl;
  final TextEditingController targetMarginCtrl;
  final VoidCallback onSave;
  final VoidCallback onPickMenu;
  final bool isComputingCost;
  final MenuItem? pickedMenu;

  const _CalculatorTab({
    required this.formKey,
    required this.menuNameCtrl,
    required this.ingredientCtrl,
    required this.packagingCtrl,
    required this.allocatedOpCtrl,
    required this.currentPriceCtrl,
    required this.targetMarginCtrl,
    required this.onSave,
    required this.onPickMenu,
    required this.isComputingCost,
    this.pickedMenu,
  });

  @override
  // ✅ RIVERPOD: build(context) → build(context, ref)
  Widget build(BuildContext context, WidgetRef ref) {
    // ✅ RIVERPOD: Consumer<X> builder → ref.watch(xProvider)
    final state = ref.watch(costingProvider);
    final result = state.liveCalcResult;
    final notifier = ref.read(costingProvider.notifier);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Nudge: Operating Expense must be filled in first ───────────
            // The allocated operating cost per portion (used for COGS) is only
            // accurate once this month's Operating Expense data exists.
            if (state.operatingExpense.id.isEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.accentOrange.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  border: Border.all(color: AppColors.accentOrange.withValues(alpha: 0.35)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded, color: AppColors.accentOrange, size: 20),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'This month\'s Operating Expense hasn\'t been filled in yet, so the per-portion cost allocation is still Rp 0. Fill it in first so COGS is accurate.',
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: AppColors.textPrimary),
                      ),
                    ),
                    TextButton(
                      onPressed: () => context.go(AppRoutes.operatingExpense),
                      child: const Text('Fill In Now',
                        style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, color: AppColors.accentOrange)),
                    ),
                  ],
                ),
              ),

            LayoutBuilder(builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 980;
              final left = _LeftColumn(
                menuNameCtrl: menuNameCtrl,
                ingredientCtrl: ingredientCtrl,
                packagingCtrl: packagingCtrl,
                allocatedOpCtrl: allocatedOpCtrl,
                onPickMenu: onPickMenu,
                isComputingCost: isComputingCost,
                pickedMenu: pickedMenu,
                notifier: notifier,
                state: state,
                result: result,
              );
              final right = _FinancialSummaryPanel(
                result: result,
                currentPriceCtrl: currentPriceCtrl,
                targetMarginCtrl: targetMarginCtrl,
                notifier: notifier,
                isSaving: state.isSaving,
                onSave: onSave,
              );

              if (isWide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 2, child: left),
                    const SizedBox(width: 20),
                    SizedBox(width: 340, child: right),
                  ],
                );
              }
              return Column(
                children: [
                  left,
                  const SizedBox(height: 20),
                  right,
                ],
              );
            }),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _RecipeMonogram extends StatelessWidget {
  final String name;
  const _RecipeMonogram({required this.name});

  @override
  Widget build(BuildContext context) {
    return Text(
      name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?',
      style: const TextStyle(
        fontFamily: 'Poppins', fontSize: 26,
        fontWeight: FontWeight.w800, color: AppColors.primary));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LEFT COLUMN — Recipe identity + Bill of Materials-style cost breakdown
// ─────────────────────────────────────────────────────────────────────────────
class _LeftColumn extends StatelessWidget {
  final TextEditingController menuNameCtrl;
  final TextEditingController ingredientCtrl;
  final TextEditingController packagingCtrl;
  final TextEditingController allocatedOpCtrl;
  final VoidCallback onPickMenu;
  final bool isComputingCost;
  final MenuItem? pickedMenu;
  final CostingNotifier notifier;
  final CostingNotifier state;
  final CostingModel result;

  const _LeftColumn({
    required this.menuNameCtrl,
    required this.ingredientCtrl,
    required this.packagingCtrl,
    required this.allocatedOpCtrl,
    required this.onPickMenu,
    required this.isComputingCost,
    required this.pickedMenu,
    required this.notifier,
    required this.state,
    required this.result,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Recipe identity card ────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 64, height: 64,
                alignment: Alignment.center,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: (pickedMenu?.imageUrl != null && pickedMenu!.imageUrl!.isNotEmpty)
                    ? Image.network(pickedMenu!.imageUrl!,
                        width: 64, height: 64, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _RecipeMonogram(name: menuNameCtrl.text))
                    : _RecipeMonogram(name: menuNameCtrl.text),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: menuNameCtrl,
                            autovalidateMode: AutovalidateMode.always,
                            style: const TextStyle(
                              fontFamily: 'Poppins', fontSize: 17,
                              fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                            decoration: const InputDecoration(
                              isDense: true,
                              hintText: 'Menu item name *',
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.zero,
                            ),
                            validator: (v) =>
                                (v == null || v.trim().isEmpty) ? 'Menu name is required' : null,
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: isComputingCost ? null : onPickMenu,
                          icon: isComputingCost
                              ? const SizedBox(
                                  width: 14, height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.restaurant_rounded, size: 14),
                          label: const Text('Pick from Menu', style: TextStyle(fontFamily: 'Poppins', fontSize: 11)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primary,
                            side: const BorderSide(color: AppColors.primary),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      pickedMenu?.description?.isNotEmpty == true
                          ? pickedMenu!.description!
                          : 'Recipe cost and margin details for this menu item.',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Poppins', fontSize: 12, color: AppColors.textSecondary)),
                    const SizedBox(height: 8),
                    _PricingStatusBadge(status: result.pricingStatus),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // ── Bill of Materials (Direct Costs) ────────────────────────────
        _SectionCard(
          title: 'Bill of Materials',
          subtitle: 'Direct cost per single portion',
          icon: Icons.shopping_basket_rounded,
          color: AppColors.primary,
          child: Column(
            children: [
              _CostLineRow(
                label: 'Ingredient Cost',
                helper: 'From inventory data / recipe',
                controller: ingredientCtrl,
                accentColor: AppColors.primary,
                isRequired: true,
                onChanged: (v) => notifier.updateLiveIngredientCost(v),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Required';
                  final n = double.tryParse(v);
                  if (n == null) return 'Invalid';
                  if (n <= 0) return 'Ingredient cost must be greater than 0';
                  return null;
                },
              ),
              _CostLineRow(
                label: 'Packaging Cost',
                helper: 'Box, plastic, straw, etc. (for takeaway)',
                controller: packagingCtrl,
                accentColor: AppColors.primary,
                onChanged: (v) => notifier.updateLivePackagingCost(v),
              ),
              const Divider(height: 24, color: AppColors.border),
              _TotalLineRow(
                label: 'Direct Cost Subtotal',
                value: formatIdr(result.totalDirectCost),
                color: AppColors.textPrimary,
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // ── Operating Cost (Allocated) ──────────────────────────────────
        _SectionCard(
          title: 'Operating Cost (Allocated)',
          subtitle: 'Share of monthly cost per portion',
          icon: Icons.business_center_rounded,
          color: AppColors.accent,
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: _CostLineRow(
                      label: 'Allocated Operating Cost/portion',
                      helper: 'Total OpEx ÷ Estimated portions/month',
                      controller: allocatedOpCtrl,
                      accentColor: AppColors.accent,
                      onChanged: (v) => notifier.updateLiveAllocatedOpCost(v),
                      showDivider: false,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: 'Auto-fill from the latest Operating Expense',
                    child: OutlinedButton.icon(
                      onPressed: () {
                        notifier.autoFillAllocatedCost();
                        allocatedOpCtrl.text =
                            notifier.operatingExpense.operatingCostPerPortion.toStringAsFixed(0);
                      },
                      icon: const Icon(Icons.auto_fix_high_rounded, size: 16),
                      label: const Text('Auto', style: TextStyle(fontFamily: 'Poppins', fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.accent,
                        side: const BorderSide(color: AppColors.accent),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
              _OperatingExpenseInfoCard(expense: state.operatingExpense),
              const Divider(height: 24, color: AppColors.border),
              _TotalLineRow(
                label: 'COGS (Cost of Goods Sold)',
                value: formatIdr(result.hpp),
                color: AppColors.accent,
                isHighlighted: true,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PricingStatusBadge extends StatelessWidget {
  final CostingStatus status;
  const _PricingStatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (status) {
      case CostingStatus.healthy:
        color = AppColors.available;
        break;
      case CostingStatus.warning:
        color = AppColors.accentOrange;
        break;
      case CostingStatus.underpriced:
        color = AppColors.accent;
        break;
      default:
        color = AppColors.textHint;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text('${status.emoji} ${status.label}',
        style: TextStyle(
          fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final Color color;
  final Widget child;
  const _SectionCard({
    required this.title,
    this.subtitle,
    required this.icon,
    required this.color,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CostingSectionHeader(title: title, subtitle: subtitle, icon: icon, color: color),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

// A compact table-row style editable cost line: label + helper on the left,
// a small currency field on the right — the closest honest mapping of this
// data model (one lump cost per category) onto the mockup's ingredient rows.
class _CostLineRow extends StatelessWidget {
  final String label;
  final String? helper;
  final TextEditingController controller;
  final Color accentColor;
  final bool isRequired;
  final ValueChanged<double> onChanged;
  final String? Function(String?)? validator;
  final bool showDivider;

  const _CostLineRow({
    required this.label,
    this.helper,
    required this.controller,
    required this.accentColor,
    required this.onChanged,
    this.isRequired = false,
    this.validator,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: showDivider ? 12 : 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: TextSpan(
                    style: const TextStyle(
                      fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary),
                    children: [
                      TextSpan(text: label),
                      if (isRequired)
                        const TextSpan(text: ' *',
                          style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
                if (helper != null) ...[
                  const SizedBox(height: 2),
                  Text(helper!,
                    style: const TextStyle(
                      fontFamily: 'Poppins', fontSize: 11, color: AppColors.textSecondary)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 130,
            child: TextFormField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.right,
              autovalidateMode: AutovalidateMode.always,
              onChanged: (v) => onChanged(double.tryParse(v) ?? 0),
              validator: validator,
              style: const TextStyle(
                fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w800,
                color: AppColors.textPrimary),
              decoration: InputDecoration(
                isDense: true,
                prefixText: 'Rp ',
                prefixStyle: const TextStyle(
                  fontFamily: 'Poppins', fontSize: 12, color: AppColors.textSecondary),
                filled: true,
                fillColor: AppColors.surfaceVariant,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  borderSide: BorderSide(color: accentColor, width: 1.5),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  borderSide: const BorderSide(color: AppColors.accent, width: 1.3),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TotalLineRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool isHighlighted;
  const _TotalLineRow({
    required this.label,
    required this.value,
    required this.color,
    this.isHighlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
          style: TextStyle(
            fontFamily: 'Poppins', fontSize: isHighlighted ? 14 : 13,
            fontWeight: isHighlighted ? FontWeight.w800 : FontWeight.w600,
            color: isHighlighted ? color : AppColors.textSecondary)),
        Text(value,
          style: TextStyle(
            fontFamily: 'Poppins', fontSize: isHighlighted ? 16 : 14,
            fontWeight: FontWeight.w800, color: color)),
      ],
    );
  }
}

class _OperatingExpenseInfoCard extends StatelessWidget {
  final OperatingExpenseModel expense;
  const _OperatingExpenseInfoCard({required this.expense});

  @override
  Widget build(BuildContext context) {
    if (expense.id.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Operating Expense Breakdown — ${expense.periodLabel}',
            style: const TextStyle(
              fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.accent)),
          const SizedBox(height: 8),
          _ExpenseLine('Total Labor', expense.totalLaborCost),
          _ExpenseLine('Total Utilities', expense.totalUtilityCost),
          _ExpenseLine('Rent & Overhead', expense.totalOverheadCost),
          const Divider(height: 12, color: AppColors.border),
          _ExpenseLine('Total OpEx / month', expense.totalOperatingExpense, bold: true),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Estimated portions/month',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: AppColors.textSecondary)),
              Text('${expense.estimatedPortionsSoldMonthly} portions',
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 12, color: AppColors.textSecondary)),
            ],
          ),
          _ExpenseLine('Allocated per portion', expense.operatingCostPerPortion, bold: true),
        ],
      ),
    );
  }
}

class _ExpenseLine extends StatelessWidget {
  final String label;
  final double value;
  final bool bold;
  const _ExpenseLine(this.label, this.value, {this.bold = false});

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontFamily: 'Poppins', fontSize: 12,
      fontWeight: bold ? FontWeight.w800 : FontWeight.w400,
      color: bold ? AppColors.accent : AppColors.textSecondary);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(formatIdr(value), style: style),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// RIGHT COLUMN — Financial Summary panel
// ─────────────────────────────────────────────────────────────────────────────
class _FinancialSummaryPanel extends StatelessWidget {
  final CostingModel result;
  final TextEditingController currentPriceCtrl;
  final TextEditingController targetMarginCtrl;
  final CostingNotifier notifier;
  final bool isSaving;
  final VoidCallback onSave;

  const _FinancialSummaryPanel({
    required this.result,
    required this.currentPriceCtrl,
    required this.targetMarginCtrl,
    required this.notifier,
    required this.isSaving,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final marginOk = result.actualProfitMarginPercent >= result.targetProfitMarginPercent;
    final marginColor = result.currentSellingPrice <= 0
        ? AppColors.textHint
        : (marginOk ? AppColors.available : AppColors.accent);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Financial Summary',
            style: TextStyle(
              fontFamily: 'Poppins', fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          const SizedBox(height: 16),

          const Text('TOTAL FOOD COST',
            style: TextStyle(
              fontFamily: 'Poppins', fontSize: 10, fontWeight: FontWeight.w800,
              letterSpacing: 0.4, color: AppColors.textSecondary)),
          const SizedBox(height: 2),
          Text(formatIdr(result.totalDirectCost),
            style: const TextStyle(
              fontFamily: 'Poppins', fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.accent)),
          const SizedBox(height: 16),

          _MarginSlider(
            value: double.tryParse(targetMarginCtrl.text) ?? 30,
            controller: targetMarginCtrl,
            onChanged: (v) {
              targetMarginCtrl.text = v.toStringAsFixed(0);
              notifier.updateLiveTargetMargin(v);
            },
          ),
          const SizedBox(height: 14),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('SUGGESTED PRICE',
                    style: TextStyle(
                      fontFamily: 'Poppins', fontSize: 10, fontWeight: FontWeight.w800,
                      letterSpacing: 0.4, color: AppColors.textSecondary)),
                  Text('Target ${result.targetProfitMarginPercent.toStringAsFixed(0)}% margin',
                    style: const TextStyle(
                      fontFamily: 'Poppins', fontSize: 11, color: AppColors.textSecondary)),
                ],
              ),
              Text(formatIdr(result.recommendedSellingPriceRounded),
                style: const TextStyle(
                  fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 16),

          const Text('ACTUAL SELLING PRICE',
            style: TextStyle(
              fontFamily: 'Poppins', fontSize: 10, fontWeight: FontWeight.w800,
              letterSpacing: 0.4, color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          TextFormField(
            controller: currentPriceCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            autovalidateMode: AutovalidateMode.always,
            onChanged: (v) => notifier.updateLiveCurrentPrice(double.tryParse(v) ?? 0),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Required';
              final n = double.tryParse(v);
              if (n == null) return 'Invalid';
              if (n <= 0) return 'Selling price must be greater than 0';
              return null;
            },
            style: const TextStyle(
              fontFamily: 'Poppins', fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
            decoration: InputDecoration(
              isDense: true,
              prefixText: 'Rp ',
              prefixStyle: const TextStyle(
                fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
              filled: true,
              fillColor: AppColors.surfaceVariant,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                borderSide: const BorderSide(color: AppColors.available, width: 1.5),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                borderSide: const BorderSide(color: AppColors.accent, width: 1.3),
              ),
            ),
          ),
          const SizedBox(height: 16),

          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: marginColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              border: Border.all(color: marginColor.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('GROSS MARGIN',
                        style: TextStyle(
                          fontFamily: 'Poppins', fontSize: 10, fontWeight: FontWeight.w800,
                          letterSpacing: 0.4, color: AppColors.textSecondary)),
                      const SizedBox(height: 2),
                      Text(formatIdr(result.profitPerPortion),
                        style: const TextStyle(
                          fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('MARGIN %',
                      style: TextStyle(
                        fontFamily: 'Poppins', fontSize: 10, fontWeight: FontWeight.w800,
                        letterSpacing: 0.4, color: AppColors.textSecondary)),
                    const SizedBox(height: 2),
                    Text(formatPct(result.actualProfitMarginPercent),
                      style: TextStyle(
                        fontFamily: 'Poppins', fontSize: 18, fontWeight: FontWeight.w800, color: marginColor)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          FilledButton.icon(
            onPressed: isSaving ? null : onSave,
            icon: isSaving
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save_rounded, size: 18),
            label: Text(isSaving ? 'Saving...' : 'SAVE COSTING',
              style: const TextStyle(
                fontFamily: 'Poppins', fontWeight: FontWeight.w800, fontSize: 13, letterSpacing: 0.4)),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.radiusSm)),
            ),
          ),
        ],
      ),
    );
  }
}

class _MarginSlider extends StatelessWidget {
  final double value;
  final TextEditingController controller;
  final ValueChanged<double> onChanged;

  const _MarginSlider({
    required this.value,
    required this.controller,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Target Profit Margin',
              style: TextStyle(
                fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.available.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
              ),
              child: Text('${value.toStringAsFixed(0)}%',
                style: const TextStyle(
                  fontFamily: 'Poppins', fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.available)),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: AppColors.available,
            thumbColor: AppColors.available,
            overlayColor: AppColors.available.withValues(alpha: 0.15),
            inactiveTrackColor: AppColors.border,
          ),
          child: Slider(
            value: value.clamp(5, 80),
            min: 5, max: 80, divisions: 75,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB 2: MENU LIST
// ✅ RIVERPOD: StatefulWidget → ConsumerStatefulWidget
// ─────────────────────────────────────────────────────────────────────────────
class _MenuListTab extends ConsumerStatefulWidget {
  final ValueChanged<CostingModel> onSelectCosting;
  const _MenuListTab({required this.onSelectCosting});

  @override
  ConsumerState<_MenuListTab> createState() => _MenuListTabState();
}

// ✅ RIVERPOD: State<T> → ConsumerState<T>
class _MenuListTabState extends ConsumerState<_MenuListTab> {
  CostingStatus? _filterStatus;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // ✅ RIVERPOD: context.read<X>() → ref.read(xProvider.notifier)
      ref.read(costingProvider.notifier).loadAll();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ✅ RIVERPOD: Consumer<X> builder → ref.watch(xProvider)
    final state = ref.watch(costingProvider);
    final notifier = ref.read(costingProvider.notifier);

    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }

    final filtered = notifier.getFilteredCostings(
      filterByStatus: _filterStatus,
      searchQuery: _searchCtrl.text,
      sortByMarginAsc: true,
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CostingSummaryCard(summary: state.summary),
          const SizedBox(height: 20),

          // Filter bar
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Search menu...',
                    hintStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 13, color: AppColors.textHint),
                    prefixIcon: const Icon(Icons.search, size: 18, color: AppColors.textSecondary),
                    filled: true,
                    fillColor: AppColors.surfaceVariant,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                      borderSide: BorderSide.none,
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<CostingStatus?>(
                initialValue: _filterStatus,
                onSelected: (v) => setState(() => _filterStatus = v),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: null, child: Text('All')),
                  PopupMenuItem(value: CostingStatus.healthy, child: Text('🟢 Healthy')),
                  PopupMenuItem(value: CostingStatus.warning, child: Text('🟡 Needs Review')),
                  PopupMenuItem(value: CostingStatus.underpriced, child: Text('🔴 Too Low')),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.filter_list_rounded, size: 18, color: AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Text(_filterStatus?.label ?? 'Filter',
                        style: const TextStyle(fontFamily: 'Poppins', fontSize: 13, color: AppColors.textPrimary)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // List
          if (filtered.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.inbox_rounded, size: 48, color: AppColors.textHint),
                    SizedBox(height: 8),
                    Text('No costing data yet',
                        style: TextStyle(fontFamily: 'Poppins', color: AppColors.textSecondary)),
                  ],
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: filtered.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final costing = filtered[i];
                return CostingListTile(
                  costing: costing,
                  onTap: () => widget.onSelectCosting(costing),
                  onDelete: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.radiusLg)),
                        title: const Text('Delete Costing?',
                          style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
                        content: Text(
                            'The costing data for "${costing.menuItemName}" will be deleted.',
                            style: const TextStyle(fontFamily: 'Poppins')),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true && context.mounted) {
                      await notifier.deleteCosting(costing.id);
                    }
                  },
                );
              },
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PICKER: Pick from Menu — bridge between Menu ↔ Costing
// Displays the list of menu_items belonging to the active branch. Picking one
// automatically computes the ingredient cost from the recipe (menu_ingredients) ×
// the CURRENT inventory price.
// ─────────────────────────────────────────────────────────────────────────────
class _MenuPickerSheet extends ConsumerStatefulWidget {
  final String? branchId;
  const _MenuPickerSheet({required this.branchId});

  @override
  ConsumerState<_MenuPickerSheet> createState() => _MenuPickerSheetState();
}

class _MenuPickerSheetState extends ConsumerState<_MenuPickerSheet> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final menusAsync = ref.watch(menuProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16, right: 16, top: 12,
            bottom: MediaQuery.of(context).viewInsets.bottom + 12,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(4)),
                ),
              ),
              const SizedBox(height: 12),
              const Text('Select Menu',
                  style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.textPrimary)),
              const SizedBox(height: 8),
              TextField(
                controller: _searchCtrl,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Search menu...',
                  hintStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 13, color: AppColors.textHint),
                  prefixIcon: const Icon(Icons.search, size: 18, color: AppColors.textSecondary),
                  filled: true,
                  fillColor: AppColors.surfaceVariant,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    borderSide: BorderSide.none,
                  ),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: menusAsync.when(
                  loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
                  error: (e, _) => Center(child: Text('Failed to load menu: $e',
                      style: const TextStyle(fontFamily: 'Poppins'))),
                  data: (menus) {
                    var filtered = widget.branchId == null
                        ? menus
                        : menus.where((m) => m.branchId == widget.branchId).toList();

                    final q = _searchCtrl.text.trim().toLowerCase();
                    if (q.isNotEmpty) {
                      filtered = filtered
                          .where((m) => m.name.toLowerCase().contains(q))
                          .toList();
                    }

                    if (filtered.isEmpty) {
                      return const Center(
                        child: Text('No menu items in this branch yet.',
                            style: TextStyle(fontFamily: 'Poppins', color: AppColors.textSecondary)),
                      );
                    }

                    return ListView.separated(
                      controller: scrollController,
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.border),
                      itemBuilder: (context, i) {
                        final m = filtered[i];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                            child: Text(
                              m.name.isNotEmpty ? m.name[0].toUpperCase() : '?',
                              style: const TextStyle(
                                color: AppColors.primary, fontWeight: FontWeight.w700),
                            ),
                          ),
                          title: Text(m.name,
                              style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
                          subtitle: Text(formatIdr(m.price),
                              style: const TextStyle(fontFamily: 'Poppins', fontSize: 12, color: AppColors.textSecondary)),
                          onTap: () => Navigator.pop(context, m),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
