// lib/features/costing/presentation/screens/costing_calculator_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models/costing_model.dart';
import '../providers/costing_providers.dart';
import 'costing_widgets.dart';
import '../../../shared/widgets/app_drawer.dart';
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
      });
      notifier.updateLiveCurrentPrice(menu.price);

      if (ingredientCost <= 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '⚠️ "${menu.name}" doesn\'t have a recipe (ingredients) yet, or its ingredients weren\'t found in inventory. '
                'Enter the ingredient cost manually, or complete the recipe first in Menu Management.'),
            backgroundColor: Colors.orange.shade700,
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
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
          backgroundColor: const Color(0xFF2E7D32),
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
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final notifier = ref.watch(costingProvider.notifier);
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: const Text(
          'Costing & Profit Calculator',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
        ),
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 1,
        actions: [
          if (notifier.isSuperAdmin)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4),
                  ),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    value: notifier.selectedBranchId,
                    isDense: true,
                    dropdownColor: Theme.of(context).colorScheme.surface,
                    iconEnabledColor: Theme.of(context).colorScheme.primary,
                    icon: const Icon(Icons.keyboard_arrow_down, size: 16),
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onPrimaryContainer),
                    items: [
                      DropdownMenuItem<String?>(
                        value: null,
                        child: Text('All Branches',
                            style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.onPrimaryContainer)),
                      ),
                      ...notifier.branches.map((b) => DropdownMenuItem<String?>(
                            value: b['id'] as String,
                            child: Text(b['name'] as String,
                                style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Theme.of(context).colorScheme.onSurface)),
                          )),
                    ],
                    onChanged: (val) => notifier.selectBranch(val),
                  ),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => notifier.loadAll(),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Calculator', icon: Icon(Icons.calculate_outlined, size: 18)),
            Tab(text: 'Menu List', icon: Icon(Icons.list_alt_rounded, size: 18)),
          ],
          labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        ),
      ),
      body: TabBarView(
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
          ),
          _MenuListTab(onSelectCosting: _onSelectExistingCosting),
        ],
      ),
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
  });

  @override
  // ✅ RIVERPOD: build(context) → build(context, ref)
  Widget build(BuildContext context, WidgetRef ref) {
    // ✅ RIVERPOD: Consumer<X> builder → ref.watch(xProvider)
    final state = ref.watch(costingProvider);
    final result = state.liveCalcResult;
    final notifier = ref.read(costingProvider.notifier);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CostingSummaryCard(summary: state.summary),
            const SizedBox(height: 16),

            // ── Nudge: Operating Expense must be filled in first ───────────
            // The allocated operating cost per portion (used for COGS) is only
            // accurate once this month's Operating Expense data exists.
            if (state.operatingExpense.id.isEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.orange.withValues(alpha: 0.35)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded, color: Colors.orange.shade800, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'This month\'s Operating Expense hasn\'t been filled in yet, so the per-portion cost allocation is still Rp 0. Fill it in first so COGS is accurate.',
                        style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
                      ),
                    ),
                    TextButton(
                      onPressed: () => context.go(AppRoutes.operatingExpense),
                      child: const Text('Fill In Now', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),

            // ── Menu Name ──────────────────────────────────────────────────
            Row(
              children: [
                const Expanded(
                  child: CostingSectionHeader(
                    title: 'Menu Identity',
                    icon: Icons.restaurant_menu_rounded,
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: isComputingCost ? null : onPickMenu,
                  icon: isComputingCost
                      ? const SizedBox(
                          width: 14, height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.restaurant_rounded, size: 16),
                  label: const Text('Pick from Menu', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: menuNameCtrl,
              autovalidateMode: AutovalidateMode.always,
              decoration: InputDecoration(
                labelText: 'Menu Name *',
                labelStyle: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                ),
                hintText: 'Menu item name (e.g. Nasi Goreng Spesial)',
                prefixIcon: const Icon(Icons.label_rounded, size: 18),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                      color: Theme.of(context).colorScheme.primary, width: 1.5),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Colors.red, width: 1.3),
                ),
                focusedErrorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Colors.red, width: 1.6),
                ),
                errorStyle: const TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Menu name is required' : null,
            ),
            const SizedBox(height: 24),

            // ── Direct Costs ───────────────────────────────────────────────
            const CostingSectionHeader(
              title: 'Direct Costs',
              subtitle: 'Cost per single portion',
              icon: Icons.shopping_basket_rounded,
              color: Color(0xFF1565C0),
            ),
            const SizedBox(height: 12),
            CurrencyInputField(
              label: 'Ingredient Cost',
              hint: '0',
              controller: ingredientCtrl,
              helperText: 'From inventory data / recipe',
              accentColor: const Color(0xFF1565C0),
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
            const SizedBox(height: 12),
            CurrencyInputField(
              label: 'Packaging Cost',
              hint: '0',
              controller: packagingCtrl,
              helperText: 'Box, plastic, straw, etc. (for takeaway)',
              accentColor: const Color(0xFF1565C0),
              onChanged: (v) => notifier.updateLivePackagingCost(v),
            ),
            _SubtotalRow(
              label: 'Direct Cost Subtotal',
              value: formatIdr(result.totalDirectCost),
              color: const Color(0xFF1565C0),
            ),
            const SizedBox(height: 24),

            // ── Indirect / Operating Costs ─────────────────────────────────
            const CostingSectionHeader(
              title: 'Operating Cost (Allocated)',
              subtitle: 'Share of monthly cost per portion',
              icon: Icons.business_center_rounded,
              color: Color(0xFF6A1B9A),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: CurrencyInputField(
                    label: 'Allocated Operating Cost/portion',
                    hint: '0',
                    controller: allocatedOpCtrl,
                    helperText: 'Total OpEx ÷ Estimated portions/month',
                    accentColor: const Color(0xFF6A1B9A),
                    onChanged: (v) => notifier.updateLiveAllocatedOpCost(v),
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  children: [
                    const SizedBox(height: 22),
                    Tooltip(
                      message: 'Auto-fill from the latest Operating Expense',
                      child: OutlinedButton.icon(
                        onPressed: () {
                          notifier.autoFillAllocatedCost();
                          allocatedOpCtrl.text = ref
                              .read(costingProvider)
                              .operatingExpense
                              .operatingCostPerPortion
                              .toStringAsFixed(0);
                        },
                        icon: const Icon(Icons.auto_fix_high_rounded, size: 16),
                        label: const Text('Auto'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF6A1B9A),
                          side: const BorderSide(color: Color(0xFF6A1B9A)),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),

            _OperatingExpenseInfoCard(expense: state.operatingExpense),
            const SizedBox(height: 24),

            // ── COGS ───────────────────────────────────────────────────────
            _SubtotalRow(
              label: '📌 COGS (Cost of Goods Sold)',
              value: formatIdr(result.hpp),
              color: Theme.of(context).colorScheme.error,
              isHighlighted: true,
            ),
            const SizedBox(height: 24),

            // ── Target Margin & Price ────────────────────────────────────
            const CostingSectionHeader(
              title: 'Target Profit & Selling Price',
              icon: Icons.attach_money_rounded,
              color: Color(0xFF2E7D32),
            ),
            const SizedBox(height: 12),
            _MarginSlider(
              label: 'Target Profit Margin',
              value: double.tryParse(targetMarginCtrl.text) ?? 30,
              controller: targetMarginCtrl,
              onChanged: (v) {
                targetMarginCtrl.text = v.toStringAsFixed(0);
                notifier.updateLiveTargetMargin(v);
              },
            ),
            const SizedBox(height: 12),
            _RecommendedPriceBox(costing: result),
            const SizedBox(height: 12),
            CurrencyInputField(
              label: 'Current Selling Price',
              hint: '0',
              controller: currentPriceCtrl,
              helperText: 'Enter the currently applied selling price',
              accentColor: const Color(0xFF2E7D32),
              isRequired: true,
              onChanged: (v) => notifier.updateLiveCurrentPrice(v),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Required';
                final n = double.tryParse(v);
                if (n == null) return 'Invalid';
                if (n <= 0) return 'Selling price must be greater than 0';
                return null;
              },
            ),
            const SizedBox(height: 20),

            // ── Calculation Result ───────────────────────────────────────
            CostingResultCard(costing: result),
            const SizedBox(height: 24),

            // ── Save Button ──────────────────────────────────────────────
            FilledButton.icon(
              onPressed: state.isSaving ? null : onSave,
              icon: state.isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.save_rounded),
              label: Text(state.isSaving ? 'Saving...' : 'Save Costing Data'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
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
      return const Center(child: CircularProgressIndicator());
    }

    final filtered = notifier.getFilteredCostings(
      filterByStatus: _filterStatus,
      searchQuery: _searchCtrl.text,
      sortByMarginAsc: true,
    );

    return Column(
      children: [
        // Filter bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Search menu...',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    filled: true,
                    fillColor: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: 0.4),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<CostingStatus?>(
                initialValue: _filterStatus,
                onSelected: (v) => setState(() => _filterStatus = v),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: null, child: Text('All')),
                  const PopupMenuItem(
                      value: CostingStatus.healthy, child: Text('🟢 Healthy')),
                  const PopupMenuItem(
                      value: CostingStatus.warning,
                      child: Text('🟡 Needs Review')),
                  const PopupMenuItem(
                      value: CostingStatus.underpriced,
                      child: Text('🔴 Too Low')),
                ],
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.filter_list_rounded, size: 18),
                      const SizedBox(width: 4),
                      Text(
                        _filterStatus?.label ?? 'Filter',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // List
        Expanded(
          child: filtered.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inbox_rounded, size: 48, color: Colors.grey),
                      SizedBox(height: 8),
                      Text('No costing data yet',
                          style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                )
              : ListView.separated(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
                            title: const Text('Delete Costing?'),
                            content: Text(
                                'The costing data for "${costing.menuItemName}" will be deleted.'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Cancel'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(context, true),
                                style: FilledButton.styleFrom(
                                    backgroundColor:
                                        Theme.of(context).colorScheme.error),
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
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helper Widgets (don't need provider access → remain StatelessWidget)
// ─────────────────────────────────────────────────────────────────────────────

class _SubtotalRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool isHighlighted;

  const _SubtotalRow({
    required this.label,
    required this.value,
    required this.color,
    this.isHighlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: isHighlighted ? FontWeight.w800 : FontWeight.w600,
              fontSize: isHighlighted ? 14 : 13,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: isHighlighted ? 16 : 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _MarginSlider extends StatelessWidget {
  final String label;
  final double value;
  final TextEditingController controller;
  final ValueChanged<double> onChanged;

  const _MarginSlider({
    required this.label,
    required this.value,
    required this.controller,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF2E7D32).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${value.toStringAsFixed(0)}%',
                style: const TextStyle(
                  color: Color(0xFF2E7D32),
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
        Slider(
          value: value.clamp(5, 80),
          min: 5,
          max: 80,
          divisions: 75,
          activeColor: const Color(0xFF2E7D32),
          onChanged: onChanged,
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('5%',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline)),
            Text('Ideal: 30-50% for restaurants',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline)),
            Text('80%',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline)),
          ],
        ),
      ],
    );
  }
}

class _RecommendedPriceBox extends StatelessWidget {
  final CostingModel costing;

  const _RecommendedPriceBox({required this.costing});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2E7D32).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: const Color(0xFF2E7D32).withValues(alpha: 0.4), width: 1.5),
      ),
      child: Row(
        children: [
          const Icon(Icons.lightbulb_rounded,
              color: Color(0xFF2E7D32), size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Recommended Selling Price',
                  style: TextStyle(
                    color: Color(0xFF2E7D32),
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  formatIdr(costing.recommendedSellingPriceRounded),
                  style: const TextStyle(
                    color: Color(0xFF2E7D32),
                    fontWeight: FontWeight.w900,
                    fontSize: 22,
                  ),
                ),
                Text(
                  'Already rounded to the nearest Rp 500',
                  style: TextStyle(
                    color: const Color(0xFF2E7D32).withValues(alpha: 0.7),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OperatingExpenseInfoCard extends StatelessWidget {
  final OperatingExpenseModel expense;

  const _OperatingExpenseInfoCard({required this.expense});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (expense.id.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF6A1B9A).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF6A1B9A).withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '📊 Operating Expense Breakdown — ${expense.periodLabel}',
            style: const TextStyle(
              color: Color(0xFF6A1B9A),
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          _ExpenseLine('Total Labor', expense.totalLaborCost),
          _ExpenseLine('Total Utilities', expense.totalUtilityCost),
          _ExpenseLine('Rent & Overhead', expense.totalOverheadCost),
          const Divider(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total OpEx / month',
                  style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF6A1B9A))),
              Text(formatIdr(expense.totalOperatingExpense),
                  style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF6A1B9A))),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Estimated portions/month',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline)),
              Text('${expense.estimatedPortionsSoldMonthly} portions',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline)),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('⚡ Allocated per portion',
                  style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF6A1B9A))),
              Text(formatIdr(expense.operatingCostPerPortion),
                  style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF6A1B9A))),
            ],
          ),
        ],
      ),
    );
  }
}

class _ExpenseLine extends StatelessWidget {
  final String label;
  final double value;

  const _ExpenseLine(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.outline)),
          Text(formatIdr(value),
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.outline)),
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
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(4)),
                ),
              ),
              const SizedBox(height: 12),
              const Text('Select Menu',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 8),
              TextField(
                controller: _searchCtrl,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Search menu...',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: menusAsync.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('Failed to load menu: $e')),
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
                            style: TextStyle(color: Colors.grey)),
                      );
                    }

                    return ListView.separated(
                      controller: scrollController,
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final m = filtered[i];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                            child: Text(
                              m.name.isNotEmpty ? m.name[0].toUpperCase() : '?',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          title: Text(m.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(formatIdr(m.price), style: const TextStyle(fontSize: 12)),
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