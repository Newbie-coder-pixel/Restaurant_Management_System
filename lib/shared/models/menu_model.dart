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
      );
}