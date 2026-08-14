// lib/shared/data/table_events_repository.dart
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/table_event_model.dart';

/// Realtime access to `table_events`. Modeled directly on
/// OrderEventsRepository.watchBranchEvents() (lib/shared/data/
/// order_events_repository.dart) — same nullable-branchId ("all branches"
/// for superadmin) pattern.
class TableEventsRepository {
  final SupabaseClient _client;
  TableEventsRepository(this._client);

  Stream<TableEvent> watchBranchEvents(String? branchId) {
    late StreamController<TableEvent> controller;
    RealtimeChannel? channel;

    controller = StreamController<TableEvent>(
      onListen: () {
        channel = _client
            .channel('table_events_branch_${branchId ?? 'all'}')
            .onPostgresChanges(
              event: PostgresChangeEvent.insert,
              schema: 'public',
              table: 'table_events',
              filter: branchId != null
                  ? PostgresChangeFilter(
                      type: PostgresChangeFilterType.eq,
                      column: 'branch_id',
                      value: branchId,
                    )
                  : null,
              callback: (payload) {
                if (controller.isClosed) return;
                try {
                  controller.add(TableEvent.fromJson(payload.newRecord));
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
