// lib/shared/providers/order_events_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/order_events_repository.dart';
import '../models/order_event_model.dart';

final orderEventsRepositoryProvider = Provider<OrderEventsRepository>((ref) {
  return OrderEventsRepository(Supabase.instance.client);
});

/// Stream of individual order_events rows for one order, newest as they
/// arrive — used by customer/QR trackers and the global notification
/// overlay in those app modes. Each emission is one event (not an
/// accumulated list); consumers that need a running count/history should
/// `ref.listen` and accumulate locally.
final orderEventsForOrderProvider =
    StreamProvider.family<OrderEvent, String>((ref, orderId) {
  return ref.read(orderEventsRepositoryProvider).watchOrderEvents(orderId);
});

/// Stream of individual order_events rows for a whole branch — used by the
/// staff notification overlay, the KDS "new order" banner, and the
/// AppDrawer notification bell.
final orderEventsForBranchProvider =
    StreamProvider.family<OrderEvent, String>((ref, branchId) {
  return ref.read(orderEventsRepositoryProvider).watchBranchEvents(branchId);
});
