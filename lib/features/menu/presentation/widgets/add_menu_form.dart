// lib/features/menu/presentation/widgets/add_menu_form.dart

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../../../../shared/models/menu_model.dart';
import '../../providers/menu_provider.dart';
import '../../../inventory/models/inventory_item.dart';
import '../../../inventory/providers/inventory_provider.dart';

class AddMenuForm extends ConsumerStatefulWidget {
  final MenuItem? existingMenu;
  final String branchId;

  const AddMenuForm({
    super.key,
    this.existingMenu,
    required this.branchId,
  });

  @override
  ConsumerState<AddMenuForm> createState() => _AddMenuFormState();
}

class _AddMenuFormState extends ConsumerState<AddMenuForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _priceCtrl;

  String? _selectedCategoryId;
  File? _selectedImageFile;
  Uint8List? _selectedImageBytes;
  bool _isLoading = false;
  String? _imageError;
  bool _isSeasonal = false;
  late final TextEditingController _prepTimeCtrl;
  List<String> _selectedAllergens = [];
  List<String> _selectedDietaryLabels = [];
  List<MenuIngredientDraft> _ingredientDrafts = [];

  static const _allergenOptions = [
    ('gluten', 'Gluten', '🌾'),
    ('dairy', 'Dairy', '🥛'),
    ('eggs', 'Eggs', '🥚'),
    ('nuts', 'Nuts', '🥜'),
    ('seafood', 'Seafood', '🦐'),
    ('soy', 'Soy', '🫘'),
    ('wheat', 'Wheat', '🌿'),
    ('sesame', 'Sesame', '⚪'),
  ];

  static const _dietaryOptions = [
    ('vegetarian', 'Vegetarian', '🥦'),
    ('vegan', 'Vegan', '🌱'),
    ('halal', 'Halal', '✅'),
    ('gluten_free', 'Gluten-Free', '🚫'),
    ('dairy_free', 'Dairy-Free', '🥛'),
    ('spicy', 'Spicy', '🌶️'),
    ('low_calorie', 'Low Calorie', '⚡'),
  ];

  bool get _isEdit => widget.existingMenu != null;

  @override
  void initState() {
    super.initState();
    final menu = widget.existingMenu;
    _nameCtrl = TextEditingController(text: menu?.name ?? '');
    _descCtrl = TextEditingController(text: menu?.description ?? '');
    _priceCtrl = TextEditingController(
      text: menu?.price.toStringAsFixed(0) ?? '',
    );
    if (menu != null) {
      _selectedCategoryId = menu.categoryId;
      _isSeasonal = menu.isSeasonal;
      _selectedAllergens = List<String>.from(menu.allergens);
      _selectedDietaryLabels = List<String>.from(menu.dietaryLabels);
    }
    _prepTimeCtrl = TextEditingController(
      text: (widget.existingMenu?.preparationTimeMinutes ?? 15).toString(),
    );
    if (_isEdit) _loadExistingIngredients();
  }

  Future<void> _loadExistingIngredients() async {
    try {
      final service = ref.read(menuServiceProvider);
      final existing = await service.fetchIngredients(widget.existingMenu!.id);
      if (mounted) {
        setState(() {
          _ingredientDrafts = existing
              .map((i) => MenuIngredientDraft(
                    inventoryItemId: i.inventoryItemId,
                    inventoryItemName: i.inventoryItemName,
                    unit: i.unit,
                    quantity: i.quantity,
                  ))
              .toList();
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    _prepTimeCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      if (kIsWeb) {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.image,
          withData: true,
        );
        if (result != null && result.files.isNotEmpty) {
          final bytes = result.files.first.bytes;
          if (bytes != null) {
            setState(() {
              _selectedImageBytes = bytes;
              _selectedImageFile = null;
              _imageError = null;
            });
          }
        }
      } else {
        final picker = ImagePicker();
        final source = await _showImageSourcePicker();
        if (source == null) return;
        final picked = await picker.pickImage(
          source: source,
          imageQuality: 80,
          maxWidth: 1024,
        );
        if (picked != null) {
          setState(() {
            _selectedImageFile = File(picked.path);
            _selectedImageBytes = null;
            _imageError = null;
          });
        }
      }
    } catch (e) {
      setState(() => _imageError = 'Failed to pick image');
    }
  }

  Future<ImageSource?> _showImageSourcePicker() async {
    return showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Choose Image Source',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 12),
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.camera_alt)),
                title: const Text('Camera'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.photo_library)),
                title: const Text('Photo Gallery'),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showAddCategoryDialog(BuildContext context) async {
    final ctrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Add Category',
            style: TextStyle(fontWeight: FontWeight.w700)),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: ctrl,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Example: Drinks, Main Course...',
              filled: true,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
            validator: (v) => (v == null || v.trim().isEmpty)
                ? 'Category name cannot be empty'
                : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              Navigator.pop(dialogCtx);
              final messenger = ScaffoldMessenger.of(context);
              final success = await ref
                  .read(categoryNotifierProvider(widget.branchId).notifier)
                  .addCategory(ctrl.text.trim());
              if (mounted) {
                messenger.showSnackBar(SnackBar(
                  content: Text(success
                      ? 'Category added successfully!'
                      : 'Failed to add category.'),
                  backgroundColor: success ? Colors.green : Colors.red,
                ));
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    ctrl.dispose();
  }

  Future<void> _confirmDeleteCategory(
      BuildContext context, MenuCategory cat) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Category?',
            style: TextStyle(fontWeight: FontWeight.w700)),
        content: Text(
            'Category "${cat.name}" will be deleted. Menu items already using this category will not be affected.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style:
                FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      if (_selectedCategoryId == cat.id) {
        setState(() => _selectedCategoryId = null);
      }
      final success = await ref
          .read(categoryNotifierProvider(widget.branchId).notifier)
          .deleteCategory(cat.id);
      if (mounted) {
        messenger.showSnackBar(SnackBar(
          content: Text(success
              ? 'Category deleted successfully!'
              : 'Failed to delete category.'),
          backgroundColor: success ? Colors.green : Colors.red,
        ));
      }
    }
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    final price = double.tryParse(
          _priceCtrl.text.replaceAll(RegExp(r'[^0-9]'), ''),
        ) ??
        0;

    final dynamic imageToUpload = _selectedImageFile ?? _selectedImageBytes;
    bool success;

    if (_isEdit) {
      success = await ref.read(menuProvider.notifier).updateMenu(
            item: widget.existingMenu!.copyWith(
              name: _nameCtrl.text.trim(),
              description: _descCtrl.text.trim(),
              price: price,
              categoryId: _selectedCategoryId,
              isSeasonal: _isSeasonal,
              preparationTimeMinutes: int.tryParse(_prepTimeCtrl.text) ?? 15,
              allergens: _selectedAllergens,
              dietaryLabels: _selectedDietaryLabels,
            ),
            newImageFile: imageToUpload,
            ingredients: _ingredientDrafts,
          );
    } else {
      success = await ref.read(menuProvider.notifier).addMenu(
            branchId: widget.branchId,
            name: _nameCtrl.text.trim(),
            description: _descCtrl.text.trim(),
            price: price,
            categoryId: _selectedCategoryId,
            isSeasonal: _isSeasonal,
            preparationTimeMinutes: int.tryParse(_prepTimeCtrl.text) ?? 15,
            allergens: _selectedAllergens,
            dietaryLabels: _selectedDietaryLabels,
            imageFile: imageToUpload,
            ingredients: _ingredientDrafts,
          );
    }

    if (mounted) {
      setState(() => _isLoading = false);
      if (success) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEdit
                ? 'Menu item updated successfully!'
                : 'Menu item added successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Something went wrong, please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final mq = MediaQuery.of(context);
    final categoriesAsync =
        ref.watch(categoryNotifierProvider(widget.branchId));

    return Container(
      height: mq.size.height * 0.92,
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: colorScheme.onSurface.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _isEdit ? 'Edit Menu Item' : 'Add New Menu Item',
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Divider(height: 24),
          Expanded(
            child: SingleChildScrollView(
              padding:
                  EdgeInsets.fromLTRB(20, 0, 20, mq.viewInsets.bottom + 24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ImagePickerSection(
                      selectedImageFile: _selectedImageFile,
                      selectedImageBytes: _selectedImageBytes,
                      existingImageUrl:
                          _isEdit ? widget.existingMenu?.imageUrl : null,
                      errorText: _imageError,
                      onTap: _pickImage,
                    ),
                    const SizedBox(height: 20),

                    const _FormLabel('Menu Name'),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _nameCtrl,
                      decoration: _inputDecoration('Example: Special Fried Rice'),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Menu name cannot be empty'
                          : null,
                    ),
                    const SizedBox(height: 16),

                    const _FormLabel('Description'),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _descCtrl,
                      decoration: _inputDecoration('Short menu description...'),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 16),

                    const _FormLabel('Price (Rp)'),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _priceCtrl,
                      decoration: _inputDecoration('Example: 25000'),
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Price cannot be empty';
                        }
                        final num = double.tryParse(
                            v.replaceAll(RegExp(r'[^0-9]'), ''));
                        if (num == null || num <= 0) return 'Invalid price';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const _FormLabel('Category'),
                        TextButton.icon(
                          onPressed: () => _showAddCategoryDialog(context),
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Add',
                              style: TextStyle(fontSize: 13)),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    categoriesAsync.when(
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (e, _) => Text('Failed to load categories: $e',
                          style: const TextStyle(color: Colors.red)),
                      data: (categories) => _CategorySelector(
                        categories: categories,
                        selectedId: _selectedCategoryId,
                        onChanged: (id) =>
                            setState(() => _selectedCategoryId = id),
                        onDelete: (cat) =>
                            _confirmDeleteCategory(context, cat),
                      ),
                    ),
                    const SizedBox(height: 20),

                    const _FormLabel('Seasonal Status'),
                    const SizedBox(height: 8),
                    _SeasonalToggle(
                      value: _isSeasonal,
                      onChanged: (val) => setState(() => _isSeasonal = val),
                    ),
                    const SizedBox(height: 16),

                    const _FormLabel('Estimated Prep Time (minutes)'),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _prepTimeCtrl,
                      keyboardType: TextInputType.number,
                      decoration: _inputDecoration('Example: 15').copyWith(
                        suffixText: 'min',
                        helperText:
                            'Average time needed to prepare this menu item',
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Required';
                        final n = int.tryParse(v.trim());
                        if (n == null || n <= 0) {
                          return 'Enter a valid number';
                        }
                        if (n > 180) return 'Maximum 180 minutes';
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),

                    // ── Ingredients / Recipe ──────────────────────────────
                    _IngredientsSection(
                      branchId: widget.branchId,
                      drafts: _ingredientDrafts,
                      onAdd: (draft) =>
                          setState(() => _ingredientDrafts.add(draft)),
                      onRemove: (index) =>
                          setState(() => _ingredientDrafts.removeAt(index)),
                      onUpdateQty: (index, qty) => setState(() {
                        _ingredientDrafts[index] =
                            _ingredientDrafts[index].copyWith(quantity: qty);
                      }),
                      onToggleUnit: (index, useSecondary) => setState(() {
                        _ingredientDrafts[index] = _ingredientDrafts[index]
                            .copyWith(useSecondaryUnit: useSecondary);
                      }),
                    ),
                    const SizedBox(height: 20),

                    const _FormLabel('Allergens'),
                    const SizedBox(height: 4),
                    Text(
                      'Mark ingredients that may trigger allergies',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.5),
                          ),
                    ),
                    const SizedBox(height: 10),
                    _ChipSelector(
                      options: _allergenOptions
                          .map((e) => (e.$1, e.$2, e.$3))
                          .toList(),
                      selected: _selectedAllergens,
                      activeColor: Colors.red.shade700,
                      onToggle: (key) => setState(() {
                        _selectedAllergens.contains(key)
                            ? _selectedAllergens.remove(key)
                            : _selectedAllergens.add(key);
                      }),
                    ),
                    const SizedBox(height: 20),

                    const _FormLabel('Dietary Labels'),
                    const SizedBox(height: 4),
                    Text(
                      'Mark applicable dietary information',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.5),
                          ),
                    ),
                    const SizedBox(height: 10),
                    _ChipSelector(
                      options: _dietaryOptions
                          .map((e) => (e.$1, e.$2, e.$3))
                          .toList(),
                      selected: _selectedDietaryLabels,
                      activeColor: Colors.green.shade700,
                      onToggle: (key) => setState(() {
                        _selectedDietaryLabels.contains(key)
                            ? _selectedDietaryLabels.remove(key)
                            : _selectedDietaryLabels.add(key);
                      }),
                    ),
                    const SizedBox(height: 28),

                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _handleSubmit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colorScheme.primary,
                          foregroundColor: colorScheme.onPrimary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2.5),
                              )
                            : Text(
                                _isEdit
                                    ? 'Save Changes'
                                    : 'Add Menu Item',
                                style: const TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.w700),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: Theme.of(context)
          .colorScheme
          .surfaceContainerHighest
          .withValues(alpha: 0.5),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: Theme.of(context).colorScheme.primary,
          width: 2,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.red, width: 1.5),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }
}

