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

/// Satu bahan/ingredient yang dipakai untuk membuat satu menu item.
/// Tersimpan di tabel `menu_ingredients` di Supabase.
///
/// Relasi:
///   menu_ingredients.menu_item_id  → menu_items.id
///   menu_ingredients.inventory_item_id → inventory_items.id
class MenuIngredient {
  final String id;
  final String menuItemId;       // FK ke menu_items
  final String inventoryItemId;  // FK ke inventory_items
  final String inventoryItemName; // denormalized, untuk display tanpa join
  final String unit;             // satuan (ikut inventory_item)
  final double quantity;         // takaran per 1 porsi menu

  const MenuIngredient({
    required this.id,
    required this.menuItemId,
    required this.inventoryItemId,
    required this.inventoryItemName,
    required this.unit,
    required this.quantity,
  });

  factory MenuIngredient.fromJson(Map<String, dynamic> j) => MenuIngredient(
        id: j['id'] as String,
        menuItemId: j['menu_item_id'] as String,
        inventoryItemId: j['inventory_item_id'] as String,
        inventoryItemName: j['inventory_item_name'] as String? ?? '',
        unit: j['unit'] as String? ?? 'pcs',
        quantity: (j['quantity'] as num).toDouble(),
      );

  Map<String, dynamic> toInsertMap() => {
        'menu_item_id': menuItemId,
        'inventory_item_id': inventoryItemId,
        'inventory_item_name': inventoryItemName,
        'unit': unit,
        'quantity': quantity,
      };

  MenuIngredient copyWith({
    String? id,
    String? menuItemId,
    String? inventoryItemId,
    String? inventoryItemName,
    String? unit,
    double? quantity,
  }) =>
      MenuIngredient(
        id: id ?? this.id,
        menuItemId: menuItemId ?? this.menuItemId,
        inventoryItemId: inventoryItemId ?? this.inventoryItemId,
        inventoryItemName: inventoryItemName ?? this.inventoryItemName,
        unit: unit ?? this.unit,
        quantity: quantity ?? this.quantity,
      );
}

/// Digunakan sementara di form sebelum disimpan ke DB
/// (belum punya id dan menuItemId).
class MenuIngredientDraft {
  final String inventoryItemId;
  final String inventoryItemName;
  final String unit;
  final double quantity;

  const MenuIngredientDraft({
    required this.inventoryItemId,
    required this.inventoryItemName,
    required this.unit,
    required this.quantity,
  });

  /// Konversi ke MenuIngredient penuh setelah menu berhasil disimpan
  /// dan mendapat [menuItemId] dari DB.
  MenuIngredient toIngredient({required String menuItemId}) => MenuIngredient(
        id: '',           // akan diisi oleh DB (UUID auto-generated)
        menuItemId: menuItemId,
        inventoryItemId: inventoryItemId,
        inventoryItemName: inventoryItemName,
        unit: unit,
        quantity: quantity,
      );

  MenuIngredientDraft copyWith({double? quantity}) => MenuIngredientDraft(
        inventoryItemId: inventoryItemId,
        inventoryItemName: inventoryItemName,
        unit: unit,
        quantity: quantity ?? this.quantity,
      );
}