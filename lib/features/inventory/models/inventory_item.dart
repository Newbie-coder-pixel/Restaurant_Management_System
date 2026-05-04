// lib/features/inventory/models/inventory_item.dart

class InventoryItem {
  final String id;
  final String branchId;
  final String name;
  final String unit; // kg, liter, pcs, gram, dll
  final String category; // Bahan Baku, Minuman, Packaging, dll
  final double openingStock; // stok awal hari ini
  final double usedStock; // terpakai (dari order)
  final double wasteStock; // terbuang / spoilage
  final double purchasedStock; // pembelian dari supplier
  final double transferIn; // transfer masuk dari cabang lain
  final double transferOut; // transfer keluar ke cabang lain
  final double adjustmentStock; // penyesuaian manual
  final double minimumStock; // threshold low-stock alert
  final double costPerUnit; // harga per satuan
  final String? linkedMenuIds; // JSON list of menu item IDs yang pakai bahan ini
  final DateTime date; // tanggal inventory
  final DateTime createdAt;
  final DateTime updatedAt;

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
  });

  /// Stok akhir = opening + purchased + transferIn + adjustment - used - waste - transferOut
  double get closingStock =>
      openingStock +
      purchasedStock +
      transferIn +
      adjustmentStock -
      usedStock -
      wasteStock -
      transferOut;

  /// Stok tersedia saat ini
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
    };
  }
}

/// Model untuk transaksi log inventory (audit trail)
class InventoryTransaction {
  final String id;
  final String inventoryItemId;
  final String branchId;
  final String type; // 'purchase', 'order_deduct', 'waste', 'transfer_in', 'transfer_out', 'adjustment'
  final double quantity;
  final String? note;
  final String? referenceId; // order_id, transfer_id, dll
  final String? createdBy;
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
    required this.createdAt,
  });

  factory InventoryTransaction.fromMap(Map<String, dynamic> map) {
    return InventoryTransaction(
      id: map['id'] as String,
      inventoryItemId: map['inventory_item_id'] as String,
      branchId: map['branch_id'] as String,
      type: map['type'] as String,
      quantity: (map['quantity'] as num).toDouble(),
      note: map['note'] as String?,
      referenceId: map['reference_id'] as String?,
      createdBy: map['created_by'] as String?,
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

/// Summary untuk dashboard inventory harian
class InventoryDailySummary {
  final String branchId;
  final DateTime date;
  final int totalItems;
  final int lowStockItems;
  final int outOfStockItems;
  final double totalInventoryValue; // nilai stok tersedia * cost
  final double totalUsedValue; // total bahan terpakai (COGS)
  final double totalWasteValue; // nilai terbuang

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
