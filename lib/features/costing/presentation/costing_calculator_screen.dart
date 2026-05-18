// lib/features/costing/presentation/screens/costing_calculator_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/costing_model.dart';
import '../providers/costing_providers.dart';
import 'costing_widgets.dart';
import '../../../shared/widgets/app_drawer.dart';

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

// ✅ RIVERPOD: State<T> → ConsumerState<T>  (dapat akses `ref` langsung)
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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // ✅ RIVERPOD: context.read<X>() → ref.read(xProvider.notifier)
      final notifier = ref.read(costingProvider.notifier);

      // Init branch filter (superadmin check)
      notifier.init();

      if (widget.menuItemId != null) {
        notifier.loadCostingForMenu(widget.menuItemId!).then((_) {
          // ✅ RIVERPOD: baca state terkini via ref.read(costingProvider)
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

  // ✅ RIVERPOD: parameter sekarang CostingState (bukan CostingProvider)
  void _syncFromState(CostingNotifier state) {
  final c = state.activeCosting;
  _menuNameCtrl.text = c.menuItemName;
  _ingredientCtrl.text = c.ingredientCost.toStringAsFixed(0);
  _packagingCtrl.text = c.packagingCost.toStringAsFixed(0);
  _allocatedOpCtrl.text = c.allocatedOperatingCost.toStringAsFixed(0);
  _currentPriceCtrl.text = c.currentSellingPrice.toStringAsFixed(0);
  _targetMarginCtrl.text = c.targetProfitMarginPercent.toStringAsFixed(0);
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

    // ✅ RIVERPOD: ref.read(costingProvider.notifier) untuk aksi/mutation
    final success = await ref.read(costingProvider.notifier).saveCosting(
      menuItemId: widget.menuItemId ?? 'custom-${DateTime.now().millisecondsSinceEpoch}',
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
          content: const Text('✅ Data costing berhasil disimpan'),
          backgroundColor: const Color(0xFF2E7D32),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    } else {
      // ✅ RIVERPOD: baca error dari state, bukan dari provider instance
      final errorMsg = ref.read(costingProvider).errorMessage;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ ${errorMsg.isEmpty ? "Gagal menyimpan" : errorMsg}'),
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
                        child: Text('Semua Cabang',
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
            Tab(text: 'Kalkulator', icon: Icon(Icons.attach_money_rounded, size: 18)),
            Tab(text: 'Daftar Menu', icon: Icon(Icons.list_alt_rounded, size: 18)),
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
          ),
          const _MenuListTab(),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB 1: KALKULATOR
// ✅ RIVERPOD: StatelessWidget → ConsumerWidget (butuh ref untuk watch state)
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

  const _CalculatorTab({
    required this.formKey,
    required this.menuNameCtrl,
    required this.ingredientCtrl,
    required this.packagingCtrl,
    required this.allocatedOpCtrl,
    required this.currentPriceCtrl,
    required this.targetMarginCtrl,
    required this.onSave,
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
            const SizedBox(height: 20),

            // ── Nama Menu ──────────────────────────────────────────────────
            const CostingSectionHeader(
              title: 'Identitas Menu',
              icon: Icons.restaurant_menu_rounded,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: menuNameCtrl,
              decoration: InputDecoration(
                hintText: 'Nama menu item (e.g. Nasi Goreng Spesial)',
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
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Nama menu wajib diisi' : null,
            ),
            const SizedBox(height: 24),

            // ── Direct Costs ───────────────────────────────────────────────
            const CostingSectionHeader(
              title: 'Biaya Langsung (Direct Costs)',
              subtitle: 'Biaya per satu porsi',
              icon: Icons.shopping_basket_rounded,
              color: Color(0xFF1565C0),
            ),
            const SizedBox(height: 12),
            CurrencyInputField(
              label: 'Biaya Bahan Baku (Ingredients)',
              hint: '0',
              controller: ingredientCtrl,
              helperText: 'Dari data inventory / resep',
              accentColor: const Color(0xFF1565C0),
              onChanged: (v) => notifier.updateLiveIngredientCost(v),
            ),
            const SizedBox(height: 12),
            CurrencyInputField(
              label: 'Biaya Kemasan (Packaging)',
              hint: '0',
              controller: packagingCtrl,
              helperText: 'Box, plastik, sedotan, dll (untuk takeaway)',
              accentColor: const Color(0xFF1565C0),
              onChanged: (v) => notifier.updateLivePackagingCost(v),
            ),
            _SubtotalRow(
              label: 'Subtotal Biaya Langsung',
              value: formatIdr(result.totalDirectCost),
              color: const Color(0xFF1565C0),
            ),
            const SizedBox(height: 24),

            // ── Indirect / Operating Costs ─────────────────────────────────
            const CostingSectionHeader(
              title: 'Biaya Operasional (Dialokasikan)',
              subtitle: 'Bagian dari biaya bulanan per porsi',
              icon: Icons.business_center_rounded,
              color: Color(0xFF6A1B9A),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: CurrencyInputField(
                    label: 'Alokasi Biaya Operasional/porsi',
                    hint: '0',
                    controller: allocatedOpCtrl,
                    helperText: 'Total OpEx ÷ Estimasi porsi/bulan',
                    accentColor: const Color(0xFF6A1B9A),
                    onChanged: (v) => notifier.updateLiveAllocatedOpCost(v),
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  children: [
                    const SizedBox(height: 22),
                    Tooltip(
                      message: 'Auto-fill dari Operating Expense terkini',
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

            // ── HPP ────────────────────────────────────────────────────────
            _SubtotalRow(
              label: '📌 HPP (Harga Pokok Penjualan)',
              value: formatIdr(result.hpp),
              color: Theme.of(context).colorScheme.error,
              isHighlighted: true,
            ),
            const SizedBox(height: 24),

            // ── Target Margin & Harga ──────────────────────────────────────
            const CostingSectionHeader(
              title: 'Target Profit & Harga Jual',
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
              label: 'Harga Jual Saat Ini',
              hint: '0',
              controller: currentPriceCtrl,
              helperText: 'Masukkan harga jual yang berlaku sekarang',
              accentColor: const Color(0xFF2E7D32),
              onChanged: (v) => notifier.updateLiveCurrentPrice(v),
            ),
            const SizedBox(height: 20),

            // ── Hasil Kalkulasi ────────────────────────────────────────────
            CostingResultCard(costing: result),
            const SizedBox(height: 24),

            // ── Tombol Simpan ──────────────────────────────────────────────
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
              label: Text(state.isSaving ? 'Menyimpan...' : 'Simpan Data Costing'),
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
// TAB 2: DAFTAR MENU
// ✅ RIVERPOD: StatefulWidget → ConsumerStatefulWidget
// ─────────────────────────────────────────────────────────────────────────────
class _MenuListTab extends ConsumerStatefulWidget {
  const _MenuListTab();

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
                    hintText: 'Cari menu...',
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
                  const PopupMenuItem(value: null, child: Text('Semua')),
                  const PopupMenuItem(
                      value: CostingStatus.healthy, child: Text('🟢 Sehat')),
                  const PopupMenuItem(
                      value: CostingStatus.warning,
                      child: Text('🟡 Perlu Review')),
                  const PopupMenuItem(
                      value: CostingStatus.underpriced,
                      child: Text('🔴 Terlalu Rendah')),
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
                      Text('Belum ada data costing',
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
                      onTap: () {
                        notifier.setActiveCosting(costing);
                        DefaultTabController.of(context).animateTo(0);
                      },
                      onDelete: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text('Hapus Costing?'),
                            content: Text(
                                'Data costing untuk "${costing.menuItemName}" akan dihapus.'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Batal'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(context, true),
                                style: FilledButton.styleFrom(
                                    backgroundColor:
                                        Theme.of(context).colorScheme.error),
                                child: const Text('Hapus'),
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
// Helper Widgets (tidak perlu akses provider → tetap StatelessWidget)
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
            Text('Ideal: 30-50% untuk restoran',
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
                  'Rekomendasi Harga Jual',
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
                  'Sudah dibulatkan ke kelipatan Rp 500',
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
            '📊 Rincian Biaya Operasional — ${expense.periodLabel}',
            style: const TextStyle(
              color: Color(0xFF6A1B9A),
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          _ExpenseLine('Total Labor', expense.totalLaborCost),
          _ExpenseLine('Total Utilitas', expense.totalUtilityCost),
          _ExpenseLine('Sewa & Overhead', expense.totalOverheadCost),
          const Divider(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total OpEx / bulan',
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
              Text('Estimasi porsi/bulan',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline)),
              Text('${expense.estimatedPortionsSoldMonthly} porsi',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline)),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('⚡ Alokasi per porsi',
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