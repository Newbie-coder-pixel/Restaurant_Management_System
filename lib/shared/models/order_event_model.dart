// lib/shared/models/order_event_model.dart
//
// Mirrors a row in the `order_events` table (see
// supabase/migrations/20260808000000_order_events_notification_system.sql).
// Written exclusively by DB triggers on `orders` — never inserted from the
// client — so this model is read-only (fromJson only, no toJson).

enum OrderEventType {
  statusChanged,
  paymentStatusChanged,
  billRequested,
  cancelled,
}

OrderEventType _eventTypeFromString(String s) {
  switch (s) {
    case 'status_changed':
      return OrderEventType.statusChanged;
    case 'payment_status_changed':
      return OrderEventType.paymentStatusChanged;
    case 'bill_requested':
      return OrderEventType.billRequested;
    case 'cancelled':
      return OrderEventType.cancelled;
    default:
      return OrderEventType.statusChanged;
  }
}

class OrderEvent {
  final String id;
  final String orderId;
  final String branchId;
  final String? customerUserId;
  final String? deviceId;
  final OrderEventType eventType;
  final String? oldValue;
  final String? newValue;
  final String orderNumber;
  final String? tableName;
  final DateTime createdAt;

  const OrderEvent({
    required this.id,
    required this.orderId,
    required this.branchId,
    this.customerUserId,
    this.deviceId,
    required this.eventType,
    this.oldValue,
    this.newValue,
    required this.orderNumber,
    this.tableName,
    required this.createdAt,
  });

  factory OrderEvent.fromJson(Map<String, dynamic> j) {
    final createdAtRaw = j['created_at'] as String?;
    return OrderEvent(
      id: j['id'] ?? '',
      orderId: j['order_id'] ?? '',
      branchId: j['branch_id'] ?? '',
      customerUserId: j['customer_user_id'] as String?,
      deviceId: j['device_id'] as String?,
      eventType: _eventTypeFromString(j['event_type'] ?? 'status_changed'),
      oldValue: j['old_value'] as String?,
      newValue: j['new_value'] as String?,
      orderNumber: j['order_number'] ?? '',
      tableName: j['table_name_snapshot'] as String?,
      createdAt: createdAtRaw != null
          ? DateTime.tryParse(createdAtRaw) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  /// Short human-readable summary for banners/bell list — never includes
  /// another order's data (each event row is already scoped to one order).
  String get message {
    switch (eventType) {
      case OrderEventType.statusChanged:
        if (oldValue == null) {
          return 'New order $orderNumber${tableName != null ? ' — $tableName' : ''}';
        }
        return 'Order $orderNumber is now "${newValue ?? ''}"';
      case OrderEventType.paymentStatusChanged:
        return 'Order $orderNumber payment is now "${newValue ?? ''}"';
      case OrderEventType.billRequested:
        return 'Order $orderNumber requested the bill${tableName != null ? ' — $tableName' : ''}';
      case OrderEventType.cancelled:
        return 'Order $orderNumber was cancelled';
    }
  }
}
