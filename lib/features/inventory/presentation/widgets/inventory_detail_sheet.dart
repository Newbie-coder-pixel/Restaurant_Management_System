import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/inventory_item.dart';
import '../../providers/inventory_provider.dart';
import 'add_inventory_form.dart';
import '../../../../core/supabase_client.dart';

// ─── LOCAL PROVIDERS ──────────────────────────────────────────────────────────

final _branchListProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, currentBranchId) async {
  final response = await supabase
      .from('branches')
      .select('id, name')
      .neq('id', currentBranchId)
      .order('name');
  return List<Map<String, dynamic>>.from(response as List);
});

final _targetItemProvider = FutureProvider.autoDispose
    .family<List<InventoryItem>, ({String branchId, String itemName})>(
        (ref, args) async {
  final dateStr = DateTime.now().toIso8601String().split('T').first;
  final response = await supabase
      .from('inventory_items')
      .select()
      .eq('branch_id', args.branchId)
      .eq('date', dateStr)
      .ilike('name', '%${args.itemName}%');
  return (response as List)
      .map((e) => InventoryItem.fromMap(e as Map<String, dynamic>))
      .toList();
});

// ─── MAIN WIDGET ──────────────────────────────────────────────────────────────

class InventoryDetailSheet extends ConsumerStatefulWidget {
  final InventoryItem item;
  const InventoryDetailSheet({super.key, required this.item});

  @override
  ConsumerState<InventoryDetailSheet> createState() =>
      _InventoryDetailSheetState();
}

class _InventoryDetailSheetState extends ConsumerState<InventoryDetailSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _fmt(double v) =>
      v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  String _fmtCurrency(double v) {
    final formatted = v.toInt().toString().replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]}.',
        );
    return formatted;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final item = widget.item;

    Color statusColor = item.isOutOfStock
        ? Colors.red.shade500
        : item.isLowStock
            ? Colors.orange.shade600
            : Colors.green.shade600;

    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (_, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Handle
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 8),
              child: Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: colorScheme.primaryContainer
                                    .withValues(alpha: 0.6),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                item.category,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: colorScheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '• ${item.unit}',
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.onSurface.withValues(alpha: 0.5),
                              ),
                            ),
                            if (item.hasSecondaryUnit) ...[
                              Text(
                                ' / ${item.unitSecondary}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colorScheme.primary.withValues(alpha: 0.7),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      Navigator.pop(context);
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (_) => AddInventoryForm(
                          branchId: item.branchId,
                          editItem: item,
                        ),
                      );
                    },
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: 'Edit',
                  ),
                  IconButton(
                    onPressed: () => _showDeleteDialog(context, ref),
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    tooltip: 'Hapus',
                  ),
                ],
              ),
            ),

            // Stock summary cards
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  _StockSummaryCard(
                    label: 'Stok Awal',
                    value: item.openingStock,
                    secondaryValue: item.hasSecondaryUnit
                        ? item.openingStockSecondary : null,
                    unit: item.unit,
                    unitSecondary: item.unitSecondary,
                    color: Colors.blue.shade400,
                    icon: Icons.inventory_2_outlined,
                  ),
                  const SizedBox(width: 8),
                  _StockSummaryCard(
                    label: 'Terpakai',
                    value: item.usedStock,
                    secondaryValue: item.hasSecondaryUnit
                        ? item.usedStockSecondary : null,
                    unit: item.unit,
                    unitSecondary: item.unitSecondary,
                    color: Colors.orange.shade500,
                    icon: Icons.restaurant_outlined,
                    isNegative: true,
                  ),
                  const SizedBox(width: 8),
                  _StockSummaryCard(
                    label: 'Stok Akhir',
                    value: item.closingStock,
                    secondaryValue: item.hasSecondaryUnit
                        ? item.availableStockSecondary : null,
                    unit: item.unit,
                    unitSecondary: item.unitSecondary,
                    color: statusColor,
                    icon: Icons.check_circle_outline,
                    highlight: true,
                  ),
                ],
              ),
            ),

            // Detail breakdown
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    _DetailRow(label: '📦 Pembelian',
                        value: '+${_fmt(item.purchasedStock)} ${item.unit}',
                        color: Colors.green.shade500),
                    _DetailRow(label: '↩️ Transfer Masuk',
                        value: '+${_fmt(item.transferIn)} ${item.unit}',
                        color: Colors.teal.shade500),
                    _DetailRow(label: '🗑️ Terbuang',
                        value: '-${_fmt(item.wasteStock)} ${item.unit}',
                        color: Colors.red.shade400),
                    _DetailRow(label: '↪️ Transfer Keluar',
                        value: '-${_fmt(item.transferOut)} ${item.unit}',
                        color: Colors.purple.shade400),
                    _DetailRow(label: '⚙️ Penyesuaian',
                        value: '${item.adjustmentStock >= 0 ? '+' : ''}${_fmt(item.adjustmentStock)} ${item.unit}',
                        color: Colors.blueGrey.shade400),
                    const Divider(height: 16),
                    _DetailRow(
                        label: '💰 Nilai Stok Tersedia',
                        value: 'Rp ${_fmtCurrency(item.availableStock * item.costPerUnit)}',
                        color: colorScheme.primary,
                        isBold: true),
                    _DetailRow(
                        label: '📊 HPP Terpakai',
                        value: 'Rp ${_fmtCurrency(item.usedStock * item.costPerUnit)}',
                        color: Colors.orange.shade600,
                        isBold: true),
                    // Harga per satuan kecil
                    if (item.hasSecondaryUnit)
                      _DetailRow(
                          label: '🏷️ Harga per ${item.unitSecondary}',
                          value: 'Rp ${_fmtCurrency(item.costPerUnitSecondary)}',
                          color: Colors.teal.shade600,
                          isBold: true),
                  ],
                ),
              ),
            ),

            // Tabs: Aksi | Histori Terpakai | Summary
            TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: 'Aksi'),
                Tab(text: 'Histori Terpakai'),
                Tab(text: 'Summary'),
              ],
              labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),

            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _ActionsTab(item: item),
                  _UsageHistoryTab(item: item),
                  _SummaryTab(item: item),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteDialog(BuildContext context, WidgetRef ref) {
    final hasStock = widget.item.availableStock > 0;

    if (hasStock) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Tidak Bisa Dihapus'),
          content: Text(
            'Item "${widget.item.name}" masih memiliki stok ${widget.item.availableStock} ${widget.item.unit}. Kosongkan stok terlebih dahulu.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hapus Item'),
        content: Text('Yakin ingin menghapus "${widget.item.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              Navigator.pop(context);
              await supabase
                  .from('inventory_items')
                  .delete()
                  .eq('id', widget.item.id);
              ref.invalidate(inventoryStreamProvider(widget.item.branchId));
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
  }
}

