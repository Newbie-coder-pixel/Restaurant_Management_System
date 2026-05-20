class InventoryItem {
  final String id;
  final String branchId;
  final String name;
  final String unit;
  final String category;
  final double openingStock;
  final double usedStock;
  final double wasteStock;
  final double purchasedStock;
  final double transferIn;
  final double transferOut;
  final double adjustmentStock;
  final double minimumStock;
  final double costPerUnit;
  final String? linkedMenuIds;
  final DateTime date;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? unitSecondary;
  final double unitConversion;

  const InventoryItem({
    required this.id,
    required this.branchId,
    required this.name,
    required this.unit,
    required this.category,
    required this.openingStock,
    required this.usedStock,
    required this.wasteStock,
    required this.purchasedStock,
    required this.transferIn,
    required this.transferOut,
    required this.adjustmentStock,
    required this.minimumStock,
    required this.costPerUnit,
    this.linkedMenuIds,
    required this.date,
    required this.createdAt,
    required this.updatedAt,
    this.unitSecondary,
    this.unitConversion = 1.0,
  });

  double get availableStockSecondary => closingStock * unitConversion;
  double get usedStockSecondary => usedStock * unitConversion;
  double get openingStockSecondary => openingStock * unitConversion;
  double get costPerUnitSecondary =>
      unitConversion > 0 ? costPerUnit / unitConversion : costPerUnit;
  bool get hasSecondaryUnit =>
      unitSecondary != null && unitSecondary!.isNotEmpty && unitConversion > 1;

  double get closingStock =>
      openingStock +
      purchasedStock +
      transferIn +
      adjustmentStock -
      usedStock -
      wasteStock -
      transferOut;

  double get availableStock => closingStock;
  bool get isLowStock => availableStock <= minimumStock && minimumStock > 0;
  bool get isOutOfStock => availableStock <= 0;
  double get totalCostUsed => usedStock * costPerUnit;
  double get totalCostPurchased => purchasedStock * costPerUnit;

  InventoryItem copyWith({
    String? id,
    String? branchId,
    String? name,
    String? unit,
    String? category,
    double? openingStock,
    double? usedStock,
    double? wasteStock,
    double? purchasedStock,
    double? transferIn,
    double? transferOut,
    double? adjustmentStock,
    double? minimumStock,
    double? costPerUnit,
    String? linkedMenuIds,
    DateTime? date,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? unitSecondary,
    double? unitConversion,
  }) {
    return InventoryItem(
      id: id ?? this.id,
      branchId: branchId ?? this.branchId,
      name: name ?? this.name,
      unit: unit ?? this.unit,
      category: category ?? this.category,
      openingStock: openingStock ?? this.openingStock,
      usedStock: usedStock ?? this.usedStock,
      wasteStock: wasteStock ?? this.wasteStock,
      purchasedStock: purchasedStock ?? this.purchasedStock,
      transferIn: transferIn ?? this.transferIn,
      transferOut: transferOut ?? this.transferOut,
      adjustmentStock: adjustmentStock ?? this.adjustmentStock,
      minimumStock: minimumStock ?? this.minimumStock,
      costPerUnit: costPerUnit ?? this.costPerUnit,
      linkedMenuIds: linkedMenuIds ?? this.linkedMenuIds,
      date: date ?? this.date,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      unitSecondary: unitSecondary ?? this.unitSecondary,
      unitConversion: unitConversion ?? this.unitConversion,
    );
  }

  factory InventoryItem.fromMap(Map<String, dynamic> map) {
    return InventoryItem(
      id: map['id'] as String,
      branchId: map['branch_id'] as String,
      name: map['name'] as String,
      unit: map['unit'] as String? ?? 'pcs',
      category: map['category'] as String? ?? 'Bahan Baku',
      openingStock: (map['opening_stock'] as num?)?.toDouble() ?? 0.0,
      usedStock: (map['used_stock'] as num?)?.toDouble() ?? 0.0,
      wasteStock: (map['waste_stock'] as num?)?.toDouble() ?? 0.0,
      purchasedStock: (map['purchased_stock'] as num?)?.toDouble() ?? 0.0,
      transferIn: (map['transfer_in'] as num?)?.toDouble() ?? 0.0,
      transferOut: (map['transfer_out'] as num?)?.toDouble() ?? 0.0,
      adjustmentStock: (map['adjustment_stock'] as num?)?.toDouble() ?? 0.0,
      minimumStock: (map['minimum_stock'] as num?)?.toDouble() ?? 0.0,
      costPerUnit: (map['cost_per_unit'] as num?)?.toDouble() ?? 0.0,
      linkedMenuIds: map['linked_menu_ids'] as String?,
      date: DateTime.parse(map['date'] as String),
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      unitSecondary: map['unit_secondary'] as String?,
      unitConversion: (map['unit_conversion'] as num?)?.toDouble() ?? 1.0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'branch_id': branchId,
      'name': name,
      'unit': unit,
      'category': category,
      'opening_stock': openingStock,
      'used_stock': usedStock,
      'waste_stock': wasteStock,
      'purchased_stock': purchasedStock,
      'transfer_in': transferIn,
      'transfer_out': transferOut,
      'adjustment_stock': adjustmentStock,
      'minimum_stock': minimumStock,
      'cost_per_unit': costPerUnit,
      'linked_menu_ids': linkedMenuIds,
      'date': date.toIso8601String().split('T').first,
      'unit_secondary': unitSecondary,
      'unit_conversion': unitConversion,
    };
  }
}

class InventoryTransaction {
  final String id;
  final String inventoryItemId;
  final String branchId;
  final String type;
  final double quantity;
  final String? note;
  final String? referenceId;
  final String? createdBy;
  final String? menuItemName;
  final DateTime createdAt;

  const InventoryTransaction({
    required this.id,
    required this.inventoryItemId,
    required this.branchId,
    required this.type,
    required this.quantity,
    this.note,
    this.referenceId,
    this.createdBy,
    this.menuItemName,
    required this.createdAt,
  });

  factory InventoryTransaction.fromMap(Map<String, dynamic> map) {
    return InventoryTransaction(
      id: map['id'] as String,
      inventoryItemId: (map['inventory_item_id'] ?? map['item_id']) as String,
      branchId: map['branch_id'] as String,
      type: (map['type'] ?? map['transaction_type']) as String,
      quantity: (map['quantity'] as num).toDouble(),
      note: (map['note'] ?? map['notes']) as String?,
      referenceId: map['reference_id'] as String?,
      createdBy: (map['created_by'] ?? map['performed_by']) as String?,
      menuItemName: map['menu_item_name'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'inventory_item_id': inventoryItemId,
      'branch_id': branchId,
      'type': type,
      'quantity': quantity,
      'note': note,
      'reference_id': referenceId,
      'created_by': createdBy,
    };
  }
}

class InventoryDailySummary {
  final String branchId;
  final DateTime date;
  final int totalItems;
  final int lowStockItems;
  final int outOfStockItems;
  final double totalInventoryValue;
  final double totalUsedValue;
  final double totalWasteValue;

  const InventoryDailySummary({
    required this.branchId,
    required this.date,
    required this.totalItems,
    required this.lowStockItems,
    required this.outOfStockItems,
    required this.totalInventoryValue,
    required this.totalUsedValue,
    required this.totalWasteValue,
  });
}