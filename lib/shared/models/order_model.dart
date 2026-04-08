enum OrderStatus { new_, created, preparing, ready, served, cancelled, paid }

enum OrderSource { dineIn, online, takeaway }

enum OrderItemStatus { pending, preparing, ready, served, cancelled }

extension OrderStatusExt on OrderStatus {
  String get label {
    switch (this) {
      case OrderStatus.new_:      return 'Baru (Internal)';
      case OrderStatus.created:   return 'Baru (QR)';
      case OrderStatus.preparing: return 'Dimasak';
      case OrderStatus.ready:     return 'Siap';
      case OrderStatus.served:    return 'Disajikan';
      case OrderStatus.cancelled: return 'Dibatalkan';
      case OrderStatus.paid:      return 'Lunas';
    }
  }

  /// Nilai yang benar-benar disimpan ke database
  String get dbValue {
    switch (this) {
      case OrderStatus.new_:    return 'new';
      case OrderStatus.created: return 'created';
      default:                  return name; // preparing, ready, dll.
    }
  }

  static OrderStatus fromString(String s) {
    final lower = s.toLowerCase().trim();
    switch (lower) {
      case 'new':       return OrderStatus.new_;
      case 'created':   return OrderStatus.created;
      case 'preparing': return OrderStatus.preparing;
      case 'ready':     return OrderStatus.ready;
      case 'served':    return OrderStatus.served;
      case 'paid':      return OrderStatus.paid;
      case 'cancelled': return OrderStatus.cancelled;
      default:          return OrderStatus.new_;
    }
  }
}

OrderSource _orderSourceFromString(String s) {
  const map = {
    'dine_in': OrderSource.dineIn,
    'dineIn': OrderSource.dineIn,
    'online': OrderSource.online,
    'takeaway': OrderSource.takeaway,
  };
  return map[s.toLowerCase()] ?? OrderSource.dineIn;
}

// ==================== ORDER ITEM ====================
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
    required this.id,
    required this.orderId,
    required this.menuItemId,
    required this.menuItemName,
    required this.quantity,
    required this.unitPrice,
    required this.subtotal,
    required this.status,
    this.specialRequests,
    this.sentToKitchenAt,
  });

  factory OrderItem.fromJson(Map<String, dynamic> j) => OrderItem(
        id: j['id'] ?? '',
        orderId: j['order_id'] ?? '',
        menuItemId: j['menu_item_id'] ?? '',
        menuItemName: j['menu_item_name'] ?? j['menu_items']?['name'] ?? '',
        quantity: j['quantity'] ?? 1,
        unitPrice: (j['unit_price'] ?? 0).toDouble(),
        subtotal: (j['subtotal'] ?? 0).toDouble(),
        status: OrderItemStatus.values.firstWhere(
          (e) => e.name == (j['status'] ?? 'pending'),
          orElse: () => OrderItemStatus.pending,
        ),
        specialRequests: j['special_requests'] ?? j['notes'],
        sentToKitchenAt: j['sent_to_kitchen_at'] != null
            ? DateTime.parse(j['sent_to_kitchen_at'])
            : null,
      );
}

// ==================== ORDER MODEL ====================
class OrderModel {
  final String id;
  final String branchId;
  final String? tableId;
  final String? tableNumber;
  final String orderNumber;
  final OrderStatus status;
  final OrderSource source;
  final String? orderType; 
  final String? customerName;
  final double discountAmount;
  final String? notes;
  final List<OrderItem> items;
  final DateTime createdAt;

  // Field yang dihitung otomatis dari items
  double get subtotal => items.fold(0.0, (sum, item) => sum + item.subtotal);
  double get taxAmount => subtotal * 0.11; // PPN 11%
  double get totalAmount => subtotal + taxAmount - discountAmount;

  const OrderModel({
    required this.id,
    required this.branchId,
    this.tableId,
    this.tableNumber,
    required this.orderNumber,
    required this.status,
    required this.source,
    this.orderType, 
    this.customerName,
    this.discountAmount = 0.0,
    this.notes,
    this.items = const [],
    required this.createdAt,
  });

  factory OrderModel.fromJson(Map<String, dynamic> j) {
    final itemsList = j['order_items'] != null
        ? (j['order_items'] as List)
            .map((i) => OrderItem.fromJson(i as Map<String, dynamic>))
            .toList()
        : <OrderItem>[];

    return OrderModel(
      id: j['id'] ?? '',
      branchId: j['branch_id'] ?? '',
      tableId: j['table_id'],
      tableNumber: j['restaurant_tables']?['table_number'],
      orderNumber: j['order_number'] ?? j['queue_number'] ?? 'UNKNOWN',
      status: OrderStatusExt.fromString(j['status'] ?? 'created'),
      source: _orderSourceFromString(j['source'] ?? 'dine_in'),
      orderType: j['order_type'] as String?, 
      customerName: j['customer_name'],
      discountAmount: (j['discount_amount'] ?? 0).toDouble(),
      notes: j['notes'],
      items: itemsList,
      createdAt: DateTime.parse(j['created_at'] ?? DateTime.now().toIso8601String()),
    );
  }
}