// lib/shared/providers/table_events_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/table_events_repository.dart';
import '../models/table_event_model.dart';

final tableEventsRepositoryProvider = Provider<TableEventsRepository>((ref) {
  return TableEventsRepository(Supabase.instance.client);
});

/// Stream of individual table_events rows for a branch, or every branch
/// when [branchId] is null (superadmin "All Branches") — used by the staff
/// notification bell and banner+sound overlay.
final tableEventsForBranchProvider =
    StreamProvider.family<TableEvent, String?>((ref, branchId) {
  return ref.read(tableEventsRepositoryProvider).watchBranchEvents(branchId);
});