// ─── INGREDIENTS SECTION ──────────────────────────────────────────────────────

class _IngredientsSection extends ConsumerStatefulWidget {
  final String branchId;
  final List<MenuIngredientDraft> drafts;
  final ValueChanged<MenuIngredientDraft> onAdd;
  final ValueChanged<int> onRemove;
  final void Function(int index, double qty) onUpdateQty;
  final void Function(int index, bool useSecondary) onToggleUnit; // ← NEW

  const _IngredientsSection({
    required this.branchId,
    required this.drafts,
    required this.onAdd,
    required this.onRemove,
    required this.onUpdateQty,
    required this.onToggleUnit, // ← NEW
  });

  @override
  ConsumerState<_IngredientsSection> createState() =>
      _IngredientsSectionState();
}

class _IngredientsSectionState extends ConsumerState<_IngredientsSection> {
  final Map<int, TextEditingController> _qtyControllers = {};

  @override
  void dispose() {
    for (final c in _qtyControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _formatQty(double qty) {
    if (qty == qty.roundToDouble()) return qty.toInt().toString();
    return qty.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  }

  Future<void> _showPickIngredientSheet(
      BuildContext context, List<InventoryItem> items) async {
    // ── FIX BUG 2 ────────────────────────────────────────────────────────────
    // Guard: if the inventory provider hasn't finished loading yet, items can
    // be empty even though data actually exists. Check the provider state first.
    // FIX BUG 3: use todayInventoryStreamProvider (not inventoryStreamProvider)
    // so this doesn't get affected by the date the user is currently browsing
    // on the Inventory screen (inventorySelectedDateProvider is global/shared).
    final inventoryState = ref.read(todayInventoryStreamProvider(widget.branchId));
    if (inventoryState is AsyncLoading) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Loading inventory data, please try again shortly...')),
      );
      return;
    }
    // ─────────────────────────────────────────────────────────────────────────

    final alreadyPicked =
        widget.drafts.map((d) => d.inventoryItemId).toSet();
    final available =
        items.where((i) => !alreadyPicked.contains(i.id)).toList();

    if (items.isEmpty) {
      // Inventory for this branch really is empty
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No inventory items in this branch yet.')),
      );
      return;
    }

