// lib/shared/models/staff_notification.dart
//
// Common shape the notification bell and OrderNotificationOverlay render,
// regardless of which underlying table produced it — order_events (order
// lifecycle) or table_events (a QR customer tapping "Notify Staff" on a
// table that's still being cleaned/reserved). Keeps those two widgets from
// needing to know about two different source models.

import '../../core/models/staff_role.dart';
import '../../core/services/order_sound_service.dart';
import 'order_event_model.dart';
import 'table_event_model.dart';

enum StaffNotificationKind { order, table }

class StaffNotification {
  final String id;
  final StaffNotificationKind kind;
  final String message;
  final String category; // matches StaffRole.accessFeatures entries
  final String categoryLabel;
  final DateTime createdAt;
  final NotificationSound sound;

  // kind == order only — used for icon selection and tap-through routing.
  final OrderEventType? orderEventType;
  final bool isNewOrder;
  final String? orderId;
  final String? orderNumber;

  const StaffNotification({
    required this.id,
    required this.kind,
    required this.message,
    required this.category,
    required this.categoryLabel,
    required this.createdAt,
    required this.sound,
    this.orderEventType,
    this.isNewOrder = false,
    this.orderId,
    this.orderNumber,
  });

  factory StaffNotification.fromOrderEvent(OrderEvent e) {
    // billRequested keeps the 'Cashier & Payment' category (so cashier-role
    // access gating stays the same) but gets its own chime, distinct from a
    // completed-payment chime — a cashier needs to tell "customer wants the
    // bill" and "payment just went through" apart by ear.
    final sound = e.eventType == OrderEventType.billRequested
        ? NotificationSound.billRequested
        : switch (e.category) {
            'Kitchen (KDS)' => NotificationSound.kitchen,
            'Cashier & Payment' => NotificationSound.payment,
            _ => NotificationSound.service,
          };
    return StaffNotification(
      id: e.id,
      kind: StaffNotificationKind.order,
      message: e.message,
      category: e.category,
      categoryLabel: e.categoryLabel,
      createdAt: e.createdAt,
      sound: sound,
      orderEventType: e.eventType,
      isNewOrder: e.eventType == OrderEventType.statusChanged && e.oldValue == null,
      orderId: e.orderId,
      orderNumber: e.orderNumber,
    );
  }

  factory StaffNotification.fromTableEvent(TableEvent e) {
    return StaffNotification(
      id: e.id,
      kind: StaffNotificationKind.table,
      message: 'Table ${e.tableNumber} needs staff attention',
      category: 'Table Management',
      categoryLabel: 'Table',
      createdAt: e.createdAt,
      sound: NotificationSound.table,
    );
  }

  /// Whether [role] has access to the feature this notification belongs to
  /// — same feature-string vocabulary the router's route guard uses (see
  /// _roleCanAccessRoute in app_router.dart). superadmin's accessFeatures
  /// already lists every feature, so it always passes.
  bool isRelevantToRole(StaffRole role) => role.accessFeatures.contains(category);
}
