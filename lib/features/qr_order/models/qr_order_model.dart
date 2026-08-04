import 'package:flutter/foundation.dart';

enum QrOrderStatus {
  created,
  preparing,
  ready,
  served,
  paid,
  cancelled;

  String get label {
    switch (this) {
      case QrOrderStatus.created:   return 'Order Received';
      case QrOrderStatus.preparing: return 'Being Cooked';
      case QrOrderStatus.ready:     return 'Ready to Serve';
      case QrOrderStatus.served:    return 'Now Dining';
      case QrOrderStatus.paid:      return 'Completed & Paid';
      case QrOrderStatus.cancelled: return 'Cancelled';
    }
  }

  String get emoji {
    switch (this) {
      case QrOrderStatus.created:   return '🆕';
      case QrOrderStatus.preparing: return '👨‍🍳';
      case QrOrderStatus.ready:     return '🍽️';
      case QrOrderStatus.served:    return '😋';
      case QrOrderStatus.paid:      return '✅';
      case QrOrderStatus.cancelled: return '❌';
    }
  }

  int get stepIndex {
    switch (this) {
      case QrOrderStatus.created:   return 0;
      case QrOrderStatus.preparing: return 1;
      case QrOrderStatus.ready:     return 2;
      case QrOrderStatus.served:    return 3;
      case QrOrderStatus.paid:      return 4;
      case QrOrderStatus.cancelled: return -1;
    }
  }

  double get progress {
    switch (this) {
      case QrOrderStatus.created:   return 0.0;
      case QrOrderStatus.preparing: return 0.25;
      case QrOrderStatus.ready:     return 0.50;
      case QrOrderStatus.served:    return 0.75;
      case QrOrderStatus.paid:      return 1.0;
      case QrOrderStatus.cancelled: return 0.0;
    }
  }

  String get dbValue => name;
}

enum QrPaymentStatus {
  pending,
  paid,
  refunded,
  partial;

  String get dbValue => name;
}

@immutable
class QrOrderItemModel {
  final String menuItemId;
  final String menuItemName;
  final double price;
  final int quantity;
  final String? notes;
  final String? imageUrl;

  const QrOrderItemModel({
    required this.menuItemId,
    required this.menuItemName,
    required this.price,
    required this.quantity,
    this.notes,
    this.imageUrl,
  });

  double get subtotal => price * quantity;

  factory QrOrderItemModel.fromMap(Map<String, dynamic> map) => QrOrderItemModel(
        menuItemId: map['menu_item_id'] as String,
        menuItemName: map['menu_item_name'] as String,
        price: ((map['unit_price'] ?? map['price']) as num).toDouble(),
        quantity: map['quantity'] as int,
        notes: (map['special_requests'] ?? map['notes']) as String?,
        imageUrl: map['image_url'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'menu_item_id': menuItemId,
        'menu_item_name': menuItemName,
        'price': price,
        'quantity': quantity,
        if (notes != null) 'notes': notes,
        if (imageUrl != null) 'image_url': imageUrl,
      };
}

@immutable
class QrOrderModel {
  final String id;
  final String orderNumber;
  // Nullable: queue_number/table_name/payment_method are only ever populated
  // by the QR self-order insert path (qr_order_repository.createOrder). A
  // dine-in order created by staff via the cashier's order module
  // (menu_item_selector.dart) shares the same `orders` table and the same
  // table_id space — so fetchActiveOrderForTable can and does return staff
  // rows here too — but never sets these three columns. Forcing them
  // non-null used to throw on the cast, silently discarded by
  // AsyncValue.valueOrNull in qr_menu_screen.dart's ref.listen, which made
  // the "this table already has an order" guard invisible for exactly the
  // orders it most needed to catch: a table already occupied via the staff
  // app looked "free" to a customer scanning that table's QR code.
  final String? queueNumber;
  final String tableId;
  final String? tableName;
  final String customerName;
  final List<QrOrderItemModel> items;
  final double totalAmountFromDb; // store the DB value but don't use it directly
  final QrOrderStatus status;
  final QrPaymentStatus paymentStatus;
  final String? paymentMethod;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? branchId;
  final String? notes;
  final bool billRequested;
  final DateTime? billRequestedAt;
  final String? deviceId;

  const QrOrderModel({
    required this.id,
    required this.orderNumber,
    this.queueNumber,
    required this.tableId,
    this.tableName,
    required this.customerName,
    required this.items,
    required this.totalAmountFromDb,
    required this.status,
    required this.paymentStatus,
    this.paymentMethod,
    required this.createdAt,
    this.updatedAt,
    this.branchId,
    this.notes,
    this.billRequested = false,
    this.billRequestedAt,
    this.deviceId,
  });

