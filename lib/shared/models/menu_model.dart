// lib/shared/models/menu_model.dart

class MenuCategory {
  final String id;
  final String branchId;
  final String name;
  final String? description;
  final String? imageUrl;
  final int sortOrder;
  final bool isActive;

  const MenuCategory({
    required this.id,
    required this.branchId,
    required this.name,
    this.description,
    this.imageUrl,
    required this.sortOrder,
    required this.isActive,
  });

  factory MenuCategory.fromJson(Map<String, dynamic> j) => MenuCategory(
        id: j['id'],
        branchId: j['branch_id'],
        name: j['name'],
        description: j['description'],
        imageUrl: j['image_url'],
        sortOrder: j['sort_order'] ?? 0,
        isActive: j['is_active'] ?? true,
      );
}

class MenuItem {
  final String id;
  final String branchId;
  final String? categoryId;
  final String name;
  final String? description;
  final double price;
  final String? imageUrl;
  final bool isAvailable;
  final bool isSeasonal;
  final int preparationTimeMinutes;
  final int sortOrder;
  final String? inventoryItemId;
  final List<String> allergens;
  final List<String> dietaryLabels;

  const MenuItem({
    required this.id,
    required this.branchId,
    this.categoryId,
    required this.name,
    this.description,
    required this.price,
    this.imageUrl,
    required this.isAvailable,
    required this.isSeasonal,
    required this.preparationTimeMinutes,
    this.sortOrder = 0,
    this.inventoryItemId,
    this.allergens = const [],
    this.dietaryLabels = const [],
  });

  factory MenuItem.fromJson(Map<String, dynamic> j) => MenuItem(
        id: j['id'],
        branchId: j['branch_id'],
        categoryId: j['category_id'],
        name: j['name'],
        description: j['description'],
        price: (j['price'] ?? 0).toDouble(),
        imageUrl: j['image_url'],
        isAvailable: j['is_available'] ?? true,
        isSeasonal: j['is_seasonal'] ?? false,
        preparationTimeMinutes: j['preparation_time_minutes'] ?? 15,
        sortOrder: j['sort_order'] ?? 0,
        inventoryItemId: j['inventory_item_id'],
        allergens: List<String>.from(j['allergens'] ?? []),
        dietaryLabels: List<String>.from(j['dietary_labels'] ?? []),
      );

  Map<String, dynamic> toInsertMap() => {
        'branch_id': branchId,
        'category_id': categoryId,
        'name': name,
        'description': description,
        'price': price,
        'image_url': imageUrl,
        'is_available': isAvailable,
        'is_seasonal': isSeasonal,
        'preparation_time_minutes': preparationTimeMinutes,
        'sort_order': sortOrder,
        'allergens': allergens,
        'dietary_labels': dietaryLabels,
        'updated_at': DateTime.now().toIso8601String(),
      };

  MenuItem copyWith({
    String? id,
    String? branchId,
    String? categoryId,
    String? name,
    String? description,
    double? price,
    String? imageUrl,
    bool? isAvailable,
    bool? isSeasonal,
    int? preparationTimeMinutes,
    int? sortOrder,
    String? inventoryItemId,
    List<String>? allergens,
    List<String>? dietaryLabels,
  }) =>
      MenuItem(
        id: id ?? this.id,
        branchId: branchId ?? this.branchId,
        categoryId: categoryId ?? this.categoryId,
        name: name ?? this.name,
        description: description ?? this.description,
        price: price ?? this.price,
        imageUrl: imageUrl ?? this.imageUrl,
        isAvailable: isAvailable ?? this.isAvailable,
        isSeasonal: isSeasonal ?? this.isSeasonal,
        preparationTimeMinutes:
            preparationTimeMinutes ?? this.preparationTimeMinutes,
        sortOrder: sortOrder ?? this.sortOrder,
        inventoryItemId: inventoryItemId ?? this.inventoryItemId,
        allergens: allergens ?? this.allergens,
        dietaryLabels: dietaryLabels ?? this.dietaryLabels,
      );
}

// ─── MENU INGREDIENT MODEL ────────────────────────────────────────────────────

class MenuIngredient {
  final String id;
  final String menuItemId;
  final String inventoryItemId;
  final String inventoryItemName;
  final String unit;
  final double quantity;
  final double costPerUnit;

  const MenuIngredient({
    required this.id,
    required this.menuItemId,
    required this.inventoryItemId,
    required this.inventoryItemName,
    required this.unit,
    required this.quantity,
    this.costPerUnit = 0,
  });

