// lib/features/inventory/presentation/inventory_detail_sheet.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/inventory_item.dart';
import '../providers/inventory_provider.dart';
import 'widgets/add_inventory_form.dart';

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
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name,
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
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
                                color: colorScheme.onSurface
                                    .withValues(alpha: 0.5),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Edit button
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
                ],
              ),
            ),

            // Stock summary cards
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  _StockSummaryCard(
                    label: 'Stok Awal',
                    value: item.openingStock,
                    unit: item.unit,
                    color: Colors.blue.shade400,
                    icon: Icons.inventory_2_outlined,
                  ),
                  const SizedBox(width: 8),
                  _StockSummaryCard(
                    label: 'Terpakai',
                    value: item.usedStock,
                    unit: item.unit,
                    color: Colors.orange.shade500,
                    icon: Icons.restaurant_outlined,
                    isNegative: true,
                  ),
                  const SizedBox(width: 8),
                  _StockSummaryCard(
                    label: 'Stok Akhir',
                    value: item.closingStock,
                    unit: item.unit,
                    color: statusColor,
                    icon: Icons.check_circle_outline,
                    highlight: true,
                  ),
                ],
              ),
            ),

            // Detail breakdown
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    _DetailRow(
                      label: '📦 Pembelian',
                      value: '+${_fmt(item.purchasedStock)} ${item.unit}',
                      color: Colors.green.shade500,
                    ),
                    _DetailRow(
                      label: '↩️ Transfer Masuk',
                      value: '+${_fmt(item.transferIn)} ${item.unit}',
                      color: Colors.teal.shade500,
                    ),
                    _DetailRow(
                      label: '🗑️ Terbuang',
                      value: '-${_fmt(item.wasteStock)} ${item.unit}',
                      color: Colors.red.shade400,
                    ),
                    _DetailRow(
                      label: '↪️ Transfer Keluar',
                      value: '-${_fmt(item.transferOut)} ${item.unit}',
                      color: Colors.purple.shade400,
                    ),
                    _DetailRow(
                      label: '⚙️ Penyesuaian',
                      value:
                          '${item.adjustmentStock >= 0 ? '+' : ''}${_fmt(item.adjustmentStock)} ${item.unit}',
                      color: Colors.blueGrey.shade400,
                    ),
                    const Divider(height: 16),
                    _DetailRow(
                      label: '💰 Nilai Stok Tersedia',
                      value:
                          'Rp ${_fmtCurrency(item.availableStock * item.costPerUnit)}',
                      color: colorScheme.primary,
                      isBold: true,
                    ),
                    _DetailRow(
                      label: '📊 HPP Terpakai',
                      value:
                          'Rp ${_fmtCurrency(item.usedStock * item.costPerUnit)}',
                      color: Colors.orange.shade600,
                      isBold: true,
                    ),
                  ],
                ),
              ),
            ),

            // Tabs: Aksi | Histori
            TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: 'Aksi'),
                Tab(text: 'Histori Transaksi'),
              ],
            ),

            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _ActionsTab(item: item),
                  _TransactionHistoryTab(itemId: item.id),
                ],
              ),
            ),
          ],
        ),
      ),
    );
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
}

// ─── ACTIONS TAB ──────────────────────────────────────────────────────────────

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

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final qty = double.tryParse(_qtyCtrl.text);
    if (qty == null || qty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Masukkan jumlah yang valid')),
      );
      return;
    }

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
          Row(
            children: [
              _ActionChip(
                label: '📦 Beli',
                isSelected: _selectedAction == 'purchase',
                color: Colors.green.shade500,
                onTap: () => setState(() => _selectedAction = 'purchase'),
              ),
              const SizedBox(width: 8),
              _ActionChip(
                label: '🗑️ Buang',
                isSelected: _selectedAction == 'waste',
                color: Colors.red.shade500,
                onTap: () => setState(() => _selectedAction = 'waste'),
              ),
              const SizedBox(width: 8),
              _ActionChip(
                label: '⚙️ Sesuaikan',
                isSelected: _selectedAction == 'adjustment',
                color: Colors.blue.shade500,
                onTap: () => setState(() => _selectedAction = 'adjustment'),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Qty input
          TextField(
            controller: _qtyCtrl,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
            ],
            decoration: InputDecoration(
              labelText:
                  'Jumlah (${widget.item.unit})',
              filled: true,
              fillColor:
                  colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
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
              fillColor:
                  colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
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
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text(
                      'Simpan Transaksi',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── TRANSACTION HISTORY TAB ──────────────────────────────────────────────────

class _TransactionHistoryTab extends ConsumerWidget {
  final String itemId;
  const _TransactionHistoryTab({required this.itemId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transactionsAsync =
        ref.watch(inventoryTransactionsProvider(itemId));

    return transactionsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (transactions) {
        if (transactions.isEmpty) {
          return const Center(child: Text('Belum ada transaksi'));
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: transactions.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final t = transactions[i];
            final (icon, color, label) = _typeInfo(t.type);
            return ListTile(
              leading: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 18, color: color),
              ),
              title: Text(
                label,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                t.note ?? '',
                style: const TextStyle(fontSize: 11),
              ),
              trailing: Text(
                '${t.quantity >= 0 ? '+' : ''}${t.quantity}',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: color,
                  fontSize: 14,
                ),
              ),
              dense: true,
            );
          },
        );
      },
    );
  }

  (IconData, Color, String) _typeInfo(String type) {
    switch (type) {
      case 'purchase':
        return (Icons.add_shopping_cart, Colors.green.shade500, 'Pembelian');
      case 'order_deduct':
        return (Icons.restaurant, Colors.orange.shade500, 'Pemakaian Order');
      case 'waste':
        return (Icons.delete_outline, Colors.red.shade400, 'Terbuang');
      case 'transfer_in':
        return (Icons.arrow_downward, Colors.teal.shade500, 'Transfer Masuk');
      case 'transfer_out':
        return (Icons.arrow_upward, Colors.purple.shade400, 'Transfer Keluar');
      case 'adjustment':
        return (Icons.tune, Colors.blue.shade500, 'Penyesuaian');
      default:
        return (Icons.swap_horiz, Colors.grey, type);
    }
  }
}

// ─── HELPERS ──────────────────────────────────────────────────────────────────

class _StockSummaryCard extends StatelessWidget {
  final String label;
  final double value;
  final String unit;
  final Color color;
  final IconData icon;
  final bool isNegative;
  final bool highlight;

  const _StockSummaryCard({
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
    required this.icon,
    this.isNegative = false,
    this.highlight = false,
  });

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
          border: highlight
              ? Border.all(color: color.withValues(alpha: 0.3))
              : null,
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
            Text(
              unit,
              style: TextStyle(
                fontSize: 9,
                color: colorScheme.onSurface.withValues(alpha: 0.45),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                color: colorScheme.onSurface.withValues(alpha: 0.5),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(double v) =>
      v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
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
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: isBold ? 0.8 : 0.6),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
              color: color,
            ),
          ),
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
              : Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest
                  .withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(8),
          border: isSelected
              ? Border.all(color: color.withValues(alpha: 0.5))
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isSelected
                ? color
                : Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }
}
