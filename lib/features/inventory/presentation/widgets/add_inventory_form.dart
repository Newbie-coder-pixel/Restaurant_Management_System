// lib/features/inventory/presentation/widgets/add_inventory_form.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/inventory_item.dart';
import '../../providers/inventory_provider.dart';

class AddInventoryForm extends ConsumerStatefulWidget {
  final String branchId;
  final InventoryItem? editItem;

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
  // ── NEW: secondary unit ──
  final _unitSecondaryCtrl = TextEditingController();
  final _unitConversionCtrl = TextEditingController();

  String _selectedUnit = 'kg';
  // NOTE: category values below are stored verbatim as the `category` column
  // in Supabase (inventory_items). Left in Indonesian intentionally — see
  // translation report (logic-coupled data values, not just display labels).
  String _selectedCategory = 'Bahan Baku';
  bool _isLoading = false;
  bool _hasSecondaryUnit = false; // toggles whether the secondary unit field is shown

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
      // ── load secondary unit if present ──
      if (item.hasSecondaryUnit) {
        _hasSecondaryUnit = true;
        _unitSecondaryCtrl.text = item.unitSecondary ?? '';
        _unitConversionCtrl.text = item.unitConversion.toInt().toString();
      }
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _openingStockCtrl.dispose();
    _minimumStockCtrl.dispose();
    _costCtrl.dispose();
    _unitSecondaryCtrl.dispose();
    _unitConversionCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final now = DateTime.now();

      // Compute the secondary unit
      final unitSecondary = _hasSecondaryUnit && _unitSecondaryCtrl.text.trim().isNotEmpty
          ? _unitSecondaryCtrl.text.trim()
          : null;
      final unitConversion = _hasSecondaryUnit
          ? (double.tryParse(_unitConversionCtrl.text) ?? 1.0)
          : 1.0;

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
        unitSecondary: unitSecondary,       // ← NEW
        unitConversion: unitConversion,     // ← NEW
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
            content: Text('Failed to save: $e'),
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
        child: SingleChildScrollView(
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
                isEdit ? 'Edit Inventory Item' : 'Add Inventory Item',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 20),

              // Item name
              _buildTextField(
                controller: _nameCtrl,
                label: 'Ingredient / Item Name',
                hint: 'e.g. Flour, Cooking Oil...',
                isRequired: true,
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Name is required' : null,
              ),
              const SizedBox(height: 12),

              // Unit + Category
              Row(
                children: [
                  Expanded(
                    child: _buildDropdown(
                      label: 'Primary Unit',
                      value: _selectedUnit,
                      items: _units,
                      onChanged: (v) => setState(() => _selectedUnit = v!),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildDropdown(
                      label: 'Category',
                      value: _selectedCategory,
                      items: _categories,
                      onChanged: (v) => setState(() => _selectedCategory = v!),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // ── NEW: secondary unit toggle ──────────────────────────────
              GestureDetector(
                onTap: () => setState(() {
                  _hasSecondaryUnit = !_hasSecondaryUnit;
                  if (!_hasSecondaryUnit) {
                    _unitSecondaryCtrl.clear();
                    _unitConversionCtrl.clear();
                  }
                }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: _hasSecondaryUnit
                        ? colorScheme.primaryContainer.withValues(alpha: 0.4)
                        : colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(10),
                    border: _hasSecondaryUnit
                        ? Border.all(color: colorScheme.primary.withValues(alpha: 0.4))
                        : null,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _hasSecondaryUnit
                            ? Icons.check_box_rounded
                            : Icons.check_box_outline_blank_rounded,
                        size: 18,
                        color: _hasSecondaryUnit
                            ? colorScheme.primary
                            : colorScheme.onSurface.withValues(alpha: 0.4),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Has a smaller unit? (e.g. 1 kg = 6 pieces)',
                          style: TextStyle(
                            fontSize: 13,
                            color: _hasSecondaryUnit
                                ? colorScheme.primary
                                : colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Secondary unit fields — shown when the toggle is active
              if (_hasSecondaryUnit) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _buildTextField(
                        controller: _unitSecondaryCtrl,
                        label: 'Small Unit',
                        hint: 'e.g. piece, slice, sheet...',
                        validator: (v) => _hasSecondaryUnit && (v == null || v.trim().isEmpty)
                            ? 'Required'
                            : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildTextField(
                        controller: _unitConversionCtrl,
                        label: '1 $_selectedUnit = ? ${_unitSecondaryCtrl.text.isEmpty ? '...' : _unitSecondaryCtrl.text}',
                        hint: 'e.g. 6',
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                        ],
                        validator: (v) {
                          if (!_hasSecondaryUnit) return null;
                          if (v == null || v.trim().isEmpty) return 'Required';
                          final n = double.tryParse(v);
                          if (n == null || n <= 0) return 'Must be > 0';
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                // Conversion preview
                if (_unitConversionCtrl.text.isNotEmpty &&
                    _unitSecondaryCtrl.text.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Text(
                      '→ 1 $_selectedUnit = ${_unitConversionCtrl.text} ${_unitSecondaryCtrl.text}',
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
              // ─────────────────────────────────────────────────────────────

              const SizedBox(height: 12),

              // Opening stock + Min stock
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      controller: _openingStockCtrl,
                      label: 'Opening Stock ($_selectedUnit)',
                      hint: '0',
                      isRequired: true,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'^\d+\.?\d{0,2}')),
                      ],
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Required';
                        if (double.tryParse(v) == null) return 'Invalid';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildTextField(
                      controller: _minimumStockCtrl,
                      label: 'Minimum Stock',
                      hint: '0 (optional)',
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
                label: 'Price per $_selectedUnit (Rp)',
                hint: '0',
                isRequired: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                ],
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Required';
                  final n = double.tryParse(v);
                  if (n == null) return 'Invalid';
                  if (n <= 0) return 'Price must be greater than 0';
                  return null;
                },
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
                          isEdit ? 'Save Changes' : 'Add Item',
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
    bool isRequired = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      validator: validator,
      // Red warning is visible immediately as soon as the screen opens.
      autovalidateMode: AutovalidateMode.always,
      onChanged: (_) => setState(() {}), // rebuild for the conversion preview
      decoration: InputDecoration(
        labelText: isRequired ? '$label *' : label,
        labelStyle: TextStyle(
          color: colorScheme.onSurface.withValues(alpha: 0.7),
        ),
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
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red, width: 1.3),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
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