  factory MenuIngredient.fromJson(Map<String, dynamic> j) => MenuIngredient(
        id: j['id'] as String,
        menuItemId: j['menu_item_id'] as String,
        inventoryItemId: j['inventory_item_id'] as String,
        inventoryItemName: j['inventory_item_name'] as String? ?? '',
        unit: j['unit'] as String? ?? 'pcs',
        quantity: (j['quantity'] as num).toDouble(),
        costPerUnit: (j['cost_per_unit'] as num?)?.toDouble() ?? 0,
      );

  Map<String, dynamic> toInsertMap() => {
        'menu_item_id': menuItemId,
        'inventory_item_id': inventoryItemId,
        'inventory_item_name': inventoryItemName,
        'unit': unit,
        'quantity': quantity,
        'cost_per_unit': costPerUnit,
      };

  MenuIngredient copyWith({
    String? id,
    String? menuItemId,
    String? inventoryItemId,
    String? inventoryItemName,
    String? unit,
    double? quantity,
    double? costPerUnit,
  }) =>
      MenuIngredient(
        id: id ?? this.id,
        menuItemId: menuItemId ?? this.menuItemId,
        inventoryItemId: inventoryItemId ?? this.inventoryItemId,
        inventoryItemName: inventoryItemName ?? this.inventoryItemName,
        unit: unit ?? this.unit,
        quantity: quantity ?? this.quantity,
        costPerUnit: costPerUnit ?? this.costPerUnit,
      );
}

// ─── MENU INGREDIENT DRAFT ────────────────────────────────────────────────────

/// Used temporarily in the form before being saved to the DB.
/// Supports input in a secondary unit (piece, ml, etc.).
///
/// Example: Egg — unit=kg, unitSecondary=piece, unitConversion=6
///   → staff inputs "2 pieces" → stored as quantity=0.333 kg in the DB
class MenuIngredientDraft {
  final String inventoryItemId;
  final String inventoryItemName;

  /// Primary unit from inventory (kg, liter, pcs, etc.)
  final String unit;

  /// Secondary unit if any (piece, ml, sheet, etc.) — nullable
  final String? unitSecondary;

  /// How many small units make up 1 primary unit. Example: 1 kg = 6 pieces → 6.0
  final double unitConversion;

  /// Quantity is always stored in the PRIMARY unit (kg, liter).
  /// Conversion happens when the user inputs in the secondary unit.
  final double quantity;

  /// True = user is currently inputting/viewing in the secondary unit (piece, ml).
  /// False = user is inputting in the primary unit (kg, liter).
  final bool useSecondaryUnit;

  final double costPerUnit;

  const MenuIngredientDraft({
    required this.inventoryItemId,
    required this.inventoryItemName,
    required this.unit,
    this.unitSecondary,
    this.unitConversion = 1.0,
    required this.quantity,
    this.useSecondaryUnit = false,
    this.costPerUnit = 0,
  });

  /// Whether this item has a valid secondary unit
  bool get hasSecondaryUnit =>
      unitSecondary != null &&
      unitSecondary!.isNotEmpty &&
      unitConversion > 1;

  /// Qty shown to the user (in the currently active unit)
  double get displayQty =>
      useSecondaryUnit && hasSecondaryUnit ? quantity * unitConversion : quantity;

  /// Unit label shown to the user
  String get displayUnit =>
      useSecondaryUnit && hasSecondaryUnit ? unitSecondary! : unit;

  /// Convert qty from the user-facing display → primary unit for DB storage
  static double toStorageQty({
    required double inputQty,
    required bool useSecondary,
    required double unitConversion,
  }) {
    if (useSecondary && unitConversion > 1) {
      return inputQty / unitConversion;
    }
    return inputQty;
  }

  MenuIngredientDraft copyWith({
    double? quantity,
    bool? useSecondaryUnit,
  }) =>
      MenuIngredientDraft(
        inventoryItemId: inventoryItemId,
        inventoryItemName: inventoryItemName,
        unit: unit,
        unitSecondary: unitSecondary,
        unitConversion: unitConversion,
        quantity: quantity ?? this.quantity,
        useSecondaryUnit: useSecondaryUnit ?? this.useSecondaryUnit,
        costPerUnit: costPerUnit,
      );

  MenuIngredient toIngredient({required String menuItemId}) => MenuIngredient(
        id: '',
        menuItemId: menuItemId,
        inventoryItemId: inventoryItemId,
        inventoryItemName: inventoryItemName,
        unit: unit,
        quantity: quantity, // already in the primary unit
        costPerUnit: costPerUnit,
      );
}