// ─── TAB 1: AKSI ─────────────────────────────────────────────────────────────

class _ActionsTab extends ConsumerStatefulWidget {
  final InventoryItem item;
  const _ActionsTab({required this.item});

  @override
  ConsumerState<_ActionsTab> createState() => _ActionsTabState();
}

class _ActionsTabState extends ConsumerState<_ActionsTab> {
  final _qtyCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  String _selectedAction = 'purchase';
  bool _isLoading = false;
  bool _useSecondaryUnit = false;

  String? _selectedToBranchId;
  String? _selectedToBranchName;
  String? _selectedToItemId;

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  void _resetTransferState() {
    _selectedToBranchId = null;
    _selectedToBranchName = null;
    _selectedToItemId = null;
  }

  // Konversi qty ke satuan utama jika pakai satuan sekunder
  double _convertQty(double inputQty) {
    if (_useSecondaryUnit && widget.item.hasSecondaryUnit) {
      return inputQty / widget.item.unitConversion;
    }
    return inputQty;
  }

  Future<void> _submit() async {
    final rawQty = double.tryParse(_qtyCtrl.text);
    if (rawQty == null || rawQty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Masukkan jumlah yang valid')),
      );
      return;
    }

    final qty = _convertQty(rawQty);
    setState(() => _isLoading = true);

