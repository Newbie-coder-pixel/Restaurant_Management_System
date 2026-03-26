class MenuCategory {
  final String id;
  final String branchId;
  final String name;
  final String? description;
  final String? imageUrl;
  final int sortOrder;
  final bool isActive;

  const MenuCategory({
    required this.id, required this.branchId, required this.name,
    this.description, this.imageUrl, required this.sortOrder, required this.isActive,
  });

  factory MenuCategory.fromJson(Map<String, dynamic> j) => MenuCategory(
    id: j['id'], branchId: j['branch_id'], name: j['name'],
    description: j['description'], imageUrl: j['image_url'],
    sortOrder: j['sort_order'] ?? 0, isActive: j['is_active'] ?? true,
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

  const MenuItem({
    required this.id, required this.branchId, this.categoryId,
    required this.name, this.description, required this.price,
    this.imageUrl, required this.isAvailable, required this.isSeasonal,
    required this.preparationTimeMinutes,
  });

  factory MenuItem.fromJson(Map<String, dynamic> j) => MenuItem(
    id: j['id'], branchId: j['branch_id'], categoryId: j['category_id'],
    name: j['name'], description: j['description'],
    price: (j['price'] ?? 0).toDouble(), imageUrl: j['image_url'],
    isAvailable: j['is_available'] ?? true, isSeasonal: j['is_seasonal'] ?? false,
    preparationTimeMinutes: j['preparation_time_minutes'] ?? 15,
  );
}