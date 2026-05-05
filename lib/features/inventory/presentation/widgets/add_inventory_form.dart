// lib/features/inventory/presentation/widgets/add_inventory_form.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/inventory_item.dart';
import '../../providers/inventory_provider.dart';

class AddInventoryForm extends ConsumerStatefulWidget {
  final String branchId;
  final InventoryItem? editItem; // null = add, non-null = edit

  const AddInventoryForm({
    super.key,
    required this.branchId,
    this.editItem,
  });

  @override
  ConsumerState<AddInventoryForm> createState() => _AddInventoryFormState();
}

class _AddInventoryFormState extends ConsumerState<AddInventoryForm> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _openingStockCtrl = TextEditingController();
  final _minimumStockCtrl = TextEditingController();
  final _costCtrl = TextEditingController();

  String _selectedUnit = 'kg';
  String _selectedCategory = 'Bahan Baku';
  bool _isLoading = false;

  final _units = ['kg', 'gram', 'liter', 'ml', 'pcs', 'botol', 'bungkus', 'dus', 'buah'];
  final _categories = [
    'Bahan Baku',
    'Minuman',
    'Bumbu & Rempah',
    'Minyak & Lemak',
    'Packaging',
    'Peralatan',
    'Lainnya',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.editItem != null) {
      final item = widget.editItem!;
      _nameCtrl.text = item.name;
      _openingStockCtrl.text = item.openingStock.toString();
      _minimumStockCtrl.text = item.minimumStock.toString();
      _costCtrl.text = item.costPerUnit.toString();
      _selectedUnit = item.unit;
      _selectedCategory = item.category;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _openingStockCtrl.dispose();
    _minimumStockCtrl.dispose();
    _costCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final now = DateTime.now();
      final item = InventoryItem(
        id: widget.editItem?.id ?? '',
        branchId: widget.branchId,
        name: _nameCtrl.text.trim(),
        unit: _selectedUnit,
        category: _selectedCategory,
        openingStock: double.tryParse(_openingStockCtrl.text) ?? 0,
        usedStock: widget.editItem?.usedStock ?? 0,
        wasteStock: widget.editItem?.wasteStock ?? 0,
        purchasedStock: widget.editItem?.purchasedStock ?? 0,
        transferIn: widget.editItem?.transferIn ?? 0,
        transferOut: widget.editItem?.transferOut ?? 0,
        adjustmentStock: widget.editItem?.adjustmentStock ?? 0,
        minimumStock: double.tryParse(_minimumStockCtrl.text) ?? 0,
        costPerUnit: double.tryParse(_costCtrl.text) ?? 0,
        date: now,
        createdAt: widget.editItem?.createdAt ?? now,
        updatedAt: now,
      );

      final notifier = ref.read(inventoryNotifierProvider.notifier);
      if (widget.editItem != null) {
        await notifier.updateItem(item);
      } else {
        await notifier.addItem(item);
      }

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal menyimpan: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isEdit = widget.editItem != null;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),

            Text(
              isEdit ? 'Edit Item Inventory' : 'Tambah Item Inventory',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 20),

            // Nama item
            _buildTextField(
              controller: _nameCtrl,
              label: 'Nama Bahan / Item',
              hint: 'cth. Tepung Terigu, Minyak Goreng...',
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Nama wajib diisi' : null,
            ),
            const SizedBox(height: 12),

            // Unit + Category
            Row(
              children: [
                Expanded(
                  child: _buildDropdown(
                    label: 'Satuan',
                    value: _selectedUnit,
                    items: _units,
                    onChanged: (v) => setState(() => _selectedUnit = v!),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildDropdown(
                    label: 'Kategori',
                    value: _selectedCategory,
                    items: _categories,
                    onChanged: (v) => setState(() => _selectedCategory = v!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Opening stock + Min stock
            Row(
              children: [
                Expanded(
                  child: _buildTextField(
                    controller: _openingStockCtrl,
                    label: 'Stok Awal',
                    hint: '0',
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'^\d+\.?\d{0,2}')),
                    ],
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Wajib diisi';
                      if (double.tryParse(v) == null) return 'Angka tidak valid';
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildTextField(
                    controller: _minimumStockCtrl,
                    label: 'Stok Minimum',
                    hint: '0 (opsional)',
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'^\d+\.?\d{0,2}')),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Cost per unit
            _buildTextField(
              controller: _costCtrl,
              label: 'Harga per Satuan (Rp)',
              hint: '0',
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
              ],
            ),
            const SizedBox(height: 24),

            // Submit button
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
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        isEdit ? 'Simpan Perubahan' : 'Tambah Item',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }

  Widget _buildDropdown({
    required String label,
    required String value,
    required List<String> items,
    required void Function(String?) onChanged,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return DropdownButtonFormField<String>(
      initialValue: value,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      items: items
          .map((e) => DropdownMenuItem(value: e, child: Text(e)))
          .toList(),
    );
  }
}
