// lib/shared/providers/recent_order_events_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../models/order_event_model.dart';
import 'order_events_provider.dart';

const maxRecentOrderEvents = 30;

/// Accumulated order-event history for the staff notification bell — lives
/// at the ProviderScope root (see main.dart), not in NotificationBell's own
/// State. GoRouter tears down and rebuilds that widget on every navigation
/// (switching sidebar menu items), which previously reset a local
/// List<OrderEvent> to empty on every page change. This provider isn't
/// scoped to any one screen, so the history now only ever changes when a
/// new order_events row arrives or the staff member explicitly clears it
/// via clearAll() — never just from navigating around the app.
class RecentOrderEventsNotifier extends StateNotifier<List<OrderEvent>> {
  RecentOrderEventsNotifier() : super(const []);

  void add(OrderEvent event) {
    state = [event, ...state].take(maxRecentOrderEvents).toList();
  }

  void clearAll() => state = const [];
}

final recentOrderEventsProvider =
    StateNotifierProvider<RecentOrderEventsNotifier, List<OrderEvent>>((ref) {
  final branchId = ref.watch(currentBranchIdProvider);
  final notifier = RecentOrderEventsNotifier();
  ref.listen(orderEventsForBranchProvider(branchId), (prev, next) {
    next.whenData((event) {
      final role = ref.read(currentStaffProvider)?.role;
      // Only show events for a feature this role actually has access to —
      // e.g. a kitchen-only staff member never sees a "payment received"
      // notification, same access model as the route guard.
      if (role != null && !event.isRelevantToRole(role)) return;
      notifier.add(event);
    });
  });
  return notifier;
});