    if (available.isEmpty) {
      // All items have already been picked
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            items.isEmpty
                ? 'No inventory items in this branch yet.'
                : 'All inventory items have already been added.',
      ),
    ),
  );
  return;
    }

    final picked = await showModalBottomSheet<InventoryItem>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (_, scrollCtrl) => Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Select Ingredient',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: scrollCtrl,
                itemCount: available.length,
                itemBuilder: (_, i) {
                  final item = available[i];
                  // Show secondary unit info if available
                  final unitInfo = item.hasSecondaryUnit
                      ? 'Stock: ${item.availableStock.toStringAsFixed(1)} ${item.unit}  ≈  ${item.availableStockSecondary.toStringAsFixed(0)} ${item.unitSecondary}'
                      : 'Stock: ${item.availableStock.toStringAsFixed(1)} ${item.unit}';

                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.teal.shade50,
                      child: Text(
                        item.name.isNotEmpty
                            ? item.name[0].toUpperCase()
                            : '?',
                        style: TextStyle(
                            color: Colors.teal.shade700,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                    title: Text(item.name,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(unitInfo,
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade600)),
                    // Secondary unit badge
                    trailing: item.hasSecondaryUnit
                        ? Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.teal.shade50,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.teal.shade200),
                            ),
                            child: Text(
                              '${item.unit} / ${item.unitSecondary}',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.teal.shade700,
                                  fontWeight: FontWeight.w600),
                            ),
                          )
                        : null,
                    onTap: () => Navigator.pop(context, item),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );

    if (picked != null) {
      // Default: use secondary unit if available (more intuitive for recipes)
      final useSecondary = picked.hasSecondaryUnit;
      // Default qty: 1 piece (if secondary) or 1 kg (if primary)
      final defaultQtyInPrimary =
          useSecondary ? (1.0 / picked.unitConversion) : 1.0;

      widget.onAdd(MenuIngredientDraft(
        inventoryItemId: picked.id,
        inventoryItemName: picked.name,
        unit: picked.unit,
        unitSecondary: picked.unitSecondary,
        unitConversion: picked.unitConversion,
        quantity: defaultQtyInPrimary, // always store in the primary unit
        useSecondaryUnit: useSecondary,
        costPerUnit: picked.costPerUnit,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    // FIX BUG 3: use todayInventoryStreamProvider — see the note in
    // _showPickIngredientSheet above.
    final inventoryAsync =
        ref.watch(todayInventoryStreamProvider(widget.branchId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const _FormLabel('Ingredients / Recipe'),
            // ── FIX BUG 2: correct Add Ingredient button ────────────────
            inventoryAsync.when(
              // Loading: show spinner, disable the button
              loading: () => TextButton.icon(
                onPressed: null, // disabled while loading
                icon: const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                label: const Text('Loading...', style: TextStyle(fontSize: 13)),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  visualDensity: VisualDensity.compact,
                ),
              ),
              // Error: show error icon, don't hide it
              error: (_, __) => TextButton.icon(
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Failed to load inventory. Try closing and reopening the form.'),
                    backgroundColor: Colors.red,
                  ),
                ),
                icon: const Icon(Icons.error_outline, size: 16, color: Colors.red),
                label: const Text('Failed to load', style: TextStyle(fontSize: 13, color: Colors.red)),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  visualDensity: VisualDensity.compact,
                ),
              ),
              // Data is ready: active button
              data: (items) => TextButton.icon(
                onPressed: () => _showPickIngredientSheet(context, items),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add Ingredient', style: TextStyle(fontSize: 13)),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
            // ─────────────────────────────────────────────────────────────
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Ingredients used will be automatically deducted when an order comes in',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
        const SizedBox(height: 10),

        // Empty state
        if (widget.drafts.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 18),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colorScheme.outlineVariant, width: 1),
            ),
            child: Column(
              children: [
                Icon(Icons.blender_outlined,
                    size: 32,
                    color: colorScheme.onSurface.withValues(alpha: 0.3)),
                const SizedBox(height: 6),
                Text(
                  'No ingredients added yet',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.45),
                  ),
                ),
              ],
            ),
          ),

        // Ingredients list
        ...widget.drafts.asMap().entries.map((entry) {
          final index = entry.key;
          final draft = entry.value;

          // Controller always shows displayQty (in the active unit)
          final ctrl = _qtyControllers[index] ??= TextEditingController(
            text: _formatQty(draft.displayQty),
          );

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color:
                  colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: colorScheme.outlineVariant, width: 1),
            ),
            child: Row(
              children: [
                // Avatar
                CircleAvatar(
                  radius: 18,
                  backgroundColor: Colors.teal.shade50,
                  child: Text(
                    draft.inventoryItemName.isNotEmpty
                        ? draft.inventoryItemName[0].toUpperCase()
                        : '?',
                    style: TextStyle(
                        color: Colors.teal.shade700,
                        fontWeight: FontWeight.bold,
                        fontSize: 14),
                  ),
                ),
                const SizedBox(width: 12),

                // Name + unit toggle
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        draft.inventoryItemName,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                      const SizedBox(height: 2),

                      // If a secondary unit exists → show the toggle button
                      if (draft.hasSecondaryUnit)
                        GestureDetector(
                          onTap: () {
                            final newUseSecondary = !draft.useSecondaryUnit;
                            // Update the controller text to the new unit
                            final newDisplayQty = newUseSecondary
                                ? draft.quantity * draft.unitConversion
                                : draft.quantity;
                            ctrl.text = _formatQty(newDisplayQty);
                            widget.onToggleUnit(index, newUseSecondary);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: draft.useSecondaryUnit
                                  ? Colors.teal.shade50
                                  : colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: draft.useSecondaryUnit
                                    ? Colors.teal.shade300
                                    : colorScheme.outlineVariant,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.swap_horiz,
                                    size: 11,
                                    color: draft.useSecondaryUnit
                                        ? Colors.teal.shade700
                                        : colorScheme.onSurface
                                            .withValues(alpha: 0.5)),
                                const SizedBox(width: 3),
                                Text(
                                  draft.useSecondaryUnit
                                      ? '${draft.unitSecondary}  →  tap to switch to ${draft.unit}'
                                      : '${draft.unit}  →  tap to switch to ${draft.unitSecondary}',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: draft.useSecondaryUnit
                                        ? Colors.teal.shade700
                                        : colorScheme.onSurface
                                            .withValues(alpha: 0.5),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        // No secondary unit — show the plain unit
                        Text(
                          draft.unit,
                          style: TextStyle(
                              fontSize: 11,
                              color: colorScheme.onSurface
                                  .withValues(alpha: 0.5)),
                        ),
                    ],
                  ),
                ),

                // Input qty
                SizedBox(
                  width: 72,
                  child: TextFormField(
                    controller: ctrl,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: colorScheme.surface,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide:
                            BorderSide(color: colorScheme.outlineVariant),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide:
                            BorderSide(color: colorScheme.outlineVariant),
                      ),
                    ),
                    onChanged: (v) {
                      final inputQty = double.tryParse(v);
                      if (inputQty != null && inputQty > 0) {
                        // Convert to the primary unit before saving
                        final qtyInPrimary = MenuIngredientDraft.toStorageQty(
                          inputQty: inputQty,
                          useSecondary: draft.useSecondaryUnit,
                          unitConversion: draft.unitConversion,
                        );
                        widget.onUpdateQty(index, qtyInPrimary);
                      }
                    },
                    validator: (v) {
                      final qty = double.tryParse(v ?? '');
                      if (qty == null || qty <= 0) return '!';
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 4),

                // Delete
                IconButton(
                  onPressed: () {
                    _qtyControllers.remove(index)?.dispose();
                    widget.onRemove(index);
                  },
                  icon: const Icon(Icons.close, size: 18),
                  color: Colors.red.shade400,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

// ─── SUB-WIDGETS (unchanged) ──────────────────────────────────────────────────

class _FormLabel extends StatelessWidget {
  final String text;
  const _FormLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context)
          .textTheme
          .labelLarge
          ?.copyWith(fontWeight: FontWeight.w700),
    );
  }
}