  // ── Correct calculation ──────────────────────────────────────────
  double get subtotal {
    if (items.isEmpty) return 0.0;
    final computed = items.fold(0.0, (sum, i) => sum + i.subtotal);
    // Guard: if all items have price=0, data is corrupt → return 0
    return computed;
  }

  double get serviceCharge => subtotal * 0.03;
  double get pb1Amount => (subtotal + serviceCharge) * 0.10;

  /// Correct total:
  /// 1. If items exist AND subtotal > 0 → compute from items
  /// 2. Fallback to totalAmountFromDb (already includes tax when saved)
  double get totalAmount {
    if (items.isNotEmpty && subtotal > 0) {
      return subtotal + serviceCharge + pb1Amount;
    }
    // totalAmountFromDb was already stored with tax in createOrder()
    return totalAmountFromDb;
  }

  factory QrOrderModel.fromMap(Map<String, dynamic> map) => QrOrderModel(
        id: map['id'] as String,
        orderNumber: map['order_number'] as String,
        queueNumber: map['queue_number'] as String?,
        tableId: map['table_id'] as String,
        tableName: map['table_name'] as String?,
        customerName: map['customer_name'] as String? ?? 'Guest',
        items: ((map['items'] ?? map['order_items']) as List<dynamic>? ?? [])
            .map((e) => QrOrderItemModel.fromMap(e as Map<String, dynamic>))
            .toList(),
        totalAmountFromDb: (map['total_amount'] as num).toDouble(),
        status: QrOrderStatus.values.firstWhere(
          (s) => s.name.toLowerCase() == (map['status'] as String).toLowerCase(),
          orElse: () => QrOrderStatus.created,
        ),
        paymentStatus: () {
          final raw = (map['payment_status'] as String? ?? 'pending').toLowerCase();
          if (raw == 'unpaid') return QrPaymentStatus.pending;
          return QrPaymentStatus.values.firstWhere(
            (s) => s.name.toLowerCase() == raw,
            orElse: () => QrPaymentStatus.pending,
          );
        }(),
        paymentMethod: map['payment_method'] as String?,
        createdAt: DateTime.parse(map['created_at'] as String),
        updatedAt: map['updated_at'] != null
            ? DateTime.parse(map['updated_at'] as String)
            : null,
        branchId: map['branch_id'] as String?,
        notes: map['notes'] as String?,
        billRequested: (map['bill_requested'] as bool?) ?? false,
        billRequestedAt: map['bill_requested_at'] != null
            ? DateTime.tryParse(map['bill_requested_at'] as String)
            : null,
        deviceId: map['device_id'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'order_number': orderNumber,
        if (queueNumber != null) 'queue_number': queueNumber,
        'table_id': tableId,
        if (tableName != null) 'table_name': tableName,
        'customer_name': customerName,
        'items': items.map((i) => i.toMap()).toList(),
        'total_amount': totalAmount,
        'status': status.dbValue,
        'payment_status': paymentStatus.dbValue,
        if (paymentMethod != null) 'payment_method': paymentMethod,
        'created_at': createdAt.toIso8601String(),
        if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
        if (branchId != null) 'branch_id': branchId,
        if (notes != null) 'notes': notes,
        'bill_requested': billRequested,
        if (billRequestedAt != null)
          'bill_requested_at': billRequestedAt!.toIso8601String(),
        if (deviceId != null) 'device_id': deviceId,
      };

  QrOrderModel copyWith({
    QrOrderStatus? status,
    QrPaymentStatus? paymentStatus,
    DateTime? updatedAt,
    bool? billRequested,
    DateTime? billRequestedAt,
  }) =>
      QrOrderModel(
        id: id,
        orderNumber: orderNumber,
        queueNumber: queueNumber,
        tableId: tableId,
        tableName: tableName,
        customerName: customerName,
        items: items,
        totalAmountFromDb: totalAmountFromDb,
        status: status ?? this.status,
        paymentStatus: paymentStatus ?? this.paymentStatus,
        paymentMethod: paymentMethod,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        branchId: branchId,
        notes: notes,
        billRequested: billRequested ?? this.billRequested,
        billRequestedAt: billRequestedAt ?? this.billRequestedAt,
      );

  bool get isActive =>
      status != QrOrderStatus.paid && status != QrOrderStatus.cancelled;
}