    try {
      final notifier = ref.read(inventoryNotifierProvider.notifier);
      final note = _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim();

      switch (_selectedAction) {
        case 'purchase':
          await notifier.recordPurchase(
              itemId: widget.item.id, quantity: qty, note: note);
          break;
        case 'waste':
          await notifier.recordWaste(
              itemId: widget.item.id, quantity: qty, note: note);
          break;
        case 'adjustment':
          await notifier.adjustStock(
              itemId: widget.item.id,
              adjustmentQty: qty,
              reason: note ?? 'Stock opname');
          break;
        case 'transfer_out':
          if (_selectedToBranchId == null || _selectedToItemId == null) {
            setState(() => _isLoading = false);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Pilih cabang dan item tujuan'),
                  backgroundColor: Colors.orange,
                ),
              );
            }
            return;
          }
          await notifier.recordTransfer(
            fromItemId: widget.item.id,
            toItemId: _selectedToItemId!,
            toBranchId: _selectedToBranchId!,
            quantity: qty,
          );
          setState(() => _resetTransferState());
          break;
      }

      _qtyCtrl.clear();
      _noteCtrl.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Berhasil disimpan'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final item = widget.item;
    final activeUnit = _useSecondaryUnit && item.hasSecondaryUnit
        ? item.unitSecondary!
        : item.unit;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Action selector
          Text('Jenis Transaksi',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface.withValues(alpha: 0.6),
              )),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              _ActionChip(label: '📦 Beli', isSelected: _selectedAction == 'purchase',
                  color: Colors.green.shade500,
                  onTap: () => setState(() { _selectedAction = 'purchase'; _resetTransferState(); })),
              _ActionChip(label: '🗑️ Buang', isSelected: _selectedAction == 'waste',
                  color: Colors.red.shade500,
                  onTap: () => setState(() { _selectedAction = 'waste'; _resetTransferState(); })),
              _ActionChip(label: '⚙️ Sesuaikan', isSelected: _selectedAction == 'adjustment',
                  color: Colors.blue.shade500,
                  onTap: () => setState(() { _selectedAction = 'adjustment'; _resetTransferState(); })),
              _ActionChip(label: '🔄 Transfer', isSelected: _selectedAction == 'transfer_out',
                  color: Colors.purple.shade500,
                  onTap: () => setState(() => _selectedAction = 'transfer_out')),
            ],
          ),
          const SizedBox(height: 16),

          if (_selectedAction == 'transfer_out')
            _TransferTargetPanel(
              currentBranchId: item.branchId,
              itemName: item.name,
              selectedBranchId: _selectedToBranchId,
              selectedBranchName: _selectedToBranchName,
              selectedItemId: _selectedToItemId,
              onBranchSelected: (id, name) => setState(() {
                _selectedToBranchId = id;
                _selectedToBranchName = name;
                _selectedToItemId = null;
              }),
              onItemSelected: (id) => setState(() => _selectedToItemId = id),
            ),
          if (_selectedAction == 'transfer_out') const SizedBox(height: 12),

          // Toggle satuan sekunder
          if (item.hasSecondaryUnit) ...[
            GestureDetector(
              onTap: () => setState(() {
                _useSecondaryUnit = !_useSecondaryUnit;
                _qtyCtrl.clear();
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: _useSecondaryUnit
                      ? colorScheme.primaryContainer.withValues(alpha: 0.4)
                      : colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _useSecondaryUnit
                          ? Icons.check_box_rounded
                          : Icons.check_box_outline_blank_rounded,
                      size: 16,
                      color: _useSecondaryUnit
                          ? colorScheme.primary
                          : colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Input dalam ${item.unitSecondary} (1 ${item.unit} = ${item.unitConversion.toInt()} ${item.unitSecondary})',
                      style: TextStyle(
                        fontSize: 12,
                        color: _useSecondaryUnit
                            ? colorScheme.primary
                            : colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],

          // Qty input
          TextField(
            controller: _qtyCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
            ],
            decoration: InputDecoration(
              labelText: 'Jumlah ($activeUnit)',
              filled: true,
              fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Note
          TextField(
            controller: _noteCtrl,
            decoration: InputDecoration(
              labelText: 'Catatan (opsional)',
              filled: true,
              fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 16),

          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _isLoading ? null : _submit,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: _isLoading
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Simpan Transaksi',
                      style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── TAB 2: HISTORI TERPAKAI ──────────────────────────────────────────────────

class _UsageHistoryTab extends ConsumerWidget {
  final InventoryItem item;
  const _UsageHistoryTab({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transactionsAsync = ref.watch(inventoryTransactionsProvider(item.id));

    return transactionsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (transactions) {
        // Filter hanya yang terpakai (order_deduct)
        final usageList = transactions
            .where((t) => t.type == 'order_deduct')
            .toList();

        if (usageList.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.restaurant_outlined, size: 48,
                    color: Colors.grey.withValues(alpha: 0.5)),
                const SizedBox(height: 12),
                const Text('Belum ada riwayat pemakaian',
                    style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 4),
                Text(
                  'Bahan ini akan tercatat saat dipakai dalam order',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.withValues(alpha: 0.7),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        // Hitung total terpakai
        final totalUsed = usageList.fold(0.0, (sum, t) => sum + t.quantity);
        final totalUsedSecondary = item.hasSecondaryUnit
            ? totalUsed * item.unitConversion : null;

        return Column(
          children: [
            // Summary terpakai
            Container(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.restaurant_rounded,
                      color: Colors.orange.shade600, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Total Terpakai Hari Ini',
                            style: TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w600)),
                        Text(
                          '${_fmtQty(totalUsed)} ${item.unit}'
                          '${totalUsedSecondary != null ? ' (≈ ${_fmtQty(totalUsedSecondary)} ${item.unitSecondary})' : ''}',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Colors.orange.shade700,
                          ),
                        ),
                        Text(
                          'Nilai: Rp ${_fmtCurrency(totalUsed * item.costPerUnit)}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.orange.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // List histori
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                itemCount: usageList.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final t = usageList[i];
                  final qtySecondary = item.hasSecondaryUnit
                      ? t.quantity * item.unitConversion : null;

                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.restaurant,
                          size: 18, color: Colors.orange.shade500),
                    ),
                    title: Text(
                      t.menuItemName ?? t.note ?? 'Order',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      _formatTime(t.createdAt),
                      style: const TextStyle(fontSize: 11),
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '-${_fmtQty(t.quantity)} ${item.unit}',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Colors.orange.shade600,
                            fontSize: 13,
                          ),
                        ),
                        if (qtySecondary != null)
                          Text(
                            '≈ ${_fmtQty(qtySecondary)} ${item.unitSecondary}',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.orange.shade400,
                            ),
                          ),
                      ],
                    ),
                    dense: true,
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  String _fmtQty(double v) =>
      v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

  String _fmtCurrency(double v) {
    return v.toInt().toString().replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]}.',
        );
  }

  String _formatTime(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

// ─── TAB 3: SUMMARY ───────────────────────────────────────────────────────────

class _SummaryTab extends StatelessWidget {
  final InventoryItem item;
  const _SummaryTab({required this.item});

  String _fmtQty(double v) =>
      v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

  String _fmtCurrency(double v) {
    return 'Rp ${v.toInt().toString().replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]}.',
        )}';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Rumus inventory
          const _SectionTitle('📐 Rumus Perhitungan Stok'),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: colorScheme.primary.withValues(alpha: 0.3)),
            ),
            child: Column(
              children: [
                _FormulaRow(
                  label: 'Stok Awal',
                  value: '${_fmtQty(item.openingStock)} ${item.unit}',
                  secondaryValue: item.hasSecondaryUnit
                      ? '≈ ${_fmtQty(item.openingStockSecondary)} ${item.unitSecondary}'
                      : null,
                  color: Colors.blue.shade500,
                  prefix: '',
                ),
                _FormulaRow(
                  label: 'Pembelian',
                  value: '${_fmtQty(item.purchasedStock)} ${item.unit}',
                  color: Colors.green.shade500,
                  prefix: '+',
                ),
                _FormulaRow(
                  label: 'Transfer Masuk',
                  value: '${_fmtQty(item.transferIn)} ${item.unit}',
                  color: Colors.teal.shade500,
                  prefix: '+',
                ),
                _FormulaRow(
                  label: 'Terpakai (Order)',
                  value: '${_fmtQty(item.usedStock)} ${item.unit}',
                  secondaryValue: item.hasSecondaryUnit
                      ? '≈ ${_fmtQty(item.usedStockSecondary)} ${item.unitSecondary}'
                      : null,
                  color: Colors.orange.shade500,
                  prefix: '-',
                ),
                _FormulaRow(
                  label: 'Terbuang',
                  value: '${_fmtQty(item.wasteStock)} ${item.unit}',
                  color: Colors.red.shade400,
                  prefix: '-',
                ),
                _FormulaRow(
                  label: 'Transfer Keluar',
                  value: '${_fmtQty(item.transferOut)} ${item.unit}',
                  color: Colors.purple.shade400,
                  prefix: '-',
                ),
                _FormulaRow(
                  label: 'Penyesuaian',
                  value: '${item.adjustmentStock >= 0 ? '+' : ''}${_fmtQty(item.adjustmentStock)} ${item.unit}',
                  color: Colors.blueGrey.shade400,
                  prefix: '±',
                ),
                const Divider(height: 20),
                _FormulaRow(
                  label: '= Stok Akhir',
                  value: '${_fmtQty(item.closingStock)} ${item.unit}',
                  secondaryValue: item.hasSecondaryUnit
                      ? '≈ ${_fmtQty(item.availableStockSecondary)} ${item.unitSecondary}'
                      : null,
                  color: Colors.green.shade600,
                  prefix: '',
                  isBold: true,
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Kalkulasi harga
          const _SectionTitle('💰 Kalkulasi Harga'),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green.withValues(alpha: 0.25)),
            ),
            child: Column(
              children: [
                _CalcRow(
                  label: 'Harga per ${item.unit}',
                  value: _fmtCurrency(item.costPerUnit),
                ),
                if (item.hasSecondaryUnit) ...[
                  _CalcRow(
                    label: 'Konversi',
                    value: '1 ${item.unit} = ${_fmtQty(item.unitConversion)} ${item.unitSecondary}',
                  ),
                  _CalcRow(
                    label: 'Harga per ${item.unitSecondary}',
                    value: _fmtCurrency(item.costPerUnitSecondary),
                    highlight: true,
                  ),
                ],
                const Divider(height: 16),
                _CalcRow(
                  label: 'Nilai Stok Tersedia',
                  value: _fmtCurrency(item.availableStock * item.costPerUnit),
                  highlight: true,
                ),
                _CalcRow(
                  label: 'HPP Terpakai',
                  value: _fmtCurrency(item.usedStock * item.costPerUnit),
                  color: Colors.orange.shade600,
                ),
                _CalcRow(
                  label: 'Nilai Terbuang',
                  value: _fmtCurrency(item.wasteStock * item.costPerUnit),
                  color: Colors.red.shade400,
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Info satuan
          if (item.hasSecondaryUnit) ...[
            const _SectionTitle('📏 Info Satuan'),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.secondaryContainer.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  _CalcRow(
                    label: 'Satuan Utama',
                    value: item.unit,
                  ),
                  _CalcRow(
                    label: 'Satuan Kecil',
                    value: item.unitSecondary ?? '-',
                  ),
                  _CalcRow(
                    label: 'Konversi',
                    value: '1 ${item.unit} = ${_fmtQty(item.unitConversion)} ${item.unitSecondary}',
                    highlight: true,
                  ),
                  _CalcRow(
                    label: 'Stok dalam ${item.unitSecondary}',
                    value: '${_fmtQty(item.availableStockSecondary)} ${item.unitSecondary}',
                    highlight: true,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── HELPERS ──────────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _FormulaRow extends StatelessWidget {
  final String label;
  final String value;
  final String? secondaryValue;
  final Color color;
  final String prefix;
  final bool isBold;

  const _FormulaRow({
    required this.label,
    required this.value,
    this.secondaryValue,
    required this.color,
    required this.prefix,
    this.isBold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            child: Text(
              prefix,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: isBold ? 13 : 12,
                fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
                color: Theme.of(context).colorScheme.onSurface
                    .withValues(alpha: isBold ? 0.9 : 0.7),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: isBold ? 14 : 12,
                  fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
                  color: color,
                ),
              ),
              if (secondaryValue != null)
                Text(
                  secondaryValue!,
                  style: TextStyle(
                    fontSize: 10,
                    color: color.withValues(alpha: 0.7),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CalcRow extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;
  final Color? color;

  const _CalcRow({
    required this.label,
    required this.value,
    this.highlight = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? (highlight
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7));

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: highlight ? FontWeight.w700 : FontWeight.w500,
              color: Theme.of(context).colorScheme.onSurface
                  .withValues(alpha: highlight ? 0.85 : 0.6),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: highlight ? 14 : 12,
              fontWeight: highlight ? FontWeight.w800 : FontWeight.w600,
              color: c,
            ),
          ),
        ],
      ),
    );
  }
}

class _StockSummaryCard extends StatelessWidget {
  final String label;
  final double value;
  final double? secondaryValue;
  final String unit;
  final String? unitSecondary;
  final Color color;
  final IconData icon;
  final bool isNegative;
  final bool highlight;

  const _StockSummaryCard({
    required this.label,
    required this.value,
    this.secondaryValue,
    required this.unit,
    this.unitSecondary,
    required this.color,
    required this.icon,
    this.isNegative = false,
    this.highlight = false,
  });

  String _fmt(double v) =>
      v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: highlight
              ? color.withValues(alpha: 0.1)
              : colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(12),
          border: highlight ? Border.all(color: color.withValues(alpha: 0.3)) : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(height: 4),
            Text(
              '${isNegative && value > 0 ? '-' : ''}${_fmt(value)}',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            Text(unit,
                style: TextStyle(
                    fontSize: 9,
                    color: colorScheme.onSurface.withValues(alpha: 0.45))),
            if (secondaryValue != null && unitSecondary != null)
              Text(
                '≈ ${_fmt(secondaryValue!)} $unitSecondary',
                style: TextStyle(
                  fontSize: 9,
                  color: color.withValues(alpha: 0.7),
                  fontWeight: FontWeight.w600,
                ),
              ),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(
                    fontSize: 9,
                    color: colorScheme.onSurface.withValues(alpha: 0.5),
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool isBold;

  const _DetailRow({
    required this.label,
    required this.value,
    required this.color,
    this.isBold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
                color: Theme.of(context).colorScheme.onSurface
                    .withValues(alpha: isBold ? 0.8 : 0.6),
              )),
          Text(value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
                color: color,
              )),
        ],
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final Color color;
  final VoidCallback onTap;

  const _ActionChip({
    required this.label,
    required this.isSelected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.15)
              : Theme.of(context).colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(8),
          border: isSelected ? Border.all(color: color.withValues(alpha: 0.5)) : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isSelected
                ? color
                : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }
}

class _TransferTargetPanel extends ConsumerWidget {
  final String currentBranchId;
  final String itemName;
  final String? selectedBranchId;
  final String? selectedBranchName;
  final String? selectedItemId;
  final void Function(String id, String name) onBranchSelected;
  final void Function(String id) onItemSelected;

  const _TransferTargetPanel({
    required this.currentBranchId,
    required this.itemName,
    required this.selectedBranchId,
    required this.selectedBranchName,
    required this.selectedItemId,
    required this.onBranchSelected,
    required this.onItemSelected,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final branchAsync = ref.watch(_branchListProvider(currentBranchId));

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.purple.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.purple.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.swap_horiz, size: 14, color: Colors.purple.shade400),
              const SizedBox(width: 6),
              Text('Tujuan Transfer',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.purple.shade700)),
            ],
          ),
          const SizedBox(height: 10),
          branchAsync.when(
            loading: () => const Center(
                child: SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))),
            error: (e, _) => Text('Gagal memuat cabang: $e',
                style: const TextStyle(color: Colors.red, fontSize: 12)),
            data: (branches) {
              if (branches.isEmpty) {
                return const Text('Tidak ada cabang lain',
                    style: TextStyle(fontSize: 12));
              }
              return DropdownButtonFormField<String>(
                initialValue: selectedBranchId,
                decoration: InputDecoration(
                  labelText: 'Cabang Tujuan',
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
                items: branches.map((b) => DropdownMenuItem<String>(
                  value: b['id'] as String,
                  child: Text(b['name'] as String,
                      style: const TextStyle(fontSize: 13)),
                )).toList(),
                onChanged: (id) {
                  if (id == null) return;
                  final name = branches.firstWhere(
                      (b) => b['id'] == id)['name'] as String;
                  onBranchSelected(id, name);
                },
              );
            },
          ),
          if (selectedBranchId != null) ...[
            const SizedBox(height: 10),
            Consumer(
              builder: (context, ref, _) {
                final itemsAsync = ref.watch(_targetItemProvider(
                    (branchId: selectedBranchId!, itemName: itemName)));
                return itemsAsync.when(
                  loading: () => const Center(
                      child: SizedBox(width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))),
                  error: (e, _) => Text('Gagal: $e',
                      style: const TextStyle(color: Colors.red, fontSize: 12)),
                  data: (items) {
                    if (items.isEmpty) {
                      return Text(
                        'Item "$itemName" tidak ditemukan di $selectedBranchName',
                        style: const TextStyle(fontSize: 12, color: Colors.orange),
                      );
                    }
                    return DropdownButtonFormField<String>(
                      initialValue: selectedItemId,
                      decoration: InputDecoration(
                        labelText: 'Item Tujuan',
                        filled: true,
                        fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      ),
                      items: items.map((i) => DropdownMenuItem<String>(
                        value: i.id,
                        child: Text('${i.name} (${i.availableStock} ${i.unit})',
                            style: const TextStyle(fontSize: 13)),
                      )).toList(),
                      onChanged: (id) { if (id != null) onItemSelected(id); },
                    );
                  },
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}