class _CategorySelector extends StatelessWidget {
  final List<MenuCategory> categories;
  final String? selectedId;
  final ValueChanged<String?> onChanged;
  final ValueChanged<MenuCategory> onDelete;

  const _CategorySelector({
    required this.categories,
    required this.selectedId,
    required this.onChanged,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (categories.isEmpty) {
      return const Text('No categories yet. Add a new category.',
          style: TextStyle(color: Colors.grey));
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: categories.map((cat) {
        final isSelected = selectedId == cat.id;
        return GestureDetector(
          onTap: () => onChanged(cat.id),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding:
                const EdgeInsets.only(left: 14, top: 6, bottom: 6, right: 6),
            decoration: BoxDecoration(
              color: isSelected
                  ? colorScheme.primary
                  : colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  cat.name,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: isSelected
                        ? colorScheme.onPrimary
                        : colorScheme.onSurface,
                  ),
                ),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: () => onDelete(cat),
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? colorScheme.onPrimary.withValues(alpha: 0.2)
                          : colorScheme.onSurface.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.close,
                      size: 12,
                      color: isSelected
                          ? colorScheme.onPrimary
                          : colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _ImagePickerSection extends StatelessWidget {
  final File? selectedImageFile;
  final Uint8List? selectedImageBytes;
  final String? existingImageUrl;
  final String? errorText;
  final VoidCallback onTap;

  const _ImagePickerSection({
    this.selectedImageFile,
    this.selectedImageBytes,
    this.existingImageUrl,
    this.errorText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    Widget imageContent;

    if (selectedImageBytes != null) {
      imageContent = Stack(fit: StackFit.expand, children: [
        Image.memory(selectedImageBytes!, fit: BoxFit.cover),
        const Positioned(bottom: 8, right: 8, child: _EditBadge()),
      ]);
    } else if (selectedImageFile != null) {
      imageContent = Stack(fit: StackFit.expand, children: [
        Image.file(selectedImageFile!, fit: BoxFit.cover),
        const Positioned(bottom: 8, right: 8, child: _EditBadge()),
      ]);
    } else if (existingImageUrl != null && existingImageUrl!.isNotEmpty) {
      imageContent = Stack(fit: StackFit.expand, children: [
        Image.network(existingImageUrl!, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const _EmptyImagePlaceholder()),
        const Positioned(bottom: 8, right: 8, child: _EditBadge()),
      ]);
    } else {
      imageContent = const _EmptyImagePlaceholder();
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 160,
        width: double.infinity,
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: errorText != null
                ? Colors.red
                : colorScheme.outline.withValues(alpha: 0.3),
            width: errorText != null ? 1.5 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: imageContent,
      ),
    );
  }
}

class _EmptyImagePlaceholder extends StatelessWidget {
  const _EmptyImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.add_photo_alternate_outlined,
            size: 40,
            color: Theme.of(context)
                .colorScheme
                .primary
                .withValues(alpha: 0.7)),
        const SizedBox(height: 8),
        Text('Add Menu Photo',
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            )),
        const SizedBox(height: 4),
        Text(
          kIsWeb ? 'Tap to choose a file' : 'Tap to choose',
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context)
                .colorScheme
                .onSurface
                .withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }
}

class _EditBadge extends StatelessWidget {
  const _EditBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.edit, color: Colors.white, size: 12),
          SizedBox(width: 4),
          Text('Change', style: TextStyle(color: Colors.white, fontSize: 11)),
        ],
      ),
    );
  }
}

