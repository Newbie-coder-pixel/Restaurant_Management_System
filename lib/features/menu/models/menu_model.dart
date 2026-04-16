// lib/features/menu/models/menu_model.dart

enum MenuCategory { food, drinks, dessert, snack }

enum MenuStatus { available, outOfStock, seasonal }

class Menu {
  final String id;
  final String name;
  final String description;
  final double price;
  final String? imageUrl;
  final MenuCategory category;
  final bool isAvailable;
  final MenuStatus status;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Menu({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    this.imageUrl,
    required this.category,
    required this.isAvailable,
    this.status = MenuStatus.available,
    this.createdAt,
    this.updatedAt,
  });

  factory Menu.fromMap(Map<String, dynamic> map) {
    return Menu(
      id: map['id'] as String,
      name: map['name'] as String,
      description: map['description'] as String? ?? '',
      price: (map['price'] as num).toDouble(),
      imageUrl: map['image_url'] as String?,
      category: MenuCategory.values.firstWhere(
        (e) => e.name == (map['category'] as String? ?? 'food'),
        orElse: () => MenuCategory.food,
      ),
      isAvailable: map['is_available'] as bool? ?? true,
      status: MenuStatus.values.firstWhere(
        (e) => e.name == (map['status'] as String? ?? 'available'),
        orElse: () => MenuStatus.available,
      ),
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String)
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'price': price,
      'image_url': imageUrl,
      'category': category.name,
      'is_available': isAvailable,
      'status': status.name,
    };
  }

  Map<String, dynamic> toInsertMap() {
    return {
      'name': name,
      'description': description,
      'price': price,
      'image_url': imageUrl,
      'category': category.name,
      'is_available': isAvailable,
      'status': status.name,
    };
  }

  Menu copyWith({
    String? id,
    String? name,
    String? description,
    double? price,
    String? imageUrl,
    MenuCategory? category,
    bool? isAvailable,
    MenuStatus? status,
  }) {
    return Menu(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      price: price ?? this.price,
      imageUrl: imageUrl ?? this.imageUrl,
      category: category ?? this.category,
      isAvailable: isAvailable ?? this.isAvailable,
      status: status ?? this.status,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  @override
  String toString() =>
      'Menu(id: $id, name: $name, price: $price, isAvailable: $isAvailable)';
} 
