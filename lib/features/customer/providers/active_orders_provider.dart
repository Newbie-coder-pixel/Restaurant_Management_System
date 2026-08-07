// lib/features/customer/providers/active_orders_provider.dart
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'customer_auth_provider.dart';

/// The customer's most recent still-in-progress order id, or null if they
/// have none — feeds OrderNotificationOverlay in customer mode so it knows
/// which order's events to watch. Multiple simultaneous open orders per
/// customer is assumed to be rare/non-primary for v1, so this surfaces only
/// the single most recent active one rather than merging several streams.
final myActiveOrderIdProvider = StreamProvider.autoDispose<String?>((ref) {
  final userId = ref.watch(
    customerUserProvider.select((async) => async.value?.id),
  );
  if (userId == null) return Stream.value(null);

  final client = Supabase.instance.client;
  late StreamController<String?> controller;
  RealtimeChannel? channel;

  Future<void> fetchAndEmit() async {
    try {
      final res = await client
          .from('orders')
          .select('id, created_at')
          .eq('customer_user_id', userId)
          .not('status', 'in', '(served,cancelled,paid)')
          .order('created_at', ascending: false)
          .limit(1);
      final list = res as List;
      if (!controller.isClosed) {
        controller.add(list.isNotEmpty ? list.first['id'] as String : null);
      }
    } catch (e) {
      if (!controller.isClosed) controller.addError(e);
    }
  }

  controller = StreamController<String?>(
    onListen: () async {
      await fetchAndEmit();
      channel = client
          .channel('customer_active_order_$userId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'orders',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'customer_user_id',
              value: userId,
            ),
            callback: (_) => fetchAndEmit(),
          )
          .subscribe();
    },
    onCancel: () async {
      if (channel != null) await client.removeChannel(channel!);
    },
  );

  ref.onDispose(() => controller.close());
  return controller.stream;
});
