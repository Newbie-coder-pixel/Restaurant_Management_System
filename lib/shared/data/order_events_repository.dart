// lib/shared/data/order_events_repository.dart
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/order_event_model.dart';

/// Realtime access to `order_events`. Modeled on
/// QrOrderRepository.watchOrder() (lib/features/qr_order/data/
/// qr_order_repository.dart) but — unlike orders/watchOrder(), which
/// re-fetches the full row on every change for PII-safety reasons —
/// order_events carries no PII, so each stream emits the new row straight
/// from the realtime payload with no follow-up query.
class OrderEventsRepository {
  final SupabaseClient _client;
  OrderEventsRepository(this._client);

  /// Live feed of events for one order (customer/QR trackers).
  Stream<OrderEvent> watchOrderEvents(String orderId) {
    late StreamController<OrderEvent> controller;
    RealtimeChannel? channel;

    controller = StreamController<OrderEvent>(
      onListen: () {
        channel = _client
            .channel('order_events_order_$orderId')
            .onPostgresChanges(
              event: PostgresChangeEvent.insert,
              schema: 'public',
              table: 'order_events',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'order_id',
                value: orderId,
              ),
              callback: (payload) {
                if (controller.isClosed) return;
                try {
                  controller.add(OrderEvent.fromJson(payload.newRecord));
                } catch (e) {
                  controller.addError(e);
                }
              },
            )
            .subscribe();
      },
      onCancel: () async {
        if (channel != null) await _client.removeChannel(channel!);
      },
    );

    return controller.stream;
  }

  /// Live feed of events for a whole branch (staff overlay/KDS banner/bell).
  Stream<OrderEvent> watchBranchEvents(String branchId) {
    late StreamController<OrderEvent> controller;
    RealtimeChannel? channel;

    controller = StreamController<OrderEvent>(
      onListen: () {
        channel = _client
            .channel('order_events_branch_$branchId')
            .onPostgresChanges(
              event: PostgresChangeEvent.insert,
              schema: 'public',
              table: 'order_events',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'branch_id',
                value: branchId,
              ),
              callback: (payload) {
                if (controller.isClosed) return;
                try {
                  controller.add(OrderEvent.fromJson(payload.newRecord));
                } catch (e) {
                  controller.addError(e);
                }
              },
            )
            .subscribe();
      },
      onCancel: () async {
        if (channel != null) await _client.removeChannel(channel!);
      },
    );

    return controller.stream;
  }
}
