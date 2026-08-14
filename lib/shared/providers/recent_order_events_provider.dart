// lib/shared/providers/recent_order_events_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../models/staff_notification.dart';
import 'order_events_provider.dart';
import 'table_events_provider.dart';

const maxRecentOrderEvents = 30;

/// Accumulated notification history for the staff notification bell — lives
/// at the ProviderScope root (see main.dart), not in NotificationBell's own
/// State. GoRouter tears down and rebuilds that widget on every navigation
/// (switching sidebar menu items), which previously reset a local
/// List<OrderEvent> to empty on every page change. This provider isn't
/// scoped to any one screen, so the history now only ever changes when a
/// new order_events/table_events row arrives or the staff member
/// explicitly clears it via clearAll() — never just from navigating around
/// the app.
class RecentOrderEventsNotifier extends StateNotifier<List<StaffNotification>> {
  RecentOrderEventsNotifier() : super(const []);

  void add(StaffNotification notification) {
    state = [notification, ...state].take(maxRecentOrderEvents).toList();
  }

  void clearAll() => state = const [];
}

final recentOrderEventsProvider =
    StateNotifierProvider<RecentOrderEventsNotifier, List<StaffNotification>>(
        (ref) {
  final branchId = ref.watch(currentBranchIdProvider);
  final notifier = RecentOrderEventsNotifier();

  void addIfRelevant(StaffNotification notification) {
    final role = ref.read(currentStaffProvider)?.role;
    // Only show notifications for a feature this role actually has access
    // to — e.g. a kitchen-only staff member never sees a "payment
    // received" or "table needs attention" notification, same access
    // model as the route guard.
    if (role != null && !notification.isRelevantToRole(role)) return;
    notifier.add(notification);
  }

  ref.listen(orderEventsForBranchProvider(branchId), (prev, next) {
    next.whenData((event) => addIfRelevant(StaffNotification.fromOrderEvent(event)));
  });
  ref.listen(tableEventsForBranchProvider(branchId), (prev, next) {
    next.whenData((event) => addIfRelevant(StaffNotification.fromTableEvent(event)));
  });

  return notifier;
});
