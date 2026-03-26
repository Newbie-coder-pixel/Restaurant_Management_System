enum OrderStatus { new_, preparing, ready, served, cancelled, paid }
enum OrderSource { dineIn, online, takeaway }
enum OrderItemStatus { pending, preparing, ready, served, cancelled }

extension OrderStatusExt on OrderStatus {
  String get label {
    switch (this) {
      case OrderStatus.new_:      return 'Baru';
      case OrderStatus.preparing: return 'Dimasak';
      case OrderStatus.ready:     return 'Siap';
      case OrderStatus.served:    return 'Disajikan';
      case OrderStatus.cancelled: return 'Dibatal';
      case OrderStatus.paid:      return 'Lunas';
    }
  }
  static OrderStatus fromString(String s) {
    if (s == 'new') return OrderStatus.new_;
    return OrderStatus.values.firstWhere(
      (e) => e.name == s, orElse: () => OrderStatus.new_);
  }
}

// Map DB snake_case ke enum camelCase
OrderSource _orderSourceFromString(String s) {
  const map = {
    'dine_in':  OrderSource.dineIn,
    'dineIn':   OrderSource.dineIn,
    'online':   OrderSource.online,
    'takeaway': OrderSource.takeaway,
  };
  return map[s] ?? OrderSource.dineIn;
}

class OrderItem {
  final String id;
  final String orderId;
  final String menuItemId;
  final String menuItemName;
  final int quantity;
  final double unitPrice;
  final double subtotal;
  final OrderItemStatus status;
  final String? specialRequests;
  final DateTime? sentToKitchenAt;

  const OrderItem({
    required this.id, required this.orderId, required this.menuItemId,
    required this.menuItemName, required this.quantity, required this.unitPrice,
    required this.subtotal, required this.status,
    this.specialRequests, this.sentToKitchenAt,
  });

  factory OrderItem.fromJson(Map<String, dynamic> j) => OrderItem(
    id: j['id'], orderId: j['order_id'], menuItemId: j['menu_item_id'],
    menuItemName: j['menu_items']?['name'] ?? '',
    quantity: j['quantity'] ?? 1,
    unitPrice: (j['unit_price'] ?? 0).toDouble(),
    subtotal: (j['subtotal'] ?? 0).toDouble(),
    status: OrderItemStatus.values.firstWhere(
      (e) => e.name == (j['status'] ?? 'pending'),
      orElse: () => OrderItemStatus.pending),
    specialRequests: j['special_requests'],
    sentToKitchenAt: j['sent_to_kitchen_at'] != null
        ? DateTime.parse(j['sent_to_kitchen_at']) : null,
  );
}

class OrderModel {
  final String id;
  final String branchId;
  final String? tableId;
  final String? tableNumber;
  final String orderNumber;
  final OrderStatus status;
  final OrderSource source;
  final String? customerName;
  final double subtotal;
  final double discountAmount;
  final double taxAmount;
  final double totalAmount;
  final String? notes;
  final List<OrderItem> items;
  final DateTime createdAt;

  const OrderModel({
    required this.id, required this.branchId, this.tableId, this.tableNumber,
    required this.orderNumber, required this.status, required this.source,
    this.customerName, required this.subtotal, required this.discountAmount,
    required this.taxAmount, required this.totalAmount, this.notes,
    this.items = const [], required this.createdAt,
  });

  factory OrderModel.fromJson(Map<String, dynamic> j) => OrderModel(
    id: j['id'], branchId: j['branch_id'], tableId: j['table_id'],
    tableNumber: j['restaurant_tables']?['table_number'],
    orderNumber: j['order_number'],
    status: OrderStatusExt.fromString(j['status'] ?? 'new'),
    source: _orderSourceFromString(j['source'] ?? 'dine_in'),
    customerName: j['customer_name'],
    subtotal: (j['subtotal'] ?? 0).toDouble(),
    discountAmount: (j['discount_amount'] ?? 0).toDouble(),
    taxAmount: (j['tax_amount'] ?? 0).toDouble(),
    totalAmount: (j['total_amount'] ?? 0).toDouble(),
    notes: j['notes'],
    items: j['order_items'] != null
        ? (j['order_items'] as List).map((i) => OrderItem.fromJson(i)).toList()
        : [],
    createdAt: DateTime.parse(j['created_at']),
  );
}