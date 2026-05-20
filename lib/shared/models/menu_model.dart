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

/// Digunakan sementara di form sebelum disimpan ke DB.
/// Mendukung input dalam satuan sekunder (butir, ml, dll).
///
/// Contoh: Telur — unit=kg, unitSecondary=butir, unitConversion=6
///   → staff input "2 butir" → disimpan quantity=0.333 kg di DB
class MenuIngredientDraft {
  final String inventoryItemId;
  final String inventoryItemName;

  /// Satuan utama dari inventory (kg, liter, pcs, dll)
  final String unit;

  /// Satuan sekunder jika ada (butir, ml, lembar, dll) — nullable
  final String? unitSecondary;

  /// Berapa satuan kecil dalam 1 satuan utama. Contoh: 1 kg = 6 butir → 6.0
  final double unitConversion;

  /// Quantity selalu disimpan dalam satuan UTAMA (kg, liter).
  /// Konversi dilakukan saat user input dalam satuan sekunder.
  final double quantity;

  /// True = user sedang input/lihat dalam satuan sekunder (butir, ml).
  /// False = user input dalam satuan utama (kg, liter).
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

  /// Apakah item ini punya satuan sekunder yang valid
  bool get hasSecondaryUnit =>
      unitSecondary != null &&
      unitSecondary!.isNotEmpty &&
      unitConversion > 1;

  /// Qty yang ditampilkan ke user (dalam satuan yang sedang aktif)
  double get displayQty =>
      useSecondaryUnit && hasSecondaryUnit ? quantity * unitConversion : quantity;

  /// Label satuan yang ditampilkan ke user
  String get displayUnit =>
      useSecondaryUnit && hasSecondaryUnit ? unitSecondary! : unit;

  /// Konversi qty dari tampilan user → satuan utama untuk disimpan ke DB
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
        quantity: quantity, // sudah dalam satuan utama
        costPerUnit: costPerUnit,
      );
}