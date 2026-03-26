class InventoryItem {
  final String id;
  final String branchId;
  final String name;
  final String unit;
  final double currentStock;
  final double minimumStock;
  final double costPerUnit;
  final String? supplierName;
  final String? supplierContact;
  final String? category;

  bool get isLowStock => currentStock <= minimumStock;

  const InventoryItem({
    required this.id, required this.branchId, required this.name,
    required this.unit, required this.currentStock, required this.minimumStock,
    required this.costPerUnit, this.supplierName, this.supplierContact, this.category,
  });

  factory InventoryItem.fromJson(Map<String, dynamic> j) => InventoryItem(
    id: j['id'], branchId: j['branch_id'], name: j['name'], unit: j['unit'],
    currentStock: (j['current_stock'] ?? 0).toDouble(),
    minimumStock: (j['minimum_stock'] ?? 0).toDouble(),
    costPerUnit: (j['cost_per_unit'] ?? 0).toDouble(),
    supplierName: j['supplier_name'], supplierContact: j['supplier_contact'],
    category: j['category'],
  );
}