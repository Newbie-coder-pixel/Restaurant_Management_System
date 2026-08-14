// lib/shared/models/table_event_model.dart
//
// Mirrors a row in the `table_events` table (see
// supabase/migrations/20260814000000_table_events_customer_reported.sql).
// Written exclusively by a DB trigger on `restaurant_tables` — never
// inserted from the client — so this model is read-only (fromJson only).

class TableEvent {
  final String id;
  final String tableId;
  final String branchId;
  final String tableNumber;
  final DateTime createdAt;

  const TableEvent({
    required this.id,
    required this.tableId,
    required this.branchId,
    required this.tableNumber,
    required this.createdAt,
  });

  factory TableEvent.fromJson(Map<String, dynamic> j) {
    final createdAtRaw = j['created_at'] as String?;
    return TableEvent(
      id: j['id'] ?? '',
      tableId: j['table_id'] ?? '',
      branchId: j['branch_id'] ?? '',
      tableNumber: j['table_number'] ?? '',
      createdAt: createdAtRaw != null
          ? DateTime.tryParse(createdAtRaw) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