class _SeasonalToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SeasonalToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: value
              ? Colors.orange.withValues(alpha: 0.08)
              : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: value
                ? Colors.orange.withValues(alpha: 0.4)
                : colorScheme.outlineVariant,
            width: 1.2,
          ),
        ),
        child: Row(
          children: [
            Icon(
              value ? Icons.wb_sunny_rounded : Icons.wb_sunny_outlined,
              size: 20,
              color: value
                  ? Colors.orange
                  : colorScheme.onSurface.withValues(alpha: 0.4),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Seasonal Menu',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: value
                          ? Colors.orange.shade800
                          : colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value
                        ? 'This item is only available at certain times'
                        : 'This item is available all the time',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurface.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: Colors.orange,
              activeTrackColor: Colors.orange.withValues(alpha: 0.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChipSelector extends StatelessWidget {
  final List<(String, String, String)> options;
  final List<String> selected;
  final Color activeColor;
  final ValueChanged<String> onToggle;

  const _ChipSelector({
    required this.options,
    required this.selected,
    required this.activeColor,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((opt) {
        final key = opt.$1;
        final label = opt.$2;
        final emoji = opt.$3;
        final isSelected = selected.contains(key);

        return GestureDetector(
          onTap: () => onToggle(key),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: isSelected
                  ? activeColor.withValues(alpha: 0.1)
                  : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isSelected
                    ? activeColor.withValues(alpha: 0.5)
                    : colorScheme.outlineVariant,
                width: 1.2,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(emoji, style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight:
                        isSelected ? FontWeight.w700 : FontWeight.w500,
                    color:
                        isSelected ? activeColor : colorScheme.onSurface,
                  ),
                ),
                if (isSelected) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.check_circle, size: 14, color: activeColor),
                ],
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}